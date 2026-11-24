#ifndef RUNNER_WEBVIEW_BACKEND_H_
#define RUNNER_WEBVIEW_BACKEND_H_

namespace otzaria {

// האם לכפות על WebView של התוספים מצב HWND (FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND)
// במקום מצב ה-composition. build הוא מספר הבנייה של Windows, ו-0 אם לא ידוע.
inline bool ShouldForceHwndWebView(bool remote_session, unsigned long build) {
  (void)build;
  // ב-RDP שיתוף ה-D3D surface של ה-composition נכשל (מסך ריק בתוספים).
  return remote_session;
}

}  // namespace otzaria

#endif  // RUNNER_WEBVIEW_BACKEND_H_
