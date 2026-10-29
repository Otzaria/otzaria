#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <memory>
#include <queue>
#include <string>

#include "win32_window.h"
#include "otzar_window_automation.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // When |headless| is true, the window will not be shown after the first
  // frame — used for CLI commands (e.g. pack-plugin) that expect the Dart
  // entrypoint to call exit() before any UI is rendered.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool headless = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  void OnWindowHidden() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  std::unique_ptr<OtzarWindowAutomation> otzar_window_automation_;
  void ArmForceExitWatchdog(uint32_t timeout_ms);

  // מציג שוב את החלון אם המשתמש סגר (הסתיר) אותו; false אם לא נסגר.
  bool RestoreClosedWindow();

  // שוטף את הכתיבות התלויות של Dart לפני שאנחנו מאשרים סיום סשן.
  //
  // חוסם את ה-platform thread עד שה-Dart מסמן סיום או עד פקיעת הזמן, תוך
  // הרצת לולאת הודעות מצומצמת — בלעדיה ה-Dart לא ירוץ כלל, כי ה-platform
  // thread וה-UI thread ממוזגים. מחזיר true אם ה-flush הושלם.
  bool FlushBeforeSessionEnd();

  // אירוע שה-Dart מסמן דרך "sessionEndFlushDone". manual-reset.
  HANDLE session_end_flush_event_ = nullptr;

  // The project to run.
  flutter::DartProject project_;

  // When true, skip Show() in the first-frame callback. Used by CLI commands.
  bool headless_ = false;
  // המשתמש סגר את החלון: הוא מוסתר ולא נהרס. להבדיל מחלון שטרם נחשף.
  bool closed_by_user_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      process_control_channel_;
  // ערוץ החלונות (otzaria/multiwindow): סגירה והעלאה של הראשי וגרירה.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      multiwindow_channel_;
  // בקשות "מסור את הגרירה ל-Windows" שממתינות ללולאת ההודעות.
  //
  // ⚠️ נענות **אחרי** שהמשתמש שחרר, כי התשובה היא המסגרת הסופית — כולל
  // הצמדה. הן אינן מבוצעות בתוך הטיפול בערוץ: `DragWithSystem` נכנס
  // ללולאה מודאלית, וחסימה מתוך קריאת ערוץ היא ריאנטרנטית.
  struct PendingSystemDrag {
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
    // חלון המקור (חלון Dart), או nullptr לחלון הזה.
    HWND self = nullptr;
    bool report_hwnd = false;
  };
  std::queue<PendingSystemDrag> pending_system_drags_;
  // ערוץ לסגירת חלון ה-splash הנייטיב (otzaria/splash) — Dart קורא "close"
  // בעת חשיפת החלון הראשי.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      splash_channel_;
  std::atomic_bool force_exit_watchdog_armed_ = false;

  // Win32 Job Object that contains this process plus any child processes
  // it spawns (notably WebView2's msedgewebview2.exe instances). Configured
  // with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE so the kernel kills every
  // member when the handle is released — which happens on TerminateProcess
  // of the host. Without this, fast-exit shutdown orphans Edge children.
  //
  // Setup can fail on hardened environments (sandboxed launches, debugger
  // job objects on Win32 versions that don't allow nesting, certain
  // enterprise MDM/AV configurations). `job_object_ready_` reflects whether
  // every setup step succeeded; we only honour forceTerminate when it did,
  // otherwise the Dart side falls back to the existing graceful close path.
  // ⚠️ ה-handle עצמו אינו נשמר: הוא `static` בתוך הקונסטרוקטור (משאב של
  // התהליך), ולעולם אינו נסגר. השדה שהחזיק אותו כאן נכתב ולא נקרא.
  std::atomic_bool job_object_ready_ = false;
  // סיבת כשל הקמת ה-Job Object (ריק בהצלחה) — מדווח ל-Dart דרך
  // "jobObjectStatus" ונרשם ל-errors.txt לאבחון msedgewebview2 יתומים.
  std::string job_object_failure_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
