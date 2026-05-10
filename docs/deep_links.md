# קישורי עומק (Deep Links) — סכמת `otzaria://`

## סקירה כללית

אוצריא רשומה במערכת ההפעלה כמטפלת בסכמת ה‑URI `otzaria://`, כך שכל לחיצה על קישור כזה — בדפדפן, באפליקציה אחרת, בקיצור דרך, ב‑PowerShell, או ב‑system tray — פותחת את אוצריא ומבצעת פעולה מוגדרת מראש (פתיחת מסך, פתיחת ספר, התקנת תוסף).

מטרת המסמך: לתעד את כל הכתובות הנתמכות, איך הן עובדות מאחורי הקלעים, ואיך מוסיפים יעדים חדשים.

## איפה הסכמה נרשמת

נייד (Android/iOS/macOS) — רישום סטטי דרך קונפיגורציית הפלטפורמה:

- **Android** — [`android/app/src/main/AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml) (`<intent-filter>` עם `<data android:scheme="otzaria"/>`).
- **iOS** — [`ios/Runner/Info.plist`](../ios/Runner/Info.plist) (`CFBundleURLSchemes`).
- **macOS** — [`macos/Runner/Info.plist`](../macos/Runner/Info.plist) (זהה ל‑iOS).

דסקטופ (Windows/Linux) — **רישום דינמי בזמן ריצה** דרך [`PluginProtocolRegistrationService.ensureRegistered`](../lib/plugins/services/plugin_protocol_registration_service.dart). השם ההיסטורי מטעה — השירות אינו ספציפי לתוספים, הוא רושם את כל סכמת `otzaria://`:

- **Windows** — קריאה ל‑`reg.exe` שכותבת ל‑`HKCU\Software\Classes\otzaria` עם `shell\open\command` שמכוון ל‑exe הפעיל ([`buildWindowsRegistrationCommands`](../lib/plugins/services/plugin_protocol_registration_service.dart#L136-L153)). [`windows/runner/main.cpp`](../windows/runner/main.cpp) אחראי רק על מה שקורה אחרי שה‑OS הפעיל את אוצריא עם הארגומנט (forwarding למופע קיים), לא על הרישום עצמו.
- **Linux** — יצירה דינמית של `~/.local/share/applications/otzaria.desktop` עם `MimeType=x-scheme-handler/otzaria;`, ואז `update-desktop-database` ו‑`xdg-mime default` ([`_ensureLinuxRegistration`](../lib/plugins/services/plugin_protocol_registration_service.dart#L49-L85)). אין קובץ `.desktop` סטטי במאגר.

## כתובות נתמכות

### `otzaria://open/...` — ניווט פנימי

| כתובת | תוצאה |
|--------|--------|
| `otzaria://open/calendar` | פותח את לוח השנה (לשונית במסך הכלים) |
| `otzaria://open/gematria` | פותח את כלי הגימטריה |
| `otzaria://open/notes` | פותח הערות אישיות |
| `otzaria://open/library` | פותח את מסך הספרייה |
| `otzaria://open/search` | פותח את מסך החיפוש (ללא הפעלת חיפוש) |
| `otzaria://open/search?q=<text>` | פותח לשונית חיפוש חדשה ומפעיל חיפוש מיידית בכל הספרים, עם ברירות המחדל (מצב מתקדם, scope `/`) |
| `otzaria://open/settings` | פותח את ההגדרות |
| `otzaria://open/tools` | פותח את מסך הכלים (בלשונית האחרונה שהיתה פעילה) |
| `otzaria://open/tool/<tool-id>` | פותח לשונית כלי לפי מזהה מלא — תומך גם בתוספים מוצמדים |
| `otzaria://open/book/<id>` | פותח ספר בעיון לפי מזהה מסד הנתונים |
| `otzaria://open/book/<id>?index=<n>` | פותח את הספר בסעיף `n` (אינדקס לא שלילי). |
| `otzaria://open/book/<id>?q=<text>` | פותח את הספר עם מחרוזת חיפוש להדגשה. ניתן לשלב עם `index`. |
| `otzaria://open/pdf/<id>` | פותח ספר PDF לפי מזהה משותף עם ה-TextBook במסד הנתונים |
| `otzaria://open/pdf/<id>?index=<n>` | פותח את ספר ה-PDF בעמוד `n` (מספר עמוד חיובי). |

**דוגמאות:**

```text
otzaria://open/calendar
otzaria://open/library
otzaria://open/tool/builtin.gematria
otzaria://open/tool/com.example.myplugin
otzaria://open/book/1234
otzaria://open/book/1234?index=42
otzaria://open/book/1234?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/book/1234?index=42&q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/search?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/pdf/120
otzaria://open/pdf/120?index=17
```

**הערות על קידוד:** טקסט בעברית ב‑`q=` חייב להיות URL‑encoded (UTF‑8). ערך `index` שלילי או לא מספרי מתעלם — הספר ייפתח בתחילתו. `q=` ריק מתעלם.

**רגישות לאותיות גדולות/קטנות:** הסכמה, ה‑host, ושמות הפעולה (`calendar`, `library`, `book`, `tool`, וכד') כולם case‑insensitive — `OTZARIA://OPEN/CALENDAR` ו‑`otzaria://Open/Book/1234` תקפים בדיוק כמו הצורה הקטנה. הערכים (tool id, מזהי ספרים, כתובות `url=`) נשמרים כפי שהם.

### `otzaria://plugin/install?url=...` — התקנת תוסף

קישור התקנת תוסף מהמאגר. תומך גם ב‑download URLs חיצוניים.

| פרמטר | תיאור |
|--------|--------|
| `url` (חובה) | כתובת ה‑download של חבילת ה‑`.otzplugin`. חייב להיות `http`/`https`. |
| `overwrite` (אופציונלי) | `true`/`1`/`yes`/`on` — דרוס תוסף קיים בלי לשאול. ברירת מחדל `false`. |

**דוגמה:**

```text
otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fmyplugin.otzplugin&overwrite=true
```

לאחר קבלת הקישור, אוצריא עוברת למסך הכלים ויוזמת זרימת התקנה (כולל בקשת אישור הרשאות אם נחוץ).

## איך משתמשים בקישור

### מהדפדפן

```html
<a href="otzaria://open/calendar">פתח לוח שנה</a>
```

הדפדפן יציע למשתמש לפתוח את אוצריא בפעם הראשונה ויזכור את ההסכמה לאחר מכן.

### משורת פקודה

```powershell
# Windows
Start-Process "otzaria://open/calendar"

# או דרך ShellExecute
explorer "otzaria://open/calendar"
```

```bash
# Linux
xdg-open "otzaria://open/calendar"

# macOS
open "otzaria://open/calendar"
```

### מקיצור דרך בדסקטופ (Windows)

יוצרים קובץ `.lnk` שה‑target שלו הוא:

```text
explorer.exe otzaria://open/calendar
```

או, לחלופין, קובץ `.url`:

```ini
[InternetShortcut]
URL=otzaria://open/calendar
```

### מאפליקציה אחרת

כל קוד שיכול לבצע "פתיחת URL במערכת ההפעלה" יעבוד. למשל:

```dart
// Flutter / Dart
await launchUrl(Uri.parse('otzaria://open/book/1234'));
```

```javascript
// Web
window.location.href = 'otzaria://open/calendar';
```

```csharp
// C# / .NET
System.Diagnostics.Process.Start(new ProcessStartInfo {
  FileName = "otzaria://open/calendar",
  UseShellExecute = true,
});
```

### ממגש מערכת / כפתור משולב

תשתית הקישורים זמינה — אם תרצה להוסיף קיצור דרך במגש המערכת או להטמיע כפתור באפליקציה אחרת, פשוט קרא ל‑`ShellExecute`/`launchUrl` עם הכתובת המתאימה. אין צורך בקוד מיוחד מצד אוצריא.

## איך זה עובד מאחורי הקלעים

הזרימה זהה בכל הפלטפורמות, עם הבדל אחד מרכזי בין אינסטנס יחיד לחדש:

```
            ┌──────────────────────┐
            │ Click otzaria://...  │
            └──────────┬───────────┘
                       ▼
        ┌──────────────────────────────┐
        │ OS מפעיל את אוצריא עם הארגומנט │
        └──────────────┬───────────────┘
                       ▼
            ┌──────────────────────┐
            │ אוצריא כבר רצה?      │
            └──────┬─────────┬─────┘
                  לא│        │כן
                    ▼        ▼
         ┌───────────┐   ┌────────────────────────────┐
         │ הפעלה רגילה│   │ הפרוסס המשני כותב          │
         │ + טיפול   │   │ pending_external_activations│
         │ בארגומנטים│   │ ויוצא מיד                  │
         └─────┬─────┘   └─────────────┬──────────────┘
               │                       ▼
               │       ┌─────────────────────────────────┐
               │       │ המופע הקיים זוהה את השינוי בקובץ │
               │       │ דרך file watcher                 │
               │       └─────────────┬───────────────────┘
               ▼                     ▼
         ┌────────────────────────────────────────────┐
         │ _handleExternalActivationUriString(uri)    │
         │   ↓                                        │
         │   ExternalUriRouter.parseUri               │
         │   → ExternalUriAction (sealed)             │
         └─────────────────┬──────────────────────────┘
                           ▼
                 ┌───────────────────┐
                 │ פעולה (ניווט/     │
                 │  פתיחת ספר/התקנה) │
                 └───────────────────┘
```

### Single‑instance ב‑Windows

ב‑[`windows/runner/main.cpp:104-121`](../windows/runner/main.cpp#L104-L121) משתמשים ב‑Mutex בשם `OtzariaAppSingleInstance`. אם המופע השני מזהה שהמופע הראשון כבר חי, הוא:

1. מוציא מהארגומנטים את ה‑URIs שמתחילים ב‑`otzaria:`.
2. מוסיף אותם לקובץ `%APPDATA%\otzaria\pending_external_activations.jsonl` כשורות JSONL.
3. יוצא מיד עם `EXIT_SUCCESS`.

המופע הראשון מאזין לשינויים בקובץ דרך [`ExternalActivationQueue`](../lib/core/external_activation_queue.dart) ב־[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart):

```dart
_externalActivationWatchSub = queueFile.parent.watch().listen((event) {
  if (normalizedPath != normalizedQueuePath) return;
  unawaited(_processPendingExternalActivations());
});
```

הקובץ עובר rename ל‑`.processing` בזמן הקריאה — כך שלא נאבדים URIs אם המופע הראשון נסגר באמצע.

### פענוח URI

ראוטר יחיד — [`ExternalUriRouter`](../lib/core/external_uri_router.dart) — מנתב את כל הסכמות (`open` ו‑`plugin`) לאותו `sealed class ExternalUriAction`:

| variant | מאיפה | תוכן |
|---------|--------|------|
| `OpenScreenAction(Screen)` | `otzaria://open/library`, `/settings`, ... | מסך עליון |
| `OpenToolAction(String toolId)` | `otzaria://open/calendar`, `/tool/<id>`, ... | לשונית כלי |
| `OpenBookAction(int bookId, {int? index, String? searchQuery})` | `otzaria://open/book/<id>?index=<n>&q=<text>` | ספר בעיון |
| `RunSearchAction(String query)` | `otzaria://open/search?q=<text>` | חיפוש מלא בלשונית חדשה |
| `InstallPluginAction(PluginStoreInstallRequest)` | `otzaria://plugin/install?url=...` | התקנת תוסף |

לפענוח `plugin/install` הראוטר מעביר את ה‑URI ל‑[`PluginStoreLinkParser.parseUri`](../lib/plugins/services/plugin_store_link_parser.dart) (שמרנו אותו עצמאי כדי לא לשבור את הבדיקות הקיימות), ועוטף את התוצאה ב‑`InstallPluginAction`. אין יותר נפילה אחורה בין שני פרסרים — `ExternalUriRouter.parseUri` הוא נקודת הכניסה היחידה.

### דיספצ׳ר

ב‑[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) הפונקציה `_handleExternalActivationUriString`:

1. מנסה לפענח דרך `ExternalUriRouter.parseUri`. אם `null` — מתעלמת בשקט.
2. מציפה את החלון לפני־כל (`_bringWindowToFront`) ב‑Windows/Linux/macOS.
3. `_dispatchExternalUriAction` עם `switch` יחיד על ה‑sealed class:
   - **`OpenScreenAction`** — שולח `NavigateToScreen` ל‑NavigationBloc.
   - **`OpenToolAction`** — שולח `NavigateToScreen(Screen.more)` ואז `moreScreenKey.currentState?.requestOpenTool(toolId)` עם retry מדורג ב‑`_openToolWhenAvailable` עד שה‑state מוכן. ב‑[`ToolsScreen.requestOpenTool`](../lib/tools/tools_screen.dart) יש תור pending — אם ה‑descriptor של הכלי עוד לא נטען (תוסף שעוד לא הגיע מ‑PluginSystemBloc), הבקשה מחכה לרענון הבא של descriptors. אחרי 5 שניות בלי הצלחה — `UiSnack.showError`.
   - **`OpenBookAction`** — `await DataRepository.instance.library`, מחפש לפי `b.id`. אם נמצא — `openBook(context, book, index ?? 0, searchQuery ?? '')`. אם לא — `UiSnack.showError`.
   - **`RunSearchAction`** — יוצר `SearchingTab` חדש עם הקוורי, מוסיף ל‑`HistoryBloc` ול‑`TabsBloc`, ומנווט ל‑`Screen.search`. ה‑`UpdateSearchQuery` מופעל אוטומטית מ‑`TantivyFullTextSearch.initState` ברגע שהלשונית מוצגת.
   - **`InstallPluginAction`** — `NavigateToScreen(Screen.more)` + `InstallRemotePluginRequested` ל‑PluginSystemBloc.

## הוספת יעד חדש

נניח שרוצים להוסיף `otzaria://open/bookmarks` שיפתח את מסך הסימניות.

### 1. הגדרת alias בראוטר

ב‑[`lib/core/external_uri_router.dart`](../lib/core/external_uri_router.dart), בתוך `_screenAliases` (אם זה מסך עליון):

```dart
static const Map<String, Screen> _screenAliases = {
  'library': Screen.library,
  // ...
  'bookmarks': Screen.bookmarks,  // ← חדש
};
```

אם זו פעולה חדשה לגמרי (לא מסך/כלי/ספר), צור variant חדש ב‑`sealed class ExternalUriAction`:

```dart
class OpenBookmarksAction extends ExternalUriAction {
  const OpenBookmarksAction();
}
```

ועדכן את `ExternalUriRouter.parseUri` (או את `_parseOpen`) כדי להחזיר אותו.

### 2. דיספצ׳ר

ב‑[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) ב‑`_dispatchExternalUriAction`, הוסף `case`:

```dart
case OpenBookmarksAction():
  context.read<NavigationBloc>().add(const NavigateToScreen(Screen.bookmarks));
```

הקומפיילר אוכף exhaustive matching על ה‑`sealed class`, אז אם תשכח להוסיף — תקבל שגיאת קומפילציה.

### 3. בדיקות

הוסף ב‑[`test/core/external_uri_router_test.dart`](../test/core/external_uri_router_test.dart) מקרי בדיקה — כתובת תקינה, כתובות שאמורות להידחות, ובדיקת case‑insensitivity.

### 4. עדכון תיעוד

הוסף שורה לטבלת ה־"כתובות נתמכות" במסמך זה.

## אבטחה ושיקולי שימוש

- **אין התקנה אוטומטית של תוספים ללא אישור משתמש.** גם עם `overwrite=true`, המשתמש רואה את שמות הקבצים והרשאות התוסף לפני ההתקנה בפועל.
- **לא ניתן להעביר נתיבי קבצים מקומיים** (`file://`) ב‑`plugin/install` — הסכמה נדחית בכוונה כדי למנוע ניצול לרעה.
- **קישור ל‑URL לא קיים** (למשל `otzaria://open/banana`) פשוט מוחזר `null` ואוצריא מתעלמת בשקט. אין הודעת שגיאה — זה עיצובית מכוון, כדי לא להפחיד משתמשים שלחצו על קישור עתידי.
- **קישור לספר עם ID לא קיים** מציג `UiSnack.showError` בעברית. זאת בכוונה כדי שהמשתמש יבין שהקישור לא תקף בספרייה שלו.

## קבצים מרכזיים

| קובץ | תפקיד |
|--------|--------|
| [`lib/core/external_uri_router.dart`](../lib/core/external_uri_router.dart) | ראוטר אחיד + sealed `ExternalUriAction` (`OpenScreen`/`OpenTool`/`OpenBook`/`InstallPlugin`) |
| [`lib/plugins/services/plugin_store_link_parser.dart`](../lib/plugins/services/plugin_store_link_parser.dart) | פענוח פנימי של `plugin/install` (משמש את הראוטר) |
| [`lib/plugins/services/plugin_protocol_registration_service.dart`](../lib/plugins/services/plugin_protocol_registration_service.dart) | רישום דינמי של סכמת `otzaria://` ב‑Windows ובלינוקס בזמן ריצה |
| [`lib/core/external_activation_queue.dart`](../lib/core/external_activation_queue.dart) | תור JSONL להעברת URIs בין מופעים |
| [`lib/core/external_activation_channel.dart`](../lib/core/external_activation_channel.dart) | ערוץ פלטפורמה ל‑URIs שמגיעים בזמן ריצה (Android/iOS) |
| [`lib/navigation/view/main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) | מאזין, פענוח ודיספצ׳ר (ראה `_handleExternalActivationUriString` ו‑`_dispatchExternalUriAction`) |
| [`lib/tools/tools_screen.dart`](../lib/tools/tools_screen.dart) | `requestOpenTool` עם תור pending לתוספים שטרם נטענו |
| [`windows/runner/main.cpp`](../windows/runner/main.cpp) | זיהוי single‑instance + העברת ארגומנטים לתור (לא רישום) |
| [`test/core/external_uri_router_test.dart`](../test/core/external_uri_router_test.dart) | בדיקות הראוטר האחיד |
| [`test/plugins/services/plugin_store_link_parser_test.dart`](../test/plugins/services/plugin_store_link_parser_test.dart) | בדיקות פרסר התקנת תוסף |
