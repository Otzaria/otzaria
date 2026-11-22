#include "hang_monitor.h"

#include <psapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "crash_record.h"
#include "native_exception_log.h"
#include "startup_watchdog.h"

namespace hang_monitor {

namespace {

// IsHungAppWindow מחזיר true אחרי 5 שניות שה-thread לא שלף הודעות. בלי
// WM_TIMER: הצפת הודעות מרעיבה אותו ומייצרת התראות שווא.
constexpr DWORD kPollIntervalMs = 1000;
constexpr ULONGLONG kHungThresholdMs = 5000;
constexpr int kRequiredHungPolls = 2;
constexpr ULONGLONG kSleepGapMs = 2000;
constexpr ULONGLONG kResumeGraceMs = 10000;
// פער כזה בשעון הערות בין דגימות של שנייה = כל התהליך או המחשב נעצר (דפדוף).
constexpr ULONGLONG kProcessStallGapMs = 10000;
constexpr int kMaxReports = 5;
// דגימה אחת לא מבדילה בין לולאה ארוכה אחת לבין עבודה שמתחלפת.
constexpr int kMaxExtraSamples = 3;
constexpr ULONGLONG kSampleIntervalMs = 2000;
constexpr size_t kMaxThreadCandidates = 96;
constexpr size_t kMaxPeerStacks = 32;
constexpr size_t kMaxPeerFrames = 256;
constexpr size_t kFirstThreadBytes = 32 * 1024;
constexpr size_t kLaterThreadBytes = 8 * 1024;
constexpr size_t kProcessThreadBytes = 64 * 1024;
constexpr DWORD kCpuWindowMs = 250;
constexpr ULONGLONG kLowUiCpuMs = 25;
constexpr ULONGLONG kExceptionLeadMs = 10000;

HWND g_window = nullptr;
HANDLE g_stop_event = nullptr;
std::thread g_watcher;

// זמן ערות בלבד: בניגוד ל-GetTickCount64 אינו מתקדם בשינה של המערכת.
ULONGLONG AwakeMs() {
  ULONGLONG units = 0;
  ::QueryUnbiasedInterruptTime(&units);
  return units / 10000;
}

ULONGLONG MsSinceLaunch() {
  FILETIME created = {}, exited = {}, kernel = {}, user = {};
  if (!::GetProcessTimes(::GetCurrentProcess(), &created, &exited, &kernel,
                         &user)) {
    return 0;
  }
  FILETIME now = {};
  ::GetSystemTimeAsFileTime(&now);
  const ULONGLONG start =
      (static_cast<ULONGLONG>(created.dwHighDateTime) << 32) |
      created.dwLowDateTime;
  const ULONGLONG current =
      (static_cast<ULONGLONG>(now.dwHighDateTime) << 32) | now.dwLowDateTime;
  return current > start ? (current - start) / 10000 : 0;
}

using GetThreadDescriptionFn = HRESULT(WINAPI*)(HANDLE, PWSTR*);
GetThreadDescriptionFn g_get_thread_description = nullptr;

void LoadThreadNameReader() {
  g_get_thread_description = reinterpret_cast<GetThreadDescriptionFn>(
      ::GetProcAddress(::GetModuleHandleW(L"kernel32.dll"),
                       "GetThreadDescription"));
}

std::string ThreadName(HANDLE thread) {
  PWSTR wide = nullptr;
  if (g_get_thread_description == nullptr ||
      FAILED(g_get_thread_description(thread, &wide)) || wide == nullptr) {
    return "";
  }
  char name[128] = {};
  int chars = 0;
  while (chars < 42 && wide[chars] != L'\0') ++chars;
  if (chars > 0 && wide[chars - 1] >= 0xd800 && wide[chars - 1] <= 0xdbff)
    --chars;
  const int bytes = chars == 0 ? 0 : ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, wide, chars, name, sizeof(name), nullptr,
      nullptr);
  ::LocalFree(wide);
  for (int i = 0; i < bytes; ++i) {
    const auto ch = static_cast<unsigned char>(name[i]);
    if (ch < 32 || ch == 127) name[i] = ' ';
  }
  return std::string(name, bytes);
}

std::optional<ULONGLONG> ThreadCpuMs(HANDLE thread) {
  FILETIME created = {}, exited = {}, kernel = {}, user = {};
  if (!::GetThreadTimes(thread, &created, &exited, &kernel, &user))
    return std::nullopt;
  const ULONGLONG kernel_units =
      (static_cast<ULONGLONG>(kernel.dwHighDateTime) << 32) |
      kernel.dwLowDateTime;
  const ULONGLONG user_units =
      (static_cast<ULONGLONG>(user.dwHighDateTime) << 32) | user.dwLowDateTime;
  return (kernel_units + user_units) / 10000;
}

struct OtherThread {
  DWORD id = 0;
  HANDLE handle = nullptr;
  ULONGLONG cpu_ms = 0;
  ULONGLONG recent_cpu_ms = 0;
  std::string name;
  std::vector<ULONG_PTR> frames;
  int same_stack = 0;
  bool in_loader = false;
};

struct ThreadCapture {
  std::vector<OtherThread> threads;
  std::optional<ULONGLONG> ui_cpu_ms;
  size_t omitted = 0;
};

std::optional<ULONGLONG> CpuDelta(std::optional<ULONGLONG> before,
                                  std::optional<ULONGLONG> after) {
  if (!before || !after || *after < *before) return std::nullopt;
  return *after - *before;
}

#if defined(_M_X64)
ULONG_PTR g_ntdll_begin = 0;
ULONG_PTR g_ntdll_end = 0;

struct LoaderEntry {
  ULONG_PTR address = 0;
  ULONG_PTR function_begin = 0;
};
std::array<LoaderEntry, 3> g_loader_entries{};

ULONG_PTR FunctionBegin(ULONG_PTR pc, ULONG_PTR expected_base) {
  __try {
    DWORD64 image_base = 0;
    const auto* function = ::RtlLookupFunctionEntry(pc, &image_base, nullptr);
    if (image_base != expected_base) return 0;
    for (unsigned depth = 0; function != nullptr && depth < 32; ++depth) {
      const auto* info =
          reinterpret_cast<const BYTE*>(image_base) + function->UnwindData;
      if (((info[0] >> 3) & UNW_FLAG_CHAININFO) == 0)
        return image_base + function->BeginAddress;
      const BYTE codes = info[2];
      function = reinterpret_cast<const RUNTIME_FUNCTION*>(
          info + 4 + ((codes + 1) & ~1) * 2);
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
  return 0;
}

void LoadLoaderEntries() {
  if (g_ntdll_begin != 0) return;
  const HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  MODULEINFO info = {};
  if (ntdll == nullptr ||
      !::GetModuleInformation(::GetCurrentProcess(), ntdll, &info, sizeof(info)))
    return;
  g_ntdll_begin = reinterpret_cast<ULONG_PTR>(info.lpBaseOfDll);
  g_ntdll_end = g_ntdll_begin + info.SizeOfImage;
  constexpr const char* names[] = {
      "LdrLoadDll", "LdrUnloadDll", "LdrInitializeThunk"};
  for (size_t i = 0; i < g_loader_entries.size(); ++i) {
    const auto address =
        reinterpret_cast<ULONG_PTR>(::GetProcAddress(ntdll, names[i]));
    if (address < g_ntdll_begin || address >= g_ntdll_end) continue;
    g_loader_entries[i] = {address, FunctionBegin(address, g_ntdll_begin)};
  }
}

bool IsLoaderFrame(ULONG_PTR pc, bool from_return_address = false) {
  if (pc < g_ntdll_begin || pc >= g_ntdll_end) return false;
  const ULONG_PTR begin =
      FunctionBegin(pc - (from_return_address ? 1 : 0), g_ntdll_begin);
  return std::any_of(g_loader_entries.begin(), g_loader_entries.end(),
                     [&](const LoaderEntry& entry) {
                       return pc == entry.address ||
                              (begin != 0 && begin == entry.function_begin);
                     });
}

bool LoaderProbeReady() { return g_ntdll_begin != 0; }
#else
void LoadLoaderEntries() {}
bool IsLoaderFrame(ULONG_PTR, bool) { return false; }
bool LoaderProbeReady() { return false; }
#endif

bool InLoader(const std::vector<ULONG_PTR>& frames) {
  for (size_t i = 0; i < frames.size(); ++i) {
    if (IsLoaderFrame(frames[i], i != 0))
      return true;
  }
  return false;
}

void LimitPeerStacks(ThreadCapture* capture) {
  std::stable_partition(capture->threads.begin(), capture->threads.end(),
                        [](const OtherThread& thread) { return thread.in_loader; });
  while (capture->threads.size() > kMaxPeerStacks) {
    capture->omitted += 1 + static_cast<size_t>(capture->threads.back().same_stack);
    capture->threads.pop_back();
  }
}

ThreadCapture CaptureOtherThreads(bool first_report) {
  ThreadCapture capture;
  std::vector<OtherThread> threads;
  const HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return capture;
  const DWORD process = ::GetCurrentProcessId();
  const DWORD self = ::GetCurrentThreadId();
  const DWORD main_thread = ::GetWindowThreadProcessId(g_window, nullptr);
  THREADENTRY32 entry = {};
  entry.dwSize = sizeof(entry);
  for (BOOL more = ::Thread32First(snapshot, &entry); more;
       more = ::Thread32Next(snapshot, &entry)) {
    if (entry.th32OwnerProcessID != process || entry.th32ThreadID == self ||
        entry.th32ThreadID == main_thread) {
      continue;
    }
    if (threads.size() >= kMaxThreadCandidates) {
      ++capture.omitted;
      continue;
    }
    const HANDLE handle = ::OpenThread(THREAD_SUSPEND_RESUME |
                                           THREAD_GET_CONTEXT |
                                           THREAD_QUERY_LIMITED_INFORMATION,
                                       FALSE, entry.th32ThreadID);
    if (handle == nullptr) continue;
    if (::GetProcessIdOfThread(handle) != process) {
      ::CloseHandle(handle);
      continue;
    }
    OtherThread thread;
    thread.id = entry.th32ThreadID;
    thread.handle = handle;
    thread.cpu_ms = ThreadCpuMs(handle).value_or(0);
    threads.push_back(std::move(thread));
  }
  ::CloseHandle(snapshot);

  const HANDLE ui = ::OpenThread(THREAD_QUERY_LIMITED_INFORMATION, FALSE,
                                  main_thread);
  const auto before = ui == nullptr ? std::nullopt : ThreadCpuMs(ui);
  const bool stopping =
      ::WaitForSingleObject(g_stop_event, kCpuWindowMs) == WAIT_OBJECT_0;
  if (ui != nullptr) {
    capture.ui_cpu_ms = CpuDelta(before, ThreadCpuMs(ui));
    ::CloseHandle(ui);
  }
  const bool low_ui_cpu =
      capture.ui_cpu_ms && *capture.ui_cpu_ms < kLowUiCpuMs;
  if (stopping || (!first_report && !low_ui_cpu)) {
    for (const OtherThread& thread : threads) ::CloseHandle(thread.handle);
    return capture;
  }

  // במצב של מעט CPU ב-UI, מי שמעכב אותו עשוי להיות מחוץ ל-Flutter.
  MODULEINFO flutter = {};
  if (!low_ui_cpu) {
    const HMODULE module = ::GetModuleHandleW(L"flutter_windows.dll");
    if (module != nullptr) {
      ::GetModuleInformation(::GetCurrentProcess(), module, &flutter,
                             sizeof(flutter));
    }
  }
  const ULONG_PTR begin = reinterpret_cast<ULONG_PTR>(flutter.lpBaseOfDll);
  const ULONG_PTR end = begin + flutter.SizeOfImage;
  for (OtherThread& thread : threads) {
    const ULONGLONG cpu_ms = ThreadCpuMs(thread.handle).value_or(thread.cpu_ms);
    thread.recent_cpu_ms = cpu_ms - (std::min)(cpu_ms, thread.cpu_ms);
    thread.cpu_ms = cpu_ms;
  }
  std::stable_sort(threads.begin(), threads.end(),
                   [](const OtherThread& a, const OtherThread& b) {
                     return a.recent_cpu_ms != b.recent_cpu_ms
                                ? a.recent_cpu_ms > b.recent_cpu_ms
                                : a.cpu_ms > b.cpu_ms;
                   });
  const bool probe_loader = low_ui_cpu && LoaderProbeReady();
  const size_t capture_limit =
      probe_loader ? kMaxThreadCandidates : kMaxPeerStacks;
  for (size_t i = 0; i < threads.size(); ++i) {
    OtherThread& thread = threads[i];
    if (i >= capture_limit ||
        ::WaitForSingleObject(g_stop_event, 0) == WAIT_OBJECT_0) {
      ++capture.omitted;
      ::CloseHandle(thread.handle);
      continue;
    }
    startup_watchdog::CaptureThreadStack(thread.handle, &thread.frames,
                                         kMaxPeerFrames);
    thread.name = ThreadName(thread.handle);
    ::CloseHandle(thread.handle);
    thread.handle = nullptr;
    if (thread.frames.empty()) continue;
    if (!low_ui_cpu && !std::any_of(
            thread.frames.begin(), thread.frames.end(), [&](ULONG_PTR frame) {
              return (frame >= begin && frame < end) ||
                     startup_watchdog::IsDartFrame(frame);
            })) {
      continue;
    }
    thread.in_loader = probe_loader && InLoader(thread.frames);
    const auto same = std::find_if(
        capture.threads.begin(), capture.threads.end(),
        [&](const OtherThread& other) { return other.frames == thread.frames; });
    if (same != capture.threads.end()) {
      ++same->same_stack;
    } else {
      capture.threads.push_back(std::move(thread));
    }
  }
  LimitPeerStacks(&capture);
  return capture;
}

size_t AppendOtherThreads(const ThreadCapture& capture, size_t max_bytes,
                          std::string* report,
                          std::vector<ULONG_PTR>* described_frames) {
  size_t used = 0;
  size_t omitted = capture.omitted;
  for (const OtherThread& thread : capture.threads) {
    char header[256];
    snprintf(header, sizeof(header),
             "--- Thread %lu \"%s\", CPU %llums (%llums in last %lums), "
             "%d more with this stack%s ---\n",
             thread.id, thread.name.c_str(), thread.cpu_ms,
             thread.recent_cpu_ms, kCpuWindowMs, thread.same_stack,
             thread.in_loader ? ", in loader" : "");
    std::string section = header;
    startup_watchdog::AppendStack(thread.frames, &section);
    if (section.size() > max_bytes - used) {
      omitted += 1 + static_cast<size_t>(thread.same_stack);
      continue;
    }
    used += section.size();
    *report += section;
    described_frames->insert(described_frames->end(), thread.frames.begin(),
                             thread.frames.end());
  }
  if (omitted != 0) {
    char summary[96];
    snprintf(summary, sizeof(summary),
             "--- %zu more threads omitted (capture or log limit) ---\n",
             omitted);
    *report += summary;
  }
  return used;
}

// commit = הזיכרון שהמערכת יכולה עוד להקצות (כולל קובץ הדפדוף); כשהוא אוזל
// גם יצירת thread ממתינה.
void AppendMemory(std::string* report) {
  constexpr ULONGLONG kMb = 1024 * 1024;
  PROCESS_MEMORY_COUNTERS_EX process = {};
  process.cb = sizeof(process);
  MEMORYSTATUSEX system = {};
  system.dwLength = sizeof(system);
  if (!::GetProcessMemoryInfo(
          ::GetCurrentProcess(),
          reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&process),
          sizeof(process)) ||
      !::GlobalMemoryStatusEx(&system)) {
    return;
  }
  char line[256];
  snprintf(line, sizeof(line),
           "Memory: private %lluMB, working set %lluMB; system available "
           "%llu/%lluMB (load %lu%%), commit available %llu/%lluMB\n",
           static_cast<ULONGLONG>(process.PrivateUsage) / kMb,
           static_cast<ULONGLONG>(process.WorkingSetSize) / kMb,
           system.ullAvailPhys / kMb, system.ullTotalPhys / kMb,
           system.dwMemoryLoad, system.ullAvailPageFile / kMb,
           system.ullTotalPageFile / kMb);
  *report += line;
}

void ReportHang(const std::vector<ULONG_PTR>& frames, bool first_report,
                ULONGLONG hang_started_at, ULONGLONG detected_at,
                size_t* thread_bytes_left) {
  std::string context;
  crash_record::AppendDiagnosticContext(&context);
  const auto exception = native_exception_log::FindStackMatch(
      native_exception_log::ReadRecent(), frames,
      hang_started_at > kExceptionLeadMs ? hang_started_at - kExceptionLeadMs : 0,
      detected_at);
  const ThreadCapture capture = *thread_bytes_left == 0
      ? ThreadCapture()
      : CaptureOtherThreads(first_report);
  std::vector<ULONG_PTR> all_frames = frames;
  std::string thread_details;
  const size_t used = AppendOtherThreads(
      capture, (std::min)(*thread_bytes_left,
                          first_report ? kFirstThreadBytes : kLaterThreadBytes),
      &thread_details, &all_frames);
  std::string report =
      "\n=== App hang " + startup_watchdog::UtcTimestamp() + " ===\n";
#ifdef FLUTTER_VERSION
  report += std::string("Version: ") + FLUTTER_VERSION + "\n";
#endif
  // בלי מספרים בשורה: ממנה נגזר סוג החתימה (AppHang).
  report += "Message: AppHang: UI thread not responding\n";
  char detected[64];
  snprintf(detected, sizeof(detected), "Detected: %llums after launch\n",
           MsSinceLaunch());
  report += detected;
  report += context;
  AppendMemory(&report);
  if (capture.ui_cpu_ms) {
    char cpu[96];
    snprintf(cpu, sizeof(cpu), "UI thread CPU: %llums in %lums\n",
             *capture.ui_cpu_ms, kCpuWindowMs);
    report += cpu;
  }
  startup_watchdog::AppendBuildIdentity(all_frames, &report);
  startup_watchdog::AppendStack(frames, &report);
  if (exception) {
    char header[160];
    snprintf(header, sizeof(header),
             "--- Recent UI exception matching stack (%llums before detection) ---\n"
             "Code: 0x%08x\nAddress: ",
             static_cast<unsigned long long>(detected_at - exception->awake_ms),
             static_cast<unsigned int>(exception->code));
    report += header;
    report += startup_watchdog::DescribeFrame(exception->address) + "\n";
  }
  report += thread_details;
  if (startup_watchdog::AppendReport(report)) *thread_bytes_left -= used;
}

// בתוך רשומת התקיעה, אחרי שורת `---`: הפרסר מחשב את החתימה מהדגימה הראשונה.
void ReportSample(int index, ULONGLONG into_hang_ms,
                  const std::vector<ULONG_PTR>& frames) {
  char header[96];
  snprintf(header, sizeof(header), "--- Sample %d, %llums into the hang ---\n",
           index, into_hang_ms);
  std::string report = header;
  startup_watchdog::AppendStack(frames, &report);
  startup_watchdog::AppendReport(report);
}

std::vector<ULONG_PTR> CaptureFrames() {
  std::vector<ULONG_PTR> frames;
  startup_watchdog::CaptureMainStack(&frames);
  return frames;
}

void ReportRecovered(ULONGLONG duration_ms) {
  char text[96];
  snprintf(text, sizeof(text), "Duration: %llums\n", duration_ms);
  startup_watchdog::AppendReport("\n=== App hang recovered " +
                                 startup_watchdog::UtcTimestamp() + " ===\n" +
                                 text);
}

enum class PollGap { kNone, kSleep, kProcessStall };

// פער בין השעונים = המערכת ישנה.
PollGap ClassifyPollGap(ULONGLONG tick_delta, ULONGLONG awake_delta) {
  if (tick_delta > awake_delta + kSleepGapMs) return PollGap::kSleep;
  if (awake_delta > kProcessStallGapMs) return PollGap::kProcessStall;
  return PollGap::kNone;
}

void ReportProcessStall(ULONGLONG gap_ms) {
  char text[64];
  snprintf(text, sizeof(text), "Gap: %llums\n", gap_ms);
  std::string report = "\n=== Process stall " +
                       startup_watchdog::UtcTimestamp() + " ===\n" + text;
  AppendMemory(&report);
  startup_watchdog::AppendReport(report);
}

void WatcherLoop() {
  LoadThreadNameReader();
  LoadLoaderEntries();
  native_exception_log::Install(::GetWindowThreadProcessId(g_window, nullptr));
  ULONGLONG last_tick = ::GetTickCount64();
  ULONGLONG last_awake = AwakeMs();
  ULONGLONG grace_until = 0;
  ULONGLONG first_hung_at = 0;
  ULONGLONG hang_started_at = 0;
  ULONGLONG last_sample_at = 0;
  int hung_polls = 0;
  int reports = 0;
  size_t thread_bytes_left = kProcessThreadBytes;
  int stalls = 0;
  int samples = 0;
  bool in_hang = false;

  while (::WaitForSingleObject(g_stop_event, kPollIntervalMs) == WAIT_TIMEOUT) {
    if (!::IsWindow(g_window)) return;
    const ULONGLONG tick = ::GetTickCount64();
    const ULONGLONG awake = AwakeMs();
    // אחרי שינה או עצירה החלון "תקוע" עד שישלוף הודעות.
    const ULONGLONG tick_delta = tick - last_tick;
    const ULONGLONG awake_delta = awake - last_awake;
    last_tick = tick;
    last_awake = awake;
    const PollGap gap = ClassifyPollGap(tick_delta, awake_delta);
    if (gap != PollGap::kNone) grace_until = awake + kResumeGraceMs;
    // בתוך תקיעה רשומה נפרדת הייתה מנתקת ממנה את הדגימות שאחריה.
    if (gap == PollGap::kProcessStall && !in_hang && stalls < kMaxReports) {
      ++stalls;
      ReportProcessStall(awake_delta);
    }

    const bool hung = ::IsHungAppWindow(g_window) != FALSE;
    if (in_hang) {
      if (hung) {
        if (samples < kMaxExtraSamples &&
            awake - last_sample_at >= kSampleIntervalMs) {
          last_sample_at = awake;
          ReportSample(++samples, awake - hang_started_at, CaptureFrames());
        }
        continue;
      }
      in_hang = false;
      const ULONGLONG duration = awake - hang_started_at;
      ReportRecovered(duration);
      ::PostMessageW(g_window, kMsgAppHangRecovered, 0,
                     static_cast<LPARAM>(duration));
      continue;
    }

    if (!hung || ::IsDebuggerPresent() || awake < grace_until) {
      hung_polls = 0;
      continue;
    }
    if (++hung_polls == 1) first_hung_at = awake;
    if (hung_polls < kRequiredHungPolls || reports >= kMaxReports) continue;

    hung_polls = 0;
    ++reports;
    in_hang = true;
    hang_started_at = first_hung_at - kHungThresholdMs;
    last_sample_at = awake;
    samples = 0;
    ReportHang(CaptureFrames(), reports == 1, hang_started_at, awake,
               &thread_bytes_left);
  }
}

}  // namespace

void SetMainWindow(HWND window) { g_window = window; }

void Start() {
  if (g_window == nullptr || g_watcher.joinable()) return;
  g_stop_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_stop_event == nullptr) return;
  g_watcher = std::thread(WatcherLoop);
}

void Stop() {
  if (g_stop_event != nullptr) ::SetEvent(g_stop_event);
  if (g_watcher.joinable()) g_watcher.join();
  if (g_stop_event != nullptr) {
    ::CloseHandle(g_stop_event);
    g_stop_event = nullptr;
  }
}

}  // namespace hang_monitor
