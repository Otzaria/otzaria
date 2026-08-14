#include "splash_window.h"

#include <windows.h>
#include <wincodec.h>  // WIC — פענוח PNG

#include <string>
#include <vector>

#pragma comment(lib, "windowscodecs.lib")

namespace {

const wchar_t* kSplashClassName = L"OtzariaSplashWindow";

// גודל הסמל בפיקסלים לוגיים.
constexpr int kIconLogicalSize = 160;
// אטימות כוללת ~70% (0.70 * 255), זהה ל-Opacity שהיה ב-SplashIcon.
constexpr BYTE kIconAlpha = 178;

// fade-in (הופעה הדרגתית) מתבצע *סינכרונית* ב-CreateSplashWindow, בזמן שה-thread
// הראשי חסום במחסום (WaitForSingleObject) — אז ה-thread של ה-splash חופשי
// להנפיש (אין loader-lock כי המנוע עוד לא נטען). fade-out (kIconAlpha→0) בסגירה,
// בלולאת ה-thread. שניהם מבוססי Sleep + UpdateLayeredWindow ישיר (DWM מרכיב כל
// עדכון) — *לא* WM_TIMER (שלא נורה ל-thread הזה תחת עומס האתחול).
constexpr UINT kFadeIntervalMs = 15;  // ~60fps
constexpr int kFadeInStep = 14;        // 178/14 ≈ 13 צעדים ≈ 195ms (fade-in)
constexpr int kFadeOutStep = 30;       // 178/30 ≈ 6 צעדים ≈ 90ms (fade-out)
// זמן תצוגה מינימלי (החזקה אחרי ה-fade-in): גם אם החשיפה (Close) מגיעה מוקדם
// (האפליקציה נטענת מהר), הסמל יוחזק לפחות זמן זה לפני ה-fade-out — מונע "הבזק".
constexpr ULONGLONG kMinDisplayMs = 800;
// זמן תצוגה מרבי: Close מגיע רק מ-Dart, כך שקריסה לפני חשיפת החלון הראשי
// הותירה את הסמל תלוי על המסך כל עוד התהליך חי. חייב להישאר גבוה מאתחול
// תקין הארוך ביותר — שחזור seforim.db (כמה GB) על דיסק קר נמשך דקות.
constexpr ULONGLONG kMaxDisplayMs = 300000;

// g_splash_hwnd נכתב ע"י ה-thread *לפני* SetEvent(g_created_event) ונקרא ע"י
// Close רק *אחרי* שה-WaitForSingleObject ב-Show חזר — האירוע מספק happens-before.
HWND g_splash_hwnd = nullptr;
HANDLE g_splash_thread = nullptr;
HANDLE g_created_event = nullptr;  // ה-thread מאותת עליו אחרי יצירת החלון
HANDLE g_close_event = nullptr;    // Close מסמן עליו → לולאת האנימציה עוברת ל-fade-out

// משאבי הציור (בבעלות ה-thread של ה-splash).
HDC g_mem_dc = nullptr;
HBITMAP g_dib = nullptr;
HGDIOBJ g_old_bmp = nullptr;
int g_disp = 0;
POINT g_pos = {0, 0};

// הסמל מפוענח מראש על ה-thread הראשי ב-Show() (שם windowscodecs.dll נטען בעוד
// ה-loader פנוי), כך שה-thread רק יוצר את החלון — מהיר, ללא I/O וללא COM.
std::vector<BYTE> g_icon_pixels;
int g_icon_disp = 0;

// מעדכן את אטימות החלון השכבתי (re-blit של אותו סמל עם SourceConstantAlpha חדש).
void ApplyLayeredAlpha(HWND hwnd, int alpha) {
  if (!g_mem_dc) return;
  if (alpha < 0) alpha = 0;
  if (alpha > 255) alpha = 255;
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, static_cast<BYTE>(alpha),
                         AC_SRC_ALPHA};
  POINT src = {0, 0};
  SIZE sz = {g_disp, g_disp};
  UpdateLayeredWindow(hwnd, nullptr, &g_pos, &sz, g_mem_dc, &src, 0, &blend,
                      ULW_ALPHA);
}

LRESULT CALLBACK SplashWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                               LPARAM lparam) {
  if (msg == WM_DESTROY) {
    if (g_mem_dc) {
      if (g_old_bmp) SelectObject(g_mem_dc, g_old_bmp);
      DeleteDC(g_mem_dc);
      g_mem_dc = nullptr;
    }
    if (g_dib) {
      DeleteObject(g_dib);
      g_dib = nullptr;
    }
    return 0;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

// תיקיית קובץ ההרצה (ללא לוכסן בסוף).
std::wstring ExecutableDir() {
  wchar_t buffer[MAX_PATH];
  DWORD len = GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return std::wstring();
  }
  std::wstring path(buffer, len);
  size_t pos = path.find_last_of(L"\\/");
  if (pos == std::wstring::npos) {
    return std::wstring();
  }
  return path.substr(0, pos);
}

// DPI המערכת (מסך ראשי). GetDpiForSystem זמין מ-Windows 10 1607; טעינה
// דינמית עם fallback ל-GetDeviceCaps כדי שלא ניפול בסביבות ישנות.
UINT SystemDpi() {
  if (HMODULE user32 = GetModuleHandleW(L"user32.dll")) {
    using GetDpiForSystemFn = UINT(WINAPI*)();
    auto fn = reinterpret_cast<GetDpiForSystemFn>(
        GetProcAddress(user32, "GetDpiForSystem"));
    if (fn) {
      UINT dpi = fn();
      if (dpi != 0) {
        return dpi;
      }
    }
  }
  HDC dc = GetDC(nullptr);
  UINT dpi = dc ? static_cast<UINT>(GetDeviceCaps(dc, LOGPIXELSX)) : 96;
  if (dc) {
    ReleaseDC(nullptr, dc);
  }
  return dpi != 0 ? dpi : 96;
}

// טוען PNG דרך WIC, מקנה גודל ל-[target] x [target] ומחזיר מאגר BGRA
// מוכפל-אלפא (32bppPBGRA) — הפורמט ש-UpdateLayeredWindow מצפה לו.
bool LoadIconScaled(const std::wstring& path, int target,
                    std::vector<BYTE>* out_pixels) {
  IWICImagingFactory* factory = nullptr;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
    return false;
  }

  IWICBitmapDecoder* decoder = nullptr;
  IWICBitmapFrameDecode* frame = nullptr;
  IWICBitmapScaler* scaler = nullptr;
  IWICFormatConverter* converter = nullptr;
  bool ok = false;
  do {
    if (FAILED(factory->CreateDecoderFromFilename(
            path.c_str(), nullptr, GENERIC_READ,
            WICDecodeMetadataCacheOnDemand, &decoder))) {
      break;
    }
    if (FAILED(decoder->GetFrame(0, &frame))) {
      break;
    }
    if (FAILED(factory->CreateBitmapScaler(&scaler))) {
      break;
    }
    if (FAILED(scaler->Initialize(frame, target, target,
                                  WICBitmapInterpolationModeFant))) {
      break;
    }
    if (FAILED(factory->CreateFormatConverter(&converter))) {
      break;
    }
    if (FAILED(converter->Initialize(scaler, GUID_WICPixelFormat32bppPBGRA,
                                     WICBitmapDitherTypeNone, nullptr, 0.0,
                                     WICBitmapPaletteTypeCustom))) {
      break;
    }
    const UINT stride = static_cast<UINT>(target) * 4;
    out_pixels->resize(static_cast<size_t>(stride) * target);
    if (FAILED(converter->CopyPixels(nullptr, stride,
                                     static_cast<UINT>(out_pixels->size()),
                                     out_pixels->data()))) {
      break;
    }
    ok = true;
  } while (false);

  if (converter) converter->Release();
  if (scaler) scaler->Release();
  if (frame) frame->Release();
  if (decoder) decoder->Release();
  if (factory) factory->Release();
  return ok;
}

// יוצר את חלון ה-splash מהפיקסלים המפוענחים-מראש, באטימות 0 (שקוף).
// מהיר, ללא I/O/COM. מחזיר את ה-HWND, או nullptr בכשל.
HWND CreateSplashWindow() {
  const int disp = g_icon_disp;
  g_disp = disp;
  if (disp <= 0 || g_icon_pixels.empty()) {
    return nullptr;
  }

  HINSTANCE hinst = GetModuleHandleW(nullptr);
  WNDCLASSW wc = {};
  wc.lpfnWndProc = SplashWndProc;
  wc.hInstance = hinst;
  wc.lpszClassName = kSplashClassName;
  RegisterClassW(&wc);  // אם כבר רשום — נכשל בשקט, וזה תקין.

  // ממורכז על אזור-העבודה של המסך הראשי.
  HMONITOR mon = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi = {sizeof(MONITORINFO)};
  GetMonitorInfo(mon, &mi);
  const int x =
      mi.rcWork.left + ((mi.rcWork.right - mi.rcWork.left) - disp) / 2;
  const int y =
      mi.rcWork.top + ((mi.rcWork.bottom - mi.rcWork.top) - disp) / 2;
  g_pos = {x, y};

  HWND hwnd = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_TOPMOST |
          WS_EX_NOACTIVATE,
      kSplashClassName, L"", WS_POPUP, x, y, disp, disp, nullptr, nullptr,
      hinst, nullptr);
  if (!hwnd) {
    return nullptr;
  }

  HDC screen_dc = GetDC(nullptr);
  g_mem_dc = CreateCompatibleDC(screen_dc);
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = disp;
  bmi.bmiHeader.biHeight = -disp;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  g_dib = CreateDIBSection(screen_dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  bool have_pixels = false;
  if (g_dib && bits) {
    memcpy(bits, g_icon_pixels.data(), g_icon_pixels.size());
    g_old_bmp = SelectObject(g_mem_dc, g_dib);
    ApplyLayeredAlpha(hwnd, 0);  // מתחילים שקוף (לפני fade-in).
    have_pixels = true;
  }
  ReleaseDC(nullptr, screen_dc);

  // SW_SHOWNOACTIVATE — לא לחטוף פוקוס מהחלון הראשי כשהוא ייפתח.
  ShowWindow(hwnd, SW_SHOWNOACTIVATE);

  // fade-in סינכרוני: נקרא בעוד ה-thread הראשי חסום במחסום שב-Show (לא טוען
  // DLLs), כך שה-thread של ה-splash חופשי להנפיש עד הסוף ללא loader-lock.
  // ה-thread הראשי ימשיך רק אחרי שזה יסתיים (SetEvent אחרי החזרה מכאן).
  if (have_pixels) {
    for (int a = kFadeInStep; a < kIconAlpha; a += kFadeInStep) {
      ApplyLayeredAlpha(hwnd, a);
      Sleep(kFadeIntervalMs);
    }
    ApplyLayeredAlpha(hwnd, kIconAlpha);
  }
  return hwnd;
}

DWORD WINAPI SplashThreadProc(LPVOID) {
  // CoInitializeEx על ה-thread (לא נחוץ ל-GDI, אך תואם לסביבת thread "GUI").
  const HRESULT co = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  HWND hwnd = CreateSplashWindow();
  g_splash_hwnd = hwnd;
  // מאותתים ל-Show() שהיצירה הושלמה — כך ה-thread הראשי ממשיך רק אחרי שהחלון
  // קיים, *לפני* שהוא טוען את ה-DLLs של המנוע (שהיו מחזיקים את ה-loader lock).
  SetEvent(g_created_event);

  if (hwnd != nullptr) {
    // החלון כבר באטימות מלאה (הוצג ב-CreateSplashWindow). כאן מחזיקים אותו —
    // שואבים הודעות (מונע "not responding") וממתינים לאות הסגירה (g_close_event)
    // ואז מבצעים fade-out מבוסס Sleep + UpdateLayeredWindow ישיר (לא WM_TIMER).
    int alpha = kIconAlpha;
    const ULONGLONG start = GetTickCount64();
    bool closing = false;
    for (;;) {
      MSG msg;
      while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
      }
      if (!closing && WaitForSingleObject(g_close_event, 0) == WAIT_OBJECT_0) {
        closing = true;
      }
      if (!closing && (GetTickCount64() - start) >= kMaxDisplayMs) {
        closing = true;
      }
      // מתחילים fade-out רק אחרי שעבר זמן התצוגה המינימלי (מונע הבזק).
      if (closing && (GetTickCount64() - start) >= kMinDisplayMs) {
        alpha -= kFadeOutStep;
        if (alpha <= 0) {
          break;
        }
        ApplyLayeredAlpha(hwnd, alpha);
      }
      Sleep(kFadeIntervalMs);
    }
    DestroyWindow(hwnd);  // → WM_DESTROY → ניקוי
    g_splash_hwnd = nullptr;
  }

  // g_close_event אינו נסגר כאן: מאז שה-thread מסיים גם מעצמו (kMaxDisplayMs)
  // ולא רק בעקבות Close, סגירה כאן עלולה להקדים SetEvent על ידית משוחררת.
  // ידית בודדת לכל חיי התהליך — המערכת משחררת אותה ביציאה.
  if (SUCCEEDED(co)) {
    CoUninitialize();
  }
  return 0;
}

}  // namespace

namespace splash {

void Show() {
  if (g_splash_thread) {
    return;
  }

  // פענוח הסמל על ה-thread הראשי (windowscodecs.dll נטען כאן, בעוד ה-loader פנוי).
  const UINT dpi = SystemDpi();
  g_icon_disp = MulDiv(kIconLogicalSize, static_cast<int>(dpi), 96);
  const std::wstring icon_path = ExecutableDir() +
      L"\\data\\flutter_assets\\assets\\icon\\iconnew.png";
  if (!LoadIconScaled(icon_path, g_icon_disp, &g_icon_pixels)) {
    return;  // ללא splash; האפליקציה ממשיכה.
  }

  g_close_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);     // manual-reset
  g_created_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_splash_hwnd = nullptr;
  g_splash_thread =
      CreateThread(nullptr, 0, SplashThreadProc, nullptr, 0, nullptr);

  // מחסום: ממתינים שה-thread ייצור את החלון *ויסיים את ה-fade-in* לפני שנמשיך
  // (וה-thread הראשי יתחיל לטעון את ה-DLLs של המנוע — מה שהיה מחזיק את ה-loader
  // lock וחוסם את לולאת ה-fade-in). זה מוסיף את משך ה-fade-in (~200ms) לזמן
  // הפתיחה, אך מבטיח שההתבהרות תרוץ חלק. ה-timeout הוא רשת ביטחון בלבד.
  if (g_created_event) {
    WaitForSingleObject(g_created_event, 2000);
    CloseHandle(g_created_event);
    g_created_event = nullptr;
  }
}

void Close() {
  // נקרא על ה-thread הראשי בעת חשיפת החלון הראשי. מסמן ללולאת האנימציה לעבור
  // ל-fade-out (לא ממתין — ה-thread משמיד את החלון בסיום). מוגן מפני קריאה כפולה.
  if (g_splash_thread == nullptr) {
    return;
  }
  if (g_close_event != nullptr) {
    SetEvent(g_close_event);
  }
  CloseHandle(g_splash_thread);
  g_splash_thread = nullptr;
}

bool IsAnyInstanceShowing() {
  return FindWindowW(kSplashClassName, nullptr) != nullptr;
}

}  // namespace splash
