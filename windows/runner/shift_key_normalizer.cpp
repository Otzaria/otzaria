#include "shift_key_normalizer.h"

#include <commctrl.h>

namespace {

constexpr UINT_PTR kSubclassId = 0x1645;
constexpr UINT kScanCodeShiftLeft = 0x2A;
constexpr UINT kScanCodeShiftRight = 0x36;
constexpr LPARAM kScanCodeMask = 0x00FF0000;
constexpr LPARAM kExtendedBit = 0x01000000;

LPARAM CompleteControlVScanCode(WPARAM key, LPARAM flags) {
  if ((flags & kScanCodeMask) != 0) return flags;
  const bool extended = (flags & kExtendedBit) != 0;
  UINT virtual_key = static_cast<UINT>(key);
  if (key == VK_CONTROL) {
    virtual_key = extended ? VK_RCONTROL : VK_LCONTROL;
  } else if (key != VK_LCONTROL && key != VK_RCONTROL && key != 'V') {
    return flags;
  }
  const UINT mapped = MapVirtualKeyExW(
      virtual_key, MAPVK_VK_TO_VSC_EX, GetKeyboardLayout(0));
  const UINT scan_code = mapped & 0xff;
  const UINT prefix = mapped & 0xff00;
  if (scan_code == 0 || (prefix != 0 && prefix != 0xe000) ||
      (prefix == 0xe000) != extended) {
    return flags;
  }
  // קוד חסר גורם ל-Ctrl ול-V לחלוק מקש פיזי ב-Flutter.
  // רק קוד הסריקה מושלם; מצב המקשים והודעות ההדבקה נשארים בידי Windows.
  return flags | (static_cast<LPARAM>(scan_code) << 16);
}

LRESULT CALLBACK NormalizerProc(HWND hwnd,
                                UINT message,
                                WPARAM wparam,
                                LPARAM lparam,
                                UINT_PTR,
                                DWORD_PTR) {
  switch (message) {
    case WM_KEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP:
      if (wparam == VK_SHIFT) {
        // כל צד מקבל את ה-scancode התקני שלו; כך סנכרון ה-modifiers של ה-engine
        // בתזוזת עכבר מרפא גם Shift שהשחרור שלו אבד.
        const UINT scancode = (lparam & kScanCodeMask) >> 16;
        const UINT normalized = scancode == kScanCodeShiftRight
                                    ? kScanCodeShiftRight
                                    : kScanCodeShiftLeft;
        lparam = (lparam & ~(kScanCodeMask | kExtendedBit)) |
                 (static_cast<LPARAM>(normalized) << 16);
      } else {
        lparam = CompleteControlVScanCode(wparam, lparam);
      }
      break;
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, NormalizerProc, kSubclassId);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

void InstallShiftKeyNormalizer(HWND flutter_view) {
  SetWindowSubclass(flutter_view, NormalizerProc, kSubclassId, 0);
}

void NormalizeFlutterKeyboardMessage(MSG& message) {
  switch (message.message) {
    case WM_KEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP: {
      DWORD_PTR reference = 0;
      if (GetWindowSubclass(message.hwnd, NormalizerProc, kSubclassId,
                            &reference)) {
        message.lParam =
            CompleteControlVScanCode(message.wParam, message.lParam);
      }
      break;
    }
  }
}
