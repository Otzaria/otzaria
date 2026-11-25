#include "webview_backend.h"

#include <cassert>
#include <iostream>

int main() {
  using otzaria::ShouldForceHwndWebView;

  // RDP: תמיד HWND, בכל גרסה וגם כשהגרסה לא ידועה.
  assert(ShouldForceHwndWebView(true, 26100));
  assert(ShouldForceHwndWebView(true, 17763));
  assert(ShouldForceHwndWebView(true, 0));

  // Windows 10 1809 (17763), כולל LTSC 2019: Direct3D11CaptureFramePool::Close
  // ממתין עד 2 שניות ל-thread הלכידה, ואחרת fail-fast לכל התהליך (#4211).
  assert(ShouldForceHwndWebView(false, 17763));
  assert(ShouldForceHwndWebView(false, 17134));
  assert(ShouldForceHwndWebView(false, 18361));

  // מ-1903 (18362) Close רק מאותת ל-thread וחוזר, בלי המתנה ובלי fail-fast.
  assert(!ShouldForceHwndWebView(false, 18362));
  assert(!ShouldForceHwndWebView(false, 19045));
  assert(!ShouldForceHwndWebView(false, 26100));

  // גרסה לא ידועה (RtlGetVersion נכשל): משאירים את ברירת המחדל.
  assert(!ShouldForceHwndWebView(false, 0));

  std::cout << "WebView backend choice cases passed\n";
}
