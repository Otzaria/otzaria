# טסטים שצריך להוסיף — עיצוב מחדש של דיאלוג החיפוש

מסמך עבודה. נכתב במהלך סבב עיצוב על דיאלוג החיפוש (`lib/search/view/search_dialog.dart`)
ועל הפקדים שסביבו, כשהעיצוב עדיין בתנועה ולכן הטסטים טרם נכתבו.
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
| `1bbf1cca6` | בורר המצב עבר ל-`AppSegmentedControl`, ו-`SegmentOption` קיבל `tooltip` |
| `b92bbdc48` | שורת חיפוש אחת: סוג החיפוש כתפריט נפתח, כותרת לכל פקד, שדה היקף גמיש |
| `e79ff144a` | תגיות ההיקף בשורה נפרדת (`SearchScopeChips`), בלי אייקון בנבחר ובלי עיגול מונה |

### המבנה שהתקבל

```
                    חיפוש בספרייה                    ✕     ← כותרת ממורכזת
────────────────────────────────────────────────────────
 סוג החיפוש      מה לחפש                 היקף החיפוש     ← כותרות LabeledInput
 [ מדויק  ▾ ]  [ הקלד מילות חיפוש 🕘 ✕ ] [ כל הספרייה ▾ ]
               [תגית] [תגית]                            ← SearchScopeChips

 הגדרות החיפוש
 [ מרווח בין מילים ]   אפשרויות מילה            ⚙
 [שגיאות כתיב] [קידומות דקדוקיות] …
────────────────────────────────────────────────────────
 Enter מפעיל את החיפוש            [ביטול]  [חפש]
```

## תשתית קיימת שאפשר להישען עליה

`test/search/search_dialog_test.dart` כבר מכיל את כל מה שצריך כדי לבנות את הדיאלוג
בטסט, ואת רוב הטסטים אפשר להוסיף לתוכו במקום לבנות תשתית מחדש:

- `_buildDialogHarness({theme, historyBloc, indexingBloc, navigationBloc, dialog})` —
  עוטף את הדיאלוג ב-`MaterialApp` + `MultiBlocProvider` עם ארבעת ה-blocs הדרושים.
- `MockHistoryBloc` / `MockIndexingBloc` / `MockNavigationBloc` / `MockLibraryBloc`
  ו-`_stubLibraryBloc()` (ספרייה ריקה — מספיק ל-`parseCategoryQuery`).
- `_selectSearchMode(tester, 'מתקדם')` — פותח את תפריט סוג החיפוש דרך
  `searchModeButtonKey` ובוחר מצב. **זו הדרך היחידה להחליף מצב בטסט** מאז
  שהבורר הפך לתפריט נפתח.
- `setUpAll` שקורא ל-`Settings.init(cacheProvider: MemoryCacheProvider())` —
  **חובה** לכל טסט שנוגע ב-`SearchDefaults`, שכן הוא נשען על `flutter_settings_screens`.
- `setUp` שמאפס `SearchDefaults.rememberSessionMode(SearchMode.exact)` — סגירת
  הדיאלוג זוכרת את המצב לסשן, ובלי האיפוס טסט שמסיים במצב אחר קובע את המצב
  של הטסט הבא. **אל תסיר.**
- `tryInitSearchEngine()` מ-`test/support/search_engine_test_init.dart` — מחזיר
  `false` כשאין build נייטיבי של מנוע ה-Rust. טסט שמפעיל חיפוש בפועל
  (`sanitizeQuery` / `splitQueryWords`) חייב `skip: !engineReady`. טסט שבודק
  **רק תצוגה** אינו צריך את המנוע ואסור לו לדלג בגללו.

### מלכודות שחוזרות בכל הטסטים כאן

1. **רוחב המסך קובע את הפריסה.** מתחת ל-760 פיקסלים שורת החיפוש נשברת לשתי
   שורות. טסט שבודק את השורה האחת חייב
   `await tester.binding.setSurfaceSize(const Size(1400, 900))` +
   `addTearDown(() => tester.binding.setSurfaceSize(null))`.
2. **`getPlatform` בטסטים הוא `android`.** כל בדיקת פס גלילה מחייבת
   `debugDefaultTargetPlatformOverride = TargetPlatform.windows` עם ניקוי ב-tearDown.
3. **`SearchingTab` מחזיק controllers** — `addTearDown(tab.dispose)`, ובעריכה
   (`editTab`) הדיאלוג עובד על `SearchingTab.clone` ולכן יש שני טאבים לשחרר.
4. **`find.text` תופס גם את הכפתור וגם את פריט התפריט** כששניהם מציגים את אותו
   מצב. בתפריט פתוח יש להשתמש ב-`.last`.

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

### 1.2 הכותרת ארוכה — נחתכת ולא דוחפת את כפתור הסגירה

**למה:** `bookTitle` ארוך ("חיפוש ב<שם ספר ארוך מאוד>") ב-`Stack` עם ריפוד
אופקי של 48; בלי `ellipsis` הוא היה גולש מעל הכפתור.

**מה לבדוק:** עם כותרת של 200 תווים — `tester.takeException()` הוא `null`,
ורוחב ה-`Text` אינו עולה על רוחב הדיאלוג פחות 96.

### 1.3 שורת החיפוש: שלושה פקדים, שלוש כותרות

**למה:** זו התוצאה הסופית של סבב העיצוב — סוג החיפוש בקצה ימין, שדה החיפוש
באמצע, היקף החיפוש בקצה שמאל, ולכל אחד כותרת קטנה מעליו.

**מה לבדוק** (במסך 1400×900):
- `find.text('סוג החיפוש')`, `find.text('מה לחפש')`, `find.text('היקף החיפוש')` —
  כל אחת `findsOneWidget`.
- סדר ה-`dx` ב-RTL: מרכז "סוג החיפוש" > מרכז "מה לחפש" > מרכז "היקף החיפוש".
- שלוש הכותרות באותו `dy` (אותה שורה).
- `find.byType(LabeledInput)` מחזיר לפחות שלושה.

### 1.4 שלושת הפקדים באותו גובה

**למה:** זו הדרישה שהובילה ל-`SearchScopeMenuButton.height` ול-
`AppInputTokens.height` בכפתור המצב. גובה שונה בין הפקדים היה מה שגרם לשורה
להיראות שבורה.

**מה לבדוק:** `tester.getSize()` של כפתור המצב (`searchModeButtonKey`), של
ה-`TextField` של שדה החיפוש, ושל השדה שבתוך `SearchScopeMenuButton` —
כל שלושתם באותו `height` (48 כשאין `SettingsBloc`, כלומר `compactMenuMode=false`).

### 1.5 מצב תפריטים מצומצם מקטין את שלושת הפקדים יחד

**למה:** הגובה נגזר מ-`compactMenuMode` בשלושה מקומות נפרדים; קל לשכוח אחד.

**הכנה:** להוסיף `BlocProvider<SettingsBloc>` מדומה עם `compactMenuMode: true`
ל-harness (כרגע ה-harness אינו מספק אותו, ולכן נופלים ל-`false`).

**מה לבדוק:** שלושת הגבהים הם 36 ולא 48, וגודל הטקסט בשדה ההיקף הוא 13.

### 1.6 השורה נשברת במסך צר

**למה:** מתחת ל-760 פיקסלים אין מקום לשלושה פקדים, ובלי השבירה הטקסט בשדות
נחתך — בדיוק התקלה שדווחה ממחשב 11 אינץ'.

**מה לבדוק:**
- ב-1400 רוחב: שלוש הכותרות באותו `dy`.
- ב-700 רוחב: "מה לחפש" ב-`dy` קטן יותר מ"סוג החיפוש" ומ"היקף החיפוש"
  (שדה החיפוש עלה לשורה נפרדת מעל).
- בשני המקרים `tester.takeException()` הוא `null` (אין overflow).

### 1.7 חלוקת הרוחב בין שדה החיפוש לשדה ההיקף

**למה:** הרוחב הקשיח (220) הוא שקטע את הטקסט; היחס 3:2 הוא התיקון.

**מה לבדוק:** במסך 1400 — רוחב שדה החיפוש גדול מרוחב שדה ההיקף, והיחס
ביניהם קרוב ל-1.5 (סטייה מותרת). כפתור סוג החיפוש ברוחב קבוע 128.

### 1.8 בחירת סוג חיפוש דרך התפריט

**מה לבדוק:**
- לחיצה על `searchModeButtonKey` פותחת תפריט עם שלושת הפריטים
  ('מדויק', 'מתקדם', 'מקורב').
- בחירת 'מתקדם' משנה את הטקסט על הכפתור ל'מתקדם'.
- ה-`SearchBloc` קיבל `SetSearchMode` בחיפוש חדש, ו-`SetSearchModeWithoutSearch`
  בעריכת טאב (`editTab`) — שני המסלולים.

### 1.9 הכפתור הנבחר בלי אייקון

**למה:** דרישה מפורשת — האייקון נשאר בפריטי התפריט בלבד.

**מה לבדוק:** בתוך `find.byKey(searchModeButtonKey)` יש בדיוק `Icon` אחד,
והוא `FluentIcons.chevron_down_16_regular`.

### 1.10 התפריט נפתח ברוחב הכפתור

**למה:** זה מה שגורם לו להיראות כמו תפריט היקף החיפוש שלצדו.

**מה לבדוק:** אחרי פתיחת התפריט, רוחב ה-`PopupMenuItem` הראשון גדול או שווה
לרוחב הכפתור (`minWidth` מועבר מרוחב העוגן).

### 1.11 מעבר מצב שומר את אפשרויות המצב הקודם לסשן

**למה:** `_swapGlobalOptionsForModeChange` — לכל מצב סט אפשרויות עצמאי, וזו
לוגיקה שקל לשבור כשנוגעים בבורר המצב.

**מה לבדוק:** לסמן אפשרות במצב מדויק, לעבור למתקדם, לחזור למדויק —
האפשרות עדיין מסומנת. ובמקביל: אפשרות שסומנה במתקדם אינה מופיעה במדויק.

### 1.12 "החרגת תוצאות" מקופל בחיפוש חדש

**הכנה:** הקטע מוצג רק במצב **מתקדם** ורק כש-`onSearch == null` ו-
`returnResultOnSubmit == false`. הדרך היציבה: `SearchDialog(initialSearchMode:
SearchMode.advanced)`.

**מה לבדוק:**
- קיים `ActionButton.ghost` עם הטקסט `החרגת תוצאות`.
- **לא** קיים שדה עם `hintText: 'מילים שלא יופיעו בתוצאות'`.
- אחרי `tap` + `pumpAndSettle`: השדה מופיע, וגם תווית הקטע.

### 1.13 החרגה קיימת נפתחת מראש בעריכה

**למה:** `_showNegativeSection` מאותחל ב-`initState` מתוך תוכן
`negativeQueryController`. אם מישהו יאתחל אותו ל-`false` קבוע, עריכת חיפוש
עם החרגה תסתיר אותה — והמשתמש יריץ חיפוש עם סינון שהוא לא רואה.

**מה לבדוק:** `SearchingTab` שה-`negativeQueryController.text` שלו לא ריק,
מועבר כ-`editTab` → השדה מוצג מיד עם הטקסט, בלי שום לחיצה.

### 1.14 סגירת ההחרגה מנקה את השדה — **הטסט הכי חשוב ברשימה**

**למה:** קיפול בלי ניקוי משאיר סינון פעיל שאינו נראה במסך.

**מה לבדוק:**
1. לפתוח את הקטע ולהקליד בו `tester.enterText(..., 'רש"י')`.
2. לוודא ש-`tab.negativeQueryController.text` אינו ריק.
3. ללחוץ על כפתור ה-X (tooltip `בטל את ההחרגה`).
4. `expect(tab.negativeQueryController.text, isEmpty)`.
5. הכפתור המקופל `החרגת תוצאות` חזר, והשדה נעלם.

### 1.15 תפריט ברירות המחדל של החיפוש הרגיל

**למה:** שני כפתורים רחבים אוחדו לתפריט אחד. האיחוד לא אמור לגרוע יכולת —
הטסט הוא מה שמוודא את זה.

**מה לבדוק:**
- קיים `IconButton` עם tooltip `ברירות מחדל לחיפוש רגיל`, והוא באותו `dy`
  של הכותרת `אפשרויות מילה` (ולא בשורה נפרדת מתחת לשבבים).
- לחיצה פותחת תפריט עם `CheckboxMenuButton` לכל מפתח ב-
  `SearchQueryBuilder.exactWordOptionKeys`, ועוד שני `MenuItemButton`:
  `קבע את המרווח הנוכחי (N) כברירת מחדל` ו-`חזרה לברירת המחדל השמורה`.
- סימון תיבה: `SearchDefaults.loadExactDefaults()[key] == true`, **וגם**
  ה-`FilterChip` המתאים בחלונית נצבע כנבחר מיד.
- התפריט לא נסגר בסימון (`closeOnActivate: false`).

### 1.16 "חזרה לברירת המחדל השמורה" מאפס גם אפשרויות וגם מרווח

**מה לבדוק:**
1. `SearchDefaults.saveExactDefaults({...})` + `SearchDefaults.saveDistanceDefault(5)`.
2. לשנות במסך: לסמן שבב אחר ולשנות את ה-`SpinBox`.
3. ללחוץ על הפריט בתפריט.
4. `globalSearchOptions` שווה לברירת המחדל השמורה.
5. ה-bloc קיבל `UpdateDistance(5)` בחיפוש חדש, ו-`UpdateDistanceWithoutSearch(5)`
   בעריכה — שני המסלולים.

### 1.17 "קבע את המרווח הנוכחי כברירת מחדל" מציג הודעה

**מה לבדוק:** הפריט מציג את הערך הנוכחי בטקסט שלו, ולחיצה עליו קוראת
ל-`SearchDefaults.saveDistanceDefault` ומציגה `UiSnack` עם
`LibraryMessages.distanceSetAsDefault`.

### 1.18 אין גולל בתוך גולל

**למה:** קודם היה `SizedBox(height: 260)` עם `SingleChildScrollView` בפנים,
בתוך `SingleChildScrollView` חיצוני — שני פסי גלילה ותוכן שנחתך בגובה שרירותי.

**מה לבדוק:**
- `find.descendant(of: find.byKey(tourSearchDialogTargetKey), matching:
  find.byType(SingleChildScrollView))` מחזיר בדיוק אחד, בכל אחד משלושת המצבים.
- אין `SizedBox` עם `height: 260` בעץ.

### 1.19 מצב מקורב אינו מציג אפשרויות מילה

**למה:** `_buildModeContent` מוסיף את שורת אפשרויות המילה רק ב-exact ו-advanced.

**מה לבדוק:** במצב מקורב — `find.text('אפשרויות מילה')` הוא `findsNothing`,
ושדה המרחק מוצג עם התווית `מרחק חיפוש` (ולא `מרווח בין מילים`).

### 1.20 Enter מפעיל חיפוש גם כשהפוקוס מחוץ לשדה

**למה:** `FocusScope.onKeyEvent` ברמת הדיאלוג, עם חריג ל-
`_advancedControlsHasFocus` (שדות המרווח/מילה חילופית מטפלים ב-Enter בעצמם).

**מה לבדוק:** Enter כשהפוקוס על גוף הדיאלוג פותח חיפוש; Enter כשהפוקוס בשדה
"מרווח למילה הבאה" אינו סוגר את הדיאלוג פעמיים.

---

## 2. `test/search/search_scope_chips_test.dart` — קובץ חדש

הרכיבים: `SearchScopeChips` ו-`activeScopeFilters` מ-`lib/search/view/search_scope_menu.dart`.
שניהם ניתנים לבדיקה בלי לבנות את הדיאלוג כולו.

### 2.1 `activeScopeFilters` — קטגוריות מיוצגות בתגית אחת

**למה:** ההתנהגות מכוונת: בחירת חמש קטגוריות אינה מייצרת חמש תגיות אלא
תגית אחת "כל הספרים" עם `partial: true`.

**מה לבדוק:** `selected: {'/תנ"ך', '/משנה'}` → רשימה באורך 1, `label == 'כל הספרים'`,
`partial == true`.

### 2.2 `'/'` לבדו אינו סינון

**מה לבדוק:** `selected: {'/'}` → רשימה ריקה. וכך גם `selected: {}`.

### 2.3 תוויות ה-facets הממדיים

**מה לבדוק:** לכל אחד — התווית הצפויה:

| facet | תווית |
|---|---|
| `FacetHelper.baseDimensionFacet` | `ספרי יסוד` |
| `${eraDimensionPrefix}ראשונים` | `ראשונים` |
| `${authorDimensionPrefix}רש"י` | `רש"י` |

### 2.4 `onRemove` של קטגוריות משאיר את הממדים

**למה:** ההסרה מחזירה `dimensions.toSet()` ולא סט ריק — הסרת "כל הספרים"
לא אמורה לבטל גם את "ספרי יסוד".

**מה לבדוק:** עם קטגוריה + facet ממדי, קריאה ל-`onRemove` של התגית הראשונה
מעבירה ל-`onChanged` סט שמכיל רק את הממדי.

### 2.5 `onRemove` של ממד מסיר רק אותו

**מה לבדוק:** עם שני facets ממדיים, הסרת אחד משאירה את השני ואת הקטגוריות.

### 2.6 `SearchScopeChips` ריק כשאין סינון

**מה לבדוק:** `find.byType(InputChip)` הוא `findsNothing`, והרכיב מחזיר
`SizedBox.shrink` (גובה 0) — כדי שלא ייווצר רווח מיותר בשורה.

### 2.7 תגית חלקית מקבלת אייקון

**מה לבדוק:** לתגית `partial` יש `avatar` עם
`FluentIcons.checkbox_indeterminate_24_regular`; לתגית ממדית אין `avatar`.

### 2.8 לחיצה על ה-X של תגית מפעילה `onChanged`

**מה לבדוק:** `tester.tap` על אזור המחיקה של ה-`InputChip` קורא ל-`onChanged`
עם הסט הצפוי.

---

## 3. `test/search/search_scope_menu_field_test.dart` — קובץ חדש

הרכיב: `SearchScopeMenuButton` (השדה בלבד — לא העץ שנפתח).

### 3.1 הרמז מתאר את המצב

**למה:** זו הבחירה שהתקבלה אחרי שהרמז "סינון לפי ספר או מחבר" נמצא לא ברור.

**מה לבדוק:**
- בלי סינון: `hintText == 'כל הספרייה'`.
- עם סינון: `hintText == 'צמצום נוסף'`.

### 3.2 אין עיגול מונה

**למה:** הוסר במפורש.

**מה לבדוק:** `find.byType(Badge)` הוא `findsNothing` בכל מצב, כולל כאשר
`showChips: false` ויש שלושה סינונים פעילים (המצב שבו ה-Badge היה מופיע).

### 3.3 סמל הסינון נצבע כשיש סינון

**מה לבדוק:** בלי סינון — `Icon.color == colorScheme.onSurfaceVariant`;
עם סינון — `colorScheme.primary`.

### 3.4 `height` נאכף

**מה לבדוק:** `SearchScopeMenuButton(height: 48)` → גובה השדה בפועל 48.
עם `height: null` — הגובה נגזר מהתוכן ואינו קבוע.

### 3.5 גודל הטקסט מתיישר לשדה החיפוש

**מה לבדוק:** `style?.fontSize` ו-`decoration?.hintStyle?.fontSize` שווים
ל-`AppInputTokens.fontSize(false)` (=16), ועם `compactMenuMode: true` ל-13.

### 3.6 השדה ללא מסגרת ובמילוי האחיד

**מה לבדוק:** `decoration.filled == true`,
`fillColor == AppInputTokens.fillColor(context)`, וכל ה-borders
עם `BorderSide.none`.

### 3.7 `showChips: false` אינו מצייר תגיות בתוך הפקד

**למה:** בדיאלוג התגיות מוצגות בשורה נפרדת; תגיות כפולות היו מבלבלות.

**מה לבדוק:** עם `showChips: false` ועם סינון פעיל —
`find.descendant(of: find.byType(SearchScopeMenuButton), matching:
find.byType(InputChip))` הוא `findsNothing`.

---

## 4. `test/widgets/labeled_input_test.dart` — קובץ חדש

הרכיב: `lib/widgets/text/labeled_input.dart`.

### 4.1 התווית מעל השדה ואינה חופפת לו

**למה:** זו בדיוק התקלה שהובילה ליצירת הרכיב — תווית צפה בתוך שדה מלא נתלית
על שפתו ודוחקת את התוכן והכפתורים מהמרכז.

**מה לבדוק:** `getRect(label).bottom <= getRect(child).top`.
(אימות מקביל הורץ ידנית בזמן העיצוב ועבר: שדה בגובה 48, התווית בין 4 ל-16
פיקסלים מראשו.)

### 4.2 `width` מגביל את שניהם

**מה לבדוק:** `LabeledInput(width: 150, ...)` — רוחב התווית והשדה יחד אינו
עולה על 150, גם כשהתווית ארוכה.

### 4.3 תווית ארוכה נחתכת ולא גולשת

**מה לבדוק:** תווית של 100 תווים ברוחב 128 — `takeException()` הוא `null`,
וה-`Text` מוגדר `overflow: TextOverflow.ellipsis`.

### 4.4 בלי `width` הרכיב לוקח את רוחב ההורה

**מה לבדוק:** בתוך `SizedBox(width: 400)` — השדה נמתח ל-400.

### 4.5 צבע וגודל התווית מגיעים מה-theme

**מה לבדוק:** `style?.color == colorScheme.onSurfaceVariant` ו-`fontSize == 12` —
כדי שלא יוחזר צבע קשיח.

### 4.6 התווית מיושרת לתחילת השורה ב-RTL

**מה לבדוק:** תחת `Directionality.rtl` — הקצה הימני של התווית מיושר לקצה
הימני של השדה (הריפוד הוא `EdgeInsetsDirectional.only(start: 4)`).

---

## 5. `test/widgets/edge_scrollbar_behavior_test.dart` — קובץ חדש

הרכיב: `lib/widgets/layout/edge_scrollbar_behavior.dart`.

### 5.1 בסביבה RTL פס הגלילה בימין כשמבקשים ימין

**למה:** זה כל הטעם ברכיב. `MaterialScrollBehavior` בברירת מחדל שם פס אנכי
בקצה ה-trailing — בעברית זה **שמאל**.

**מה לבדוק:** `ListView` ארוך ב-`ScrollConfiguration` עם
`EdgeScrollbarBehavior(ScrollbarOrientation.right)` בתוך
`Directionality(textDirection: TextDirection.rtl)` →
`tester.widget<Scrollbar>(...).scrollbarOrientation == ScrollbarOrientation.right`.

**מלכודת:** חובה `debugDefaultTargetPlatformOverride = TargetPlatform.windows`.

### 5.2 שמאל כשמבקשים שמאל

אותו טסט עם `ScrollbarOrientation.left` — מוודא שהרכיב באמת מקבל פרמטר ולא
מקובע לימין (`adaptive_side_pane` מסתמך על שני הכיוונים).

### 5.3 גלילה אופקית — אין פס

**מה לבדוק:** `ListView(scrollDirection: Axis.horizontal)` → `findsNothing`.

### 5.4 מובייל — אין פס

**מה לבדוק:** עם `TargetPlatform.android` ו-`iOS` → אין `Scrollbar`.
זו התנהגות `MaterialScrollBehavior` שהרכיב משכפל, וקל לאבד אותה בשכתוב.

### 5.5 ה-controller מועבר לפס

**מה לבדוק:** `Scrollbar.controller` זהה ל-`ScrollController` של הרשימה —
בלעדיו הפס לא נגרר.

---

## 6. `test/search/search_dialog_scrollbar_test.dart` — קובץ חדש

### 6.1 פס הגלילה של הדיאלוג בימין

**מה לבדוק:** בדיאלוג בנוי, ה-`Scrollbar` שעוטף את גוף הדיאלוג הוא
`ScrollbarOrientation.right`. גם כאן נדרש `debugDefaultTargetPlatformOverride`.

### 6.2 המרווח נשמר — הפס לא מצויר על התוכן

**למה:** המרווחים הוזזו מ-`Padding` שעטף את הגולל אל `padding` של
`SingleChildScrollView` עצמו. אם מישהו יחזיר אותם החוצה, הפס יחזור לשבת על
תחילת התוכן.

**מה לבדוק:** ה-`SingleChildScrollView` בגוף הדיאלוג מחזיק `padding` לא-null
עם `horizontal` חיובי, ורוחב ה-`Scrollable` שווה לרוחב הדיאלוג.

---

## 7. `test/theme/app_input_tokens_test.dart` — קובץ חדש

### 7.1 `filledDecoration` מחזירה מילוי בלי מסגרת

**מה לבדוק:**
- `filled == true`, `fillColor == AppInputTokens.fillColor(context)`.
- כל שישה ה-borders (`border`, `enabledBorder`, `focusedBorder`,
  `disabledBorder`, `errorBorder`, `focusedErrorBorder`) עם
  `borderSide == BorderSide.none`.
- הרדיוס הוא `AppTokens.borderRadiusAll` — אותו רדיוס של שדה החיפוש.
- `labelText == null` — הרכיב **לא** מקבל תווית פנימית; היא ב-`LabeledInput`.

### 7.2 מצב מושבת מקבל alpha חלש יותר

**מה לבדוק:** `enabled: false` → `fillColor` עם `AppInputTokens.disabledAlpha`,
ו-`fillColor(context, enabled: false)` מחזיר את אותו ערך.

### 7.3 `hintStyle` עובר כמו שהוא

**מה לבדוק:** `filledDecoration(context, hintStyle: s).hintStyle == s`,
ו-`null` כשלא הועבר (כדי שה-theme יכריע).

### 7.4 עוזרי הגודל

**מה לבדוק:** `height(true) == 36`, `height(false) == 48`,
`fontSize(true) == 13`, `fontSize(false) == 16`. טסט טריוויאלי אבל הוא מה
שיתפוס שינוי טוקן שנעשה בלי לחשוב על מי שמסתמך עליו.

---

## 8. `test/widgets/segmented_control_test.dart` — קובץ חדש

הרכיב: `lib/widgets/controls/segmented_control.dart`. שני שדות נוספו לו
בסבב הזה והם עדיין בלי כיסוי.

### 8.1 `SegmentOption.tooltip` מגיע ל-`ButtonSegment`

**למה:** נוסף כדי לשמר את ההסבר לכל מצב חיפוש כשהבורר עבר לרכיב המשותף.

**מה לבדוק:** `tester.widget<SegmentedButton>(...)` — ה-`segments` נושאים את
ה-tooltip שהועבר; ו-`longPress` על מקטע מציג את הטקסט **בלי** לשנות בחירה.

### 8.2 `direction: Axis.vertical` אינו מותח את הגובה

**למה:** זה בדיוק מה שהפיל את הפריסה — `expandedInsets` בכיוון אנכי מבקש
גובה אינסופי, ובתוך גולל אין גובה חסום.

**מה לבדוק:** `AppSegmentedControl(direction: Axis.vertical,
expandToFillWidth: true)` בתוך `SingleChildScrollView` → `takeException()`
הוא `null`.

### 8.3 `expandToFillWidth` בכיוון אופקי כן מותח

**מה לבדוק:** ב-`Row`/`SizedBox(width: 400)` — רוחב ה-`SegmentedButton` הוא 400.

### 8.4 `height` קובע גובה מקטע

**מה לבדוק:** `height: 40` → גובה כל מקטע 40.

### 8.5 `showSelectedIcon: false` מסתיר את סימן ה-✓

**מה לבדוק:** אין `FluentIcons.checkmark_24_regular` בעץ.

---

## 9. `test/search/advanced_search_controls_test.dart` — קובץ חדש

### 9.1 תפריט ברירות המחדל בשורת "אפשרויות מילה"

**מה לבדוק:**
- `IconButton` עם tooltip `ברירות מחדל לחיפוש חדש` באותו `dy` של הטקסט
  `אפשרויות מילה`.
- אין יותר `ActionButton` נפרדים בשם `ברירת מחדל לחיפוש חדש` /
  `חזרה לברירת מחדל`.

### 9.2 "ניקוד"/"טעמים" רק כש-`supportsVocalized: true`

**למה:** קיים בקוד מלפני השינוי, אין לו כיסוי, וקל לשבור אותו כשנוגעים בתפריט.

**מה לבדוק:** עם `false` מפתחות `SearchQueryBuilder.vocalizedWordOptionKeys`
אינם בתפריט; עם `true` — כן.

### 9.3 "חזרה לברירת מחדל" מנקה גם את האפשרויות הפר-מיליות

**מה לבדוק:** אחרי סימון אפשרות במצב פר-מילה (`useGlobalSearchOptions = false`)
— לחיצה על הפריט מרוקנת את `tab.searchOptions` ומחזירה את
`tab.globalSearchOptions` ל-`SearchDefaults.loadDefaults()`.

### 9.4 התוויות מעל השדות ולא בתוכם

**מה לבדוק:**
- `find.byType(LabeledInput)` מחזיר שניים כשמילה נבחרה.
- `decoration?.labelText` הוא `null` ו-`hintText` הוא `'0-30'`.
- מרכז הטקסט `מרווח למילה הבאה` נמצא **מעל** ראש ה-`TextField`.

**מלכודת:** השדות מוצגים רק כש-`perWordInputsEnabled` — נבחרה מילה בודדת.
צריך `tab.queryController.text = 'שלום'` ולמקם את הסמן בתוכה
(`selection = TextSelection.collapsed(offset: 2)`).

### 9.5 בחירת טווח של כמה מילים מנטרלת את השדות הפר-מיליים

**למה:** `perWordInputsEnabled` דורש `_selectedSpans.length <= 1`; מרווח
ומילה חילופית חלים על מילה אחת בלבד.

**מה לבדוק:** עם `selection` שמכסה שתי מילים — `find.byType(LabeledInput)`
מחזיר 0, ותיבות האפשרויות עדיין פעילות.

### 9.6 שבב אפשרות במצב פר-מילה חל על כל המילים שנבחרו

**מה לבדוק:** בחירת טווח של שתי מילים וסימון שבב → `tab.searchOptions` מכיל
מפתח לכל אחת מהן עם הערך `true`.

---

## 10. `test/search/enhanced_search_field_test.dart` — להרחיב את הקיים

### 10.1 כפתור הניקוי מופיע רק כשיש טקסט

**למה:** התנהגות שהגיעה עם `OtzariaSearchField` והחליפה X שהוצג תמיד.

**מה לבדוק:** שדה ריק → אין `FluentIcons.dismiss_24_regular`; אחרי הקלדה → יש.

### 10.2 ניקוי מחזיר את הפוקוס לשדה

**למה:** נוסף במפורש — לחיצה על ה-X גזלה את הפוקוס לכפתור.

**מה לבדוק:** אחרי `tap` על ה-X — `tab.searchFieldFocusNode.hasFocus` הוא `true`.

### 10.3 ניקוי מרוקן גם את אפשרויות החיפוש

**מה לבדוק:** `tab.searchOptions` ו-`tab.globalSearchOptions` ריקים, וה-bloc
קיבל `UpdateSearchQuery('')` ו-`UpdateFacetCounts({})`.

### 10.4 Enter מפעיל חיפוש גם כשהפוקוס לא בשדה

**למה:** ה-`KeyboardListener` שעוטף את השדה קיים בדיוק בשביל זה.

**מה לבדוק:** שליחת `LogicalKeyboardKey.enter` כשה-`searchFieldFocusNode`
אינו בפוקוס → הטאב קיבל כותרת מעודכנת (כמו בטסט הקיים).

---

## 11. עדכון לקבצים קיימים

- `test/tools/tools_launcher_panel_test.dart` — אם הוא מתייחס בשם למחלקה
  `_RightScrollbarBehavior` שנמחקה, להצביע על `EdgeScrollbarBehavior`.
  (בהרצה האחרונה הקובץ עבר, כך שכנראה הוא בודק התנהגות ולא שם.)
- `test/widgets/adaptive_side_pane_test.dart` — אותו דבר לגבי
  `_OuterEdgePaneScrollBehavior`.
- `test/settings/widgets/segmented_settings_tile_test.dart` — לוודא שהוספת
  `direction` ו-`tooltip` ל-`AppSegmentedControl` לא שינתה את התנהגות
  ברירת המחדל (אופקי, בלי tooltip).

---

## מה **לא** צריך טסט

- מראה הכרטיסים והרקעים שהוסרו — צבע רקע אינו חוזה, וטסט עליו נשבר בכל
  שינוי ערכת נושא.
- הסרת ריבוע האייקון ושורת ההסבר מהכותרת — בדיקת "משהו לא קיים" בעיצוב
  נוטה להתיישן; מספיקה הבדיקה החיובית שהכותרת ממורכזת ובגודל הנכון.
- ערכי הריפוד והמרווחים המדויקים (8/10/16/20) — הם ישתנו בסבב העיצוב הבא.
  מה שכן שווה לבדוק הוא **יחסים** (אותו גובה, אותו `dy`, אותו יישור).
