#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
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
#include "../../windows/runner/hang_monitor.cpp"

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

DWORD WINAPI WaitInNativeWorker(LPVOID event) {
  WaitForSingleObject(static_cast<HANDLE>(event), INFINITE);
  return 0;
}

std::string ReadLog(const std::wstring& path) {
  std::ifstream record(std::filesystem::path(path), std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(record), {});
}

void TestLoaderPriority() {
#if defined(_M_X64)
  hang_monitor::LoadLoaderEntries();
  Require(hang_monitor::LoaderProbeReady(), "Loader exports must be available");
  const auto load = hang_monitor::g_loader_entries.front();
  Require(load.address != 0 && hang_monitor::IsLoaderFrame(load.address),
          "LdrLoadDll must be recognized even if the export lacks unwind data");
  if (load.function_begin != 0) {
    Require(hang_monitor::IsLoaderFrame(load.address + 1),
            "LdrLoadDll must be recognized from a program counter in its body");
  }
  // משתמשים בכתובת מתוך טבלת החריגות, גם כשה-linker מחזיר thunk לסמל.
  const auto image = reinterpret_cast<ULONG_PTR>(GetModuleHandleW(nullptr));
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
  const auto* nt =
      reinterpret_cast<const IMAGE_NT_HEADERS*>(image + dos->e_lfanew);
  const auto& directory =
      nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXCEPTION];
  const auto* unwind_entries =
      reinterpret_cast<const RUNTIME_FUNCTION*>(image + directory.VirtualAddress);
  bool checked_unwind = false;
  for (size_t i = 0; i < directory.Size / sizeof(*unwind_entries); ++i) {
    if (unwind_entries[i].EndAddress - unwind_entries[i].BeginAddress <= 1) continue;
    const ULONG_PTR pc = image + unwind_entries[i].BeginAddress + 1;
    DWORD64 lookup_image = 0;
    const auto* function = RtlLookupFunctionEntry(pc, &lookup_image, nullptr);
    if (function == nullptr || lookup_image != image) continue;
    const auto* unwind = reinterpret_cast<const BYTE*>(image + function->UnwindData);
    if (((unwind[0] >> 3) & UNW_FLAG_CHAININFO) != 0) continue;
    Require(hang_monitor::FunctionBegin(pc, image) ==
                image + function->BeginAddress,
            "The guarded lookup must resolve an interior PC with unwind data");
    checked_unwind = true;
    break;
  }
  Require(checked_unwind, "The fixture must exercise a real x64 unwind entry");
#endif
  hang_monitor::ThreadCapture crowded;
  for (size_t i = 0; i < hang_monitor::kMaxPeerStacks + 1; ++i) {
    auto& thread = crowded.threads.emplace_back();
    thread.id = static_cast<DWORD>(1 + i);
    thread.frames.push_back(0x1234);
  }
  crowded.threads.back().in_loader = true;
  hang_monitor::LimitPeerStacks(&crowded);
  Require(crowded.threads.size() == hang_monitor::kMaxPeerStacks &&
              crowded.threads.front().in_loader && crowded.omitted == 1,
          "An idle loader thread must survive the stack limit");
  std::string details;
  std::vector<ULONG_PTR> frames;
  hang_monitor::AppendOtherThreads(crowded, 128, &details, &frames);
  Require(details.find("in loader") != std::string::npos && frames.size() == 1,
          "The loader stack must be written first when the log budget is tight");
}

void TestNativePeerCapture() {
  const HWND window = CreateWindowW(L"STATIC", L"", WS_POPUP, 0, 0, 1, 1,
                                    nullptr, nullptr, nullptr, nullptr);
  Require(window != nullptr, "Cannot create the fixture's UI window");
  const HANDLE release = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  Require(release != nullptr, "Cannot create the native worker event");
  DWORD worker_id = 0;
  const HANDLE worker =
      CreateThread(nullptr, 0, WaitInNativeWorker, release, 0, &worker_id);
  Require(worker != nullptr, "Cannot start the native worker");
  Require(SUCCEEDED(SetThreadDescription(worker, L"tokio-runtime-worker\npeer")),
          "Cannot name the native worker");
  hang_monitor::LoadThreadNameReader();
  hang_monitor::SetMainWindow(window);
  hang_monitor::g_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  Require(hang_monitor::g_stop_event != nullptr, "Cannot create the stop event");

  hang_monitor::ThreadCapture capture;
  std::thread inspector([&] { capture = hang_monitor::CaptureOtherThreads(false); });
  inspector.join();
  SetEvent(release);
  Require(WaitForSingleObject(worker, 5000) == WAIT_OBJECT_0,
          "The inspected native thread must resume");
  CloseHandle(worker);
  CloseHandle(release);
  hang_monitor::Stop();
  hang_monitor::SetMainWindow(nullptr);
  DestroyWindow(window);

  Require(capture.ui_cpu_ms && *capture.ui_cpu_ms < hang_monitor::kLowUiCpuMs,
          "The sleeping UI thread must be classified as low CPU");
  const auto worker_stack = std::find_if(
      capture.threads.begin(), capture.threads.end(),
      [&](const hang_monitor::OtherThread& thread) { return thread.id == worker_id; });
  Require(worker_stack != capture.threads.end() && !worker_stack->frames.empty(),
          "A later hang must include a native peer when the UI is waiting");
  Require(worker_stack->name == "tokio-runtime-worker peer",
          "Native thread names survive with line breaks removed");
  std::vector<ULONG_PTR> described;
  std::string details;
  Require(hang_monitor::AppendOtherThreads(capture, 0, &details, &described) == 0 &&
              described.empty() && details.find("omitted") != std::string::npos,
          "A full log budget must omit peer stacks");
}

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
  // Equivalent to the Dart encoder for the reading screen, 4 tabs, PDF, Semantics on.
  OtzariaSetIncidentContext(3u | (2u << 4) | (1u << 8) | (4u << 9));
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

  constexpr char kContextLine[] =
      "Context: screen=reading; tabs=4; tab=pdf; semantics=on";
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
    const std::string record = ReadLog(log);
    Require(record.find(kContextLine, complete ? 0 : before) != std::string::npos,
            "The process writer and the WER fallback must both include context");
    std::cout << "scenario=" << scenario << " recorded=" << complete
              << " bytes=" << before << "->" << after << std::endl;
  }
  CrashWerContext legacy = {};
  memcpy(&legacy, &crash_record::g_wer, kLegacyCrashWerContextSize);
  legacy.size = static_cast<DWORD>(kLegacyCrashWerContextSize);
  legacy.recorded = 0;
  const auto legacy_start = std::filesystem::file_size(log);
  BOOL claimed = TRUE;
  Require(callback(&legacy, &info, &claimed, nullptr, nullptr, nullptr) == S_OK &&
              !claimed,
          "The new WER DLL must accept the previous context layout");
  const std::string legacy_record = ReadLog(log).substr(legacy_start);
  Require(!legacy_record.empty() &&
              legacy_record.find(kContextLine) == std::string::npos,
          "A legacy runner must produce a report without the optional word");
  TestLoaderPriority();
  TestNativePeerCapture();
  CloseHandle(crash_record::g_crash_event);
  CloseHandle(crash_record::g_done_event);
  FreeLibrary(module);
  std::cout << "WER static CRT, parent dynamic CRT, writer fallback: PASS" << std::endl;
  return 0;
}
