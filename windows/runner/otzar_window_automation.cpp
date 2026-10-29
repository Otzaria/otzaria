#include "otzar_window_automation.h"

#include <algorithm>
#include <cwctype>
#include <variant>
#include <vector>

namespace {
constexpr UINT_PTR kOtzarInputTimer = 0x4F545A01;
std::wstring Normalize(std::wstring text) {
  text.erase(std::remove_if(text.begin(), text.end(), [](wchar_t c) {
    return c == 0x200e || c == 0x200f || (c >= 0x202a && c <= 0x202e) ||
           (c >= 0x2066 && c <= 0x2069);
  }), text.end());
  const auto first = text.find_first_not_of(L" \t\r\n");
  if (first == std::wstring::npos) return L"";
  text = text.substr(first, text.find_last_not_of(L" \t\r\n") - first + 1);
  std::transform(text.begin(), text.end(), text.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return text;
}

bool IsOtzarProcess(DWORD pid) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return false;
  wchar_t path[32768]{};
  DWORD length = static_cast<DWORD>(sizeof(path) / sizeof(path[0]));
  const bool ok = QueryFullProcessImageNameW(process, 0, path, &length) != FALSE;
  CloseHandle(process);
  if (!ok) return false;
  std::wstring name(path, length);
  const auto slash = name.find_last_of(L"\\/");
  if (slash != std::wstring::npos) name.erase(0, slash + 1);
  name = Normalize(name);
  // Escapes avoid depending on the source-file execution character set.
  return name == L"otzar.exe" ||
         name == L"\u05d0\u05d5\u05e6\u05e8 \u05d4\u05d7\u05db\u05de\u05d4.exe";
}

struct Candidates { std::vector<HWND> primary, secondary; };
BOOL CALLBACK CollectWindow(HWND window, LPARAM parameter) {
  if (!IsWindowVisible(window) || !IsWindowEnabled(window) ||
      GetWindow(window, GW_OWNER) != nullptr) return TRUE;
  wchar_t buffer[512]{};
  GetWindowTextW(window, buffer, static_cast<int>(sizeof(buffer) / sizeof(buffer[0])));
  const auto title = Normalize(buffer);
  const bool primary = title == L"otzar";
  const bool secondary =
      title == L"\u05d0\u05d5\u05e6\u05e8 \u05d4\u05d7\u05db\u05de\u05d4" ||
      title == L"otzar hahochma" || title == L"otzar hachochma";
  if (!primary && !secondary) return TRUE;
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  if (!IsOtzarProcess(pid)) return TRUE;
  auto* found = reinterpret_cast<Candidates*>(parameter);
  (primary ? found->primary : found->secondary).push_back(window);
  return TRUE;
}

bool ModifiersOrMouseDown() {
  for (int key : {VK_CONTROL, VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN, VK_LBUTTON}) {
    if ((GetAsyncKeyState(key) & 0x8000) != 0) return true;
  }
  return false;
}
}  // namespace

OtzarWindowAutomation::OtzarWindowAutomation(
    flutter::BinaryMessenger* messenger, HWND host) : host_(host) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "otzaria/otzar_main_window",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
        if (call.method_name() != "openBookById") {
          result->NotImplemented();
          return;
        }
        int64_t book_id = 0;
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (args) {
          const auto found = args->find(Value("bookId"));
          if (found != args->end()) {
            if (const auto* small = std::get_if<int32_t>(&found->second)) book_id = *small;
            if (const auto* large = std::get_if<int64_t>(&found->second)) book_id = *large;
          }
        }
        if (book_id <= 0) {
          result->Error("invalid_book_id", "bookId must be a positive integer.");
          return;
        }
        Begin(book_id, std::move(result));
      });
}

OtzarWindowAutomation::~OtzarWindowAutomation() {
  channel_->SetMethodCallHandler(nullptr);
  if (result_) Fail("cancelled", "Otzaria is closing.");
  Reset();
}

void OtzarWindowAutomation::Begin(int64_t book_id, std::unique_ptr<Result> result) {
  if (result_) {
    result->Error("busy", "Another Otzar input operation is active.");
    return;
  }
  result_ = std::move(result);
  book_id_ = book_id;
  digits_ = std::to_wstring(book_id);
  // Shared across Flutter windows and other Otzaria instances in this session.
  mutex_ = CreateMutexW(nullptr, FALSE, L"Local\\Otzaria.OtzarBookInput.v1");
  if (!mutex_) { Fail("mutex_failed", "Cannot create input lock."); return; }
  const DWORD lock = WaitForSingleObject(mutex_, 0);
  owns_mutex_ = lock == WAIT_OBJECT_0 || lock == WAIT_ABANDONED;
  if (!owns_mutex_) { Fail("busy", "Another Otzaria window is using Otzar."); return; }
  Candidates candidates;
  if (!EnumWindows(CollectWindow, reinterpret_cast<LPARAM>(&candidates))) {
    Fail("window_search_failed", "Cannot enumerate application windows."); return;
  }
  const auto& windows = candidates.primary.empty()
      ? candidates.secondary : candidates.primary;
  if (windows.empty()) {
    Fail("window_not_found", "Open the main Otzar HaHochma window first."); return;
  }
  // Do not guess which independent instance owns the requested library.
  if (windows.size() != 1) {
    Fail("ambiguous_window", "More than one Otzar main window is open."); return;
  }
  target_ = windows.front();
  GetWindowThreadProcessId(target_, &target_pid_);
  if (ModifiersOrMouseDown()) {
    Fail("input_busy", "Release modifier keys and the mouse before trying again."); return;
  }
  if (IsIconic(target_)) ShowWindowAsync(target_, SW_RESTORE);
  SetForegroundWindow(target_);
  stage_ = Stage::kActivate;
  due_ = GetTickCount64();
  activation_deadline_ = due_ + 1200;
  // With a non-null HWND, WM_TIMER carries the requested ID, not necessarily
  // the nonzero success value returned by SetTimer. Never use ID zero here.
  timer_ = kOtzarInputTimer;
  if (SetTimer(host_, timer_, 20, nullptr) == 0) {
    timer_ = 0;
    Fail("timer_failed", "Cannot schedule input operation.");
  }
}

bool OtzarWindowAutomation::HandleMessage(UINT message, WPARAM wparam) {
  if (message != WM_TIMER || timer_ == 0 || wparam != timer_) return false;
  if (result_ && GetTickCount64() >= due_) Tick();
  return true;
}

bool OtzarWindowAutomation::CheckFocus() {
  DWORD pid = 0;
  if (IsWindow(target_)) GetWindowThreadProcessId(target_, &pid);
  if (pid != target_pid_ || !IsWindowEnabled(target_) ||
      GetForegroundWindow() != target_ || ModifiersOrMouseDown()) {
    Fail("focus_lost", "Otzar lost focus or the user is holding an input key.");
    return false;
  }
  return true;
}

bool OtzarWindowAutomation::ClickInside() {
  if (!CheckFocus()) return false;
  RECT client{};
  if (!GetClientRect(target_, &client) || client.right < 100 || client.bottom < 100) {
    Fail("window_too_small", "Enlarge the Otzar main window."); return false;
  }
  POINT point{client.right / 2, client.bottom * 55 / 100};
  if (!ClientToScreen(target_, &point) ||
      GetAncestor(WindowFromPoint(point), GA_ROOT) != target_) {
    Fail("click_obstructed", "The Otzar work area is covered by another window."); return false;
  }
  POINT original{};
  const bool restore = GetCursorPos(&original) != FALSE;
  if (!SetCursorPos(point.x, point.y)) {
    Fail("cursor_failed", "Cannot focus the Otzar work area."); return false;
  }
  INPUT input[2]{};
  input[0].type = input[1].type = INPUT_MOUSE;
  input[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
  input[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
  const UINT sent = SendInput(2, input, static_cast<int>(sizeof(INPUT)));
  if (sent == 1) SendInput(1, &input[1], static_cast<int>(sizeof(INPUT)));
  POINT current{};
  if (restore && GetCursorPos(&current) && current.x == point.x && current.y == point.y)
    SetCursorPos(original.x, original.y);
  if (sent != 2) {
    Fail("click_failed", "Windows rejected the click; check privilege levels."); return false;
  }
  return true;
}

HWND OtzarWindowAutomation::FocusedControl() {
  if (!CheckFocus()) return nullptr;
  GUITHREADINFO info{};
  info.cbSize = static_cast<DWORD>(sizeof(info));
  const DWORD thread = GetWindowThreadProcessId(target_, nullptr);
  if (thread == 0 || !GetGUIThreadInfo(thread, &info) || !info.hwndFocus ||
      GetAncestor(info.hwndFocus, GA_ROOT) != target_) {
    Fail("no_focused_control", "Cannot identify the focused Otzar control.");
    return nullptr;
  }
  return info.hwndFocus;
}

bool OtzarWindowAutomation::PostKey(WORD key, WORD scan_code) {
  const HWND control = FocusedControl();
  if (!control) return false;
  const uint32_t down = (static_cast<uint32_t>(scan_code) << 16) | 1u;
  const LPARAM up = static_cast<LPARAM>(static_cast<int32_t>(down | 0xC0000000u));
  // Address the control directly; do not send F1 through global remapping hooks.
  if (!PostMessageW(control, WM_KEYDOWN, key, static_cast<LPARAM>(down)) ||
      !PostMessageW(control, WM_KEYUP, key, up)) {
    Fail("key_message_failed", "Cannot post a key to the focused Otzar control.");
    return false;
  }
  return true;
}

bool OtzarWindowAutomation::SendDigits() {
  if (!FocusedControl()) return false;
  std::vector<INPUT> input;
  for (wchar_t digit : digits_) {
    INPUT down{};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = static_cast<WORD>(digit);
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    INPUT up = down;
    up.ki.dwFlags |= KEYEVENTF_KEYUP;
    input.push_back(down);
    input.push_back(up);
  }
  const auto count = static_cast<UINT>(input.size());
  const UINT sent = SendInput(count, input.data(), static_cast<int>(sizeof(INPUT)));
  if (sent != count) {
    if ((sent % 2) == 1 && sent < count)
      SendInput(1, &input[sent], static_cast<int>(sizeof(INPUT)));
    // Do not retry partial input: that could duplicate digits in the dialog.
    Fail("text_input_failed", "Windows rejected all or part of the book number.");
    return false;
  }
  return true;
}

void OtzarWindowAutomation::Tick() {
  const ULONGLONG now = GetTickCount64();
  switch (stage_) {
    case Stage::kActivate:
      if (GetForegroundWindow() != target_ || IsIconic(target_)) {
        if (now >= activation_deadline_) Fail("activation_failed", "Activate Otzar and try again.");
        return;
      }
      if (!ClickInside()) return;
      stage_ = Stage::kAfterClick; due_ = now + 40; return;
    case Stage::kAfterClick:
      if (!PostKey(VK_F1, 0x3b)) return;
      stage_ = Stage::kAfterF1; due_ = now + 350; return;
    case Stage::kAfterF1:
      if (!SendDigits()) return;
      stage_ = Stage::kAfterDigits; due_ = now + 80; return;
    case Stage::kAfterDigits:
      if (!PostKey(VK_RETURN, 0x1c)) return;
      stage_ = Stage::kFinish; due_ = now + 250; return;
    case Stage::kFinish:
      Succeed(); return;
  }
}

void OtzarWindowAutomation::Reset() {
  if (timer_) { KillTimer(host_, timer_); timer_ = 0; }
  if (owns_mutex_) { ReleaseMutex(mutex_); owns_mutex_ = false; }
  if (mutex_) { CloseHandle(mutex_); mutex_ = nullptr; }
  target_ = nullptr;
  target_pid_ = 0;
}

void OtzarWindowAutomation::Fail(const std::string& code, const std::string& message) {
  auto reply = std::move(result_);
  Reset();
  if (reply) reply->Error(code, message);
}

void OtzarWindowAutomation::Succeed() {
  auto reply = std::move(result_);
  const int64_t book_id = book_id_;
  Reset();
  if (reply) reply->Success(Value(flutter::EncodableMap{
      {Value("sent"), Value(true)}, {Value("bookId"), Value(book_id)},
      {Value("openedVerified"), Value(false)}}));
}
