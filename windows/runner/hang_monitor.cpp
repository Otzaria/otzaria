#include "hang_monitor.h"

#include <psapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

#include "accessibility_probe.h"
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
constexpr int kMaxOtherThreads = 32;
constexpr DWORD kCpuWindowMs = 250;
// פחות מזה בחלון המדידה = ה-thread הראשי ממתין למישהו (safepoint, loader, COM).
constexpr ULONGLONG kMainWaitingCpuMs = kCpuWindowMs / 10;
// thread שעבד לפחות כך בחלון נדגם שוב עם הדגימות הנוספות.
constexpr ULONGLONG kBusyThreadCpuMs = kCpuWindowMs / 5;
constexpr size_t kMaxResampledThreads = 2;
// הדוח לוקח 200KB מזנב errors.txt: threads רבים היו דוחקים רשומות קודמות.
constexpr size_t kFirstReportThreadBytes = 48 * 1024;
constexpr size_t kLaterReportThreadBytes = 12 * 1024;
constexpr size_t kProcessThreadBytes = 96 * 1024;
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

std::string ThreadName(HANDLE thread) {
  using GetThreadDescriptionFn = HRESULT(WINAPI*)(HANDLE, PWSTR*);
  static const auto get_description = reinterpret_cast<GetThreadDescriptionFn>(
      ::GetProcAddress(::GetModuleHandleW(L"kernel32.dll"),
                       "GetThreadDescription"));
  PWSTR wide = nullptr;
  if (get_description == nullptr || FAILED(get_description(thread, &wide)) ||
      wide == nullptr) {
    return "";
  }
  char name[128] = {0};
  ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, name, sizeof(name) - 1, nullptr,
                        nullptr);
  ::LocalFree(wide);
  return name;
}

ULONGLONG ThreadCpuMs(HANDLE thread) {
  FILETIME created = {}, exited = {}, kernel = {}, user = {};
  if (!::GetThreadTimes(thread, &created, &exited, &kernel, &user)) return 0;
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

#if defined(_M_X64)
// RtlLookupFunctionEntry מחזיר את המקטע של הפריים; הפונקציה מתחילה ברשומה
// הראשית שבסוף שרשרת UNW_FLAG_CHAININFO.
ULONG_PTR FunctionBegin(DWORD64 image_base, PRUNTIME_FUNCTION function) {
  for (int depth = 0; depth < 32; ++depth) {
    const BYTE* info = reinterpret_cast<const BYTE*>(image_base) +
                       function->UnwindData;
    if (((info[0] >> 3) & UNW_FLAG_CHAININFO) == 0) break;
    const BYTE codes = info[2];
    function = reinterpret_cast<PRUNTIME_FUNCTION>(
        const_cast<BYTE*>(info + 4 + ((codes + 1) & ~1) * 2));
  }
  return static_cast<ULONG_PTR>(image_base) + function->BeginAddress;
}
#endif

// בלי סמלים: פונקציות ה-loader המיוצאות מ-ntdll נמצאות מתחת לכל טעינת DLL.
// רק x64: פורמט ה-unwind של ARM64 שונה.
bool InLoader(const std::vector<ULONG_PTR>& frames) {
#if defined(_M_X64)
  static const std::vector<ULONG_PTR> entries = [] {
    std::vector<ULONG_PTR> found;
    const HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
    for (const char* name :
         {"LdrLoadDll", "LdrUnloadDll", "LdrInitializeThunk"}) {
      const FARPROC entry = ntdll ? ::GetProcAddress(ntdll, name) : nullptr;
      if (entry) found.push_back(reinterpret_cast<ULONG_PTR>(entry));
    }
    return found;
  }();
  for (const ULONG_PTR frame : frames) {
    DWORD64 image_base = 0;
    const PRUNTIME_FUNCTION function =
        ::RtlLookupFunctionEntry(frame - 1, &image_base, nullptr);
    if (function == nullptr) continue;
    const ULONG_PTR begin = FunctionBegin(image_base, function);
    if (std::find(entries.begin(), entries.end(), begin) != entries.end()) {
      return true;
    }
  }
#else
  (void)frames;
#endif
  return false;
}

struct ThreadCapture {
  std::vector<OtherThread> threads;
  ULONGLONG main_recent_cpu_ms = 0;
  bool main_cpu_known = false;
  bool main_waiting = false;
};

// threads שעבדו בלכידה הראשונה, לדגימה חוזרת יחד עם ה-thread הראשי.
struct BusyThread {
  DWORD id = 0;
  ULONGLONG cpu_ms = 0;
  std::string name;
};
std::vector<BusyThread> g_busy_threads;
// לכל חלקי ה-threads והדגימות החוזרות בכל התקיעות של התהליך.
size_t g_thread_bytes_left = kProcessThreadBytes;

// ה-UI יכול לחכות ל-thread אחר (safepoint של GC, #3332, loader, TSF). כשהראשי
// עובד נלכדים רק threads של Flutter, וכשהוא ממתין כולם.
ThreadCapture CaptureOtherThreads(bool first_report) {
  ThreadCapture capture;
  const DWORD main_thread = ::GetWindowThreadProcessId(g_window, nullptr);
  const HANDLE main_handle =
      ::OpenThread(THREAD_QUERY_LIMITED_INFORMATION, FALSE, main_thread);
  if (main_handle != nullptr) {
    const ULONGLONG before = ThreadCpuMs(main_handle);
    ::Sleep(kCpuWindowMs);
    const ULONGLONG after = ThreadCpuMs(main_handle);
    ::CloseHandle(main_handle);
    capture.main_recent_cpu_ms = after - (std::min)(after, before);
    capture.main_cpu_known = true;
    capture.main_waiting = capture.main_recent_cpu_ms < kMainWaitingCpuMs;
  }
  // בתקיעות הבאות רק כשהראשי ממתין: כשהוא עצמו עובד, מחסניתו מספיקה.
  if (!first_report && !capture.main_waiting) return capture;
  MODULEINFO flutter = {};
  const HMODULE module = ::GetModuleHandleW(L"flutter_windows.dll");
  if (module == nullptr ||
      !::GetModuleInformation(::GetCurrentProcess(), module, &flutter,
                              sizeof(flutter))) {
    return capture;
  }
  const HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return capture;
  const DWORD process = ::GetCurrentProcessId();
  const DWORD self = ::GetCurrentThreadId();
  std::vector<OtherThread> threads;
  THREADENTRY32 entry = {};
  entry.dwSize = sizeof(entry);
  for (BOOL more = ::Thread32First(snapshot, &entry); more;
       more = ::Thread32Next(snapshot, &entry)) {
    if (entry.th32OwnerProcessID != process || entry.th32ThreadID == self ||
        entry.th32ThreadID == main_thread) {
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
    thread.cpu_ms = ThreadCpuMs(handle);
    threads.push_back(std::move(thread));
  }
  ::CloseHandle(snapshot);

  // זמן CPU שנצבר בחלון קצר מצביע על ה-thread שעובד עכשיו.
  ::Sleep(kCpuWindowMs);
  const ULONG_PTR begin = reinterpret_cast<ULONG_PTR>(flutter.lpBaseOfDll);
  const ULONG_PTR end = begin + flutter.SizeOfImage;
  std::vector<OtherThread> captured;
  for (OtherThread& thread : threads) {
    const ULONGLONG cpu_ms = ThreadCpuMs(thread.handle);
    thread.recent_cpu_ms = cpu_ms - (std::min)(cpu_ms, thread.cpu_ms);
    thread.cpu_ms = cpu_ms;
    startup_watchdog::CaptureThreadStack(thread.handle, &thread.frames);
    thread.name = ThreadName(thread.handle);
    ::CloseHandle(thread.handle);
    thread.handle = nullptr;
    thread.in_loader = InLoader(thread.frames);
    const bool ours = std::any_of(
        thread.frames.begin(), thread.frames.end(), [&](ULONG_PTR frame) {
          return (frame >= begin && frame < end) ||
                 startup_watchdog::IsDartFrame(frame);
        });
    if (ours || thread.in_loader || capture.main_waiting) {
      captured.push_back(std::move(thread));
    }
  }

  std::stable_sort(captured.begin(), captured.end(),
                   [](const OtherThread& a, const OtherThread& b) {
                     if (a.in_loader != b.in_loader) return a.in_loader;
                     return a.recent_cpu_ms != b.recent_cpu_ms
                                ? a.recent_cpu_ms > b.recent_cpu_ms
                                : a.cpu_ms > b.cpu_ms;
                   });
  for (OtherThread& thread : captured) {
    const auto same = std::find_if(
        capture.threads.begin(), capture.threads.end(),
        [&](const OtherThread& other) { return other.frames == thread.frames; });
    if (same != capture.threads.end()) {
      ++same->same_stack;
    } else if (static_cast<int>(capture.threads.size()) < kMaxOtherThreads) {
      capture.threads.push_back(std::move(thread));
    }
  }
  return capture;
}

void AppendOtherThreads(const std::vector<OtherThread>& threads,
                        size_t report_bytes, std::string* report) {
  const size_t max_bytes = (std::min)(report_bytes, g_thread_bytes_left);
  size_t used = 0;
  int omitted = 0;
  for (const OtherThread& thread : threads) {
    char header[256];
    snprintf(header, sizeof(header),
             "--- Thread %lu \"%s\", CPU %llums (%llums in last %lums), "
             "%d more with this stack%s ---\n",
             thread.id, thread.name.c_str(), thread.cpu_ms,
             thread.recent_cpu_ms, kCpuWindowMs, thread.same_stack,
             thread.in_loader ? ", in loader" : "");
    std::string section = header;
    startup_watchdog::AppendStack(thread.frames, &section);
    if (used + section.size() > max_bytes) {
      ++omitted;
      continue;
    }
    used += section.size();
    *report += section;
  }
  g_thread_bytes_left -= used;
  if (omitted > 0) {
    char line[96];
    snprintf(line, sizeof(line),
             "--- %d more threads omitted (record size cap) ---\n", omitted);
    *report += line;
  }
}

void RememberBusyThreads(const std::vector<OtherThread>& threads) {
  g_busy_threads.clear();
  for (const OtherThread& thread : threads) {
    if (g_busy_threads.size() >= kMaxResampledThreads) break;
    if (thread.recent_cpu_ms < kBusyThreadCpuMs) continue;
    g_busy_threads.push_back({thread.id, thread.cpu_ms, thread.name});
  }
}

void AppendBusyThreadSamples(std::string* report) {
  const DWORD process = ::GetCurrentProcessId();
  for (BusyThread& busy : g_busy_threads) {
    const HANDLE handle = ::OpenThread(THREAD_SUSPEND_RESUME |
                                           THREAD_GET_CONTEXT |
                                           THREAD_QUERY_LIMITED_INFORMATION,
                                       FALSE, busy.id);
    if (handle == nullptr) continue;
    std::vector<ULONG_PTR> frames;
    ULONGLONG cpu_ms = 0;
    const bool ours = ::GetProcessIdOfThread(handle) == process;
    if (ours) {
      cpu_ms = ThreadCpuMs(handle);
      startup_watchdog::CaptureThreadStack(handle, &frames);
    }
    ::CloseHandle(handle);
    if (!ours) continue;
    std::string section;
    char header[192];
    snprintf(header, sizeof(header),
             "--- Thread %lu \"%s\" again, CPU +%llums since previous "
             "capture ---\n",
             busy.id, busy.name.c_str(),
             cpu_ms - (std::min)(cpu_ms, busy.cpu_ms));
    busy.cpu_ms = cpu_ms;
    section = header;
    startup_watchdog::AppendStack(frames, &section);
    if (section.size() > g_thread_bytes_left) continue;
    g_thread_bytes_left -= section.size();
    *report += section;
  }
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
                ULONGLONG hang_started_at, ULONGLONG detected_at) {
  const auto exception = native_exception_log::FindStackMatch(
      native_exception_log::ReadRecent(), frames,
      hang_started_at > kExceptionLeadMs ? hang_started_at - kExceptionLeadMs : 0,
      detected_at);
  const ThreadCapture capture = CaptureOtherThreads(first_report);
  const std::vector<OtherThread>& threads = capture.threads;
  RememberBusyThreads(threads);
  std::vector<ULONG_PTR> all_frames = frames;
  for (const OtherThread& thread : threads) {
    all_frames.insert(all_frames.end(), thread.frames.begin(),
                      thread.frames.end());
  }
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
  crash_record::AppendContext(&report);
  accessibility_probe::AppendFirstRequest(&report);
  AppendMemory(&report);
  if (capture.main_cpu_known) {
    char main_line[128];
    snprintf(main_line, sizeof(main_line),
             "Main thread: CPU %llums in last %lums (%s)%s\n",
             capture.main_recent_cpu_ms, kCpuWindowMs,
             capture.main_waiting ? "waiting" : "running",
             InLoader(frames) ? ", in loader" : "");
    report += main_line;
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
  AppendOtherThreads(
      threads,
      first_report ? kFirstReportThreadBytes : kLaterReportThreadBytes,
      &report);
  startup_watchdog::AppendReport(report);
}

// בתוך רשומת התקיעה, אחרי שורת `---`: הפרסר מחשב את החתימה מהדגימה הראשונה.
void ReportSample(int index, ULONGLONG into_hang_ms,
                  const std::vector<ULONG_PTR>& frames) {
  char header[96];
  snprintf(header, sizeof(header), "--- Sample %d, %llums into the hang ---\n",
           index, into_hang_ms);
  std::string report = header;
  startup_watchdog::AppendStack(frames, &report);
  AppendBusyThreadSamples(&report);
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
  native_exception_log::Install(::GetWindowThreadProcessId(g_window, nullptr));
  ULONGLONG last_tick = ::GetTickCount64();
  ULONGLONG last_awake = AwakeMs();
  ULONGLONG grace_until = 0;
  ULONGLONG first_hung_at = 0;
  ULONGLONG hang_started_at = 0;
  ULONGLONG last_sample_at = 0;
  int hung_polls = 0;
  int reports = 0;
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
    ReportHang(CaptureFrames(), reports == 1, hang_started_at, awake);
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
