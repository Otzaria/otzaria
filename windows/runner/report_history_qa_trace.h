#ifndef REPORT_HISTORY_QA_TRACE_H_
#define REPORT_HISTORY_QA_TRACE_H_

#include <windows.h>
#include <commctrl.h>
#include <cstdio>
#include <iterator>
#include <string>

// Temporary observation only: every native message reaches the unchanged chain.
inline LRESULT CALLBACK ReportHistoryQaTrace(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR id,
    DWORD_PTR reference) {
  auto* path = reinterpret_cast<std::wstring*>(reference);
  switch (message) {
    case WM_KEYDOWN: case WM_KEYUP: case WM_SYSKEYDOWN: case WM_SYSKEYUP:
    case WM_CHAR: case WM_SYSCHAR: case WM_UNICHAR: case WM_PASTE:
    case WM_SETFOCUS: case WM_KILLFOCUS: {
      SYSTEMTIME utc{};
      GetSystemTime(&utc);
      char line[700];
      const int count = std::snprintf(
          line, sizeof(line),
          "{\"utc\":\"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ\","
          "\"tick\":%llu,\"hwnd\":%llu,\"message\":%u,\"wparam\":%llu,"
          "\"lparam\":%llu,\"scan\":%llu,\"extended\":%llu,"
          "\"previousDown\":%llu,\"ctrlState\":%d,\"ctrlAsync\":%d,"
          "\"foreground\":%llu,\"focus\":%llu}\n",
          static_cast<unsigned>(utc.wYear), static_cast<unsigned>(utc.wMonth),
          static_cast<unsigned>(utc.wDay), static_cast<unsigned>(utc.wHour),
          static_cast<unsigned>(utc.wMinute), static_cast<unsigned>(utc.wSecond),
          static_cast<unsigned>(utc.wMilliseconds),
          static_cast<unsigned long long>(GetTickCount64()),
          reinterpret_cast<unsigned long long>(hwnd), message,
          static_cast<unsigned long long>(wparam),
          static_cast<unsigned long long>(lparam),
          (static_cast<unsigned long long>(lparam) >> 16) & 0xff,
          (static_cast<unsigned long long>(lparam) >> 24) & 1,
          (static_cast<unsigned long long>(lparam) >> 30) & 1,
          (GetKeyState(VK_CONTROL) & 0x8000) != 0,
          (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0,
          reinterpret_cast<unsigned long long>(GetForegroundWindow()),
          reinterpret_cast<unsigned long long>(GetFocus()));
      const HANDLE file = CreateFileW(path->c_str(), FILE_APPEND_DATA,
          FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
          FILE_ATTRIBUTE_NORMAL, nullptr);
      if (file != INVALID_HANDLE_VALUE) {
        if (count > 0 && count < static_cast<int>(sizeof(line))) {
          DWORD written = 0;
          WriteFile(file, line, static_cast<DWORD>(count), &written, nullptr);
        }
        CloseHandle(file);
      }
      break;
    }
    case WM_NCDESTROY:
      RemoveWindowSubclass(hwnd, ReportHistoryQaTrace, id);
      delete path;
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

inline void InstallReportHistoryQaTrace(HWND view) {
  wchar_t path[32768];
  const DWORD length = GetEnvironmentVariableW(
      L"REPORT_QA_HISTORY_TRACE", path, static_cast<DWORD>(std::size(path)));
  if (!length || length >= std::size(path)) return;
  constexpr UINT_PTR id = 0x2256;
  DWORD_PTR existing = 0;
  if (GetWindowSubclass(view, ReportHistoryQaTrace, id, &existing)) return;
  auto* owned = new std::wstring(path, length);
  if (!SetWindowSubclass(view, ReportHistoryQaTrace, id,
                        reinterpret_cast<DWORD_PTR>(owned))) delete owned;
}

#endif
