#include "accessibility_request_filter.h"

#include <commctrl.h>
#include <uiautomation.h>

namespace {

constexpr UINT_PTR kSubclassId = 0x3336;

// Narrator אינו מדליק את SPI_GETSCREENREADER; הוא מסמן את עצמו רק כאן.
bool NarratorRunning() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  return RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Narrator\\NoRoam",
                      L"RunningState", RRF_RT_REG_DWORD, nullptr, &value,
                      &size) == ERROR_SUCCESS &&
         value != 0;
}

// קורא מסך שולח מאות בקשות בשנייה; רק תשובה חיובית נשמרת, כדי שקורא מסך
// שעלה זה עתה לא ייחסם.
bool ScreenReaderActive() {
  static ULONGLONG active_until = 0;
  const ULONGLONG now = GetTickCount64();
  if (now < active_until) return true;
  BOOL active = FALSE;
  if ((SystemParametersInfoW(SPI_GETSCREENREADER, 0, &active, 0) && active) ||
      NarratorRunning()) {
    active_until = now + 1000;
    return true;
  }
  return false;
}

LRESULT CALLBACK FilterProc(HWND hwnd,
                            UINT message,
                            WPARAM wparam,
                            LPARAM lparam,
                            UINT_PTR,
                            DWORD_PTR) {
  switch (message) {
    case WM_GETOBJECT: {
      const DWORD object_id =
          static_cast<DWORD>(static_cast<DWORD_PTR>(lparam));
      if ((object_id == static_cast<DWORD>(UiaRootObjectId) ||
           object_id == static_cast<DWORD>(OBJID_CLIENT)) &&
          !ScreenReaderActive()) {
        return DefWindowProcW(hwnd, message, wparam, lparam);
      }
      break;
    }
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, FilterProc, kSubclassId);
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

void InstallAccessibilityRequestFilter(HWND flutter_view) {
  SetWindowSubclass(flutter_view, FilterProc, kSubclassId, 0);
}
