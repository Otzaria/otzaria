#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Debug: Print all command line arguments
  for (size_t i = 0; i < command_line_arguments.size(); i++) {
    OutputDebugStringA("Arg ");
    OutputDebugStringA(std::to_string(i).c_str());
    OutputDebugStringA(": ");
    OutputDebugStringA(command_line_arguments[i].c_str());
    OutputDebugStringA("\n");
  }

  // Check if any argument contains otzaria:// and add --url= prefix if not already present
  bool urlFound = false;
  for (const auto& arg : command_line_arguments) {
    // Check if URL is already in --url= format
    if (arg.find("--url=") == 0) {
      urlFound = true;
      break;
    }
    // Check if we have a direct otzaria:// URL
    if (arg.find("otzaria://") != std::string::npos) {
      OutputDebugStringA("Found URL in arguments: ");
      OutputDebugStringA(arg.c_str());
      OutputDebugStringA("\n");
      
      // The URL is already in UTF-8, just pass it as is with --url= prefix
      command_line_arguments.push_back("--url=" + arg);
      urlFound = true;
      break;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"אוצריא", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
