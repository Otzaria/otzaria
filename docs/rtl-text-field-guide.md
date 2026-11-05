# מדריך: `RtlTextField`

`RtlTextField` (`lib/widgets/text/rtl_text_field.dart`) הוא שדה הקלט של האפליקציה. הוא עוטף `TextField` ומתקן בעיות של Flutter בשולחן העבודה עם טקסט בעברית: ניווט בחיצים, בחירה, הבהוב הסמן, תפריט הקשר וסמן בשורה רב־שורתית.

`TextField` גולמי מחוץ לקובץ הזה נכשל ב־UIL-011 (`tool/ui_lint/config.yaml`).

## מתי להשתמש במה

| צורך | רכיב |
|---|---|
| שדה חיפוש (אייקון, ניקוי, כפתורי סינון) | `OtzariaSearchField` (`lib/widgets/text/otzaria_search_field.dart`), שבנוי על `RtlTextField` |
| דיאלוג עם שדה אחד | `showInputDialog` (`lib/widgets/dialogs/input_dialog.dart`) |
| כל שדה קלט אחר: טופס, מספר, טקסט רב־שורתי | `RtlTextField` |

כללי העיצוב של השדות (`InputDecoration` מערכת הנושא, שדה מספרי): `docs/design-system/DESIGN_SYSTEM.md`.

## שימוש

```dart
import 'package:otzaria/widgets/text/rtl_text_field.dart';

RtlTextField(
  controller: controller,
  focusNode: focusNode,
  decoration: const InputDecoration(hintText: 'הקלד טקסט...'),
  onChanged: (value) { ... },
  onSubmitted: (value) { ... },
)
```

הפרמטרים הם תת־קבוצה של `TextField`:

- `controller`, `focusNode`, `decoration`
- `onChanged`, `onSubmitted`
- `autofocus` (ברירת מחדל `false`), `enabled` (`true`)
- `keyboardType`, `textInputAction`, `inputFormatters`, `obscureText` (`false`)
- `maxLines` (ברירת מחדל `1`), `minLines`, `expands` (`false`; ממלא את הגובה הזמין, מחייב `maxLines: null` ו־`minLines: null`)
- `style`, `textAlign` (`TextAlign.start`), `textAlignVertical`, `cursorColor`
- `scrollController`

פרמטר שחסר מוסיפים ל־`RtlTextField` עצמו, ומעבירים אותו ל־`TextField` הפנימי.

## מה השדה עושה

### חיצים ובחירה (רק כשהכיוון RTL)

כש־`Directionality.of(context)` הוא RTL, השדה עוטף את `TextField` ב־`CallbackShortcuts` לחיצים שמאלה וימינה:

- **חץ:** מזיז את הסמן בתו אחד, וכשיש בחירה מכווץ אותה.
- **Shift+חץ:** מרחיב או מצמצם את הבחירה בתו.
- **Ctrl+חץ (Alt ב־macOS וב־iOS):** מזיז במילה, ועם Shift בוחר במילה. ההחלטה בין Ctrl ל־Alt היא `usesAltForWordNavigation` ב־`lib/widgets/text/rtl_selection_shortcuts.dart`.

השדה לא מחשב offset בעצמו. הוא מפעיל את ה־Intents המובנים של Flutter, `ExtendSelectionByCharacterIntent` ו־`ExtendSelectionToNextWordBoundaryIntent`, עם `forward` הפוך לכיוון החזותי. הכיוון נקבע לפי התו שליד הסמן: בתוך קטע LTR (אנגלית, ספרות) החץ זז בכיוון החזותי הרגיל. ב־LTR השדה מתנהג כמו `TextField` רגיל.

### הבהוב הסמן

- ההבהוב המובנה של Flutter כבוי לכל האפליקציה (`EditableText.debugDeterministicCursor = true` ב־`lib/main.dart`). השדה מחליף אותו בהחלפת `cursorColor` כל 500ms.
- כל שינוי בטקסט או בבחירה, וכל קבלת פוקוס, מציגים את הסמן מיד ומתחילים מחזור חדש.
- אחרי 8 שניות בלי פעולה ההבהוב נעצר והסמן **נעלם** עד הפעולה הבאה. גם ביציאה מהשדה הסמן נעלם.
- הסמן ברוחב 1 (ברירת המחדל של Flutter היא 2).

### תפריט הקשר

- `contextMenuBuilder` מחזיר תפריט ריק, ולכן תפריט ברירת המחדל של Flutter לא מופיע.
- לחיצה ימנית (`Listener`, כפתור 2) פותחת `showMenu` קומפקטי. במגע, לחיצה ארוכה פותחת אותו תפריט במקום סרגל הכלים של Flutter, בלי לקחת פוקוס.
- הפריטים:
  - "גזור" ו"העתק", כשיש בחירה.
  - "הדבק", תמיד.
  - קו מפריד ו"בחר הכל", כשיש טקסט בשדה.
- מידות: פריט בגובה 36, ריפוד אופקי 12, אייקון 18 (Fluent), טקסט 14, פינות `AppTokens.borderRadiusAll`.
- גזירה והדבקה מהתפריט קוראות ל־`onChanged` ידנית, כי שינוי ישיר של `controller.text` לא מפעיל אותו.

### שורות בטקסט רב־שורתי

בשדה עם `maxLines` שאינו 1 השדה עוקף באג של מנוע Flutter (flutter/flutter#178945): סמן בשורת RTL שמסתיימת ב־`\n` מוצג במקום שגוי. השדה מחזיק controller פנימי שבו כל שבירת שורה היא `\r\n`, ומסנכרן אותו עם ה־controller שלך, שבו נשאר `\n`. `onChanged`, `onSubmitted`, ההעתקה וההדבקה מקבלים את הטקסט הנקי. המימוש: `lib/widgets/text/rtl_hard_break_workaround.dart`.

- הבחירה מצוירת ב־`BoxWidthStyle.tight`, כדי שבחירה בטקסט RTL רב־שורתי לא תימתח עד הקצה השמאלי.

### Android

ב־Android עם `focusNode` חיצוני, `autofocus` לא מועבר ל־`TextField`. במקומו השדה פותח את המקלדת אחרי הפריים הראשון (`requestKeyboard`), וכך גם כשה־`focusNode` כבר בפוקוס בבנייה.

## בדיקות

הבדיקות של השדה נמצאות ב־`test/widgets/text/`:

- `rtl_text_field_editing_test.dart`
- `rtl_text_field_word_selection_test.dart`
- `rtl_text_field_cursor_blink_test.dart`
- `rtl_text_field_context_menu_test.dart`
- `rtl_text_field_hard_break_test.dart`
- `rtl_text_field_expands_test.dart`
- `rtl_text_field_selection_boxes_test.dart`
- `rtl_selection_shortcuts_test.dart`

בדיקת האכיפה של UIL-011: `test/design_system/ui_lint_test.dart`.
