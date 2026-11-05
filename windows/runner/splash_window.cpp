#include "splash_window.h"

#include <windows.h>
#include <wincodec.h>  // WIC — פענוח PNG

#include <limits>
#include <string>

#include "resource.h"
#include "../../native/splash/splash_timeline.h"

#pragma comment(lib, "windowscodecs.lib")

#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

namespace {

namespace tl = splash_timeline;

const wchar_t* kSplashClassName = L"OtzariaSplashWindow";

// הסמל הסטטי (הפחתת תנועה, או גיבוי) בפיקסלים לוגיים.
constexpr int kIconLogicalSize = 160;
// פריים האנימציה: בגודל הזה הספר הפתוח בפריים האחרון זהה בגודלו לסמל הסטטי.
constexpr int kFrameLogicalSize = 177;
constexpr double kFadeIntervalMs = 15.0;
constexpr double kForever = std::numeric_limits<double>::infinity();

struct StripResource {
  int side;
  int id;
};
// רצועה אנכית לכל דלי DPI (native/splash, משותף ל-Linux).
// נבחרת הקטנה שמכסה את הגודל.
constexpr StripResource kStrips[] = {
    {177, IDR_SPLASH_BOOK_100},
    {266, IDR_SPLASH_BOOK_150},
    {354, IDR_SPLASH_BOOK_200},
};

// g_splash_hwnd נכתב ע"י ה-thread *לפני* SetEvent(g_created_event) ונקרא ע"י
// Close רק *אחרי* שה-WaitForSingleObject ב-Show חזר — האירוע מספק happens-before.
HWND g_splash_hwnd = nullptr;
HANDLE g_splash_thread = nullptr;
HANDLE g_created_event = nullptr;  // ה-thread מאותת עליו אחרי יצירת החלון
HANDLE g_close_event = nullptr;    // Close מסמן עליו → fade-out

// נקבעים ב-Show לפני יצירת ה-thread.
bool g_animate = false;
UINT g_dpi = 96;

// משאבי הציור (בבעלות ה-thread של ה-splash).
HDC g_mem_dc = nullptr;
HBITMAP g_dib = nullptr;
HGDIOBJ g_old_bmp = nullptr;
BYTE* g_bits = nullptr;  // זיכרון ה-DIB: כל הפריימים זה מתחת לזה
int g_disp = 0;
POINT g_pos = {0, 0};

double NowMs() {
  static const double ticks_per_ms = [] {
    LARGE_INTEGER freq;
    QueryPerformanceFrequency(&freq);
    return freq.QuadPart / 1000.0;
  }();
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  return now.QuadPart / ticks_per_ms;
}

// מפענח פריים אחר פריים מרצועה אנכית ישר לזיכרון ה-DIB. PNG מפוענח בסדר
// השורות, ולכן כל פס עולה רק את חלקו — לא את פענוח הרצועה כולה.
class FrameDecoder {
 public:
  ~FrameDecoder() { Release(); }

  bool OpenFile(IWICImagingFactory* factory, const std::wstring& path,
                int disp) {
    IWICBitmapDecoder* decoder = nullptr;
    if (FAILED(factory->CreateDecoderFromFilename(
            path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand,
            &decoder))) {
      return false;
    }
    return Init(factory, decoder, disp, /*strip=*/false);
  }

  bool OpenResource(IWICImagingFactory* factory, int id, int disp) {
    HRSRC res = FindResourceW(nullptr, MAKEINTRESOURCEW(id), RT_RCDATA);
    HGLOBAL data = res ? LoadResource(nullptr, res) : nullptr;
    void* bytes = data ? LockResource(data) : nullptr;
    const DWORD size = res ? SizeofResource(nullptr, res) : 0;
    if (!bytes || size == 0 || FAILED(factory->CreateStream(&stream_)) ||
        FAILED(stream_->InitializeFromMemory(static_cast<BYTE*>(bytes),
                                             size))) {
      Release();
      return false;
    }
    IWICBitmapDecoder* decoder = nullptr;
    if (FAILED(factory->CreateDecoderFromStream(
            stream_, nullptr, WICDecodeMetadataCacheOnDemand, &decoder))) {
      Release();
      return false;
    }
    return Init(factory, decoder, disp, /*strip=*/true);
  }

  int frames() const { return frames_; }
  int decoded() const { return decoded_; }
  int disp() const { return disp_; }

  // מפענח את הפריים הבא לתוך [bits]. כשל עוצר את הרצועה בפריים האחרון שפוענח.
  bool DecodeNext(BYTE* bits) {
    if (!source_ || decoded_ >= frames_) return false;
    const UINT stride = static_cast<UINT>(disp_) * 4;
    const UINT frame_bytes = stride * static_cast<UINT>(disp_);
    WICRect rect = {0, decoded_ * disp_, disp_, disp_};
    if (FAILED(source_->CopyPixels(&rect, stride, frame_bytes,
                                   bits + static_cast<size_t>(frame_bytes) *
                                              decoded_))) {
      frames_ = decoded_;
      Release();
      return false;
    }
    if (++decoded_ == frames_) Release();
    return true;
  }

  void Release() {
    source_ = nullptr;
    if (scaler_) scaler_->Release();
    if (converter_) converter_->Release();
    if (frame_) frame_->Release();
    if (decoder_) decoder_->Release();
    if (stream_) stream_->Release();
    scaler_ = nullptr;
    converter_ = nullptr;
    frame_ = nullptr;
    decoder_ = nullptr;
    stream_ = nullptr;
  }

 private:
  bool Init(IWICImagingFactory* factory, IWICBitmapDecoder* decoder, int disp,
            bool strip) {
    decoder_ = decoder;
    UINT w = 0, h = 0;
    if (FAILED(decoder_->GetFrame(0, &frame_)) ||
        FAILED(frame_->GetSize(&w, &h)) || w == 0 ||
        (strip && h % w != 0)) {
      Release();
      return false;
    }
    frames_ = strip ? static_cast<int>(h / w) : 1;
    disp_ = disp;
    // הכפלת אלפא לפני ההקטנה, אחרת שולי הזהב השקופים למחצה מקבלים הילה כהה.
    if (FAILED(factory->CreateFormatConverter(&converter_)) ||
        FAILED(converter_->Initialize(frame_, GUID_WICPixelFormat32bppPBGRA,
                                      WICBitmapDitherTypeNone, nullptr, 0.0,
                                      WICBitmapPaletteTypeCustom))) {
      Release();
      return false;
    }
    source_ = converter_;
    if (static_cast<int>(w) != disp) {
      if (FAILED(factory->CreateBitmapScaler(&scaler_)) ||
          FAILED(scaler_->Initialize(
              converter_, disp, disp * frames_,
              WICBitmapInterpolationModeHighQualityCubic))) {
        Release();
        return false;
      }
      source_ = scaler_;
    }
    return true;
  }

  IWICStream* stream_ = nullptr;
  IWICBitmapDecoder* decoder_ = nullptr;
  IWICBitmapFrameDecode* frame_ = nullptr;
  IWICFormatConverter* converter_ = nullptr;
  IWICBitmapScaler* scaler_ = nullptr;
  IWICBitmapSource* source_ = nullptr;  // converter_ או scaler_, לא בבעלות
  int frames_ = 0;
  int decoded_ = 0;
  int disp_ = 0;
};

// מציג את [frame] מתוך ה-DIB (היסט מקור, בלי העתקה) באטימות [alpha].
void Present(HWND hwnd, int frame, double alpha) {
  if (!g_mem_dc) return;
  int a = static_cast<int>(alpha + 0.5);
  a = a < 0 ? 0 : (a > 255 ? 255 : a);
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, static_cast<BYTE>(a), AC_SRC_ALPHA};
  POINT src = {0, frame * g_disp};
  SIZE sz = {g_disp, g_disp};
  UpdateLayeredWindow(hwnd, nullptr, &g_pos, &sz, g_mem_dc, &src, 0, &blend,
                      ULW_ALPHA);
}

void PumpMessages() {
  MSG msg;
  while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }
}

bool CloseRequested() {
  return WaitForSingleObject(g_close_event, 0) == WAIT_OBJECT_0;
}

// ממתין עד [deadline_ms] (או לסגירה, אם [watch_close]) ושואב הודעות בדרך.
// טיימר ברזולוציה גבוהה: Sleep רגיל קופץ ב-15.6ms ומרעיד קצב של 24fps.
// מחזיר true אם התבקשה סגירה.
bool WaitUntil(HANDLE timer, double deadline_ms, bool watch_close) {
  for (;;) {
    PumpMessages();
    if (watch_close && CloseRequested()) return true;
    const double now = NowMs();
    if (now >= deadline_ms) return false;
    HANDLE handles[2] = {g_close_event, timer};
    DWORD count = 0;
    DWORD timeout = INFINITE;
    const HANDLE* wait_on = handles;
    if (deadline_ms != kForever) {
      LARGE_INTEGER due;
      due.QuadPart = -static_cast<LONGLONG>((deadline_ms - now) * 10000.0);
      if (timer && SetWaitableTimer(timer, &due, 0, nullptr, nullptr, FALSE)) {
        wait_on = watch_close ? handles : handles + 1;
        count = watch_close ? 2 : 1;
      } else {
        timeout = static_cast<DWORD>(deadline_ms - now) + 1;
        count = watch_close ? 1 : 0;
      }
    } else {
      count = watch_close ? 1 : 0;
    }
    MsgWaitForMultipleObjects(count, wait_on, FALSE, timeout, QS_ALLINPUT);
  }
}

LRESULT CALLBACK SplashWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                               LPARAM lparam) {
  if (msg == WM_DESTROY) {
    if (g_mem_dc) {
      if (g_old_bmp) SelectObject(g_mem_dc, g_old_bmp);
      DeleteDC(g_mem_dc);
      g_mem_dc = nullptr;
    }
    if (g_dib) {
      DeleteObject(g_dib);
      g_dib = nullptr;
    }
    g_bits = nullptr;
    return 0;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

// תיקיית קובץ ההרצה (ללא לוכסן בסוף).
std::wstring ExecutableDir() {
  wchar_t buffer[MAX_PATH];
  DWORD len = GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return std::wstring();
  }
  std::wstring path(buffer, len);
  size_t pos = path.find_last_of(L"\\/");
  if (pos == std::wstring::npos) {
    return std::wstring();
  }
  return path.substr(0, pos);
}

// DPI המערכת (מסך ראשי). GetDpiForSystem זמין מ-Windows 10 1607; טעינה
// דינמית עם fallback ל-GetDeviceCaps כדי שלא ניפול בסביבות ישנות.
UINT SystemDpi() {
  if (HMODULE user32 = GetModuleHandleW(L"user32.dll")) {
    using GetDpiForSystemFn = UINT(WINAPI*)();
    auto fn = reinterpret_cast<GetDpiForSystemFn>(
        GetProcAddress(user32, "GetDpiForSystem"));
    if (fn) {
      UINT dpi = fn();
      if (dpi != 0) {
        return dpi;
      }
    }
  }
  HDC dc = GetDC(nullptr);
  UINT dpi = dc ? static_cast<UINT>(GetDeviceCaps(dc, LOGPIXELSX)) : 96;
  if (dc) {
    ReleaseDC(nullptr, dc);
  }
  return dpi != 0 ? dpi : 96;
}

// "הצג אנימציות ב-Windows" כבוי = הפחתת תנועה.
bool SystemAnimationsEnabled() {
  BOOL enabled = TRUE;
  if (!SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0)) {
    return true;
  }
  return enabled != FALSE;
}

int StripFor(int disp) {
  for (const StripResource& strip : kStrips) {
    if (strip.side >= disp) return strip.id;
  }
  return kStrips[sizeof(kStrips) / sizeof(kStrips[0]) - 1].id;
}

// יוצר את החלון השקוף (אטימות 0) עם פריים 0 מפוענח, ממורכז על המסך הראשי.
HWND CreateSplashWindow(FrameDecoder* decoder, double* band_ms) {
  const int disp = decoder->disp();
  g_disp = disp;

  HDC screen_dc = GetDC(nullptr);
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = disp;
  bmi.bmiHeader.biHeight = -disp * decoder->frames();  // top-down, כל הפריימים
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  g_dib = CreateDIBSection(screen_dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  const double start = NowMs();
  if (g_dib && bits && decoder->DecodeNext(static_cast<BYTE*>(bits))) {
    *band_ms = NowMs() - start;
    g_bits = static_cast<BYTE*>(bits);
    g_mem_dc = CreateCompatibleDC(screen_dc);
    g_old_bmp = SelectObject(g_mem_dc, g_dib);
  }
  ReleaseDC(nullptr, screen_dc);
  if (!g_mem_dc) {
    if (g_dib) DeleteObject(g_dib);
    g_dib = nullptr;
    g_bits = nullptr;
    return nullptr;
  }

  HINSTANCE hinst = GetModuleHandleW(nullptr);
  WNDCLASSW wc = {};
  wc.lpfnWndProc = SplashWndProc;
  wc.hInstance = hinst;
  wc.lpszClassName = kSplashClassName;
  RegisterClassW(&wc);  // אם כבר רשום — נכשל בשקט, וזה תקין.

  HMONITOR mon = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi = {sizeof(MONITORINFO)};
  GetMonitorInfo(mon, &mi);
  const int x =
      mi.rcWork.left + ((mi.rcWork.right - mi.rcWork.left) - disp) / 2;
  const int y =
      mi.rcWork.top + ((mi.rcWork.bottom - mi.rcWork.top) - disp) / 2;
  g_pos = {x, y};

  HWND hwnd = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW |
          WS_EX_NOACTIVATE,
      kSplashClassName, L"", WS_POPUP, x, y, disp, disp, nullptr, nullptr,
      hinst, nullptr);
  if (!hwnd) {
    SelectObject(g_mem_dc, g_old_bmp);
    DeleteDC(g_mem_dc);
    DeleteObject(g_dib);
    g_mem_dc = nullptr;
    g_dib = nullptr;
    g_bits = nullptr;
    return nullptr;
  }
  Present(hwnd, 0, 0);
  // SW_SHOWNOACTIVATE — לא לחטוף פוקוס מהחלון הראשי כשהוא ייפתח.
  ShowWindow(hwnd, SW_SHOWNOACTIVATE);
  return hwnd;
}

bool DecodeOne(FrameDecoder* decoder, double* band_ms) {
  const double start = NowMs();
  if (!g_bits || !decoder->DecodeNext(g_bits)) return false;
  *band_ms = NowMs() - start;
  return true;
}

// מפענח קדימה רק כשיש זמן לפני [deadline_ms], לפי משך הפס הקודם.
void DecodeWithin(FrameDecoder* decoder, double deadline_ms,
                  double* band_ms) {
  while (decoder->decoded() < decoder->frames() &&
         NowMs() + *band_ms < deadline_ms) {
    if (!DecodeOne(decoder, band_ms)) return;
  }
}

// fade-in סינכרוני, בזמן שה-thread הראשי חסום במחסום שב-Show (לא טוען DLLs).
// הפענוח קדימה מנצל את ההמתנה שבין הצעדים ואינו מאריך את המחסום.
void FadeIn(HWND hwnd, FrameDecoder* decoder, HANDLE timer, double* band_ms) {
  const double start = NowMs();
  for (;;) {
    const double t = NowMs() - start;
    Present(hwnd, 0, tl::FadeInAlpha(t));
    if (t >= tl::kFadeInMs) return;
    const double next = NowMs() + kFadeIntervalMs;
    DecodeWithin(decoder, next, band_ms);
    WaitUntil(timer, next, /*watch_close=*/false);
  }
}

// מנגן עד שמתבקשת סגירה, ומחזיר את מה שמוצג ברגע זה (ל-fade-out).
tl::Pose Play(HWND hwnd, FrameDecoder* decoder, bool animate, HANDLE timer,
              double* band_ms) {
  tl::Pose shown = {0, tl::kAlpha};
  double play_ms = 0;
  double last = NowMs();
  for (;;) {
    const double now = NowMs();
    play_ms = tl::ClampPlayMs(play_ms + (now - last), decoder->decoded(),
                              decoder->frames());
    last = now;
    const tl::Pose pose = tl::PoseAt(play_ms, decoder->frames(), animate);
    if (pose.frame != shown.frame ||
        static_cast<int>(pose.alpha + 0.5) !=
            static_cast<int>(shown.alpha + 0.5)) {
      Present(hwnd, pose.frame, pose.alpha);
      shown = pose;
    }
    const double next_rel =
        tl::NextChangeMs(play_ms, decoder->frames(), animate);
    const double deadline =
        next_rel < 0 ? kForever : now + (next_rel - play_ms);
    // הפריים הבא תמיד מוכן מראש; מעבר לו — רק בזמן הפנוי.
    while (decoder->decoded() < decoder->frames() &&
           decoder->decoded() <= pose.frame + 1) {
      if (!DecodeOne(decoder, band_ms)) break;
    }
    DecodeWithin(decoder, deadline, band_ms);
    if (WaitUntil(timer, deadline, /*watch_close=*/true)) return shown;
  }
}

// הסגירה מגיעה כשהחלון הראשי כבר גלוי; החזקת הסמל מעבר לזה תשאיר אותו צף מעליו.
void FadeOut(HWND hwnd, tl::Pose from, HANDLE timer) {
  const double start = NowMs();
  for (;;) {
    const double alpha = tl::FadeOutAlpha(from.alpha, NowMs() - start);
    if (alpha <= 0) return;
    Present(hwnd, from.frame, alpha);
    WaitUntil(timer, NowMs() + kFadeIntervalMs, /*watch_close=*/false);
  }
}

DWORD WINAPI SplashThreadProc(LPVOID) {
  const HRESULT co = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // כל הפענוח וה-COM כאן, לפני האות: ה-thread הראשי ממתין במחסום ולא טוען DLLs.
  IWICImagingFactory* factory = nullptr;
  CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                   IID_PPV_ARGS(&factory));
  FrameDecoder decoder;
  bool animate = g_animate;
  HWND hwnd = nullptr;
  double band_ms = 0;
  if (factory && animate) {
    const int disp = MulDiv(kFrameLogicalSize, static_cast<int>(g_dpi), 96);
    hwnd = decoder.OpenResource(factory, StripFor(disp), disp)
               ? CreateSplashWindow(&decoder, &band_ms)
               : nullptr;
  }
  if (factory && !hwnd) {
    decoder.Release();
    animate = false;
    const int disp = MulDiv(kIconLogicalSize, static_cast<int>(g_dpi), 96);
    const std::wstring icon_path =
        ExecutableDir() + L"\\data\\flutter_assets\\assets\\icon\\icon.png";
    hwnd = decoder.OpenFile(factory, icon_path, disp)
               ? CreateSplashWindow(&decoder, &band_ms)
               : nullptr;
  }

  HANDLE timer =
      CreateWaitableTimerExW(nullptr, nullptr,
                             CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                             TIMER_ALL_ACCESS);
  if (!timer) {
    timer = CreateWaitableTimerExW(nullptr, nullptr, 0, TIMER_ALL_ACCESS);
  }
  if (hwnd) {
    FadeIn(hwnd, &decoder, timer, &band_ms);
  }
  g_splash_hwnd = hwnd;
  // מאותתים ל-Show() שהחלון קיים וה-fade-in הסתיים — *לפני* שה-thread הראשי
  // טוען את ה-DLLs של המנוע (שהיו מחזיקים את ה-loader lock).
  SetEvent(g_created_event);

  if (hwnd != nullptr) {
    const tl::Pose last = Play(hwnd, &decoder, animate, timer, &band_ms);
    FadeOut(hwnd, last, timer);
    DestroyWindow(hwnd);  // → WM_DESTROY → שחרור ה-DIB
    g_splash_hwnd = nullptr;
  }

  decoder.Release();
  if (factory) factory->Release();
  if (timer) CloseHandle(timer);
  if (g_close_event) {
    CloseHandle(g_close_event);
    g_close_event = nullptr;
  }
  if (SUCCEEDED(co)) {
    CoUninitialize();
  }
  return 0;
}

}  // namespace

namespace splash {

void Show() {
  if (g_splash_thread) {
    return;
  }

  g_dpi = SystemDpi();
  g_animate = SystemAnimationsEnabled();
  g_close_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);  // manual-reset
  g_created_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_splash_hwnd = nullptr;
  g_splash_thread =
      CreateThread(nullptr, 0, SplashThreadProc, nullptr, 0, nullptr);
  if (!g_splash_thread) {
    CloseHandle(g_close_event);
    g_close_event = nullptr;
  }

  // מחסום: ממתינים שה-thread יפענח, ייצור את החלון *ויסיים את ה-fade-in* לפני
  // שנמשיך לטעון את ה-DLLs של המנוע (ה-loader lock היה חוסם את ההתבהרות).
  // ה-timeout הוא רשת ביטחון בלבד.
  if (g_created_event) {
    if (g_splash_thread) WaitForSingleObject(g_created_event, 2000);
    CloseHandle(g_created_event);
    g_created_event = nullptr;
  }
}

void Close() {
  // נקרא בעת חשיפת החלון הראשי. מסמן ל-thread לעבור ל-fade-out (לא ממתין —
  // ה-thread משמיד את החלון בסיום). מוגן מפני קריאה כפולה.
  if (g_splash_thread == nullptr) {
    return;
  }
  if (g_close_event != nullptr) {
    SetEvent(g_close_event);
  }
  CloseHandle(g_splash_thread);
  g_splash_thread = nullptr;
}

}  // namespace splash
