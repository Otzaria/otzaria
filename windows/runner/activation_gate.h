#ifndef RUNNER_ACTIVATION_GATE_H_
#define RUNNER_ACTIVATION_GATE_H_

#include <string_view>

#ifdef _WIN32
#include <windows.h>
#endif

namespace otzaria {

enum class FocusWindowClass { kOther, kRunner, kDartHost, kFlutterView };

inline FocusWindowClass ClassifyFocusWindow(std::wstring_view name) {
  if (name == L"FLUTTER_RUNNER_WIN32_WINDOW") return FocusWindowClass::kRunner;
  if (name == L"FLUTTER_HOST_WINDOW") return FocusWindowClass::kDartHost;
  if (name == L"FLUTTERVIEW") return FocusWindowClass::kFlutterView;
  return FocusWindowClass::kOther;
}

inline bool IsOtzariaTopLevel(FocusWindowClass window_class) {
  return window_class == FocusWindowClass::kRunner ||
         window_class == FocusWindowClass::kDartHost;
}

template <typename Window, typename ClassOf, typename RootOf,
          typename CanKeepFocus>
bool ShouldVetoViewFocus(Window target, Window active, ClassOf class_of,
                         RootOf root_of, CanKeepFocus can_keep_focus) {
  if (!target || !active || class_of(target) != FocusWindowClass::kFlutterView) {
    return false;
  }
  const Window root = root_of(target);
  return root && root != active && IsOtzariaTopLevel(class_of(root)) &&
         IsOtzariaTopLevel(class_of(active)) && can_keep_focus(active);
}

#ifdef _WIN32
inline FocusWindowClass FocusWindowClassOnCurrentThread(HWND window) {
  if (::GetWindowThreadProcessId(window, nullptr) != ::GetCurrentThreadId()) {
    return FocusWindowClass::kOther;
  }
  wchar_t name[64] = {};
  ::GetClassNameW(window, name, ARRAYSIZE(name));
  return ClassifyFocusWindow(name);
}

inline LRESULT CALLBACK ViewFocusGuardProc(int code, WPARAM wparam,
                                           LPARAM lparam) {
  // SetFocus on a Flutter child can activate its parent; let Windows switch
  // top-level windows independently of the Flutter view's focus requests.
  if (code == HCBT_SETFOCUS &&
      ShouldVetoViewFocus(
          reinterpret_cast<HWND>(wparam), ::GetActiveWindow(),
          FocusWindowClassOnCurrentThread,
          [](HWND window) { return ::GetAncestor(window, GA_ROOT); },
          [](HWND window) {
            return ::IsWindowVisible(window) && ::IsWindowEnabled(window) &&
                   !::IsIconic(window);
          })) {
    return 1;
  }
  return ::CallNextHookEx(nullptr, code, wparam, lparam);
}

inline HHOOK InstallViewFocusGuard() {
  return ::SetWindowsHookExW(WH_CBT, ViewFocusGuardProc, nullptr,
                             ::GetCurrentThreadId());
}
#endif

}  // namespace otzaria

#endif  // RUNNER_ACTIVATION_GATE_H_
