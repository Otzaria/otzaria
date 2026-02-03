# מדריך: תיקון שדות טקסט RTL

## סקירה כללית

רכיב `RtlTextField` מתקן בעיות ידועות ב-Flutter Desktop עם שדות טקסט בעברית:

1. **מקשי חיצים הפוכים** - חץ שמאל מזיז ימינה וחץ ימין מזיז שמאלה
2. **Shift+חיצים לא עובד נכון** - בחירת טקסט עם Shift+חיצים מתנהגת הפוך
3. **Collapse של Selection בכיוון הלא נכון** - כשיש טקסט מסומן ולוחצים חץ, הסמן קופץ לקצה הלא נכון
4. **הסמן לא נראה מיד בניווט** - צריך לחכות למחזור ההבהוב כדי לראות את הסמן אחרי תזוזה
5. **הבהוב אינסופי** - הסמן ממשיך להבהב גם כשלא עורכים (בניגוד ל-Word)
6. **תפריט הקשר לא מתאים** - תפריט ברירת המחדל מרווח מדי ולא מעוצב

## התיקונים שבוצעו

### 1. תיקון חיצים בסיסי
- חץ ימינה (ויזואלית) מזיז את הסמן ימינה (+1 offset)
- חץ שמאלה (ויזואלית) מזיז את הסמן שמאלה (-1 offset)

### 2. תיקון Shift+חיצים
- Shift+חץ ימינה מרחיב את הבחירה ימינה (extent +1)
- Shift+חץ שמאלה מרחיב את הבחירה שמאלה (extent -1)
- base נשאר קבוע, extent זז - כמו בכל עורך טקסט סטנדרטי

### 3. Collapse נכון של Selection
כשיש טקסט מסומן ולוחצים חץ (ללא Shift):
- חץ ימינה → הסמן קופץ לסוף הבחירה (offset גבוה יותר)
- חץ שמאלה → הסמן קופץ לתחילת הבחירה (offset נמוך יותר)

### 4. נראות מיידית של הסמן
- בכל לחיצת חץ, הסמן מופיע מיד (reset blink)
- לא צריך לחכות למחזור ההבהוב הבא

### 5. הפסקת הבהוב לאחר Idle
- אחרי 5 שניות ללא פעילות, הסמן מפסיק להבהב ונשאר גלוי
- בלחיצת מקש הבאה, ההבהוב חוזר
- התנהגות דומה ל-Microsoft Word

## איך ליישם?

### שלב 1: הוסף ייבוא

בראש הקובץ, הוסף:

```dart
import 'package:otzaria/widgets/rtl_text_field.dart';
```

### שלב 2: החלף TextField ב-RtlTextField

**לפני:**
```dart
TextField(
  controller: myController,
  focusNode: myFocusNode,
  decoration: InputDecoration(
    hintText: 'הקלד טקסט...',
  ),
  onChanged: (value) {
    // הקוד שלך
  },
)
```

**אחרי:**
```dart
RtlTextField(
  controller: myController,
  focusNode: myFocusNode,
  decoration: InputDecoration(
    hintText: 'הקלד טקסט...',
  ),
  onChanged: (value) {
    // הקוד שלך
  },
)
```

זהו! פשוט החלף `TextField` ב-`RtlTextField` - כל הפרמטרים זהים.

## פרמטרים נתמכים

`RtlTextField` תומך בכל הפרמטרים הנפוצים של `TextField`:

- `controller` - TextEditingController
- `focusNode` - FocusNode
- `decoration` - InputDecoration
- `onChanged` - ValueChanged<String>
- `onSubmitted` - ValueChanged<String>
- `autofocus` - bool
- `keyboardType` - TextInputType
- `textInputAction` - TextInputAction
- `maxLines` - int
- `minLines` - int
- `enabled` - bool
- `style` - TextStyle
- `textAlign` - TextAlign
- `inputFormatters` - List<TextInputFormatter>

## דוגמאות מהפרויקט

### דוגמה 1: שדה חיפוש פשוט (ספרייה)

```dart
RtlTextField(
  controller: searchController,
  focusNode: searchFocusNode,
  autofocus: true,
  decoration: InputDecoration(
    prefixIcon: const Icon(FluentIcons.search_24_regular),
    suffixIcon: IconButton(
      onPressed: () => searchController.clear(),
      icon: const Icon(FluentIcons.dismiss_24_regular),
    ),
    hintText: 'איתור ספר...',
  ),
  onChanged: (value) {
    // טיפול בשינוי
  },
)
```

### דוגמה 2: שדה עם אימות (חיפוש - מרווח)

```dart
RtlTextField(
  controller: spacingController,
  focusNode: spacingFocusNode,
  keyboardType: TextInputType.number,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    FilteringTextInputFormatter.allow(RegExp(r'^([0-9]|[12][0-9]|30)$')),
  ],
  decoration: InputDecoration(
    labelText: 'מרווח למילה הבאה',
    hintText: '0-30',
  ),
  onChanged: (value) {
    // טיפול בשינוי
  },
)
```

### דוגמה 3: שדה עם onSubmitted (איתור)

```dart
RtlTextField(
  controller: refController,
  focusNode: refFocusNode,
  autofocus: true,
  decoration: InputDecoration(
    hintText: 'הקלד מקור מדוייק...',
    suffixIcon: IconButton(
      icon: const Icon(FluentIcons.dismiss_24_regular),
      onPressed: () => refController.clear(),
    ),
  ),
  onChanged: (value) {
    // חיפוש בזמן אמת
  },
  onSubmitted: (value) {
    // פתיחת התוצאה
  },
)
```

## מה קורה מאחורי הקלעים?

1. **זיהוי RTL אוטומטי** - הרכיב בודק את `Directionality.of(context)`
2. **תיקון חיצים מתקדם** - אם RTL, מוסיף `CallbackShortcuts` עם 4 bindings:
   - חיצים רגילים (ללא Shift) - ניווט עם collapse נכון
   - Shift+חיצים - הרחבת/צמצום בחירה
3. **Reset Blink** - בכל לחיצת חץ, מאפס את ה-blink timer ומציג את הסמן מיד
4. **Idle Timeout** - אחרי 5 שניות, מפסיק את ההבהוב (הסמן נשאר גלוי)
5. **תפריט מותאם** - מוסיף `Listener` שתופס לחיצה ימנית ומציג תפריט קומפקטי
6. **השבתת תפריט ברירת מחדל** - משתמש ב-`contextMenuBuilder` להשבתת התפריט המובנה

## לוגיקת הטיפול בחיצים

### מצב 1: יש Selection פעיל + לוחצים חץ (ללא Shift)
```dart
// Collapse לקצה הנכון
if (isRightArrow) {
  // חץ ימינה -> קפוץ לסוף הבחירה (offset גבוה)
  targetOffset = selection.end;
} else {
  // חץ שמאלה -> קפוץ לתחילת הבחירה (offset נמוך)
  targetOffset = selection.start;
}
```

### מצב 2: אין Selection או לוחצים Shift+חץ
```dart
// חישוב offset חדש
offsetChange = isRightArrow ? 1 : -1;  // RTL: ימינה=+1, שמאלה=-1
newOffset = (currentOffset + offsetChange).clamp(0, text.length);

if (extendSelection) {
  // Shift לחוץ - מרחיבים בחירה
  // base קבוע, extent זז
  selection = TextSelection(
    baseOffset: selection.baseOffset,
    extentOffset: newOffset,
  );
} else {
  // ניווט רגיל
  selection = TextSelection.collapsed(offset: newOffset);
}
```

## תפריט ההקשר

התפריט המותאם כולל:

**כשיש טקסט נבחר:**
- גזור
- העתק
- הדבק

**כשאין טקסט נבחר:**
- הדבק
- בחר הכל (רק אם יש טקסט בשדה)

התפריט מעוצב בצורה קומפקטית:
- גובה פריט: 36px (במקום 48px)
- padding: 12px (במקום 16px)
- גודל אייקון: 18px (במקום 20px)
- גודל טקסט: 14px

## שאלות נפוצות

**ש: האם זה עובד גם ב-LTR?**  
ת: כן! הרכיב זוהה אוטומטית את הכיוון. ב-LTR הוא מתנהג כמו TextField רגיל.

**ש: האם אני צריך לשנות משהו בקוד הקיים?**  
ת: לא! פשוט החלף `TextField` ב-`RtlTextField` - כל הפרמטרים זהים.

**ש: מה אם אני צריך פרמטר שלא נתמך?**  
ת: פתח issue או הוסף את הפרמטר ל-`RtlTextField` בקובץ `lib/widgets/rtl_text_field.dart`.

**ש: האם זה משפיע על ביצועים?**  
ת: לא. התיקונים מתבצעים רק כשצריך (RTL) ובצורה יעילה.

## קבצים שכבר משתמשים ב-RtlTextField

### שדות חיפוש ראשיים
- ✅ `lib/library/view/library_browser.dart` - שדה חיפוש בספרייה
- ✅ `lib/find_ref/find_ref_dialog.dart` - שדה איתור מקורות
- ✅ `lib/search/view/search_dialog.dart` - שדות מרווח ומילה חילופית
- ✅ `lib/search/view/enhanced_search_field.dart` - שדה החיפוש הראשי

### שדות חיפוש בספרים
- ✅ `lib/widgets/search_pane_base.dart` - בסיס לכל שדות החיפוש בספרים
- ✅ `lib/text_book/view/commentary_list_base.dart` - חיפוש במפרשים
- ✅ `lib/text_book/view/selected_line_links_view.dart` - חיפוש בקישורים
- ✅ `lib/text_book/view/toc_navigator_screen.dart` - חיפוש בתוכן עניינים

## סיכום

החלפת `TextField` ב-`RtlTextField` היא פשוטה וישירה:

1. הוסף ייבוא: `import 'package:otzaria/widgets/rtl_text_field.dart';`
2. החלף `TextField(` ב-`RtlTextField(`
3. זהו!

הרכיב יטפל אוטומטית בתיקון החיצים ובתפריט ההקשר.
