#ifndef RUNNER_CRASH_WER_CONTEXT_H_
#define RUNNER_CRASH_WER_CONTEXT_H_

#include <windows.h>

// זיכרון בתהליך האפליקציה שמודול ה-WER קורא ב-ReadProcessMemory בזמן קריסה.
struct CrashWerContext {
  static constexpr DWORD kMagic = 0x4f545a57;  // "OTZW"

  DWORD magic;
  DWORD size;
  DWORD main_thread_id;
  // המטפל בתהליך כבר כתב רשומה — המודול לא כותב שנייה.
  volatile LONG recorded;
  wchar_t log_path[1024];
  char version[64];
  char build_commit[64];
};

// שם ה-DLL ליד otzaria.exe.
#define OTZARIA_CRASH_WER_DLL L"otzaria_crash_wer.dll"

#endif  // RUNNER_CRASH_WER_CONTEXT_H_
