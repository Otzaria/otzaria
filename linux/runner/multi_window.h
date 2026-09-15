#ifndef RUNNER_MULTI_WINDOW_H_
#define RUNNER_MULTI_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

// ריבוי חלונות ב-Linux — תת-הקבוצה "פתיחת חלונות" בלבד.
//
// כל חלון הוא `GtkWindow` + `FlView` עם `FlDartProject` משלו, כלומר מנוע
// Flutter נפרד באותו תהליך — אותו מודל כמו ב-Windows וב-macOS
// (ראו docs/multi-window.md). חלון שנסגר **מוסתר ולא נהרס**, והמנוע
// שלו ממוחזר בפתיחה הבאה או משוחזר ב-`restoreLastClosedWindow`.
//
// הגרירה בין חלונות (`dragOutToSystem` ואחיותיה) אינה ממומשת כאן ומחזירה
// not-implemented: Wayland אינו מאפשר מיקום חלון או קריאת מיקום הסמן מחוץ
// לחלון, ולכן המסלול הזה דורש מנגנון אחר לגמרי.
//
// ⚠️ הקוד לא נבנה ולא הורץ על מכונת לינוקס — האימות הוא ב-CI בלבד.

// הארגומנט הראשון שמנוע של חלון משני מקבל, ואחריו המטען.
//
// ⚠️ ל-`FlDartProject` אין API לבחירת נקודת כניסה שאינה `main` (בשונה
// מ-`DartProject::set_dart_entrypoint` ב-Windows ו-`run(withEntrypoint:)`
// ב-macOS). לכן `main()` בצד Dart חייב לזהות את הדגל הזה ולהעביר את שאר
// הארגומנטים ל-`secondaryWindowMain` — זהה לדרך של `desktop_multi_window`.
#define OTZARIA_SECONDARY_WINDOW_FLAG "--otzaria-secondary-window"

// רושם את החלון הראשי ואת ה-`FlView` שלו, ומתקין על המנוע את ערוץ
// `otzaria/multiwindow`. נקרא פעם אחת מ-`my_application_activate`, **אחרי**
// `fl_register_plugins` — אחרת `window_manager` מנתק את מטפלי
// `delete-event` שקדמו לו.
void otzaria_multi_window_register_main(GtkWindow* window, FlView* view);

// מחיל את סרגל הכותרת של אוצריא: header bar ב-GNOME, כותרת מסורתית
// בשאר מנהלי החלונות ב-X11. משותף לחלון הראשי ולחלונות המשניים.
void otzaria_apply_window_titlebar(GtkWindow* window);

G_END_DECLS

#endif  // RUNNER_MULTI_WINDOW_H_
