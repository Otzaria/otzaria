#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <tlhelp32.h>
#include <dbghelp.h>
#include <psapi.h>
#include <intrin.h>
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#pragma comment(lib, "dbghelp.lib")
#pragma comment(lib, "psapi.lib")

namespace fs = std::filesystem;
static std::ofstream records;
static unsigned dumps = 0, stackCount = 0, debugBytes = 0;
static bool debugTruncated = false;
static ULONGLONG creation = 0;
static DWORD watchedPid = 0;
static std::wstring image;
static std::vector<DWORD> fatalCodes;

std::string utf8(const std::wstring& value) {
  if (value.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
  return result;
}
std::string quote(const std::string& value) {
  std::ostringstream out;
  out << '"';
  for (unsigned char c : value) {
    if (c == '"' || c == '\\') out << '\\' << c;
    else if (c < 32) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<unsigned>(c) << std::dec;
    else out << c;
  }
  out << '"';
  return out.str();
}
std::string hex(ULONGLONG value) {
  std::ostringstream out; out << "0x" << std::hex << value; return out.str();
}
ULONGLONG ticks(FILETIME value) {
  return (static_cast<ULONGLONG>(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}
ULONGLONG now() {
  FILETIME value{}; GetSystemTimeAsFileTime(&value); return ticks(value);
}
void record(const std::string& body) {
  records << "{\"utcFileTime\":" << quote(std::to_string(now())) << "," << body << "}\n";
  records.flush();
}
void failure(const char* stage, DWORD error) {
  record("\"event\":\"error\",\"stage\":" + quote(stage) + ",\"win32Error\":" + std::to_string(error));
}
bool exact(HANDLE process, const std::wstring& expected, ULONGLONG minimum) {
  wchar_t buffer[32768]; DWORD count = 32768;
  FILETIME made{}, ended{}, kernel{}, user{};
  if (!QueryFullProcessImageNameW(process, 0, buffer, &count) ||
      !GetProcessTimes(process, &made, &ended, &kernel, &user)) return false;
  if (_wcsicmp(std::wstring(buffer, count).c_str(), expected.c_str()) != 0 || ticks(made) < minimum) return false;
  image.assign(buffer, count); creation = ticks(made);
  return true;
}
HANDLE find(const std::wstring& expected, ULONGLONG minimum) {
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return nullptr;
  PROCESSENTRY32W entry{}; entry.dwSize = sizeof(entry);
  HANDLE selected = nullptr;
  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (entry.th32ProcessID == GetCurrentProcessId() ||
          _wcsicmp(entry.szExeFile, fs::path(expected).filename().c_str()) != 0) continue;
      HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ | SYNCHRONIZE, FALSE, entry.th32ProcessID);
      if (!process) continue;
      if (exact(process, expected, minimum)) {
        if (selected) { CloseHandle(process); CloseHandle(selected); CloseHandle(snapshot); throw std::runtime_error("Multiple exact-path processes match"); }
        watchedPid = entry.th32ProcessID; selected = process;
      } else CloseHandle(process);
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return selected;
}
std::wstring filePath(HANDLE file) {
  if (!file || file == INVALID_HANDLE_VALUE) return {};
  wchar_t path[32768];
  DWORD size = GetFinalPathNameByHandleW(file, path, 32768, FILE_NAME_NORMALIZED);
  if (!size || size >= 32768) return {};
  std::wstring result(path, size);
  if (result.rfind(L"\\\\?\\", 0) == 0) result.erase(0, 4);
  return result;
}
void frame(HANDLE process, DWORD tid, unsigned index, DWORD64 address, DWORD64 stack) {
  MEMORY_BASIC_INFORMATION info{};
  wchar_t path[32768]{};
  ULONGLONG base = 0;
  if (VirtualQueryEx(process, reinterpret_cast<LPCVOID>(address), &info, sizeof(info))) {
    base = reinterpret_cast<ULONGLONG>(info.AllocationBase);
    GetModuleFileNameExW(process, reinterpret_cast<HMODULE>(info.AllocationBase), path, 32768);
  }
  alignas(SYMBOL_INFO) char symbolBuffer[sizeof(SYMBOL_INFO) + 1024]{};
  auto* symbol = reinterpret_cast<SYMBOL_INFO*>(symbolBuffer);
  symbol->SizeOfStruct = sizeof(SYMBOL_INFO); symbol->MaxNameLen = 1023;
  DWORD64 displacement = 0;
  bool named = SymFromAddr(process, address, &displacement, symbol) != FALSE;
  IMAGEHLP_LINE64 line{}; line.SizeOfStruct = sizeof(line); DWORD lineDisplacement = 0;
  bool located = SymGetLineFromAddr64(process, address, &lineDisplacement, &line) != FALSE;
  IMAGEHLP_MODULE64 module{}; module.SizeOfStruct = sizeof(module);
  bool moduleKnown = SymGetModuleInfo64(process, address, &module) != FALSE;
  record("\"event\":\"frame\",\"tid\":" + std::to_string(tid) + ",\"index\":" + std::to_string(index) +
    ",\"pc\":" + quote(hex(address)) + ",\"sp\":" + quote(hex(stack)) +
    ",\"module\":" + quote(utf8(path)) + ",\"base\":" + quote(hex(base)) + ",\"rva\":" + quote(hex(address - base)) +
    ",\"symbol\":" + (named ? quote(symbol->Name) : "null") +
    ",\"symbolDisplacement\":" + quote(hex(displacement)) +
    ",\"pdb\":" + (moduleKnown ? quote(module.LoadedPdbName) : "null") +
    ",\"file\":" + (located ? quote(line.FileName) : "null") +
    ",\"line\":" + std::to_string(located ? line.LineNumber : 0));
}
bool context(HANDLE thread, CONTEXT& value) {
  value = {}; value.ContextFlags = CONTEXT_ALL;
  return GetThreadContext(thread, &value) != FALSE;
}
void stack(HANDLE process, HANDLE thread, DWORD tid, CONTEXT value) {
  STACKFRAME64 current{};
  current.AddrPC.Offset = value.Rip;
  current.AddrFrame.Offset = value.Rbp;
  current.AddrStack.Offset = value.Rsp;
  current.AddrPC.Mode = current.AddrFrame.Mode = current.AddrStack.Mode = AddrModeFlat;
  ++stackCount;
  frame(process, tid, 0, current.AddrPC.Offset, current.AddrStack.Offset);
  DWORD64 lastPc = current.AddrPC.Offset, lastSp = current.AddrStack.Offset;
  for (unsigned index = 1; index < 80; ++index) {
    if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, thread, &current, &value, nullptr,
        SymFunctionTableAccess64, SymGetModuleBase64, nullptr) || !current.AddrPC.Offset) break;
    if (current.AddrPC.Offset == lastPc && current.AddrStack.Offset == lastSp) break;
    frame(process, tid, index, current.AddrPC.Offset, current.AddrStack.Offset);
    lastPc = current.AddrPC.Offset; lastSp = current.AddrStack.Offset;
  }
}
void capture(HANDLE process, const DEBUG_EVENT& event, const fs::path& out) {
  const auto& details = event.u.Exception;
  fatalCodes.push_back(details.ExceptionRecord.ExceptionCode);
  HANDLE thread = OpenThread(THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, event.dwThreadId);
  CONTEXT value{};
  if (!thread || !context(thread, value)) {
    failure("GetExceptionThreadContext", GetLastError());
    if (thread) CloseHandle(thread);
    return;
  }
  if (dumps < 4) {
    fs::path name = out / (L"native-" + std::to_wstring(watchedPid) + L"-" + std::to_wstring(dumps) + L".dmp");
    HANDLE file = CreateFileW(name.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
      EXCEPTION_RECORD exception = details.ExceptionRecord;
      EXCEPTION_POINTERS pointers{&exception, &value};
      MINIDUMP_EXCEPTION_INFORMATION information{event.dwThreadId, &pointers, FALSE};
      MINIDUMP_TYPE type = static_cast<MINIDUMP_TYPE>(MiniDumpWithThreadInfo | MiniDumpWithUnloadedModules |
        MiniDumpWithFullMemoryInfo | MiniDumpWithIndirectlyReferencedMemory);
      BOOL written = MiniDumpWriteDump(process, watchedPid, file, type, &information, nullptr, nullptr);
      DWORD error = written ? 0 : GetLastError();
      FlushFileBuffers(file); CloseHandle(file);
      record("\"event\":\"dump\",\"path\":" + quote(utf8(name.wstring())) +
        ",\"written\":" + (written ? "true" : "false") + ",\"win32Error\":" + std::to_string(error));
      if (written) ++dumps;
    } else failure("CreateDump", GetLastError());
  }
  stack(process, thread, event.dwThreadId, value);
  CloseHandle(thread);
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (snapshot == INVALID_HANDLE_VALUE) { failure("ThreadsSnapshot", GetLastError()); return; }
  THREADENTRY32 entry{}; entry.dwSize = sizeof(entry);
  unsigned count = 0;
  if (Thread32First(snapshot, &entry)) {
    do {
      if (entry.th32OwnerProcessID != watchedPid || entry.th32ThreadID == event.dwThreadId) continue;
      if (++count > 96) { record("\"event\":\"threadLimit\",\"limit\":96"); break; }
      HANDLE other = OpenThread(THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, entry.th32ThreadID);
      if (!other) continue;
      CONTEXT otherValue{};
      if (context(other, otherValue)) stack(process, other, entry.th32ThreadID, otherValue);
      CloseHandle(other);
    } while (Thread32Next(snapshot, &entry));
  }
  CloseHandle(snapshot);
}
void outputString(HANDLE process, const OUTPUT_DEBUG_STRING_INFO& value) {
  size_t requested = std::min<size_t>(value.nDebugStringLength, 8192) * (value.fUnicode ? 2 : 1);
  if (debugBytes >= 1024 * 1024) { debugTruncated = true; return; }
  std::vector<char> buffer(requested + 2, 0);
  SIZE_T read = 0;
  if (!ReadProcessMemory(process, value.lpDebugStringData, buffer.data(), requested, &read)) return;
  debugBytes += static_cast<unsigned>(read);
  std::string message;
  if (value.fUnicode) {
    std::wstring wide(reinterpret_cast<const wchar_t*>(buffer.data()), read / 2);
    while (!wide.empty() && wide.back() == L'\0') wide.pop_back();
    message = utf8(wide);
  } else {
    int length = MultiByteToWideChar(CP_ACP, 0, buffer.data(), static_cast<int>(read), nullptr, 0);
    std::wstring wide(length, L'\0');
    MultiByteToWideChar(CP_ACP, 0, buffer.data(), static_cast<int>(read), wide.data(), length);
    while (!wide.empty() && wide.back() == L'\0') wide.pop_back();
    message = utf8(wide);
  }
  record("\"event\":\"outputDebugString\",\"text\":" + quote(message));
}
int watch(const std::wstring& expected, const fs::path& out, const fs::path& stop) {
  fs::create_directories(out);
  records.open(out / "native-debug-events.jsonl", std::ios::binary);
  if (!records) return 2;
  ULONGLONG armed = now();
  HANDLE preexisting = find(expected, 0);
  if (preexisting) { CloseHandle(preexisting); failure("ExistingTargetRejected", ERROR_ALREADY_EXISTS); return 2; }
  watchedPid = 0; creation = 0; image.clear();
  { std::ofstream ready(out / "armed.json", std::ios::binary);
    ready << "{\"expectedExecutable\":" << quote(utf8(expected)) << ",\"armedFileTime\":" << quote(std::to_string(armed)) << "}\n"; }
  HANDLE process = nullptr;
  auto limit = std::chrono::steady_clock::now() + std::chrono::minutes(24);
  while (std::chrono::steady_clock::now() < limit && !fs::exists(stop)) {
    process = find(expected, armed);
    if (process) break;
    Sleep(20);
  }
  if (!process) { failure("OwnedTargetNotStarted", WAIT_TIMEOUT); return 3; }
  record("\"event\":\"identity\",\"pid\":" + std::to_string(watchedPid) +
    ",\"creationFileTime\":" + quote(std::to_string(creation)) + ",\"executable\":" + quote(utf8(image)) +
    ",\"armedFileTime\":" + quote(std::to_string(armed)));
  if (!DebugActiveProcess(watchedPid)) {
    failure("DebugActiveProcess", GetLastError()); CloseHandle(process); return 4;
  }
  if (!DebugSetProcessKillOnExit(FALSE)) {
    failure("DebugSetProcessKillOnExit", GetLastError());
    DebugActiveProcessStop(watchedPid); CloseHandle(process); return 4;
  }
  SymSetOptions(SYMOPT_UNDNAME | SYMOPT_LOAD_LINES | SYMOPT_DEFERRED_LOADS | SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS);
  std::wstring search = fs::path(expected).parent_path().wstring();
  bool symbols = SymInitializeW(process, search.c_str(), FALSE) != FALSE;
  record("\"event\":\"debuggerAttached\",\"symbolsInitialized\":" + std::string(symbols ? "true" : "false") +
    ",\"symbolSearchPath\":" + quote(utf8(search)) + ",\"networkSymbolDownloads\":false,\"killTargetOnExit\":false");
  bool initial = false, exited = false, detached = false;
  DWORD observedExit = STILL_ACTIVE;
  limit = std::chrono::steady_clock::now() + std::chrono::minutes(35);
  unsigned exceptionCount = 0;
  while (std::chrono::steady_clock::now() < limit) {
    DEBUG_EVENT event{};
    if (!WaitForDebugEventEx(&event, 500)) {
      DWORD error = GetLastError();
      if (error != ERROR_SEM_TIMEOUT) { failure("WaitForDebugEventEx", error); break; }
      if (fs::exists(stop)) break;
      continue;
    }
    DWORD disposition = DBG_CONTINUE;
    switch (event.dwDebugEventCode) {
      case CREATE_PROCESS_DEBUG_EVENT: {
        auto path = filePath(event.u.CreateProcessInfo.hFile);
        record("\"event\":\"createProcess\",\"image\":" + quote(utf8(path)) +
          ",\"imageBase\":" + quote(hex(reinterpret_cast<ULONGLONG>(event.u.CreateProcessInfo.lpBaseOfImage))));
        if (symbols) SymLoadModuleExW(process, event.u.CreateProcessInfo.hFile, path.c_str(), nullptr,
          reinterpret_cast<DWORD64>(event.u.CreateProcessInfo.lpBaseOfImage), 0, nullptr, 0);
        if (event.u.CreateProcessInfo.hFile) CloseHandle(event.u.CreateProcessInfo.hFile);
        break;
      }
      case LOAD_DLL_DEBUG_EVENT: {
        auto path = filePath(event.u.LoadDll.hFile);
        record("\"event\":\"loadDll\",\"path\":" + quote(utf8(path)) +
          ",\"base\":" + quote(hex(reinterpret_cast<ULONGLONG>(event.u.LoadDll.lpBaseOfDll))));
        if (symbols && !path.empty()) SymLoadModuleExW(process, event.u.LoadDll.hFile, path.c_str(), nullptr,
          reinterpret_cast<DWORD64>(event.u.LoadDll.lpBaseOfDll), 0, nullptr, 0);
        if (event.u.LoadDll.hFile) CloseHandle(event.u.LoadDll.hFile);
        break;
      }
      case UNLOAD_DLL_DEBUG_EVENT:
        if (symbols) SymUnloadModule64(process, reinterpret_cast<DWORD64>(event.u.UnloadDll.lpBaseOfDll));
        break;
      case OUTPUT_DEBUG_STRING_EVENT:
        outputString(process, event.u.DebugString); break;
      case EXCEPTION_DEBUG_EVENT: {
        const auto& value = event.u.Exception;
        const auto& exception = value.ExceptionRecord;
        std::ostringstream fields;
        fields << "\"event\":\"exception\",\"tid\":" << event.dwThreadId
          << ",\"code\":" << quote(hex(exception.ExceptionCode))
          << ",\"flags\":" << exception.ExceptionFlags
          << ",\"address\":" << quote(hex(reinterpret_cast<ULONGLONG>(exception.ExceptionAddress)))
          << ",\"firstChance\":" << (value.dwFirstChance ? "true" : "false")
          << ",\"parameters\":[";
        for (DWORD i = 0; i < std::min<DWORD>(exception.NumberParameters, EXCEPTION_MAXIMUM_PARAMETERS); ++i) {
          if (i) fields << ',';
          fields << quote(hex(exception.ExceptionInformation[i]));
        }
        fields << ']';
        if (exceptionCount++ < 2048) record(fields.str());
        disposition = DBG_EXCEPTION_NOT_HANDLED;
        if (!initial && value.dwFirstChance && exception.ExceptionCode == EXCEPTION_BREAKPOINT) {
          initial = true; disposition = DBG_CONTINUE;
          record("\"event\":\"initialAttachBreakpointContinued\"");
        } else if (!value.dwFirstChance || exception.ExceptionCode == 0xC0000409 || exception.ExceptionCode == 0xC0000602) {
          if (fatalCodes.size() < 4) capture(process, event, out);
        }
        break;
      }
      case EXIT_PROCESS_DEBUG_EVENT:
        exited = true; observedExit = event.u.ExitProcess.dwExitCode;
        record("\"event\":\"processExit\",\"code\":" + quote(hex(observedExit)) +
          ",\"unsignedExit\":" + std::to_string(observedExit));
        break;
      default: break;
    }
    if (!ContinueDebugEvent(event.dwProcessId, event.dwThreadId, disposition)) {
      failure("ContinueDebugEvent", GetLastError()); break;
    }
    if (exited) break;
  }
  DWORD detachError = 0;
  if (!exited) {
    detached = DebugActiveProcessStop(watchedPid) != FALSE;
    if (!detached) { detachError = GetLastError(); failure("DebugActiveProcessStop", detachError); }
  }
  if (symbols) SymCleanup(process);
  DWORD finalCode = STILL_ACTIVE; GetExitCodeProcess(process, &finalCode);
  CloseHandle(process);
  std::ofstream summary(out / "native-debug-summary.json", std::ios::binary);
  summary << "{\"pid\":" << watchedPid << ",\"creationFileTime\":" << quote(std::to_string(creation))
    << ",\"executable\":" << quote(utf8(image)) << ",\"expectedExecutable\":" << quote(utf8(expected))
    << ",\"processExitObserved\":" << (exited ? "true" : "false") << ",\"unsignedExit\":" << observedExit
    << ",\"finalHandleExit\":" << finalCode << ",\"dumpCount\":" << dumps << ",\"stackCount\":" << stackCount
    << ",\"detachedWhileLive\":" << (detached ? "true" : "false") << ",\"detachError\":" << detachError
    << ",\"targetTerminatedByDebugger\":false,\"debugOutputBytes\":" << debugBytes
    << ",\"debugOutputTruncated\":" << (debugTruncated ? "true" : "false") << ",\"fatalCodes\":[";
  for (size_t i = 0; i < fatalCodes.size(); ++i) { if (i) summary << ','; summary << quote(hex(fatalCodes[i])); }
  summary << "]}\n";
  summary.close();
  return exited && dumps > 0 ? 0 : exited ? 10 : 11;
}
int wmain(int argc, wchar_t** argv) {
  if (argc == 2 && std::wstring(argv[1]) == L"--fault") {
    Sleep(1200); __fastfail(FAST_FAIL_FATAL_APP_EXIT);
  }
  if (argc != 5 || std::wstring(argv[1]) != L"--watch") return 64;
  try { return watch(fs::absolute(argv[2]).lexically_normal().wstring(), argv[3], argv[4]); }
  catch (const std::exception& error) {
    if (records) record("\"event\":\"fatalMonitorError\",\"message\":" + quote(error.what()));
    return 70;
  }
}
