#ifndef RUNNER_WEBVIEW_BACKEND_POLICY_H_
#define RUNNER_WEBVIEW_BACKEND_POLICY_H_

#include <windows.h>

namespace webview_backend_policy {

// לפני 1903 סגירת ה-frame pool של Windows.Graphics.Capture עלולה לסגור את
// התהליך (0xc0000409 ב-GraphicsCapture.dll, #4211).
constexpr DWORD kFirstReliableCaptureBuild = 18362;

// ב-RDP שיתוף ה-D3D surface של ה-composition נכשל (מסך ריק בתוספים).
constexpr bool ShouldForceHwnd(bool remote_session, DWORD windows_build) {
  return remote_session ||
         (windows_build != 0 && windows_build < kFirstReliableCaptureBuild);
}

static_assert(ShouldForceHwnd(false, 17763), "1809 hosts WebView in HWND");
static_assert(!ShouldForceHwnd(false, 18362), "1903 keeps composition");
static_assert(!ShouldForceHwnd(false, 26100), "current builds keep default");
static_assert(ShouldForceHwnd(true, 26100), "RDP still forces HWND");
static_assert(!ShouldForceHwnd(false, 0), "unknown build keeps default");

// RtlGetVersion מחזיר את הגרסה האמיתית בלי manifest, registry או COM.
inline DWORD WindowsBuildNumber() {
  using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  const HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) return 0;
  const auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
      reinterpret_cast<void*>(::GetProcAddress(ntdll, "RtlGetVersion")));
  if (rtl_get_version == nullptr) return 0;
  RTL_OSVERSIONINFOW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  return rtl_get_version(&info) == 0 ? info.dwBuildNumber : 0;
}

}  // namespace webview_backend_policy

#endif  // RUNNER_WEBVIEW_BACKEND_POLICY_H_
