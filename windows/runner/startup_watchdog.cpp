#include "startup_watchdog.h"

#include <windows.h>

#include <psapi.h>
#include <shlobj.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <initializer_list>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace startup_watchdog {

namespace {

// סף התקיעה, המרווח בין צילומים ומספרם המרבי — הדוח נועד לאבחון עלייה,
// לא לניטור רציף.
constexpr DWORD kStallThresholdMs = 3000;
constexpr DWORD kCaptureIntervalMs = 5000;
constexpr int kMaxCaptures = 6;
constexpr DWORD kHeartbeatIntervalMs = 250;
constexpr ULONGLONG kMaxLifetimeMs = 300000;
// מגבלת הפרישה. בדוח נכתבים רק הראש, שממנו נגזרת החתימה (error_log_blocks.dart),
// והתחתית, שבה מי שהתחיל את העבודה.
constexpr size_t kMaxFrames = 8192;
constexpr size_t kTopFrames = 48;
constexpr size_t kBottomFrames = 32;
// כל מחסנית ה-thread הראשי (1MB, ברירת המחדל של ה-linker); מועתק רק החלק שבשימוש.
constexpr size_t kMaxStackCopyBytes = 1024 * 1024;
// אפסים אחרי העותק: פרישת המסגרת האחרונה קוראת מעבר לקצהו.
constexpr size_t kStackCopyPaddingBytes = 64 * 1024;

struct ModuleRange {
  ULONG_PTR base = 0;
  ULONG_PTR size = 0;
  std::string name;
};

std::atomic<ULONGLONG> g_last_beat{0};
std::atomic<bool> g_stop{false};
std::atomic<bool> g_started{false};
HANDLE g_main_thread = nullptr;
UINT_PTR g_timer = 0;
ULONGLONG g_start_tick = 0;
std::thread g_watcher;

using ModuleSnapshot = std::vector<ModuleRange>;
std::shared_ptr<const ModuleSnapshot> g_modules =
    std::make_shared<const ModuleSnapshot>();

void CALLBACK HeartbeatProc(HWND, UINT, UINT_PTR, DWORD) {
  const ULONGLONG now = ::GetTickCount64();
  g_last_beat.store(now, std::memory_order_relaxed);
  if (now - g_start_tick > kMaxLifetimeMs) return RequestStop();
}

std::string NarrowPathTail(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  const std::wstring tail =
      slash == std::wstring::npos ? path : path.substr(slash + 1);
  const int len = ::WideCharToMultiByte(CP_UTF8, 0, tail.c_str(), -1, nullptr,
                                        0, nullptr, nullptr);
  if (len <= 1) return std::string();
  std::string out(static_cast<size_t>(len), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, tail.c_str(), -1, &out[0], len, nullptr,
                        nullptr);
  out.resize(static_cast<size_t>(len - 1));
  return out;
}

std::shared_ptr<const ModuleSnapshot> BuildModuleSnapshot() {
  HMODULE handles[512];
  DWORD needed = 0;
  if (!::EnumProcessModules(::GetCurrentProcess(), handles, sizeof(handles),
                            &needed)) {
    return nullptr;
  }
  const size_t count =
      (std::min)(static_cast<size_t>(needed / sizeof(HMODULE)),
                 sizeof(handles) / sizeof(handles[0]));
  auto fresh = std::make_shared<ModuleSnapshot>();
  fresh->reserve(count);
  for (size_t i = 0; i < count; ++i) {
    MODULEINFO info = {};
    if (!::GetModuleInformation(::GetCurrentProcess(), handles[i], &info,
                                sizeof(info))) {
      continue;
    }
    wchar_t path[MAX_PATH] = {0};
    if (::GetModuleFileNameW(handles[i], path, MAX_PATH) == 0) continue;
    ModuleRange range;
    range.base = reinterpret_cast<ULONG_PTR>(info.lpBaseOfDll);
    range.size = info.SizeOfImage;
    range.name = NarrowPathTail(path);
    fresh->push_back(std::move(range));
  }
  return fresh;
}

bool ReadBytes(ULONG_PTR address, void* out, size_t size) {
  __try {
    memcpy(out, reinterpret_cast<const void*>(address), size);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// ה-loader של Dart טוען את app.so ל-VirtualAlloc אחד בלי מודול, וכותרת ה-ELF
// בבסיסו; ההיסט ממנו הוא הכתובת הווירטואלית שבקובץ הסמלים.
ULONG_PTR DartImageBase(ULONG_PTR address) {
  MEMORY_BASIC_INFORMATION info = {};
  if (::VirtualQuery(reinterpret_cast<LPCVOID>(address), &info,
                     sizeof(info)) == 0 ||
      info.Type != MEM_PRIVATE ||
      (info.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ)) == 0) {
    return 0;
  }
  const auto base = reinterpret_cast<ULONG_PTR>(info.AllocationBase);
  unsigned char magic[4] = {};
  if (!ReadBytes(base, magic, sizeof(magic))) return 0;
  return memcmp(magic, "\x7f" "ELF", sizeof(magic)) == 0 ? base : 0;
}

// ה-build-id מ-PT_NOTE של ה-ELF (64 ביט) — מזהה את קובץ הסמלים התואם.
std::string DartBuildId(ULONG_PTR base) {
  unsigned char header[64] = {};
  if (!ReadBytes(base, header, sizeof(header)) || header[4] != 2) return "";
  uint64_t phoff = 0;
  uint16_t phentsize = 0, phnum = 0;
  memcpy(&phoff, header + 0x20, sizeof(phoff));
  memcpy(&phentsize, header + 0x36, sizeof(phentsize));
  memcpy(&phnum, header + 0x38, sizeof(phnum));
  if (phentsize < 0x30 || phnum > 64) return "";
  for (uint16_t i = 0; i < phnum; ++i) {
    unsigned char ph[0x30] = {};
    if (!ReadBytes(base + phoff + i * phentsize, ph, sizeof(ph))) return "";
    uint32_t type = 0;
    uint64_t vaddr = 0, size = 0;
    memcpy(&type, ph, sizeof(type));
    memcpy(&vaddr, ph + 0x10, sizeof(vaddr));
    memcpy(&size, ph + 0x28, sizeof(size));
    if (type != 4 /* PT_NOTE */) continue;
    for (uint64_t at = 0; at + 12 <= size;) {
      uint32_t note[3] = {};  // namesz, descsz, type
      if (!ReadBytes(base + vaddr + at, note, sizeof(note))) return "";
      const uint64_t name_size = (note[0] + 3) & ~3u;
      const uint64_t desc_size = (note[1] + 3) & ~3u;
      char name[4] = {};
      if (note[2] == 3 /* NT_GNU_BUILD_ID */ && note[0] == 4 && note[1] <= 64 &&
          ReadBytes(base + vaddr + at + 12, name, sizeof(name)) &&
          memcmp(name, "GNU", 4) == 0) {
        unsigned char id[64] = {};
        if (!ReadBytes(base + vaddr + at + 12 + name_size, id, note[1])) {
          return "";
        }
        std::string hex;
        char byte[3];
        for (uint32_t b = 0; b < note[1]; ++b) {
          snprintf(byte, sizeof(byte), "%02x", id[b]);
          hex += byte;
        }
        return hex;
      }
      at += 12 + name_size + desc_size;
    }
  }
  return "";
}

// "<pdb> <GUID><age>" מרשומת CodeView RSDS — המפתח בשרת הסמלים של Microsoft,
// שבלעדיו אין PDB לפריים ב-DLL של המערכת.
std::string ModulePdbKey(HMODULE module) {
  const auto base = reinterpret_cast<ULONG_PTR>(module);
  IMAGE_DOS_HEADER dos = {};
  if (!ReadBytes(base, &dos, sizeof(dos)) || dos.e_magic != IMAGE_DOS_SIGNATURE ||
      dos.e_lfanew <= 0 || dos.e_lfanew > 0x10000) {
    return "";
  }
  IMAGE_NT_HEADERS nt = {};
  if (!ReadBytes(base + dos.e_lfanew, &nt, sizeof(nt)) ||
      nt.Signature != IMAGE_NT_SIGNATURE ||
      nt.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR_MAGIC ||
      nt.OptionalHeader.NumberOfRvaAndSizes <= IMAGE_DIRECTORY_ENTRY_DEBUG) {
    return "";
  }
  const DWORD image_size = nt.OptionalHeader.SizeOfImage;
  const IMAGE_DATA_DIRECTORY dir =
      nt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG];
  if (dir.VirtualAddress == 0 || dir.VirtualAddress >= image_size ||
      dir.Size > image_size - dir.VirtualAddress) {
    return "";
  }
  const DWORD count = (std::min)(
      static_cast<DWORD>(dir.Size / sizeof(IMAGE_DEBUG_DIRECTORY)), DWORD{32});
  for (DWORD i = 0; i < count; ++i) {
    IMAGE_DEBUG_DIRECTORY entry = {};
    if (!ReadBytes(base + dir.VirtualAddress + i * sizeof(entry), &entry,
                   sizeof(entry))) {
      return "";
    }
    if (entry.Type != IMAGE_DEBUG_TYPE_CODEVIEW || entry.AddressOfRawData == 0 ||
        entry.SizeOfData < 25 || entry.SizeOfData > 1024 ||
        entry.AddressOfRawData >= image_size ||
        entry.SizeOfData > image_size - entry.AddressOfRawData) {
      continue;
    }
    // RSDS: חתימה, GUID, age, ונתיב ה-PDB מסתיים ב-0.
    unsigned char data[1024] = {};
    if (!ReadBytes(base + entry.AddressOfRawData, data, entry.SizeOfData) ||
        memcmp(data, "RSDS", 4) != 0) {
      continue;
    }
    GUID guid = {};
    DWORD age = 0;
    memcpy(&guid, data + 4, sizeof(guid));
    memcpy(&age, data + 20, sizeof(age));
    const char* path = reinterpret_cast<const char*>(data + 24);
    const size_t path_len = strnlen(path, entry.SizeOfData - 24);
    if (path_len == 0 || path_len == entry.SizeOfData - 24) continue;
    std::string pdb(path, path_len);
    const size_t slash = pdb.find_last_of("\\/");
    if (slash != std::string::npos) pdb = pdb.substr(slash + 1);
    if (pdb.empty() || pdb.find(' ') != std::string::npos) continue;
    char key[64];
    snprintf(key, sizeof(key),
             "%08lX%04X%04X%02X%02X%02X%02X%02X%02X%02X%02X%lX", guid.Data1,
             guid.Data2, guid.Data3, guid.Data4[0], guid.Data4[1],
             guid.Data4[2], guid.Data4[3], guid.Data4[4], guid.Data4[5],
             guid.Data4[6], guid.Data4[7], age);
    return pdb + " " + key;
  }
  return "";
}

// שורת "Module PDB:" לכל מודול PE שמופיע בפריימים; app.so אינו PE.
void AppendModulePdbLines(const std::vector<ULONG_PTR>& frames,
                          std::string* report) {
  std::vector<HMODULE> seen;
  for (const ULONG_PTR frame : frames) {
    if (DartImageBase(frame) != 0) continue;
    HMODULE module = nullptr;
    if (!::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                  GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                              reinterpret_cast<LPCWSTR>(frame), &module) ||
        std::find(seen.begin(), seen.end(), module) != seen.end()) {
      continue;
    }
    seen.push_back(module);
    const std::string key = ModulePdbKey(module);
    if (key.empty()) continue;
    wchar_t path[MAX_PATH] = {0};
    const DWORD length = ::GetModuleFileNameW(module, path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) continue;
    *report += "Module PDB: " + NarrowPathTail(path) + " " + key + "\n";
  }
}

std::string DescribeAddress(ULONG_PTR address) {
  char buffer[160];
  const auto modules =
      std::atomic_load_explicit(&g_modules, std::memory_order_acquire);
  for (const ModuleRange& range : *modules) {
    if (address >= range.base && address < range.base + range.size) {
      snprintf(buffer, sizeof(buffer), "%s+0x%llx", range.name.c_str(),
               static_cast<unsigned long long>(address - range.base));
      return buffer;
    }
  }
  const ULONG_PTR dart_base = DartImageBase(address);
  if (dart_base != 0) {
    snprintf(buffer, sizeof(buffer), "app.so+0x%llx",
             static_cast<unsigned long long>(address - dart_base));
    return buffer;
  }
  // מיפוי לפי כתובת מזהה DLL מאוחר בלי לגשת לרשימת ה-loader.
  // נקרא רק בעת דיווח, אחרי חידוש ה-thread הראשי.
  MEMORY_BASIC_INFORMATION info = {};
  if (::VirtualQuery(reinterpret_cast<LPCVOID>(address), &info, sizeof(info)) != 0 &&
      info.Type == MEM_IMAGE) {
    wchar_t path[MAX_PATH] = {0};
    const DWORD length = ::GetMappedFileNameW(
        ::GetCurrentProcess(), reinterpret_cast<LPVOID>(address), path, MAX_PATH);
    if (length > 0 && length < MAX_PATH) {
      const std::string name = NarrowPathTail(path);
      if (!name.empty()) {
        snprintf(buffer, sizeof(buffer), "%s+0x%llx", name.c_str(),
                 static_cast<unsigned long long>(
                     address - reinterpret_cast<ULONG_PTR>(info.AllocationBase)));
        return buffer;
      }
    }
  }
  snprintf(buffer, sizeof(buffer), "0x%llx",
           static_cast<unsigned long long>(address));
  return buffer;
}

#if defined(_M_X64) || defined(_M_ARM64)

#if defined(_M_X64)
#define WD_PC(ctx) ((ctx).Rip)
#define WD_SP(ctx) ((ctx).Rsp)
#else
#define WD_PC(ctx) ((ctx).Pc)
#define WD_SP(ctx) ((ctx).Sp)
#endif

// קריאת מילה מהמחסנית שהועתקה — כתובת פגומה תפיל את התהליך בלי זה.
bool ReadStackWord(ULONG_PTR address, ULONG_PTR* out) {
  __try {
    *out = *reinterpret_cast<ULONG_PTR*>(address);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// עותק שנחתך או מודול שנפרק אחרי החידוש מסתיימים במחסנית קטועה, לא בקריסה.
bool UnwindFrame(CONTEXT* context, bool* has_function) {
  __try {
    DWORD64 image_base = 0;
    PRUNTIME_FUNCTION function =
        ::RtlLookupFunctionEntry(WD_PC(*context), &image_base, nullptr);
    *has_function = function != nullptr;
    if (function == nullptr) return true;
    PVOID handler_data = nullptr;
    DWORD64 establisher_frame = 0;
    ::RtlVirtualUnwind(UNW_FLAG_NHANDLER, image_base, WD_PC(*context), function,
                       context, &handler_data, &establisher_frame, nullptr);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// פורשת מחסנית שהועתקה; RtlLookupFunctionEntry נוטלת נעילות של ה-loader, ולכן
// רצה רק אחרי שה-thread חודש.
void UnwindCopiedStack(CONTEXT* context, ULONG_PTR stack_begin,
                       ULONG_PTR stack_end, std::vector<ULONG_PTR>* frames) {
  while (frames->size() < kMaxFrames) {
    const ULONG_PTR pc = static_cast<ULONG_PTR>(WD_PC(*context));
    if (pc == 0) break;
    frames->push_back(pc);
    const ULONG_PTR sp = static_cast<ULONG_PTR>(WD_SP(*context));
    if (sp < stack_begin || sp >= stack_end) break;

    bool has_function = false;
    if (!UnwindFrame(context, &has_function)) break;
    if (!has_function) {
#if defined(_M_X64)
      ULONG_PTR return_address = 0;
      if (!ReadStackWord(static_cast<ULONG_PTR>(WD_SP(*context)),
                         &return_address)) {
        break;
      }
      WD_PC(*context) = return_address;
      WD_SP(*context) += sizeof(ULONG_PTR);
#else
      if (context->Lr == 0 || context->Lr == WD_PC(*context)) break;
      WD_PC(*context) = context->Lr;
#endif
      continue;
    }
    if (WD_PC(*context) == 0) break;
  }
}

bool CopyStackBytes(ULONG_PTR from, void* to, size_t size) {
  __try {
    memcpy(to, reinterpret_cast<const void*>(from), size);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

// מצביע לתוך המחסנית המקורית מצביע אחרי הפרישה לתוך העותק.
void Relocate(ULONG_PTR* value, ULONG_PTR from, size_t size, ULONG_PTR to) {
  if (*value >= from && *value - from < size) *value = *value - from + to;
}

// בזמן ההשהיה רק syscalls ו-memcpy: thread מושהה שמחזיק נעילה שה-watcher
// צריך היה נשאר מושהה לתמיד.
bool CaptureSuspendedStack(HANDLE thread, std::vector<ULONG_PTR>* frames) {
  if (thread == nullptr) return false;
  std::vector<ULONG_PTR> copy(
      (kMaxStackCopyBytes + kStackCopyPaddingBytes) / sizeof(ULONG_PTR));
  if (::SuspendThread(thread) == static_cast<DWORD>(-1)) return false;

  CONTEXT context = {};
  context.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
  const bool got_context = ::GetThreadContext(thread, &context) != FALSE;
  const ULONG_PTR sp = static_cast<ULONG_PTR>(WD_SP(context));
  size_t copied = 0;
  MEMORY_BASIC_INFORMATION info = {};
  if (got_context &&
      ::VirtualQuery(reinterpret_cast<LPCVOID>(sp), &info, sizeof(info)) != 0 &&
      info.State == MEM_COMMIT) {
    const ULONG_PTR end =
        reinterpret_cast<ULONG_PTR>(info.BaseAddress) + info.RegionSize;
    copied = (std::min)(static_cast<size_t>(end - sp), kMaxStackCopyBytes) &
             ~(sizeof(ULONG_PTR) - 1);
    if (!CopyStackBytes(sp, copy.data(), copied)) copied = 0;
  }
  ::ResumeThread(thread);
  if (!got_context) return false;
  if (copied == 0) {
    frames->push_back(static_cast<ULONG_PTR>(WD_PC(context)));
    return true;
  }

  const ULONG_PTR to = reinterpret_cast<ULONG_PTR>(copy.data());
  for (size_t i = 0; i < copied / sizeof(ULONG_PTR); ++i) {
    Relocate(&copy[i], sp, copied, to);
  }
#if defined(_M_X64)
  for (DWORD64* reg : {&context.Rbp, &context.Rbx, &context.Rsi, &context.Rdi,
                       &context.R12, &context.R13, &context.R14,
                       &context.R15}) {
    Relocate(reinterpret_cast<ULONG_PTR*>(reg), sp, copied, to);
  }
#else
  for (int i = 19; i <= 28; ++i) {
    Relocate(reinterpret_cast<ULONG_PTR*>(&context.X[i]), sp, copied, to);
  }
  Relocate(reinterpret_cast<ULONG_PTR*>(&context.Fp), sp, copied, to);
#endif
  WD_SP(context) = to;
  UnwindCopiedStack(&context, to, to + copied, frames);
  return true;
}

#else  // ארכיטקטורה בלי פרישת מחסנית מבוססת-טבלאות (x86)

bool CaptureSuspendedStack(HANDLE, std::vector<ULONG_PTR>*) { return false; }

#endif

bool CaptureMainThreadStack(std::vector<ULONG_PTR>* frames) {
  return CaptureSuspendedStack(g_main_thread, frames);
}

std::wstring ResolveLogPath() {
  wchar_t exe_path[MAX_PATH] = {0};
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) != 0) {
    std::wstring dir(exe_path);
    const size_t slash = dir.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
      dir = dir.substr(0, slash);
      // חייב לשקף את AppPaths.isPortable, אחרת הדוח נכתב לקובץ שהמשתמש הנייד
      // אינו רואה.
      if (::GetFileAttributesW((dir + L"\\portable.marker").c_str()) !=
          INVALID_FILE_ATTRIBUTES) {
        return dir + L"\\otzaria_data\\logs\\errors.txt";
      }
    }
  }

  wchar_t* app_data_raw = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_DEFAULT,
                                    nullptr, &app_data_raw))) {
    return std::wstring();
  }
  std::wstring app_data(app_data_raw);
  ::CoTaskMemFree(app_data_raw);
  return app_data + L"\\otzaria\\logs\\errors.txt";
}

void CreateParentDirectories(const std::wstring& path) {
  const size_t slash = path.find_last_of(L'\\');
  if (slash == std::wstring::npos) return;
  const std::wstring dir = path.substr(0, slash);
  const size_t parent = dir.find_last_of(L'\\');
  if (parent != std::wstring::npos) {
    ::CreateDirectoryW(dir.substr(0, parent).c_str(), nullptr);
  }
  ::CreateDirectoryW(dir.c_str(), nullptr);
}

void AppendToLog(const std::string& text) {
  const std::wstring path = ResolveLogPath();
  if (path.empty()) return;
  CreateParentDirectories(path);
  HANDLE file = ::CreateFileW(path.c_str(), FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  ::WriteFile(file, text.c_str(), static_cast<DWORD>(text.size()), &written,
              nullptr);
  ::CloseHandle(file);
}

std::string Timestamp() {
  SYSTEMTIME utc = {};
  ::GetSystemTime(&utc);
  char buffer[32];
  snprintf(buffer, sizeof(buffer), "%04u-%02u-%02uT%02u:%02u:%02uZ", utc.wYear,
           utc.wMonth, utc.wDay, utc.wHour, utc.wMinute, utc.wSecond);
  return buffer;
}

// התרגום לשמות מודולים נעשה רק כאן, אחרי שה-thread הראשי חודש.
void AppendStackSection(const std::vector<ULONG_PTR>& frames,
                        std::string* report) {
  if (frames.empty()) {
    *report += "Stack: unavailable\n";
    return;
  }
  *report += "Stack (module+RVA):\n";
  const size_t count = frames.size();
  const size_t omitted = count > kTopFrames + kBottomFrames
                             ? count - kTopFrames - kBottomFrames
                             : 0;
  for (size_t i = 0; i < count; ++i) {
    if (omitted != 0 && i == kTopFrames) {
      char marker[96];
      snprintf(marker, sizeof(marker), "  ... (%zu frames omitted%s) ...\n",
               omitted, count >= kMaxFrames ? ", unwind limit reached" : "");
      *report += marker;
      i += omitted;
    }
    const ULONG_PTR frame = frames[i];
    *report += "  " + DescribeAddress(frame) + "\n";
  }
}

// לפני שורת Stack: הפרסר של הלוג קורא כפריימים את כל מה שאחריה.
void AppendBuildIdentitySection(const std::vector<ULONG_PTR>& frames,
                                std::string* report) {
#ifdef OTZARIA_BUILD_COMMIT
  *report += std::string("Build commit: ") + OTZARIA_BUILD_COMMIT + "\n";
#endif
  for (const ULONG_PTR frame : frames) {
    const ULONG_PTR base = DartImageBase(frame);
    if (base == 0) continue;
    const std::string build_id = DartBuildId(base);
    if (!build_id.empty()) *report += "Dart build-id: " + build_id + "\n";
    break;
  }
  AppendModulePdbLines(frames, report);
}

void ReportStall(int capture_index, ULONGLONG stalled_for_ms,
                 ULONGLONG since_launch_ms,
                 const std::vector<ULONG_PTR>& frames) {
  std::string report =
      "\n=== Startup heartbeat delay " + Timestamp() + " ===\n";
#ifdef FLUTTER_VERSION
  report += std::string("Version: ") + FLUTTER_VERSION + "\n";
#endif
  char header[192];
  snprintf(header, sizeof(header),
           "Message-loop timer delayed for %llums, at %llums after launch "
           "(the thread may be blocked or WM_TIMER starved) "
           "(capture %d/%d)\n",
           static_cast<unsigned long long>(stalled_for_ms),
           static_cast<unsigned long long>(since_launch_ms), capture_index,
           kMaxCaptures);
  report += header;
  AppendBuildIdentitySection(frames, &report);
  AppendStackSection(frames, &report);
  AppendToLog(report);
}

void WatcherLoop() {
  int captures = 0;
  ULONGLONG last_capture = 0;

  while (!g_stop.load(std::memory_order_relaxed)) {
    ::Sleep(kHeartbeatIntervalMs);
    const ULONGLONG now = ::GetTickCount64();
    if (now - g_start_tick > kMaxLifetimeMs) return;

    const ULONGLONG beat = g_last_beat.load(std::memory_order_relaxed);
    const ULONGLONG gap = now > beat ? now - beat : 0;

    if (gap < kStallThresholdMs) continue;

    if (captures >= kMaxCaptures) continue;
    if (last_capture != 0 && now - last_capture < kCaptureIntervalMs) continue;

    std::vector<ULONG_PTR> frames;
    CaptureMainThreadStack(&frames);
    last_capture = now;
    ++captures;
    ReportStall(captures, gap, now - g_start_tick, frames);
  }
}

}  // namespace

bool CaptureMainStack(std::vector<ULONG_PTR>* frames) {
  return CaptureMainThreadStack(frames);
}

bool CaptureThreadStack(HANDLE thread, std::vector<ULONG_PTR>* frames) {
  return CaptureSuspendedStack(thread, frames);
}

bool IsDartFrame(ULONG_PTR address) { return DartImageBase(address) != 0; }

void AppendStack(const std::vector<ULONG_PTR>& frames, std::string* report) {
  AppendStackSection(frames, report);
}

void AppendBuildIdentity(const std::vector<ULONG_PTR>& frames,
                         std::string* report) {
  AppendBuildIdentitySection(frames, report);
}

void AppendReport(const std::string& text) { AppendToLog(text); }

std::string UtcTimestamp() { return Timestamp(); }

void Start() {
  if (g_started.exchange(true)) return;
  g_stop.store(false, std::memory_order_relaxed);
  g_start_tick = ::GetTickCount64();
  g_last_beat.store(g_start_tick, std::memory_order_relaxed);

  if (!::DuplicateHandle(::GetCurrentProcess(), ::GetCurrentThread(),
                         ::GetCurrentProcess(), &g_main_thread,
                         THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT |
                             THREAD_QUERY_INFORMATION,
                         FALSE, 0)) {
    g_main_thread = nullptr;
  }

  RefreshModules();
  g_timer = ::SetTimer(nullptr, 0, kHeartbeatIntervalMs, HeartbeatProc);
  if (g_timer == 0) {
    if (g_main_thread != nullptr) {
      ::CloseHandle(g_main_thread);
      g_main_thread = nullptr;
    }
    g_started.store(false, std::memory_order_relaxed);
    return;
  }
  g_watcher = std::thread(WatcherLoop);
}

void RefreshModules() {
  const auto fresh = BuildModuleSnapshot();
  if (fresh != nullptr) {
    std::atomic_store_explicit(&g_modules, fresh, std::memory_order_release);
  }
}

void RequestStop() {
  g_stop.store(true, std::memory_order_relaxed);
  if (g_timer != 0) {
    ::KillTimer(nullptr, g_timer);
    g_timer = 0;
  }
}

void Stop() {
  RequestStop();
  if (g_watcher.joinable()) g_watcher.join();
  if (g_main_thread != nullptr) {
    ::CloseHandle(g_main_thread);
    g_main_thread = nullptr;
  }
  g_started.store(false, std::memory_order_relaxed);
}

}  // namespace startup_watchdog
