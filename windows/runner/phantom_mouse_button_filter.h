#ifndef RUNNER_PHANTOM_MOUSE_BUTTON_FILTER_H_
#define RUNNER_PHANTOM_MOUSE_BUTTON_FILTER_H_

#include <windows.h>

// מסיר מ-WM_MOUSEMOVE כפתורים שהעכבר עצמו לא לחץ, לפני שה-engine רואה אותם.
// מגע מייצר לעיתים תנועה סינתטית בלי חתימת מגע, וה-engine הופך אותה ללחיצת
// עכבר שלא משתחררת — וכל מגע אחריה נקרא כצביטה (issue #1441).
void InstallPhantomMouseButtonFilter(HWND flutter_view);

#endif  // RUNNER_PHANTOM_MOUSE_BUTTON_FILTER_H_
