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
| `otzaria://open/shamor_zachor` | פותח שמור וזכור |
| `otzaria://open/measurements` | פותח מדות ושיעורים |
| `otzaria://open/aramaic_dictionary` | פותח מילון ארמי-עברי |
| `otzaria://open/acronyms_dictionary` | פותח ראשי תיבות |
| `otzaria://open/library` | פותח את מסך הספרייה |
| `otzaria://open/search` | פותח את מסך החיפוש (ללא הפעלת חיפוש) |
| `otzaria://open/search?q=<text>` | פותח לשונית חיפוש חדשה ומפעיל חיפוש מיידית בכל הספרים, עם ברירות המחדל (מצב מתקדם, scope `/`) |
| `otzaria://open/search?q=<text>&mode=<mode>` | כנ"ל, עם קביעת מצב החיפוש ללשונית: `advanced` (מתקדם), `exact` (מדויק) או `fuzzy` (מקורב). ערך לא מוכר מתעלם — מצב מתקדם |
| `otzaria://open/settings` | פותח את ההגדרות (הלשונית הנוכחית) |
| `otzaria://open/settings/design` | פותח הגדרות › מראה |
| `otzaria://open/settings/text` | פותח הגדרות › כתב |
| `otzaria://open/settings/library` | פותח הגדרות › ספרייה |
| `otzaria://open/settings/tools` | פותח הגדרות › כלים |
| `otzaria://open/settings/shortcuts` | פותח הגדרות › קיצורים |
| `otzaria://open/settings/system` | פותח הגדרות › מערכת |
| `otzaria://open/settings/about` | פותח הגדרות › אודות |
| `otzaria://open/tools` | פותח את פאנל הכלים (רשת הקוביות עם חיפוש) |
| `otzaria://open/history` | פותח את דיאלוג ההיסטוריה |
| `otzaria://open/bookmarks` | פותח את דיאלוג הסימניות |
| `otzaria://open/detection?q=<text>` | פותח את דיאלוג איתור מקורות עם טקסט מילוי-מראש ומפעיל חיפוש מיידית |
| `otzaria://open/detection` | פותח את דיאלוג איתור מקורות ריק |
| `otzaria://open/inspection` | פותח את מסך העיון (הספר האחרון שנפתח) |
| `otzaria://open/sdk` | פותח את הגדרות › כלים (ניהול תוספים) |
| `otzaria://open/daily_page` | פותח את הדף היומי (PDF תלמוד בבלי בדף הנכון ליום) |
| `otzaria://open/tool/<tool-id>` | פותח כרטיסיית כלי בעיון לפי מזהה מלא — תומך גם בתוספים |
| `otzaria://open/plugin/<plugin-id>` | פותח כרטיסיית תוסף בעיון לפי מזהה התוסף |
| `otzaria://open/tab/<index>` | מעבר לטאב פתוח לפי מיקומו (0-based). אינו פותח טאב חדש; אם המיקום לא קיים — מתעלם. נבנה אוטומטית ב-Jump List של שורת המשימות (Windows) |
| `otzaria://open/book/<id>` | פותח ספר בעיון לפי מזהה מסד הנתונים |
| `otzaria://open/book/<id>?index=<n>` | פותח את הספר בסעיף `n` (אינדקס לא שלילי). |
| `otzaria://open/book/<id>?q=<text>` | פותח את הספר עם מחרוזת חיפוש להדגשה. ניתן לשלב עם `index`. |
| `otzaria://open/book/<id>?index=<n>&mark` | פותח את הספר בסעיף `n` ומדגיש את כל רקע המקטע בצהוב. |
| `otzaria://open/book/<id>?index=<n>&m=<text>` | פותח את הספר בסעיף `n` ומדגיש את הטקסט `text` בצהוב בתוך המקטע. |
| `otzaria://open/pdf/<id>` | פותח ספר PDF לפי מזהה משותף עם ה-TextBook במסד הנתונים |
| `otzaria://open/pdf/<id>?index=<n>` | פותח את ספר ה-PDF בעמוד `n` (מספר עמוד חיובי). |

**דוגמאות:**

```text
otzaria://open/calendar
otzaria://open/shamor_zachor
otzaria://open/measurements
otzaria://open/aramaic_dictionary
otzaria://open/acronyms_dictionary
otzaria://open/library
otzaria://open/history
otzaria://open/bookmarks
otzaria://open/settings
otzaria://open/detection
otzaria://open/detection?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/inspection
otzaria://open/sdk
otzaria://open/daily_page
otzaria://open/settings/design
otzaria://open/settings/text
otzaria://open/settings/library
otzaria://open/settings/tools
otzaria://open/settings/shortcuts
otzaria://open/settings/system
otzaria://open/settings/about
otzaria://open/tool/builtin.gematria
otzaria://open/tool/com.example.myplugin
otzaria://open/plugin/com.example.myplugin
otzaria://open/book/1234
otzaria://open/book/1234?index=42
otzaria://open/book/1234?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/book/1234?index=42&q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/book/1234?index=42&mark
otzaria://open/book/1234?index=42&m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/search?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/search?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA&mode=exact
otzaria://open/search?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA&mode=fuzzy
otzaria://open/pdf/120
otzaria://open/pdf/120?index=17
otzaria://open/detection?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
```

**הערות על קידוד:** טקסט בעברית ב‑`q=` ו-`m=` חייב להיות URL‑encoded (UTF‑8). ערך `index` שלילי או לא מספרי מתעלם — הספר ייפתח בתחילתו. `q=` ריק מתעלם. `m=` ריק או רווחים בלבד מתעלם. לגבי `detection?q=` — חובה לספק ערך לא-ריק; קישור ללא `q=` מתעלם לחלוטין.

**הבדל בין `mark` ל-`m=`:**
- `?mark` — מדגיש את **כל רקע המקטע** בצהוב (הדגשת שורה שלמה).
- `?m=<text>` — מדגיש **טקסט ספציפי** בתוך המקטע בצהוב (הדגשת מילים בלבד).
- ניתן לשלב `mark` עם `q=` (חיפוש פעיל + הדגשת שורה).
- ניתן לשלב `m=` עם `q=` (חיפוש פעיל + הדגשת טקסט ספציפי).

**`tool/<id>` מול `plugin/<id>`:** שניהם מנותבים כיום לאותה פונקציה — `openToolTabById` — ופותחים כרטיסיית כלי במסך העיון. ההבחנה נשמרה לתאימות אחורה בלבד. כלי שכבר פתוח מקבל מיקוד במקום כרטיסיה נוספת. כלי מוסתר, תוסף מושבת או תוסף שדורש רשת במצב מנותק — מציגים `UiSnack.showError` עם הסיבה. כשמערכת התוספים עדיין נטענת הכרטיסיה נפתחת מיד ומציגה מחוון טעינה עד שהמצב ידוע.

**רגישות לאותיות גדולות/קטנות:** הסכמה, ה‑host, ושמות הפעולה (`calendar`, `library`, `book`, `tool`, `plugin`, וכד') כולם case‑insensitive — `OTZARIA://OPEN/CALENDAR` ו‑`otzaria://Open/Book/1234` תקפים בדיוק כמו הצורה הקטנה. הערכים (tool id, plugin id, מזהי ספרים, כתובות `url=`) נשמרים כפי שהם.

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
| `OpenScreenAction(Screen)` | `otzaria://open/library`, ... | מסך עליון |
| `OpenToolAction(String toolId)` | `otzaria://open/calendar`, `/daily`, `/shamor_zachor`, `/measurements`, `/aramaic_dictionary`, `/acronyms_dictionary`, `/gematria`, `/notes`, `/tool/<id>`, ... | לשונית כלי |
| `OpenPluginAction(String pluginId)` | `otzaria://open/plugin/<plugin-id>` | פתיחת תוסף ישירות (גם לא-מוצמד) |
| `SwitchToTabAction(int index)` | `otzaria://open/tab/<index>` | מעבר לטאב פתוח קיים לפי מיקומו (Jump List של Windows) |
| `OpenBookAction(int bookId, {int? index, String? searchQuery, bool markSection, String? markText})` | `otzaria://open/book/<id>?index=<n>&q=<text>&mark&m=<text>` | ספר בעיון |
| `OpenSettingsTabAction({SettingsTab? tab})` | `otzaria://open/settings`, `/settings/design`, `/settings/text`, ... | פתיחת הגדרות, אופציונלית עם ניווט לטאב |
| `OpenHistoryAction()` | `otzaria://open/history` | דיאלוג היסטוריה |
| `OpenBookmarksAction()` | `otzaria://open/bookmarks` | דיאלוג סימניות |
| `RunSearchAction(String query, {SearchMode? mode})` | `otzaria://open/search?q=<text>&mode=<advanced\|exact\|fuzzy>` | חיפוש מלא בלשונית חדשה, אופציונלית עם מצב חיפוש |
| `RunDetectionAction(String query)` | `otzaria://open/detection?q=<text>`, `otzaria://open/detection` | פתיחת דיאלוג איתור מקורות (ריק או עם טקסט) |
| `OpenInspectionAction()` | `otzaria://open/inspection` | מסך העיון (ספר אחרון) |
| `OpenSdkAction()` | `otzaria://open/sdk` | פתיחת דיאלוג ניהול תוספים |
| `OpenDailyPageAction()` | `otzaria://open/daily_page` | פתיחת ה-PDF של תלמוד בבלי בדף הנכון ליום |
| `InstallPluginAction(PluginStoreInstallRequest)` | `otzaria://plugin/install?url=...` | התקנת תוסף מהחנות |
| `InstallLocalPluginAction(String archivePath)` | `otzaria://plugin/install-local?path=<abs>` | התקנת תוסף מקובץ `.otzplugin` מקומי (לחיצה כפולה על קובץ משויך) |

לפענוח `plugin/install` הראוטר מעביר את ה‑URI ל‑[`PluginStoreLinkParser.parseUri`](../lib/plugins/services/plugin_store_link_parser.dart) (שמרנו אותו עצמאי כדי לא לשבור את הבדיקות הקיימות), ועוטף את התוצאה ב‑`InstallPluginAction`. אין יותר נפילה אחורה בין שני פרסרים — `ExternalUriRouter.parseUri` הוא נקודת הכניסה היחידה.

### דיספצ׳ר

ב‑[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) הפונקציה `_handleExternalActivationUriString`:

1. מנסה לפענח דרך `ExternalUriRouter.parseUri`. אם `null` — מתעלמת בשקט.
2. מציפה את החלון לפני־כל (`_bringWindowToFront`) ב‑Windows/Linux/macOS.
3. `_dispatchExternalUriAction` עם `switch` יחיד על ה‑sealed class:
   - **`OpenScreenAction`** — שולח `NavigateToScreen` ל‑NavigationBloc.
   - **`OpenToolAction`** — קורא ל‑[`openToolTabById`](../lib/tools/open_tool_tab.dart), שפותח `ToolTab` דרך `OpenOrFocusTab` ומנווט ל‑`Screen.reading`. ה‑`dedupeKey` (`tool:<id>`) ממקד כרטיסיה קיימת במקום להכפיל. אין תור pending ואין retry — כשמערכת התוספים עדיין נטענת הכרטיסיה נפתחת אופטימיסטית ו‑`ToolTabScreen` מציג טעינה.
   - **`OpenPluginAction`** — זהה ל‑`OpenToolAction`: `openToolTabById(pluginId)`. תוסף שלא נמצא, מושבת, מוסתר מהממשק או חסום במצב מנותק — מציג `UiSnack.showError` עם הסיבה המדויקת ([`lookupTool`](../lib/tools/tool_catalog_entry.dart)).
   - **`OpenToolsLauncherAction`** — פותח את פאנל הכלים דרך `ToolsLauncherController.instance.open()`, בלי לנווט.
   - **`OpenSettingsTabAction`** — שולח `NavigateToScreen(Screen.settings)`. אם `tab != null` — קורא ל‑`_settingsScreenController.openTab(tab)` לניווט לטאב הרצוי.
   - **`OpenHistoryAction`** — פותח `HistoryDialog` דרך `showDialog`.
   - **`OpenBookmarksAction`** — פותח `BookmarksDialog` דרך `showDialog`.
   - **`OpenBookAction`** — `await DataRepository.instance.library`, מחפש לפי `b.id`. אם נמצא — `openBook(context, book, index ?? 0, searchQuery ?? '', markSection: markSection, markText: markText)`. אם לא — `UiSnack.showError`.
   - **`RunSearchAction`** — יוצר `SearchingTab` חדש עם הקוורי, מוסיף ל‑`HistoryBloc` ול‑`TabsBloc`, ומנווט ל‑`Screen.search`. ה‑`UpdateSearchQuery` מופעל אוטומטית מ‑`TantivyFullTextSearch.initState` ברגע שהלשונית מוצגת.
   - **`InstallPluginAction`** — `InstallRemotePluginRequested` ל‑PluginSystemBloc (ללא ניווט).
   - **`InstallLocalPluginAction`** — `InstallPluginRequested(archivePath)` ל‑PluginSystemBloc. הדיאלוג נפתח אוטומטית דרך `BlocListener` כשמתקבל `PluginSystemInstallRequiresPermissions`.

## הוספת יעד חדש

נניח שרוצים להוסיף `otzaria://open/myfeature` שיבצע פעולה חדשה לגמרי.

### 1. הגדרת פעולה בראוטר

אם זו פעולה חדשה (לא מסך/כלי/ספר), צור variant חדש ב‑`sealed class ExternalUriAction`:

```dart
class OpenMyFeatureAction extends ExternalUriAction {
  const OpenMyFeatureAction();
}
```

ועדכן את `_parseOpen` ב‑[`lib/core/external_uri_router.dart`](../lib/core/external_uri_router.dart) להחזיר אותו:

```dart
if (firstLower == 'myfeature') {
  return const OpenMyFeatureAction();
}
```

אם זה כלי מובנה חדש — מספיק להוסיף alias ב‑`_toolAliases`:

```dart
'myalias': 'builtin.my_tool_id',
```

### 2. דיספצ׳ר

ב‑[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) ב‑`_dispatchExternalUriAction`, הוסף `case`:

```dart
case OpenMyFeatureAction():
  // לוגיקת הפתיחה כאן
  return true;
```

הקומפיילר אוכף exhaustive matching על ה‑`sealed class`, אז אם תשכח להוסיף — תקבל שגיאת קומפילציה.

### 3. בדיקות

הוסף ב‑[`test/core/external_uri_router_test.dart`](../test/core/external_uri_router_test.dart) מקרי בדיקה — כתובת תקינה, כתובות שאמורות להידחות, ובדיקת case‑insensitivity.

### 4. עדכון תיעוד

הוסף שורה לטבלת ה‑"כתובות נתמכות" במסמך זה.

## אבטחה ושיקולי שימוש

- **אין התקנה אוטומטית של תוספים ללא אישור משתמש.** גם עם `overwrite=true`, המשתמש רואה את שמות הקבצים והרשאות התוסף לפני ההתקנה בפועל.
- **`plugin/install` (הורדה מרשת)** מקבל רק `url=` בסכמת `http`/`https` — `file://` וכל סכמה אחרת נדחות בכוונה.
- **`plugin/install-local` (קובץ מקומי)** מקבל `path=` שחייב להיות **נתיב מוחלט**, להסתיים ב‑`.otzplugin`, ואינו נתיב UNC/התקן (`\\server\share`, `\\.\`, `\\?\`, `//host`). מאחר שקישור `otzaria://` ניתן להפעלה מדף אינטרנט, החסימה מונעת קריאת קובץ שרירותי מהדיסק, שימוש בנתיב יחסי בלתי-צפוי (הנפתר מול תיקיית העבודה), ודליפת אישורי SMB בעצם הגישה לנתיב.
- **קישור ל‑URL לא קיים** (למשל `otzaria://open/banana`) פשוט מוחזר `null` ואוצריא מתעלמת בשקט. אין הודעת שגיאה — זה עיצובית מכוון, כדי לא להפחיד משתמשים שלחצו על קישור עתידי.
- **קישור לספר עם ID לא קיים** מציג `UiSnack.showError` בעברית. זאת בכוונה כדי שהמשתמש יבין שהקישור לא תקף בספרייה שלו.

## קבצים מרכזיים

| קובץ | תפקיד |
|--------|--------|
| [`lib/core/external_uri_router.dart`](../lib/core/external_uri_router.dart) | ראוטר אחיד + sealed `ExternalUriAction` (כולל `OpenTool`/`OpenScreen`/`OpenSettingsTab`/`OpenHistory`/`OpenBookmarks`/`OpenBook`/`InstallPlugin`) |
| [`lib/plugins/services/plugin_store_link_parser.dart`](../lib/plugins/services/plugin_store_link_parser.dart) | פענוח פנימי של `plugin/install` (משמש את הראוטר) |
| [`lib/plugins/services/plugin_protocol_registration_service.dart`](../lib/plugins/services/plugin_protocol_registration_service.dart) | רישום דינמי של סכמת `otzaria://` ב‑Windows ובלינוקס בזמן ריצה |
| [`lib/core/external_activation_queue.dart`](../lib/core/external_activation_queue.dart) | תור JSONL להעברת URIs בין מופעים |
| [`lib/core/external_activation_channel.dart`](../lib/core/external_activation_channel.dart) | ערוץ פלטפורמה ל‑URIs שמגיעים בזמן ריצה (Android/iOS) |
| [`lib/navigation/view/main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) | מאזין, פענוח ודיספצ׳ר (ראה `_handleExternalActivationUriString` ו‑`_dispatchExternalUriAction`) |
| [`lib/settings/view/settings_screen.dart`](../lib/settings/view/settings_screen.dart) | מגדיר `SettingsTab` enum ו‑`SettingsScreenController` לניווט לטאב |
| [`lib/history/view/history_screen.dart`](../lib/history/view/history_screen.dart) | `HistoryDialog` — נפתח דרך `showDialog` |
| [`lib/bookmarks/view/bookmark_screen.dart`](../lib/bookmarks/view/bookmark_screen.dart) | `BookmarksDialog` — נפתח דרך `showDialog` |
| [`lib/tools/open_tool_tab.dart`](../lib/tools/open_tool_tab.dart) | `openToolTab` / `openToolTabById` — פתיחת כרטיסיית כלי בעיון |
| [`lib/tools/tool_catalog_entry.dart`](../lib/tools/tool_catalog_entry.dart) | `buildToolCatalog` / `lookupTool` — קטלוג הכלים וסיבות אי-זמינות |
| [`windows/runner/main.cpp`](../windows/runner/main.cpp) | זיהוי single‑instance + העברת ארגומנטים לתור (לא רישום) |
| [`test/core/external_uri_router_test.dart`](../test/core/external_uri_router_test.dart) | בדיקות הראוטר האחיד |
| [`test/plugins/services/plugin_store_link_parser_test.dart`](../test/plugins/services/plugin_store_link_parser_test.dart) | בדיקות פרסר התקנת תוסף |
