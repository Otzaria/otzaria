#include "flutter_window.h"

#include <dwmapi.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <limits>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include <cstdlib>

// נדרשים ל-`RegisterPluginsMasked`, שרושם תת-קבוצה של התוספים לחלונות
// משניים. `generated_plugin_registrant.h` לבדו רושם הכול או כלום.
#include <file_selector_windows/file_selector_windows.h>
#include <flutter_inappwebview_windows/flutter_inappwebview_windows_plugin_c_api.h>
#include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>
#include <printing/printing_plugin.h>
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
// ⚠️ `sentry_flutter_plugin.h` מגדיר את ה-registrar inline, ולכן הכללתו
// כאן **וגם** ב-generated_plugin_registrant.cc יוצרת LNK2005. הוא ממילא
// stub ריק ב-Windows (כפי שהמסמך קובע), ולכן הוא מדולג במסכה.
#include <super_native_extensions/super_native_extensions_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>
#include <window_manager/window_manager_plugin.h>
#include <zstandard_windows/zstandard_windows_plugin_c_api.h>

#include "flutter/generated_plugin_registrant.h"
#include "jump_list_manager.h"
#include "drag_preview_window.h"
#include "splash_window.h"
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

// הרגע שבו שטיפת סיום הסשן נגמרת — **משותף לכל החלונות בתהליך**.
//
// ⚠️ Windows שואל כל חלון עליון בנפרד, כולל מוסתרים, וכל חלון חסם עד
// שלוש שניות בנפרד: ארבעה מנועים = עד 12 שניות, בעוד שהמערכת מסמנת
// "לא מגיב" אחרי ~5 והמשתמש רואה את אוצריא מעכבת את הכיבוי. התקציב הוא
// של התהליך, ולכן הדדליין נקבע פעם אחת וכולם מתחלקים בו.
//
// 0 פירושו "עוד לא התחיל". מאותחל מחדש כשהכיבוי מבוטל (`shutdown /a`).
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

// הודעה פרטית שמבקשת מה-thread של החלון לפתוח חלון אוצריא נוסף **על
// עצמו**. ראו `CreateSecondaryWindowOnThisThread`.
constexpr UINT kMsgOpenSecondaryWindow = WM_APP + 0x101;

// הודעה פרטית שמבקשת למסור ל-Windows את המשך גרירת הכרטיסיה.
// ראו `drag_preview::DragWithSystem`.
constexpr UINT kMsgDragOutToSystem = WM_APP + 0x103;

// החלונות המשניים שנוצרו על ה-thread הזה. `FlutterWindow` חייב לחיות כל
// עוד החלון שלו קיים, ולכן הבעלות נשמרת כאן ולא במחסנית.
std::vector<std::unique_ptr<FlutterWindow>>& SecondaryWindowsOnThisThread() {
  static thread_local std::vector<std::unique_ptr<FlutterWindow>> windows;
  return windows;
}

// תקרת חלונות. כל חלון הוא מנוע Flutter מלא (~340MB בבנייית debug), ולכן
// זו הגבלת משאבים ולא העדפת ממשק.
constexpr size_t kMaxWindows = 4;

// מציג שוב את החלון האחרון שהוסתר, אם יש כזה.
//
// מחזיר true אם חלון שוחזר. מוגדר כאן ולא ב-`FlutterWindow` כי הוא סורק
// את כל החלונות ולא פועל על אחד מסוים.
bool RestoreLastHiddenWindow();

// הגודל המינימלי שממנו מסגרת נחשבת מסגרת של חלון אמיתי, בפיקסלים פיזיים.
//
// אזור שהצמדת Windows נותנת הוא חצי מסך ומעלה; כל דבר בסדר גודל של
// כרטיסיה הוא סימן שמשהו בצד המשלח שגוי.
constexpr int kMinReasonableWindowWidth = 320;
constexpr int kMinReasonableWindowHeight = 240;

// מונה סידורי של הסתרות, כדי שהשחזור יתחיל **מהאחרון שנסגר**.
//
// ⚠️ סדר היצירה אינו סדר הסגירה. הסריקה הקודמת רצה על רשימת החלונות
// מהסוף להתחלה, כלומר בסדר יצירה הפוך — ומשתמש שסגר את החלון הראשון
// ואחריו את השני קיבל ב-Ctrl+Shift+T דווקא את הראשון.
unsigned long long g_hidden_sequence = 0;

// מיפוי חלון → משבצת באפיק ההודעות של Dart.
//
// ⚠️ נדרש לגרירה בין חלונות. Win32 יודע איזה **חלון** נמצא תחת הסמן, אבל
// Dart מזהה חלונות לפי משבצת באפיק. בלי המיפוי אי אפשר לתרגם "שוחרר מעל
// החלון הזה" ל"שלח לחלון מספר N".
std::map<HWND, int>& WindowSlots() {
  static std::map<HWND, int> slots;
  return slots;
}

// מספר חלונות אוצריא החיים בתהליך, כולל הראשי.
//
// משמש לשני דברים: אכיפת [kMaxWindows], והחלטה מתי יציאה מהתהליך מוצדקת.
// ⚠️ סגירת חלון בודד **אינה** מסיימת את התהליך — רק סגירת האחרון.
std::atomic<int> g_live_window_count{0};

// מספר מנועי Flutter החיים בתהליך.
//
// ⚠️ **אינו זהה ל-`g_live_window_count`, וההבדל הוא הנקודה.** המונה שמעל
// יורד בהסתרה, כי חלון שנסגר מוסתר ולא נהרס — אבל **המנוע שלו נשאר חי**.
// כלומר "נסגר החלון האחרון" יכול לקרות בעוד שלושה מנועים רצים.
//
// זה קריטי ליציאה: P-2 מדד ש-`exit()` בזמן שמנוע אחר חי מפיל את הבדיקה
// של ה-Dart VM ("Isolate main is owned by os thread X, failed to schedule
// from os thread Y") ב-~1% מהיציאות. המסלול הרגיל יוצא ב-
// `TerminateProcess`, שאינו מריץ teardown של ה-VM ולכן חסין; רק מסלול
// הנפילה-לאחור (כשה-Job Object לא הוקם) מגיע ל-`exit()`. המונה הזה נשלח
// ל-Dart כדי שהשורה בלוג תכיל את המידע שחסר בדיוק לאבחון ההוא.
//
// אינו יורד לעולם, במכוון: מנוע אינו נהרס עד יציאת התהליך (הריסה על
// ה-thread הראשי מפילה — ראו `CreateSecondaryWindowOnThisThread`).
std::atomic<int> g_live_engine_count{0};

// מיקום החלון החדש: פינתו **בנקודה שנמסרה**, מהודקת למסך שתחתיה.
//
// ⚠️ הפינה, ולא חישוב סביבה. הגרסה הקודמת הזיזה את החלון
// `-width + 100` פיקסלים כדי שהכרטיסיה תשב תחת הסמן — היסט שנועד לתצוגה
// ברוחב 300, ועם חלון ברוחב 1400 הוא 1,300 פיקסלים שמאלה. אחרי ההידוק
// לקצה המסך התוצאה הייתה קבועה: חלון שנגרר ימינה נפתח **בשמאל**, טיפה
// מתחת למקור. בדיוק מה שהמשתמש דיווח.
//
// הנקודה שמגיעה לכאן היא הפינה שבה **התצוגה** נעצרה, כלומר המקום שבו
// המשתמש ראה את הכרטיסיה בשחרור. לכן אין מה לחשב סביבה.
// ⚠️ הכול כאן ב**פיקסלים פיזיים**: הנקודה, המידות והתוצאה. `POINT`
// (מסומן) ולא `Win32Window::Point` (unsigned) — קואורדינטה שלילית היא
// מסך שמאלי, מצב לגיטימי לחלוטין, ואין טעם להעביר אותה דרך גלישה
// מודולרית וחזרה.
POINT OriginForDrop(int origin_x, int origin_y, int width, int height) {
  int left = origin_x;
  int top = origin_y;

  // ⚠️ הידוק לאזור העבודה של המסך שתחת הנקודה, ולא של המסך הראשי:
  // שחרור בקצה מסך שני היה יוצר חלון שחלקו מחוץ לתחום.
  POINT pt{origin_x, origin_y};
  const HMONITOR monitor = ::MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (::GetMonitorInfoW(monitor, &info)) {
    const RECT& work = info.rcWork;
    if (left + width > work.right) left = work.right - width;
    if (left < work.left) left = work.left;
    if (top + height > work.bottom) top = work.bottom - height;
    if (top < work.top) top = work.top;
  }
  return POINT{left, top};
}

// מתאר את היעד שתחת הסמן, בשפה ש-Dart מבין.
//
// ⚠️ עוזר משותף ל-`windowAtCursor` ול-`dragOutToSystem`, ובמכוון: שני
// המסלולים מקבלים את אותה החלטה — "מה נמצא שם" — ושתי גרסאות שלה היו
// נפרדות בשקט ברגע שאחת מהן משתנה.
flutter::EncodableMap DescribeTarget(HWND under, POINT cursor, HWND self) {
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

  const auto& slots = WindowSlots();
  const auto it = slots.find(under);
  if (it != slots.end() && ::IsWindowVisible(under)) {
    info[flutter::EncodableValue("slot")] =
        flutter::EncodableValue(it->second);
    info[flutter::EncodableValue("isSelf")] =
        flutter::EncodableValue(under == self);
  }
  return info;
}

// מתאר גרירה שהמערכת ניהלה: היעד, והמסגרת שהמשתמש עצר בה.
flutter::EncodableValue DescribeSystemDrag(
    const drag_preview::SystemDragResult& drag, HWND self) {
  flutter::EncodableMap info = DescribeTarget(drag.under, drag.cursor, self);
  info[flutter::EncodableValue("ran")] = flutter::EncodableValue(drag.ran);
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

// יוצר חלון אוצריא נוסף **על ה-thread הקורא**, ומשתמש בלולאת ההודעות
// הקיימת שלו.
//
// ⚠️ ה-thread אינו שרירותי. יצירת מנוע על thread ייעודי חדש קורסת
// בעקביות כשהחלון הראשון כבר רץ ("Isolate main is already scheduled on
// mutator thread"), בלי קשר לתוספים או ל-`RustLib.init`. כך גם עושה
// `desktop_multi_window`: כל המנועים על ה-thread הראשי.
//
// המחיר: ה-platform thread וה-UI thread ממוזגים, ולכן כל המנועים חולקים
// scheduler אחד — חלון עסוק מקפיא את השני. ראו docs/multi-window.md.
bool CreateSecondaryWindowOnThisThread(const flutter::DartProject& base,
                                       const std::string& payload,
                                       int inherited_width,
                                       int inherited_height, int origin_x,
                                       int origin_y, const RECT* bounds) {
  // ניקוי חלונות שנסגרו, כדי שהרשימה לא תגדל בלי גבול.
  auto& windows = SecondaryWindowsOnThisThread();
  windows.erase(
      std::remove_if(windows.begin(), windows.end(),
                     [](const std::unique_ptr<FlutterWindow>& w) {
                       return w == nullptr || w->GetHandle() == nullptr;
                     }),
      windows.end());

  // ⚠️ חלון סגור אינו נהרס אלא מוסתר (ראו `kMsgDeferredDestroy`), והמנוע
  // שלו נשאר חם. שימוש חוזר בו במקום יצירת מנוע חדש חוסך את כל האתחול —
  // זה ההבדל בין ~1800ms לפתיחה מיידית — **וגם** מונע גידול בזיכרון
  // במחזורי פתיחה-סגירה, כי אין מנוע נוסף.
  //
  // ⚠️ סורק את **כל** החלונות ולא רק את המשניים. חלון ראשון שהמשתמש סגר
  // לא הוחזר לשימוש, ובמקומו נוצר מנוע חמישי — ראו
  // [FlutterWindow::AllWindowsInProcess]. הבחירה היא באחרון שנסגר, כמו
  // בשחזור.
  FlutterWindow* reusable = nullptr;
  for (FlutterWindow* existing : FlutterWindow::AllWindowsInProcess()) {
    if (existing == nullptr || existing->GetHandle() == nullptr) continue;
    // ⚠️ `IsClosedByUser()` ולא `IsWindowVisible` — ראו ההערה שם.
    if (!existing->IsClosedByUser()) continue;
    if (reusable == nullptr || existing->hidden_at() > reusable->hidden_at()) {
      reusable = existing;
    }
  }
  if (reusable != nullptr) {
    reusable->ReviveWith(payload, inherited_width, inherited_height, origin_x,
                         origin_y, bounds);
    return true;
  }

  // ⚠️ התקרה נאכפת על **המנועים** ולא על החלונות הגלויים. מנוע אינו נהרס
  // לעולם (ראו [g_live_engine_count]), ולכן ספירת החלונות הגלויים אפשרה
  // ליצור מנוע נוסף כל עוד חלון אחד מוסתר — וכאן זה כבר לא יכול לקרות,
  // כי לולאת המיחזור שמעל הייתה מוצאת אותו.
  if (g_live_engine_count.load() >= static_cast<int>(kMaxWindows) ||
      g_live_window_count.load() >= static_cast<int>(kMaxWindows)) {
    return false;
  }

  flutter::DartProject project(base);
  project.set_dart_entrypoint("secondaryWindowMain");
  project.set_dart_entrypoint_arguments({payload});

  auto window = std::make_unique<FlutterWindow>(project);
  // ⚠️ יורש את מידות החלון שפתח אותו. חלון בגודל קבוע נראה שרירותי —
  // המשתמש שהגדיל את החלון שלו מצפה שהחדש יהיה דומה. נופלים לברירת מחדל
  // רק כשהמידות לא הגיעו (מסלול ישן, או קריאה בלי ארגומנטים).
  // ⚠️ **לוגיים.** `windowManager.getSize()` מחלק ב-DPR לפני שהוא מחזיר
  // ל-Dart, ולכן המידות שמגיעות משם אינן פיקסלים של המסך.
  const int logical_width = inherited_width > 400 ? inherited_width : 1100;
  const int logical_height = inherited_height > 300 ? inherited_height : 760;

  // מסגרת מדויקת (הצמדה) קודמת לכול, אחריה הפינה שנמסרה, ובהיעדר
  // שתיהן — היסט מדורג, כמו קודם.
  //
  // ⚠️ שתי הראשונות מגיעות **בפיקסלים פיזיים** (`GetWindowRect` /
  // `GetCursorPos` בצד הגרירה), ולכן הן עוברות ל-`CreatePhysical` ולא
  // ל-`Create` שמכפיל ב-scale factor. ראו [Win32Window::CreatePhysical].
  //
  // ⚠️ מסגרת קטנה מדי אינה הצמדה אמיתית. אזור שההצמדה נותנת הוא חצי מסך
  // ומעלה, ואילו תצוגת הגרירה עצמה היא בגודל כרטיסיה. באג בצד המשלח
  // (`snapped` כוזב) הגיע לכאן עם 176×40 ויצר חלון אוצריא ברוחב סרגל —
  // עדיף להתעלם ולפתוח בגודל תקין מאשר לכבד מסגרת שברור שאינה מסגרת חלון.
  if (bounds != nullptr &&
      (bounds->right - bounds->left < kMinReasonableWindowWidth ||
       bounds->bottom - bounds->top < kMinReasonableWindowHeight)) {
    OutputDebugStringW(L"Otzaria: ignoring implausible snapped bounds.\n");
    bounds = nullptr;
  }
  if (bounds != nullptr) {
    if (!window->CreatePhysical(L"אוצריא", *bounds,
                                kNoActivateUntilRevealed)) {
      return false;
    }
  } else if (origin_x != 0 || origin_y != 0) {
    // המידות הלוגיות מומרות לפיזיות לפי ה-DPI של המסך שתחת נקודת
    // השחרור — לא של המסך הראשי, כי גרירה למסך שני היא המקרה השכיח.
    const POINT drop{origin_x, origin_y};
    const UINT dpi = FlutterDesktopGetDpiForMonitor(
        ::MonitorFromPoint(drop, MONITOR_DEFAULTTONEAREST));
    const double scale = dpi / 96.0;
    const int physical_width = static_cast<int>(logical_width * scale);
    const int physical_height = static_cast<int>(logical_height * scale);
    // ⚠️ ההידוק למסך נעשה בפיקסלים פיזיים בשני הצדדים — הן הנקודה והן
    // המידות. השוואת נקודה פיזית מול רוחב לוגי הידקה לפי חלון קטן יותר
    // ממה שנוצר בפועל, וקצה החלון יצא מחוץ למסך.
    const POINT corner =
        OriginForDrop(origin_x, origin_y, physical_width, physical_height);
    RECT frame{};
    frame.left = corner.x;
    frame.top = corner.y;
    frame.right = frame.left + physical_width;
    frame.bottom = frame.top + physical_height;
    if (!window->CreatePhysical(L"אוצריא", frame,
                                kNoActivateUntilRevealed)) {
      return false;
    }
  } else {
    static int spawn_index = 0;
    const int offset = 40 + (spawn_index++ % 6) * 32;
    // כאן הכול לוגי — היסט קטן שנקבע אצלנו, ולא מיקום שהגיע מ-Win32.
    if (!window->Create(L"אוצריא", Win32Window::Point(offset, offset),
                        Win32Window::Size(logical_width, logical_height),
                        kNoActivateUntilRevealed)) {
      return false;
    }
  }
  // ⚠️ `false` במפורש: סגירת חלון משני אסור לה לפרסם `WM_QUIT` ל-thread
  // הראשי — זה היה סוגר את כל האפליקציה. היציאה מנוהלת ב-`OnDestroy` לפי
  // מספר החלונות החיים.
  window->SetQuitOnClose(false);

  // ⚠️ נחשף בפריים הראשון, ולא בסוף האתחול.
  //
  // הצגה **מיידית** חושפת חלון ריק שמצטייר בהדרגה — ריצוד. המתנה עד סיום
  // האתחול משאירה שניות שבהן לא קורה כלום על המסך, והמשתמש אינו יודע אם
  // הלחיצה נקלטה. הפריים הראשון הוא מסך הטעינה של האפליקציה: מופיע כמעט
  // מיד, ואינו ריק.
  window->RevealOnFirstFrame();

  // רשת ביטחון: אם הפריים הראשון לא הגיע, חלון בלתי-נראה לתמיד גרוע
  // מחלון שמופיע מאוחר.
  const HWND handle = window->GetHandle();
  auto hidden = window->hidden_flag();
  // ⚠️ ה-`try` אינו קוסמטי: הפונקציה נקראת מ-`MessageHandler`, שהוא
  // `noexcept`, וכשל בהקצאת thread היה מגיע ל-`std::terminate` — כלומר
  // קריסת התהליך כולו במקום חלון שנחשף מאוחר.
  try {
    std::thread([handle, hidden]() {
      ::Sleep(20000);
      // ⚠️ רק אם המשתמש לא סגר אותו בינתיים: `IsWindowVisible` לבדו היה
      // מחזיר לחיים חלון שנסגר לפני שהשעון פקע.
      if (::IsWindow(handle) && !::IsWindowVisible(handle) &&
          !hidden->load()) {
        // ⚠️ גם הבאה לחזית, ולא רק הצגה. זהו המסלול היחיד שנשאר כשהפריים
        // הראשון לא הגיע, ו-`presentMainWindow` כבר אינו מעלה חלון משני
        // (זה היה חטיפת פוקוס שניות אחרי החשיפה). בלי זה חלון שנחשף
        // במסלול הזה היה מופיע מאחורי החלון שפתח אותו.
        Win32Window::AllowActivation(handle);
        ::ShowWindow(handle, SW_SHOW);
        ::BringWindowToTop(handle);
        ::SetForegroundWindow(handle);
      }
    }).detach();
  } catch (const std::exception&) {
    OutputDebugStringW(L"Otzaria: reveal watchdog thread not started.\n");
  }

  windows.push_back(std::move(window));
  return true;
}


}  // namespace

std::vector<FlutterWindow*>& FlutterWindow::AllWindowsInProcess() {
  static std::vector<FlutterWindow*> windows;
  return windows;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool headless)
    : project_(project), headless_(headless) {
  AllWindowsInProcess().push_back(this);
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
  // ⚠️ ה-Job שייך ל**תהליך**, לא לחלון. במודל A יש `FlutterWindow` לכל
  // חלון, וגרסה קודמת יצרה Job לכל אחד וסגרה אותו בדסטרקטור. עם
  // `KILL_ON_JOB_CLOSE` והתהליך שלנו כחבר, סגירת ה-handle כשחלון **משני**
  // נסגר מורה לגרעין להרוג את כל חברי ה-Job — כלומר אותנו. נמדד: הדסטרקטור
  // של החלון המשני נכנס ל-`~FlutterWindow` ולעולם אינו חוזר
  // (ראו docs/multi-window.md). לכן: נוצר פעם אחת, ואינו נסגר לעולם —
  // סגירת ה-handle בעת יציאת התהליך היא בדיוק הרגע שבו KILL_ON_JOB_CLOSE
  // אמור לפעול.
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
  auto& all = AllWindowsInProcess();
  all.erase(std::remove(all.begin(), all.end(), this), all.end());
  // ⚠️ ה-Job **אינו** נסגר כאן. הוא משאב של התהליך, ולא של החלון: סגירתו
  // מפעילה `KILL_ON_JOB_CLOSE` על כל החברים, והתהליך שלנו הוא אחד מהם.
  // כשחלון משני נסגר, זה פירושו הריגה עצמית. ראו ההערה בקונסטרוקטור.
  // יציאת התהליך סוגרת את ה-handle ממילא — וזה בדיוק העיתוי הנכון.
  if (session_end_flush_event_) {
    CloseHandle(session_end_flush_event_);
    session_end_flush_event_ = nullptr;
  }
}

namespace {

// האם כבר נרשמו תוספים למנוע כלשהו בתהליך. במודל A יש מנוע לכל חלון,
// והחלון הראשון מקבל את מסלול היצור המלא בעוד הנוספים מקבלים תת-קבוצה.
std::atomic<bool> g_first_engine_registered{false};

// מסכת כל התוספים ב-`RegisterPluginsMasked`, וביט ה-`printing` בתוכה.
constexpr unsigned long kAllPluginsMask = 0x3FF;  // עשרה תוספים
constexpr unsigned long kPrintingPluginBit = 1UL << 3;

// מונע מ-`flutter_inappwebview_windows` לבטל רישום של מחלקות חלון שחלונות
// אחרים עדיין צריכים.
//
// הבעיה: `InAppWebViewManager` רושם את המחלקה `CustomPlatformView`
// בקונסטרוקטור ומבטל אותה בדסטרקטור **ללא תנאי וללא מונה הפניות**
// (in_app_webview_manager.cpp:259), ואותו דפוס חוזר עבור
// `HeadlessInAppWebView` (headless_in_app_webview_manager.cpp:145). עם מנוע
// לכל חלון נוצר manager לכל חלון: הרישום השני נכשל בשקט (ערך ההחזרה
// מתעלם), וסגירת חלון אחד מסירה את המחלקה מתחת לרגליו של האחר. התוצאה
// היא WebView שבור עד סוף הריצה — ורק כשאין חלון פתוח מאותה מחלקה, ולכן
// בדיקה תמימה של "פתח WebView בחלון שני" תעבור ותחמיץ אותה.
//
// התיקון: מחזיקים חלון message-only יחיד מכל מחלקה לכל אורך חיי התהליך.
// `UnregisterClass` נכשל כל עוד קיים חלון מהמחלקה, ולכן ביטול הרישום של
// התוסף הופך ל-no-op. אומת ב-`--check2`: בלי חלון שומר ביטול הרישום
// מצליח והמחלקה נעלמת; עם חלון שומר הוא נכשל והמחלקה שורדת.
//
// נדרש **אחרי** `RegisterPlugins`, כי המחלקה חייבת להיות רשומה כדי שאפשר
// יהיה ליצור ממנה חלון.
void KeepWebViewWindowClassesAlive() {
  static std::once_flag once;
  std::call_once(once, []() {
    static const wchar_t* kClasses[] = {L"CustomPlatformView",
                                        L"HeadlessInAppWebView"};
    for (const wchar_t* cls : kClasses) {
      // המחלקה נרשמת על ידי ה-DLL של התוסף, ולכן ה-hInstance שלה אינו
      // בהכרח שלנו. מנסים את שתי האפשרויות ומדווחים.
      HWND keeper = ::CreateWindowExW(0, cls, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                                      nullptr, nullptr, nullptr);
      if (!keeper) {
        keeper = ::CreateWindowExW(0, cls, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                                   nullptr, ::GetModuleHandle(nullptr),
                                   nullptr);
      }
      if (keeper) {
        // דולף בכוונה: אורך החיים הוא אורך חיי התהליך.
        printf("[webview-class-keeper] %ls ok\n", cls);
      } else {
        printf("[webview-class-keeper] %ls FAILED err=%lu\n", cls,
               ::GetLastError());
      }
    }
    fflush(stdout);
  });
}

// רושם תת-קבוצה של התוספים לפי מסכת ביטים, בסדר של
// `generated_plugin_registrant.cc`.
//
// ⚠️ נדרש כי תוספים מסוימים אינם בטוחים לרישום פעמיים באותו תהליך —
// ראו ההערה על `printing` באתר הקריאה.
void RegisterPluginsMasked(flutter::PluginRegistry* registry,
                           unsigned long mask) {
  struct Entry {
    const char* name;
    void (*fn)(FlutterDesktopPluginRegistrarRef);
  };
  static const Entry kEntries[] = {
      {"FileSelectorWindows", FileSelectorWindowsRegisterWithRegistrar},
      {"FlutterInappwebviewWindowsPluginCApi",
       FlutterInappwebviewWindowsPluginCApiRegisterWithRegistrar},
      {"IrondashEngineContextPluginCApi",
       IrondashEngineContextPluginCApiRegisterWithRegistrar},
      {"PrintingPlugin", PrintingPluginRegisterWithRegistrar},
      {"ScreenRetrieverWindowsPluginCApi",
       ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar},
      {"SentryFlutterPlugin", nullptr},  // stub ריק — ראו ההערה בהכללות
      {"SuperNativeExtensionsPluginCApi",
       SuperNativeExtensionsPluginCApiRegisterWithRegistrar},
      {"UrlLauncherWindows", UrlLauncherWindowsRegisterWithRegistrar},
      {"WindowManagerPlugin", WindowManagerPluginRegisterWithRegistrar},
      {"ZstandardWindowsPluginCApi",
       ZstandardWindowsPluginCApiRegisterWithRegistrar},
  };
  for (size_t i = 0; i < sizeof(kEntries) / sizeof(kEntries[0]); ++i) {
    if ((mask & (1UL << i)) && kEntries[i].fn != nullptr) {
      kEntries[i].fn(registry->GetRegistrarForPlugin(kEntries[i].name));
      printf("[plugin] registered %s\n", kEntries[i].name);
    }
  }
  fflush(stdout);
}

}  // namespace

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
  // ⚠️ רישום התוספים מסוריאלי בין חלונות.
  //
  // רבים מה-registrar-ים כותבים למצב process-global (`printing_plugin.cpp:35`
  // הוא הדוגמה המובהקת, אך לא היחידה). כששני חלונות נוצרים על שני threads
  // בו-זמנית, שתי הכתיבות מתערבבות והתוצאה שנמדדה היא קריסה בשיעור ~1%:
  // "Isolate main is owned by os thread X, failed to schedule from os
  // thread Y" — thread אחד שמנסה להריץ Dart של ה-isolate של האחר.
  // ראו docs/multi-window.md.
  static std::mutex plugin_registration_mutex;
  std::lock_guard<std::mutex> plugin_registration_lock(
      plugin_registration_mutex);

  if (!g_first_engine_registered.exchange(true)) {
    // החלון הראשון עובר במסלול היצור המדויק, ללא שינוי.
    RegisterPlugins(flutter_controller_->engine());
  } else {
    // ⚠️ חלון נוסף — `printing` מדולג.
    //
    // `printing_plugin.cpp:35` מחזיק `std::unique_ptr<MethodChannel> channel`
    // יחיד ב-**namespace scope**, ומשייך אליו מחדש בכל `RegisterWithRegistrar`
    // (:41). `printing.cpp:24` מכריז עליו `extern` ושולח דרכו את כל
    // הקולבקים — `onLayout` (:102) ועוד שלושה (:43, :66, :137). עם מנוע לכל
    // חלון, רישום המנוע השני דורס את הערוץ, וכל קולבק הדפסה — גם של החלון
    // הראשון — מנותב ל-isolate שנרשם אחרון. התוצאה: הדפסה שנתקעת בשקט.
    //
    // עד שההדפסה תנותב ל-host (פרק 3), עדיף שהדפסה מחלון משני תיכשל מיד
    // מאשר שתשבור את החלון הראשון.
    RegisterPluginsMasked(flutter_controller_->engine(),
                          kAllPluginsMask & ~kPrintingPluginBit);
  }
  g_live_window_count.fetch_add(1);
  g_live_engine_count.fetch_add(1);
  KeepWebViewWindowClassesAlive();
  // ── ריבוי חלונות ──
  // Dart קורא `openWindow` עם מטען JSON (בדרך כלל טאב מסוריאל), וה-runner
  // יוצר חלון נוסף על ה-thread הראשי. המטען עובר כארגומנט לנקודת הכניסה
  // `secondaryWindowMain`, ולא דרך ערוץ — החלון החדש עוד לא קיים בזמן
  // הקריאה, ואין למי לשלוח.
  multiwindow_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "otzaria/multiwindow",
          &flutter::StandardMethodCodec::GetInstance());
  multiwindow_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        // Dart שואל כמה חלונות פתוחים ומה התקרה, כדי להשבית את פריט
        // התפריט כשאין מקום — עדיף מלחיצה שלא עושה כלום.
        if (call.method_name() == "windowCount") {
          flutter::EncodableMap info;
          info[flutter::EncodableValue("count")] =
              flutter::EncodableValue(g_live_window_count.load());
          info[flutter::EncodableValue("max")] =
              flutter::EncodableValue(static_cast<int>(kMaxWindows));
          // ⚠️ מנועים ולא חלונות. חלון סגור מוסתר ולא נהרס, ולכן המנוע
          // שלו נספר כאן ולא ב-`count`. ההבדל הוא מה שקובע אם `exit()`
          // בטוח — ראו [g_live_engine_count].
          info[flutter::EncodableValue("engines")] =
              flutter::EncodableValue(g_live_engine_count.load());
          result->Success(flutter::EncodableValue(info));
          return;
        }
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
        // Dart מודיע איזו משבצת באפיק הוא תפס, כדי שנוכל לתרגם "החלון
        // שתחת הסמן" למספר משבצת.
        if (call.method_name() == "setBusSlot") {
          if (const auto* slot = std::get_if<int>(call.arguments())) {
            if (const HWND self = GetHandle()) WindowSlots()[self] = *slot;
          }
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
          result->Success(flutter::EncodableValue(
              DescribeTarget(under, cursor, GetHandle())));
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
          drag_preview::Begin(drag_preview::Utf16FromUtf8(title), GetHandle(),
                              colors);
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
            result->Success(
                DescribeSystemDrag(drag_preview::SystemDragResult{}, nullptr));
            return;
          }
          pending_system_drags_.push(std::move(result));
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

        // משחזר את החלון האחרון שנסגר, כמו Ctrl+Shift+T בדפדפן.
        //
        // ⚠️ אפשרי **רק** מפני שחלון סגור מוסתר ולא נהרס: המנוע שלו עדיין
        // חי עם הכרטיסיות שהיו בו, ולכן השחזור הוא הצגה בלבד.
        if (call.method_name() == "restoreLastClosedWindow") {
          result->Success(
              flutter::EncodableValue(RestoreLastHiddenWindow()));
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
          if (const HWND self = GetHandle()) ::ScreenToClient(self, &pt);
          flutter::EncodableMap out;
          out[flutter::EncodableValue("x")] =
              flutter::EncodableValue(static_cast<int>(pt.x));
          out[flutter::EncodableValue("y")] =
              flutter::EncodableValue(static_cast<int>(pt.y));
          result->Success(flutter::EncodableValue(out));
          return;
        }

        // מביא את החלון הזה לחזית.
        //
        // ⚠️ נדרש כי חלון משני נוצר **מוסתר**, ו-`ShowWindow` על חלון
        // מוסתר אינו מפעיל אותו — הוא נחשף מאחורי החלון שפתח אותו.
        if (call.method_name() == "raiseSelf") {
          const HWND self = GetHandle();
          if (self) {
            // ⚠️ חלון שהמשתמש סגר **מוסתר ולא נהרס**, ו-`ShowWindow` עליו
            // מצד Dart היה מציג אותו בעוד `counted_`/`hidden_flag_`
            // ממשיכים לתאר חלון סגור: המונה חסר אחד, וסגירת שאר החלונות
            // מסיימת את התהליך בעוד החלון הזה גלוי. `ReviveWith` הוא
            // המסלול היחיד שמחזיר חלון מוסתר יחד עם הספירה.
            // ⚠️ העלאה **מכוונת** (כרטיסיה שהועברה לכאן, `otzaria://`),
            // ולכן היא נרשמת ככוונה מפורשת ולא נחסמת בשער ההפעלה —
            // ראו [Win32Window::ShouldVetoActivation].
            Win32Window::NoteUserActivation(self);
            if (IsClosedByUser()) {
              ReviveWith(std::string(), 0, 0);
            } else {
              ::BringWindowToTop(self);
              ::SetForegroundWindow(self);
            }
          }
          result->Success();
          return;
        }
        // אילו חלונות אוצריא **מוצגים** על המסך כרגע.
        //
        // ⚠️ נדרש כי חלון שהמשתמש סגר מוסתר ולא נהרס, וה-isolate שלו
        // ממשיך לענות על האפיק. בלי ההבחנה הזו חלון סגור המשיך להופיע
        // ב"העבר לחלון קיים", אישר קבלת כרטיסיה, והמקור מחק אותה. חלון
        // מוסתר אינו יודע שהוסתר, ולכן התשובה חייבת לבוא מכאן.
        if (call.method_name() == "visibleSlots") {
          flutter::EncodableList slots;
          for (const auto& entry : WindowSlots()) {
            if (::IsWindow(entry.first) && ::IsWindowVisible(entry.first)) {
              slots.push_back(flutter::EncodableValue(entry.second));
            }
          }
          result->Success(flutter::EncodableValue(slots));
          return;
        }

        if (call.method_name() != "openWindow") {
          result->NotImplemented();
          return;
        }
        if (g_live_window_count.load() >= static_cast<int>(kMaxWindows)) {
          result->Success(flutter::EncodableValue(false));
          return;
        }
        // הארגומנט הוא מפה: המטען, ומידות שהחלון החדש יורש מהפותח.
        PendingSecondaryWindow pending;
        if (const auto* args =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          const auto payload_it =
              args->find(flutter::EncodableValue("payload"));
          if (payload_it != args->end()) {
            if (const auto* value =
                    std::get_if<std::string>(&payload_it->second)) {
              pending.payload = *value;
            }
          }
          const auto w_it = args->find(flutter::EncodableValue("width"));
          if (w_it != args->end()) {
            if (const auto* v = std::get_if<int>(&w_it->second)) {
              pending.width = *v;
            }
          }
          const auto h_it = args->find(flutter::EncodableValue("height"));
          if (h_it != args->end()) {
            if (const auto* v = std::get_if<int>(&h_it->second)) {
              pending.height = *v;
            }
          }
          // פינת החלון החדש — הוא ייפתח שם ולא בהיסט מדורג מהפינה.
          const auto dx_it = args->find(flutter::EncodableValue("originX"));
          if (dx_it != args->end()) {
            if (const auto* v = std::get_if<int>(&dx_it->second)) {
              pending.origin_x = *v;
            }
          }
          const auto dy_it = args->find(flutter::EncodableValue("originY"));
          if (dy_it != args->end()) {
            if (const auto* v = std::get_if<int>(&dy_it->second)) {
              pending.origin_y = *v;
            }
          }
          // מסגרת מדויקת, כשהגרירה הסתיימה בהצמדה של Windows.
          //
          // ⚠️ מחליפה את `originX/originY`: חלון שהמשתמש הצמיד לחצי מסך
          // חייב להיווצר **באותה מסגרת**, אחרת ההצמדה שהוא ראה נעלמת
          // ברגע שהחלון האמיתי מופיע.
          const auto b_it = args->find(flutter::EncodableValue("bounds"));
          if (b_it != args->end()) {
            if (const auto* b =
                    std::get_if<flutter::EncodableMap>(&b_it->second)) {
              const auto at = [b](const char* key) -> int {
                const auto it = b->find(flutter::EncodableValue(key));
                if (it == b->end()) return 0;
                const auto* v = std::get_if<int>(&it->second);
                return v ? *v : 0;
              };
              const int w = at("width");
              const int h = at("height");
              if (w > 0 && h > 0) {
                pending.has_bounds = true;
                pending.bounds.left = at("left");
                pending.bounds.top = at("top");
                pending.bounds.right = pending.bounds.left + w;
                pending.bounds.bottom = pending.bounds.top + h;
              }
            }
          }
        }
        // ⚠️ הבקשה מתפרסמת ל-thread של החלון ואינה מבוצעת כאן ישירות.
        // הקריאה מגיעה מתוך טיפול בערוץ, כלומר מתוך ריצת ה-Dart של החלון
        // הזה; יצירת מנוע נוסף באמצע היא ריאנטרנטית. `PostMessage` דוחה
        // אותה לאיטרציה הבאה של לולאת ההודעות, כשה-isolate כבר לא בתוך
        // הקריאה.
        //
        // ⚠️ ה-`result` נוסע איתה ונענה שם. Dart מוחק את הכרטיסיה על סמך
        // התשובה הזו, ולכן היא חייבת לתאר את מה שקרה בפועל.
        // ⚠️ בלי handle ההודעה נשלחת ל-thread ולא לחלון, כלומר לא תטופל
        // לעולם — ראו את אותו טיפול ב-`dragOutToSystem`.
        const HWND self = GetHandle();
        if (self == nullptr) {
          result->Success(flutter::EncodableValue(false));
          return;
        }
        pending.result = std::move(result);
        pending_secondary_windows_.push(std::move(pending));
        ::PostMessageW(self, kMsgOpenSecondaryWindow, 0, 0);
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

  // ערוץ עדכון ה-Jump List: Dart שולח "updateTabs" עם רשימת כותרות הטאבים.
  // ה-handler רץ על ה-UI thread (אותו STA שאיתחל COM ב-main.cpp), כנדרש
  // ל-ICustomDestinationList.
  jumplist_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "otzaria/jumplist",
          &flutter::StandardMethodCodec::GetInstance());
  jumplist_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "updateTabs") {
          result->NotImplemented();
          return;
        }

        std::vector<std::string> titles;
        if (const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto titles_it =
              arguments->find(flutter::EncodableValue("titles"));
          if (titles_it != arguments->end()) {
            if (const auto* list =
                    std::get_if<flutter::EncodableList>(&titles_it->second)) {
              for (const auto& entry : *list) {
                if (const auto* title = std::get_if<std::string>(&entry)) {
                  titles.push_back(*title);
                }
              }
            }
          }
        }

        result->Success(
            flutter::EncodableValue(jump_list::UpdateOpenTabs(titles)));
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  // ⚠️ בקשות פתיחה שלא בוצעו חייבות לקבל תשובה. `MethodResult` שנהרס בלי
  // מענה משאיר את ה-`Future` בצד Dart תלוי לנצח, ואיתו את מסלול העברת
  // הכרטיסיה שממתין לו.
  while (!pending_secondary_windows_.empty()) {
    auto pending = std::move(pending_secondary_windows_.front());
    pending_secondary_windows_.pop();
    if (pending.result) {
      pending.result->Success(flutter::EncodableValue(false));
    }
  }
  // ⚠️ אותו חוזה בדיוק לתור השני, שנשכח. ל-`dragOutToSystem` אין timeout
  // בצד Dart — ובמכוון, גרירה יכולה להימשך דקות — ולכן בקשה שנהרסת בלי
  // מענה משאירה את הגרירה תלויה לנצח, עם הכרטיסיה מעומעמת במקומה.
  while (!pending_system_drags_.empty()) {
    auto pending = std::move(pending_system_drags_.front());
    pending_system_drags_.pop();
    if (pending) {
      pending->Success(
          DescribeSystemDrag(drag_preview::SystemDragResult{}, nullptr));
    }
  }
  // ⚠️ **לא** לפי `GetHandle()`. במסלול `WM_DESTROY` השדה `window_handle_`
  // מתאפס **לפני** הקריאה ל-`Destroy()` שמגיעה לכאן, ולכן מחיקה לפיו
  // הייתה no-op שקט שנראה כמו ניקוי. סריקה של עד ארבע רשומות היא זולה,
  // והיא נכונה בשני המסלולים — גם ב-`Destroy()` שנקרא מתוך `Create()`.
  auto& slots = WindowSlots();
  for (auto it = slots.begin(); it != slots.end();) {
    it = ::IsWindow(it->first) ? std::next(it) : slots.erase(it);
  }

  splash_channel_.reset();
  multiwindow_channel_.reset();
  jumplist_channel_.reset();
  process_control_channel_.reset();
  if (flutter_controller_) {
    // ⚠️ הריסת המנוע קורית **בתוך** ה-window proc של WM_DESTROY. נמדד
    // שהריסת שני מנועים במקביל, משני threads, ננעלת — ולכן סגירת חלונות
    // חייבת להיות מסוריאלית. ראו docs/multi-window.md.
    flutter_controller_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

namespace {

bool RestoreLastHiddenWindow() {
  // ⚠️ `IsClosedByUser()` ולא `IsWindowVisible` — חלון שנוצר הרגע ועוד לא
  // הגיע לפריים הראשון אינו נראה, אבל המשתמש לא סגר אותו. השחזור שלו הציג
  // חלון באמצע טעינה (ריצוד) והחזיר true כאילו שוחזר חלון סגור.
  //
  // ⚠️ **לפי חותמת ההסתרה** ולא לפי סדר הרשימה: הסריקה מהסוף להתחלה היא
  // סדר יצירה הפוך, לא סדר סגירה.
  FlutterWindow* newest = nullptr;
  for (FlutterWindow* window : FlutterWindow::AllWindowsInProcess()) {
    if (window == nullptr || window->GetHandle() == nullptr) continue;
    if (!window->IsClosedByUser()) continue;
    if (newest == nullptr || window->hidden_at() > newest->hidden_at()) {
      newest = window;
    }
  }
  if (newest == nullptr) return false;
  // מחזיר בלי מטען: הכרטיסיות שהיו בחלון עדיין שם, וזה בדיוק מה
  // שהמשתמש מצפה לקבל בשחזור.
  newest->ReviveWith(std::string(), 0, 0);
  return true;
}

}  // namespace

void FlutterWindow::ReviveWith(const std::string& payload, int width,
                               int height, int origin_x, int origin_y,
                               const RECT* bounds) {
  const HWND self = GetHandle();
  if (!self) return;

  // ⚠️ מותנה. ספירה בלתי-מותנית ניפחה את המונה לצמיתות כשחלון שטרם נחשף
  // "מוחזר לשימוש", והתהליך אז לא יוצא לעולם.
  if (!counted_) {
    counted_ = true;
    g_live_window_count.fetch_add(1);
  }
  hidden_flag_->store(false);

  // ⚠️ `width`/`height` מגיעים מ-Dart והם **לוגיים**
  // (`windowManager.getSize` מחלק ב-DPR), אבל `SetWindowPos` מצפה
  // לפיקסלים פיזיים. בלי ההמרה חלון שהוחזר לשימוש במסך 150% קיבל 733
  // פיקסלים לוגיים במקום 1100 — כלומר התכווץ בכל פתיחה חוזרת.
  // ⚠️ ה-DPI של המסך שתחת נקודת השחרור, כמו במסלול היצירה — ולא של המסך
  // שבו החלון המוסתר הזדמן להיות. בלעדיו שחרור למסך 150% יצר חלון בגודל
  // 1.0×, וההידוק לאזור העבודה חושב על מידות קטנות מדי.
  UINT dpi = ::GetDpiForWindow(self);
  if (origin_x != 0 || origin_y != 0) {
    const POINT drop{origin_x, origin_y};
    dpi = FlutterDesktopGetDpiForMonitor(
        ::MonitorFromPoint(drop, MONITOR_DEFAULTTONEAREST));
  }
  const double scale = dpi / 96.0;
  const int final_width =
      width > 400 ? static_cast<int>(width * scale) : 0;
  const int final_height =
      height > 300 ? static_cast<int>(height * scale) : 0;
  if (bounds != nullptr) {
    // ⚠️ המסגרת שההצמדה נתנה, מילה במילה. חישוב מחדש ממיקום וגודל היה
    // מחמיץ אותה בפיקסלים, וחלון "כמעט מוצמד" נראה שבור.
    ::SetWindowPos(self, nullptr, bounds->left, bounds->top,
                   bounds->right - bounds->left, bounds->bottom - bounds->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
  } else if (origin_x != 0 || origin_y != 0) {
    // פינה שנמסרה: מזיזים **וגם** משנים גודל בקריאה אחת, כדי שלא
    // תיראה קפיצה בשני שלבים.
    RECT current{};
    ::GetWindowRect(self, &current);
    const int w = final_width > 0 ? final_width : current.right - current.left;
    const int h = final_height > 0 ? final_height : current.bottom - current.top;
    const POINT origin = OriginForDrop(origin_x, origin_y, w, h);
    ::SetWindowPos(self, nullptr, origin.x, origin.y, w, h,
                   SWP_NOZORDER | SWP_NOACTIVATE);
  } else if (final_width > 0 && final_height > 0) {
    ::SetWindowPos(self, nullptr, 0, 0, final_width, final_height,
                   SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
  }
  AllowActivation(self);
  // ⚠️ החזרת חלון לשימוש היא כוונה מפורשת — ראו
  // [Win32Window::ShouldVetoActivation].
  NoteUserActivation(self);
  ::ShowWindow(self, SW_SHOW);
  ::BringWindowToTop(self);
  ::SetForegroundWindow(self);
  // החלון האמיתי כאן — הרוח שהוקפאה במקום השחרור סיימה את תפקידה.
  drag_preview::End();

  // המטען מועבר ל-Dart בערוץ ולא כארגומנט לנקודת כניסה: המנוע כבר רץ,
  // ונקודת הכניסה שלו הורצה מזמן.
  if (multiwindow_channel_ && !payload.empty()) {
    multiwindow_channel_->InvokeMethod(
        "adoptPayload",
        std::make_unique<flutter::EncodableValue>(payload));
  }
}

// ⚠️ **הקולבק כאן רץ על ה-platform thread, ולא על thread הרסטר.**
//
// זו הייתה השערה שנבדקה ונשללה בחיפוש אחר מרוץ ההתנעה (~1% קריסה
// חוצת-threads בפתיחת חלון): קריאות Win32 מתוך קולבק של המנוע נראו כמו
// החשוד המובן מאליו. `flutter_windows.h` מפורש —
// *"The callback is executed only once on the platform thread"* — ולכן
// `ShowWindow`/`SetForegroundWindow` כאן תקינים, ואין טעם לחפש כאן שוב.
void FlutterWindow::RevealOnFirstFrame() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    ::ShowWindow(GetHandle(), SW_SHOW);
    return;
  }
  const HWND hwnd = GetHandle();
  const DWORD started = ::GetTickCount();
  flutter_controller_->engine()->SetNextFrameCallback([hwnd, started]() {
    if (!::IsWindow(hwnd)) return;
    // ⚠️ לפני ההצגה. עד כאן החלון לא היה יכול להיות מופעל כלל
    // ([kNoActivateUntilRevealed]) — זה מה שמנע את תנודת ההפעלות.
    AllowActivation(hwnd);
    // ⚠️ חשיפת חלון חדש היא כוונה מפורשת — ראו
    // [Win32Window::ShouldVetoActivation].
    Win32Window::NoteUserActivation(hwnd);
    ::ShowWindow(hwnd, SW_SHOW);
    ::BringWindowToTop(hwnd);
    ::SetForegroundWindow(hwnd);
    // החלון האמיתי על המסך — הרוח שהוקפאה במקום השחרור מוסתרת בדיוק
    // ברגע שיש מה להחליף אותה.
    drag_preview::End();
    // הזמן שהמשתמש באמת מרגיש: מהלחיצה ועד שמשהו מופיע על המסך.
    // ⚠️ אנגלית, ובמכוון: `printf` צר כותב UTF-8 גולמי לקונסולה שקוראת
    // אותו ב-code page 862, והשורה יצאה ג'יבריש.
    printf("[window] visible to user after %lums\n",
           ::GetTickCount() - started);
    fflush(stdout);
  });
  flutter_controller_->ForceRedraw();
}

void FlutterWindow::OnWindowHidden() {
  // ⚠️ הספירה יורדת כאן, בהסתרה, ולא ב-`OnDestroy`: החלון אינו נהרס
  // (ראו `kMsgDeferredDestroy`), ולכן `OnDestroy` לא ירוץ עד יציאת
  // התהליך — ומונה שלא יורד היה מונע לנצח פתיחת חלון חדש אחרי שהתקרה
  // הושגה, וגם מונע מהתהליך לצאת כשנסגר החלון האחרון.
  if (!counted_) {
    return;
  }
  counted_ = false;
  hidden_flag_->store(true);
  // חותמת ההסתרה קובעת את סדר השחזור ב-`RestoreLastHiddenWindow`.
  hidden_at_ = ++g_hidden_sequence;
  if (g_live_window_count.fetch_sub(1) > 1) {
    return;
  }

  // ⚠️ נסגר החלון האחרון. **לא** `PostQuitMessage`.
  //
  // `PostQuitMessage` מוציא את הלולאה ב-`main.cpp`, ואז `~FlutterWindow`
  // של החלון הראשי הורס את ה-controller ואת המנוע על ה-thread הראשי בעוד
  // מנועים של חלונות מוסתרים חיים — בדיוק התצורה ש-`win32_window.h`
  // מתעדת כקורסת, ושהמסלול הרגיל (`TerminateProcess`) קיים כדי להימנע
  // ממנה.
  //
  // המסלול הזה נגיש רק כשחלון הוסתר בלי לעבור את מסלול הסגירה של Dart
  // (שם `windowCount() <= 1` מוביל לכיבוי מלא). ה-flush הפר-חלוני כבר רץ
  // לפני `closeSelf`, ולכן אין כאן מה לשטוף — רק לצאת בבטחה.
  if (job_object_ready_.load()) {
    ::TerminateProcess(::GetCurrentProcess(), 0);
    return;  // לא נגיש בפועל.
  }
  // בלי Job Object אין למי להבטיח שתהליכי WebView2 הילדים ימותו איתנו,
  // ולכן נשארת היציאה המסודרת — אותה התנהגות שהייתה כאן קודם.
  OutputDebugStringW(L"Otzaria: last window hidden without a Job Object — "
                     L"falling back to PostQuitMessage.\n");
  ::PostQuitMessage(0);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // נפתח לפני שמעבירים ל-Flutter: זו הודעה פרטית שלנו, ואין לתוספים מה
  // לעשות איתה.
  if (message == kMsgOpenSecondaryWindow) {
    if (pending_secondary_windows_.empty()) return 0;
    PendingSecondaryWindow pending =
        std::move(pending_secondary_windows_.front());
    pending_secondary_windows_.pop();
    // ⚠️ ה-try אינו קוסמטי: הפונקציה `noexcept`, ובתוכה נוצר מנוע Flutter
    // ורצים `RegisterPlugins` של עשר DLL. חריגה כאן = `std::terminate`.
    bool created = false;
    try {
      created = CreateSecondaryWindowOnThisThread(
          project_, pending.payload, pending.width, pending.height,
          pending.origin_x, pending.origin_y,
          pending.has_bounds ? &pending.bounds : nullptr);
    } catch (...) {
      created = false;
    }
    // יצירה שנכשלה — אין מה להחליף את הרוח, והיא לא יכולה להישאר תלויה.
    if (!created) drag_preview::End();
    // ⚠️ **כאן** נענה Dart, ולא בטיפול בערוץ. זו התשובה שעל פיה הוא מוחק
    // את הכרטיסיה מהחלון המקורי.
    if (pending.result) {
      pending.result->Success(flutter::EncodableValue(created));
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
      if (pending) {
        replied = true;
        pending->Success(DescribeSystemDrag(drag, GetHandle()));
      }
    } catch (...) {
      drag_preview::End();
      // `null` ל-Dart פירושו "לא ידוע", והוא מטפל בו כ"אל תעשה כלום".
      if (pending && !replied) pending->Success(flutter::EncodableValue());
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
