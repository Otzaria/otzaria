#include "accessibility_probe.h"

#include <commctrl.h>

#include <atomic>
#include <cstdint>
#include <cstdio>

namespace accessibility_probe {

namespace {

constexpr UINT_PTR kSubclassId = 0xA11E;
// uiautomationcoreapi.h; בלי ה-include הכבד.
constexpr LONG kUiaRootObjectId = -25;

enum Kind : int32_t { kNone = 0, kUia = 1, kMsaa = 2 };

std::atomic<int32_t> g_kind{kNone};
std::atomic<int64_t> g_ms_since_launch{0};

int64_t MsSinceLaunch() {
  FILETIME created = {}, exited = {}, kernel = {}, user = {};
  if (!::GetProcessTimes(::GetCurrentProcess(), &created, &exited, &kernel,
                         &user)) {
    return -1;
  }
  FILETIME now = {};
  ::GetSystemTimeAsFileTime(&now);
  const int64_t start =
      (static_cast<int64_t>(created.dwHighDateTime) << 32) |
      created.dwLowDateTime;
  const int64_t current =
      (static_cast<int64_t>(now.dwHighDateTime) << 32) | now.dwLowDateTime;
  return current > start ? (current - start) / 10000 : 0;
}

LRESULT CALLBACK ProbeProc(HWND hwnd, UINT message, WPARAM wparam,
                           LPARAM lparam, UINT_PTR, DWORD_PTR) {
  if (message == WM_GETOBJECT) {
    const LONG object_id = static_cast<LONG>(static_cast<DWORD>(lparam));
    const int32_t kind = object_id == kUiaRootObjectId ? kUia
                         : object_id == OBJID_CLIENT   ? kMsaa
                                                       : kNone;
    if (kind != kNone && g_kind.load(std::memory_order_relaxed) == kNone) {
      g_ms_since_launch.store(MsSinceLaunch(), std::memory_order_relaxed);
      g_kind.store(kind, std::memory_order_release);
      ::RemoveWindowSubclass(hwnd, ProbeProc, kSubclassId);
    }
  } else if (message == WM_NCDESTROY) {
    ::RemoveWindowSubclass(hwnd, ProbeProc, kSubclassId);
  }
  return ::DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

void Install(HWND flutter_view) {
  if (g_kind.load(std::memory_order_acquire) != kNone) return;
  ::SetWindowSubclass(flutter_view, ProbeProc, kSubclassId, 0);
}

void AppendFirstRequest(std::string* report) {
  const int32_t kind = g_kind.load(std::memory_order_acquire);
  if (kind == kNone) return;
  char line[96];
  snprintf(line, sizeof(line),
           "Accessibility: first request %s at %lldms after launch\n",
           kind == kUia ? "UIA" : "MSAA",
           static_cast<long long>(
               g_ms_since_launch.load(std::memory_order_relaxed)));
  *report += line;
}

}  // namespace accessibility_probe

// 0 = לא הגיעה בקשה, 1 = UIA, 2 = MSAA. נקרא מ-Dart ב-FFI רק בבניית דוח.
extern "C" __declspec(dllexport) int32_t OtzariaFirstAccessibilityRequest(
    int64_t* ms_since_launch) {
  const int32_t kind =
      accessibility_probe::g_kind.load(std::memory_order_acquire);
  if (ms_since_launch != nullptr) {
    *ms_since_launch =
        accessibility_probe::g_ms_since_launch.load(std::memory_order_relaxed);
  }
  return kind;
}
