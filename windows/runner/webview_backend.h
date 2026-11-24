#ifndef RUNNER_WEBVIEW_BACKEND_H_
#define RUNNER_WEBVIEW_BACKEND_H_

namespace otzaria {

// Windows 10 1903. עד 1809 (כולל LTSC 2019, 17763.1–17763.2989)
// Direct3D11CaptureFramePool::Close ב-GraphicsCapture.dll ממתין עד 2 שניות
// (WaitForSingleObject(…, 2000)) ל-thread הלכידה, ואם לא הספיק — fail-fast
// לכל התהליך (0xc0000409, #4211). מ-18362 Close רק מאותת ל-thread וחוזר.
constexpr unsigned long kFirstBuildWithAsyncCaptureClose = 18362;

// האם לכפות על WebView של התוספים מצב HWND (FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND)
// במקום מצב ה-composition. build הוא מספר הבנייה של Windows, ו-0 אם לא ידוע.
inline bool ShouldForceHwndWebView(bool remote_session, unsigned long build) {
  // ב-RDP שיתוף ה-D3D surface של ה-composition נכשל (מסך ריק בתוספים).
  if (remote_session) return true;
  // מצב HWND אינו משתמש ב-Windows.Graphics.Capture, ולכן לא מגיע ל-Close.
  return build != 0 && build < kFirstBuildWithAsyncCaptureClose;
}

}  // namespace otzaria

#endif  // RUNNER_WEBVIEW_BACKEND_H_
