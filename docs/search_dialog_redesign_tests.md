# טסטים שצריך להוסיף — עיצוב מחדש של דיאלוג החיפוש

מסמך עבודה. נכתב אחרי סבב עיצוב על דיאלוג החיפוש (`lib/search/view/search_dialog.dart`)
ועל שדות הקלט שסביבו, כשהעיצוב עדיין עשוי להשתנות ולכן הטסטים טרם נכתבו.
כשהעיצוב יתייצב — לעבור על הרשימה, למחוק ממנה מה שכבר לא רלוונטי, ולכתוב את השאר.

**מחק את הקובץ הזה כשכל הטסטים נכתבו.**

## מה השתנה (הרקע לטסטים)

בענף `cleanup/remove-dead-search-ui`:

| קומיט | שינוי |
|---|---|
| `bc9bd89ac` | `EnhancedSearchField` עבר להשתמש ב-`OtzariaSearchField` — אותו רכיב כמו שדה החיפוש בספרייה |
| `a4c26c63c` | כותרת ממורכזת, איחוד כפתורי ברירת המחדל לתפריט, קיפול "החרגת תוצאות", הסרת הגובה הקבוע |
| `b81db44f5` | שדות הקלט המשניים עברו ל-`AppInputTokens.filledDecoration` |
| `6bce5f7c6` | פס גלילה בימין (`EdgeScrollbarBehavior`), תוויות מעל השדות (`LabeledInput`) |

## תשתית קיימת שאפשר להישען עליה

`test/search/search_dialog_test.dart` כבר מכיל את כל מה שצריך כדי לבנות את הדיאלוג
בטסט, ואת רובם אפשר להוסיף לתוכו במקום לבנות תשתית מחדש:

- `_buildDialogHarness({theme, historyBloc, indexingBloc, navigationBloc, dialog})` —
  עוטף את הדיאלוג ב-`MaterialApp` + `MultiBlocProvider` עם ארבעת ה-blocs הדרושים.
- `MockHistoryBloc` / `MockIndexingBloc` / `MockNavigationBloc` / `MockLibraryBloc`
  ו-`_stubLibraryBloc()` (ספרייה ריקה — מספיק ל-`parseCategoryQuery`).
- `setUpAll` שקורא ל-`Settings.init(cacheProvider: MemoryCacheProvider())` —
  **חובה** לכל טסט שנוגע ב-`SearchDefaults`, שכן הוא נשען על `flutter_settings_screens`.
- `tryInitSearchEngine()` מ-`test/support/search_engine_test_init.dart` — מחזיר
  `false` כשאין build נייטיבי של מנוע ה-Rust. טסט שמפעיל חיפוש בפועל
  (`sanitizeQuery` / `splitQueryWords`) חייב `skip: !engineReady`. טסט שבודק
  **רק תצוגה** אינו צריך את המנוע ואסור לו לדלג בגללו.

---

## 1. `test/search/search_dialog_test.dart` — להוסיף לקובץ הקיים

### 1.1 הכותרת ממורכזת ובגודל הנכון

**למה:** הכותרת נבנית ב-`Stack` ולא ב-`Row` דווקא כדי שתתמרכז ביחס לחלון כולו
ולא ביחס למקום שנשאר אחרי כפתור הסגירה. מי שיחזיר `Row` יקבל כותרת שנראית
ממורכזת רק במקרה, ותזוז ברגע שהכותרת תתארך.

**מה לבדוק:**
- `tester.getCenter(find.text('חיפוש בספרייה')).dx` שווה למרכז האופקי של
  `find.byKey(tourSearchDialogTargetKey)` (סטייה מותרת ~1 פיקסל).
- הסגנון שנצבע הוא `Theme.of(context).textTheme.titleLarge` עם
  `fontWeight: FontWeight.bold` — לקרוא את ה-`Text` דרך
  `tester.widget<Text>(...)` ולהשוות `style?.fontSize` ל-`titleLarge?.fontSize`.
- כפתור הסגירה קיים ויושב בקצה ה-end (בעברית — שמאל): ה-`dx` שלו קטן מזה
  של הכותרת.

**וריאציות הכותרת** (טסט אחד עם שלוש בדיקות או שלושה טסטים):
| מצב | כותרת צפויה |
|---|---|
| `SearchDialog()` | `חיפוש בספרייה` |
| `SearchDialog(editTab: tab)` | `עריכת חיפוש` |
| `SearchDialog(bookTitle: 'בראשית')` | `חיפוש בבראשית` |

**מלכודת:** ב-`editTab` הדיאלוג עושה `SearchingTab.clone` — צריך `addTearDown`
שמשחרר גם את הטאב המקורי וגם לוודא שהעותק לא נשאר תלוי.

### 1.2 "החרגת תוצאות" מקופל בחיפוש חדש

**למה:** זה עיקר ההקלה בתחתית הדיאלוג — קטע שלם ירד מהמסך.

**הכנה:** הקטע מוצג רק במצב **מתקדם** ורק כש-`onSearch == null` ו-
`returnResultOnSubmit == false`. לכן: לפתוח `SearchDialog()` רגיל, ולעבור
למצב מתקדם — או דרך לחיצה על מקטע "מתקדם" בבורר המצב, או ע"י יצירת הטאב עם
`initialSearchMode: SearchMode.advanced`. השני יציב יותר בטסט.

**מה לבדוק:**
- קיים כפתור `ActionButton.ghost` עם הטקסט `החרגת תוצאות`.
- **לא** קיים שדה עם `hintText: 'מילים שלא יופיעו בתוצאות'`.
- אחרי `tester.tap` על הכפתור + `pumpAndSettle`: השדה מופיע, וגם תווית
  הקטע `החרגת תוצאות` כ-`_sectionLabel`.

### 1.3 החרגה קיימת נפתחת מראש בעריכה

**למה:** `_showNegativeSection` מאותחל ב-`initState` מתוך תוכן
`negativeQueryController`. אם מישהו יאתחל אותו ל-`false` קבוע, עריכת חיפוש
עם החרגה תסתיר אותה — והמשתמש יריץ חיפוש עם סינון שהוא לא רואה.

**הכנה:** `SearchingTab` שה-`negativeQueryController.text` שלו לא ריק,
ומועבר כ-`editTab`.

**מה לבדוק:** השדה מוצג מיד, בלי שום לחיצה, עם הטקסט הקיים בתוכו.

### 1.4 סגירת ההחרגה מנקה את השדה — **הטסט הכי חשוב ברשימה**

**למה:** קיפול בלי ניקוי משאיר סינון פעיל שאינו נראה במסך. זה בדיוק סוג הבאג
שהקיפול עלול להכניס, וזו הסיבה שהסגירה מנקה.

**מה לבדוק:**
1. לפתוח את הקטע ולהקליד בו `tester.enterText(..., 'רש"י')`.
2. לוודא ש-`tab.negativeQueryController.text` אינו ריק.
3. ללחוץ על כפתור ה-X (tooltip `בטל את ההחרגה`).
4. `expect(tab.negativeQueryController.text, isEmpty)`.
5. הכפתור המקופל `החרגת תוצאות` חזר, והשדה נעלם.

### 1.5 תפריט ברירות המחדל של החיפוש הרגיל

**למה:** שני כפתורים רחבים אוחדו לתפריט אחד. האיחוד לא אמור לגרוע יכולת —
הטסט הוא מה שמוודא את זה.

**הכנה:** `SearchDialog(initialSearchMode: SearchMode.exact)`, ו-`Settings.init`
מה-`setUpAll` הקיים.

**מה לבדוק:**
- קיים `IconButton` עם tooltip `ברירות מחדל לחיפוש רגיל`, והוא יושב בשורת
  `אפשרויות מילה` (לא בשורה נפרדת מתחת לשבבים).
- לחיצה פותחת תפריט שמכיל `CheckboxMenuButton` לכל מפתח ב-
  `SearchQueryBuilder.exactWordOptionKeys`, ועוד שני `MenuItemButton`:
  `קבע את המרווח הנוכחי (N) כברירת מחדל` ו-`חזרה לברירת המחדל השמורה`.
- סימון תיבה: `SearchDefaults.loadExactDefaults()[key] == true`, **וגם**
  ה-`FilterChip` המתאים בחלונית נצבע כנבחר מיד (`selected == true`) —
  זו התנהגות שקיימת בקוד וקל לאבד אותה.
- התפריט לא נסגר בסימון (`closeOnActivate: false`).

### 1.6 "חזרה לברירת המחדל השמורה" מאפס גם אפשרויות וגם מרווח

**מה לבדוק:**
1. לשמור ברירת מחדל ידועה: `SearchDefaults.saveExactDefaults({...})` +
   `SearchDefaults.saveDistanceDefault(5)`.
2. לשנות במסך: לסמן שבב אחר, ולשנות את ה-`SpinBox` לערך אחר.
3. ללחוץ על הפריט בתפריט.
4. `_searchTab.globalSearchOptions` שווה בדיוק לברירת המחדל השמורה.
5. ה-`SearchBloc` קיבל `UpdateDistanceWithoutSearch(5)` — בדיאלוג של חיפוש
   חדש `_usesStagedSubmit` הוא `false`, ולכן שם דווקא `UpdateDistance(5)`.
   לוודא את שני המסלולים: חיפוש חדש מול `editTab`.

### 1.7 אין גולל בתוך גולל

**למה:** קודם היה `SizedBox(height: 260)` עם `SingleChildScrollView` בפנים,
בתוך `SingleChildScrollView` חיצוני — שני פסי גלילה ותוכן שנחתך בגובה שרירותי.

**מה לבדוק:**
- `find.descendant(of: find.byKey(tourSearchDialogTargetKey), matching: find.byType(Scrollable))`
  מחזיר בדיוק גולל אחד לכל מצב חיפוש (רגיל / מתקדם / מקורב).
  שים לב: `TextField` מכיל `Scrollable` פנימי משלו — לסנן לפי
  `find.byType(SingleChildScrollView)` במקום `Scrollable`, או לספור רק
  גוללים שהם צאצאי הגוף ולא של שדות.
- אין `SizedBox` עם `height: 260` בעץ.

---

## 2. `test/search/advanced_search_controls_test.dart` — קובץ חדש

הרכיב הוא `AdvancedSearchControls` (`lib/search/view/advanced_search_controls.dart`).
אפשר לבנות אותו ישירות עם `SearchingTab` אמיתי בלי הדיאלוג — הוא לא דורש
`SearchBloc` מהעץ, רק `tab`.

### 2.1 תפריט ברירות המחדל בשורת "אפשרויות מילה"

**מה לבדוק:**
- `IconButton` עם tooltip `ברירות מחדל לחיפוש חדש` מופיע באותה שורה עם
  הטקסט `אפשרויות מילה` (להשוות `getCenter(...).dy` של השניים).
- אין יותר כפתורי טקסט `ברירת מחדל לחיפוש חדש` / `חזרה לברירת מחדל`
  כ-`ActionButton` נפרדים.
- התפריט מכיל תיבה לכל מפתח ב-`availableWordOptionKeys` +
  `advancedOnlyWordOptionKeys`.

### 2.2 "ניקוד"/"טעמים" רק כש-`supportsVocalized: true`

**למה:** קיים בקוד מלפני השינוי, אין לו כיסוי, וקל לשבור אותו כשנוגעים בתפריט.

**מה לבדוק:** עם `supportsVocalized: false` מפתחות
`SearchQueryBuilder.vocalizedWordOptionKeys` לא מופיעים בתפריט; עם `true` — כן.

### 2.3 "חזרה לברירת מחדל" מנקה גם את האפשרויות הפר-מיליות

**מה לבדוק:** אחרי שמסמנים אפשרות במצב פר-מילה (`useGlobalSearchOptions = false`)
ולוחצים על הפריט — `tab.searchOptions` ריק, ו-`tab.globalSearchOptions` שווה
ל-`SearchDefaults.loadDefaults()`.

### 2.4 התוויות מעל השדות ולא בתוכם

**מה לבדוק:**
- `find.byType(LabeledInput)` מחזיר שניים כשמילה נבחרה.
- `tester.widget<TextField>` של "מרווח למילה הבאה" — `decoration?.labelText`
  הוא `null` ו-`hintText` הוא `'0-30'`.
- מרכז הטקסט `מרווח למילה הבאה` נמצא **מעל** ראש ה-`TextField`
  (`labelRect.bottom <= fieldRect.top`).

**מלכודת:** השדות מוצגים רק כש-`perWordInputsEnabled` — כלומר נבחרה מילה בודדת
בשאילתה. צריך `tab.queryController.text = 'שלום'` ולמקם את הסמן בתוך המילה
(`selection = TextSelection.collapsed(offset: 2)`), אחרת אין מה לבדוק.

---

## 3. `test/widgets/labeled_input_test.dart` — קובץ חדש

הרכיב: `lib/widgets/text/labeled_input.dart`.

### 3.1 התווית מעל השדה ואינה חופפת לו

**למה:** זו בדיוק התקלה שהובילה ליצירת הרכיב — תווית צפה בתוך שדה מלא נתלית
על שפתו ודוחקת את התוכן והכפתורים מהמרכז.

**מה לבדוק:** `getRect(label).bottom <= getRect(child).top`.
(אימות מקביל הורץ ידנית בזמן העיצוב ועבר: שדה בגובה 48, התווית בין 4 ל-16
פיקסלים מראשו.)

### 3.2 `width` מגביל את שניהם

**מה לבדוק:** `LabeledInput(width: 150, ...)` — רוחב התווית והשדה יחד אינו
עולה על 150, גם כשהתווית ארוכה (`overflow: ellipsis`).

### 3.3 בלי `width` הרכיב לוקח את רוחב ההורה

**מה לבדוק:** בתוך `SizedBox(width: 400)` — השדה נמתח ל-400.

### 3.4 צבע וגודל התווית מגיעים מה-theme

**מה לבדוק:** `style?.color == colorScheme.onSurfaceVariant` — כדי שלא יוחזר
צבע קשיח.

---

## 4. `test/widgets/edge_scrollbar_behavior_test.dart` — קובץ חדש

הרכיב: `lib/widgets/layout/edge_scrollbar_behavior.dart`.

### 4.1 בסביבה RTL פס הגלילה בימין כשמבקשים ימין

**למה:** זה כל הטעם ברכיב. `MaterialScrollBehavior` בברירת מחדל שם פס אנכי
בקצה ה-trailing — בעברית זה **שמאל**. הרכיב קיים כדי לעקוף את זה.

**מה לבדוק:** לעטוף `ListView` ארוך ב-`ScrollConfiguration` עם
`EdgeScrollbarBehavior(ScrollbarOrientation.right)` בתוך
`Directionality(textDirection: TextDirection.rtl)`, ולוודא ש-
`tester.widget<Scrollbar>(find.byType(Scrollbar)).scrollbarOrientation ==
ScrollbarOrientation.right`.

**מלכודת:** `getPlatform(context)` — בטסטים ברירת המחדל היא `android`, ואז
הרכיב **לא** בונה פס כלל. חובה
`debugDefaultTargetPlatformOverride = TargetPlatform.windows` עם
`addTearDown(() => debugDefaultTargetPlatformOverride = null)`.

### 4.2 שמאל כשמבקשים שמאל

אותו טסט עם `ScrollbarOrientation.left` — מוודא שהרכיב באמת מקבל פרמטר ולא
מקובע לימין (`adaptive_side_pane` מסתמך על שני הכיוונים).

### 4.3 גלילה אופקית — אין פס

**מה לבדוק:** `ListView(scrollDirection: Axis.horizontal)` → `find.byType(Scrollbar)`
מחזיר `findsNothing`.

### 4.4 מובייל — אין פס

**מה לבדוק:** עם `TargetPlatform.android` ו-`iOS` → אין `Scrollbar`.
זו התנהגות `MaterialScrollBehavior` שהרכיב משכפל, וקל לאבד אותה בשכתוב.

---

## 5. `test/search/search_dialog_scrollbar_test.dart` — קובץ חדש (או בתוך 1)

### 5.1 פס הגלילה של הדיאלוג בימין

**מה לבדוק:** בדיאלוג בנוי, ה-`Scrollbar` שעוטף את גוף הדיאלוג הוא
`ScrollbarOrientation.right`. גם כאן נדרש `debugDefaultTargetPlatformOverride`.

### 5.2 המרווח נשמר — הפס לא מצויר על התוכן

**למה:** המרווחים הוזזו מ-`Padding` שעטף את הגולל אל `padding` של
`SingleChildScrollView` עצמו. אם מישהו יחזיר אותם החוצה, הפס יחזור לשבת על
תחילת התוכן.

**מה לבדוק:** ה-`SingleChildScrollView` בגוף הדיאלוג מחזיק `padding` לא-null
עם `horizontal` חיובי, ואינו עטוף ב-`Padding` שמצמצם את רוחבו — כלומר רוחב
ה-`Scrollable` שווה לרוחב הדיאלוג.

---

## 6. `test/theme/app_input_tokens_test.dart` — קובץ חדש

### 6.1 `filledDecoration` מחזירה מילוי בלי מסגרת

**מה לבדוק:**
- `filled == true`.
- `fillColor == colorScheme.onSurface.withValues(alpha: AppInputTokens.unfocusedAlpha)`.
- כל שישה ה-borders (`border`, `enabledBorder`, `focusedBorder`,
  `disabledBorder`, `errorBorder`, `focusedErrorBorder`) עם
  `borderSide == BorderSide.none`.
- `labelText == null` — הרכיב **לא** אמור לקבל תווית פנימית; היא ב-`LabeledInput`.

### 6.2 מצב מושבת מקבל alpha חלש יותר

**מה לבדוק:** `enabled: false` → `fillColor` עם `AppInputTokens.disabledAlpha`.

---

## 7. עדכון לקובץ קיים

`test/tools/tools_launcher_panel_test.dart` — אם הוא מתייחס בשם למחלקה
`_RightScrollbarBehavior` שנמחקה, להצביע על `EdgeScrollbarBehavior`.
(בהרצה האחרונה הקובץ עבר, כך שכנראה הוא בודק את ההתנהגות ולא את השם —
לוודא לפני שנוגעים.)

---

## מה **לא** צריך טסט

- מראה הכרטיסים והרקעים שהוסרו — צבע רקע אינו חוזה, וטסט עליו נשבר בכל
  שינוי ערכת נושא.
- הסרת ריבוע האייקון ושורת ההסבר מהכותרת — בדיקת "משהו לא קיים" בעיצוב
  נוטה להתיישן; מספיקה הבדיקה החיובית שהכותרת ממורכזת ובגודל הנכון.
