#include "multi_window.h"

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// נדרשים ל-`register_plugins_for_secondary_window`, שרושם תת-קבוצה של
// התוספים. `generated_plugin_registrant.h` לבדו רושם הכול או כלום.
//
// ⚠️ `printing` ו-`sentry_flutter` אינם כאן בכוונה: הראשון מחזיק ערוץ
// יחיד ב-namespace scope (`printing_plugin.cc:37`) שרישום שני דורס, והשני
// מגדיר את ה-registrar **בתוך הכותרת** — הכללתו בשני קבצי מקור היא הגדרה
// כפולה בקישור. ראו הטבלה למטה.
#include <custom_mouse_cursor/custom_mouse_cursor_plugin.h>
#include <file_selector_linux/file_selector_plugin.h>
#include <flutter_inappwebview_linux/flutter_inappwebview_linux_plugin.h>
#include <irondash_engine_context/irondash_engine_context_plugin.h>
#include <screen_retriever_linux/screen_retriever_linux_plugin.h>
#include <super_native_extensions/super_native_extensions_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>
#include <window_manager/window_manager_plugin.h>
#include <zstandard_linux/zstandard_linux_plugin.h>

namespace {

// תקרת חלונות. כל חלון הוא מנוע Flutter מלא, ולכן זו הגבלת משאבים ולא
// העדפת ממשק — אותו ערך כמו ב-Windows וב-macOS.
constexpr int kMaxWindows = 4;

// מידות ברירת מחדל (לוגיות) כשהפותח לא מסר מידות סבירות.
constexpr int kDefaultWidth = 1100;
constexpr int kDefaultHeight = 760;

// רשת ביטחון לחשיפה: אם Dart לא שלח "close" בערוץ ה-splash, חלון
// בלתי-נראה לתמיד גרוע מחלון שמופיע מאוחר.
constexpr guint kRevealTimeoutSeconds = 20;

// חלון אוצריא יחיד — הראשי או משני — כפי שמנהל החלונות רואה אותו.
struct WindowEntry {
  GtkWindow* window = nullptr;
  FlView* view = nullptr;
  FlMethodChannel* channel = nullptr;         // otzaria/multiwindow
  FlMethodChannel* splash_channel = nullptr;  // חלון משני בלבד
  bool is_main = false;
  // המשתמש סגר את החלון: הוא מוסתר ולא נהרס, והמנוע שלו נשאר חם.
  bool closed_by_user = false;
  // חלון משני נחשף רק כשיש לו תוכן (ערוץ ה-splash) או בפקיעת הזמן.
  bool revealed = false;
  // סידורי ההסתרה — קובע מי משוחזר ב"שחזר חלון אחרון".
  uint64_t hidden_at = 0;
  // המשבצת באפיק ההודעות של Dart; 0 = טרם נמסרה.
  int bus_slot = 0;
  guint reveal_timeout_id = 0;
};

// כל החלונות שנוצרו בתהליך. רשומה אינה משוחררת לעולם: חלון אינו נהרס
// אלא מוסתר, ואם בכל זאת נהרס (סגירת התוכנה) הוא מוסר מהרשימה.
std::vector<WindowEntry*>& Entries() {
  static std::vector<WindowEntry*> entries;
  return entries;
}

// מנועים שנוצרו. אינו יורד לעולם — מנוע אינו נהרס עם החלון, ולכן התקרה
// נאכפת גם עליו ולא רק על החלונות הגלויים.
int g_engines_created = 0;
uint64_t g_hidden_sequence = 0;
int g_spawn_index = 0;
GtkWindow* g_last_active_window = nullptr;

// מספר החלונות שהמשתמש רואה כפתוחים. חלון שנסגר מוסתר ואינו נספר.
int LiveWindowCount() {
  int count = 0;
  for (const WindowEntry* entry : Entries()) {
    if (!entry->closed_by_user) ++count;
  }
  return count;
}

WindowEntry* MainEntry() {
  for (WindowEntry* entry : Entries()) {
    if (entry->is_main) return entry;
  }
  return nullptr;
}

bool IsShown(const WindowEntry* entry) {
  return !entry->closed_by_user && entry->window != nullptr &&
         gtk_widget_get_visible(GTK_WIDGET(entry->window));
}

// ── רישום תוספים לחלון משני ─────────────────────────────────────────────

struct PluginEntry {
  const char* name;
  void (*fn)(FlPluginRegistrar*);
};

// אותם תוספים ובאותו סדר כמו `generated_plugin_registrant.cc`; `nullptr`
// פירושו "מדולג בחלון משני". `linux_plugin_registrant_parity_test` שומר
// שהרשימה לא תישאר מאחור כשנוסף תוסף.
//
// ⚠️ `PrintingPlugin` מדולג: `printing_plugin.cc:37` מחזיק
// `static FlMethodChannel* channel` יחיד ומשייך אליו מחדש בכל רישום, וכל
// קולבק הדפסה — גם של החלון הראשון — היה מנותב למנוע שנרשם אחרון. עדיף
// שהדפסה מחלון משני תיכשל מיד מאשר שתשבור את החלון הראשון.
// `SentryFlutterPlugin` הוא stub ריק (ראו ההערה בהכללות).
const PluginEntry kSecondaryWindowPlugins[] = {
    {"CustomMouseCursorPlugin",
     custom_mouse_cursor_plugin_register_with_registrar},
    {"FileSelectorPlugin", file_selector_plugin_register_with_registrar},
    {"FlutterInappwebviewLinuxPlugin",
     flutter_inappwebview_linux_plugin_register_with_registrar},
    {"IrondashEngineContextPlugin",
     irondash_engine_context_plugin_register_with_registrar},
    {"PrintingPlugin", nullptr},
    {"ScreenRetrieverLinuxPlugin",
     screen_retriever_linux_plugin_register_with_registrar},
    {"SentryFlutterPlugin", nullptr},
    {"SuperNativeExtensionsPlugin",
     super_native_extensions_plugin_register_with_registrar},
    {"UrlLauncherPlugin", url_launcher_plugin_register_with_registrar},
    {"WindowManagerPlugin", window_manager_plugin_register_with_registrar},
    {"ZstandardLinuxPlugin", zstandard_linux_plugin_register_with_registrar},
};

void RegisterPluginsForSecondaryWindow(FlPluginRegistry* registry) {
  for (const PluginEntry& plugin : kSecondaryWindowPlugins) {
    if (plugin.fn == nullptr) continue;
    g_autoptr(FlPluginRegistrar) registrar =
        fl_plugin_registry_get_registrar_for_plugin(registry, plugin.name);
    plugin.fn(registrar);
  }
}

// ── קריאת ארגומנטים ─────────────────────────────────────────────────────

std::string StringArg(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return "";
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return "";
  }
  return fl_value_get_string(value);
}

int IntArg(FlValue* map, const char* key, int fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return static_cast<int>(fl_value_get_int(value));
}

void RespondSuccess(FlMethodCall* call, FlValue* value) {
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond_success(call, value, &error)) {
    g_warning("otzaria/multiwindow: respond failed: %s", error->message);
  }
}

// ── חשיפה, הסתרה ושחזור ─────────────────────────────────────────────────

void Reveal(WindowEntry* entry) {
  if (entry->reveal_timeout_id != 0) {
    g_source_remove(entry->reveal_timeout_id);
    entry->reveal_timeout_id = 0;
  }
  if (entry->revealed || entry->closed_by_user) return;
  entry->revealed = true;
  gtk_widget_show(GTK_WIDGET(entry->window));
  gtk_window_present(entry->window);
}

gboolean OnRevealTimeout(gpointer user_data) {
  auto* entry = static_cast<WindowEntry*>(user_data);
  entry->reveal_timeout_id = 0;
  Reveal(entry);
  return G_SOURCE_REMOVE;
}

void Hide(WindowEntry* entry) {
  if (entry->closed_by_user) return;
  entry->closed_by_user = true;
  entry->hidden_at = ++g_hidden_sequence;
  gtk_widget_hide(GTK_WIDGET(entry->window));
  if (LiveWindowCount() > 0) return;
  // ⚠️ נסגר החלון האחרון בלי שעבר את מסלול הסגירה של Dart (שם
  // `windowCount() <= 1` מוביל לכיבוי מלא). אין מה לשטוף — רק לצאת.
  // לא `g_application_quit`: יציאה מלולאת GTK הורסת את ה-FlView-ים ואת
  // המנועים על ה-thread הראשי, ובדיוק זה נמדד כקורס ב-Windows.
  exit(0);
}

void Revive(WindowEntry* entry, const std::string& payload, int width,
            int height) {
  entry->closed_by_user = false;
  if (width > 400 && height > 300) {
    // המידות מ-Dart הן לוגיות — אותה יחידה של GTK, ואין כאן המרת DPI.
    gtk_window_resize(entry->window, width, height);
  }
  entry->revealed = true;
  gtk_widget_show(GTK_WIDGET(entry->window));
  gtk_window_present(entry->window);
  // המנוע כבר רץ ונקודת הכניסה שלו הורצה מזמן, ולכן המטען מגיע בערוץ.
  if (entry->channel != nullptr && !payload.empty()) {
    g_autoptr(FlValue) args = fl_value_new_string(payload.c_str());
    fl_method_channel_invoke_method(entry->channel, "adoptPayload", args,
                                    nullptr, nullptr, nullptr);
  }
}

WindowEntry* LastClosedEntry() {
  WindowEntry* newest = nullptr;
  for (WindowEntry* entry : Entries()) {
    if (!entry->closed_by_user) continue;
    if (newest == nullptr || entry->hidden_at > newest->hidden_at) {
      newest = entry;
    }
  }
  return newest;
}

bool RestoreLastClosedWindow() {
  WindowEntry* newest = LastClosedEntry();
  if (newest == nullptr) return false;
  // בלי מטען: הכרטיסיות שהיו בחלון עדיין שם.
  Revive(newest, std::string(), 0, 0);
  return true;
}

// המשבצת של החלון הגלוי שהופעל אחרון; 0 כשאין כזה.
//
// ⚠️ חלון מוסתר (כזה שהמשתמש סגר) לעולם אינו נבחר — קישור חיצוני היה
// מקפיץ אותו למסך. כשאין מועמד מוחזרת המשבצת הגלויה הנמוכה ביותר.
int LastActiveSlot() {
  for (const WindowEntry* entry : Entries()) {
    if (entry->window == g_last_active_window && IsShown(entry) &&
        entry->bus_slot > 0) {
      return entry->bus_slot;
    }
  }
  int fallback = 0;
  for (const WindowEntry* entry : Entries()) {
    if (!IsShown(entry) || entry->bus_slot <= 0) continue;
    if (fallback == 0 || entry->bus_slot < fallback) fallback = entry->bus_slot;
  }
  return fallback;
}

// ── אותות GTK ──────────────────────────────────────────────────────────

void OnIsActiveChanged(GObject* object, GParamSpec*, gpointer) {
  GtkWindow* window = GTK_WINDOW(object);
  if (gtk_window_is_active(window)) g_last_active_window = window;
}

// חלון משני שנסגר מה-X כשאף מטפל לא עצר את האירוע.
//
// ⚠️ בדרך כלל לא מגיעים לכאן: `window_manager` מחובר לפני ומחזיר TRUE
// כל עוד `setPreventClose(true)` פעיל, ו-Dart סוגר דרך `closeSelf`. זו
// רשת ביטחון לחלון באמצע עלייה — הריסת GtkWindow הורסת את המנוע שלו.
gboolean OnSecondaryDeleteEvent(GtkWidget*, GdkEvent*, gpointer user_data) {
  Hide(static_cast<WindowEntry*>(user_data));
  return TRUE;
}

void OnWindowDestroyed(GtkWidget*, gpointer user_data) {
  auto* entry = static_cast<WindowEntry*>(user_data);
  if (entry->reveal_timeout_id != 0) {
    g_source_remove(entry->reveal_timeout_id);
    entry->reveal_timeout_id = 0;
  }
  if (g_last_active_window == entry->window) g_last_active_window = nullptr;
  g_clear_object(&entry->channel);
  g_clear_object(&entry->splash_channel);
  entry->window = nullptr;
  entry->view = nullptr;
  auto& entries = Entries();
  for (auto it = entries.begin(); it != entries.end(); ++it) {
    if (*it == entry) {
      entries.erase(it);
      break;
    }
  }
  delete entry;
}

// ── יצירת חלון משני ────────────────────────────────────────────────────

void MultiWindowMethodCallCb(FlMethodChannel*, FlMethodCall* call,
                             gpointer user_data);
void SecondarySplashMethodCallCb(FlMethodChannel*, FlMethodCall* call,
                                 gpointer user_data);

void InstallMultiWindowChannel(WindowEntry* entry) {
  FlEngine* engine = fl_view_get_engine(entry->view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  entry->channel = fl_method_channel_new(messenger, "otzaria/multiwindow",
                                         FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      entry->channel, MultiWindowMethodCallCb, entry, nullptr);
  g_signal_connect(entry->window, "notify::is-active",
                   G_CALLBACK(OnIsActiveChanged), nullptr);
  g_signal_connect(entry->window, "destroy", G_CALLBACK(OnWindowDestroyed),
                   entry);
}

// היסט מדורג מהחלון שפתח אותנו. best-effort: Wayland מתעלם מ-`gtk_window_move`
// והקומפוזיטור ממקם בעצמו; ב-X11 זה נותן את הקסקדה המוכרת.
void PlaceCascading(GtkWindow* window, GtkWindow* opener) {
  gint x = 0;
  gint y = 0;
  if (opener != nullptr) gtk_window_get_position(opener, &x, &y);
  const int offset = 40 + (g_spawn_index++ % 6) * 32;
  gtk_window_move(window, x + offset, y + offset);
}

bool CreateSecondaryWindow(const std::string& payload, int width, int height,
                           GtkWindow* opener) {
  WindowEntry* main_entry = MainEntry();
  if (main_entry == nullptr || main_entry->window == nullptr) return false;
  GtkApplication* app = gtk_window_get_application(main_entry->window);
  if (app == nullptr) return false;

  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(app));
  otzaria_apply_window_titlebar(window);
  // המידות מ-Dart לוגיות; נופלים לברירת מחדל כשלא הגיעו מידות סבירות.
  gtk_window_set_default_size(window, width > 400 ? width : kDefaultWidth,
                              height > 300 ? height : kDefaultHeight);
  PlaceCascading(window, opener);

  // ⚠️ המטען עובר כארגומנט לנקודת הכניסה ולא בערוץ: החלון עוד לא קיים
  // בזמן הקריאה. הדגל שלפניו הוא מה שמפנה את `main()` ל-`secondaryWindowMain`
  // (ראו OTZARIA_SECONDARY_WINDOW_FLAG). `set_dart_entrypoint_arguments`
  // מעתיק את המערך, ולכן משוחרר כאן.
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  gchar* argv[] = {g_strdup(OTZARIA_SECONDARY_WINDOW_FLAG),
                   g_strdup(payload.c_str()), nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(project, argv);
  g_free(argv[0]);
  g_free(argv[1]);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  // כמו בחלון הראשי: ה-realize מתניע את המנוע בעוד החלון מוסתר, והחלון
  // נחשף רק כשיש תוכן (ערוץ ה-splash) — בלי ריצוד של חלון ריק.
  gtk_widget_realize(GTK_WIDGET(view));
  ++g_engines_created;

  RegisterPluginsForSecondaryWindow(FL_PLUGIN_REGISTRY(view));

  auto* entry = new WindowEntry();
  entry->window = window;
  entry->view = view;
  entry->is_main = false;
  Entries().push_back(entry);
  InstallMultiWindowChannel(entry);

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  entry->splash_channel = fl_method_channel_new(messenger, "otzaria/splash",
                                                FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      entry->splash_channel, SecondarySplashMethodCallCb, entry, nullptr);

  // ⚠️ אחרי רישום התוספים: `window_manager` מנתק מטפל `delete-event`
  // קיים בזמן הרישום שלו, ומטפל שנחבר קודם היה נעלם.
  g_signal_connect(window, "delete-event", G_CALLBACK(OnSecondaryDeleteEvent),
                   entry);
  entry->reveal_timeout_id =
      g_timeout_add_seconds(kRevealTimeoutSeconds, OnRevealTimeout, entry);
  gtk_widget_grab_focus(GTK_WIDGET(view));
  return true;
}

// בקשת פתיחה שממתינה לסבב הבא של לולאת GTK.
struct PendingOpen {
  FlMethodCall* call = nullptr;  // ref משלנו
  std::string payload;
  int width = 0;
  int height = 0;
  GtkWindow* opener = nullptr;
};

gboolean OnOpenWindowIdle(gpointer user_data) {
  auto* pending = static_cast<PendingOpen*>(user_data);
  bool created = false;
  // ⚠️ מיחזור לפני יצירה. חלון שנסגר מוסתר והמנוע שלו חם, ושימוש חוזר
  // בו חוסך את כל האתחול וגם מונע גידול בזיכרון במחזורי פתיחה-סגירה.
  if (WindowEntry* reusable = LastClosedEntry()) {
    Revive(reusable, pending->payload, pending->width, pending->height);
    created = true;
  } else if (g_engines_created < kMaxWindows &&
             LiveWindowCount() < kMaxWindows) {
    created = CreateSecondaryWindow(pending->payload, pending->width,
                                    pending->height, pending->opener);
  }
  // ⚠️ **כאן** נענה Dart, ולא בטיפול בערוץ. זו התשובה שעל פיה הוא מוחק
  // את הכרטיסיה מהחלון המקורי, ולכן היא חייבת לתאר את מה שקרה בפועל.
  g_autoptr(FlValue) result = fl_value_new_bool(created);
  RespondSuccess(pending->call, result);
  g_object_unref(pending->call);
  delete pending;
  return G_SOURCE_REMOVE;
}

// ── הערוצים ─────────────────────────────────────────────────────────────

// ערוץ `otzaria/multiwindow`, על **כל** מנוע. ה-isolate של כל חלון רואה
// רק את עצמו, ולכן הנייטיב הוא מקור האמת לספירה, לנראות ולחלון הפעיל.
void MultiWindowMethodCallCb(FlMethodChannel*, FlMethodCall* call,
                             gpointer user_data) {
  auto* entry = static_cast<WindowEntry*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (strcmp(method, "windowCount") == 0) {
    g_autoptr(FlValue) info = fl_value_new_map();
    fl_value_set_string_take(info, "count", fl_value_new_int(LiveWindowCount()));
    fl_value_set_string_take(info, "max", fl_value_new_int(kMaxWindows));
    // ⚠️ מנועים ולא חלונות: חלון סגור מוסתר ולא נהרס, והמנוע שלו נספר
    // כאן ולא ב-`count`. ההבדל קובע אם `exit()` בטוח בצד Dart.
    fl_value_set_string_take(info, "engines",
                             fl_value_new_int(g_engines_created));
    RespondSuccess(call, info);
    return;
  }
  if (strcmp(method, "openWindow") == 0) {
    // ⚠️ נדחה לסבב הבא של לולאת GTK. הקריאה מגיעה מתוך טיפול בערוץ, כלומר
    // מתוך ריצת ה-Dart של החלון הזה, ויצירת מנוע נוסף משם ריאנטרנטית.
    // `originX`/`originY`/`bounds` שייכים למסלול הגרירה, שאינו ממומש כאן.
    auto* pending = new PendingOpen();
    pending->call = FL_METHOD_CALL(g_object_ref(call));
    pending->payload = StringArg(args, "payload");
    pending->width = IntArg(args, "width", 0);
    pending->height = IntArg(args, "height", 0);
    pending->opener = entry->window;
    g_idle_add(OnOpenWindowIdle, pending);
    return;
  }
  if (strcmp(method, "closeSelf") == 0) {
    // הסתרה ולא הריסה, בדחייה — מאותה סיבה כמו הפתיחה.
    g_idle_add(
        [](gpointer data) -> gboolean {
          Hide(static_cast<WindowEntry*>(data));
          return G_SOURCE_REMOVE;
        },
        entry);
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "raiseSelf") == 0) {
    if (entry->closed_by_user) {
      // ⚠️ חלון שהמשתמש סגר חוזר רק דרך `Revive`, שמחזיר גם את הספירה.
      Revive(entry, std::string(), 0, 0);
    } else if (entry->window != nullptr) {
      gtk_window_present(entry->window);
    }
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "setBusSlot") == 0) {
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_INT) {
      entry->bus_slot = static_cast<int>(fl_value_get_int(args));
    }
    RespondSuccess(call, nullptr);
    return;
  }
  if (strcmp(method, "visibleSlots") == 0) {
    g_autoptr(FlValue) slots = fl_value_new_list();
    for (const WindowEntry* candidate : Entries()) {
      if (IsShown(candidate) && candidate->bus_slot > 0) {
        fl_value_append_take(slots, fl_value_new_int(candidate->bus_slot));
      }
    }
    RespondSuccess(call, slots);
    return;
  }
  if (strcmp(method, "lastActiveSlot") == 0) {
    const int slot = LastActiveSlot();
    if (slot > 0) {
      g_autoptr(FlValue) value = fl_value_new_int(slot);
      RespondSuccess(call, value);
    } else {
      RespondSuccess(call, nullptr);
    }
    return;
  }
  if (strcmp(method, "restoreLastClosedWindow") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(RestoreLastClosedWindow());
    RespondSuccess(call, value);
    return;
  }
  // ⚠️ כולל את מתודות הגרירה (`windowAtCursor`, `screenToClient`,
  // `dragOutToSystem`, `beginTabDrag`, `setTabDragImage`, `freezeTabDrag`,
  // `endTabDrag`). הצד של Dart עוטף כל אחת וממפה כשל ל"לא ידוע".
  g_autoptr(GError) error = nullptr;
  fl_method_call_respond_not_implemented(call, &error);
}

// ערוץ ה-splash של חלון משני. "close" מגיע בסוף האתחול של Dart
// (`presentMainWindow`), וזהו הרגע שבו יש תוכן להציג. "cloak" הוא
// Windows-only בצד Dart ונענה בהצלחה ריקה ליתר ביטחון.
void SecondarySplashMethodCallCb(FlMethodChannel*, FlMethodCall* call,
                                 gpointer user_data) {
  auto* entry = static_cast<WindowEntry*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  if (strcmp(method, "close") == 0) {
    Reveal(entry);
    RespondSuccess(call, nullptr);
  } else if (strcmp(method, "cloak") == 0) {
    RespondSuccess(call, nullptr);
  } else {
    g_autoptr(GError) error = nullptr;
    fl_method_call_respond_not_implemented(call, &error);
  }
}

}  // namespace

void otzaria_multi_window_register_main(GtkWindow* window, FlView* view) {
  if (MainEntry() != nullptr) return;
  auto* entry = new WindowEntry();
  entry->window = window;
  entry->view = view;
  entry->is_main = true;
  entry->revealed = true;  // החשיפה של הראשי היא של Dart (`windowManager.show`).
  Entries().push_back(entry);
  g_engines_created = 1;
  InstallMultiWindowChannel(entry);
}

void otzaria_apply_window_titlebar(GtkWindow* window) {
  // Header bar ב-GNOME, כי זה הסגנון המקובל שם; ב-X11 עם מנהל חלונות
  // אחר — כותרת מסורתית, למקרה של פריסה חריגה (tiling). ב-Wayland מניחים
  // ש-header bar יעבוד.
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "אוצריא");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "אוצריא");
  }
}
