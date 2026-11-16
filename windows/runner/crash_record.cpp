#include "crash_record.h"

#include <windows.h>

#include <werapi.h>

#include <atomic>
#include <cstdio>
#include <string>
#include <vector>

#include "crash_wer_context.h"
#include "startup_watchdog.h"

namespace crash_record {

namespace {

constexpr DWORD kWriteTimeoutMs = 3000;
constexpr size_t kMaxFrames = 64;

LPTOP_LEVEL_EXCEPTION_FILTER g_previous = nullptr;
std::atomic<bool> g_claimed{false};
HANDLE g_crash_event = nullptr;
HANDLE g_done_event = nullptr;
HANDLE g_writer = nullptr;
DWORD g_main_thread_id = 0;
DWORD g_crash_thread_id = 0;
EXCEPTION_RECORD g_record = {};
CONTEXT g_context = {};
CrashWerContext g_wer = {};
std::string g_started_at;

#if defined(_M_X64) || defined(_M_ARM64)

#if defined(_M_X64)
#define CR_PC(ctx) ((ctx).Rip)
#define CR_SP(ctx) ((ctx).Rsp)
#else
#define CR_PC(ctx) ((ctx).Pc)
#define CR_SP(ctx) ((ctx).Sp)
#endif

// מחסנית פגומה מסתיימת בפרישה קטועה, לא בקריסה של ה-writer.
bool UnwindStep(CONTEXT* context) {
  __try {
    DWORD64 image_base = 0;
    PRUNTIME_FUNCTION function =
        ::RtlLookupFunctionEntry(CR_PC(*context), &image_base, nullptr);
    if (function == nullptr) {
#if defined(_M_X64)
      context->Rip = *reinterpret_cast<DWORD64*>(context->Rsp);
      context->Rsp += sizeof(DWORD64);
#else
      context->Pc = context->Lr;
#endif
      return true;
    }
    PVOID handler_data = nullptr;
    DWORD64 establisher_frame = 0;
    ::RtlVirtualUnwind(UNW_FLAG_NHANDLER, image_base, CR_PC(*context), function,
                       context, &handler_data, &establisher_frame, nullptr);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

void Unwind(CONTEXT context, std::vector<ULONG_PTR>* frames) {
  // PC 0 (קריאה דרך מצביע null): הצעד הראשון עדיין מגיע לקורא.
  while (frames->size() < kMaxFrames &&
         (CR_PC(context) != 0 || frames->empty())) {
    if (CR_PC(context) != 0) {
      frames->push_back(static_cast<ULONG_PTR>(CR_PC(context)));
    }
    const auto pc = CR_PC(context);
    const auto sp = CR_SP(context);
    if (!UnwindStep(&context)) break;
    if (CR_PC(context) == pc && CR_SP(context) == sp) break;
  }
}

#else

void Unwind(CONTEXT, std::vector<ULONG_PTR>*) {}

#endif

// במילישניות: הקריסה יכולה לקרות באותה שנייה שבה נכתבה נעילת ההפעלה.
std::string TimestampMs() {
  SYSTEMTIME utc = {};
  ::GetSystemTime(&utc);
  char buffer[40];
  snprintf(buffer, sizeof(buffer), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
           utc.wYear, utc.wMonth, utc.wDay, utc.wHour, utc.wMinute,
           utc.wSecond, utc.wMilliseconds);
  return buffer;
}

// שם המודול כפי שה-loader רשם אותו, כמו ב-minidump: אותה קריסה, אותה חתימה.
std::string DescribeFault(ULONG_PTR address) {
  HMODULE module = nullptr;
  wchar_t path[MAX_PATH] = {0};
  if (::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(address), &module)) {
    const DWORD length = ::GetModuleFileNameW(module, path, MAX_PATH);
    if (length > 0 && length < MAX_PATH) {
      const wchar_t* name = ::wcsrchr(path, L'\\');
      name = name == nullptr ? path : name + 1;
      char narrow[MAX_PATH * 3] = {0};
      if (::WideCharToMultiByte(CP_UTF8, 0, name, -1, narrow, sizeof(narrow),
                                nullptr, nullptr) > 0) {
        char offset[32];
        snprintf(offset, sizeof(offset), "+0x%llx",
                 static_cast<unsigned long long>(
                     address - reinterpret_cast<ULONG_PTR>(module)));
        return std::string(narrow) + offset;
      }
    }
  }
  return startup_watchdog::DescribeFrame(address);
}

bool WriteRecord() {
  std::vector<ULONG_PTR> frames;
  frames.reserve(kMaxFrames);
  Unwind(g_context, &frames);

  char line[160];
  std::string report = "\n=== Native crash " + TimestampMs() + " ===\n";
#ifdef FLUTTER_VERSION
  report += std::string("Version: ") + FLUTTER_VERSION + "\n";
#endif
  snprintf(line, sizeof(line), "Exception code: 0x%08lx\n",
           static_cast<unsigned long>(g_record.ExceptionCode));
  report += line;
  report += "Fault: " +
            DescribeFault(
                reinterpret_cast<ULONG_PTR>(g_record.ExceptionAddress)) +
            "\n";
  if (g_record.ExceptionCode == EXCEPTION_ACCESS_VIOLATION &&
      g_record.NumberParameters >= 2) {
    const ULONG_PTR kind = g_record.ExceptionInformation[0];
    snprintf(line, sizeof(line), "Access: %s 0x%llx\n",
             kind == 0 ? "read" : kind == 8 ? "execute" : "write",
             static_cast<unsigned long long>(g_record.ExceptionInformation[1]));
    report += line;
  }
  report += g_crash_thread_id == g_main_thread_id ? "Thread: main\n"
                                                  : "Thread: other\n";
  startup_watchdog::AppendBuildIdentity(frames, &report);
  startup_watchdog::AppendStack(frames, &report);
  return startup_watchdog::AppendReport(report);
}

std::wstring ExeDirectory() {
  wchar_t path[MAX_PATH] = {0};
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return std::wstring();
  std::wstring dir(path, length);
  return dir.substr(0, dir.find_last_of(L'\\'));
}

std::wstring LogsDirectory() {
  const std::wstring log = startup_watchdog::ErrorLogPath();
  const size_t slash = log.find_last_of(L'\\');
  return slash == std::wstring::npos ? std::wstring() : log.substr(0, slash);
}

// fastfail ו-heap corruption עוקפים את המטפל; רק WER מגיע אליהם, דרך המודול.
void CALLBACK RegisterWerModule(ULONG_PTR) {
  const std::wstring log = startup_watchdog::ErrorLogPath();
  if (log.empty() || log.size() >= ARRAYSIZE(g_wer.log_path)) return;
  ::wcscpy_s(g_wer.log_path, log.c_str());
  const std::wstring dll = ExeDirectory() + L"\\" OTZARIA_CRASH_WER_DLL;
  if (::GetFileAttributesW(dll.c_str()) == INVALID_FILE_ATTRIBUTES) return;
  // WER טוען רק מודול שרשום כאן; HKCU מספיק גם להתקנה למחשב כולו.
  constexpr wchar_t kKey[] =
      L"Software\\Microsoft\\Windows\\Windows Error Reporting\\"
      L"RuntimeExceptionHelperModules";
  if (::RegGetValueW(HKEY_CURRENT_USER, kKey, dll.c_str(), RRF_RT_REG_DWORD,
                     nullptr, nullptr, nullptr) != ERROR_SUCCESS) {
    const DWORD one = 1;
    if (::RegSetKeyValueW(HKEY_CURRENT_USER, kKey, dll.c_str(), REG_DWORD,
                          &one, sizeof(one)) != ERROR_SUCCESS) {
      return;
    }
  }
  ::WerRegisterRuntimeExceptionModule(dll.c_str(), &g_wer);
}

// נמחקת כש-Dart כותב את session.lock; נשארת אם התהליך מת לפני כן.
void CALLBACK WriteStartupLock(ULONG_PTR) {
  const std::wstring dir = LogsDirectory();
  if (dir.empty()) return;
  const size_t parent = dir.find_last_of(L'\\');
  if (parent != std::wstring::npos) {
    ::CreateDirectoryW(dir.substr(0, parent).c_str(), nullptr);
  }
  ::CreateDirectoryW(dir.c_str(), nullptr);
  const DWORD pid = ::GetCurrentProcessId();
  const std::wstring path =
      dir + L"\\startup-" + std::to_wstring(pid) + L".lock";
  char json[160];
  snprintf(json, sizeof(json),
           "{\"pid\":%lu,\"version\":\"%s\",\"startedAt\":\"%s\"}",
           static_cast<unsigned long>(pid), g_wer.version,
           g_started_at.c_str());
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  ::WriteFile(file, json, static_cast<DWORD>(strlen(json)), &written, nullptr);
  ::CloseHandle(file);
}

// הכתיבה ב-thread נפרד: ב-stack overflow אין מקום, ונעילת loader תפוסה
// הייתה הופכת את הקריסה לתקיעה. המטפל ממתין לו עם תקרה.
DWORD WINAPI WriterThread(LPVOID) {
  // ההמתנה מתעוררת גם למשימות העלייה שנשלחות אליו ב-APC.
  while (::WaitForSingleObjectEx(g_crash_event, INFINITE, TRUE) ==
         WAIT_IO_COMPLETION) {
  }
  // רק אחרי הכתיבה: writer שנכשל משאיר את הרישום למודול ה-WER.
  if (WriteRecord()) ::InterlockedExchange(&g_wer.recorded, 1);
  ::SetEvent(g_done_event);
  return 0;
}

LONG WINAPI OnUnhandledException(EXCEPTION_POINTERS* info) {
  if (info != nullptr && info->ExceptionRecord != nullptr &&
      info->ContextRecord != nullptr && !g_claimed.exchange(true)) {
    g_record = *info->ExceptionRecord;
    g_context = *info->ContextRecord;
    g_crash_thread_id = ::GetCurrentThreadId();
    ::SetEvent(g_crash_event);
  }
  // גם thread שני ממתין, אחרת WER מסיים את התהליך באמצע הכתיבה. writer שמת
  // (קריסה בתוך ExitProcess) משחרר את ההמתנה מיד.
  const HANDLE waits[] = {g_done_event, g_writer};
  ::WaitForMultipleObjects(2, waits, FALSE, kWriteTimeoutMs);
  return g_previous != nullptr ? g_previous(info) : EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void Install() {
  if (g_crash_event != nullptr) return;
  g_started_at = TimestampMs();
  g_main_thread_id = ::GetCurrentThreadId();
  g_wer.magic = CrashWerContext::kMagic;
  g_wer.size = sizeof(g_wer);
  g_wer.main_thread_id = g_main_thread_id;
#ifdef FLUTTER_VERSION
  ::strcpy_s(g_wer.version, FLUTTER_VERSION);
#endif
#ifdef OTZARIA_BUILD_COMMIT
  ::strcpy_s(g_wer.build_commit, OTZARIA_BUILD_COMMIT);
#endif
  g_crash_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_done_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_crash_event == nullptr || g_done_event == nullptr) return;
  g_writer = ::CreateThread(nullptr, 256 * 1024, WriterThread, nullptr,
                            STACK_SIZE_PARAM_IS_A_RESERVATION, nullptr);
  if (g_writer == nullptr) return;
  g_previous = ::SetUnhandledExceptionFilter(OnUnhandledException);
  ::QueueUserAPC(RegisterWerModule, g_writer, 0);
}

void BeginSession() {
  if (g_writer != nullptr) ::QueueUserAPC(WriteStartupLock, g_writer, 0);
}

}  // namespace crash_record
