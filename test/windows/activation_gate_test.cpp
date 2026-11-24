#include "activation_gate.h"

#include <iostream>

namespace {

int failures = 0;

void Check(bool ok, const char* name) {
  std::cout << (ok ? "ok   " : "FAIL ") << name << '\n';
  if (!ok) ++failures;
}

enum Window {
  kNone,
  kMain,
  kDart,
  kOtherDart,
  kForeign,
  kInactive,
  kMainView,
  kDartView,
  kOtherDartView,
  kForeignView,
  kDetachedView,
  kOtherControl,
};

otzaria::FocusWindowClass ClassOf(Window window) {
  using otzaria::ClassifyFocusWindow;
  switch (window) {
    case kMain:
      return ClassifyFocusWindow(L"FLUTTER_RUNNER_WIN32_WINDOW");
    case kDart:
    case kOtherDart:
    case kInactive:
      return ClassifyFocusWindow(L"FLUTTER_HOST_WINDOW");
    case kMainView:
    case kDartView:
    case kOtherDartView:
    case kForeignView:
    case kDetachedView:
      return ClassifyFocusWindow(L"FLUTTERVIEW");
    case kOtherControl:
      return ClassifyFocusWindow(L"Edit");
    default:
      return ClassifyFocusWindow(L"");
  }
}

Window RootOf(Window window) {
  switch (window) {
    case kMainView:
      return kMain;
    case kDartView:
    case kOtherControl:
      return kDart;
    case kOtherDartView:
      return kOtherDart;
    case kForeignView:
      return kForeign;
    default:
      return kNone;
  }
}

void TestFocusPolicy() {
  const auto veto = [](Window target, Window active) {
    return otzaria::ShouldVetoViewFocus(target, active, ClassOf, RootOf,
                                       [](Window w) { return w != kInactive; });
  };
  Check(veto(kMainView, kDart), "runner view cannot reclaim focus from Dart");
  Check(veto(kDartView, kMain), "Dart view cannot reclaim focus from runner");
  Check(veto(kOtherDartView, kDart), "Dart views cannot reclaim from each other");
  Check(!veto(kDartView, kDart), "focus within the active Dart window");
  Check(!veto(kMainView, kMain), "focus within the active runner");
  Check(!veto(kDart, kMain), "focus on a top-level window");
  Check(!veto(kOtherControl, kMain), "focus on a non-Flutter control");
  Check(!veto(kDartView, kForeign), "foreign active window");
  Check(!veto(kForeignView, kDart), "Flutter view outside Otzaria");
  Check(!veto(kDetachedView, kMain), "Flutter view without a host");
  Check(!veto(kMainView, kInactive), "active window cannot retain focus");
  Check(!veto(kDartView, kNone), "no active window");
  Check(!veto(kNone, kMain), "clearing focus");
}

#ifdef _WIN32
constexpr wchar_t kRunnerClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kDartClass[] = L"FLUTTER_HOST_WINDOW";
constexpr wchar_t kViewClass[] = L"FLUTTERVIEW";

LRESULT CALLBACK TestWindowProc(HWND window, UINT message, WPARAM wparam,
                               LPARAM lparam) {
  if (message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE) {
    if (const HWND child = ::FindWindowExW(window, nullptr, kViewClass, nullptr)) {
      ::SetFocus(child);
      return 0;
    }
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

bool RegisterTestClass(const wchar_t* name) {
  WNDCLASSW definition = {};
  definition.hInstance = ::GetModuleHandleW(nullptr);
  definition.lpszClassName = name;
  definition.lpfnWndProc = TestWindowProc;
  return ::RegisterClassW(&definition) != 0;
}

HWND CreateTestWindow(const wchar_t* name, HWND parent = nullptr) {
  const DWORD style = parent ? WS_CHILD | WS_VISIBLE : WS_OVERLAPPEDWINDOW;
  return ::CreateWindowExW(0, name, L"Window focus test", style, 20, 20, 250,
                           150, parent, nullptr, ::GetModuleHandleW(nullptr),
                           nullptr);
}

void TestNativeFocus() {
  if (!RegisterTestClass(kRunnerClass) || !RegisterTestClass(kDartClass) ||
      !RegisterTestClass(kViewClass)) {
    Check(false, "register test window classes");
    return;
  }
  const HWND runner = CreateTestWindow(kRunnerClass);
  const HWND dart = CreateTestWindow(kDartClass);
  const HWND reveal = CreateTestWindow(kDartClass);
  const HWND runner_view = runner ? CreateTestWindow(kViewClass, runner) : nullptr;
  const HWND dart_view = dart ? CreateTestWindow(kViewClass, dart) : nullptr;
  const HWND reveal_view = reveal ? CreateTestWindow(kViewClass, reveal) : nullptr;
  const HWND edit = runner ? CreateTestWindow(L"EDIT", runner) : nullptr;
  if (!runner || !dart || !reveal || !runner_view || !dart_view || !reveal_view ||
      !edit) {
    Check(false, "create native test windows");
    return;
  }

  ::ShowWindow(runner, SW_SHOWNORMAL);
  ::ShowWindow(dart, SW_SHOWNA);
  ::SetActiveWindow(dart);
  Check(::GetActiveWindow() == dart && ::GetFocus() == dart_view,
        "control: Dart starts active");
  ::SetFocus(runner_view);
  Check(::GetActiveWindow() == runner && ::GetFocus() == runner_view,
        "control: SetFocus on another Flutter child activates its parent");

  const HHOOK hook = otzaria::InstallViewFocusGuard();
  if (!hook) {
    Check(false, "install native CBT hook");
    return;
  }
  ::SetActiveWindow(dart);
  Check(::GetActiveWindow() == dart && ::GetFocus() == dart_view,
        "SetActiveWindow transfers activation and keyboard focus");
  ::SetFocus(runner_view);
  Check(::GetActiveWindow() == dart && ::GetFocus() == dart_view,
        "stale Flutter SetFocus leaves Dart active and focused");

  ::SetFocus(edit);
  Check(::GetActiveWindow() == runner && ::GetFocus() == edit,
        "an ordinary Win32 control can still take focus");
  ::SetFocus(runner_view);
  Check(::GetActiveWindow() == runner && ::GetFocus() == runner_view,
        "Flutter focus can return from a control in the active window");
  ::SetFocus(dart_view);
  Check(::GetActiveWindow() == runner && ::GetFocus() == runner_view,
        "stale Flutter SetFocus leaves the runner active");

  ::ShowWindow(reveal, SW_SHOWNORMAL);
  Check(::IsWindowVisible(reveal) && ::GetActiveWindow() == reveal &&
            ::GetFocus() == reveal_view,
        "first-frame ShowWindow transfers activation and keyboard focus");
  ::ShowWindow(reveal, SW_HIDE);
  ::SetActiveWindow(runner);
  ::ShowWindow(reveal, SW_SHOWNA);
  Check(::IsWindowVisible(reveal) && ::GetActiveWindow() == runner &&
            ::GetFocus() == runner_view,
        "non-activating show leaves the current window focused");

  Check(::UnhookWindowsHookEx(hook) != FALSE, "remove native CBT hook");
  ::DestroyWindow(reveal);
  ::DestroyWindow(dart);
  ::DestroyWindow(runner);
}
#endif

}  // namespace

int main() {
  TestFocusPolicy();
#ifdef _WIN32
  TestNativeFocus();
#endif
  return failures == 0 ? 0 : 1;
}
