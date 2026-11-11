#ifndef RUNNER_NATIVE_EXCEPTION_LOG_H_
#define RUNNER_NATIVE_EXCEPTION_LOG_H_

#include <windows.h>

#include <vector>

// רושם חריגות נייטיב מסוג קריסה לחוצץ טבעתי סטטי, לפני ה-UEF של Sentry. VEH
// שנרשם אחרינו עם First (crashpad, ‏heap corruption) רץ לפנינו. לא כותב לדיסק.
namespace native_exception_log {

struct Record {
  LONG sequence = 0;
  DWORD code = 0;
  DWORD thread_id = 0;
  // QueryUnbiasedInterruptTime במילישניות, כמו שעון hang_monitor.
  ULONGLONG awake_ms = 0;
  ULONG_PTR address = 0;
  // ב-AV וב-IN_PAGE_ERROR: סוג הגישה (0 קריאה, 1 כתיבה, 8 הרצה) והכתובת.
  bool has_access = false;
  ULONG_PTR access_type = 0;
  ULONG_PTR access_address = 0;
  std::vector<ULONG_PTR> frames;
};

// רושם vectored exception handler בראש השרשרת הנוכחית. אידמפוטנטי.
void Install();

// הרשומות השמורות, מהישנה לחדשה. פורש מחסניות — אסור מתוך מטפל חריגות.
std::vector<Record> Snapshot();

const char* CodeName(DWORD code);

}  // namespace native_exception_log

#endif  // RUNNER_NATIVE_EXCEPTION_LOG_H_
