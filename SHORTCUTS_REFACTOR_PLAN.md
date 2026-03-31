# תוכנית ריפקטור מלאה לקיצורי מקשים

## מטרה

לבנות שכבת קיצורי מקשים אחידה, יציבה, ברורה לתחזוקה, ומתעדכנת בזמן אמת, כך ש:

- כל קיצור יוגדר במקום מרכזי אחד
- כל מסך ישתמש באותו מנגנון
- שינוי קיצור בהגדרות יתעדכן מיד בלי לרענן מסך
- בדיקת קונפליקטים תיעשה לפני שמירה ולא אחרי
- תצוגת הקיצורים תישאב ממקור אחד ולא ממספר קבצים מפוזרים
- רוב הקיצורים יעברו ל-`Shortcuts/Actions` של Flutter, עם חריגים מעטים בלבד

מסמך משלים חשוב:

- [PLATFORM_CAPABILITIES_PLAN.md](./PLATFORM_CAPABILITIES_PLAN.md)

המסמך הזה מגדיר את שכבת הפלטפורמות/מכשירים/יכולות קלט שעליה ריפקטור הקיצורים צריך להישען.

---

## תמונת מצב נוכחית

כיום יש בפרויקט כמה שכבות מעורבות:

- `lib/shortcuts/keyboard_shortcuts.dart`
  מטפל בקיצורים גלובליים דרך `FocusScope.onKeyEvent`
- `lib/shortcuts/shortcut_helper.dart`
  ממיר מחרוזות קיצור, בודק התאמה, ומעצב תצוגה
- `lib/shortcuts/key_map.dart`
  ממפה שמות מקשים ל-`LogicalKeyboardKey`
- `lib/shortcuts/shortcut_validator.dart`
  מגדיר מפתחות, ברירות מחדל, שמות ותאימות בין קיצורים
- `lib/shortcuts/shortcut_dropdown_tile.dart`
  ווידג'ט בחירה לקיצור
- `lib/shortcuts/custom_shortcut_dialog.dart`
  דיאלוג הקלטת קיצור
- `lib/settings/tabs/shortcuts_settings_tab.dart`
  קובע איך ייראה טאב ההגדרות של הקיצורים

בנוסף, במסכים שונים יש עדיין שימושים מעורבים:

- `CallbackShortcuts`
- `ShortcutHelper.matchesShortcut(...)`
- `Settings.getValue(...)` ישיר
- `context.watch<SettingsBloc>()`
- `context.select(...)`

כלומר, יש כבר התחלה טובה, אבל לא מנגנון אחיד שלם.

---

## בעיות שעדיין צריך לפתור

### 1. מקור אמת לא אחיד

כרגע חלק מהמסכים קוראים קיצורים מתוך `SettingsBloc`, וחלק ישירות מ-`Settings.getValue`.

תוצאה:

- חלק מהקיצורים מתעדכנים בזמן אמת
- חלק מתעדכנים רק אחרי rebuild מקרי

### 1א. חוסר עקביות בין מנגנוני parsing/runtime

כיום יש פער ממשי בין שני נתיבי העבודה המרכזיים:

- `ShortcutHelper.matchesShortcut(...)`
- `ShortcutHelper.activatorFromShortcut(...)`

בפרט:

- `activatorFromShortcut(...)` כבר תומך ב-`meta`
- `matchesShortcut(...)` עדיין לא בודק `meta`

כלומר, אם יוגדרו ברירות מחדל של `meta+...` ב-macOS/iPadOS לפני תיקון הפער הזה:

- קיצורים שעובדים דרך `CallbackShortcuts` / `SingleActivator` יעבדו
- קיצורים שעובדים דרך `matchesShortcut(...)` עלולים לא לעבוד

זו לא רק בעיית polish או formatting, אלא בעיית עקביות פונקציונלית שצריך לפתור לפני מעבר מלא ל-platform defaults של Apple.

### 2. שכבת הגדרה, שכבת UI ושכבת runtime מעורבבות

`shortcut_validator.dart` מחזיק גם:

- רשימת מפתחות
- ברירות מחדל
- שמות להצגה
- לוגיקת תאימות

וזה יוצר קובץ אחד עם יותר מדי אחריות.

### 3. שמירת קיצור חדש למרות קונפליקט

במצב הנוכחי, המשתמש יכול להקליט קיצור שכבר תפוס, לקבל אזהרה, אבל בפועל השמירה כבר נעשית.

ההתנהגות הנכונה:

- קודם לבדוק
- אחר כך להחליט אם לאשר
- ורק אז לשמור

### 4. תצוגת קיצורים מפוזרת

הצגה של קיצור קיימת בכמה מקומות:

- `formatShortcutForDisplay`
- רשימת dropdown
- tooltips
- כותרות בטאב ההגדרות
- דיאלוג הקלטה

צריך לאחד את דרך התצוגה.

### 5. לא כל הקיצורים משתמשים ב-Shortcuts/Actions

יש עדיין קיצורים שמטופלים ידנית ב-`KeyEvent`.

זה נחוץ בחלק קטן מהמקרים, אבל לא ברובם.

### 6. שימוש בווידג'טים לא אחידים

בדיאלוג הקלטת קיצור יש עדיין שימושים ב:

- `AlertDialog` ישיר
- `ElevatedButton`
- `Icons` של Material

זה לא תואם את קווי הפרויקט.

### 7. דפוס focus למסך לא מתועד מספיק

מהקוד הקיים כבר רואים דפוס שחוזר על עצמו בכמה מסכים:

- קיצורים עם modifier כמו `Ctrl+F`, `Ctrl+E`, `Ctrl+N`
  יושבים טוב ב-`CallbackShortcuts`
- מקשים בלי modifier כמו:
  `Escape`, `Backspace`, `Space`, חיצים, ו-repeat רציף
  יושבים טוב יותר ב-`Focus` + `onKeyEvent`

המסמך הנוכחי רומז לזה, אבל לא מגדיר זאת כדפוס מחייב מספיק ברור.

### 8. יש עדיין פערי focus ויציבות שצריך לסגור לפני הריפקטור הגדול

מעבר לריפקטור עצמו, יש קבוצה של פערים פונקציונליים/UX שצריך קודם לייצב.

לא נכון להתייחס לכולם כ"סגורים" רק כי התשתית החדשה טובה יותר.

צריך להחזיק רשימת ייצוב מסודרת של:

- באגים שדווחו על ידי המשתמש וצריך לאמת/לתקן
- מצבי focus במעבר בין טאב/חלון
- דיאלוגים שצריכים להיסגר/להיפתח נכון בלחיצה חוזרת
- מסכים שבהם קיצור עובד רק כש-focus במקום מסוים

---

## מה צריך להיות המבנה הנכון

### שכבת Core

המיקום המומלץ:

- `lib/core/shortcuts/`

כאן צריכים לשבת רק דברים שהם runtime / engine / parsing:

- `shortcut_ids.dart`
  כל מזהי הקיצורים הקבועים
- `shortcut_definition.dart`
  מודל אחד שמתאר קיצור: מזהה, ברירת מחדל, scope, תיאור, קבוצה, האם ניתן לשיתוף, וכו'
- `shortcut_registry.dart`
  מקור האמת המרכזי לכל ההגדרות
- `shortcut_parser.dart`
  המרה בין string, `ShortcutActivator`, `LogicalKeyboardKey`, ו-`KeyEvent`
- `shortcut_formatter.dart`
  אחראי בלעדית על איך קיצור מוצג למשתמש
- `shortcut_conflicts.dart`
  בדיקת קונפליקטים ותאימויות
- `shortcut_scope.dart`
  הגדרת רמות פעולה: גלובלי, מסך קריאה, לוח שנה, כלי מסוים, וכו'

### שכבת Runtime של האפליקציה

המיקום המומלץ:

- `lib/core/shortcuts/widgets/`

כאן ישבו:

- `app_shortcuts_host.dart`
  מעטפת גלובלית לכל האפליקציה עם `Shortcuts`/`Actions`
- `screen_shortcuts_host.dart`
  מעטפת למסך מקומי

### שכבת Settings UI

המיקום המומלץ:

- `lib/settings/shortcuts/`

כאן ישבו:

- `shortcut_dropdown_tile.dart`
- `custom_shortcut_dialog.dart`
- `shortcut_conflict_dialog.dart` אם יתווסף
- `shortcut_settings_section.dart`

### טאב ההגדרות

המיקום המומלץ:

- `lib/settings/tabs/shortcuts_settings_tab.dart`

הוא צריך להישאר טאב, אבל לא להכיל לוגיקה של מנגנון. הוא צריך רק להרכיב section-ים.

### מה לא צריך להישאר בתיקיית `lib/shortcuts/`

השם `lib/shortcuts/` כרגע מערבב Core ו-UI.

בריפקטור הגדול מומלץ לפרק כך:

- `lib/core/shortcuts/` — מנגנון
- `lib/settings/shortcuts/` — תצוגה/עריכה

---

## מה צריך להשתנות במנגנון עצמו

### 1. לבנות Registry מרכזי

במקום לפזר מידע בין `shortcut_validator.dart` ו-UI, צריך לבנות registry אחד.

כל קיצור יוגדר פעם אחת כך:

- `id`
- `defaultShortcut`
- `title`
- `subtitle`
- `scope`
- `category`
- `icon`
- `allowsSharedBindingWith`

ואז:

- מסך ההגדרות ייקח משם את הרשימה
- מנוע הקונפליקטים ייקח משם את החוקים
- מסכים ייקחו משם ברירת מחדל

### 2. להפסיק לגשת ישירות ל-Settings

כל קיצור ב-runtime צריך להיקרא מתוך מצב reactive אחד:

- `SettingsBloc`
או
- `ShortcutBindingsCubit` ייעודי אם נרצה בידול מלא

לא להשתמש ב:

- `Settings.getValue<String>('key-shortcut-...')`

בתוך build/runtime של קיצורים.

### 3. לעבור ל-Shortcuts/Actions ככל האפשר

היעד:

- קיצורים גלובליים: `Shortcuts` + `Actions` ברמת app
- קיצורים מקומיים למסך: `CallbackShortcuts` או `Shortcuts/Actions`

להשאיר `onKeyEvent` רק למה שלא באמת קיצור רגיל:

- חיצים עם repeat רציף
- הקלדת מספרים שמוזרקת לשדה
- לוגיקות low-level של גלילה/תנועה

כלל עבודה מפורש:

- מקשים עם modifier:
  עדיף ב-`CallbackShortcuts` / `Shortcuts`
- מקשים בלי modifier:
  עדיף ב-`Focus` + `onKeyEvent`

במיוחד עבור:

- `Escape`
- `Backspace`
- `Space`
- חיצים
- repeat רציף בגלילה/ניווט

כלומר, לא נכון לשאוף להעביר גם אותם בכוח ל-`CallbackShortcuts` רק כדי "לאחד הכול".

### 4. לאחד את parsing

צריך מקור אחד בלבד ל:

- `matchesShortcut(...)`
- `activatorFromShortcut(...)`
- `formatKeysToShortcut(...)`
- `formatShortcutForDisplay(...)`

הכוונה היא לאחד סביב:

- `shortcut_parser.dart`
- `shortcut_formatter.dart`

ולצמצם את `shortcut_helper.dart` עד שיוכל להימחק או להפוך façade דק בלבד.

### 5. לחסום שמירה של קיצור תפוס

בעת שינוי קיצור:

1. לקרוא את הערך החדש
2. לחשב קונפליקטים לפני save
3. אם יש קונפליקט אסור:
   לא לשמור
4. אם יש קונפליקט מותר:
   לאפשר
5. אם צריך override:
   להציג דיאלוג מפורש ורק לאחר אישור לשמור

### 6. להפוך את תצוגת הקיצור לאחידה

כל מקום שמציג קיצור צריך להשתמש רק ב:

- `ShortcutFormatter.formatForDisplay(...)`

ולא ב:

- `toUpperCase()` מקומי
- `replaceAll('+', ' + ')` מקומי
- מחרוזות hardcoded שונות

---

## מה נשאר ספציפית מהריפקטור הגדול של הגלובליים

כיום `keyboard_shortcuts.dart` מטפל גלובלית דרך `FocusScope.onKeyEvent`.

הריפקטור הגדול שעדיין נשאר:

### שלב א

להגדיר Intents גלובליים:

- `OpenLibraryIntent`
- `OpenFindRefIntent`
- `CloseTabIntent`
- `CloseAllTabsIntent`
- `OpenReadingScreenIntent`
- `OpenNewSearchIntent`
- `OpenSettingsIntent`
- `OpenContextSettingsIntent`
- `OpenMoreIntent`
- `OpenBookmarksIntent`
- `OpenHistoryIntent`
- `SwitchWorkspaceIntent`
- `FocusCurrentWindowSearchIntent`

### שלב ב

להחליף את רוב התנאים ב-`keyboard_shortcuts.dart` ב:

- `Shortcuts`
- `Actions`

כלומר:

- binding אחד שמבוסס על settings
- action אחת לכל intent

### שלב ג

להשאיר ב-`onKeyEvent` רק חריגים:

- `F11`
- `Escape`
- `Ctrl+Tab`
- `Ctrl+Shift+Tab`

וגם אותם אפשר אחר כך להעביר ל-`Shortcuts`, אם לא תהיה בעיית focus.

### שלב ד

לייצר helper אחד לבניית map של bindings ממצב ההגדרות:

- `ShortcutBindingsBuilder.buildGlobalBindings(SettingsState state)`
- `ShortcutBindingsBuilder.buildScreenBindings(...)`

---

## מה צריך לבצע בפועל, שלב אחרי שלב

### שלב 1 — ייצוב המצב הקיים

- לאמת ולתקן את כל הבאגים הפתוחים שהמשתמש כבר סימן לפני הריפקטור הגדול
- להשלים reactive לכל המסכים שעוד נשארו
- להסיר מפתחות ישנים/מתים
- לוודא שכל קיצור שמוגדר ב-registry מוצג גם ב-UI אם הוא user-configurable

רשימת ייצוב שצריך לכלול כאן:

- פוקוס אחרי `Enter` בחיפוש, כולל מעבר נכון מהחיפוש לתוכן
- באג חץ למעלה מתוך חיפוש במסכים הרלוונטיים
- `Ctrl+E` ב"שמור וזכור" כש-focus לא נמצא במקום הצפוי
- `Ctrl+F` ב"הערות אישיות" ובמסכי כלים דומים
- סגירה/פתיחה חוזרת של דיאלוגים בלוח השנה בלחיצה חוזרת על אותו קיצור
- פוקוס כשעוברים לטאב "כלים"
- מצבים שבהם `Ctrl+Tab` או קיצורים דומים ממשיכים לעבוד על "עיון" במקום על המסך הפעיל

מטרת השלב הזה:

- לא לפתור רק "ארכיטקטורה"
- אלא קודם לייצב את ההתנהגות בפועל כך שהריפקטור הגדול לא ייבנה על בסיס לא יציב

### שלב 2 — לפצל Core מול UI

- להעביר את מנוע הקיצורים ל-`lib/core/shortcuts/`
- להעביר את UI של עריכת קיצורים ל-`lib/settings/shortcuts/`

### שלב 3 — לבנות Registry חדש

- להפסיק להשתמש ב-3 מפות שונות בקובץ validator
- להחליף אותן ברשימת `ShortcutDefinition`

### שלב 4 — לבנות Conflict Engine חדש

- `validateBeforeSave(...)`
- `findConflicts(...)`
- `canShareShortcut(...)`

ולהשתמש בו גם ב-dropdown וגם בדיאלוג הקלטה

### שלב 5 — לאחד תצוגה

- כל tooltip
- כל subtitle
- כל תצוגת dropdown
- כל warning

כולם דרך formatter אחד

### שלב 6 — להעביר גלובליים ל-Shortcuts/Actions

- לבנות `AppShortcutsHost`
- לחבר אותו ברמת האפליקציה
- לצמצם את `keyboard_shortcuts.dart`

### שלב 7 — להעביר מסכים מקומיים לתבנית אחת

בכל מסך:

1. `final shortcutX = context.select(...)`
2. `ShortcutHelper/Parser` להמרה ל-`ShortcutActivator`
3. `CallbackShortcuts` עם bindings

או לחלופין:

- `ScreenShortcutsHost(shortcuts: ..., child: ...)`

### שלב 8 — לשכתב את דיאלוג הקלטת קיצור

צריך להחליף את `custom_shortcut_dialog.dart` כך ש:

- ישתמש רק ב-Fluent icons
- ישתמש בדיאלוגים והכפתורים של הפרויקט
- לא יבצע save implicit
- יחזיר תוצאת validation מסודרת

### שלב 9 — להוסיף בדיקות

צריך להוסיף tests ל:

- parsing
- formatting
- conflict rules
- compatible groups
- update בזמן אמת מתוך bloc
- save עם קונפליקט

---

## החלטות מוצר שצריך לסגור

### 1. האם כל קיצור user-configurable?

כנראה לא.

צריך להפריד:

- configurable
- fixed

לדוגמה:

- מקשי חיצים עם repeat כנראה יישארו fixed

### 2. האם כל קיצור גלובלי צריך לעבוד גם בזמן עריכת טקסט?

צריך לקבוע לכל קיצור:

- `allowedWhileEditing`

ולא להחזיק את זה כבדיקה כללית אחת בלבד.

### 3. איך מטפלים בקונפליקט?

מומלץ להחליט על אחד מ-3 מצבים:

- חסימה מוחלטת
- אישור override
- שיתוף רק בקבוצות תאימות מוגדרות

### 4. מדיניות פלטפורמה: macOS / iPadOS / iPhone

זו החלטה מוצרית חשובה, ולא רק החלטת מימוש.

#### מה אומרת הפלטפורמה

ב-Apple:

- ב-macOS קיצורי אפליקציה סטנדרטיים נשענים בדרך כלל על `Command` (`⌘`), לא על `Control`
- ב-iPadOS עם מקלדת חיצונית, רוב קיצורי האפליקציה גם נשענים על `Command`, בדומה ל-Mac
- ב-iPadOS קיימת ציפייה לגילוי קיצורים דרך לחיצה ממושכת על `Command`
- ב-macOS קיצורים מוצגים בדרך כלל ליד פקודות בתפריטים
- ב-iPhone קיימת תמיכה במקלדת חיצונית, אבל זו צורת שימוש משנית יותר, ואין להעמיס עליה UI קבוע שמיועד ל-hover

#### מה המצב כיום בפרויקט

נכון לעכשיו, הפרויקט עדיין לא מוגדר נכון ל-macOS/iPadOS:

- ברירות המחדל ב-`shortcut_validator.dart` הן כמעט כולן `ctrl+...`
- `shortcut_helper.dart` מציג `meta` בתור `WIN + ...`
- `shortcut_helper.dart` לא מטפל עדיין ב-`meta` באופן עקבי בכל נתיבי הזיהוי
- במסכים רבים ה-fallbacks עדיין מניחים `ctrl+...`

כלומר, המנגנון הנוכחי הוא בעיקר:

- Windows/Linux-first

ולא:

- platform-adaptive

#### דעתי המוצרית

המדיניות הנכונה היא **לא** להחזיק ברירת מחדל אחת זהה לכל הפלטפורמות.

במקום זאת צריך להגדיר:

- Windows/Linux:
  ברירות מחדל על בסיס `Ctrl`
- macOS:
  ברירות מחדל על בסיס `Meta/Command`
- iPadOS:
  ברירות מחדל על בסיס `Meta/Command`
- iPhone:
  לתמוך בקיצורים אם יש מקלדת חיצונית, אבל לא לבנות UI קבוע כאילו זו צורת השימוש הראשית

כלומר:

- `search-current-window`
  צריך להיות `Ctrl+F` ב-Windows/Linux
  ו-`⌘F` ב-macOS/iPadOS
- `open-settings`
  צריך להיות `Ctrl+,` ב-Windows/Linux
  ו-`⌘,` ב-macOS/iPadOS

וכן הלאה.

#### החלטת מימוש מומלצת

ב-registry החדש כל קיצור צריך לתמוך ב:

- `defaultShortcutWindows`
- `defaultShortcutLinux`
- `defaultShortcutMacos`
- `defaultShortcutIpados`
- אופציונלית `defaultShortcutIos`

או לחלופין:

- `defaultShortcutByPlatform`

לדוגמה:

- `windows`: `ctrl+f`
- `linux`: `ctrl+f`
- `macos`: `meta+f`
- `ipados`: `meta+f`

#### מדיניות תצוגה

לא נכון להציג קיצורים "תמיד" באותה צורה בכל פלטפורמה.

##### macOS

כן נכון:

- להציג קיצור ב-tooltip בריחוף כמידע משלים
- להציג קיצור במסכי הגדרות, עזרה, ותפריטים

לא נכון:

- להסתמך רק על hover כדי שהמשתמש יגלה קיצורים

##### iPadOS

לא כדאי להסתמך על hover כתצורת גילוי מרכזית, כי:

- אין תמיד pointer
- הרבה משתמשים יעבדו במגע + מקלדת, בלי hover קלאסי

לכן ב-iPadOS נכון יותר:

- להשאיר קיצורי מקשים פעילים כשיש מקלדת חיצונית
- להציג אותם במסך הגדרות/עזרה
- לתכנן בעתיד גם discoverability בסגנון "רשימת קיצורים" מתוך האפליקציה

עם זאת, אם יש trackpad / pointer:

- tooltip בריחוף עדיין יכול להישאר כתוספת שימושית

אבל:

- הוא לא צריך להיות ערוץ הגילוי המרכזי או היחיד.

##### iPhone

לא מומלץ להציג קיצורים תמיד ב-hover או ב-UI צפוף, כי:

- אין hover רגיל
- המסך קטן
- מקלדת חיצונית היא תרחיש משני

ב-iPhone המדיניות הנכונה היא:

- התמיכה בקיצורים תישאר אם יש מקלדת חיצונית
- אבל התצוגה שלהם תהיה בעיקר במסך ההגדרות / מסך עזרה
- לא להעמיס תוויות קיצור קבועות בתוך UI רגיל

#### מסקנה לפרויקט

מה שצריך להיחשב "נכון" בפרויקט:

- להשאיר את מנגנון הקיצורים פעיל גם ב-iPadOS וגם ב-iPhone עם מקלדת חיצונית
- לשנות את ברירות המחדל ל-platform-specific defaults
- להציג formatter פלטפורמי:
  `CTRL` ב-Windows/Linux,
  `⌘`/`Command` ב-macOS/iPadOS,
  ולא `WIN`
- לפני כל מעבר בפועל ל-`meta` כברירות מחדל:
  לתקן את `matchesShortcut(...)` כך שיתנהג באופן עקבי עם `activatorFromShortcut(...)`
- לא לבנות מדיניות מוצר שמחייבת tooltip-hover כערוץ הגילוי הראשי באייפד/אייפון

בקיצור:

- כרגע הפרויקט **לא** מוגדר נכון לגמרי עבור macOS/iPadOS
- התמיכה עצמה צריכה להישאר גם ב-iPadOS וגם ב-iPhone
- מה שצריך להשתנות הוא ברירות המחדל, ה-formatting, ודרך הגילוי/התצוגה

---

## מה אני חושב שכדאי לבצע בנוסף למה שכבר עלה

### א. לבטל שמות setting keys כמחרוזות raw בקוד

במקום:

- `'key-shortcut-search-current-window'`

להגדיר constants או ids מרוכזים.

### ב. להפריד בין שם פנימי לשם תצוגה

לא להשתמש ב-`shortcutNames` גם כ-label סופי וגם כטקסט אזהרה בלי שכבת formatting נוספת.

### ג. להחזיק cache מומר של activators

כאשר `SettingsState.shortcuts` משתנה, אפשר לבנות פעם אחת:

- `Map<ShortcutId, ShortcutActivator>`

במקום שכל מסך ימפה מחדש מחרוזת ל-activator.

### ד. לבנות wrapper למסך

למשל:

- `ConfigurableShortcuts`

שיקבל:

- scope
- bindings ids -> callbacks

וכך יחסוך כפילות של `context.select + activatorFromShortcut`.

---

## Definition of Done

הריפקטור ייחשב מושלם רק אם:

- אין `Settings.getValue<String>('key-shortcut-...')` בתוך runtime של קיצורים
- אין parsing פרטי במסכים
- `matchesShortcut(...)` ו-`activatorFromShortcut(...)` מתנהגים באופן עקבי בכל המודיפיירים, כולל `meta`
- אין tooltip/dropdown/dialog שמעצבים קיצור בעצמם
- שינוי קיצור בהגדרות מתעדכן מייד בכל מקום
- לא ניתן לשמור קיצור תפוס בלי flow ברור ומפורש
- כל קיצור configurable מופיע ב-UI
- הגלובליים המרכזיים עובדים דרך `Shortcuts/Actions`
- נשאר `onKeyEvent` רק לחריגים אמיתיים

---

## סדר עבודה מומלץ

1. להשלים קודם ייצוב bugים ו-focus של המצב הקיים
2. להכריע ולבנות את שכבת הפלטפורמות לפי [PLATFORM_CAPABILITIES_PLAN.md](./PLATFORM_CAPABILITIES_PLAN.md)
3. לפצל תיקיות Core/UI
4. לבנות Registry חדש
5. לבנות Conflict Engine לפני שינוי ה-UI
6. לשכתב את מסך ההגדרות והדיאלוג
7. להעביר את הגלובליים ל-`Shortcuts/Actions`
8. להעביר את המסכים המקומיים ל-wrapper אחיד
9. להוסיף tests
