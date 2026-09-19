#include "phantom_mouse_button_filter.h"

#include <commctrl.h>

namespace {

constexpr UINT_PTR kSubclassId = 0x1441;
constexpr WPARAM kButtonMask =
    MK_LBUTTON | MK_RBUTTON | MK_MBUTTON | MK_XBUTTON1 | MK_XBUTTON2;

// אותה חתימה שה-engine בודק כדי להתעלם מהודעות עכבר שמקורן במגע או בעט.
bool IsFromTouchOrPen() {
  constexpr LPARAM kTouchOrPenSignature = 0xFF515700;
  constexpr LPARAM kSignatureMask = 0xFFFFFF00;
  return (GetMessageExtraInfo() & kSignatureMask) == kTouchOrPenSignature;
}

WPARAM ButtonOf(UINT message, WPARAM wparam) {
  switch (message) {
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
      return MK_LBUTTON;
    case WM_RBUTTONDOWN:
    case WM_RBUTTONUP:
      return MK_RBUTTON;
    case WM_MBUTTONDOWN:
    case WM_MBUTTONUP:
      return MK_MBUTTON;
    case WM_XBUTTONDOWN:
    case WM_XBUTTONUP:
      return GET_XBUTTON_WPARAM(wparam) == XBUTTON1 ? MK_XBUTTON1
                                                    : MK_XBUTTON2;
  }
  return 0;
}

LRESULT CALLBACK FilterProc(HWND hwnd,
                            UINT message,
                            WPARAM wparam,
                            LPARAM lparam,
                            UINT_PTR,
                            DWORD_PTR ref_data) {
  // הכפתורים שה-engine ראה נלחצים בעכבר אמיתי; לכל חלון מנוע משלו.
  auto* pressed = reinterpret_cast<WPARAM*>(ref_data);
  switch (message) {
    case WM_LBUTTONDOWN:
    case WM_RBUTTONDOWN:
    case WM_MBUTTONDOWN:
    case WM_XBUTTONDOWN:
      if (!IsFromTouchOrPen()) *pressed |= ButtonOf(message, wparam);
      break;
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
    case WM_MBUTTONUP:
    case WM_XBUTTONUP:
      *pressed &= ~ButtonOf(message, wparam);
      break;
    case WM_MOUSEMOVE:
      if (!IsFromTouchOrPen()) {
        // רק מסירים: כפתור ששוחרר מחוץ לחלון עדיין מרפא את מצב ה-engine.
        *pressed &= wparam & kButtonMask;
        wparam = (wparam & ~kButtonMask) | *pressed;
      }
      break;
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, FilterProc, kSubclassId);
      delete pressed;
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

void InstallPhantomMouseButtonFilter(HWND flutter_view) {
  auto* pressed = new WPARAM(0);
  if (!SetWindowSubclass(flutter_view, FilterProc, kSubclassId,
                         reinterpret_cast<DWORD_PTR>(pressed))) {
    delete pressed;
  }
}
