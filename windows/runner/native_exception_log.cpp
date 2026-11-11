#include "native_exception_log.h"

#include <algorithm>
#include <cstring>

#include "startup_watchdog.h"

namespace native_exception_log {

namespace {

constexpr LONG kSlots = 8;
// מספיק לכ-48 פריימים; פרישה רק בדיווח, מעותק המחסנית.
constexpr size_t kStackBytes = 64 * 1024;
constexpr size_t kMaxFrames = 48;

#if defined(_M_X64)
#define NEL_PC(ctx) ((ctx).Rip)
#define NEL_SP(ctx) ((ctx).Rsp)
#elif defined(_M_ARM64)
#define NEL_PC(ctx) ((ctx).Pc)
#define NEL_SP(ctx) ((ctx).Sp)
#else
#define NEL_PC(ctx) ((ctx).Eip)
#define NEL_SP(ctx) ((ctx).Esp)
#endif

// CONTEXT מיושר ל-16, והריפוד שלפניו תלוי בארכיטקטורה (C4324 תחת /WX).
#pragma warning(push)
#pragma warning(disable : 4324)
struct Slot {
  // ה-thread שכותב כעת לתא, או 0. גם מונע כניסה חוזרת בלי TLS.
  volatile LONG owner;
  // 0 = ריק או באמצע כתיבה; אחרת מספר הרשומה.
  volatile LONG sequence;
  DWORD code;
  DWORD thread_id;
  DWORD parameter_count;
  ULONGLONG awake_ms;
  ULONG_PTR address;
  ULONG_PTR parameters[2];
  CONTEXT context;
  ULONG_PTR stack_sp;
  size_t stack_bytes;
  ULONG_PTR stack[kStackBytes / sizeof(ULONG_PTR)];
};
#pragma warning(pop)

Slot g_slots[kSlots];
volatile LONG g_next = 0;
PVOID g_handler = nullptr;

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
    // 0xC0000409 ו-0xC0000602 (fast fail) עוקפים VEH, ולכן אינם כאן.
    case 0xC0000374:  // STATUS_HEAP_CORRUPTION
      return true;
    default:
      return false;
  }
}

// תופס תא פנוי; nullptr כשה-thread כבר כותב (כניסה חוזרת) או שכל התאים תפוסים.
Slot* ClaimSlot(LONG thread_id, LONG sequence) {
  for (Slot& slot : g_slots) {
    if (slot.owner == thread_id) return nullptr;
  }
  for (LONG i = 0; i < kSlots; ++i) {
    Slot& slot = g_slots[static_cast<ULONG>(sequence - 1 + i) % kSlots];
    if (::InterlockedCompareExchange(&slot.owner, thread_id, 0) == 0) {
      return &slot;
    }
  }
  return nullptr;
}

// עלול לרוץ על ערימה פגומה או מחסנית כמעט מלאה: בלי הקצאות, נעילות, TLS או
// CRT מלבד memcpy, ותמיד ממשיך בחיפוש.
LONG CALLBACK OnException(EXCEPTION_POINTERS* info) {
  const EXCEPTION_RECORD* record = info->ExceptionRecord;
  if (record == nullptr || info->ContextRecord == nullptr ||
      !IsCrashCode(record->ExceptionCode)) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  const LONG thread_id = static_cast<LONG>(::GetCurrentThreadId());
  const LONG sequence = ::InterlockedIncrement(&g_next);
  Slot* claimed = ClaimSlot(thread_id, sequence);
  if (claimed == nullptr) return EXCEPTION_CONTINUE_SEARCH;
  Slot& slot = *claimed;
  ::InterlockedExchange(&slot.sequence, 0);

  slot.code = record->ExceptionCode;
  slot.thread_id = static_cast<DWORD>(thread_id);
  ULONGLONG units = 0;
  ::QueryUnbiasedInterruptTime(&units);
  slot.awake_ms = units / 10000;
  slot.address = reinterpret_cast<ULONG_PTR>(record->ExceptionAddress);
  slot.parameter_count = (std::min)(record->NumberParameters, DWORD{2});
  for (DWORD i = 0; i < slot.parameter_count; ++i) {
    slot.parameters[i] = record->ExceptionInformation[i];
  }
  memcpy(&slot.context, info->ContextRecord, sizeof(CONTEXT));

  // רק בתוך גבולות המחסנית מה-TEB: שם הדפים מוקצים, וההעתקה לא תיכשל.
  const NT_TIB* tib = reinterpret_cast<const NT_TIB*>(::NtCurrentTeb());
  const ULONG_PTR sp = static_cast<ULONG_PTR>(NEL_SP(slot.context));
  const ULONG_PTR low = reinterpret_cast<ULONG_PTR>(tib->StackLimit);
  const ULONG_PTR high = reinterpret_cast<ULONG_PTR>(tib->StackBase);
  size_t bytes = 0;
  if (sp >= low && sp < high) {
    bytes = (std::min)(static_cast<size_t>(high - sp), kStackBytes) &
            ~(sizeof(ULONG_PTR) - 1);
    memcpy(slot.stack, reinterpret_cast<const void*>(sp), bytes);
  }
  slot.stack_sp = sp;
  slot.stack_bytes = bytes;

  ::InterlockedExchange(&slot.sequence, sequence);
  ::InterlockedExchange(&slot.owner, 0);
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void Install() {
  if (g_handler == nullptr) {
    g_handler = ::AddVectoredExceptionHandler(1, OnException);
  }
}

std::vector<Record> Snapshot() {
  std::vector<Record> records;
  std::vector<ULONG_PTR> copy(
      (kStackBytes + startup_watchdog::kStackCopyPaddingBytes) /
      sizeof(ULONG_PTR));
  for (Slot& slot : g_slots) {
    const LONG before = ::InterlockedCompareExchange(&slot.sequence, 0, 0);
    if (before == 0) continue;
    Record record;
    record.sequence = before;
    record.code = slot.code;
    record.thread_id = slot.thread_id;
    record.awake_ms = slot.awake_ms;
    record.address = slot.address;
    if ((slot.code == EXCEPTION_ACCESS_VIOLATION ||
         slot.code == EXCEPTION_IN_PAGE_ERROR) &&
        slot.parameter_count == 2) {
      record.has_access = true;
      record.access_type = slot.parameters[0];
      record.access_address = slot.parameters[1];
    }
    CONTEXT context = slot.context;
    const ULONG_PTR sp = slot.stack_sp;
    const size_t bytes = (std::min)(slot.stack_bytes, kStackBytes);
    std::fill(copy.begin(), copy.end(), 0);
    memcpy(copy.data(), slot.stack, bytes);
    ::MemoryBarrier();
    // נדרסה בזמן ההעתקה.
    if (::InterlockedCompareExchange(&slot.sequence, 0, 0) != before) continue;

    startup_watchdog::UnwindStackCopy(&context, sp, copy.data(), bytes,
                                      &record.frames);
    if (record.frames.size() > kMaxFrames) record.frames.resize(kMaxFrames);
    records.push_back(std::move(record));
  }
  std::sort(records.begin(), records.end(),
            [](const Record& a, const Record& b) {
              return a.sequence < b.sequence;
            });
  return records;
}

const char* CodeName(DWORD code) {
  switch (code) {
    case EXCEPTION_ACCESS_VIOLATION: return "EXCEPTION_ACCESS_VIOLATION";
    case EXCEPTION_IN_PAGE_ERROR: return "EXCEPTION_IN_PAGE_ERROR";
    case EXCEPTION_ILLEGAL_INSTRUCTION: return "EXCEPTION_ILLEGAL_INSTRUCTION";
    case EXCEPTION_PRIV_INSTRUCTION: return "EXCEPTION_PRIV_INSTRUCTION";
    case EXCEPTION_STACK_OVERFLOW: return "EXCEPTION_STACK_OVERFLOW";
    case EXCEPTION_INT_DIVIDE_BY_ZERO: return "EXCEPTION_INT_DIVIDE_BY_ZERO";
    case EXCEPTION_INT_OVERFLOW: return "EXCEPTION_INT_OVERFLOW";
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "EXCEPTION_ARRAY_BOUNDS_EXCEEDED";
    case EXCEPTION_DATATYPE_MISALIGNMENT: return "EXCEPTION_DATATYPE_MISALIGNMENT";
    case EXCEPTION_NONCONTINUABLE_EXCEPTION:
      return "EXCEPTION_NONCONTINUABLE_EXCEPTION";
    case EXCEPTION_INVALID_DISPOSITION: return "EXCEPTION_INVALID_DISPOSITION";
    case 0xC0000374: return "STATUS_HEAP_CORRUPTION";
    default: return "UNKNOWN";
  }
}

}  // namespace native_exception_log
