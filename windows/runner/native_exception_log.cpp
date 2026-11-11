#include "native_exception_log.h"

namespace native_exception_log {

namespace {

static_assert(std::atomic<DWORD>::is_always_lock_free);
std::atomic<DWORD> g_main_thread_id{0};
RecentRecords g_recent;

bool IsCrashCode(DWORD code) {
  switch (code) {
    case EXCEPTION_ACCESS_VIOLATION:
    case EXCEPTION_IN_PAGE_ERROR:
    case EXCEPTION_ILLEGAL_INSTRUCTION:
    case EXCEPTION_PRIV_INSTRUCTION:
    case EXCEPTION_STACK_OVERFLOW:
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
    case EXCEPTION_INT_OVERFLOW:
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:
    case EXCEPTION_DATATYPE_MISALIGNMENT:
    case EXCEPTION_NONCONTINUABLE_EXCEPTION:
    case EXCEPTION_INVALID_DISPOSITION:
    case 0xC0000374:  // STATUS_HEAP_CORRUPTION
      return true;
    default:
      return false;
  }
}

// אין לקרוא את מחסנית החריגה או לבצע פעולה שיכולה להמתין במטפל.
LONG CALLBACK OnException(EXCEPTION_POINTERS* info) {
  const EXCEPTION_RECORD* record = info->ExceptionRecord;
  if (record != nullptr && IsCrashCode(record->ExceptionCode) &&
      ::GetCurrentThreadId() == g_main_thread_id.load(std::memory_order_relaxed)) {
    ULONGLONG units = 0;
    if (::QueryUnbiasedInterruptTime(&units)) {
      g_recent.TryRecord({
          units / 10000,
          reinterpret_cast<std::uintptr_t>(record->ExceptionAddress),
          record->ExceptionCode,
      });
    }
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void Install(DWORD thread_id) {
  DWORD unregistered = 0;
  if (thread_id == 0 || !g_main_thread_id.compare_exchange_strong(
                            unregistered, thread_id, std::memory_order_relaxed)) {
    return;
  }
  if (::AddVectoredExceptionHandler(1, OnException) == nullptr) {
    g_main_thread_id.store(0, std::memory_order_relaxed);
  }
}

Snapshot ReadRecent() { return g_recent.TrySnapshot(); }

}  // namespace native_exception_log
