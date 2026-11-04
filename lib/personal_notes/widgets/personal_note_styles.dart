import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// גובה השורה של הערה אישית, כמו בהערה בטקסט רגיל בכרטיס.
const double personalNoteLineHeight = 1.5;

/// סגנונות Quill של הערה אישית, מקור אחד לעורך, לתצוגה בכרטיס ולתצוגה
/// המקדימה, כדי שההערה תיראה בעריכה כמו אחריה.
///
/// ברירת המחדל של Quill היא שורה 1.15, צפופה לטקסט עברי מנוקד. הכותרות וגובה
/// שורה שהמשתמש בחר (`line-height`) נשארים של Quill.
quill.DefaultStyles personalNoteStyles(BuildContext context) {
  final base = quill.DefaultStyles.getInstance(context);
  final paragraph = base.paragraph!;
  final lists = base.lists!;
  return base.merge(
    quill.DefaultStyles(
      paragraph: paragraph.copyWith(
        style: paragraph.style.copyWith(height: personalNoteLineHeight),
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
