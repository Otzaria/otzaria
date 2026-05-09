#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <initguid.h>
#include <knownfolders.h>
#include <shlobj.h>
#include <windows.h>
#include <tlhelp32.h>

#include <chrono>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

static const wchar_t* kSingleInstanceMutexName = L"OtzariaAppSingleInstance";
static const wchar_t* kOtzariaExeName = L"otzaria.exe";

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

// Returns true if the given PID belongs to an otzaria.exe process other than
// the current one. Used to filter EnumWindows results.
static bool IsOtzariaProcess(DWORD pid) {
  if (pid == 0 || pid == GetCurrentProcessId()) return false;
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (h == nullptr) return false;
  wchar_t path[MAX_PATH] = {0};
  DWORD size = MAX_PATH;
  bool result = false;
  if (QueryFullProcessImageNameW(h, 0, path, &size)) {
    const wchar_t* name = wcsrchr(path, L'\\');
    name = name ? name + 1 : path;
    result = (_wcsicmp(name, kOtzariaExeName) == 0);
  }
  CloseHandle(h);
  return result;
}

struct FindWindowContext {
  HWND result;
};

static BOOL CALLBACK FindOtzariaWindowProc(HWND hwnd, LPARAM lparam) {
  FindWindowContext* ctx = reinterpret_cast<FindWindowContext*>(lparam);
  if (!IsWindowVisible(hwnd)) return TRUE;
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (!IsOtzariaProcess(pid)) return TRUE;
  ctx->result = hwnd;
  return FALSE;
}

// Searches all top-level windows for a visible window owned by another
// otzaria.exe process. Returns the first match, or nullptr.
static HWND FindOtzariaWindow() {
  FindWindowContext ctx = { nullptr };
  EnumWindows(FindOtzariaWindowProc, reinterpret_cast<LPARAM>(&ctx));
  return ctx.result;
}

// Restores a minimized window and brings it to the foreground.
static void BringWindowToFront(HWND hwnd) {
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetForegroundWindow(hwnd);
}

// Terminates every otzaria.exe process other than the current one. Waits up to
// 5 seconds per process so the OS can release any handles (mutex, files, ...)
// before we continue startup.
static void KillOtherOtzariaProcesses() {
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) return;

  PROCESSENTRY32W entry = {0};
  entry.dwSize = sizeof(entry);
  DWORD self_pid = GetCurrentProcessId();

  if (Process32FirstW(snap, &entry)) {
    do {
      if (entry.th32ProcessID == self_pid) continue;
      if (_wcsicmp(entry.szExeFile, kOtzariaExeName) != 0) continue;

      HANDLE h = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE,
                             entry.th32ProcessID);
      if (h == nullptr) continue;
      if (TerminateProcess(h, 1)) {
        WaitForSingleObject(h, 5000);
      }
      CloseHandle(h);
    } while (Process32NextW(snap, &entry));
  }

  CloseHandle(snap);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Single-instance check: must happen before the Flutter engine starts so
  // that the second instance never acquires any shared resources (DB, etc.).
  // bInitialOwner = FALSE: we don't need ownership, just existence of the object.
  // If CreateMutexW fails (returns NULL), treat as first instance so the app
  // can still start rather than being permanently blocked.
  HANDLE mutex =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  bool is_second_instance =
      (mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS);

  if (is_second_instance) {
    // Look for a real running instance — a visible window owned by another
    // otzaria.exe process. Retry briefly so we don't kill an instance that's
    // still in early startup and hasn't created its window yet.
    HWND existing = FindOtzariaWindow();
    for (int i = 0; existing == nullptr && i < 3; ++i) {
      Sleep(500);
      existing = FindOtzariaWindow();
    }

    if (existing != nullptr) {
      // Real instance is alive. Hand off any otzaria:// URIs so it can pick
      // them up via its file-watcher, then bring its window to the front.
      std::vector<std::string> args = GetCommandLineArguments();
      for (const auto& arg : args) {
        if (arg.size() >= 8 &&
            _strnicmp(arg.c_str(), "otzaria:", 8) == 0) {
          EnqueueUri(arg);
        }
      }
      BringWindowToFront(existing);
      CloseHandle(mutex);
      return EXIT_SUCCESS;
    }

    // The mutex is held but no Otzaria window exists — the existing process
    // is a zombie. Kill it and continue startup as the primary instance. Our
    // mutex handle stays open, so a future third instance will still see
    // ERROR_ALREADY_EXISTS against us.
    KillOtherOtzariaProcesses();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"אוצריא", origin, size)) {
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
