#ifndef RUNNER_ACCESSIBILITY_PROBE_H_
#define RUNNER_ACCESSIBILITY_PROBE_H_

#include <windows.h>

#include <string>

// רושם את בקשת הנגישות הראשונה (WM_GETOBJECT) שתצוגת Flutter קיבלה, ומי
// שלח אותה: UIA או MSAA. היא שמדליקה את גשר הנגישות של המנוע.
namespace accessibility_probe {

// מתקין על תצוגת Flutter; מסיר את עצמו אחרי הבקשה הראשונה.
void Install(HWND flutter_view);

// מוסיף שורת `Accessibility:` לרשומה, אם הגיעה בקשה.
void AppendFirstRequest(std::string* report);

}  // namespace accessibility_probe

#endif  // RUNNER_ACCESSIBILITY_PROBE_H_
