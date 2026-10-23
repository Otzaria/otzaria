#include "hang_monitor.h"

#include <cstdio>
#include <string>
#include <thread>
#include <vector>

#include "startup_watchdog.h"

namespace hang_monitor {

namespace {

// IsHungAppWindow מחזיר true אחרי 5 שניות שה-thread לא שלף הודעות. בלי
// WM_TIMER: הצפת הודעות מרעיבה אותו ומייצרת התראות שווא.
constexpr DWORD kPollIntervalMs = 1000;
constexpr ULONGLONG kHungThresholdMs = 5000;
constexpr int kRequiredHungPolls = 2;
constexpr ULONGLONG kSleepGapMs = 2000;
constexpr ULONGLONG kResumeGraceMs = 10000;
constexpr int kMaxReports = 5;
constexpr int kMaxFrames = 48;
// דגימה אחת לא מבדילה בין לולאה ארוכה אחת לבין עבודה שמתחלפת.
constexpr int kMaxExtraSamples = 3;
constexpr ULONGLONG kSampleIntervalMs = 2000;

HWND g_window = nullptr;
HANDLE g_stop_event = nullptr;
std::thread g_watcher;

// זמן ערות בלבד: בניגוד ל-GetTickCount64 אינו מתקדם בשינה של המערכת.
ULONGLONG AwakeMs() {
  ULONGLONG units = 0;
  ::QueryUnbiasedInterruptTime(&units);
  return units / 10000;
}

ULONGLONG MsSinceLaunch() {
  FILETIME created = {}, exited = {}, kernel = {}, user = {};
  if (!::GetProcessTimes(::GetCurrentProcess(), &created, &exited, &kernel,
                         &user)) {
    return 0;
  }
  FILETIME now = {};
  ::GetSystemTimeAsFileTime(&now);
  const ULONGLONG start =
      (static_cast<ULONGLONG>(created.dwHighDateTime) << 32) |
      created.dwLowDateTime;
  const ULONGLONG current =
      (static_cast<ULONGLONG>(now.dwHighDateTime) << 32) | now.dwLowDateTime;
  return current > start ? (current - start) / 10000 : 0;
}

void ReportHang(const std::vector<ULONG_PTR>& frames) {
  std::string report =
      "\n=== App hang " + startup_watchdog::UtcTimestamp() + " ===\n";
#ifdef FLUTTER_VERSION
  report += std::string("Version: ") + FLUTTER_VERSION + "\n";
#endif
  // בלי מספרים בשורה: ממנה נגזר סוג החתימה (AppHang).
  report += "Message: AppHang: UI thread not responding\n";
  char detected[64];
  snprintf(detected, sizeof(detected), "Detected: %llums after launch\n",
           MsSinceLaunch());
  report += detected;
  startup_watchdog::AppendBuildIdentity(frames, &report);
  startup_watchdog::AppendStack(frames, &report);
  startup_watchdog::AppendReport(report);
}

// בתוך רשומת התקיעה, אחרי שורת `---`: הפרסר מחשב את החתימה מהדגימה הראשונה.
void ReportSample(int index, ULONGLONG into_hang_ms,
                  const std::vector<ULONG_PTR>& frames) {
  char header[96];
  snprintf(header, sizeof(header), "--- Sample %d, %llums into the hang ---\n",
           index, into_hang_ms);
  std::string report = header;
  startup_watchdog::AppendStack(frames, &report);
  startup_watchdog::AppendReport(report);
}

std::vector<ULONG_PTR> CaptureFrames() {
  // הקצאה מראש: הקצאה בזמן שה-thread הראשי מושהה עלולה להיתקע על נעילת ה-heap.
  std::vector<ULONG_PTR> frames;
  frames.reserve(kMaxFrames);
  startup_watchdog::CaptureMainStack(&frames);
  return frames;
}

void ReportRecovered(ULONGLONG duration_ms) {
  char text[96];
  snprintf(text, sizeof(text), "Duration: %llums\n", duration_ms);
  startup_watchdog::AppendReport("\n=== App hang recovered " +
                                 startup_watchdog::UtcTimestamp() + " ===\n" +
                                 text);
}

void WatcherLoop() {
  ULONGLONG last_tick = ::GetTickCount64();
  ULONGLONG last_awake = AwakeMs();
  ULONGLONG grace_until = 0;
  ULONGLONG first_hung_at = 0;
  ULONGLONG hang_started_at = 0;
  ULONGLONG last_sample_at = 0;
  int hung_polls = 0;
  int reports = 0;
  int samples = 0;
  bool in_hang = false;

  while (::WaitForSingleObject(g_stop_event, kPollIntervalMs) == WAIT_TIMEOUT) {
    if (!::IsWindow(g_window)) return;
    const ULONGLONG tick = ::GetTickCount64();
    const ULONGLONG awake = AwakeMs();
    // פער בין השעונים = המערכת ישנה; אחרי חזרה החלון "תקוע" עד שישלוף הודעות.
    const ULONGLONG tick_delta = tick - last_tick;
    const ULONGLONG awake_delta = awake - last_awake;
    last_tick = tick;
    last_awake = awake;
    if (tick_delta > awake_delta + kSleepGapMs) {
      grace_until = awake + kResumeGraceMs;
    }

    const bool hung = ::IsHungAppWindow(g_window) != FALSE;
    if (in_hang) {
      if (hung) {
        if (samples < kMaxExtraSamples &&
            awake - last_sample_at >= kSampleIntervalMs) {
          last_sample_at = awake;
          ReportSample(++samples, awake - hang_started_at, CaptureFrames());
        }
        continue;
      }
      in_hang = false;
      const ULONGLONG duration = awake - hang_started_at;
      ReportRecovered(duration);
      ::PostMessageW(g_window, kMsgAppHangRecovered, 0,
                     static_cast<LPARAM>(duration));
      continue;
    }

    if (!hung || ::IsDebuggerPresent() || awake < grace_until) {
      hung_polls = 0;
      continue;
    }
    if (++hung_polls == 1) first_hung_at = awake;
    if (hung_polls < kRequiredHungPolls || reports >= kMaxReports) continue;

    hung_polls = 0;
    ++reports;
    in_hang = true;
    hang_started_at = first_hung_at - kHungThresholdMs;
    last_sample_at = awake;
    samples = 0;
    ReportHang(CaptureFrames());
  }
}

}  // namespace

void SetMainWindow(HWND window) { g_window = window; }

void Start() {
  if (g_window == nullptr || g_watcher.joinable()) return;
  g_stop_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_stop_event == nullptr) return;
  g_watcher = std::thread(WatcherLoop);
}

void Stop() {
  if (g_stop_event != nullptr) ::SetEvent(g_stop_event);
  if (g_watcher.joinable()) g_watcher.join();
  if (g_stop_event != nullptr) {
    ::CloseHandle(g_stop_event);
    g_stop_event = nullptr;
  }
}

}  // namespace hang_monitor
