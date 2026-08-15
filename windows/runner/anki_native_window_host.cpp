#include "anki_native_window_host.h"

#include <knownfolders.h>
#include <shlobj.h>

#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <vector>

namespace {

std::wstring Lowercase(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), towlower);
  return value;
}

std::wstring ProcessPath(DWORD process_id) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (!process) return {};
  std::vector<wchar_t> buffer(32768);
  DWORD size = static_cast<DWORD>(buffer.size());
  const bool success = QueryFullProcessImageNameW(process, 0, buffer.data(), &size);
  CloseHandle(process);
  return success ? std::wstring(buffer.data(), size) : std::wstring();
}

std::wstring KnownFolder(REFKNOWNFOLDERID id) {
  wchar_t* raw = nullptr;
  if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &raw))) {
    return {};
  }
  std::wstring value(raw);
  CoTaskMemFree(raw);
  return value;
}

std::wstring FindAnkiExecutable() {
  const std::vector<std::filesystem::path> candidates = {
      std::filesystem::path(KnownFolder(FOLDERID_LocalAppData)) /
          L"Programs" / L"Anki" / L"anki.exe",
      std::filesystem::path(KnownFolder(FOLDERID_ProgramFiles)) /
          L"Anki" / L"anki.exe",
      std::filesystem::path(KnownFolder(FOLDERID_ProgramFilesX86)) /
          L"Anki" / L"anki.exe",
  };
  for (const auto& candidate : candidates) {
    std::error_code error;
    if (!candidate.empty() && std::filesystem::is_regular_file(candidate, error)) {
      return candidate.wstring();
    }
  }
  return {};
}

std::vector<wchar_t> BackgroundEnvironment() {
  constexpr wchar_t kVariablePrefix[] = L"OTZARIA_ANKI_BACKGROUND=";
  std::vector<std::wstring> entries;
  wchar_t* environment = GetEnvironmentStringsW();
  if (environment) {
    for (const wchar_t* entry = environment; *entry;
         entry += wcslen(entry) + 1) {
      std::wstring value(entry);
      if (Lowercase(value).rfind(Lowercase(kVariablePrefix), 0) != 0) {
        entries.push_back(std::move(value));
      }
    }
    FreeEnvironmentStringsW(environment);
  }
  entries.emplace_back(L"OTZARIA_ANKI_BACKGROUND=1");
  std::sort(entries.begin(), entries.end(), [](const auto& left, const auto& right) {
    return Lowercase(left) < Lowercase(right);
  });

  size_t length = 1;
  for (const auto& entry : entries) length += entry.size() + 1;
  std::vector<wchar_t> block(length, L'\0');
  wchar_t* output = block.data();
  for (const auto& entry : entries) {
    std::copy(entry.begin(), entry.end(), output);
    output += entry.size() + 1;
  }
  return block;
}

}  // namespace

AnkiNativeWindowHost::AnkiNativeWindowHost(HWND flutter_view)
    : flutter_view_(flutter_view) {}

AnkiNativeWindowHost::~AnkiNativeWindowHost() {
  Detach();
  if (container_) {
    DestroyWindow(container_);
    container_ = nullptr;
  }
}

bool AnkiNativeWindowHost::EnsureContainer(std::string* error) {
  if (container_) return true;
  container_ = CreateWindowExW(
      0, L"STATIC", L"", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
      0, 0, 1, 1, flutter_view_, nullptr, GetModuleHandle(nullptr), nullptr);
  if (!container_) {
    *error = "CreateWindowEx failed: " + std::to_string(GetLastError());
    return false;
  }
  return true;
}

bool AnkiNativeWindowHost::ValidateAnkiWindow(
    HWND target, DWORD expected_process_id, std::string* error) const {
  if (!IsWindow(target)) {
    *error = "The Anki window no longer exists";
    return false;
  }
  DWORD actual_process_id = 0;
  GetWindowThreadProcessId(target, &actual_process_id);
  if (!actual_process_id || actual_process_id != expected_process_id) {
    *error = "The window does not belong to the reported Anki process";
    return false;
  }
  const auto path = ProcessPath(actual_process_id);
  if (path.empty() || Lowercase(std::filesystem::path(path).filename().wstring()) !=
                          L"anki.exe") {
    *error = "The reported process is not anki.exe";
    return false;
  }
  return true;
}

bool AnkiNativeWindowHost::Prepare(HWND* container, std::string* error) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!EnsureContainer(error)) return false;
  *container = container_;
  return true;
}

bool AnkiNativeWindowHost::Attach(HWND target, DWORD expected_process_id,
                                  std::string* error) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!EnsureContainer(error) ||
      !ValidateAnkiWindow(target, expected_process_id, error)) {
    return false;
  }
  if (target_ == target) {
    return true;
  }
  if (target_) DetachUnlocked();

  if (GetParent(target) != container_) {
    *error = "Anki window was not parented by Qt";
    return false;
  }

  target_ = target;
  ShowWindow(container_, visible_ ? SW_SHOW : SW_HIDE);
  return true;
}

bool AnkiNativeWindowHost::SetBounds(int x, int y, int width, int height,
                                     std::string* error) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (width <= 0 || height <= 0) {
    *error = "Native host bounds must be positive";
    return false;
  }
  if (!EnsureContainer(error)) return false;
  const UINT flags = SWP_NOACTIVATE | (visible_ ? SWP_SHOWWINDOW : 0);
  if (!SetWindowPos(container_, HWND_TOP, x, y, width, height, flags)) {
    *error = "SetWindowPos failed: " + std::to_string(GetLastError());
    return false;
  }
  return true;
}

void AnkiNativeWindowHost::SetVisible(bool visible) {
  std::lock_guard<std::mutex> lock(mutex_);
  visible_ = visible;
  if (container_) ShowWindow(container_, visible ? SW_SHOW : SW_HIDE);
}

void AnkiNativeWindowHost::Detach() {
  std::lock_guard<std::mutex> lock(mutex_);
  DetachUnlocked();
}

void AnkiNativeWindowHost::DetachUnlocked() {
  if (container_) ShowWindow(container_, SW_HIDE);
  if (!target_) {
    return;
  }
  target_ = nullptr;
}

bool AnkiNativeWindowHost::LaunchAnki(std::string* error) {
  const std::wstring executable = FindAnkiExecutable();
  if (executable.empty()) {
    *error = "Anki installation was not found";
    return false;
  }
  std::wstring command_line = L"\"" + executable + L"\"";
  std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
  mutable_command.push_back(L'\0');
  auto environment = BackgroundEnvironment();
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  const DWORD flags = CREATE_UNICODE_ENVIRONMENT | CREATE_BREAKAWAY_FROM_JOB;
  const std::wstring working_directory =
      std::filesystem::path(executable).parent_path().wstring();
  if (!CreateProcessW(executable.c_str(), mutable_command.data(), nullptr,
                      nullptr, FALSE, flags, environment.data(),
                      working_directory.c_str(), &startup, &process)) {
    *error = "CreateProcess failed: " + std::to_string(GetLastError());
    return false;
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return true;
}
