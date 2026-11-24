#include "win32_window.h"

#include <atomic>
#include <dwmapi.h>
#include <flutter_windows.h>

#include "activation_gate.h"
#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
// ⚠️ חלונות נוספים נוצרים על אותו thread (ראו docs/multi-window.md), ולכן
// המונה הזה נקרא ונכתב משני threads. כ-`int` רגיל זה מרוץ נתונים: שני
// חלונות שנסגרים במקביל עלולים שניהם לראות 0 ולבטל את רישום המחלקה
// פעמיים, או לפספס את האפס ולא לבטל כלל. בחלון יחיד זה לא הופיע.
static std::atomic<int> g_active_window_count{0};

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  //
  // ⚠️ אתחול עצל ב-`if (!instance_)` אינו בטוח כששני threads יוצרים
  // חלונות במקביל — שניהם עלולים לראות null ולהקצות. סינגלטון מקומי-סטטי
  // מובטח על ידי התקן כבטוח ל-threads מאז C++11.
  static WindowClassRegistrar* GetInstance() {
    static WindowClassRegistrar instance;
    return &instance;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  bool class_registered_ = false;
};

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

namespace {

// החלון שהמשתמש בחר לאחרונה בלחיצה, והרגע שבו.
//
// ⚠️ הבסיס ל-[Win32Window::ShouldVetoActivation] — ראו שם.
otzaria::ActivationGate<HWND> g_activation_gate;

// רק חלונות של ה-thread הזה; מחלקת המנוע קיימת גם בתוכנות Flutter אחרות.
std::wstring WindowClassOf(HWND window) {
  wchar_t name[64] = {0};
  if (::GetWindowThreadProcessId(window, nullptr) == ::GetCurrentThreadId()) {
    ::GetClassNameW(window, name, sizeof(name) / sizeof(name[0]));
  }
  return name;
}

bool IsShownWindow(HWND window) {
  return ::IsWindow(window) && ::IsWindowVisible(window);
}

}  // namespace

void Win32Window::NoteUserActivation(HWND window) {
  g_activation_gate.NoteUserActivation(window, ::GetTickCount64());
}

bool Win32Window::ShouldVetoActivation(HWND window) {
  return g_activation_gate.ShouldVetoActivation(window, ::GetTickCount64(),
                                                WindowClassOf, IsShownWindow);
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOW);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      // ⚠️ ההריסה אינה מותנית ב-`quit_on_close_` — הדגל אומר "סגירת החלון
      // הזה מסיימת את התהליך", ולא "מותר לסגור אותו" — ואינה מיידית.
      // ראו `kMsgDeferredDestroy`.
      ::PostMessageW(hwnd, kMsgDeferredDestroy, 0, 0);
      return 0;

    case kMsgDeferredDestroy:
      // מוסתר ולא נהרס — ראו ההערה ליד `kMsgDeferredDestroy`.
      ShowWindow(hwnd, SW_HIDE);
      OnWindowHidden();
      return 0;

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_MOUSEACTIVATE:
      // בחירה מפורשת של המשתמש — ראו [ShouldVetoActivation].
      NoteUserActivation(hwnd);
      break;

    case WM_ACTIVATE:
      // ⚠️ **רק בהפעלה, לא בביטול הפעלה.** זו שורה מקוד ה-runner
      // הסטנדרטי של Flutter, והיא תקינה בחלון יחיד בלבד.
      //
      // `WM_ACTIVATE` נשלח גם עם `WA_INACTIVE`, כשהחלון **מאבד** הפעלה.
      // בלי הבדיקה, חלון שהמשתמש עזב קרא ל-`SetFocus` על התוכן של עצמו —
      // ו-`SetFocus` על חלון באותו thread מפעיל גם את החלון העליון שלו.
      // כלומר: המשתמש לוחץ על חלון ב', א' מקבל `WA_INACTIVE`, גונב את
      // הפוקוס בחזרה, ב' מקבל `WA_INACTIVE` וגונב אותו שוב — לולאה.
      //
      // זה בדיוק מה שהמשתמש דיווח: לחיצה על החלון התחתון משאירה את
      // הפוקוס בעליון, והאזור החופף מרצד בלי סוף כאילו החלונות רבים מי
      // יהיה למעלה. בחלון יחיד אין מי שיתחרה, ולכן זה מעולם לא נראה.
      //
      // ⚠️ וגם **רק כשהחלון גלוי**. חלון מוסתר שקיבל הפעלה (המנוע קורא
      // `SetFocus` על ה-view שלו ביצירה) היה מושך את הפוקוס אל התוכן שלו
      // ובכך מחזק הפעלה מדומה, ומצטרף לתנודה במקום לשבור אותה.
      //
      // ⚠️ וגם **רק כשיש מה לשנות**. `SetFocus` יוצר הודעות מיקוד והפעלה
      // נוספות, ועם כמה חלונות עליונים על אותו thread כל אחד מהם הגיב
      // עליהן בהצבת מיקוד משלו — נמדדה תנודה **אינסופית** של הפעלות כל
      // ~16ms בין שלושה חלונות (783 הפעלות בהרצה של 40 שניות; עם הבדיקה
      // הזו: 77, ובלי לולאה). הגידור ב-`WA_INACTIVE` לבדו שבר רק את
      // המקרה הפשוט של שני חלונות.
      if (LOWORD(wparam) != WA_INACTIVE && child_content_ != nullptr &&
          ::IsWindowVisible(hwnd) && ::GetFocus() != child_content_) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  // רק כשהחלון גלוי: `SetFocus` על ילד מפעיל את החלון העליון, והראשי נוצר
  // מוסתר. `WM_ACTIVATE` ממקד את התוכן בחשיפה.
  if (::IsWindowVisible(window_handle_)) {
    SetFocus(child_content_);
  }
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}

void Win32Window::OnWindowHidden() {}
