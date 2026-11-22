import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/theme/readable_ink.dart';

/// גובה השורה של הערה אישית, כמו בהערה בטקסט רגיל בכרטיס.
const double personalNoteLineHeight = 1.5;

/// רווח אחרי כל פסקה (Enter). בלעדיו מעבר Enter נראה כמו גלישת שורה אוטומטית.
const double personalNoteParagraphSpacing = 8;

/// סגנונות Quill של הערה אישית, מקור אחד לעורך, לתצוגה בכרטיס ולתצוגה
/// המקדימה, כדי שההערה תיראה בעריכה כמו אחריה.
///
/// ברירת המחדל של Quill היא שורה 1.15 וללא רווח בין פסקאות, צפופה לטקסט עברי
/// מנוקד. הכותרות וגובה שורה שהמשתמש בחר (`line-height`) נשארים של Quill.
quill.DefaultStyles personalNoteStyles(BuildContext context) {
  final base = quill.DefaultStyles.getInstance(context);
  final paragraph = base.paragraph!;
  final lists = base.lists!;
  return base.merge(
    quill.DefaultStyles(
      paragraph: paragraph.copyWith(
        style: paragraph.style.copyWith(height: personalNoteLineHeight),
        verticalSpacing: const quill.VerticalSpacing(
          0,
          personalNoteParagraphSpacing,
        ),
      ),
      lists: lists.copyWith(
        style: lists.style.copyWith(height: personalNoteLineHeight),
      ),
      quote: base.quote!.copyWith(
        style: base.quote!.style.copyWith(height: personalNoteLineHeight),
      ),
      placeHolder: base.placeHolder!.copyWith(
        style: base.placeHolder!.style.copyWith(height: personalNoteLineHeight),
      ),
    ),
  );
}

/// צבע הרקע של כפתור "הדגשה". צבע תוכן קבוע: נשמר בהערה עצמה, ולכן אינו תלוי
/// בערכת הנושא.
const String personalNoteHighlightBackground = '#fff59d';

/// צבע `#rrggbb` או `#aarrggbb` של Quill, או null כשהערך אינו צבע כזה.
Color? parseNoteColor(Object? value) {
  if (value is! String || !value.startsWith('#')) return null;
  var hex = value.substring(1);
  if (hex.length == 6) hex = 'ff$hex';
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// הסגנון ש-Quill ממזג לכל מאפיין (`QuillEditorConfig.customStyleBuilder`):
/// ברקע שנבחר, צבע טקסט קריא עליו ([readableInkOn]), בעורך ובתצוגה בכרטיס.
/// התצוגה הקלה ([NoteDeltaPreview]) מחשבת אותו מאותה פונקציה.
///
/// הפונקציה רואה מאפיין אחד בכל פעם ולא את צבע הטקסט שנקבע במקום אחר, ו-Quill
/// (flutter_quill 11.6.0, `text_line.dart`) ממזג את תוצאתה אחרי החלת הצבע.
/// לכן בעורך ובתצוגת Quill בכרטיס הצבע הקריא גובר גם על צבע טקסט מפורש שנשמר
/// בהערה על רקע מודגש (הערה מיובאת או מודבקת; אין בממשק כפתור צבע טקסט).
/// [NoteDeltaPreview], שמחשבת את הסגנון בעצמה, כן מכבדת צבע מפורש.
TextStyle personalNoteBackgroundInkStyle(quill.Attribute<dynamic> attribute) {
  if (attribute.key != quill.Attribute.background.key) return const TextStyle();
  final background = parseNoteColor(attribute.value);
  return background == null
      ? const TextStyle()
      : TextStyle(color: readableInkOn(background));
}
