import 'package:otzaria/book_common/utils/link_anchor_variants.dart';

/// ביטוי RegExp ל-[letter] עטופה בכל אחד מסוגי הסוגריים של סמני המפרשים.
/// המפרש משובץ לווריאנט לפי הנתיב, ולכן טסט לא יניח סוג סוגריים מסוים.
String anyAnchorMarker(String letter) =>
    '(?:${LinkAnchorDelimiter.values.map((d) => RegExp.escape(d.wrap(letter))).join('|')})';
