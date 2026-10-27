#include "flutter_window.h"

#include <commctrl.h>
#include <dwmapi.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cwchar>
#include <limits>
#include <optional>
#include <string>
#include <thread>

#include <cstdlib>

#include "flutter/generated_plugin_registrant.h"
#include "accessibility_request_filter.h"
#include "drag_preview_window.h"
#include "phantom_mouse_button_filter.h"
#include "shift_key_normalizer.h"
#include "splash_window.h"
#include "hang_monitor.h"
#include "startup_watchdog.h"
#include "utils.h"

namespace {

// ── דיאגנוסטיקה של סיום סשן (כיבוי / יציאת משתמש) ────────────────────────
//
// כותבת ל-`%TEMP%\otzaria_session_end.log`. המסלול הזה אינו ניתן לבדיקה
// אוטומטית — מריצים אותו רק כיבוי אמיתי — ולכן שורת לוג היא האמצעי היחיד
// לאבחון תלונה עתידית של "הכרטיסיות שלי לא נשמרו בכיבוי". השורות:
//
//   flush-begin / flush-ok / flush-timeout   מצב השטיפה
//   session-ending / session-cancelled       מה המערכת החליטה בסוף
//   swallowed-by-flutter                     גלאי רגרסיה, ראו MessageHandler
//
// כותבת גם ל-OutputDebugStringW, לניפוי חי ב-DebugView.
void LogSessionEndDiagnostic(const wchar_t* stage, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  wchar_t buffer[200];
  _snwprintf_s(buffer, _TRUNCATE,
               L"Otzaria[session-end] %ls msg=%ls wparam=%llu lparam=0x%llX\n", stage,
               message == WM_QUERYENDSESSION ? L"WM_QUERYENDSESSION"
                                             : L"WM_ENDSESSION",
               static_cast<unsigned long long>(wparam),
               static_cast<unsigned long long>(lparam));
  OutputDebugStringW(buffer);

  // גם לקובץ, ולא רק ל-OutputDebugStringW: קריאת הפלט של OutputDebugString
  // מחייבת DebugView שרץ כמנהל, ומשתמש שמדווח על תקלה לא יעשה זאת. הדפוס
  // זהה ל-`_logForceTerminateFailure` שכותב ל-%TEMP%.
  //
  // ⚠️ פתיחה וסגירה בכל שורה, ולא handle מתמשך: הקוד הזה רץ בזמן כיבוי,
  // ובאפר שלא נשטף לפני שהמערכת הורגת אותנו הופך את הלוג לחסר ערך בדיוק
  // במקרה שבגללו הוא קיים.
  wchar_t temp_path[MAX_PATH];
  const DWORD temp_len = GetTempPathW(MAX_PATH, temp_path);
  if (temp_len == 0 || temp_len > MAX_PATH) {
    return;
  }
  std::wstring log_path(temp_path);
  log_path += L"otzaria_session_end.log";

  const HANDLE file =
      CreateFileW(log_path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                  OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  const std::string utf8 = Utf8FromUtf16(buffer);
  DWORD written = 0;
  WriteFile(file, utf8.data(), static_cast<DWORD>(utf8.size()), &written,
            nullptr);
  CloseHandle(file);
}

// כמה זמן מחכים ל-Dart לפני שמוותרים ומאשרים את סיום הסשן. Windows נותן
// לאפליקציה מספר שניות להשיב ל-WM_QUERYENDSESSION לפני שהיא מסומנת כלא-
// מגיבה ומוצגת למשתמש כמעכבת כיבוי. שלוש שניות מספיקות לשטיפת Hive וקצרות
// דיין שלא ייראו כתקיעה.
constexpr DWORD kSessionEndFlushTimeoutMs = 3000;

// דדליין אחד לשטיפת סיום הסשן, גם כש-WM_QUERYENDSESSION מגיע כמה פעמים.
// 0 = עוד לא התחיל; מתאפס כשהכיבוי מבוטל (`shutdown /a`).
ULONGLONG g_session_end_deadline = 0;

// חלון-ההודעות של תור המשימות של Flutter, אם הוא שייך ל-thread הזה.
//
// `TaskRunnerWindow` מפרסם `WM_NULL` ומשתמש ב-`SetTimer` כדי להריץ את תורי
// המשימות של המנוע, ולכן שאיבה **ממנו בלבד** מריצה את ה-Dart בלי לגעת
// בהודעות של חלונות אחרים. `HWND_MESSAGE` מחזיר חלונות של כל התהליכים,
// ולכן חובה לאמת גם תהליך וגם thread.
//
// שם המחלקה הוא פרט פנימי של המנוע ועלול להשתנות בשדרוג. כשלא נמצא —
// נופלים לשאיבה לפי **סוג הודעה** (posted/timer בלבד), שגם היא חוסמת קלט
// ו-WM_PAINT מלהיכנס re-entrantly.
HWND FindFlutterTaskRunnerWindow() {
  const DWORD our_pid = GetCurrentProcessId();
  const DWORD our_tid = GetCurrentThreadId();
  HWND hwnd = nullptr;
  while ((hwnd = FindWindowExW(HWND_MESSAGE, hwnd, L"FlutterTaskRunnerWindow",
                               nullptr)) != nullptr) {
    DWORD pid = 0;
    const DWORD tid = GetWindowThreadProcessId(hwnd, &pid);
    if (pid == our_pid && tid == our_tid) {
      return hwnd;
    }
  }
  return nullptr;
}

// מפעיל/מבטל DWM cloaking: החלון נשאר "מוצג" מבחינת המערכת (WS_VISIBLE,
// מיקסום, פוקוס והצגת פריימים עובדים כרגיל) אבל ה-DWM לא מצייר אותו כלל.
// ביטול ה-cloak הוא אטומי — פריים קומפוזיציה אחד עם התוכן העדכני.
void SetWindowCloaked(HWND hwnd, bool cloaked) {
  if (!hwnd) {
    return;
  }
  BOOL value = cloaked ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, &value, sizeof(value));
}

// מגדיר את מגבלות ה-Job ומשייך אליו את התהליך. מחזיר true בהצלחה; במקרה
// כשל ממלא |failure| וסוגר את ה-handle.
bool ConfigureProcessJob(HANDLE job, std::string& failure) {
  // BREAKAWAY_OK: ילד שנוצר עם CREATE_BREAKAWAY_FROM_JOB מתנתק מה-Job
  // ושורד את סגירת אוצריא (מתקין העדכון); ילדים רגילים (WebView2) נשארים
  // מוכלים ונהרגים בסגירה כרצוי.
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{};
  info.BasicLimitInformation.LimitFlags =
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info,
                               sizeof(info))) {
    failure = "SetInformationJobObject failed (error " +
              std::to_string(GetLastError()) + ")";
    OutputDebugStringW(L"Otzaria: SetInformationJobObject failed; not "
                       L"honouring forceTerminate.\n");
    CloseHandle(job);
    return false;
  }
  if (!AssignProcessToJobObject(job, GetCurrentProcess())) {
    failure = "AssignProcessToJobObject failed (error " +
              std::to_string(GetLastError()) +
              "); likely already in a non-nestable job";
    // The most common failure mode: the launching environment (debugger,
    // sandbox, AppContainer, certain enterprise/MDM tooling) has already
    // placed our process in a non-nestable job. We have no way to break
    // out, so we discard the job we created and stay on the graceful
    // close path — forceTerminate will report not-ready and Dart will
    // fall back to windowManager.destroy() + exit(0).
    OutputDebugStringW(L"Otzaria: AssignProcessToJobObject failed; likely "
                       L"already in a non-nestable job. Falling back to "
                       L"graceful shutdown on close.\n");
    CloseHandle(job);
    return false;
  }
  return true;
}

// הודעה פרטית שמבקשת למסור ל-Windows את המשך גרירת הכרטיסיה.
// ראו `drag_preview::DragWithSystem`.
constexpr UINT kMsgDragOutToSystem = WM_APP + 0x103;

// הראשי תמיד במשבצת 1; Dart מזהה אותו בגרירה לפי `slot` שאינו null.
constexpr int kMainWindowSlot = 1;

// מסירת גרירה חייבת לקרות בתוך אזור זה, בעוד הסמן נע מעלה אל Snap Layouts.
// Dart מוודא שהסמן כבר יצא מרצועת הכרטיסיות.
constexpr int kTopApproachLogicalHeight = 28;

// נסיעת מינימום ליציאה מעלה, באותן יחידות לוגיות של אזור ההתקרבות.
constexpr int kUpwardTravelLogical = 24;

// מתאר את היעד שתחת הסמן, בשפה ש-Dart מבין.
//
// ⚠️ עוזר משותף ל-`windowAtCursor` ול-`dragOutToSystem`, ובמכוון: שני
// המסלולים מקבלים את אותה החלטה — "מה נמצא שם" — ושתי גרסאות שלה היו
// נפרדות בשקט ברגע שאחת מהן משתנה.
// [report_hwnd] (חלונות Dart): גם ה-HWND שתחת הסמן, ו-isSelf מול [self] בכל חלון.
flutter::EncodableMap DescribeTarget(HWND under, POINT cursor, HWND self,
                                     HWND main, bool report_hwnd = false) {
  flutter::EncodableMap info;
  info[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<int>(cursor.x));
  info[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<int>(cursor.y));

  // ⚠️ שורת המשימות מדווחת בנפרד. היא נגישה גם כשהחלון ממוקסם, ולכן
  // שחרור עליה הוא כמעט תמיד החטאה ולא בקשה לפתוח חלון — ומשתמש בחלון
  // יחיד שאינו מכיר את הפיצ'ר גילה פתאום חלון שני.
  wchar_t class_name[64] = {0};
  if (under) {
    ::GetClassNameW(under, class_name,
                    sizeof(class_name) / sizeof(class_name[0]));
  }
  const bool is_shell_tray =
      ::wcscmp(class_name, L"Shell_TrayWnd") == 0 ||
      ::wcscmp(class_name, L"Shell_SecondaryTrayWnd") == 0 ||
      ::wcscmp(class_name, L"TopLevelWindowForOverflowXamlIsland") == 0;
  info[flutter::EncodableValue("isShellTray")] =
      flutter::EncodableValue(is_shell_tray);

  // בודקים את הצג שמתחת לסמן, כולל אזור העבודה לשורת משימות עליונה.
  bool approaching_top = false;
  bool in_work_area = false;
  int upward_travel = kUpwardTravelLogical;
  const HMONITOR monitor = ::MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (monitor && ::GetMonitorInfoW(monitor, &monitor_info)) {
    // גבולות הצג והסף חייבים להשתמש באותו DPI.
    UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
    if (dpi == 0) dpi = self ? ::GetDpiForWindow(self) : 96;
    if (dpi == 0) dpi = 96;
    const int band = ::MulDiv(kTopApproachLogicalHeight, dpi, 96);
    upward_travel = ::MulDiv(kUpwardTravelLogical, dpi, 96);
    approaching_top = cursor.y - monitor_info.rcMonitor.top <= band ||
                      cursor.y - monitor_info.rcWork.top <= band;
    // הצגים אינם חופפים: נקודה מחוץ לאזור העבודה של הקרוב היא מחוץ לכולם.
    in_work_area = ::PtInRect(&monitor_info.rcWork, cursor) != FALSE;
  }
  info[flutter::EncodableValue("approachingTop")] =
      flutter::EncodableValue(approaching_top);
  info[flutter::EncodableValue("minUpwardTravel")] =
      flutter::EncodableValue(upward_travel);

  if (under != nullptr && under == main && ::IsWindowVisible(under)) {
    info[flutter::EncodableValue("slot")] =
        flutter::EncodableValue(kMainWindowSlot);
    info[flutter::EncodableValue("isSelf")] =
        flutter::EncodableValue(under == self);
  }
  if (report_hwnd) {
    if (under) {
      info[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(
          static_cast<int64_t>(reinterpret_cast<intptr_t>(under)));
    }
    info[flutter::EncodableValue("isSelf")] =
        flutter::EncodableValue(under != nullptr && under == self);
  }
  // שורת משימות או appbar גם כשהמחלקה אינה מזוהה כ-`isShellTray`.
  info[flutter::EncodableValue("inWorkArea")] =
      flutter::EncodableValue(in_work_area);
  return info;
}

// HWND שהגיע מ-Dart, רק אם הוא חלון חי של התהליך הזה; אחרת nullptr.
HWND OwnWindowArg(const flutter::EncodableValue* arguments, const char* key) {
  const auto* args = std::get_if<flutter::EncodableMap>(arguments);
  if (!args) return nullptr;
  const auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return nullptr;
  int64_t raw = 0;
  if (const auto* wide = std::get_if<int64_t>(&it->second)) {
    raw = *wide;
  } else if (const auto* narrow = std::get_if<int>(&it->second)) {
    raw = *narrow;
  } else {
    return nullptr;
  }
  const HWND hwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(raw));
  if (!hwnd || !::IsWindow(hwnd)) return nullptr;
  DWORD pid = 0;
  ::GetWindowThreadProcessId(hwnd, &pid);
  return pid == ::GetCurrentProcessId() ? hwnd : nullptr;
}

// ⚠️ לולאת ההזזה של Windows כולאת את הסמן באזור העבודה, ולכן שחרור מעל
// שורת המשימות נמדד בשורה האחרונה שלו, מעל מה שנמצא שם (BUG-7).
bool HeldAtReservedEdge(POINT cursor) {
  constexpr int kTolerance = 2;
  const HMONITOR monitor = ::MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  if (!monitor || !::GetMonitorInfoW(monitor, &mi)) return false;
  const RECT& work = mi.rcWork;
  const RECT& mon = mi.rcMonitor;
  if (!::PtInRect(&work, cursor)) return false;
  return (work.bottom < mon.bottom && cursor.y >= work.bottom - kTolerance) ||
         (work.top > mon.top && cursor.y < work.top + kTolerance) ||
         (work.left > mon.left && cursor.x < work.left + kTolerance) ||
         (work.right < mon.right && cursor.x >= work.right - kTolerance);
}

// מתאר גרירה שהמערכת ניהלה: היעד, והמסגרת שהמשתמש עצר בה.
flutter::EncodableValue DescribeSystemDrag(
    const drag_preview::SystemDragResult& drag, HWND self, HWND main,
    bool report_hwnd = false) {
  flutter::EncodableMap info =
      DescribeTarget(drag.under, drag.cursor, self, main, report_hwnd);
  info[flutter::EncodableValue("ran")] = flutter::EncodableValue(drag.ran);
  info[flutter::EncodableValue("atTaskbarEdge")] =
      flutter::EncodableValue(drag.ran && HeldAtReservedEdge(drag.cursor));
  // ⚠️ `snapped` הוא מה שמבדיל בין "פתח כאן" לבין "פתח **במסגרת הזו**".
  // התצוגה היא בגודל כרטיסיה, ושימוש עיוור במסגרת היה יוצר חלון אוצריא
  // של 176×40.
  info[flutter::EncodableValue("snapped")] =
      flutter::EncodableValue(drag.snapped);
  info[flutter::EncodableValue("left")] =
      flutter::EncodableValue(static_cast<int>(drag.rect.left));
  info[flutter::EncodableValue("top")] =
      flutter::EncodableValue(static_cast<int>(drag.rect.top));
  info[flutter::EncodableValue("width")] =
      flutter::EncodableValue(static_cast<int>(drag.rect.right -
                                               drag.rect.left));
  info[flutter::EncodableValue("height")] =
      flutter::EncodableValue(static_cast<int>(drag.rect.bottom -
                                               drag.rect.top));
  return flutter::EncodableValue(info);
}

// חלון שנוצר מ-Dart (ריבוי תצוגות). חי על המנוע של החלון הראשי, באותו thread.
bool IsDartHostWindow(HWND hwnd) {
  wchar_t name[32] = {};
  return ::GetClassNameW(hwnd, name, ARRAYSIZE(name)) > 0 &&
         wcscmp(name, L"FLUTTER_HOST_WINDOW") == 0;
}

BOOL CALLBACK FindVisibleDartHostWindow(HWND hwnd, LPARAM found) {
  if (!::IsWindowVisible(hwnd) || !IsDartHostWindow(hwnd)) return TRUE;
  *reinterpret_cast<bool*>(found) = true;
  return FALSE;
}

bool HasVisibleDartHostWindow() {
  bool found = false;
  ::EnumThreadWindows(::GetCurrentThreadId(), FindVisibleDartHostWindow,
                      reinterpret_cast<LPARAM>(&found));
  return found;
}

// מתקין על תצוגת Flutter של חלון Dart את אותם תיקוני קלט של החלון הראשי.
// רק חלון Dart של ה-thread הזה; התקנה חוזרת אינה עושה דבר.
bool InstallDartViewHooks(HWND root) {
  if (!::IsWindow(root) || !IsDartHostWindow(root) ||
      ::GetWindowThreadProcessId(root, nullptr) != ::GetCurrentThreadId()) {
    return false;
  }
  const HWND view = ::FindWindowExW(root, nullptr, L"FLUTTERVIEW", nullptr);
  if (!view) return false;
  InstallPhantomMouseButtonFilter(view);
  InstallShiftKeyNormalizer(view);
  InstallAccessibilityRequestFilter(view);
  return true;
}

constexpr UINT_PTR kFramelessSubclassId = 0x0F1F;

// כמו `IsWindows11OrGreater` של window_manager: ב-10 נשאר פס עליון של פיקסל.
bool IsWindows11OrGreaterForFrame() {
#pragma warning(push)
#pragma warning(disable : 4996)
  const DWORD version = ::GetVersion();
#pragma warning(pop)
  const DWORD build = version < 0x80000000 ? HIWORD(version) : 0;
  return build >= 22000;
}

// `adjustNCCALCSIZE` של window_manager: חלון ממוקסם ממלא את אזור העבודה.
void AdjustMaximizedClientRect(NCCALCSIZE_PARAMS* sz) {
  LONG l = 8;
  LONG t = 8;
  const HMONITOR monitor =
      ::MonitorFromRect(&sz->rgrc[0], MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(MONITORINFO)};
  if (monitor && ::GetMonitorInfo(monitor, &info)) {
    l = sz->rgrc[0].left - info.rcWork.left;
    t = sz->rgrc[0].top - info.rcWork.top;
  }
  sz->rgrc[0].left -= l;
  sz->rgrc[0].top -= t;
  sz->rgrc[0].right += l;
  sz->rgrc[0].bottom += t;
}

// מה ש-window_manager עושה לחלון הראשי ב-`TitleBarStyle.hidden`, לחלון Dart.
// בלי WS_THICKFRAME (מסך מלא של ה-engine) הכול עובר כרגיל.
LRESULT CALLBACK FramelessViewProc(HWND hwnd, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR, DWORD_PTR) {
  const bool framed =
      (::GetWindowLongPtr(hwnd, GWL_STYLE) & WS_THICKFRAME) != 0;
  switch (message) {
    case WM_NCCALCSIZE:
      if (wparam && framed) {
        auto* sz = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        if (::IsZoomed(hwnd)) {
          AdjustMaximizedClientRect(sz);
        } else {
          sz->rgrc[0].top += IsWindows11OrGreaterForFrame() ? 0 : 1;
          sz->rgrc[0].right -= 8;
          sz->rgrc[0].bottom -= 8;
          sz->rgrc[0].left += 8;
        }
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      if (framed) return 1;
      break;
    case WM_NCDESTROY:
      ::RemoveWindowSubclass(hwnd, FramelessViewProc, kFramelessSubclassId);
      break;
  }
  return ::DefSubclassProc(hwnd, message, wparam, lparam);
}

// חלון Dart בלי כותרת, כמו החלון הראשי. רק חלון Dart של ה-thread הזה.
bool InstallFramelessViewFrame(HWND root) {
  if (!::IsWindow(root) || !IsDartHostWindow(root) ||
      ::GetWindowThreadProcessId(root, nullptr) != ::GetCurrentThreadId()) {
    return false;
  }
  DWORD_PTR existing = 0;
  if (::GetWindowSubclass(root, FramelessViewProc, kFramelessSubclassId,
                          &existing)) {
    return true;
  }
  if (!::SetWindowSubclass(root, FramelessViewProc, kFramelessSubclassId, 0)) {
    return false;
  }
  // כמו `SetTitleBarStyle`: מאפס את הרחבת ה-DWM ומחשב מחדש את המסגרת.
  const MARGINS margins = {0, 0, 0, 0};
  ::DwmExtendFrameIntoClientArea(root, &margins);
  ::SetWindowPos(root, nullptr, 0, 0, 0, 0,
                 SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_NOSIZE |
                     SWP_NOACTIVATE | SWP_FRAMECHANGED);
  return true;
}

// ה-HWND מארגומנט `{hwnd}` של הערוץ; 0 כשחסר או אינו מספר.
HWND HwndArgument(const flutter::EncodableValue* arguments) {
  const auto* args = std::get_if<flutter::EncodableMap>(arguments);
  if (!args) return nullptr;
  const auto it = args->find(flutter::EncodableValue("hwnd"));
  if (it == args->end()) return nullptr;
  int64_t hwnd = 0;
  if (const auto* wide = std::get_if<int64_t>(&it->second)) {
    hwnd = *wide;
  } else if (const auto* narrow = std::get_if<int>(&it->second)) {
    hwnd = *narrow;
  }
  return reinterpret_cast<HWND>(static_cast<intptr_t>(hwnd));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool headless)
    : project_(project), headless_(headless) {
  // Create a Job Object early — before any child processes can spawn. We
  // assign our own process to it with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
  // so that *any* child process created from this point onward (WebView2's
  // msedgewebview2.exe browser/GPU/renderer/utility processes, in particular)
  // is automatically terminated when the job is closed — which happens
  // when this process dies, including via TerminateProcess.
  //
  // The Job Object is the standard Win32 mechanism for containing process
  // trees; without it, WebView2's Edge child processes have been observed
  // orphaning after fast-exit shutdown (13 zombie msedgewebview2.exe
  // instances persisting for days, holding the user data folder locked and
  // breaking subsequent WebView2 initialization with a silent blank-tab
  // failure).
  //
  // ⚠️ ה-Job שייך לתהליך ואינו נסגר לעולם: סגירת ה-handle מפעילה
  // `KILL_ON_JOB_CLOSE` גם עלינו. היציאה סוגרת אותו בדיוק בזמן הנכון.
  static std::once_flag job_once;
  static HANDLE process_job = nullptr;
  static std::string process_job_failure;

  std::call_once(job_once, [&]() {
    process_job = CreateJobObjectW(nullptr, nullptr);
    if (!process_job) {
      process_job_failure = "CreateJobObjectW failed (error " +
                            std::to_string(GetLastError()) + ")";
      OutputDebugStringW(L"Otzaria: CreateJobObjectW failed; Edge child "
                         L"processes will not be contained on fast-exit.\n");
      return;
    }
    if (!ConfigureProcessJob(process_job, process_job_failure)) {
      process_job = nullptr;
    }
  });

  job_object_failure_ = process_job_failure;
  job_object_ready_.store(process_job != nullptr &&
                          process_job_failure.empty());
}

FlutterWindow::~FlutterWindow() {
  // ⚠️ reset() מאפס את המצביע לפני ההריסה: הריסת חלון-הילד שולחת WM_PARENTNOTIFY
  // לחלון הראשי החי, ו-MessageHandler היה מפנה אותה ל-controller שבאמצע פירוק.
  flutter_controller_.reset();
  // ה-Job אינו נסגר כאן — ראו הקונסטרוקטור.
  if (session_end_flush_event_) {
    CloseHandle(session_end_flush_event_);
    session_end_flush_event_ = nullptr;
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  // ערוץ החלונות: סגירה והעלאה של הראשי, גרירת כרטיסיות ועזרים לחלונות Dart.
  multiwindow_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "otzaria/multiwindow",
          &flutter::StandardMethodCodec::GetInstance());
  multiwindow_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        // סוגר את החלון הזה, בדחייה לאיטרציה הבאה של לולאת ההודעות.
        //
        // ⚠️ `windowManager.destroy()` קורא ל-`DestroyWindow` מתוך טיפול
        // בערוץ, כלומר מתוך ריצת ה-Dart של החלון — הריסת המנוע משם היא
        // ריאנטרנטית ומפילה את התהליך. ראו `kMsgDeferredDestroy`.
        if (call.method_name() == "closeSelf") {
          const HWND self = GetHandle();
          if (self) ::PostMessageW(self, kMsgDeferredDestroy, 0, 0);
          result->Success();
          return;
        }
        // איזה חלון אוצריא נמצא תחת הסמן, אם בכלל.
        //
        // ⚠️ `WindowFromPoint` מחזיר את החלון הפנימי ביותר — בדרך כלל
        // ה-view של Flutter או חלון של WebView2 — ולכן חובה לעלות ל-root.
        // בלי זה שחרור מעל תוכן הספר לא היה מזוהה כשחרור מעל החלון.
        if (call.method_name() == "windowAtCursor") {
          POINT cursor{};
          ::GetCursorPos(&cursor);
          // ⚠️ `drag_preview::WindowUnderCursor` ולא `WindowFromPoint`
          // ישירות: התצוגה אינה `WS_EX_TRANSPARENT` יותר (בלי זה ה-shell
          // אינו רואה בה חלון שנגרר, ואין Snap Layouts), ולכן היא הייתה
          // מחזירה את עצמה כיעד וכל שחרור מעל חלון אחר לא היה מזוהה.
          const HWND under = drag_preview::WindowUnderCursor(cursor);
          // ארגומנטים רק מחלונות Dart: בלעדיהם התשובה זהה לזו של היום.
          const bool report_hwnd =
              std::get_if<flutter::EncodableMap>(call.arguments()) != nullptr;
          const HWND self = OwnWindowArg(call.arguments(), "selfHwnd");
          result->Success(flutter::EncodableValue(DescribeTarget(
              under, cursor, self ? self : GetHandle(), GetHandle(),
              report_hwnd)));
          return;
        }

        // תצוגת הגרירה הנייטיבית — הכרטיסיה שנראית מחוץ לחלון.
        if (call.method_name() == "beginTabDrag") {
          std::string title;
          drag_preview::Colors colors;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto title_it = args->find(flutter::EncodableValue("title"));
            if (title_it != args->end()) {
              if (const auto* v = std::get_if<std::string>(&title_it->second)) {
                title = *v;
              }
            }
            // הצבעים מגיעים כ-ARGB מ-`colorScheme`; GDI רוצה BGR.
            //
            // ⚠️ `int64_t` וגם `int`. צבע אטום הוא `0xFF......` — כלומר
            // גדול מ-`INT32_MAX` — ו-`StandardMessageCodec` מקודד אותו
            // כ-int64. `get_if<int>` לבדו החזיר null לכל צבע אטום, ולכן
            // `colors.valid` היה תמיד false והתצוגה נצבעה בפלטה הבהירה
            // המוטמעת — גם בערכת נושא כהה.
            const auto read = [&](const char* key, COLORREF* out) -> bool {
              const auto it = args->find(flutter::EncodableValue(key));
              if (it == args->end()) return false;
              int64_t argb_value = 0;
              if (const auto* wide = std::get_if<int64_t>(&it->second)) {
                argb_value = *wide;
              } else if (const auto* narrow = std::get_if<int>(&it->second)) {
                argb_value = *narrow;
              } else {
                return false;
              }
              const unsigned argb = static_cast<unsigned>(argb_value);
              *out = RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
              return true;
            };
            colors.valid = read("tab", &colors.tab) &&
                           read("border", &colors.border) &&
                           read("text", &colors.text);
          } else if (const auto* legacy =
                         std::get_if<std::string>(call.arguments())) {
            // מסלול תאימות: הערוץ קיבל מחרוזת בלבד עד שהצבעים נוספו.
            title = *legacy;
          }
          // חלון המקור מועבר במפורש: התצוגה מוסתרת רק מעליו, ולא מעל
          // חלונות אוצריא אחרים. ראו ההערה ב-`drag_preview::Begin`.
          const HWND source = OwnWindowArg(call.arguments(), "sourceHwnd");
          drag_preview::Begin(drag_preview::Utf16FromUtf8(title),
                              source ? source : GetHandle(), colors);
          result->Success();
          return;
        }
        // עוצר את המעקב ומשאיר את התצוגה במקום השחרור, עד שהחלון האמיתי
        // נחשף. ראו `drag_preview::Freeze`.
        // התמונה האמיתית של הכרטיסיה, מ-`RepaintBoundary` בצד Dart.
        if (call.method_name() == "setTabDragImage") {
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto get_int = [&](const char* key, int fallback) {
              const auto it = args->find(flutter::EncodableValue(key));
              if (it == args->end()) return fallback;
              const auto* v = std::get_if<int>(&it->second);
              return v ? *v : fallback;
            };
            const auto bytes_it = args->find(flutter::EncodableValue("bytes"));
            if (bytes_it != args->end()) {
              if (const auto* bytes =
                      std::get_if<std::vector<uint8_t>>(&bytes_it->second)) {
                drag_preview::SetImage(
                    bytes->data(), bytes->size(), get_int("width", 0),
                    get_int("height", 0), get_int("targetWidth", 0),
                    get_int("targetHeight", 0));
              }
            }
          }
          result->Success();
          return;
        }
        // מסירת הגרירה ל-Windows — כך מגיעים Snap Layouts.
        //
        // ⚠️ הבקשה מתפרסמת ולא מבוצעת כאן: `DragWithSystem` נכנס ללולאה
        // מודאלית שנמשכת כל זמן הגרירה, וחסימה כזו מתוך טיפול בערוץ היא
        // ריאנטרנטית. התשובה נשלחת מלולאת ההודעות, עם המסגרת הסופית.
        if (call.method_name() == "dragOutToSystem") {
          // ⚠️ בלי handle ההודעה נשלחת ל-**thread** ולא לחלון, ואז
          // `MessageHandler` לא יראה אותה לעולם — הבקשה נשארת בתור
          // וה-`Future` בצד Dart תלוי בלי timeout.
          const HWND self = GetHandle();
          if (self == nullptr) {
            result->Success(DescribeSystemDrag(
                drag_preview::SystemDragResult{}, nullptr, nullptr));
            return;
          }
          const HWND source = OwnWindowArg(call.arguments(), "selfHwnd");
          pending_system_drags_.push(PendingSystemDrag{
              std::move(result), source,
              std::get_if<flutter::EncodableMap>(call.arguments()) != nullptr});
          ::PostMessageW(self, kMsgDragOutToSystem, 0, 0);
          return;
        }
        if (call.method_name() == "freezeTabDrag") {
          drag_preview::Freeze();
          result->Success();
          return;
        }
        if (call.method_name() == "endTabDrag") {
          drag_preview::End();
          result->Success();
          return;
        }

        // Ctrl+Shift+T כשהראשי נסגר: הוא מוסתר ולא נהרס, ולכן השחזור הוא הצגה.
        if (call.method_name() == "restoreLastClosedWindow") {
          result->Success(flutter::EncodableValue(RestoreClosedWindow()));
          return;
        }

        // ממיר נקודת מסך לקואורדינטות אזור-הלקוח של החלון הזה.
        //
        // ⚠️ ההמרה בנייטיב ולא ב-Dart: המיקום מגיע מחלון אחר, ו-Flutter
        // אינו יודע היכן החלון שלו יושב על המסך. חישוב ידני עם DPI היה
        // ניחוש; `ScreenToClient` הוא התשובה המדויקת.
        if (call.method_name() == "screenToClient") {
          POINT pt{};
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto x_it = args->find(flutter::EncodableValue("x"));
            const auto y_it = args->find(flutter::EncodableValue("y"));
            if (x_it != args->end()) {
              if (const auto* v = std::get_if<int>(&x_it->second)) pt.x = *v;
            }
            if (y_it != args->end()) {
              if (const auto* v = std::get_if<int>(&y_it->second)) pt.y = *v;
            }
          }
          // חלון Dart מעביר את ה-HWND שלו; בלעדיו — החלון הזה.
          const HWND target = OwnWindowArg(call.arguments(), "hwnd");
          if (const HWND self = target ? target : GetHandle()) {
            ::ScreenToClient(self, &pt);
          }
          flutter::EncodableMap out;
          out[flutter::EncodableValue("x")] =
              flutter::EncodableValue(static_cast<int>(pt.x));
          out[flutter::EncodableValue("y")] =
              flutter::EncodableValue(static_cast<int>(pt.y));
          result->Success(flutter::EncodableValue(out));
          return;
        }

        // חלון Dart חדש: תיקוני הקלט של #1441 ו-#1645 לתצוגה שלו.
        if (call.method_name() == "installViewHooks") {
          bool installed = false;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto it = args->find(flutter::EncodableValue("hwnd"));
            // `LongValue` זורק על ערך שאינו מספר; חריגה כאן מפילה את התהליך.
            int64_t hwnd = 0;
            if (it != args->end()) {
              if (const auto* wide = std::get_if<int64_t>(&it->second)) {
                hwnd = *wide;
              } else if (const auto* narrow = std::get_if<int>(&it->second)) {
                hwnd = *narrow;
              }
            }
            if (hwnd != 0) {
              installed = InstallDartViewHooks(
                  reinterpret_cast<HWND>(static_cast<intptr_t>(hwnd)));
            }
          }
          result->Success(flutter::EncodableValue(installed));
          return;
        }

        // חלון Dart בלי כותרת המערכת, כמו החלון הראשי (P1f).
        if (call.method_name() == "makeFrameless") {
          const HWND hwnd = HwndArgument(call.arguments());
          result->Success(flutter::EncodableValue(
              hwnd != nullptr && InstallFramelessViewFrame(hwnd)));
          return;
        }

        // מביא את החלון הזה לחזית; ראשי שהמשתמש סגר מוצג מחדש.
        // לפני החשיפה הראשונה אין הצגה: את זו עושה Dart כשהתוכן מוכן.
        if (call.method_name() == "raiseSelf") {
          const HWND self = GetHandle();
          if (self && !RestoreClosedWindow()) {
            Win32Window::NoteUserActivation(self);
            ::BringWindowToTop(self);
            ::SetForegroundWindow(self);
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  process_control_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "otzaria/process_control",
          &flutter::StandardMethodCodec::GetInstance());
  process_control_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "jobObjectStatus") {
          flutter::EncodableMap status;
          status[flutter::EncodableValue("ready")] =
              flutter::EncodableValue(job_object_ready_.load());
          status[flutter::EncodableValue("failure")] =
              job_object_failure_.empty()
                  ? flutter::EncodableValue()
                  : flutter::EncodableValue(job_object_failure_);
          result->Success(flutter::EncodableValue(status));
          return;
        }
        if (call.method_name() == "forceTerminate") {
          // Only honour forceTerminate when the Job Object containment is
          // verifiably in place. Without it, TerminateProcess would still
          // skip atexit / DLL_PROCESS_DETACH / Dart VM teardown — but it
          // would also orphan every msedgewebview2.exe child process the
          // user has spawned, which is the exact pathology we're trying
          // to avoid. Returning false here lets the Dart caller fall back
          // to the existing graceful close path (windowManager.destroy +
          // exit(0)), trading shutdown speed for child-process cleanup.
          if (!job_object_ready_.load()) {
            OutputDebugStringW(L"Otzaria: forceTerminate refused — Job "
                               L"Object not ready. Falling back to "
                               L"graceful close.\n");
            result->Success(flutter::EncodableValue(false));
            return;
          }
          // Instant process kill — skips C runtime atexit handlers (notably
          // sentry-native's pending-event flush, which adds several seconds
          // on plain exit(0) paths), DLL_PROCESS_DETACH, static destructors,
          // and Dart VM isolate teardown. The Job Object created in our
          // ctor guarantees that WebView2 Edge child processes die with us.
          //
          // Hive (write-through with per-record checksums) and SQLite in WAL
          // mode survive this kind of dirty shutdown by design; the existing
          // window_listener.dart shutdown sequence already flushes any
          // remaining in-memory state before calling us.
          TerminateProcess(GetCurrentProcess(), 0);
          // Unreachable in practice.
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "sessionEndFlushDone") {
          // ה-Dart סיים לשטוף. משחררים את ההמתנה ב-FlushBeforeSessionEnd,
          // שרצה כרגע על ה-thread הזה ושואבת הודעות — ולכן הקריאה הזו
          // בכלל הגיעה אלינו.
          if (session_end_flush_event_) {
            SetEvent(session_end_flush_event_);
          }
          result->Success();
          return;
        }
        if (call.method_name() != "armForceExitWatchdog") {
          result->NotImplemented();
          return;
        }

        uint32_t timeout_ms = 15000;
        if (const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto timeout_it = arguments->find(flutter::EncodableValue("timeoutMs"));
          if (timeout_it != arguments->end()) {
            if (const auto* timeout_value =
                    std::get_if<int32_t>(&timeout_it->second)) {
              if (*timeout_value > 0) {
                timeout_ms = static_cast<uint32_t>(*timeout_value);
              }
            } else if (const auto* timeout_value64 =
                           std::get_if<int64_t>(&timeout_it->second)) {
              if (*timeout_value64 > 0 &&
                  *timeout_value64 <
                      static_cast<int64_t>(std::numeric_limits<uint32_t>::max())) {
                timeout_ms = static_cast<uint32_t>(*timeout_value64);
              }
            }
          }
        }

        timeout_ms = std::clamp<uint32_t>(timeout_ms, 5000, 60000);
        ArmForceExitWatchdog(timeout_ms);
        result->Success(flutter::EncodableValue(true));
      });

  // Channel for closing the native floating-icon splash window (created in
  // main.cpp before the engine started). Dart invokes "close" when it reveals
  // the main window, so the splash icon disappears exactly as the main window
  // appears with content.
  splash_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "otzaria/splash",
          &flutter::StandardMethodCodec::GetInstance());
  splash_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "cloak") {
          // הצד של Dart קורא לזה לפני windowManager.show() בחשיפה הראשונה:
          // החלון יוצג, ימוקסם ויקבל פוקוס בעודו בלתי-נראה, וכל שינויי הגודל
          // (שזורקים את ה-swapchain ומשאירים חלון שקוף עד לפריים הבא)
          // מתרחשים מאחורי הקלעים. החשיפה בפועל היא ביטול ה-cloak ב-"close".
          SetWindowCloaked(GetHandle(), true);
          result->Success();
          return;
        }
        if (call.method_name() == "close") {
          // החלון נחשף — הניטור סיים את תפקידו.
          startup_watchdog::RequestStop();
          hang_monitor::Start();
          // Defer the actual reveal until the engine *presents* the next
          // frame (raster output reaching the swapchain) — by then the
          // window is at its final size/state (Dart sends "close" after
          // show/maximize/fullscreen). Uncloaking on that callback makes the
          // reveal atomic: one DWM composition with the final content, and
          // the splash icon's fade-out starts at that exact moment. The Dart
          // side can only observe UI-thread frame completion (endOfFrame),
          // never the actual present — hence the native callback.
          // ForceRedraw guarantees a frame is produced even if the previous
          // one was already presented before the callback was registered.
          if (flutter_controller_ && flutter_controller_->engine()) {
            HWND hwnd = GetHandle();
            flutter_controller_->engine()->SetNextFrameCallback([hwnd]() {
              SetWindowCloaked(hwnd, false);
              splash::Close();
            });
            flutter_controller_->ForceRedraw();
          } else {
            SetWindowCloaked(GetHandle(), false);
            splash::Close();
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  InstallPhantomMouseButtonFilter(
      flutter_controller_->view()->GetNativeWindow());
  InstallShiftKeyNormalizer(flutter_controller_->view()->GetNativeWindow());
  InstallAccessibilityRequestFilter(
      flutter_controller_->view()->GetNativeWindow());

  // NOTE: the main window is intentionally NOT shown here. It stays hidden
  // until Dart reveals it (window_manager.show in presentMainWindow) once the
  // active tab's content is ready — so it appears directly at its final
  // size/position with content already painted, with no resize, no jump, and
  // no blank gap. The native splash window (see main.cpp) provides the visible
  // floating icon meanwhile. ForceRedraw drives the engine to render frames
  // into the (hidden) window surface, so content is ready when Dart shows it.
  if (!headless_) {
    flutter_controller_->ForceRedraw();
  }
  // In headless mode the window stays invisible — CLI commands are expected
  // to invoke exit() from Dart before any UI work happens.

  return true;
}

void FlutterWindow::OnDestroy() {
  // NOTE: do NOT close the splash here. Win32Window::Create() calls Destroy()
  // (→ OnDestroy()) at its very start to clear any prior state — even on the
  // first creation, before any window exists — so OnDestroy fires spuriously
  // during window.Create(), which would close the splash prematurely (long
  // before the main window is revealed). The splash is closed via the
  // "otzaria/splash" channel when Dart reveals the main window (or its 8s
  // failsafe). On process exit the OS tears down the splash thread/window.
  // ⚠️ ל-`dragOutToSystem` אין timeout בצד Dart (גרירה נמשכת דקות), ולכן
  // בקשה שנהרסת בלי מענה משאירה את הגרירה תלויה לנצח.
  while (!pending_system_drags_.empty()) {
    auto pending = std::move(pending_system_drags_.front());
    pending_system_drags_.pop();
    if (pending.result) {
      pending.result->Success(DescribeSystemDrag(
          drag_preview::SystemDragResult{}, nullptr, nullptr,
          pending.report_hwnd));
    }
  }

  splash_channel_.reset();
  multiwindow_channel_.reset();
  process_control_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::RestoreClosedWindow() {
  const HWND self = GetHandle();
  if (!self || !closed_by_user_) return false;
  closed_by_user_ = false;
  if (::IsWindowVisible(self)) return false;
  // שחזור הוא כוונה מפורשת — ראו [Win32Window::ShouldVetoActivation].
  NoteUserActivation(self);
  ::ShowWindow(self, SW_SHOW);
  ::BringWindowToTop(self);
  ::SetForegroundWindow(self);
  return true;
}

void FlutterWindow::OnWindowHidden() {
  closed_by_user_ = true;
  // R1: חלון Dart גלוי חי על המנוע הזה; סגירתו היא שתסיים את התהליך.
  if (HasVisibleDartHostWindow()) return;

  // לא `PostQuitMessage`: TerminateProcess אינו מריץ teardown של המנוע וה-VM.
  // מגיעים לכאן רק כשהראשי הוסתר בלי מסלול הסגירה של Dart.
  if (job_object_ready_.load()) {
    ::TerminateProcess(::GetCurrentProcess(), 0);
    return;  // לא נגיש בפועל.
  }
  // בלי Job Object אין ערובה שתהליכי WebView2 ימותו איתנו; יציאה מסודרת.
  OutputDebugStringW(L"Otzaria: last window hidden without a Job Object — "
                     L"falling back to PostQuitMessage.\n");
  ::PostQuitMessage(0);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // נשלחת רק לחלון הראשי: ל-Dart שלו יש את ה-Navigator להצעת הדיווח.
  if (message == hang_monitor::kMsgAppHangRecovered) {
    if (process_control_channel_) {
      flutter::EncodableMap arguments;
      arguments[flutter::EncodableValue("durationMs")] =
          flutter::EncodableValue(static_cast<int64_t>(lparam));
      process_control_channel_->InvokeMethod(
          "appHangRecovered",
          std::make_unique<flutter::EncodableValue>(arguments));
    }
    return 0;
  }

  // מסירת הגרירה למערכת — ראו `drag_preview::DragWithSystem`. נפתח כאן,
  // לפני Flutter, כי מכאן נכנסים ללולאה מודאלית ואין לתוספים מה לעשות בה.
  if (message == kMsgDragOutToSystem) {
    if (pending_system_drags_.empty()) return 0;
    auto pending = std::move(pending_system_drags_.front());
    pending_system_drags_.pop();
    // אותו נימוק כמו למעלה: `noexcept`, ובפנים לולאה מודאלית של המערכת.
    bool replied = false;
    try {
      const auto drag = drag_preview::DragWithSystem();
      if (pending.result) {
        replied = true;
        // חלון המקור עלול להיהרס במהלך הלולאה המודאלית.
        const HWND self = pending.self && ::IsWindow(pending.self)
                              ? pending.self
                              : GetHandle();
        pending.result->Success(
            DescribeSystemDrag(drag, self, GetHandle(), pending.report_hwnd));
      }
    } catch (...) {
      drag_preview::End();
      // `null` ל-Dart פירושו "לא ידוע", והוא מטפל בו כ"אל תעשה כלום".
      if (pending.result && !replied) {
        pending.result->Success(flutter::EncodableValue());
      }
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      // גלאי רגרסיה: היום `window_manager` אינו בולע את הודעות סיום הסשן
      // (נמדד), ולכן ה-flush שלנו רץ. אם שדרוג של המנוע או של התוסף ישנה
      // זאת, השטיפה תפסיק לקרות **בשקט** — והשורה הזו תהיה הרמז היחיד.
      if (message == WM_QUERYENDSESSION || message == WM_ENDSESSION) {
        LogSessionEndDiagnostic(L"swallowed-by-flutter", message, wparam,
                                lparam);
      }
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;

    case WM_QUERYENDSESSION: {
      // ⚠️ ה-flush חייב לרוץ **כאן**, לפני ההחזרה. החזרת TRUE היא הבטחה
      // מחייבת: מרגע שנתנו אותה המערכת רשאית להרוג אותנו בכל רגע, ולכן
      // שטיפה מאוחרת ב-WM_ENDSESSION אינה מובטחת לרוץ. נמדד: לפני השינוי
      // הזה `DefWindowProc` כבר החזיר TRUE.
      LogSessionEndDiagnostic(L"flush-begin", message, wparam, lparam);
      const bool flushed = FlushBeforeSessionEnd();
      LogSessionEndDiagnostic(flushed ? L"flush-ok" : L"flush-timeout", message,
                              wparam, lparam);
      // תמיד מסכימים לסיום. עיכוב הכיבוי דורש ShutdownBlockReasonCreate,
      // שמציג למשתמש שאנחנו מעכבים — החלטת UX שלא התקבלה.
      return TRUE;
    }

    case WM_ENDSESSION:
      if (wparam == FALSE) {
        // בוטל (למשל `shutdown /a`). מאפסים כדי שכיבוי עתידי ישטוף מחדש
        // את מה שנכתב בינתיים — בלי זה שטיפה אחת מחסנת את כל שאר הסשן.
        LogSessionEndDiagnostic(L"session-cancelled", message, wparam, lparam);
        if (session_end_flush_event_) {
          ResetEvent(session_end_flush_event_);
        }
        // גם התקציב המשותף מתאפס, אחרת הכיבוי הבא לא יקבל זמן בכלל.
        g_session_end_deadline = 0;
        if (process_control_channel_) {
          process_control_channel_->InvokeMethod("sessionEndCancelled",
                                                 nullptr);
        }
      } else {
        LogSessionEndDiagnostic(L"session-ending", message, wparam, lparam);
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::FlushBeforeSessionEnd() {
  if (!process_control_channel_ || !flutter_controller_) {
    return false;
  }

  if (!session_end_flush_event_) {
    // manual-reset: הסימון נשאר דלוק גם אם ההודעה תגיע שוב.
    session_end_flush_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!session_end_flush_event_) {
      return false;
    }
  }
  if (WaitForSingleObject(session_end_flush_event_, 0) == WAIT_OBJECT_0) {
    // כבר נשטף בהודעה קודמת — WM_QUERYENDSESSION מגיע לא פעם יותר מפעם אחת.
    return true;
  }

  process_control_channel_->InvokeMethod("prepareForSessionEnd", nullptr);

  const HWND task_runner = FindFlutterTaskRunnerWindow();
  // תקציב אחד לכל התהליך — ראו [g_session_end_deadline].
  if (g_session_end_deadline == 0) {
    g_session_end_deadline = GetTickCount64() + kSessionEndFlushTimeoutMs;
  }
  const ULONGLONG deadline = g_session_end_deadline;
  while (true) {
    const ULONGLONG now = GetTickCount64();
    if (now >= deadline) {
      break;
    }
    // QS_POSTMESSAGE|QS_TIMER בלבד: אלה הערוצים שבהם תור המשימות של Flutter
    // מתעורר. מסכה רחבה יותר הייתה מעירה אותנו על כל תזוזת עכבר וגורמת
    // ללולאה עמוסה שסתם שורפת את שלוש השניות.
    const DWORD wait = MsgWaitForMultipleObjects(
        1, &session_end_flush_event_, FALSE,
        static_cast<DWORD>(deadline - now), QS_POSTMESSAGE | QS_TIMER);
    if (wait == WAIT_OBJECT_0) {
      return true;
    }
    if (wait != WAIT_OBJECT_0 + 1) {
      break;  // WAIT_TIMEOUT או כשל
    }

    MSG msg;
    if (task_runner != nullptr) {
      while (PeekMessageW(&msg, task_runner, 0, 0, PM_REMOVE)) {
        DispatchMessageW(&msg);
      }
    } else {
      // נפילה חזרה: אותו סוג הודעות, בלי הגבלה לחלון מסוים.
      while (PeekMessageW(&msg, nullptr, 0, 0,
                          PM_REMOVE | PM_QS_POSTMESSAGE | PM_QS_SENDMESSAGE)) {
        DispatchMessageW(&msg);
      }
    }
  }

  return WaitForSingleObject(session_end_flush_event_, 0) == WAIT_OBJECT_0;
}

void FlutterWindow::ArmForceExitWatchdog(uint32_t timeout_ms) {
  bool expected = false;
  if (!force_exit_watchdog_armed_.compare_exchange_strong(expected, true)) {
    return;
  }

  std::thread([timeout_ms]() {
    std::this_thread::sleep_for(std::chrono::milliseconds(timeout_ms));
    OutputDebugStringW(
        L"Otzaria force-exit watchdog expired; terminating process.\n");
    TerminateProcess(GetCurrentProcess(), 0);
  }).detach();
}
