#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <memory>
#include <string>

#include "win32_window.h"

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
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void ArmForceExitWatchdog(uint32_t timeout_ms);

  // The project to run.
  flutter::DartProject project_;

  // When true, skip Show() in the first-frame callback. Used by CLI commands.
  bool headless_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      process_control_channel_;
  // ערוץ לסגירת חלון ה-splash הנייטיב (otzaria/splash) — Dart קורא "close"
  // בעת חשיפת החלון הראשי.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      splash_channel_;
  // ערוץ עדכון ה-Jump List של שורת המשימות (otzaria/jumplist) — Dart שולח
  // "updateTabs" עם כותרות הטאבים הפתוחים בכל שינוי.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      jumplist_channel_;
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
  HANDLE job_handle_ = nullptr;
  std::atomic_bool job_object_ready_ = false;
  // סיבת כשל הקמת ה-Job Object (ריק בהצלחה) — מדווח ל-Dart דרך
  // "jobObjectStatus" ונרשם ל-errors.txt לאבחון msedgewebview2 יתומים.
  std::string job_object_failure_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
