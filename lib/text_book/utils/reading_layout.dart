/// מיפוי שורות מקור לפריטי הרשימה, מתוך מבנה הספר בלבד (אורך, TOC, מצב)
/// ולא מהתוכן שנטען — כך שטעינה או שחרור אינם מזיזים את המספור.
library;

import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/mikra_structure.dart';

/// מספר הרצות תבניות הכותרת/היישור; נספר רק במצב debug.
int debugReadingTagPatternChecks = 0;

/// מתחת ל-U+1680, `\s` של RegExp ב-Dart תופס רק תווים עד 0x20 ואת U+00A0.
bool _mayBeRegExpSpace(int c) => c <= 0x20 || c == 0xA0 || c >= 0x1680;

/// שתי התבניות דורשות `<` אחרי רווח מוביל, ולכן שורה שמתחילה באות נפסלת בלי RegExp.
bool _matchesLeadingTag(RegExp pattern, String line) {
  if (line.isEmpty) return false;
  final c = line.codeUnitAt(0);
  if (c != 0x3C && !_mayBeRegExpSpace(c)) return false;
  assert(() {
    debugReadingTagPatternChecks++;
    return true;
  }());
  return pattern.hasMatch(line);
}

bool isReadingHeaderLine(String line) =>
    _matchesLeadingTag(_headerPattern, line);

final RegExp _headerPattern = RegExp(r'^\s*<h[1-6]', caseSensitive: false);

/// שורה מיושרת במפורש (`text-align` / `<center>`); עוגנים ריקים ו-`<br>`
/// בתחילתה אינם משנים זאת. אינה שוברת פריסה — תלויה בתוכן שנטען.
bool isAlignedBlockLine(String line) =>
    _matchesLeadingTag(_alignedBlockPattern, line);

final RegExp _alignedBlockPattern = RegExp(
  r'^\s*(?:(?:<a\b[^>]*>\s*</a>|<br\s*/?>)\s*)*'
  r'<(?:center\b|div\b[^>]*\btext-align\s*:)',
  caseSensitive: false,
);

/// רצף שורות ללא שבירה נחתך לפריטים באורך זה לכל היותר — לספר בלי TOC
/// ולפסקאות חריגות. החיתוך לפי אינדקס בלבד, ולכן יציב.
const int kMaxReadingParagraphLines = 200;

/// פריסה בלתי-משתנה: במצב רגיל פריט לכל שורה; במצב רציף כל שורת שבירה
/// היא פריט לבדה, וכל רצף שורות אחרות הוא פסקה (חתוכה ל-[kMaxReadingParagraphLines]).
@immutable
class ReadingLayout {
  /// מצב רגיל — פריט לכל שורה.
  const ReadingLayout.identity(this.lineCount)
    : continuous = false,
      _starts = null;

  const ReadingLayout._continuous(this.lineCount, this._starts)
    : continuous = true;

  /// [breakLines] מחוץ לטווח השורות מתעלמים מהן. [splitAfterLines] — שורות
  /// שאחריהן הפסקה נחתכת, בלי שהשורה עצמה נעשית פריט לבדה (פרשה פתוחה).
  factory ReadingLayout.continuous({
    required int lineCount,
    required Iterable<int> breakLines,
    Iterable<int> splitAfterLines = const [],
  }) {
    // נקודות חיתוך: שורת שבירה היא פריט לבדה (חיתוך לפניה ואחריה).
    final cuts = <int>{0};
    for (final line in breakLines) {
      if (line < 0 || line >= lineCount) continue;
      cuts.add(line);
      if (line + 1 < lineCount) cuts.add(line + 1);
    }
    for (final line in splitAfterLines) {
      if (line >= 0 && line + 1 < lineCount) cuts.add(line + 1);
    }
    final ordered = cuts.toList()..sort();
    final starts = <int>[];
    for (var i = 0; i < ordered.length; i++) {
      final to = i + 1 < ordered.length ? ordered[i + 1] : lineCount;
      for (
        var start = ordered[i];
        start < to;
        start += kMaxReadingParagraphLines
      ) {
        starts.add(start);
      }
    }
    return ReadingLayout._continuous(lineCount, Int32List.fromList(starts));
  }

  final int lineCount;
  final bool continuous;
  final Int32List? _starts;

  int get itemCount => _starts?.length ?? lineCount;

  bool get isEmpty => itemCount == 0;

  bool get isNotEmpty => itemCount > 0;

  /// הפריט שמכיל את [line]; שורה מחוץ לטווח נצמדת לפריט הקרוב.
  int itemForLine(int line) {
    final starts = _starts;
    if (starts == null) {
      if (lineCount == 0) return 0;
      return line.clamp(0, lineCount - 1);
    }
    if (starts.isEmpty || line <= 0) return 0;
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (starts[mid] <= line) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  int firstLineOf(int item) {
    final starts = _starts;
    if (starts == null) return item;
    return starts[item];
  }

  int lastLineOf(int item) {
    final starts = _starts;
    if (starts == null) return item;
    return item + 1 < starts.length ? starts[item + 1] - 1 : lineCount - 1;
  }

  int lineCountOf(int item) => lastLineOf(item) - firstLineOf(item) + 1;

  bool hasSameStructure(ReadingLayout other) {
    if (identical(this, other)) return true;
    if (lineCount != other.lineCount || continuous != other.continuous) {
      return false;
    }
    final starts = _starts;
    final otherStarts = other._starts;
    if (starts == null || otherStarts == null) {
      return starts == otherStarts;
    }
    return listEquals(starts, otherStarts);
  }
}

/// שורות השבירה של ספר במצב רציף: שורות ה-TOC בלבד.
List<int> readingBreakLines(List<TocEntry> tableOfContents) => [
  for (final entry in flattenToc(tableOfContents)) entry.index,
];

/// הפריסה הרציפה של ספר באורך [lineCount] עם [tableOfContents].
ReadingLayout continuousReadingLayout({
  required int lineCount,
  required List<TocEntry> tableOfContents,
}) => ReadingLayout.continuous(
  lineCount: lineCount,
  breakLines: readingBreakLines(tableOfContents),
);

class _LayoutMemo {
  _LayoutMemo(
    TextBookLoaded state,
    this.breakLines,
    this.layout, {
    this.splitAfterLines,
  }) : bookTitle = state.book.title,
       lineCount = state.content.length,
       tableOfContents = state.tableOfContents,
       mikra = isMikraDisplay(state);

  /// הפריסה נבנתה בתצוגת מקרא; החלפת התצוגה מחייבת פריסה חדשה.
  final bool mikra;

  final String bookTitle;
  final int lineCount;
  final List<TocEntry> tableOfContents;

  /// null במצב רגיל, שבו ה-TOC אינו משפיע.
  final List<int>? breakLines;

  /// שורות החיתוך שאחריהן (פתוחה במקרא); null כשאין.
  final List<int>? splitAfterLines;
  final ReadingLayout layout;
}

/// [TextBookLoaded.readerIdentity] קבוע לאורך כל ה-states של הקורא — מפתח לזיכרון.
/// משבצת לכל מצב, כדי ש-state ישן שנקרא אחרי החלפת מצב לא ידרוס את הפריסה.
final Expando<List<_LayoutMemo?>> _layoutMemos = Expando<List<_LayoutMemo?>>(
  'readingLayout',
);

/// הפריסה של [state]. מופע חדש רק כשהספר, אורכו, שורות ה-TOC או מצב הרצף
/// משתנים; TOC שונה כמופע אך זהה בתוכנו מחזיר את אותו מופע.
ReadingLayout readingLayoutOf(TextBookLoaded state) {
  final slots = _layoutMemos[state.readerIdentity] ??= [null, null];
  final continuous = state.continuousReadingMode;
  final slot = continuous ? 1 : 0;
  final memo = slots[slot];
  final sameBook =
      memo != null &&
      memo.bookTitle == state.book.title &&
      memo.lineCount == state.content.length &&
      memo.mikra == isMikraDisplay(state);
  if (sameBook &&
      (!continuous || identical(memo.tableOfContents, state.tableOfContents))) {
    return memo.layout;
  }

  // ספר מקרא: רק שם הספר שובר את הרצף, והפתוחה חותכת פסקה; הפרקים בגליון.
  final mikra = continuous ? mikraStructureOf(state) : null;
  final breakLines = continuous
      ? (mikra?.bookTitleLines ?? readingBreakLines(state.tableOfContents))
      : null;
  final splitAfter = mikra?.paragraphEndLines;
  if (sameBook &&
      listEquals(memo.breakLines, breakLines) &&
      listEquals(memo.splitAfterLines, splitAfter)) {
    slots[slot] = _LayoutMemo(
      state,
      breakLines,
      memo.layout,
      splitAfterLines: splitAfter,
    );
    return memo.layout;
  }

  final built = breakLines != null
      ? ReadingLayout.continuous(
          lineCount: state.content.length,
          breakLines: breakLines,
          splitAfterLines: splitAfter ?? const [],
        )
      : ReadingLayout.identity(state.content.length);
  final layout = memo != null && memo.layout.hasSameStructure(built)
      ? memo.layout
      : built;
  slots[slot] = _LayoutMemo(
    state,
    breakLines,
    layout,
    splitAfterLines: splitAfter,
  );
  return layout;
}

class _MikraParse {
  const _MikraParse(this.structure);
  final MikraStructure? structure;
}

final Expando<_MikraParse> _mikraByContent = Expando<_MikraParse>(
  'mikraStructure',
);

/// האם [state] מוצג כמקרא כמסורה: ספר תנ"ך (לפי זיהוי האפליקציה), במצב רצף,
/// והתצוגה כמסורה מופעלת.
bool isMikraDisplay(TextBookLoaded state) =>
    state.isTanach &&
    state.continuousReadingMode &&
    state.mikraTraditionalLayout;

/// מבנה המקרא של [state], או null כשאינו מוצג כמקרא. נשמר לפי זהות התוכן,
/// כמו פריסת הקריאה. ספר שמבנהו אינו כותרת/פרק/פסוק נשאר כמות שהוא.
MikraStructure? mikraStructureOf(TextBookLoaded state) =>
    isMikraDisplay(state) ? mikraTextStructureOf(state) : null;

/// מבנה ספר התנ"ך בלי קשר לתצוגה (לציון מקור בהעתקה גם כנדפס ובשורות
/// בודדות); null בספר שאינו תנ"ך או שמבנהו אינו כותרת/פרק/פסוק.
MikraStructure? mikraTextStructureOf(TextBookLoaded state) {
  if (!state.isTanach) return null;
  final content = state.content;
  final cached = _mikraByContent[content];
  if (cached != null) return cached.structure;
  final parsed = _MikraParse(
    MikraStructure.parse(content, bookTitle: state.book.title),
  );
  _mikraByContent[content] = parsed;
  return parsed.structure;
}
