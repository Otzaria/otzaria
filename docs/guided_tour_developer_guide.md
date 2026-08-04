# מדריך מפתח: הוספת פריטים לסיור המודרך

מסמך זה מיועד למפתחים שמוסיפים או משנים שלבים, יעדי spotlight, פעולות מקדימות או טיפים חיים בסיור המודרך של אוצריא.

## מבנה הקבצים

- `lib/tour/models/tour_step.dart` - הגדרת `TourStep`, אזורי spotlight ופעולות מעבר.
- `lib/tour/models/tour_steps.dart` - רשימת השלבים, הטקסטים והסדר.
- `lib/tour/models/tour_shortcuts.dart` - הטקסט שממלא את `{shortcut}` בגוף שלב.
- `lib/tour/bloc/tour_cubit.dart` - התחלה, מעבר שלבים, דילוג, סיום ו-autoplay.
- `lib/tour/tour_target_keys.dart` - מזהי `GlobalKey` לאלמנטים שמסומנים בחלון השקוף.
- `lib/tour/view/tour_overlay_screen.dart` - ציור ה-overlay, מיקום הכרטיס וחישוב rects.
- `lib/navigation/main_window_screen.dart` - ביצוע פעולות לפני שלב: ניווט, פתיחת דיאלוג, פתיחת תפריט, בחירת טאב.

## הוספת שלב

1. הוסף ערך ל-`TourSpotlightArea` אם צריך אזור חדש.
2. הוסף ערך ל-`TourStepAction` אם צריך פעולה לפני הצגת השלב.
3. הוסף `TourStep` במקום המתאים ב-`TourSteps.build`.
4. טפל בפעולה החדשה ב-`_handleTourStepChanged`.
5. חבר `GlobalKey` או resolver אם צריך spotlight מדויק.
6. הוסף את הכותרת ואת הגוף ל-`lib/settings/l10n/settings_en.arb` והרץ
   `dart run tool/generate_settings_l10n.dart`. ראו "תרגום" למטה.
7. עדכן או הוסף בדיקות ב-`test/tour/tour_cubit_test.dart`.

```dart
const TourStep(
  id: 'my_new_button',
  title: 'פעולה חדשה',
  body: 'כאן מסבירים מה הכפתור עושה.',
  area: TourSpotlightArea.myNewButton,
  action: TourStepAction.openRelevantScreen,
)
```

`id` חייב להיות יציב וייחודי. הוא משמש למעבר בין שלבים, בדיקות, resolver-ים ונקודות טיפול מיוחדות.

## תרגום

הסיור מוצג גם באנגלית. **הטקסט העברי הוא מפתח התרגום** — הכרטיסים מתרגמים
אותו בעת הציור, והתרגום עצמו יושב ב-`lib/settings/l10n/settings_en.arb`.
לכן כותרת או גוף חדשים חייבים ערך ב-ARB, ואחריו הרצת המחולל:

```bash
dart run tool/generate_settings_l10n.dart
```

הטקסט מגיע לכרטיס דרך `step.title` / `step.body`, כלומר דרך משתנה — והסורק
של הולידציה רואה רק מחרוזות קבועות. הכיסוי נשמר לכן על ידי
`test/settings/l10n/settings_variable_labels_test.dart`, שבונה את השלבים
בפועל ונכשל על כותרת או גוף בלי תרגום. אין צורך לעדכן אותו בהוספת שלב.

**הגוף חייב להישאר מחרוזת קבועה**, אחרת אין לו מפתח. ערך משתנה נמסר
כ-placeholder: קיצור מקלדת דרך `shortcut:` שממלא את `{shortcut}` (הקיצור
נפתר בעת הציור ב-`tour_shortcuts.dart`, כדי שתוויות הניווט שבתוכו יתורגמו
גם הן).

תווית ממשק שמצוטטת בתוך הטקסט ואינה מתורגמת בעצמה (למשל פריט בתפריט
הימני) נשארת עברית גם בתרגום האנגלי — המשתמש צריך למצוא על המסך בדיוק את
מה שכתוב בכרטיס. חץ מסלול `←` מתהפך ל-`→` בתרגום.

## סוגי שלבים

שלב הסבר כללי במרכז המסך:

```dart
const TourStep(
  id: 'welcome',
  title: 'כותרת',
  body: 'טקסט הסבר קצר',
  area: TourSpotlightArea.center,
  isDialog: true,
)
```

שלב שמסמן אזור במסך:

```dart
const TourStep(
  id: 'library_search',
  title: 'חיפוש מהיר בספרייה',
  body: 'הקלד כאן שם ספר, מחבר או נושא.',
  area: TourSpotlightArea.librarySearch,
  action: TourStepAction.openLibrary,
)
```

## סימון widget בחלון השקוף

כאשר היעד קיים בעץ ה-widgets, העדף `GlobalKey` על חישוב ידני.

### הוספת key

הוסף key ב-`lib/tour/tour_target_keys.dart`:

```dart
final GlobalKey tourMyButtonTargetKey = GlobalKey(
  debugLabel: 'tour_my_button_target',
);
```

אם ה-widget מופיע פעם אחת בלבד בממשק, אפשר להצמיד את ה-key ישירות:

```dart
IconButton(
  key: tourMyButtonTargetKey,
  icon: const Icon(FluentIcons.search_24_regular),
  onPressed: _handleSearch,
)
```

אם יכולים להיות כמה מופעים במקביל, למשל בכמה טאבים, הצמד את ה-key רק למופע הפעיל:

```dart
IconButton(
  key: widget.enableTourTargets ? tourMyButtonTargetKey : null,
  icon: const Icon(FluentIcons.search_24_regular),
  onPressed: _handleSearch,
)
```

כך נמנעת שגיאת `Duplicate GlobalKey`.

### הוספת key לפריט קיים שאין לו key

רוב ה-widgets באפליקציה לא נבנו מראש עם key לסיור. כשמוסיפים שלב חדש, צריך להוסיף נקודת עיגון במקום שבו היעד מצויר בפועל.

פעל לפי הסדר הזה:

1. מצא את ה-widget שהמשתמש אמור לראות דרך ה-spotlight: כפתור, שורת חיפוש, פריט תפריט, טאב, כרטיס וכו'.
2. אם ה-widget מקבל `key`, העבר אליו את ה-`GlobalKey` ישירות.
3. אם ה-widget לא מקבל `key`, עטוף אותו ב-`KeyedSubtree`.
4. אם זה widget משותף, הוסף לו פרמטר אופציונלי כמו `tourTargetKey`.
5. אם יכולים להיות כמה מופעים במקביל, הוסף גם תנאי כמו `enableTourTargets` כדי שרק המופע הפעיל יקבל את ה-key.

דוגמה לפריט מקומי שאפשר לעטוף:

```dart
KeyedSubtree(
  key: tourMyPanelTargetKey,
  child: MyPanel(...),
)
```

דוגמה ל-widget משותף:

```dart
class MySharedButton extends StatelessWidget {
  const MySharedButton({
    super.key,
    this.tourTargetKey,
  });

  final Key? tourTargetKey;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: tourTargetKey,
      icon: const Icon(FluentIcons.search_24_regular),
      onPressed: _handleTap,
    );
  }
}
```

שימוש:

```dart
MySharedButton(
  tourTargetKey: enableTourTargets ? tourMyButtonTargetKey : null,
)
```

אם צריך לסמן אזור רחב יותר מהכפתור עצמו, הוסף key למעטפת בגודל הנכון ולא לכפתור הפנימי.

### חיבור key ל-resolver

ב-`main_window_screen.dart` חבר את ה-key ל-rect:

```dart
case 'my_new_button':
  return _rectForGlobalKey(tourMyButtonTargetKey);
```

אם רק שלב ספציפי דורש חישוב מיוחד, הוסף override לפי `step.id` לפני ה-`switch` הכללי:

```dart
if (step.id == 'my_special_step') {
  return _rectForGlobalKey(tourSpecialTargetKey);
}
```

אם שלב אחד צריך להאיר כמה אזורים יחד, החזר רשימת rects מ-`_resolveTourTargetRects`:

```dart
if (step.id == 'my_complex_step') {
  final firstRect = _rectForGlobalKey(tourFirstTargetKey);
  final secondRect = _rectForGlobalKey(tourSecondTargetKey);
  return [
    if (firstRect != null) firstRect,
    if (secondRect != null) secondRect,
  ];
}
```

## דיוק spotlight

הצמד את ה-key ל-widget שהמשתמש אמור לראות דרך החלון השקוף. key על מעטפת רחבה מדי ייצור rect גדול מדי וסימון לא מדויק.

בדיאלוגים, בדרך כלל עדיף להצמיד key לתוכן היציב או לאזור הפנימי שמעניין את הסיור, ולא למעטפת העליונה של הדיאלוג. אם צריך לכלול כותרת או כפתורי פעולה, הרחב את ה-rect ב-helper ייעודי:

```dart
Rect? _myDialogTourRect() {
  final contentRect = _rectForGlobalKey(tourMyDialogContentKey, inflate: 0);
  if (contentRect == null) return null;

  return Rect.fromLTRB(
    contentRect.left - 24,
    contentRect.top - 72,
    contentRect.right + 24,
    contentRect.bottom + 72,
  );
}
```

הרחב רק לפי צורך ממשי: כותרת, כפתורי פעולה או padding חיצוני.

## פריטי ניווט

בפריטי ניווט יש להחליט אם השלב מסמן רק את הכפתור או את כל הפריט כולל התווית.

- לסימון הכפתור בלבד, השתמש ב-key שעל ה-`IconButton`.
- לסימון הפריט כולו, השתמש ב-key שעל מעטפת הפריט.

כאשר מוסיפים שלב שמסמן פריט ניווט מלא, השתמש ב-helper שמחזיר rect לפי מפתח הפריט:

```dart
Rect? _navItemTourRect(int index) {
  return _rectForGlobalKey(
    tourMainNavigationItemTargetKeys[index],
    inflate: 2,
  );
}
```

## אזור משוער ללא key

אם אין widget יציב להצמד אליו, אפשר להשתמש באזור מחושב ב-`tourTargetRectFor` בתוך `tour_overlay_screen.dart`:

```dart
case TourSpotlightArea.myArea:
  rect = Rect.fromLTWH(110, 80, width - 220, 78);
```

השתמש באזור מחושב רק עבור layout יציב. אם היעד קיים כ-widget, עדיף `GlobalKey`.

## פעולות לפני הצגת שלב

`TourStepAction` מגדיר מה צריך לקרות לפני שהשלב מוצג: מעבר למסך, פתיחת דיאלוג, פתיחת תפריט, בחירת טאב וכו'.

```dart
case TourStepAction.openSettings:
  context.read<NavigationBloc>().add(
        const NavigateToScreen(Screen.settings),
      );
```

אם הפעולה דורשת שהמסך ייבנה לפני שמחפשים את היעד, השתמש ב-post-frame callback:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _scheduleTourTargetRebuilds(remainingFrames: 4);
});
```

אם שלב פותח דיאלוג או חלונית זמנית, סגור אותה במעבר לשלב שלא צריך אותה. כך שלבים חדשים לא יוסתרו על ידי UI שנפתח בשלב קודם.

## דיאלוגים ו-overlay

כאשר שלב פותח דיאלוג, השתמש ב-root navigator אם ה-overlay של הסיור צריך להיות מעליו:

```dart
showDialog(
  context: context,
  useRootNavigator: true,
  builder: (context) => const MyDialog(),
);
```

אם הדיאלוג נפתח במיוחד עבור שלב בסיור, שקול להשתמש ב-barrier שקוף כדי שההכהיה תגיע רק מ-`SpotlightOverlay`.

אחרי פתיחת דיאלוג, תפריט או טאב, הבא את overlay הסיור קדימה ובקש חישוב rect מחדש:

```dart
_bringTourOverlayToFront();
_scheduleTourTargetRebuilds(remainingFrames: 4);
```

## פתיחת תפריטים ופריטי תפריט

לתפריטים יש שני דפוסים:

- `ResponsiveActionBar` מקבל `overflowButtonKey` ו-`menuItemKeysByTooltip`.
- `AppContextMenuRegion` מקבל `menuItemKeysByLabel`.

```dart
ResponsiveActionBar(
  overflowButtonKey: tourOverflowTargetKey,
  menuItemKeysByTooltip: {
    'חיפוש': tourOverflowSearchTargetKey,
    'הדפסה': tourOverflowPrintTargetKey,
  },
  actions: actions,
  alwaysInMenu: menuActions,
  maxVisibleButtons: maxButtons,
)
```

אם השלב מצביע על פריט בתת-תפריט, פתח קודם את התפריט הראשי, ואז את תת-התפריט ב-post-frame נוסף. אחרי כל פתיחה בקש rebuild ליעדי הסיור.

## כרטיסי הסבר ואנימציות

מסך הסבר במרכז משתמש ב-`isDialog: true` וב-`TourSpotlightArea.center`. שלבים כאלה אינם נספרים בנקודות ההתקדמות אם הם מוגדרים כדיאלוג.

כרטיסי הסבר רגילים בתחתית המסך יכולים להתחלף באנימציה, אבל המעברים בין כרטיס ממורכז לכרטיס תחתון צריכים להיות ללא אנימציה:

- יציאה ממסך פתיחה ממורכז אל שלב ההסבר הראשון.
- כניסה למסך הסיום הממורכז.

כאשר משתמשים ב-`AnimatedSwitcher`, עגן את layout ההחלפה לתחתית כדי שכרטיס חדש לא יתחיל ממיקום זמני:

```dart
layoutBuilder: (currentChild, previousChildren) {
  return Stack(
    alignment: AlignmentDirectional.bottomStart,
    children: [
      ...previousChildren,
      if (currentChild != null) currentChild,
    ],
  );
},
```

## סיור מלא מול סיור מקוצר

`TourSteps.build` מקבל `libraryLoaded`. שלבים שדורשים ספרייה טעונה צריכים להופיע רק בתוך:

```dart
if (libraryLoaded) {
  steps.addAll([
    // שלבים שתלויים בספרייה
  ]);
}
```

אם מוסיפים שלב שמותר גם בלי ספרייה, הוסף אותו אחרי הבלוק הזה. אם מוסיפים שלב שקשור למסך הספרייה הריקה, הוסף אותו לענף `!libraryLoaded`.

## טיפים חיים

טיפים חיים הם כרטיסי הדרכה קצרים שמופיעים לפי פעולות המשתמש גם כשהסיור הרגיל אינו פעיל. הוסף טיפ חי רק כאשר הוא מלמד פעולה נקודתית שהמשתמש כנראה צריך עכשיו.

קבצים רלוונטיים:

- `lib/tour/models/live_tip.dart` - הגדרת `LiveTipId`, `TourInteractionType`, `TourInteraction`, `LiveTipSpec` ו-`liveTipSpecs`.
- `lib/tour/bloc/tour_cubit.dart` - לוגיקת הצגת הטיפים.
- `lib/tour/widgets/live_tip_card.dart` - כרטיס הטיפ.

כדי להוסיף טיפ:

1. הוסף ערך ל-`LiveTipId`.
2. הוסף אירוע ל-`TourInteractionType` רק אם אין אירוע קיים שמתאר את הפעולה.
3. הוסף `LiveTipSpec` לרשימת `liveTipSpecs`.
4. עדכן את `_updateDerivedSignals` אם פעולה מסוימת צריכה לפתור את הטיפ.
5. הוסף תנאי ב-`_resolveNextLiveTip`.
6. שלח `TourInteraction` מהמקום שבו המשתמש ביצע את הפעולה.
7. הוסף בדיקה ב-`test/tour/tour_cubit_test.dart`.

```dart
LiveTipSpec(
  id: LiveTipId.myNewTip,
  area: TourSpotlightArea.reading,
  title: 'כותרת הטיפ',
  description: 'הסבר קצר ומועיל למשתמש.',
)
```

### כללי תצוגה של טיפ

לפני שמוסיפים תנאי חדש ב-`_resolveNextLiveTip`, בדוק שהוא מכבד את כללי התצוגה הקיימים:

| מצב | תוצאה |
|-----|--------|
| הסיור פעיל (`isActive == true`) | לא מציגים טיפ |
| יש כבר טיפ פעיל (`hasActiveLiveTip`) | לא מציגים טיפ נוסף |
| כבר הוצג טיפ כלשהו בסשן הנוכחי (`_sessionTipShown`) | לא מציגים — הטיפ הבא יידחה להפעלה הבאה |
| הטיפ כבר הוצג (`shownTips`) | לא מציגים שוב |
| הטיפ נפתר (`resolvedTips`) | לא מציגים בכלל |
| הסיור הסתיים או דולג, ותנאי הטיפ מתקיים | מציגים |

`shownTips` מיועד לטיפ שכבר הוצג למשתמש. הוא לא יחזור גם אם המשתמש לא ביצע את הפעולה המוצעת.  
`resolvedTips` מיועד לטיפ שכבר אינו רלוונטי כי המשתמש ביצע את הפעולה או כי מצב אחר פתר אותו.

### טיפ מסוג "הידעת?" — מינימום הפעלות

טיפ מסוג "הידעת?" אינו אמור להופיע בהפעלות הראשונות של התוכנה, גם אם תנאי האינטראקציה כבר התקיים. דרוש מינימום הפעלות לפני שהוא מוצג, כדי לא להציף משתמש חדש.

- מספר ההפעלות נשמר ב-`LiveTipStorage.launchCountKey` ומוגדל ב-`registerSession()` פעם אחת בכל עליית חלון.
- בטיפ מבוסס-אינטראקציה (למשל `bookSourceHint`, `printHint`) בדוק את הסף ב-`_resolveNextLiveTip` דרך `_hasLaunchesAtLeast` בנוסף לתנאי האינטראקציה.
- בטיפ מבוסס-טיימר (למשל `customFoldersHint`) הסף מוגדר ב-`DelayedTipSchedule` ונבדק ב-`registerSession()` לפני תזמון הטיימר.

### טיפ מבוסס ותק שימוש (לא מבוסס אינטראקציה)

לא כל טיפ נובע מפעולה נקודתית. טיפ מסוג "הידעת?" יכול להופיע אחרי זמן שימוש מסוים ומההפעלה ה-N ואילך. טיפים כאלה מוגדרים ב-`TourCubit.defaultDelayedTipSchedules` — רשימת `DelayedTipSchedule` שבה כל רשומה קובעת טיפ, מינימום הפעלות והשהיה בסשן:

| טיפ | מינימום הפעלות | השהיה בסשן |
|-----|----------------|-------------|
| `customFoldersHint` | 3 | 2:30 דק' |
| `shortcutsHint` | 5 | 2 דק' |
| `backupHint` | 10 | 2 דק' |

- `registerSession()` ב-`TourCubit` נקרא פעם אחת בעליית החלון הראשי, סופר את ההפעלות (`LiveTipStorage.launchCountKey`) ומתזמן טיימר **רק לטיפ הזכאי הראשון** לפי סדר הרשימה — הסדר קובע עדיפות.
- כשהטיימר יורה מוצג הטיפ דרך אותו מסלול תצוגה של טיפים חיים, אלא אם כבר הוצג טיפ אחר בסשן (`_sessionTipShown`).
- אם החלון נסגר לפני שהטיימר ירה, הטיפ לא סומן כ-`shown` ולכן יופיע בהפעלה הבאה — כך מתממש הכלל "אם השימוש היה קצר, בפעם הבאה".
- `delayedTipSchedules` ו-`printHintMinimumSessionDuration` ניתנים להזרקה דרך ה-constructor כדי לאפשר בדיקות מהירות.

השתמש ב-`primaryValue` כאשר התנאי צריך לזהות קשר בין כמה אירועים, למשל כמה פעולות שנעשו על אותו ספר או אותו טאב.

`_recentInteractions` שומר אינטראקציות אחרונות בחלון זמן קצר, ומשמש לזיהוי דפוסים כמו כמה פעולות קשורות ברצף. כשמוסיפים טיפ שמבוסס על רצף פעולות, העדף להשתמש במנגנון הזה במקום לשמור state מקומי ב-widget.

דוגמת בדיקה בסיסית לטיפ חדש:

```dart
test('shows myNewTip after condition is met', () async {
  final cubit = TourCubit();

  cubit.recordInteraction(
    TourInteraction(type: TourInteractionType.myNewEvent),
  );

  expect(cubit.state.activeLiveTipId, LiveTipId.myNewTip);
  cubit.close();
});
```

## בדיקות חובה

אחרי שינוי בסיור:

```bash
dart format <files you changed>
flutter analyze
flutter test test\tour\tour_cubit_test.dart
```

הוסף בדיקה כאשר:

- מספר השלבים משתנה.
- נוסף `TourSpotlightArea` עם חישוב `Rect`.
- משתנה לוגיקת `tour_status`.
- נוסף behavior כמו autoplay, דילוג, restart או מעבר ידני.
- נוסף יעד spotlight לפריט ניווט או דיאלוג.
- נוסף טיפ חי.

## רשימת בדיקה לפני קומיט

- `id` חדש הוא ייחודי ויציב.
- אין `textDirection: TextDirection.rtl` על `Text` — ה-locale קובע RTL גלובלית; `TextDirection.ltr` רק לתוכן LTR מובהק.
- icons חדשים הם רק מ-`fluentui_system_icons`.
- לא הוצמד `GlobalKey` גלובלי לכמה מופעים במקביל.
- key של spotlight מוצמד ל-widget המדויק.
- בפריטי ניווט נבחר key מתאים: כפתור בלבד או פריט מלא כולל טקסט.
- דיאלוג שנפתח בזמן סיור משתמש ב-root navigator כאשר צריך להציג מעליו spotlight.
- overlay הסיור מובא קדימה אחרי פתיחת דיאלוג/תפריט.
- דיאלוגים וחלוניות זמניות נסגרים במעבר לשלב שלא צריך אותם.
- אין לוגי debug זמניים בקוד.
- אם היעד מופיע רק אחרי ניווט/תפריט/דיאלוג, יש post-frame ו-`_scheduleTourTargetRebuilds`.
- שלבים שתלויים בספרייה נמצאים רק במסלול `libraryLoaded`.
- `flutter analyze` ובדיקות הסיור עוברים.
