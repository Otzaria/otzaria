#include "flutter_window.h"

#include <algorithm>
#include <chrono>
#include <limits>
#include <optional>
#include <thread>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  process_control_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "otzaria/process_control",
          &flutter::StandardMethodCodec::GetInstance());
  process_control_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "armForceExitWatchdog") {
          result->NotImplemented();
          return;
        }

        uint32_t timeout_ms = 15000;
        if (const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          auto timeout_it = arguments->find(flutter::EncodableValue("timeoutMs"));
          if (timeout_it != arguments->end()) {
            if (const auto* timeout_value =
                    std::get_if<int32_t>(&timeout_it->second)) {
              if (*timeout_value > 0) {
                timeout_ms = static_cast<uint32_t>(*timeout_value);
              }
            } else if (const auto* timeout_value64 =
                           std::get_if<int64_t>(&timeout_it->second)) {
              if (*timeout_value64 > 0 &&
                  *timeout_value64 <
                      static_cast<int64_t>(std::numeric_limits<uint32_t>::max())) {
                timeout_ms = static_cast<uint32_t>(*timeout_value64);
              }
            }
          }
        }

        timeout_ms = std::clamp<uint32_t>(timeout_ms, 5000, 60000);
        ArmForceExitWatchdog(timeout_ms);
        result->Success(flutter::EncodableValue(true));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  process_control_channel_.reset();
  if (flutter_controller_) {
    // Reset the controller properly - no need to call Shutdown explicitly
    flutter_controller_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::ArmForceExitWatchdog(uint32_t timeout_ms) {
  bool expected = false;
  if (!force_exit_watchdog_armed_.compare_exchange_strong(expected, true)) {
    return;
  }

  std::thread([timeout_ms]() {
    std::this_thread::sleep_for(std::chrono::milliseconds(timeout_ms));
    OutputDebugStringW(
        L"Otzaria force-exit watchdog expired; terminating process.\n");
    TerminateProcess(GetCurrentProcess(), 0);
  }).detach();
}
