/// החוזים שבין שכבת התצוגה של "תיקון קוראים" לבין מנוע העימוד וטבלאות הנתונים.
///
/// המימושים חיים תחת `engine/` ו-`data/`; המסך וה-BLoC מדברים רק דרך כאן.
library;

import 'package:equatable/equatable.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// מדור התנ"ך שנבחר בסרגל.
enum TikkunSection {
  torah('torah', 'תורה'),
  neviim('neviim', 'נביאים'),
  ketuvim('ketuvim', 'כתובים'),
  haftarot('haftarot', 'הפטרות'),
  torahReadings('torah_readings', 'קריאות למועדים');

  const TikkunSection(this.id, this.label);

  final String id;
  final String label;

  bool get isTanachBook =>
      this == TikkunSection.neviim || this == TikkunSection.ketuvim;

  static TikkunSection fromId(String id) => TikkunSection.values.firstWhere(
    (s) => s.id == id,
    orElse: () => TikkunSection.torah,
  );
}

/// ספר תנ"ך אחד אחרי עיבוד: אסימונים, שורות מעומדות ומיפוי פרק → שורה.
class ProcessedBook {
  final List<TikkunToken> tokens;
  final List<TikkunLine> allLines;
  final Map<int, int> chapterToLineIdx;

  const ProcessedBook({
    required this.tokens,
    required this.allLines,
    this.chapterToLineIdx = const {},
  });
}

/// מנוע העימוד. כל הפונקציות טהורות — בלי IO ובלי מצב — כדי שאפשר יהיה
/// להריץ אותן ב-`Isolate.run`; לכן גם המימוש חייב להיות חסר שדות.
abstract class TikkunEngine {
  String cleanRawText(String raw);

  List<TikkunToken> tokenizeText(String cleaned);

  List<TikkunToken> markSpecialSections(
    List<TikkunToken> tokens,
    String bookName,
  );

  /// [widths] הוא מודל רוחב גופן הסת"ם — הפריסה נגזרת ממנו, ולכן כל מטמון
  /// שורות חייב לכלול את `widths.id` במפתח שלו.
  List<TikkunLine> paginateAllTokens(
    List<TikkunToken> tokens,
    StamWidthModel widths,
  );

  /// עיבוד מלא של חמשת החומשים. המפתחות: bereshit/shemot/vayikra/bamidbar/devarim.
  /// [tradition] קובעת את הפרשיות תלויות-הנוסח, ו-[methodId] את עוגני העמודים.
  ProcessedTorah processTorah(
    Map<String, String> rawByBookId,
    StamWidthModel widths, {
    TikkunTradition tradition,
    TikkunDecalogueTaam decalogueTaam,
    String methodId,
  });

  /// חלוקת התורה המעובדת לעמודים לפי שיטה
  /// ('ramah' | 'ramach' | 'rambamRosh' | 'single_page').
  List<TikkunPage> buildPages(ProcessedTorah processed, String methodId);

  /// עיבוד ספר בודד (נביאים/כתובים/חומש לצורך הפטרה או קריאת מועד).
  ProcessedBook processBook(
    String rawText,
    String bookName,
    StamWidthModel widths, {
    TikkunTradition tradition,
    TikkunDecalogueTaam decalogueTaam,
  });

  List<TikkunToken> sliceTokensByVerseRange(
    List<TikkunToken> tokens,
    int fromCh,
    int fromVs,
    int toCh,
    int toVs,
  );

  bool precededBySetuma(List<TikkunToken> tokens, int fromCh, int fromVs);

  int findWordSequence(
    List<TikkunToken> tokens,
    List<String> words,
    int fromIdx,
  );

  int findParashaStart(
    List<TikkunToken> tokens,
    String normalizedParashaName,
    int fromIdx,
  );

  /// י-ה-ו-ה → י-ק-ו-ק תוך שמירת הניקוד והטעמים.
  String maskDivineName(String text);

  /// מיזוג עליות עוקבות/חופפות לטווחים רציפים — לכותרת הקריאה.
  List<VerseRange> computeContinuousSegments(List<ReadingAliya> aliyot);
}

/// טבלאות הנתונים הסטטיות (נוצרות מקבצי ה-JS של התוסף).
abstract class TikkunDataSource {
  /// חמשת החומשים לפי סדרם, עם רשימת הפרשות.
  List<TanachBook> get chumashim;

  /// ספרי נביאים/כתובים לפי מדור.
  List<TanachBook> booksOfSection(TikkunSection section);

  List<TorahLayoutMethod> get methods;

  List<Haftarah> get haftarot;

  List<TorahReading> get torahReadings;

  /// מזהה קטגוריית קריאה → שמה בעברית.
  Map<String, String> get readingCategoryNames;

  /// העליות של פרשה, לפי שם הספר העברי ושם הפרשה כפי שמופיע בסרגל.
  List<ParashaAliya> aliyotOf(String bookName, String parashaName);

  /// שם הפרשה כפי שהוא מופיע בטבלאות (למשל "בחוקותי" → "בחקתי").
  String normalizeParashaName(String uiName);

  /// שם עליה לתצוגה ("עליה א" → "ראשון").
  String aliyaDisplayName(String aliyaKey);

  /// הפרשה המחוברת שאליה שייכת פרשה בודדת, אם יש.
  String? combinedParashaOf(String parashaName);

  /// חומש ופרשה לפי שם שהגיע מהלוח (עם ניקוד / פרשה כפולה), או `null`.
  ({String bookId, String parashaName})? resolveParasha(String calendarName);
}

/// מיקום הניווט האחרון — נשמר בין הפעלות.
class TikkunNavState extends Equatable {
  final TikkunSection section;
  final String bookId;
  final String parashaName;
  final String methodId;
  final String? tanachBookId;
  final int tanachChapter;
  final int currentColumnIndex;
  final String? haftarahId;
  final String? torahReadingId;

  /// המיקום המדויק בתוך התצוגה — ראו `TikkunPosition`.
  final int? verseKey;
  final int lineOffset;

  const TikkunNavState({
    this.section = TikkunSection.torah,
    this.bookId = 'bereshit',
    this.parashaName = 'בראשית',
    this.methodId = 'ramah',
    this.tanachBookId,
    this.tanachChapter = 1,
    this.currentColumnIndex = 0,
    this.haftarahId,
    this.torahReadingId,
    this.verseKey,
    this.lineOffset = 0,
  });

  /// אותו ניווט עם מיקום מדויק אחר (`null` מוחק אותו).
  TikkunNavState withPosition(({int verseKey, int lineOffset})? position) =>
      TikkunNavState(
        section: section,
        bookId: bookId,
        parashaName: parashaName,
        methodId: methodId,
        tanachBookId: tanachBookId,
        tanachChapter: tanachChapter,
        currentColumnIndex: currentColumnIndex,
        haftarahId: haftarahId,
        torahReadingId: torahReadingId,
        verseKey: position?.verseKey,
        lineOffset: position?.lineOffset ?? 0,
      );

  ({int verseKey, int lineOffset})? get position =>
      verseKey == null ? null : (verseKey: verseKey!, lineOffset: lineOffset);

  TikkunNavState copyWith({
    TikkunSection? section,
    String? bookId,
    String? parashaName,
    String? methodId,
    String? tanachBookId,
    int? tanachChapter,
    int? currentColumnIndex,
    String? haftarahId,
    String? torahReadingId,
  }) => TikkunNavState(
    section: section ?? this.section,
    bookId: bookId ?? this.bookId,
    parashaName: parashaName ?? this.parashaName,
    methodId: methodId ?? this.methodId,
    tanachBookId: tanachBookId ?? this.tanachBookId,
    tanachChapter: tanachChapter ?? this.tanachChapter,
    currentColumnIndex: currentColumnIndex ?? this.currentColumnIndex,
    haftarahId: haftarahId ?? this.haftarahId,
    torahReadingId: torahReadingId ?? this.torahReadingId,
  );

  Map<String, dynamic> toJson() => {
    'section': section.id,
    'bookId': bookId,
    'parashaName': parashaName,
    'methodId': methodId,
    'tanachBookId': tanachBookId,
    'tanachChapter': tanachChapter,
    'currentColumnIndex': currentColumnIndex,
    'haftarahId': haftarahId,
    'torahReadingId': torahReadingId,
    'verseKey': verseKey,
    'lineOffset': lineOffset,
  };

  static TikkunNavState fromJson(Map<String, dynamic> json) {
    const fallback = TikkunNavState();
    return TikkunNavState(
      section: TikkunSection.fromId(json['section'] as String? ?? 'torah'),
      bookId: json['bookId'] as String? ?? fallback.bookId,
      parashaName: json['parashaName'] as String? ?? fallback.parashaName,
      methodId: json['methodId'] as String? ?? fallback.methodId,
      tanachBookId: json['tanachBookId'] as String?,
      tanachChapter: (json['tanachChapter'] as num?)?.toInt() ?? 1,
      currentColumnIndex: (json['currentColumnIndex'] as num?)?.toInt() ?? 0,
      haftarahId: json['haftarahId'] as String?,
      torahReadingId: json['torahReadingId'] as String?,
      verseKey: (json['verseKey'] as num?)?.toInt(),
      lineOffset: (json['lineOffset'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
    section,
    bookId,
    parashaName,
    methodId,
    tanachBookId,
    tanachChapter,
    currentColumnIndex,
    haftarahId,
    torahReadingId,
    verseKey,
    lineOffset,
  ];
}

/// סימניה שהמשתמש שמר — מצב ניווט מלא עם המיקום המדויק.
class TikkunBookmark extends Equatable {
  final String id;
  final String title;
  final TikkunNavState nav;

  const TikkunBookmark({
    required this.id,
    required this.title,
    required this.nav,
  });

  /// אותו מקום — בלי תלות בשיטת החלוקה ובעמוד שבו נשמר.
  bool samePlaceAs(TikkunNavState other) =>
      nav.section == other.section &&
      nav.verseKey == other.verseKey &&
      nav.lineOffset == other.lineOffset &&
      switch (nav.section) {
        TikkunSection.torah => true,
        TikkunSection.neviim ||
        TikkunSection.ketuvim => nav.tanachBookId == other.tanachBookId,
        TikkunSection.haftarot => nav.haftarahId == other.haftarahId,
        TikkunSection.torahReadings =>
          nav.torahReadingId == other.torahReadingId,
      };

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'nav': nav.toJson(),
  };

  static TikkunBookmark? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final nav = json['nav'];
    if (id is! String || title is! String || nav is! Map) return null;
    return TikkunBookmark(
      id: id,
      title: title,
      nav: TikkunNavState.fromJson(Map<String, dynamic>.from(nav)),
    );
  }

  @override
  List<Object?> get props => [id, title, nav];
}
