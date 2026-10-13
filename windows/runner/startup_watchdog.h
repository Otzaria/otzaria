#ifndef RUNNER_STARTUP_WATCHDOG_H_
#define RUNNER_STARTUP_WATCHDOG_H_

#include <string>

// גלאי תקיעות של ה-thread הראשי, בעלייה ובזמן השימוש. ב-Windows ה-UI isolate
// של Dart רץ על ה-thread הזה, ולכן קוד סינכרוני חוסם גם פריימים וגם טיימרים.
namespace startup_watchdog {

// מתחיל את הניטור. יש לקרוא מה-thread הראשי לפני לולאת ההודעות.
void Start();

// מרענן את snapshot המודולים בנקודה בטוחה ב-thread הראשי.
void RefreshModules();

// עובר לניטור קיפאון בזמן השימוש. יש לקרוא מה-thread הראשי בחשיפת החלון.
void EnterRuntimeMode();

// מה שהמשתמש רואה כעת, לצירוף לדוחות הקיפאון.
void SetContext(const std::string& context);

// מבקש עצירה בלי להמתין ל-watcher.
void RequestStop();

// משלים עצירה ושחרור משאבים ביציאה. בטוח לקריאה חוזרת.
void Stop();

}  // namespace startup_watchdog

#endif  // RUNNER_STARTUP_WATCHDOG_H_
