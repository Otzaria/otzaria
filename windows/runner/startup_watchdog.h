#ifndef RUNNER_STARTUP_WATCHDOG_H_
#define RUNNER_STARTUP_WATCHDOG_H_

#include <windows.h>

#include <string>
#include <vector>

// גלאי תקיעות של ה-thread הראשי בעלייה. ב-Windows ה-UI isolate של Dart רץ על
// ה-thread הזה, ולכן קוד נייטיב סינכרוני חוסם גם את הפריימים וגם את הטיימרים.
namespace startup_watchdog {

// מתחיל את הניטור. יש לקרוא מה-thread הראשי לפני לולאת ההודעות.
void Start();

// מרענן את snapshot המודולים בנקודה בטוחה ב-thread הראשי.
void RefreshModules();

// מבקש עצירה בלי להמתין ל-watcher. יש לקרוא במסלול חשיפת החלון.
void RequestStop();

// משלים עצירה ושחרור משאבים ביציאה. בטוח לקריאה חוזרת.
void Stop();

// כלים משותפים לגלאי התקיעה בזמן ריצה (hang_monitor). ה-handle של ה-thread
// הראשי חי עד Stop, ולכן יש לעצור את hang_monitor לפניו.
bool CaptureMainStack(std::vector<ULONG_PTR>* frames);
// מתרגם לשמות מודולים — רק אחרי ש-CaptureMainStack חידש את ה-thread.
void AppendStack(const std::vector<ULONG_PTR>& frames, std::string* report);
// commit הבנייה ו-build-id של app.so — מזהים את קובצי הסמלים לפענוח.
void AppendBuildIdentity(const std::vector<ULONG_PTR>& frames,
                         std::string* report);
void AppendReport(const std::string& text);
std::string UtcTimestamp();

}  // namespace startup_watchdog

#endif  // RUNNER_STARTUP_WATCHDOG_H_
