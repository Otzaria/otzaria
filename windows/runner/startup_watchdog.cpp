#include "startup_watchdog.h"

#include <windows.h>

#include <psapi.h>
#include <shlobj.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace startup_watchdog {

namespace {

// סף התקיעה, המרווח בין צילומים ומספרם המרבי — הדוח נועד לאבחון עלייה,
// לא לניטור רציף.
constexpr DWORD kStallThresholdMs = 3000;
constexpr DWORD kCaptureIntervalMs = 5000;
constexpr int kMaxCaptures = 6;
constexpr DWORD kHeartbeatIntervalMs = 250;
constexpr ULONGLONG kMaxLifetimeMs = 300000;
constexpr int kMaxFrames = 48;

struct ModuleRange {
  ULONG_PTR base = 0;
  ULONG_PTR size = 0;
  std::string name;
};

std::atomic<ULONGLONG> g_last_beat{0};
std::atomic<bool> g_stop{false};
std::atomic<bool> g_started{false};
HANDLE g_main_thread = nullptr;
UINT_PTR g_timer = 0;
ULONGLONG g_start_tick = 0;
std::thread g_watcher;

using ModuleSnapshot = std::vector<ModuleRange>;
std::shared_ptr<const ModuleSnapshot> g_modules =
    std::make_shared<const ModuleSnapshot>();

void CALLBACK HeartbeatProc(HWND, UINT, UINT_PTR, DWORD) {
  const ULONGLONG now = ::GetTickCount64();
  g_last_beat.store(now, std::memory_order_relaxed);
  if (now - g_start_tick > kMaxLifetimeMs) return RequestStop();
}

std::string NarrowPathTail(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  const std::wstring tail =
      slash == std::wstring::npos ? path : path.substr(slash + 1);
  const int len = ::WideCharToMultiByte(CP_UTF8, 0, tail.c_str(), -1, nullptr,
                                        0, nullptr, nullptr);
  if (len <= 1) return std::string();
  std::string out(static_cast<size_t>(len), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, tail.c_str(), -1, &out[0], len, nullptr,
                        nullptr);
  out.resize(static_cast<size_t>(len - 1));
  return out;
}

std::shared_ptr<const ModuleSnapshot> BuildModuleSnapshot() {
  HMODULE handles[512];
  DWORD needed = 0;
  if (!::EnumProcessModules(::GetCurrentProcess(), handles, sizeof(handles),
                            &needed)) {
    return nullptr;
  }
  const size_t count =
      (std::min)(static_cast<size_t>(needed / sizeof(HMODULE)),
                 sizeof(handles) / sizeof(handles[0]));
  auto fresh = std::make_shared<ModuleSnapshot>();
  fresh->reserve(count);
  for (size_t i = 0; i < count; ++i) {
    MODULEINFO info = {};
    if (!::GetModuleInformation(::GetCurrentProcess(), handles[i], &info,
                                sizeof(info))) {
      continue;
    }
    wchar_t path[MAX_PATH] = {0};
    if (::GetModuleFileNameW(handles[i], path, MAX_PATH) == 0) continue;
    ModuleRange range;
    range.base = reinterpret_cast<ULONG_PTR>(info.lpBaseOfDll);
    range.size = info.SizeOfImage;
    range.name = NarrowPathTail(path);
    fresh->push_back(std::move(range));
  }
  return fresh;
}

std::string DescribeAddress(ULONG_PTR address) {
  char buffer[160];
  const auto modules =
      std::atomic_load_explicit(&g_modules, std::memory_order_acquire);
  for (const ModuleRange& range : *modules) {
    if (address >= range.base && address < range.base + range.size) {
      snprintf(buffer, sizeof(buffer), "%s+0x%llx", range.name.c_str(),
               static_cast<unsigned long long>(address - range.base));
      return buffer;
    }
  }
  // מיפוי לפי כתובת מזהה DLL מאוחר בלי לגשת לרשימת ה-loader.
  // נקרא רק בעת דיווח, אחרי חידוש ה-thread הראשי.
  MEMORY_BASIC_INFORMATION info = {};
  if (::VirtualQuery(reinterpret_cast<LPCVOID>(address), &info, sizeof(info)) != 0 &&
      info.Type == MEM_IMAGE) {
    wchar_t path[MAX_PATH] = {0};
    const DWORD length = ::GetMappedFileNameW(
        ::GetCurrentProcess(), reinterpret_cast<LPVOID>(address), path, MAX_PATH);
    if (length > 0 && length < MAX_PATH) {
      const std::string name = NarrowPathTail(path);
      if (!name.empty()) {
        snprintf(buffer, sizeof(buffer), "%s+0x%llx", name.c_str(),
                 static_cast<unsigned long long>(
                     address - reinterpret_cast<ULONG_PTR>(info.AllocationBase)));
        return buffer;
      }
    }
  }
  snprintf(buffer, sizeof(buffer), "0x%llx",
           static_cast<unsigned long long>(address));
  return buffer;
}

#if defined(_M_X64) || defined(_M_ARM64)

#if defined(_M_X64)
#define WD_PC(ctx) ((ctx).Rip)
#define WD_SP(ctx) ((ctx).Rsp)
#else
#define WD_PC(ctx) ((ctx).Pc)
#define WD_SP(ctx) ((ctx).Sp)
#endif

// קריאת מילה מהמחסנית של ה-thread המושהה — כתובת פגומה תפיל את התהליך בלי זה.
bool ReadStackWord(ULONG_PTR address, ULONG_PTR* out) {
  __try {
    *out = *reinterpret_cast<ULONG_PTR*>(address);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// פורשת את מחסנית הקריאות של ה-thread המושהה. רק RtlVirtualUnwind ומפת מודולים
// שנקראה מראש — כל קריאה שנוטלת את נעילת ה-loader תיתקע כאן.
void UnwindSuspendedThread(CONTEXT* context, std::vector<ULONG_PTR>* frames) {
  for (int i = 0; i < kMaxFrames; ++i) {
    const ULONG_PTR pc = static_cast<ULONG_PTR>(WD_PC(*context));
    if (pc == 0) break;
    frames->push_back(pc);

    DWORD64 image_base = 0;
    PRUNTIME_FUNCTION function =
        ::RtlLookupFunctionEntry(WD_PC(*context), &image_base, nullptr);
    if (function == nullptr) {
#if defined(_M_X64)
      ULONG_PTR return_address = 0;
      if (!ReadStackWord(static_cast<ULONG_PTR>(WD_SP(*context)),
                         &return_address)) {
        break;
      }
      WD_PC(*context) = return_address;
      WD_SP(*context) += sizeof(ULONG_PTR);
#else
      if (context->Lr == 0 || context->Lr == WD_PC(*context)) break;
      WD_PC(*context) = context->Lr;
#endif
      continue;
    }

    PVOID handler_data = nullptr;
    DWORD64 establisher_frame = 0;
    ::RtlVirtualUnwind(UNW_FLAG_NHANDLER, image_base, WD_PC(*context), function,
                       context, &handler_data, &establisher_frame, nullptr);
    if (WD_PC(*context) == 0) break;
  }
}

bool CaptureMainThreadStack(std::vector<ULONG_PTR>* frames) {
  if (g_main_thread == nullptr) return false;
  if (::SuspendThread(g_main_thread) == static_cast<DWORD>(-1)) return false;

  CONTEXT context = {};
  context.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
  const bool got_context = ::GetThreadContext(g_main_thread, &context) != FALSE;
  if (got_context) UnwindSuspendedThread(&context, frames);

  ::ResumeThread(g_main_thread);
  return got_context;
}

#else  // ארכיטקטורה בלי פרישת מחסנית מבוססת-טבלאות (x86)

bool CaptureMainThreadStack(std::vector<ULONG_PTR>*) { return false; }

#endif

std::wstring ResolveLogPath() {
  wchar_t exe_path[MAX_PATH] = {0};
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) != 0) {
    std::wstring dir(exe_path);
    const size_t slash = dir.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
      dir = dir.substr(0, slash);
      // חייב לשקף את AppPaths.isPortable, אחרת הדוח נכתב לקובץ שהמשתמש הנייד
      // אינו רואה.
      if (::GetFileAttributesW((dir + L"\\portable.marker").c_str()) !=
          INVALID_FILE_ATTRIBUTES) {
        return dir + L"\\otzaria_data\\logs\\errors.txt";
      }
    }
  }

  wchar_t* app_data_raw = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_DEFAULT,
                                    nullptr, &app_data_raw))) {
    return std::wstring();
  }
  std::wstring app_data(app_data_raw);
  ::CoTaskMemFree(app_data_raw);
  return app_data + L"\\otzaria\\logs\\errors.txt";
}

void CreateParentDirectories(const std::wstring& path) {
  const size_t slash = path.find_last_of(L'\\');
  if (slash == std::wstring::npos) return;
  const std::wstring dir = path.substr(0, slash);
  const size_t parent = dir.find_last_of(L'\\');
  if (parent != std::wstring::npos) {
    ::CreateDirectoryW(dir.substr(0, parent).c_str(), nullptr);
  }
  ::CreateDirectoryW(dir.c_str(), nullptr);
}

void AppendToLog(const std::string& text) {
  const std::wstring path = ResolveLogPath();
  if (path.empty()) return;
  CreateParentDirectories(path);
  HANDLE file = ::CreateFileW(path.c_str(), FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  ::WriteFile(file, text.c_str(), static_cast<DWORD>(text.size()), &written,
              nullptr);
  ::CloseHandle(file);
}

std::string Timestamp() {
  SYSTEMTIME utc = {};
  ::GetSystemTime(&utc);
  char buffer[32];
  snprintf(buffer, sizeof(buffer), "%04u-%02u-%02uT%02u:%02u:%02uZ", utc.wYear,
           utc.wMonth, utc.wDay, utc.wHour, utc.wMinute, utc.wSecond);
  return buffer;
}

void ReportStall(int capture_index, ULONGLONG stalled_for_ms,
                 ULONGLONG since_launch_ms,
                 const std::vector<ULONG_PTR>& frames) {
  std::string report =
      "\n=== Startup heartbeat delay " + Timestamp() + " ===\n";
#ifdef FLUTTER_VERSION
  report += std::string("Version: ") + FLUTTER_VERSION + "\n";
#endif
  char header[192];
  snprintf(header, sizeof(header),
           "Message-loop timer delayed for %llums, at %llums after launch "
           "(the thread may be blocked or WM_TIMER starved) "
           "(capture %d/%d)\n",
           static_cast<unsigned long long>(stalled_for_ms),
           static_cast<unsigned long long>(since_launch_ms), capture_index,
           kMaxCaptures);
  report += header;

  if (frames.empty()) {
    report += "Stack: unavailable\n";
  } else {
    report += "Stack (module+RVA):\n";
    for (const ULONG_PTR frame : frames) {
      report += "  " + DescribeAddress(frame) + "\n";
    }
  }
  AppendToLog(report);
}

void WatcherLoop() {
  int captures = 0;
  ULONGLONG last_capture = 0;

  while (!g_stop.load(std::memory_order_relaxed)) {
    ::Sleep(kHeartbeatIntervalMs);
    const ULONGLONG now = ::GetTickCount64();
    if (now - g_start_tick > kMaxLifetimeMs) return;

    const ULONGLONG beat = g_last_beat.load(std::memory_order_relaxed);
    const ULONGLONG gap = now > beat ? now - beat : 0;

    if (gap < kStallThresholdMs) continue;

    if (captures >= kMaxCaptures) continue;
    if (last_capture != 0 && now - last_capture < kCaptureIntervalMs) continue;

    // הקצאה מראש: הקצאה בזמן שה-thread הראשי מושהה עלולה להיתקע על נעילת ה-heap.
    std::vector<ULONG_PTR> frames;
    frames.reserve(kMaxFrames);
    CaptureMainThreadStack(&frames);
    last_capture = now;
    ++captures;
    ReportStall(captures, gap, now - g_start_tick, frames);
  }
}

}  // namespace

void Start() {
  if (g_started.exchange(true)) return;
  g_stop.store(false, std::memory_order_relaxed);
  g_start_tick = ::GetTickCount64();
  g_last_beat.store(g_start_tick, std::memory_order_relaxed);

  if (!::DuplicateHandle(::GetCurrentProcess(), ::GetCurrentThread(),
                         ::GetCurrentProcess(), &g_main_thread,
                         THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT |
                             THREAD_QUERY_INFORMATION,
                         FALSE, 0)) {
    g_main_thread = nullptr;
  }

  RefreshModules();
  g_timer = ::SetTimer(nullptr, 0, kHeartbeatIntervalMs, HeartbeatProc);
  if (g_timer == 0) {
    if (g_main_thread != nullptr) {
      ::CloseHandle(g_main_thread);
      g_main_thread = nullptr;
    }
    g_started.store(false, std::memory_order_relaxed);
    return;
  }
  g_watcher = std::thread(WatcherLoop);
}

void RefreshModules() {
  const auto fresh = BuildModuleSnapshot();
  if (fresh != nullptr) {
    std::atomic_store_explicit(&g_modules, fresh, std::memory_order_release);
  }
}

void RequestStop() {
  g_stop.store(true, std::memory_order_relaxed);
  if (g_timer != 0) {
    ::KillTimer(nullptr, g_timer);
    g_timer = 0;
  }
}

void Stop() {
  RequestStop();
  if (g_watcher.joinable()) g_watcher.join();
  if (g_main_thread != nullptr) {
    ::CloseHandle(g_main_thread);
    g_main_thread = nullptr;
  }
  g_started.store(false, std::memory_order_relaxed);
}

}  // namespace startup_watchdog
