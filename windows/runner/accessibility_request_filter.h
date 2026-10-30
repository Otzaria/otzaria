#ifndef RUNNER_ACCESSIBILITY_REQUEST_FILTER_H_
#define RUNNER_ACCESSIBILITY_REQUEST_FILTER_H_

#include <windows.h>

// בקשת נגישות אחת (MSAA/UIA) מדליקה את גשר הנגישות של ה-engine לכל התהליך, והוא
// קורס על עדכונים שמעבירים צמתים (#3336). בלי קורא מסך הבקשה לא מגיעה ל-engine.
// TODO: למחוק כשה-engine יתקן את flutter/flutter#175041.
void InstallAccessibilityRequestFilter(HWND flutter_view);

#endif  // RUNNER_ACCESSIBILITY_REQUEST_FILTER_H_
