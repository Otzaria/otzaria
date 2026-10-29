#ifndef RUNNER_OTZAR_WINDOW_AUTOMATION_H_
#define RUNNER_OTZAR_WINDOW_AUTOMATION_H_

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <cstdint>
#include <memory>
#include <string>

// Driven by WM_TIMER on the Flutter platform thread: no Sleep(), worker-thread
// channel replies, clipboard changes, external helper or debugger connection.
class OtzarWindowAutomation {
 public:
  OtzarWindowAutomation(flutter::BinaryMessenger* messenger, HWND host);
  ~OtzarWindowAutomation();
  OtzarWindowAutomation(const OtzarWindowAutomation&) = delete;
  OtzarWindowAutomation& operator=(const OtzarWindowAutomation&) = delete;
  bool HandleMessage(UINT message, WPARAM wparam);

 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  enum class Stage { kActivate, kAfterClick, kAfterF1, kAfterDigits, kFinish };
  void Begin(int64_t book_id, std::unique_ptr<Result> result);
  void Tick();
  void Fail(const std::string& code, const std::string& message);
  void Succeed();
  void Reset();
  bool CheckFocus();
  bool ClickInside();
  HWND FocusedControl();
  bool PostKey(WORD key, WORD scan_code);
  bool SendDigits();

  HWND host_ = nullptr;
  HWND target_ = nullptr;
  DWORD target_pid_ = 0;
  UINT_PTR timer_ = 0;
  HANDLE mutex_ = nullptr;
  bool owns_mutex_ = false;
  Stage stage_ = Stage::kActivate;
  ULONGLONG due_ = 0;
  ULONGLONG activation_deadline_ = 0;
  int64_t book_id_ = 0;
  std::wstring digits_;
  std::unique_ptr<Result> result_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
};
#endif
