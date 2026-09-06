#include "drag_preview_window.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace drag_preview {
namespace {

constexpr const wchar_t kClassName[] = L"OtzariaDragPreview";

// מידות השרטוט שלפני שהצילום מגיע, ביחידות לוגיות (96 DPI).
//
// ⚠️ קיים רק לפריים אחד. הצילום אסינכרוני, ובלעדיו היה רגע שבו הסמן יוצא
// מהחלון ולא נראה כלום.
constexpr int kFallbackWidth = 176;
constexpr int kFallbackHeight = 40;
constexpr int kTabRadius = 8;

// צבע זקיף לזיהוי מה GDI צייר.
//
// ⚠️ GDI אינו כותב לערוץ האלפא, ו-`UpdateLayeredWindow` דורש אלפא לכל
// פיקסל — כלומר שרטוט GDI גולמי היה יוצא שקוף לחלוטין. לכן ה-DIB נצבע
// מראש במג'נטה, ואחרי הציור כל פיקסל שאינו מג'נטה מקבל אלפא 255. מג'נטה
// ולא שחור: צבע ערכה כהה יכול להיות שחור-כמעט, ואז חלקים מהכרטיסיה היו
// יוצאים שקופים.
constexpr unsigned char kSentinelB = 0xFF;
constexpr unsigned char kSentinelG = 0x00;
constexpr unsigned char kSentinelR = 0xFF;
constexpr COLORREF kSentinel = RGB(kSentinelR, kSentinelG, kSentinelB);

constexpr UINT_PTR kFollowTimerId = 1;
constexpr UINT kFollowIntervalMs = 16;

// ⚠️ רשת ביטחון להקפאה. התצוגה נשארת גלויה עד שהחלון האמיתי נחשף, ואם
// היצירה נכשלה בשקט היא הייתה נשארת תלויה על המסך לנצח.
constexpr UINT_PTR kHoldTimerId = 2;
constexpr UINT kHoldTimeoutMs = 4000;

std::mutex g_mutex;
HWND g_window = nullptr;
std::wstring g_title;
std::atomic<bool> g_active{false};

// החלון שממנו הגרירה התחילה. התצוגה מוסתרת רק מעליו.
std::atomic<HWND> g_source{nullptr};

// האם Windows מנהל כרגע את הגרירה. חוסם את המעקב שלנו, שהיה נאבק בו.
std::atomic<bool> g_system_dragging{false};

struct Palette {
  COLORREF tab = RGB(0xF7, 0xF2, 0xEA);
  COLORREF border = RGB(0xC9, 0xBA, 0xA4);
  COLORREF text = RGB(0x3A, 0x2E, 0x1E);
};
Palette g_palette;

// צילום הכרטיסיה, BGRA מוכפל-מראש, שורות מלמעלה למטה.
//
// ⚠️ מאגר ולא `HBITMAP`: `UpdateLayeredWindow` מקבל DC של DIB שאנחנו
// בונים בכל הרכבה, וכך אין מצב ביניים שבו הביטמאפ נבחר לשני DC-ים.
std::vector<unsigned char> g_shot;
int g_shot_w = 0;
int g_shot_h = 0;
// הגודל שבו התצוגה צריכה להופיע — ראו [SetImage].
int g_target_w = 0;
int g_target_h = 0;

int DpiOf(HWND hwnd) {
  const UINT dpi = hwnd ? ::GetDpiForWindow(hwnd) : 96;
  return dpi > 0 ? static_cast<int>(dpi) : 96;
}

// מידות התצוגה בפיקסלים פיזיים.
void PreviewSize(int* out_w, int* out_h) {
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_target_w > 0 && g_target_h > 0) {
      *out_w = g_target_w;
      *out_h = g_target_h;
      return;
    }
  }
  const int dpi = DpiOf(g_source.load());
  *out_w = ::MulDiv(kFallbackWidth, dpi, 96);
  *out_h = ::MulDiv(kFallbackHeight, dpi, 96);
}

// מצייר את השרטוט שלפני הצילום לתוך [hdc], ומחזיר את האזור שנגע בו.
void DrawFallback(HDC hdc, int width, int height) {
  Palette palette;
  std::wstring title;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    palette = g_palette;
    title = g_title;
  }

  const HBRUSH fill = ::CreateSolidBrush(palette.tab);
  const HGDIOBJ old_brush = ::SelectObject(hdc, fill);
  const HPEN pen = ::CreatePen(PS_SOLID, 1, palette.border);
  const HGDIOBJ old_pen = ::SelectObject(hdc, pen);
  // פינות עליונות מעוגלות ותחתונות מרובעות — כך זו כרטיסיה ולא כפתור.
  ::RoundRect(hdc, 0, 0, width, height + kTabRadius, kTabRadius * 2,
              kTabRadius * 2);
  ::SelectObject(hdc, old_pen);
  ::DeleteObject(pen);
  ::SelectObject(hdc, old_brush);
  ::DeleteObject(fill);

  // ⚠️ `DT_RTLREADING` — הכותרות בעברית, ובלעדיו סימני פיסוק ומספרים
  // מופיעים בצד הלא נכון.
  const int dpi = DpiOf(g_source.load());
  const HFONT font = ::CreateFontW(
      ::MulDiv(15, dpi, 96), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  const HGDIOBJ old_font = ::SelectObject(hdc, font);
  ::SetBkMode(hdc, TRANSPARENT);
  ::SetTextColor(hdc, palette.text);
  const int inset = ::MulDiv(9, dpi, 96);
  RECT text_rect{inset, 0, width - inset, height};
  ::DrawTextW(hdc, title.c_str(), -1, &text_rect,
              DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_END_ELLIPSIS |
                  DT_RTLREADING | DT_NOPREFIX);
  ::SelectObject(hdc, old_font);
  ::DeleteObject(font);
}

// מותח את הצילום מגודלו לגודל היעד, לתוך [dst_dc].
//
// ⚠️ נקרא **תחת** [g_mutex] — הוא קורא את [g_shot] ישירות במקום להעתיק
// אותו. הצילום הוא מיליוני פיקסלים, והעתקה נוספת בכל הרכבה (16ms) הייתה
// מכפילה את התעבורה בזיכרון בזמן שהמשתמש גורר.
void StretchShot(HDC dst_dc, int target_w, int target_h) {
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = g_shot_w;
  info.bmiHeader.biHeight = -g_shot_h;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  const HDC screen = ::GetDC(nullptr);
  void* bits = nullptr;
  const HBITMAP src =
      ::CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  ::ReleaseDC(nullptr, screen);
  if (!src || !bits) {
    if (src) ::DeleteObject(src);
    return;
  }
  ::memcpy(bits, g_shot.data(),
           static_cast<size_t>(g_shot_w) * g_shot_h * 4);

  const HDC src_dc = ::CreateCompatibleDC(dst_dc);
  const HGDIOBJ old = ::SelectObject(src_dc, src);
  // HALFTONE נותן דגימה מחדש ראויה בהקטנה; בלעדיו קווי טקסט נעלמים.
  ::SetStretchBltMode(dst_dc, HALFTONE);
  ::SetBrushOrgEx(dst_dc, 0, 0, nullptr);
  ::StretchBlt(dst_dc, 0, 0, target_w, target_h, src_dc, 0, 0, g_shot_w,
               g_shot_h, SRCCOPY);
  ::SelectObject(src_dc, old);
  ::DeleteDC(src_dc);
  ::DeleteObject(src);
}

// מרכיב את התצוגה ומעביר אותה ל-Windows עם אלפא לכל פיקסל.
//
// ⚠️ `UpdateLayeredWindow` ולא `WM_PAINT` + `SetLayeredWindowAttributes`.
// השני נותן שקיפות **אחידה** לכל החלון, ולכן הפינות המעוגלות של
// הכרטיסיה היו נצבעות ברקע שלנו במקום להיות שקופות — מלבן עם פינות
// צבועות, לא כרטיסיה. השניים גם אינם יכולים לחיות יחד: קריאה לאחד
// מבטלת את מצב השני.
//
// [move_to] הוא מיקום חדש בקואורדינטות מסך, או nullptr כדי להשאיר במקום.
void Compose(const POINT* move_to) {
  if (!g_window) return;

  int width = 0;
  int height = 0;
  PreviewSize(&width, &height);
  if (width <= 0 || height <= 0) return;

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  // ⚠️ שלילי = top-down. `toByteData` מחזיר שורות מלמעלה למטה, ו-DIB
  // ברירת מחדל הוא bottom-up — בלי המינוס התמונה מגיעה הפוכה.
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  const HDC screen = ::GetDC(nullptr);
  const HDC mem = ::CreateCompatibleDC(screen);
  void* bits = nullptr;
  const HBITMAP dib =
      ::CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!dib || !bits) {
    if (dib) ::DeleteObject(dib);
    ::DeleteDC(mem);
    ::ReleaseDC(nullptr, screen);
    return;
  }
  const HGDIOBJ old_bitmap = ::SelectObject(mem, dib);
  auto* dst = static_cast<unsigned char*>(bits);
  const size_t pixels = static_cast<size_t>(width) * height;

  bool have_shot = false;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_shot.empty() && g_shot_w > 0 && g_shot_h > 0) {
      if (g_shot_w == width && g_shot_h == height) {
        ::memcpy(dst, g_shot.data(), pixels * 4);
      } else {
        StretchShot(mem, width, height);
        // ⚠️ `StretchBlt` אינו כותב לערוץ האלפא. המוק שמגיע מ-Dart הוא
        // אטום ממילא (רקע הרצועה נצבע מתחת לכרטיסיה בזמן ההרכבה), ולכן
        // אלפא 255 גורף הוא נכון — ולא ניחוש.
        ::GdiFlush();
        for (size_t i = 0; i < pixels; ++i) {
          dst[i * 4 + 3] = 255;
        }
      }
      have_shot = true;
    }
  }

  if (!have_shot) {
    // צביעה מראש בזקיף, ציור, ואז חילוץ האלפא — ראו [kSentinel].
    for (size_t i = 0; i < pixels; ++i) {
      dst[i * 4 + 0] = kSentinelB;
      dst[i * 4 + 1] = kSentinelG;
      dst[i * 4 + 2] = kSentinelR;
      dst[i * 4 + 3] = 0;
    }
    DrawFallback(mem, width, height);
    ::GdiFlush();
    for (size_t i = 0; i < pixels; ++i) {
      const bool untouched = dst[i * 4 + 0] == kSentinelB &&
                             dst[i * 4 + 1] == kSentinelG &&
                             dst[i * 4 + 2] == kSentinelR;
      if (untouched) {
        dst[i * 4 + 0] = 0;
        dst[i * 4 + 1] = 0;
        dst[i * 4 + 2] = 0;
        dst[i * 4 + 3] = 0;
      } else {
        dst[i * 4 + 3] = 255;
      }
    }
  }

  SIZE size{width, height};
  POINT src{0, 0};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;
  POINT position{};
  if (move_to) {
    position = *move_to;
  } else {
    RECT current{};
    ::GetWindowRect(g_window, &current);
    position.x = current.left;
    position.y = current.top;
  }
  ::UpdateLayeredWindow(g_window, screen, &position, &size, mem, &src, 0,
                        &blend, ULW_ALPHA);

  ::SelectObject(mem, old_bitmap);
  ::DeleteObject(dib);
  ::DeleteDC(mem);
  ::ReleaseDC(nullptr, screen);
}

// האם הנקודה נמצאת מעל חלון המקור.
//
// ⚠️ המקור בלבד, ולא "כל חלון של התהליך" — ראו ההערה ב-[Begin] שבכותרת.
bool IsOverSourceWindow(POINT pt) {
  const HWND source = g_source.load();
  if (!source) return false;
  const HWND under = WindowUnderCursor(pt);
  return under == source;
}

// ממקם את התצוגה כך שפינתה תשב על הסמן.
//
// ⚠️ פינה ולא מרכז, ובמכוון: `Draggable` מוגדר עם
// `pointerDragAnchorStrategy`, כלומר ה-`feedback` שבתוך החלון מצויר עם
// פינתו על הסמן. אותו היסט כאן הוא מה שהופך את המעבר מתוך החלון אל
// מחוצה לו לרציף — אחרת הכרטיסיה קופצת ברגע שהסמן חוצה את הגבול.
void MoveToCursor() {
  POINT pt{};
  if (!::GetCursorPos(&pt)) return;
  Compose(&pt);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                         LPARAM lparam) {
  switch (message) {
    // ⚠️ ביטול המסגרת. הסגנונות של חלון אמיתי נדרשים כדי שה-shell יציע
    // Snap Layouts, אבל מסגרת וכותרת של Windows על צילום של כרטיסיה היו
    // נראות כמו שגיאה. החזרת אזור הלקוח כמלוא החלון משאירה את הסגנונות
    // ומוחקת את הציור שלהם.
    case WM_NCCALCSIZE:
      if (wparam == TRUE) return 0;
      break;
    case WM_TIMER: {
      if (wparam == kHoldTimerId) {
        // החלון האמיתי לא נחשף בזמן. עדיף להסתיר מלהשאיר תלוי.
        ::KillTimer(hwnd, kHoldTimerId);
        End();
        return 0;
      }
      if (wparam != kFollowTimerId) break;
      if (g_system_dragging.load()) return 0;
      POINT pt{};
      if (!::GetCursorPos(&pt)) return 0;
      // מעל חלון המקור ה-`feedback` של Flutter כבר מוצג, ולכן התצוגה
      // הנייטיבית מוסתרת כדי שלא ייראו שתי כרטיסיות. מעל כל מקום אחר —
      // כולל חלון אוצריא אחר — היא **חייבת** להיראות, כי ה-feedback
      // נחתך בגבולות חלון המקור.
      const bool should_show = !IsOverSourceWindow(pt);
      const bool visible = ::IsWindowVisible(hwnd) != FALSE;
      if (should_show != visible) {
        ::ShowWindow(hwnd, should_show ? SW_SHOWNOACTIVATE : SW_HIDE);
      }
      if (should_show) Compose(&pt);
      return 0;
    }
    case WM_DESTROY:
      return 0;
  }
  return ::DefWindowProc(hwnd, message, wparam, lparam);
}

void EnsureClass() {
  static bool registered = false;
  if (registered) return;
  WNDCLASSW wc{};
  wc.lpfnWndProc = WndProc;
  wc.hInstance = ::GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  ::RegisterClassW(&wc);
  registered = true;
}

}  // namespace

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int size = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring result(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), result.data(), size);
  return result;
}

HWND WindowUnderCursor(POINT pt) {
  // בלי התצוגה השאלה פשוטה. העלייה ל-root חיונית: `WindowFromPoint`
  // מחזיר את החלון הפנימי ביותר, בדרך כלל ה-view של Flutter או WebView2.
  if (!g_window || !::IsWindowVisible(g_window)) {
    const HWND under = ::WindowFromPoint(pt);
    return under ? ::GetAncestor(under, GA_ROOT) : nullptr;
  }
  // ⚠️ הדלקה רגעית של `WS_EX_TRANSPARENT`. הדגל אינו מודלק בקביעות כי
  // חלון שאינו נמצא תחת הסמן אינו נראה ל-shell כחלון שנגרר, ובלי זה אין
  // Snap Layouts. כאן הוא נדרש לרגע החישוב בלבד: בלעדיו התצוגה עצמה
  // הייתה התשובה, וכל שחרור מעל חלון אחר לא היה מזוהה.
  const LONG_PTR ex = ::GetWindowLongPtrW(g_window, GWL_EXSTYLE);
  ::SetWindowLongPtrW(g_window, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT);
  const HWND under = ::WindowFromPoint(pt);
  ::SetWindowLongPtrW(g_window, GWL_EXSTYLE, ex);
  return under ? ::GetAncestor(under, GA_ROOT) : nullptr;
}

void Begin(const std::wstring& title, HWND source, const Colors& colors) {
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_title = title;
    if (colors.valid) {
      g_palette.tab = colors.tab;
      g_palette.border = colors.border;
      g_palette.text = colors.text;
    }
    // הצילום של הגרירה הקודמת אינו שייך לזו — עד שיגיע חדש, שרטוט.
    g_shot.clear();
    g_shot_w = 0;
    g_shot_h = 0;
    g_target_w = 0;
    g_target_h = 0;
  }
  g_source.store(source);
  g_system_dragging.store(false);
  EnsureClass();

  if (!g_window) {
    // ⚠️ `WS_OVERLAPPEDWINDOW` ולא `WS_POPUP`, וללא `WS_EX_TOOLWINDOW`.
    //
    // אלה התנאים שה-shell בודק לפני שהוא מציע Snap Layouts: חלון עליון
    // שניתן לשנות את גודלו (`WS_THICKFRAME`), עם כפתור הגדלה
    // (`WS_MAXIMIZEBOX`), שאינו חלון כלים. עם `WS_POPUP` או
    // `WS_EX_TOOLWINDOW` הגרירה פשוט לא מזוהה כגרירת חלון — וזה מה
    // שהמשתמש דיווח.
    //
    // המסגרת עצמה מבוטלת ב-`WM_NCCALCSIZE`, כלומר הסגנונות קיימים
    // לצורך הסיווג בלבד ואינם נראים.
    //
    // ⚠️ אין כאן `WS_EX_NOACTIVATE`: לולאת ההזזה של Windows עובדת על
    // החלון הפעיל, וחלון שאינו מקבל הפעלה אינו "החלון הנגרר".
    g_window = ::CreateWindowExW(
        WS_EX_LAYERED | WS_EX_TOPMOST, kClassName, L"אוצריא",
        WS_OVERLAPPEDWINDOW, 0, 0, kFallbackWidth, kFallbackHeight, nullptr,
        nullptr, ::GetModuleHandle(nullptr), nullptr);
    if (!g_window) return;
  }

  ::KillTimer(g_window, kHoldTimerId);
  ::SetTimer(g_window, kFollowTimerId, kFollowIntervalMs, nullptr);
  g_active.store(true);

  // מיקום ותוכן ראשוניים מיידיים, כדי שהתצוגה לא תקפוץ מהפינה בפעימה
  // הראשונה.
  MoveToCursor();
}

void SetImage(const unsigned char* rgba, size_t rgba_size, int width,
              int height, int target_width, int target_height) {
  if (!rgba || width <= 0 || height <= 0) return;
  // ⚠️ המידות מגיעות מ-Dart בנפרד מהמאגר, ולכן הן נבדקות מולו. בלי
  // הבדיקה קריאה עם מידות שאינן תואמות קראה מעבר לסוף המאגר.
  if (static_cast<size_t>(width) * static_cast<size_t>(height) * 4 >
      rgba_size) {
    return;
  }
  if (target_width <= 0 || target_height <= 0) {
    target_width = width;
    target_height = height;
  }

  std::vector<unsigned char> bgra(static_cast<size_t>(width) * height * 4);
  // RGBA → BGRA. שני הפורמטים מוכפלים-מראש, ולכן די בהחלפת אדום וכחול.
  const size_t pixels = static_cast<size_t>(width) * height;
  for (size_t i = 0; i < pixels; ++i) {
    bgra[i * 4 + 0] = rgba[i * 4 + 2];
    bgra[i * 4 + 1] = rgba[i * 4 + 1];
    bgra[i * 4 + 2] = rgba[i * 4 + 0];
    bgra[i * 4 + 3] = rgba[i * 4 + 3];
  }

  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_shot = std::move(bgra);
    g_shot_w = width;
    g_shot_h = height;
    g_target_w = target_width;
    g_target_h = target_height;
  }
  // ⚠️ בלי מיקום מחדש: הסמן לא זז, והתצוגה גדלה לגודל הצילום סביב אותה
  // פינה. `Compose` מקבל nullptr ולכן שומר את המקום.
  if (g_window && !g_system_dragging.load()) Compose(nullptr);
}

SystemDragResult DragWithSystem() {
  SystemDragResult out;
  if (!g_window || !g_active.load()) return out;

  POINT cursor{};
  if (!::GetCursorPos(&cursor)) return out;
  out.cursor = cursor;

  // ⚠️ רק אם הכפתור עוד לחוץ. `WM_NCLBUTTONDOWN` בלי כפתור לחוץ נכנס
  // ללולאה שנתקעת עד הלחיצה הבאה — חלון שנתפס לסמן בלי סיבה.
  //
  // ⚠️ `VK_LBUTTON` הוא הכפתור **הפיזי** ואינו מתחשב בהחלפת כפתורים.
  // למשתמש שהחליף אותם הבדיקה נכשלה תמיד, המסירה למערכת נדחתה, וכל
  // הגרירה רצה במסלול הנפילה — בלי Snap Layouts ועם התצוגה הנייטיבית
  // מתחדשת ב-60Hz.
  const int drag_button =
      ::GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
  if ((::GetAsyncKeyState(drag_button) & 0x8000) == 0) {
    ::GetWindowRect(g_window, &out.rect);
    out.under = WindowUnderCursor(cursor);
    return out;
  }

  // ⚠️ הגודל הצפוי נדגם **לפני** הלולאה המודאלית, ולא אחריה.
  //
  // `PreviewSize` מחזיר את גודל היעד שנקבע ב-`SetImage`, ו-`SetImage`
  // יכול להגיע מ-Dart באמצע הגרירה — ואז הוא מדלג על `Compose`
  // (`g_system_dragging`), כלומר החלון **אינו** משתנה אבל הציפייה כן.
  // דגימה אחרי הלולאה השוותה גודל חלון ישן מול ציפייה חדשה, החזירה
  // `snapped=true` כוזב, ובצד Dart `snapped` גובר על היעד שתחת הסמן:
  // שחרור מעל חלון אוצריא אחר פתח חלון חדש במסגרת של 176×40 במקום להעביר
  // אליו.
  int expected_w = 0;
  int expected_h = 0;
  PreviewSize(&expected_w, &expected_h);

  g_system_dragging.store(true);
  ::KillTimer(g_window, kFollowTimerId);

  // ⚠️ יציאה מ-topmost. חלון topmost נגרר בסדר, אבל ה-shell מתייחס אליו
  // כאל שכבה מעל שאר החלונות ולא כאל חלון רגיל — וזה בדיוק הסיווג
  // שקובע אם יוצע Snap.
  ::SetWindowPos(g_window, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  ::ShowWindow(g_window, SW_SHOWNOACTIVATE);
  ::SetForegroundWindow(g_window);

  // ⚠️ `ReleaseCapture` אינו נימוס. ה-embedder של Flutter לוכד את העכבר
  // בלחיצה, וכל המנועים חולקים את ה-thread הזה — כלומר הלכידה של חלון
  // המקור בתוקף. בלעדיו לולאת ההזזה אינה רואה את העכבר, והחלון פשוט
  // אינו נגרר.
  ::ReleaseCapture();
  ::SendMessageW(g_window, WM_NCLBUTTONDOWN, HTCAPTION,
                 MAKELPARAM(cursor.x, cursor.y));

  // ⚠️ לולאת ההזזה יוצאת באותו אופן בשחרור ובביטול ב-ESC. בלי הבדיקה
  // הביטול דווח כשחרור מוצלח, והכרטיסיה עברה בניגוד לרצון המשתמש.
  if (::GetAsyncKeyState(VK_ESCAPE) & 0x8000) {
    g_system_dragging.store(false);
    return out;  // ran=false — Dart מטפל בו כ"אל תעשה כלום"
  }

  g_system_dragging.store(false);
  out.ran = true;
  ::GetWindowRect(g_window, &out.rect);
  // הצמדה = המערכת שינתה את הגודל. סבילות של 2 פיקסלים כי חלון מוצמד
  // מקבל מסגרת שאינה בהכרח זהה לפיקסל למה שביקשנו. הגודל הצפוי נדגם לפני
  // הלולאה — ראו ההערה שם.
  const int actual_w = out.rect.right - out.rect.left;
  const int actual_h = out.rect.bottom - out.rect.top;
  out.snapped =
      ::abs(actual_w - expected_w) > 2 || ::abs(actual_h - expected_h) > 2;
  ::GetCursorPos(&out.cursor);
  out.under = WindowUnderCursor(out.cursor);
  return out;
}

void Freeze() {
  if (!g_window || !g_active.load()) return;
  // מפסיק לעקוב אחרי הסמן, אבל **נשאר גלוי במקום שבו שוחרר**.
  //
  // ⚠️ זה מה שמכסה את הפער שהמשתמש תיאר: פתיחת חלון לוקחת מאות
  // מילישניות, ובלי ההקפאה המסך ריק בדיוק בפרק הזמן שבו המשתמש מחכה
  // לראות תוצאה. עכשיו הכרטיסיה נשארת במקום שגררו אליו, והחלון האמיתי
  // מחליף אותה במקום להופיע אחרי כלום.
  ::KillTimer(g_window, kFollowTimerId);

  // ⚠️ **הקפאה אינה הצגה.**
  //
  // סידור כרטיסיות בתוך החלון מסתיים גם הוא כאן — `onDragFinishedAnywhere`
  // נורה בכל מסלול — והסמן מעולם לא יצא מהחלון, כלומר התצוגה לא הוצגה.
  // `ShowWindow` בלתי-מותנה הציג אותה בשחרור, ובצירוף `kHoldTimeoutMs`
  // התוצאה הייתה חלון גדול שקופץ לארבע שניות אחרי כל סידור מקומי. כך
  // המשתמש דיווח: "בשחרור הכרטיסייה פתאום קופץ החלון עם הלשונית הגדולה
  // לכמה שניות".
  //
  // השאלה נשאלת מהמצב האמיתי ולא מ-`IsWindowVisible`: טיימר המעקב רץ כל
  // 16ms, ושחרור מיד אחרי יציאה מהחלון עלול להקדים את הפעימה שהייתה
  // מציגה אותה.
  POINT cursor{};
  if (!::GetCursorPos(&cursor) || IsOverSourceWindow(cursor)) {
    g_active.store(false);
    g_source.store(nullptr);
    ::ShowWindow(g_window, SW_HIDE);
    return;
  }

  ::ShowWindow(g_window, SW_SHOWNOACTIVATE);
  ::SetTimer(g_window, kHoldTimerId, kHoldTimeoutMs, nullptr);
}

void End() {
  g_active.store(false);
  g_source.store(nullptr);
  g_system_dragging.store(false);
  if (!g_window) return;
  ::KillTimer(g_window, kFollowTimerId);
  ::KillTimer(g_window, kHoldTimerId);
  ::ShowWindow(g_window, SW_HIDE);
  // ⚠️ גרירה שהסתיימה בהצמדה ל"מקסום" משאירה על החלון את `WS_MAXIMIZE`,
  // וכל `SetWindowPos` בגרירה הבאה מתעלם ממנו — התצוגה נשארת בגודל מסך
  // מלא. `SetWindowPlacement` עם `SW_HIDE` מנקה את המצב **בלי** להציג,
  // בעוד ש-`ShowWindow(SW_RESTORE)` היה חושף את החלון.
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (::GetWindowPlacement(g_window, &placement) &&
      placement.showCmd == SW_SHOWMAXIMIZED) {
    placement.showCmd = SW_HIDE;
    ::SetWindowPlacement(g_window, &placement);
  }
  // חזרה ל-topmost לגרירה הבאה, שמתחילה לפני שהמערכת מקבלת אותה.
  ::SetWindowPos(g_window, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}


}  // namespace drag_preview
