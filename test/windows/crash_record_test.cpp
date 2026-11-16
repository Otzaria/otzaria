#include <windows.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <iostream>
#include <string>

enum class WriteMode { complete, failed, partial };
WriteMode write_mode = WriteMode::complete;

BOOL WINAPI TestWriteFile(HANDLE file, LPCVOID data, DWORD length,
                          LPDWORD written, LPOVERLAPPED overlapped) {
  if (write_mode == WriteMode::failed) {
    *written = 0;
    SetLastError(ERROR_DISK_FULL);
    return FALSE;
  }
  return WriteFile(file, data,
                   write_mode == WriteMode::partial ? length / 2 : length,
                   written, overlapped);
}

// מריצים את ה-writer וה-callback ישירות, בלי Install, רישום WER או קריסה.
#define WriteFile TestWriteFile
#include "../../windows/runner/startup_watchdog.cpp"
#undef WriteFile
#include "../../windows/runner/crash_record.cpp"

void Require(bool condition, const char* message) {
  if (condition) return;
  std::cerr << message << std::endl;
  std::exit(1);
}

bool ImportsCrt(HMODULE module) {
  const auto base = reinterpret_cast<const unsigned char*>(module);
  const auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
  const auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
  const auto& directory =
      nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  const auto imports =
      reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(base + directory.VirtualAddress);
  for (auto entry = imports; entry->Name != 0; ++entry) {
    std::string name(reinterpret_cast<const char*>(base + entry->Name));
    std::transform(name.begin(), name.end(), name.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (name.find("vcruntime") != std::string::npos ||
        name.find("msvcp") != std::string::npos ||
        name.find("ucrtbase") != std::string::npos ||
        name.find("api-ms-win-crt") != std::string::npos) {
      return true;
    }
  }
  return false;
}

using Callback = HRESULT (*)(PVOID, const PWER_RUNTIME_EXCEPTION_INFORMATION,
                            BOOL*, PWSTR, PDWORD, PDWORD);

int wmain(int argc, wchar_t** argv) {
  Require(argc == 2, "Pass the built WER DLL path");
  HMODULE module = LoadLibraryW(argv[1]);
  Require(module != nullptr, "WER DLL did not load");
  Require(!ImportsCrt(module), "WER DLL depends on a dynamic CRT");
  Require(ImportsCrt(GetModuleHandleW(nullptr)),
          "WER directory changed the parent target's CRT");
  const auto callback = reinterpret_cast<Callback>(
      GetProcAddress(module, "OutOfProcessExceptionEventCallback"));
  Require(callback != nullptr, "WER callback missing");

  wchar_t exe[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, exe, MAX_PATH);
  const auto directory = std::filesystem::path(exe).parent_path();
  HANDLE marker = CreateFileW((directory / L"portable.marker").c_str(), GENERIC_WRITE,
                             FILE_SHARE_READ, nullptr, CREATE_ALWAYS, 0, nullptr);
  Require(marker != INVALID_HANDLE_VALUE, "Cannot create private portable marker");
  CloseHandle(marker);
  const auto log = startup_watchdog::ErrorLogPath();
  std::filesystem::create_directories(std::filesystem::path(log).parent_path());

  crash_record::g_wer.magic = CrashWerContext::kMagic;
  crash_record::g_wer.size = sizeof(CrashWerContext);
  wcscpy_s(crash_record::g_wer.log_path, log.c_str());
  crash_record::g_main_thread_id = GetCurrentThreadId();
  crash_record::g_crash_thread_id = GetCurrentThreadId();
  crash_record::g_record.ExceptionCode = EXCEPTION_ACCESS_VIOLATION;
  crash_record::g_record.ExceptionAddress = reinterpret_cast<void*>(&wmain);
  crash_record::g_crash_event = CreateEventW(nullptr, TRUE, TRUE, nullptr);
  crash_record::g_done_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  Require(crash_record::g_crash_event && crash_record::g_done_event,
          "Cannot create writer events");

  WER_RUNTIME_EXCEPTION_INFORMATION info = {};
  info.dwSize = sizeof(info);
  info.hProcess = GetCurrentProcess();
  info.hThread = GetCurrentThread();
  info.bIsFatal = TRUE;
  info.exceptionRecord = crash_record::g_record;
  RtlCaptureContext(&info.context);

  for (int scenario = 0; scenario < 4; ++scenario) {
    const bool locked = scenario == 0;
    write_mode = scenario == 1 ? WriteMode::failed
                 : scenario == 2 ? WriteMode::partial
                                 : WriteMode::complete;
    HANDLE file = CreateFileW(log.c_str(), GENERIC_WRITE, 0, nullptr,
                             CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    Require(file != INVALID_HANDLE_VALUE, "Cannot reset private log");
    if (!locked) CloseHandle(file);
    crash_record::g_wer.recorded = 0;
    ResetEvent(crash_record::g_done_event);
    crash_record::WriterThread(nullptr);
    if (locked) CloseHandle(file);
    const bool complete = scenario == 3;
    Require((crash_record::g_wer.recorded != 0) == complete,
            "Only a complete write may suppress WER");
    Require(WaitForSingleObject(crash_record::g_done_event, 0) == WAIT_OBJECT_0,
            "A failed write must still release the crash handler");
    const auto before = std::filesystem::file_size(log);
    BOOL claimed = TRUE;
    Require(callback(&crash_record::g_wer, &info, &claimed, nullptr, nullptr,
                      nullptr) == S_OK && !claimed,
            "WER must leave ownership to other crash handlers");
    const auto after = std::filesystem::file_size(log);
    Require(complete ? after == before && after > 0 : after > before,
            "WER must retry a failed/partial write and skip a complete one");
    std::cout << "scenario=" << scenario << " recorded=" << complete
              << " bytes=" << before << "->" << after << std::endl;
  }
  CloseHandle(crash_record::g_crash_event);
  CloseHandle(crash_record::g_done_event);
  FreeLibrary(module);
  std::cout << "WER static CRT, parent dynamic CRT, writer fallback: PASS" << std::endl;
  return 0;
}
