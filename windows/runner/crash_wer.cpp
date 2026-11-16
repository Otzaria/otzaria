// מודול WER: רץ בתוך WerFault.exe כשאוצריא קורסת, וכותב ל-errors.txt רשומת
// `Native crash` לקריסות שהמטפל בתהליך לא ראה (fastfail, heap corruption).
#include <windows.h>

#include <dbghelp.h>
#include <psapi.h>
#include <werapi.h>

#include <cstddef>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "crash_wer_context.h"
#include "image_identity.h"

namespace {

constexpr size_t kMaxFrames = 64;

bool ReadRemote(HANDLE process, ULONG_PTR address, void* out, size_t size) {
  SIZE_T read = 0;
  return ::ReadProcessMemory(process, reinterpret_cast<LPCVOID>(address), out,
                             size, &read) &&
         read == size;
}

std::string BaseNameUtf8(const wchar_t* path) {
  const wchar_t* name = ::wcsrchr(path, L'\\');
  name = name == nullptr ? path : name + 1;
  char narrow[MAX_PATH * 3] = {0};
  if (::WideCharToMultiByte(CP_UTF8, 0, name, -1, narrow, sizeof(narrow),
                            nullptr, nullptr) <= 0) {
    return std::string();
  }
  return narrow;
}

struct Module {
  ULONG_PTR base = 0;
  std::string name;
  bool is_dart = false;
};

// כמו בתהליך עצמו: שם המודול מה-loader, ו-app.so לפי כותרת ה-ELF.
Module FindModule(HANDLE process, ULONG_PTR address) {
  MEMORY_BASIC_INFORMATION info = {};
  if (::VirtualQueryEx(process, reinterpret_cast<LPCVOID>(address), &info,
                       sizeof(info)) == 0) {
    return {};
  }
  const auto base = reinterpret_cast<ULONG_PTR>(info.AllocationBase);
  if (info.Type == MEM_IMAGE) {
    wchar_t path[MAX_PATH] = {0};
    DWORD length = ::GetModuleFileNameExW(
        process, reinterpret_cast<HMODULE>(base), path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
      length = ::GetMappedFileNameW(process, reinterpret_cast<LPVOID>(address),
                                    path, MAX_PATH);
    }
    if (length == 0 || length >= MAX_PATH) return {};
    return {base, BaseNameUtf8(path), false};
  }
  unsigned char magic[4] = {};
  if (info.Type == MEM_PRIVATE &&
      (info.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ)) != 0 &&
      ReadRemote(process, base, magic, sizeof(magic)) &&
      memcmp(magic, "\x7f" "ELF", sizeof(magic)) == 0) {
    return {base, "app.so", true};
  }
  return {};
}

std::string Describe(HANDLE process, ULONG_PTR address) {
  char buffer[MAX_PATH * 3 + 32];
  const Module module = FindModule(process, address);
  if (module.base == 0 || module.name.empty()) {
    snprintf(buffer, sizeof(buffer), "0x%llx",
             static_cast<unsigned long long>(address));
  } else {
    snprintf(buffer, sizeof(buffer), "%s+0x%llx", module.name.c_str(),
             static_cast<unsigned long long>(address - module.base));
  }
  return buffer;
}

// בלי נתיב סמלים: הפרישה צריכה רק את טבלאות ה-unwind שבזיכרון המודולים.
void Walk(HANDLE process, HANDLE thread, CONTEXT context,
          std::vector<ULONG_PTR>* frames) {
  ::SymSetOptions(SYMOPT_DEFERRED_LOADS | SYMOPT_FAIL_CRITICAL_ERRORS |
                  SYMOPT_NO_PROMPTS | SYMOPT_IGNORE_NT_SYMPATH |
                  SYMOPT_IGNORE_CVREC);
  if (!::SymInitializeW(process, L"", TRUE)) return;
  // StackWalk64 ולא StackWalkEx: האחרון מוסיף פריימי inline כשיש PDB.
  STACKFRAME64 frame = {};
#if defined(_M_X64)
  constexpr DWORD kMachine = IMAGE_FILE_MACHINE_AMD64;
  frame.AddrPC.Offset = context.Rip;
  frame.AddrStack.Offset = context.Rsp;
  frame.AddrFrame.Offset = context.Rbp;
#elif defined(_M_ARM64)
  constexpr DWORD kMachine = IMAGE_FILE_MACHINE_ARM64;
  frame.AddrPC.Offset = context.Pc;
  frame.AddrStack.Offset = context.Sp;
  frame.AddrFrame.Offset = context.Fp;
#else
  ::SymCleanup(process);
  return;
#endif
  frame.AddrPC.Mode = frame.AddrStack.Mode = frame.AddrFrame.Mode =
      AddrModeFlat;
  while (frames->size() < kMaxFrames &&
         ::StackWalk64(kMachine, process, thread, &frame, &context, nullptr,
                       ::SymFunctionTableAccess64, ::SymGetModuleBase64,
                       nullptr)) {
    if (frame.AddrPC.Offset == 0) break;
    frames->push_back(static_cast<ULONG_PTR>(frame.AddrPC.Offset));
  }
  ::SymCleanup(process);
}

std::string Timestamp() {
  SYSTEMTIME utc = {};
  ::GetSystemTime(&utc);
  char buffer[40];
  snprintf(buffer, sizeof(buffer), "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
           utc.wYear, utc.wMonth, utc.wDay, utc.wHour, utc.wMinute,
           utc.wSecond, utc.wMilliseconds);
  return buffer;
}

// אותו מבנה כמו crash_record.cpp, כדי שהחתימה והפענוח יהיו זהים.
std::string BuildRecord(const CrashWerContext& context,
                        const WER_RUNTIME_EXCEPTION_INFORMATION& info) {
  HANDLE process = info.hProcess;
  const EXCEPTION_RECORD& record = info.exceptionRecord;
  std::vector<ULONG_PTR> frames;
  Walk(process, info.hThread, info.context, &frames);

  char line[160];
  std::string report = "\n=== Native crash " + Timestamp() + " ===\n";
  if (context.version[0] != '\0') {
    report += std::string("Version: ") + context.version + "\n";
  }
  snprintf(line, sizeof(line), "Exception code: 0x%08lx\n",
           static_cast<unsigned long>(record.ExceptionCode));
  report += line;
  report += "Fault: " +
            Describe(process,
                     reinterpret_cast<ULONG_PTR>(record.ExceptionAddress)) +
            "\n";
  if (record.ExceptionCode == STATUS_STACK_BUFFER_OVERRUN &&
      record.NumberParameters >= 1) {
    snprintf(line, sizeof(line), "Fast fail code: %llu\n",
             static_cast<unsigned long long>(record.ExceptionInformation[0]));
    report += line;
  }
  report += ::GetThreadId(info.hThread) == context.main_thread_id
                ? "Thread: main\n"
                : "Thread: other\n";
  if (context.build_commit[0] != '\0') {
    report += std::string("Build commit: ") + context.build_commit + "\n";
  }

  const auto read = [process](ULONG_PTR address, void* out, size_t size) {
    return ReadRemote(process, address, out, size);
  };
  std::vector<ULONG_PTR> seen;
  bool dart_seen = false;
  std::string pdb_lines;
  for (const ULONG_PTR frame : frames) {
    const Module module = FindModule(process, frame);
    if (module.base == 0) continue;
    if (module.is_dart) {
      if (dart_seen) continue;
      dart_seen = true;
      const std::string id = image_identity::DartBuildId(read, module.base);
      if (!id.empty()) report += "Dart build-id: " + id + "\n";
      continue;
    }
    bool known = false;
    for (const ULONG_PTR base : seen) known |= base == module.base;
    if (known) continue;
    seen.push_back(module.base);
    const std::string key = image_identity::ModulePdbKey(read, module.base);
    if (!key.empty()) {
      pdb_lines += "Module PDB: " + module.name + " " + key + "\n";
    }
  }
  report += pdb_lines;

  if (frames.empty()) {
    report += "Stack: unavailable\n";
  } else {
    report += "Stack (module+RVA):\n";
    for (const ULONG_PTR frame : frames) {
      report += "  " + Describe(process, frame) + "\n";
    }
  }
  return report;
}

void Append(const wchar_t* path, const std::string& text) {
  HANDLE file = ::CreateFileW(path, FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  ::WriteFile(file, text.c_str(), static_cast<DWORD>(text.size()), &written,
              nullptr);
  ::CloseHandle(file);
}

}  // namespace

extern "C" {

BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID) { return TRUE; }

// לא תובע בעלות: WER ממשיך כרגיל (Event Viewer, Sentry) אחרי הרישום.
HRESULT OutOfProcessExceptionEventCallback(
    PVOID pContext, const PWER_RUNTIME_EXCEPTION_INFORMATION pExceptionInformation,
    BOOL* pbOwnershipClaimed, PWSTR, PDWORD, PDWORD) {
  *pbOwnershipClaimed = FALSE;
  const WER_RUNTIME_EXCEPTION_INFORMATION* info = pExceptionInformation;
  if (info == nullptr ||
      info->dwSize < offsetof(WER_RUNTIME_EXCEPTION_INFORMATION, bIsFatal) +
                         sizeof(BOOL) ||
      !info->bIsFatal) {
    return S_OK;
  }
  CrashWerContext context = {};
  if (!ReadRemote(info->hProcess, reinterpret_cast<ULONG_PTR>(pContext),
                  &context, sizeof(context)) ||
      context.magic != CrashWerContext::kMagic ||
      context.size != sizeof(context) || context.recorded != 0) {
    return S_OK;
  }
  context.log_path[ARRAYSIZE(context.log_path) - 1] = L'\0';
  context.version[sizeof(context.version) - 1] = '\0';
  context.build_commit[sizeof(context.build_commit) - 1] = '\0';
  if (context.log_path[0] == L'\0') return S_OK;
  Append(context.log_path, BuildRecord(context, *info));
  return S_OK;
}

HRESULT OutOfProcessExceptionEventSignatureCallback(
    PVOID, const PWER_RUNTIME_EXCEPTION_INFORMATION, DWORD, PWSTR, PDWORD,
    PWSTR, PDWORD) {
  return E_FAIL;
}

HRESULT OutOfProcessExceptionEventDebuggerLaunchCallback(
    PVOID, const PWER_RUNTIME_EXCEPTION_INFORMATION, PBOOL, PWSTR, PDWORD,
    PBOOL) {
  return E_FAIL;
}

}  // extern "C"
