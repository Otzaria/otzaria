/// ציון מקור אמיתי בתורה בהעתקה: פרשה ועלייה במקום פרק ופסוק.
/// «(ויקרא, פרשת אמור, ששי)» או «(אמור, ששי)».
library;

import 'package:otzaria/text_book/utils/mikra_structure.dart';

/// ערכי ההגדרה «ציון המקור בתורה».
abstract final class TorahCopyCitation {
  /// פרק, כמו היום ("בראשית, פרק א").
  static const String chapter = 'chapter';

  /// ספר, פרשה ועלייה ("ויקרא, פרשת אמור, ששי").
  static const String bookParashaAliyah = 'book_parasha_aliyah';

  /// פרשה ועלייה ("אמור, ששי").
  static const String parashaAliyah = 'parasha_aliyah';
}

/// כותרת המקור לשורה [line], לפי [style]; null — אין ציון אמיתי לשורה
/// (פרק, ספר שאינו בתורה, או שורה לפני העלייה הראשונה), והנתיב הרגיל חל.
String? torahCitationHeader({
  required MikraStructure? mikra,
  required int line,
  required String bookTitle,
  required String style,
}) {
  if (mikra == null || style == TorahCopyCitation.chapter) return null;
  final citation = mikra.citationAt(line);
  if (citation == null) return null;
  return switch (style) {
    TorahCopyCitation.bookParashaAliyah =>
      '$bookTitle, פרשת ${citation.parasha}, ${citation.aliyah}',
    TorahCopyCitation.parashaAliyah =>
      '${citation.parasha}, ${citation.aliyah}',
    _ => null,
  };
}
