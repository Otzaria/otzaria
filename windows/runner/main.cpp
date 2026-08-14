#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <initguid.h>
#include <knownfolders.h>
#include <shlobj.h>
#include <windows.h>

#include <chrono>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "splash_window.h"
#include "utils.h"

static const wchar_t* kSingleInstanceMutexName = L"OtzariaAppSingleInstance";
static const wchar_t* kFlutterWindowClassName = L"FLUTTER_RUNNER_WIN32_WINDOW";
static const wchar_t* kMainWindowTitle = L"אוצריא";

// Escapes a UTF-8 string for safe embedding inside a JSON string value.
static std::string JsonEscape(const std::string& s) {
  std::string out;
  out.reserve(s.size());
  for (unsigned char c : s) {
    switch (c) {
      case '"':  out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\b': out += "\\b";  break;
      case '\f': out += "\\f";  break;
      case '\n': out += "\\n";  break;
      case '\r': out += "\\r";  break;
      case '\t': out += "\\t";  break;
      default:
        if (c < 0x20) {
          char buf[8];
          snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out += static_cast<char>(c);
        }
    }
  }
  return out;
}

// Percent-encodes a UTF-8 string for safe use as a URL query component.
// Reserves unreserved chars (RFC 3986): A-Z a-z 0-9 - _ . ~
static std::string UrlEncodeQueryComponent(const std::string& s) {
  std::string out;
  out.reserve(s.size() * 3);
  for (unsigned char c : s) {
    const bool unreserved =
        (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~';
    if (unreserved) {
      out += static_cast<char>(c);
    } else {
      char buf[4];
      snprintf(buf, sizeof(buf), "%%%02X", c);
      out += buf;
    }
  }
  return out;
}

// Case-insensitive ASCII string equality.
static bool EqualsIgnoreCase(const std::string& a, const std::string& b) {
  if (a.size() != b.size()) return false;
  for (size_t i = 0; i < a.size(); ++i) {
    char ca = a[i];
    char cb = b[i];
    if (ca >= 'A' && ca <= 'Z') ca = static_cast<char>(ca - 'A' + 'a');
    if (cb >= 'A' && cb <= 'Z') cb = static_cast<char>(cb - 'A' + 'a');
    if (ca != cb) return false;
  }
  return true;
}

// Returns true when the command-line indicates a CLI sub-command that must
// run without a visible window and without the single-instance guard
// (e.g. `otzaria.exe pack-plugin <path>`). Strips a leading `--` / `/` and
// underscores so `--pack-plugin` and `pack_plugin` are also accepted.
//
// Note: |args| is the list returned by GetCommandLineArguments(), which
// already strips argv[0]. The first user-supplied argument is therefore at
// index 0.
static bool IsCliInvocation(const std::vector<std::string>& args) {
  if (args.empty()) return false;
  std::string cmd = args[0];
  while (!cmd.empty() && (cmd.front() == '-' || cmd.front() == '/')) {
    cmd.erase(cmd.begin());
  }
  for (auto& c : cmd) {
    if (c == '_') c = '-';
  }
  return EqualsIgnoreCase(cmd, "pack-plugin");
}

// Case-insensitive check whether `s` ends with `suffix` (ASCII only).
static bool EndsWithIgnoreCase(const std::string& s, const std::string& suffix) {
  if (s.size() < suffix.size()) return false;
  for (size_t i = 0; i < suffix.size(); ++i) {
    char a = s[s.size() - suffix.size() + i];
    char b = suffix[i];
    if (a >= 'A' && a <= 'Z') a = static_cast<char>(a - 'A' + 'a');
    if (b >= 'A' && b <= 'Z') b = static_cast<char>(b - 'A' + 'a');
    if (a != b) return false;
  }
  return true;
}

// Appends a URI string to the external-activation queue file so the already-
// running instance can pick it up.
// Path mirrors AppPaths.getDataRootPath() on Windows: %APPDATA%\otzaria
static void EnqueueUri(const std::string& uri_utf8) {
  // Use SHGetKnownFolderPath (Vista+) instead of the deprecated
  // SHGetFolderPathW / CSIDL_APPDATA.
  wchar_t* app_data_raw = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_DEFAULT,
                                   nullptr, &app_data_raw))) {
    return;
  }
  std::wstring app_data(app_data_raw);
  CoTaskMemFree(app_data_raw);

  std::wstring dir = app_data + L"\\otzaria";
  std::wstring queue_path =
      dir + L"\\pending_external_activations.jsonl";

  // Ensure the parent directory exists.
  CreateDirectoryW(dir.c_str(), nullptr);

  // Build ISO-8601 timestamp (UTC).
  auto now = std::chrono::system_clock::now();
  std::time_t tt = std::chrono::system_clock::to_time_t(now);
  struct tm utc {};
  gmtime_s(&utc, &tt);
  std::ostringstream ts;
  ts << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");

  std::string record =
      "{\"uri\":\"" + JsonEscape(uri_utf8) + "\",\"createdAt\":\"" +
      ts.str() + "\"}";

  // Append as a single JSONL line (UTF-8).
  HANDLE fh = CreateFileW(queue_path.c_str(), FILE_APPEND_DATA,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                          OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (fh != INVALID_HANDLE_VALUE) {
    std::string line = record + "\n";
    DWORD written = 0;
    WriteFile(fh, line.c_str(), static_cast<DWORD>(line.size()), &written,
              nullptr);
    CloseHandle(fh);
  }
}

// Restores a minimized window and brings it to the foreground.
static void BringWindowToFront(HWND hwnd) {
  if (hwnd == nullptr) return;
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else if (!IsWindowVisible(hwnd) && !splash::IsAnyInstanceShowing()) {
    // חלון מוסתר בלי splash פעיל: המופע הראשון סיים את האתחול אך חלונו נעלם
    // (קריסה אחרי החשיפה). בזמן אתחול אין לחשוף — presentMainWindow מדלג אז
    // על ה-cloak ומחזיר בדיוק את ההבהוב שהוא נועד למנוע. ההבחנה תקפה כל עוד
    // ה-splash חי, כלומר עד kMaxDisplayMs.
    ShowWindow(hwnd, SW_SHOW);
  }
  SetForegroundWindow(hwnd);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // CLI sub-commands (e.g. `pack-plugin`) must skip the single-instance check
  // so they work even when the GUI is already running, and must not raise the
  // existing GUI window. The Dart entrypoint will call exit() before any UI
  // is rendered.
  std::vector<std::string> early_args = GetCommandLineArguments();
  const bool is_cli_invocation = IsCliInvocation(early_args);

  // Single-instance check: must happen before the Flutter engine starts so
  // that the second instance never acquires any shared resources (DB, etc.).
  // bInitialOwner = FALSE: we don't need ownership, just existence of the object.
  // If CreateMutexW fails (returns NULL), treat as first instance so the app
  // can still start rather than being permanently blocked.
  HANDLE mutex = is_cli_invocation
                     ? nullptr
                     : CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  bool is_second_instance =
      (mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS);

  if (is_second_instance) {
    // Enqueue any otzaria:// URIs (and .otzplugin file paths) passed on the
    // command line so the first instance can handle them via its file-watcher,
    // then exit immediately.
    for (const auto& arg : early_args) {
      if (arg.size() >= 8 &&
          _strnicmp(arg.c_str(), "otzaria:", 8) == 0) {
        EnqueueUri(arg);
      } else if (EndsWithIgnoreCase(arg, ".otzplugin")) {
        EnqueueUri("otzaria://plugin/install-local?path=" +
                   UrlEncodeQueryComponent(arg));
      }
    }
    BringWindowToFront(FindWindowW(kFlutterWindowClassName, kMainWindowTitle));
    CloseHandle(mutex);
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // חובה להיות זהה ל-AppUserModelID שבקיצורי המתקין, אחרת קיצור עם פרמטר
  // (למשל לוח שנה) מקבל כפתור נפרד בשורת המשימות במקום להתאחד עם הסמל המוצמד.
  ::SetCurrentProcessExplicitAppUserModelID(L"Otzaria.Otzaria");

  // Show the native floating-icon splash as early as possible (it needs COM
  // for WIC PNG decoding). It is an independent, top-most, click-through
  // layered window centered on the primary monitor — decoupled from the main
  // Flutter window, which stays hidden until its content is ready. This gives
  // immediate visual feedback during heavy init without any window resize,
  // jump, or blank gap. Dart closes it via the "otzaria/splash" channel when
  // the main window is revealed (see FlutterWindow method-call handler).
  // Skipped for CLI invocations (no UI).
  if (!is_cli_invocation) {
    splash::Show();
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, /*headless=*/is_cli_invocation);
  Win32Window::Point origin(10, 10);
  // The main window is created hidden and is NOT shown on the first frame (see
  // FlutterWindow::OnCreate). It stays hidden until Dart reveals it
  // (window_manager.show in presentMainWindow) once the active tab's content is
  // ready, so it appears directly at its final size/position with content — no
  // resize, no jump, no blank gap. The native floating-icon splash
  // (splash::Show above) is the only thing visible until then. Initial size is
  // irrelevant (the window is never shown at this size).
  Win32Window::Size size(240, 240);
  if (!window.Create(kMainWindowTitle, origin, size)) {
    if (mutex) CloseHandle(mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (mutex) CloseHandle(mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
