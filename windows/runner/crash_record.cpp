#include "crash_record.h"

#include <windows.h>

#include <atomic>
#include <cstdio>
#include <string>
#include <vector>

#include "startup_watchdog.h"

namespace crash_record {

namespace {

constexpr DWORD kWriteTimeoutMs = 3000;
constexpr size_t kMaxFrames = 64;

LPTOP_LEVEL_EXCEPTION_FILTER g_previous = nullptr;
std::atomic<bool> g_claimed{false};
HANDLE g_crash_event = nullptr;
HANDLE g_done_event = nullptr;
DWORD g_main_thread_id = 0;
DWORD g_crash_thread_id = 0;
EXCEPTION_RECORD g_record = {};
CONTEXT g_context = {};

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
  while (frames->size() < kMaxFrames && CR_PC(context) != 0) {
    frames->push_back(static_cast<ULONG_PTR>(CR_PC(context)));
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

void WriteRecord() {
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
            startup_watchdog::DescribeFrame(
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
  startup_watchdog::AppendReport(report);
}

// הכתיבה ב-thread נפרד: ב-stack overflow אין מקום, ונעילת loader תפוסה
// הייתה הופכת את הקריסה לתקיעה. המטפל ממתין לו עם תקרה.
DWORD WINAPI WriterThread(LPVOID) {
  ::WaitForSingleObject(g_crash_event, INFINITE);
  WriteRecord();
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
    ::WaitForSingleObject(g_done_event, kWriteTimeoutMs);
  }
  return g_previous != nullptr ? g_previous(info) : EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void Install() {
  if (g_crash_event != nullptr) return;
  g_main_thread_id = ::GetCurrentThreadId();
  g_crash_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_done_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_crash_event == nullptr || g_done_event == nullptr) return;
  HANDLE writer = ::CreateThread(nullptr, 256 * 1024, WriterThread, nullptr,
                                 STACK_SIZE_PARAM_IS_A_RESERVATION, nullptr);
  if (writer == nullptr) return;
  ::CloseHandle(writer);
  g_previous = ::SetUnhandledExceptionFilter(OnUnhandledException);
}

}  // namespace crash_record
