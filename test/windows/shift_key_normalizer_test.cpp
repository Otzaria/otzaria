#include <windows.h>
#include <commctrl.h>

#include <iostream>
#include <stdexcept>
#include <vector>

#include "shift_key_normalizer.h"

namespace {

struct Message {
  HWND window;
  UINT type;
  WPARAM key;
  LPARAM flags;
};

std::vector<Message> messages;
int checks = 0;
constexpr LPARAM kScanCodeMask = 0x00ff0000;
constexpr LPARAM kExtendedBit = 0x01000000;
constexpr LPARAM kKeyUp = 0xc0000000;

LRESULT CALLBACK CaptureProc(HWND window, UINT type, WPARAM key, LPARAM flags) {
  if (type == WM_KEYDOWN || type == WM_KEYUP || type == WM_SYSKEYDOWN ||
      type == WM_SYSKEYUP || type == WM_CHAR || type == WM_PASTE) {
    messages.push_back({window, type, key, flags});
    return 0;
  }
  return DefWindowProcW(window, type, key, flags);
}

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

void Check(HWND window, UINT type, WPARAM key, LPARAM flags, LPARAM expected) {
  const auto count = messages.size();
  SendMessageW(window, type, key, flags);
  Require(messages.size() == count + 1, "Each input must be forwarded once");
  const auto& received = messages.back();
  Require(received.window == window && received.type == type &&
              received.key == key && received.flags == expected,
          "The subclass changed an unexpected input field");
  ++checks;
}

void CheckLoopMessage(HWND window, UINT type, WPARAM key, LPARAM flags,
                      LPARAM expected) {
  MSG message{};
  message.hwnd = window;
  message.message = type;
  message.wParam = key;
  message.lParam = flags;
  message.time = 123;
  message.pt = {4, 5};
  NormalizeFlutterKeyboardMessage(message);
  Require(message.hwnd == window && message.message == type &&
              message.wParam == key && message.lParam == expected &&
              message.time == 123 && message.pt.x == 4 && message.pt.y == 5,
          "The message loop changed an unexpected input field");
  ++checks;
}

LPARAM ScanCode(UINT key, HKL layout) {
  const UINT mapped = MapVirtualKeyExW(key, MAPVK_VK_TO_VSC_EX, layout);
  Require((mapped & 0xff) != 0, "The keyboard layout must map the test key");
  return static_cast<LPARAM>(mapped & 0xff) << 16;
}

std::vector<MSG> Translate(HWND window, UINT type, LPARAM flags,
                           bool normalize) {
  MSG key{};
  key.hwnd = window;
  key.message = type;
  key.wParam = 'V';
  key.lParam = flags;
  if (normalize) NormalizeFlutterKeyboardMessage(key);
  Require(TranslateMessage(&key) != 0, "V must produce a character message");
  std::vector<MSG> characters;
  MSG character{};
  while (PeekMessageW(&character, window, WM_CHAR, WM_SYSDEADCHAR, PM_REMOVE)) {
    Require(character.message == WM_CHAR || character.message == WM_SYSCHAR ||
                character.message == WM_DEADCHAR ||
                character.message == WM_SYSDEADCHAR,
            "The native character queue contained an unexpected message");
    characters.push_back(character);
  }
  Require(!characters.empty(), "TranslateMessage did not post a character");
  return characters;
}

void CheckCharacterTranslation(HWND window, LPARAM scan) {
  BYTE original[256];
  Require(GetKeyboardState(original) != 0, "Keyboard state could not be read");
  try {
    for (int mode = 0; mode < 3; ++mode) {
      BYTE keyboard[256]{};
      if (mode == 1) keyboard[VK_CONTROL] = keyboard[VK_LCONTROL] = 0x80;
      if (mode == 2) keyboard[VK_MENU] = keyboard[VK_LMENU] = 0x80;
      Require(SetKeyboardState(keyboard) != 0,
              "The test thread keyboard state could not be set");
      const UINT type = mode == 2 ? WM_SYSKEYDOWN : WM_KEYDOWN;
      const LPARAM flags = 3 | 0x40000000 | (mode == 2 ? 0x20000000 : 0);
      const auto raw = Translate(window, type, flags, false);
      const auto normalized = Translate(window, type, flags, true);
      Require(raw.size() == normalized.size(),
              "Normalization changed the number of characters");
      for (size_t i = 0; i < raw.size(); ++i) {
        Require(normalized[i].hwnd == raw[i].hwnd &&
                    normalized[i].message == raw[i].message &&
                    normalized[i].wParam == raw[i].wParam &&
                    (normalized[i].lParam & kScanCodeMask) == scan &&
                    (normalized[i].lParam & ~kScanCodeMask) ==
                        (raw[i].lParam & ~kScanCodeMask),
                "The translated character must keep its text and flags");
        ++checks;
      }
      std::cout << "translated_mode=" << mode
                << " raw_scan=" << ((raw.front().lParam & kScanCodeMask) >> 16)
                << " normalized_scan=" << (scan >> 16)
                << " characters=" << raw.size() << '\n';
    }
  } catch (...) {
    SetKeyboardState(original);
    throw;
  }
  Require(SetKeyboardState(original) != 0,
          "The original keyboard state could not be restored");
}

void CheckLayout(HWND first, HWND second, HWND unhooked, HKL layout) {
  Require(ActivateKeyboardLayout(layout, 0) != nullptr,
          "The test keyboard layout could not be activated");
  Require(GetKeyboardLayout(0) == layout, "The target layout is not active");
  const LPARAM control = ScanCode(VK_LCONTROL, layout);
  const LPARAM right_control = ScanCode(VK_RCONTROL, layout);
  const LPARAM v = ScanCode('V', layout);

  for (const UINT type : {WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP}) {
    const bool up = type == WM_KEYUP || type == WM_SYSKEYUP;
    const bool system = type == WM_SYSKEYDOWN || type == WM_SYSKEYUP;
    const LPARAM flags = 3 | (up ? kKeyUp : 0) | (system ? 0x20000000 : 0);
    Check(first, type, VK_CONTROL, flags, flags | control);
    Check(first, type, VK_LCONTROL, flags, flags | control);
    Check(first, type, VK_LCONTROL, flags | kExtendedBit,
          flags | kExtendedBit);
    Check(second, type, VK_CONTROL, flags | kExtendedBit,
          flags | kExtendedBit | right_control);
    Check(second, type, VK_RCONTROL, flags | kExtendedBit,
          flags | kExtendedBit | right_control);
    Check(second, type, VK_RCONTROL, flags, flags);
    Check(first, type, 'V', flags, flags | v);
    Check(first, type, 'V', flags | 0x00560000, flags | 0x00560000);
    Check(first, type, VK_CONTROL, flags | 0x00290000, flags | 0x00290000);
    Check(first, type, 'A', flags, flags);
    CheckLoopMessage(first, type, 'V', flags, flags | v);
    CheckLoopMessage(second, type, VK_CONTROL, flags | kExtendedBit,
                     flags | kExtendedBit | right_control);
    CheckLoopMessage(first, type, VK_LCONTROL, flags | kExtendedBit,
                     flags | kExtendedBit);
    CheckLoopMessage(first, type, VK_RCONTROL, flags, flags);
    CheckLoopMessage(first, type, 'V', flags | 0x00560000,
                     flags | 0x00560000);
    CheckLoopMessage(first, type, 'A', flags, flags);
    CheckLoopMessage(unhooked, type, 'V', flags, flags);
    CheckLoopMessage(unhooked, type, VK_CONTROL, flags, flags);
  }

  // גם V לבדו ו-Alt+V הם מקשים רגילים; לא נשלחת הודעת הדבקה או Ctrl.
  Check(first, WM_KEYDOWN, 'V', 1, 1 | v);
  Check(first, WM_SYSKEYDOWN, 'V', 0x20000001, 0x20000001 | v);
  Check(first, WM_KEYDOWN, 'V', 0x40000007, 0x40000007 | v);
  Check(first, WM_KEYUP, 'V', kKeyUp | 1, kKeyUp | 1 | v);
  const LPARAM signed_up = static_cast<LPARAM>(static_cast<LONG>(0xc0000001));
  Check(first, WM_KEYUP, 'V', signed_up, signed_up | v);
  Check(first, WM_KEYDOWN, 'V', kExtendedBit | 1, kExtendedBit | 1);
  Check(first, WM_KEYDOWN, VK_RCONTROL, 1, 1);
  Check(first, WM_CHAR, 'V', 1, 1);
  Check(first, WM_PASTE, 0, 0, 0);
  CheckLoopMessage(first, WM_CHAR, 0x16, 1, 1);
  CheckLoopMessage(first, WM_SYSCHAR, 'v', 0x20000001, 0x20000001);
  CheckLoopMessage(first, WM_UNICHAR, 0x1f600, 1, 1);
  CheckLoopMessage(nullptr, WM_KEYDOWN, 'V', 1, 1);
  CheckCharacterTranslation(first, v);
  CheckCharacterTranslation(second, v);

  // התיקון הקיים ל-Shift נשמר; ההתקנה החוזרת לא יוצרת שרשרת כפולה.
  Check(first, WM_KEYDOWN, VK_SHIFT, kExtendedBit | 1, 0x002a0001);
  Check(first, WM_KEYUP, VK_SHIFT, kKeyUp | kExtendedBit | 0x00360001,
        kKeyUp | 0x00360001);
  InstallShiftKeyNormalizer(first);
  Check(first, WM_KEYDOWN, VK_CONTROL, 1, 1 | control);

  std::cout << "layout=" << reinterpret_cast<UINT_PTR>(layout)
            << " ctrl_scan=" << (control >> 16) << " v_scan=" << (v >> 16)
            << '\n';
}

}  // namespace

int main() {
  const HINSTANCE instance = GetModuleHandleW(nullptr);
  const HKL original_layout = GetKeyboardLayout(0);
  WNDCLASSEXW descriptor{};
  descriptor.cbSize = static_cast<UINT>(sizeof(descriptor));
  descriptor.lpfnWndProc = CaptureProc;
  descriptor.hInstance = instance;
  descriptor.lpszClassName = L"OtzariaScanCodeQa";
  HWND first = nullptr;
  HWND second = nullptr;
  HWND unhooked = nullptr;
  int result = 0;
  try {
    Require(RegisterClassExW(&descriptor) != 0, "Window class registration failed");
    first = CreateWindowExW(0, descriptor.lpszClassName, L"first", 0, 0, 0,
                           0, 0, HWND_MESSAGE, nullptr, instance, nullptr);
    second = CreateWindowExW(0, descriptor.lpszClassName, L"second", 0, 0, 0,
                            0, 0, HWND_MESSAGE, nullptr, instance, nullptr);
    unhooked = CreateWindowExW(0, descriptor.lpszClassName, L"unhooked", 0, 0, 0,
                              0, 0, HWND_MESSAGE, nullptr, instance, nullptr);
    Require(first && second && unhooked,
            "Native test windows could not be created");
    InstallShiftKeyNormalizer(first);
    InstallShiftKeyNormalizer(second);
    const int count = GetKeyboardLayoutList(0, nullptr);
    Require(count > 0, "No keyboard layout is available");
    std::vector<HKL> layouts(count);
    Require(GetKeyboardLayoutList(count, layouts.data()) == count,
            "Keyboard layouts changed while the test was starting");
    for (const HKL layout : layouts) CheckLayout(first, second, unhooked, layout);
    Require(DestroyWindow(first) != 0 && IsWindow(first) == 0,
            "The first test window did not close");
    first = nullptr;
    Check(second, WM_KEYDOWN, 'V', 1, 1 | ScanCode('V', GetKeyboardLayout(0)));
    std::cout << "passed=" << checks << ", layouts=" << layouts.size()
              << ", windows=3, hookedWindows=2, realWindowsSubclass=true, "
                 "FlutterTested=false\n";
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    result = 1;
  }
  if (first) DestroyWindow(first);
  if (second) DestroyWindow(second);
  if (unhooked) DestroyWindow(unhooked);
  ActivateKeyboardLayout(original_layout, 0);
  UnregisterClassW(descriptor.lpszClassName, instance);
  return result;
}
