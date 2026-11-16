#ifndef RUNNER_SNAP_LAYOUTS_H_
#define RUNNER_SNAP_LAYOUTS_H_

#include <windows.h>

#include <cstdint>
#include <functional>

// תפריט Snap Layouts של Windows 11 מעל כפתור ההגדלה שהאפליקציה מציירת
// (issue #4021). המערכת פותחת אותו רק כש-WM_NCHITTEST מחזיר HTMAXBUTTON.
namespace snap_layouts {

// [window] הוא המפתח שה-Dart שלח: 0 לחלון הראשי, אחרת ה-HWND של חלון Dart.
struct ButtonEvent {
  int64_t window = 0;
  bool hovered = false;
  bool pressed = false;
  bool clicked = false;
};

using EventSink = std::function<void(const ButtonEvent&)>;

// האם יש למערכת תפריט Snap Layouts (Windows 11 ומעלה).
bool IsSupported();

// [rect] בפיקסלים פיזיים של אזור הלקוח של [view]; מלבן ריק מכבה.
// ⚠️ ה-Dart שולח מלבן רק כשהכפתור חשוף לגמרי: מכאן ה-hit-test אינו שואל אותו.
bool SetMaximizeButton(HWND root, HWND view, int64_t window, const RECT& rect,
                       EventSink sink);

}  // namespace snap_layouts

#endif  // RUNNER_SNAP_LAYOUTS_H_
