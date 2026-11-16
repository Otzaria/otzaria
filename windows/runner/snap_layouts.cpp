#include "snap_layouts.h"

#include <commctrl.h>
#include <windowsx.h>

#include <unordered_map>
#include <utility>

namespace snap_layouts {
namespace {

constexpr UINT_PTR kRootSubclassId = 0x4021;
constexpr UINT_PTR kViewSubclassId = 0x4022;

struct State {
  HWND view = nullptr;
  int64_t window = 0;
  RECT rect = {};
  EventSink sink;
  bool hovered = false;
  bool pressed = false;
};

// לפי חלון השורש. כל החלונות על ה-thread של ה-UI, ולכן אין צורך בנעילה.
std::unordered_map<HWND, State>& States() {
  static auto* states = new std::unordered_map<HWND, State>();
  return *states;
}

State* StateOf(HWND root) {
  auto& states = States();
  const auto it = states.find(root);
  return it == states.end() ? nullptr : &it->second;
}

bool OverButton(const State& state, LPARAM screen_point) {
  if (::IsRectEmpty(&state.rect) || !::IsWindow(state.view)) return false;
  POINT point = {GET_X_LPARAM(screen_point), GET_Y_LPARAM(screen_point)};
  return ::ScreenToClient(state.view, &point) &&
         ::PtInRect(&state.rect, point);
}

void Report(State& state, bool hovered, bool pressed, bool clicked = false) {
  if (!clicked && state.hovered == hovered && state.pressed == pressed) return;
  state.hovered = hovered;
  state.pressed = pressed;
  if (state.sink) state.sink({state.window, hovered, pressed, clicked});
}

void TrackLeave(HWND root) {
  TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE | TME_NONCLIENT, root, 0};
  ::TrackMouseEvent(&track);
}

LRESULT CALLBACK RootProc(HWND hwnd, UINT message, WPARAM wparam,
                          LPARAM lparam, UINT_PTR, DWORD_PTR) {
  State* state = StateOf(hwnd);
  if (message == WM_NCDESTROY || !state) {
    if (message == WM_NCDESTROY) {
      ::RemoveWindowSubclass(hwnd, RootProc, kRootSubclassId);
      States().erase(hwnd);
    }
    return ::DefSubclassProc(hwnd, message, wparam, lparam);
  }
  switch (message) {
    case WM_NCHITTEST:
      if (OverButton(*state, lparam)) return HTMAXBUTTON;
      break;
    case WM_NCMOUSEMOVE:
      if (wparam == HTMAXBUTTON) {
        if (!state->hovered) TrackLeave(hwnd);
        Report(*state, true, state->pressed);
      } else {
        Report(*state, false, false);
      }
      break;
    case WM_NCMOUSELEAVE:
      Report(*state, false, false);
      break;
    // DefWindowProc היה מצייר כפתור קלאסי ומגדיל בעצמו; הלחיצה עוברת ל-Dart.
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
      if (wparam == HTMAXBUTTON) {
        Report(*state, true, true);
        return 0;
      }
      break;
    case WM_NCLBUTTONUP:
      if (wparam == HTMAXBUTTON) {
        const bool clicked = state->pressed;
        Report(*state, true, false, clicked);
        return 0;
      }
      break;
    case WM_NCRBUTTONDOWN:
    case WM_NCRBUTTONUP:
      if (wparam == HTMAXBUTTON) return 0;
      break;
  }
  return ::DefSubclassProc(hwnd, message, wparam, lparam);
}

// תצוגת Flutter מכסה את כל אזור הלקוח; HTTRANSPARENT מעביר את הבדיקה לשורש.
LRESULT CALLBACK ViewProc(HWND hwnd, UINT message, WPARAM wparam,
                          LPARAM lparam, UINT_PTR, DWORD_PTR ref_data) {
  if (message == WM_NCHITTEST) {
    const State* state = StateOf(reinterpret_cast<HWND>(ref_data));
    if (state && state->view == hwnd && OverButton(*state, lparam)) {
      return HTTRANSPARENT;
    }
  } else if (message == WM_NCDESTROY) {
    ::RemoveWindowSubclass(hwnd, ViewProc, kViewSubclassId);
  }
  return ::DefSubclassProc(hwnd, message, wparam, lparam);
}

bool EnsureSubclass(HWND hwnd, SUBCLASSPROC proc, UINT_PTR id,
                    DWORD_PTR ref_data) {
  DWORD_PTR existing = 0;
  return ::GetWindowSubclass(hwnd, proc, id, &existing) ||
         ::SetWindowSubclass(hwnd, proc, id, ref_data);
}

}  // namespace

bool IsSupported() {
  // כמו בדיקת המסגרת ב-flutter_window.cpp: Windows 11 הוא build 22000.
#pragma warning(push)
#pragma warning(disable : 4996)
  const DWORD version = ::GetVersion();
#pragma warning(pop)
  const DWORD build = version < 0x80000000 ? HIWORD(version) : 0;
  return build >= 22000;
}

bool SetMaximizeButton(HWND root, HWND view, int64_t window, const RECT& rect,
                       EventSink sink) {
  if (!IsSupported() || !::IsWindow(root) || !::IsWindow(view) ||
      ::GetAncestor(view, GA_ROOT) != root) {
    return false;
  }
  State* state = StateOf(root);
  if (::IsRectEmpty(&rect)) {
    if (state) {
      Report(*state, false, false);
      state->rect = {};
    }
    return true;
  }
  if (!state) {
    if (!EnsureSubclass(root, RootProc, kRootSubclassId, 0)) return false;
    state = &States()[root];
  }
  if (state->view != view) {
    if (!EnsureSubclass(view, ViewProc, kViewSubclassId,
                        reinterpret_cast<DWORD_PTR>(root))) {
      return false;
    }
    state->view = view;
  }
  state->window = window;
  state->rect = rect;
  state->sink = std::move(sink);
  return true;
}

}  // namespace snap_layouts
