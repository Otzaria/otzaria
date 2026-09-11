/// מודלי הנתונים של כלי "תיקון קוראים" — חוזה משותף בין מנוע העימוד,
/// ה-BLoC והתצוגה.
library;

import 'package:equatable/equatable.dart';

/// סימוני מקום במילה: רווח סתומה באמצע שורה ורווח פתיחה (שני-שלישים).
const String kGapWord = '{GAP}';
const String kBigGapWord = '{BIGGAP}';

/// תווי PUA שמסמנים זעירא/רבתי בתוך מילת סת"ם. הטוקנייזר משאיר אותם
/// בטקסט והמרנדר מפרש אותם; הם אינם נספרים באורך הגלוי של המילה.
const int kZeiraStart = 0xE020;
const int kZeiraEnd = 0xE021;
const int kRabatiStart = 0xE022;
const int kRabatiEnd = 0xE023;

/// מקדמי הגודל של אות זעירא ואות רבתי — גם המרנדר וגם מודל הרוחב נגזרים מהם.
const double kTikkunZeiraFactor = 0.78;
const double kTikkunRabatiFactor = 1.25;

/// תווי PUA של כתיב/קרי: התחלה, מפריד, סוף.
const int kKetivQereStart = 0xE010;
const int kKetivQereSep = 0xE011;
const int kKetivQereEnd = 0xE012;

/// מסורת ספרי התורה. מקצת הפרשיות שבנוסח הכתר קיימות רק באחת מהן, ולכן
/// היא נבחרת לפני העימוד — לא בשלב חלוקת העמודים.
enum TikkunTradition {
  ashkenazSephard('ashkenaz_sephard'),
  yemen('yemen');

  const TikkunTradition(this.id);

  final String id;

  /// השיטה התימנית נוהגת כרמב"ם; רמ"ה ורמ"ח כספרי אשכנז וספרד.
  static TikkunTradition forMethod(String methodId) =>
      methodId == 'rambamRosh' ? yemen : ashkenazSephard;

  static TikkunTradition? byId(String id) {
    for (final t in TikkunTradition.values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// מערכת הטעמים שבה מוצגות עשרת הדברות. במסד שתי המערכות ממוזגות על אותן
/// אותיות, ו-[merged] הוא הטקסט כפי שהוא שם.
enum TikkunDecalogueTaam {
  merged('merged'),
  elyon('elyon'),
  tachton('tachton');

  const TikkunDecalogueTaam(this.id);

  final String id;

  static TikkunDecalogueTaam byId(String? id) {
    for (final t in TikkunDecalogueTaam.values) {
      if (t.id == id) return t;
    }
    return TikkunDecalogueTaam.merged;
  }
}

/// מילה אחת מעשרת הדברות בשלוש צורות הטעמים. העיצורים זהים בשלושתן —
/// רק הטעמים משתנים. [vFrom]/[vTo] הם הפסוק במספור המסד.
class DecalogueWord extends Equatable {
  final int vFrom;
  final int vTo;
  final String merged;
  final String elyon;
  final String tachton;

  const DecalogueWord({
    required this.vFrom,
    required this.vTo,
    required this.merged,
    required this.elyon,
    required this.tachton,
  });

  String formFor(TikkunDecalogueTaam taam) => switch (taam) {
    TikkunDecalogueTaam.merged => merged,
    TikkunDecalogueTaam.elyon => elyon,
    TikkunDecalogueTaam.tachton => tachton,
  };

  @override
  List<Object?> get props => [vFrom, vTo, merged, elyon, tachton];
}

/// מקום שבו נוהגות שתי מערכות הטעמים: הפרק וטווח הפסוקים במספור המסד,
/// ומילות הדברות לפי סדרן.
class DecaloguePlace {
  final String bookName;
  final int chapter;
  final int fromVerse;
  final int toVerse;
  final List<DecalogueWord> words;

  const DecaloguePlace({
    required this.bookName,
    required this.chapter,
    required this.fromVerse,
    required this.toVerse,
    required this.words,
  });
}

enum TikkunTokenType {
  word,
  petucha,
  setuma,
  bookBreak,
  segmentBreak,
  chapterBreak,
  verseBreak,
  specialStart,
  specialEnd,
  leadingSetuma,
  aliyaBreak,
}

/// אסימון בודד ברצף הטקסט (מילה או סימן מבני).
class TikkunToken {
  final TikkunTokenType type;

  /// טקסט המילה (מנוקד, כולל טעמים) — רק ל-[TikkunTokenType.word].
  final String? value;
  final int? chapterNum;
  final int? verseNum;

  /// הקטע המיוחד שנפתח — רק ל-[TikkunTokenType.specialStart].
  final SpecialSection? section;
  final int? openingChapter;
  final int? openingVerse;

  /// מעבר פסוק שאינו סוגר סגמנט בפריסת `segment_pairs` (ראה suppressBreaks).
  final bool suppressFlush;

  /// המסורת שבספריה אין כאן פרשה — רק לסמני פתוחה/סתומה שהמסד תלה בהם
  /// הערת שוליים ("אין פרשה בספרי תימן").
  final TikkunTradition? excludedTradition;

  const TikkunToken({
    required this.type,
    this.value,
    this.chapterNum,
    this.verseNum,
    this.section,
    this.openingChapter,
    this.openingVerse,
    this.suppressFlush = false,
    this.excludedTradition,
  });

  const TikkunToken.word(String this.value)
    : type = TikkunTokenType.word,
      chapterNum = null,
      verseNum = null,
      section = null,
      openingChapter = null,
      openingVerse = null,
      suppressFlush = false,
      excludedTradition = null;

  bool get isWord => type == TikkunTokenType.word;
}

/// מילה בשורה מעומדת: [stam] בלי ניקוד וטעמים לטור הסת"ם, [nikud] המלא
/// לטור המנוקד. במקרה כתיב/קרי — הכתיב בסת"ם והקרי במנוקד.
class LayoutWord extends Equatable {
  final String stam;
  final String nikud;

  /// מספר הפסוק שאליו המילה שייכת — ידוע רק בקטעים מיוחדים.
  final int? verseNum;

  /// אינדקס האסימון הגלובלי — ידוע רק בקטעים מיוחדים.
  final int? tokenIdx;

  const LayoutWord({
    required this.stam,
    required this.nikud,
    this.verseNum,
    this.tokenIdx,
  });

  bool get isGap => stam == kGapWord;
  bool get isBigGap => stam == kBigGapWord;

  LayoutWord copyWith({String? stam, String? nikud}) => LayoutWord(
    stam: stam ?? this.stam,
    nikud: nikud ?? this.nikud,
    verseNum: verseNum,
    tokenIdx: tokenIdx,
  );

  @override
  List<Object?> get props => [stam, nikud, verseNum, tokenIdx];
}

/// פריסת שורה רגילה או מיוחדת.
enum LineLayout {
  regular,
  partial,
  petucha,
  setuma,
  setumaStart,
  empty,
  shiraParallel,
  shiraZigzag,
  listPairs,
  listAlternating,
  listQuad;

  bool get isSpecial => index >= LineLayout.shiraParallel.index;
}

/// תת-סוג של שורת זיגזג.
enum ZigzagRow { double, single, triple, manual }

/// תא בשורה ידנית (שירת הים): רוחב באחוזים ורשימת מילים.
class ManualCell extends Equatable {
  final int width;
  final List<LayoutWord> words;

  const ManualCell({required this.width, required this.words});

  @override
  List<Object?> get props => [width, words];
}

/// שורה מעומדת אחת בתיקון.
///
/// שורה רגילה משתמשת ב-[words]. שורה מיוחדת משתמשת ב-[rightWords] /
/// [leftWords] / [centerWords] (פריסת בלוקים), ב-[manualCells] (זיגזג ידני)
/// או ב-[cells] (רשימה ריבועית — ארבעה תאים: שניים מימין, שניים משמאל).
class TikkunLine {
  List<LayoutWord> words;
  LineLayout layout;

  /// אינדקס האסימון הראשון שתרם לשורה; ‎-1 לשורה ריקה.
  int startTokenIdx;
  int? firstVerseNum;
  int? firstChapterNum;

  /// תווית תחילת עליה ("ראשון", "מפטיר") ואינדקסה ברשימת העליות של הפרשה.
  String? aliyaName;
  int? aliyaIdx;

  /// עליה בקריאה המחוברת (ויקהל-פקודי וכו') — מוצגת בשורה נוספת בטור הסמנים.
  String? combinedAliyaName;

  /// המפטיר בשדה נפרד: בעקב ובנצבים הוא מתחיל באותו פסוק כמו עליה ז'.
  String? maftirName;
  int? maftirIdx;

  /// הפסקת כהן/לוי/ישראל של קריאת שני וחמישי, בתוך העליה הראשונה.
  String? weekdayAliyaName;

  /// חלופת החלוקה המקובלת לעליה שמתחילה כאן, כטקסט מוכן להצגה.
  String? aliyaAlternative;

  /// "ספר תורה שני" / "שלישי" — כותרת מפרידה בקריאות שנקראות מכמה ספרים.
  String? torahScrollLabel;

  /// שם הפרשה שמתחילה בשורה זו.
  String? parashaName;

  // --- קטעים מיוחדים ---
  ZigzagRow? zigzagRow;
  List<LayoutWord>? rightWords;
  List<LayoutWord>? leftWords;
  List<LayoutWord>? centerWords;
  List<ManualCell>? manualCells;
  List<List<LayoutWord>>? cells;

  /// מחלקות עיצוב של הקטע (מקביל ל-`cssClass`): "compact", "compact-lg",
  /// "justify-cells" — מופרדות ברווח.
  String? cssClass;

  TikkunLine({
    List<LayoutWord>? words,
    this.layout = LineLayout.regular,
    this.startTokenIdx = -1,
    this.firstVerseNum,
    this.firstChapterNum,
    this.aliyaName,
    this.aliyaIdx,
    this.combinedAliyaName,
    this.maftirName,
    this.maftirIdx,
    this.weekdayAliyaName,
    this.aliyaAlternative,
    this.torahScrollLabel,
    this.parashaName,
    this.zigzagRow,
    this.rightWords,
    this.leftWords,
    this.centerWords,
    this.manualCells,
    this.cells,
    this.cssClass,
  }) : words = words ?? [];

  bool get isSpecial => layout.isSpecial;
  bool get isEmpty => layout == LineLayout.empty;

  Set<String> get cssClasses =>
      cssClass == null ? const {} : cssClass!.split(RegExp(r'\s+')).toSet();
}

/// הגדרת עמוד בטבלת השיטה (רמ"ה / רמ"ח / תימני).
class PageDefinition extends Equatable {
  final int num;
  final int sheet;
  final String book;
  final String parasha;

  /// המילה הראשונה בעמוד בלי ניקוד; `null` כשהגבול נקבע באינטרפולציה.
  final String? firstWord;
  final String? lastWord;
  final String? isSpecial;

  const PageDefinition({
    required this.num,
    required this.sheet,
    required this.book,
    required this.parasha,
    this.firstWord,
    this.lastWord,
    this.isSpecial,
  });

  @override
  List<Object?> get props => [num, sheet, book, parasha, firstWord, lastWord];
}

/// שיטת חלוקת ספר התורה לעמודים.
class TorahLayoutMethod {
  final String id;
  final String name;
  final String fullName;
  final int totalPages;
  final int linesPerPage;
  final List<PageDefinition> pages;

  const TorahLayoutMethod({
    required this.id,
    required this.name,
    required this.fullName,
    required this.totalPages,
    required this.linesPerPage,
    required this.pages,
  });
}

/// עמוד (טור) מעומד: טווח שורות ב-`allLines`.
class TikkunPage {
  final int startLineIdx;
  final int endLineIdx;
  final List<TikkunLine> lines;

  const TikkunPage({
    required this.startLineIdx,
    required this.endLineIdx,
    required this.lines,
  });
}

/// קטע שירה/רשימה עם פריסה מיוחדת (שירת הים, האזינו, עשרת בני המן...).
class SpecialSection {
  final String id;
  final String name;
  final String book;
  final int fromCh;
  final int fromVs;
  final int toCh;
  final int toVs;

  /// 'shira_parallel' | 'shira_zigzag' | 'manual_zigzag' | 'segment_pairs' |
  /// 'list_pairs' | 'list_alternating' | 'list_quad'
  final String layout;
  final String? cssClass;
  final bool justifyLineBefore;

  /// שיטה שלמה פנויה לפני הקטע ואחריו (קסת הסופר טז, א-ב).
  final bool blankLineBefore;
  final bool blankLineAfter;

  /// חלוקה ידנית לשורות ותאים (manual_zigzag).
  final List<List<ManualRowSpec>> manualRows;

  /// רצפי מילים (בלי ניקוד) שאחריהם מוזרק/מבוטל מעבר סגמנט.
  final List<List<String>> extraBreaks;
  final List<List<String>> suppressBreaks;

  /// טרים גבולות הקטע: כמה מילים לשמור מסוף הפסוק הראשון / מתחילת האחרון.
  final int? trimStartKeepLast;
  final int? trimEndKeepFirst;

  final String? pairSeparator;
  final String pairOrder;
  final Map<String, Object?> raw;

  const SpecialSection({
    required this.id,
    required this.name,
    required this.book,
    required this.fromCh,
    required this.fromVs,
    required this.toCh,
    required this.toVs,
    required this.layout,
    this.cssClass,
    this.justifyLineBefore = false,
    this.blankLineBefore = false,
    this.blankLineAfter = false,
    this.manualRows = const [],
    this.extraBreaks = const [],
    this.suppressBreaks = const [],
    this.trimStartKeepLast,
    this.trimEndKeepFirst,
    this.pairSeparator,
    this.pairOrder = 'words_then_sep',
    this.raw = const {},
  });

  bool get hasTrim => trimStartKeepLast != null || trimEndKeepFirst != null;
}

/// תא בטבלת החלוקה הידנית: רוחב באחוזים ומספר המילים שהוא צורך.
class ManualRowSpec extends Equatable {
  final int width;
  final int count;

  const ManualRowSpec({required this.width, required this.count});

  @override
  List<Object?> get props => [width, count];
}

/// טווח פסוקים בספר (הפטרה / קריאת מועד).
class VerseRange extends Equatable {
  final String book;
  final int fromCh;
  final int fromVs;
  final int toCh;
  final int toVs;

  const VerseRange({
    required this.book,
    required this.fromCh,
    required this.fromVs,
    required this.toCh,
    required this.toVs,
  });

  /// מפרש "12:21" → (12, 21).
  static (int, int) parseRef(String ref) {
    final parts = ref.split(':');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }

  @override
  List<Object?> get props => [book, fromCh, fromVs, toCh, toVs];
}

/// שם ספר התורה לפי מספרו ([n] = 2 לספר השני). הלכה למעשה אין יותר
/// משלושה ספרים; מספר גבוה יותר נצמד לשם האחרון כדי לא לפלוט ספרה.
String torahScrollLabel(int n) {
  const names = ['שני', 'שלישי', 'רביעי'];
  return 'ספר תורה ${names[(n - 2).clamp(0, names.length - 1)]}';
}

/// שם המפטיר כפי שהוא בנתונים — חייב להישאר זהה ל-`kAliyaDisplayNames`.
const String kMaftirAliyaName = 'מפטיר';

/// עליה בקריאת מועד (מתוך TORAH_READINGS_LIST).
class ReadingAliya extends Equatable {
  final String aliya;
  final String aliyaLabel;
  final VerseRange range;

  /// ספר התורה שממנו נקראת העליה (1 = הראשון). נקבע בנתונים, ולא נגזר
  /// מהחלפת חומש — שבת ר"ח וחנוכה קוראים משני ספרים באותו חומש.
  final int scroll;

  const ReadingAliya({
    required this.aliya,
    required this.aliyaLabel,
    required this.range,
    this.scroll = 1,
  });

  @override
  List<Object?> get props => [aliya, aliyaLabel, range, scroll];
}

/// קריאה בתורה למועד / ר"ח / שבת מיוחדת.
class TorahReading {
  final String id;
  final String category;
  final String name;

  /// 'israel' | 'diaspora' | 'both'
  final String land;

  /// 'ashkenaz' | 'sephard'; null = הקריאה משותפת לכל הנוסחים.
  final String? nusach;
  final List<ReadingAliya> aliyot;

  const TorahReading({
    required this.id,
    required this.category,
    required this.name,
    required this.land,
    this.nusach,
    required this.aliyot,
  });
}

/// הפטרה — לפי נוסח אשכנז / ספרד, עם מקטעים אפשריים מספרים שונים.
class Haftarah {
  final String id;

  /// 'parasha' | 'special' | 'holiday' (כפי שבמקור)
  final String category;
  final String name;
  final List<VerseRange> ashkenaz;

  /// ריק כשמנהג עדות המזרח זהה לאשכנז — ואז [forNusach] נופל לאשכנז.
  final List<VerseRange> sephard;

  /// אין הפטרה כלל לנוסח ספרדי (מנחת תענית ציבור).
  final bool sephardNone;

  /// 'israel' | 'diaspora' | 'both'
  final String land;

  const Haftarah({
    required this.id,
    required this.category,
    required this.name,
    required this.ashkenaz,
    required this.sephard,
    this.sephardNone = false,
    this.land = 'both',
  });

  /// האם נוהגים להפטיר בנוסח זה.
  bool hasNusach(String nusach) => !(nusach == 'sephard' && sephardNone);

  List<VerseRange> forNusach(String nusach) {
    if (!hasNusach(nusach)) return const [];
    return nusach == 'sephard' && sephard.isNotEmpty ? sephard : ashkenaz;
  }
}

/// עליה בפרשת השבוע: שם ("עליה א".."עליה ז", "מפטיר") וטווח הפסוקים שלה
/// בחומש. [altFrom]/[altTo] — חלופת חלוקה מקובלת, כשקיימת.
class ParashaAliya extends Equatable {
  final String aliya;
  final int fromCh;
  final int fromVs;
  final int toCh;
  final int toVs;
  final (int, int)? altFrom;
  final (int, int)? altTo;

  const ParashaAliya({
    required this.aliya,
    required this.fromCh,
    required this.fromVs,
    required this.toCh,
    required this.toVs,
    this.altFrom,
    this.altTo,
  });

  bool get hasAlternative => altFrom != null && altTo != null;

  @override
  List<Object?> get props => [
    aliya,
    fromCh,
    fromVs,
    toCh,
    toVs,
    altFrom,
    altTo,
  ];
}

/// ספר בתנ"ך: מזהה לועזי, שם עברי (שם הספר בקטלוג אוצריא), מספר פרקים,
/// ולחומשים — רשימת הפרשות לפי הסדר.
class TanachBook {
  final String id;
  final String name;
  final int chapters;
  final List<String> parashot;

  const TanachBook({
    required this.id,
    required this.name,
    required this.chapters,
    this.parashot = const [],
  });
}

/// המצב המלא של התורה אחרי עיבוד — משותף לכל השיטות (רק גדרי העמוד משתנים).
class ProcessedTorah {
  final List<TikkunToken> tokens;
  final List<TikkunLine> allLines;
  final Map<String, int> bookStartTokenIdx;

  const ProcessedTorah({
    required this.tokens,
    required this.allLines,
    required this.bookStartTokenIdx,
  });
}
