/// כפילים למנוע, לטבלאות ולשמירת ההגדרות — לבדיקות ה-BLoC והתצוגה.
library;

import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_korim_repository.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

/// מודל רוחב קבוע לבדיקות — אינו דורש מדידה אמיתית של גופן.
const StamWidthModel fakeWidths = StamWidthModel.uniform(id: 'fake');

LayoutWord word(String text) => LayoutWord(stam: text, nikud: text);

TikkunLine textLine(
  List<String> words, {
  LineLayout layout = LineLayout.regular,
  int startTokenIdx = 0,
  int? chapter,
  int? verse,
  String? parashaName,
  String? aliyaName,
  int? aliyaIdx,
}) => TikkunLine(
  words: words.map(word).toList(),
  layout: layout,
  startTokenIdx: startTokenIdx,
  firstChapterNum: chapter,
  firstVerseNum: verse,
  parashaName: parashaName,
  aliyaName: aliyaName,
  aliyaIdx: aliyaIdx,
);

/// מנוע מזויף: מפצל לפי רווחים ומייצר שורה אחת לכל שלוש מילים.
class FakeTikkunEngine implements TikkunEngine {
  int processTorahCalls = 0;
  Object? throwOnProcessTorah;
  TikkunDecalogueTaam? lastDecalogueTaam;

  @override
  String cleanRawText(String raw) => raw.trim();

  @override
  List<TikkunToken> tokenizeText(String cleaned) => [
    for (final part in cleaned.split(RegExp(r'\s+')))
      if (part.isNotEmpty) TikkunToken.word(part),
  ];

  @override
  List<TikkunToken> markSpecialSections(
    List<TikkunToken> tokens,
    String bookName,
  ) => tokens;

  @override
  List<TikkunLine> paginateAllTokens(
    List<TikkunToken> tokens,
    StamWidthModel widths,
  ) {
    final lines = <TikkunLine>[];
    for (var i = 0; i < tokens.length; i += 3) {
      final chunk = tokens.skip(i).take(3).where((t) => t.isWord).toList();
      if (chunk.isEmpty) continue;
      lines.add(
        TikkunLine(
          words: chunk.map((t) => word(t.value!)).toList(),
          startTokenIdx: i,
          firstChapterNum: 1,
          firstVerseNum: (i ~/ 3) + 1,
        ),
      );
    }
    return lines;
  }

  @override
  ProcessedTorah processTorah(
    Map<String, String> rawByBookId,
    StamWidthModel widths, {
    TikkunTradition tradition = TikkunTradition.ashkenazSephard,
    TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
  }) {
    processTorahCalls++;
    lastDecalogueTaam = decalogueTaam;
    final error = throwOnProcessTorah;
    if (error != null) throw error;
    final tokens = <TikkunToken>[];
    final starts = <String, int>{};
    for (final entry in rawByBookId.entries) {
      starts[entry.key] = tokens.length;
      tokens.addAll(tokenizeText(entry.value));
    }
    final lines = paginateAllTokens(tokens, widths);
    if (lines.isNotEmpty) lines.first.parashaName = 'בראשית';
    if (lines.length > 1) lines[1].parashaName = 'נח';
    return ProcessedTorah(
      tokens: tokens,
      allLines: lines,
      bookStartTokenIdx: starts,
    );
  }

  @override
  List<TikkunPage> buildPages(ProcessedTorah processed, String methodId) {
    if (methodId == 'single_page') {
      return [
        TikkunPage(
          startLineIdx: 0,
          endLineIdx: processed.allLines.length,
          lines: processed.allLines,
        ),
      ];
    }
    final pages = <TikkunPage>[];
    for (var i = 0; i < processed.allLines.length; i++) {
      pages.add(
        TikkunPage(
          startLineIdx: i,
          endLineIdx: i + 1,
          lines: [processed.allLines[i]],
        ),
      );
    }
    return pages;
  }

  @override
  ProcessedBook processBook(
    String rawText,
    String bookName,
    StamWidthModel widths, {
    TikkunTradition tradition = TikkunTradition.ashkenazSephard,
    TikkunDecalogueTaam decalogueTaam = TikkunDecalogueTaam.merged,
  }) {
    lastDecalogueTaam = decalogueTaam;
    final tokens = tokenizeText(cleanRawText(rawText));
    final lines = paginateAllTokens(tokens, widths);
    return ProcessedBook(
      tokens: tokens,
      allLines: lines,
      chapterToLineIdx: {for (var i = 0; i < lines.length; i++) i + 1: i},
    );
  }

  @override
  List<TikkunToken> sliceTokensByVerseRange(
    List<TikkunToken> tokens,
    int fromCh,
    int fromVs,
    int toCh,
    int toVs,
  ) => tokens;

  @override
  bool precededBySetuma(List<TikkunToken> tokens, int fromCh, int fromVs) =>
      false;

  @override
  int findWordSequence(
    List<TikkunToken> tokens,
    List<String> words,
    int fromIdx,
  ) {
    if (words.isEmpty) return -1;
    for (var i = fromIdx; i < tokens.length; i++) {
      if (tokens[i].value == words.first) return i;
    }
    return -1;
  }

  @override
  int findParashaStart(
    List<TikkunToken> tokens,
    String normalizedParashaName,
    int fromIdx,
  ) => fromIdx;

  @override
  String maskDivineName(String text) => text;

  @override
  List<VerseRange> computeContinuousSegments(List<ReadingAliya> aliyot) =>
      aliyot.map((a) => a.range).toList();
}

class FakeTikkunDataSource implements TikkunDataSource {
  @override
  List<TanachBook> get chumashim => const [
    TanachBook(
      id: 'bereshit',
      name: 'בראשית',
      chapters: 50,
      parashot: ['בראשית', 'נח'],
    ),
    TanachBook(
      id: 'shemot',
      name: 'שמות',
      chapters: 40,
      parashot: ['שמות', 'וארא'],
    ),
  ];

  @override
  List<TanachBook> booksOfSection(TikkunSection section) =>
      section == TikkunSection.neviim
      ? const [TanachBook(id: 'shoftim', name: 'שופטים', chapters: 21)]
      : const [TanachBook(id: 'ester', name: 'אסתר', chapters: 10)];

  @override
  List<TorahLayoutMethod> get methods => const [
    TorahLayoutMethod(
      id: 'ramah',
      name: 'רמה',
      fullName: 'רמה',
      totalPages: 2,
      linesPerPage: 42,
      pages: [],
    ),
  ];

  @override
  List<Haftarah> get haftarot => const [
    Haftarah(
      id: 'h1',
      category: 'parasha',
      name: 'הפטרת בראשית',
      ashkenaz: [
        VerseRange(book: 'שופטים', fromCh: 4, fromVs: 4, toCh: 5, toVs: 31),
      ],
      sephard: [
        VerseRange(book: 'שופטים', fromCh: 5, fromVs: 1, toCh: 5, toVs: 31),
      ],
    ),
    Haftarah(
      id: 'h2',
      category: 'special',
      name: 'תענית - מנחה',
      ashkenaz: [
        VerseRange(book: 'שופטים', fromCh: 4, fromVs: 4, toCh: 4, toVs: 10),
      ],
      sephard: [],
      sephardNone: true,
    ),
    Haftarah(
      id: 'h3',
      category: 'special',
      name: 'יום טוב שני',
      ashkenaz: [
        VerseRange(book: 'שופטים', fromCh: 5, fromVs: 1, toCh: 5, toVs: 10),
      ],
      sephard: [],
      land: 'diaspora',
    ),
  ];

  @override
  List<TorahReading> get torahReadings => const [
    TorahReading(
      id: 'r1',
      category: 'roshChodesh',
      name: 'ראש חודש',
      land: 'both',
      aliyot: [
        ReadingAliya(
          aliya: 'a1',
          aliyaLabel: 'ראשון',
          range: VerseRange(
            book: 'במדבר',
            fromCh: 28,
            fromVs: 1,
            toCh: 28,
            toVs: 5,
          ),
        ),
      ],
    ),
    TorahReading(
      id: 'r2',
      category: 'pesach',
      name: 'פסח יום שני',
      land: 'diaspora',
      aliyot: [
        ReadingAliya(
          aliya: 'a1',
          aliyaLabel: 'ראשון',
          range: VerseRange(
            book: 'ויקרא',
            fromCh: 22,
            fromVs: 26,
            toCh: 22,
            toVs: 30,
          ),
        ),
      ],
    ),
    TorahReading(
      id: 'r3',
      category: 'chanukah',
      name: 'חנוכה לנוסח ספרדי',
      land: 'both',
      nusach: 'sephard',
      aliyot: [
        ReadingAliya(
          aliya: 'a1',
          aliyaLabel: 'ראשון',
          range: VerseRange(
            book: 'במדבר',
            fromCh: 6,
            fromVs: 22,
            toCh: 7,
            toVs: 3,
          ),
        ),
      ],
    ),
  ];

  @override
  Map<String, String> get readingCategoryNames => const {
    'roshChodesh': 'ראש חודש',
    'pesach': 'פסח',
  };

  @override
  List<ParashaAliya> aliyotOf(String bookName, String parashaName) => const [
    ParashaAliya(aliya: 'עליה א', fromCh: 1, fromVs: 1, toCh: 1, toVs: 5),
    ParashaAliya(aliya: 'עליה ב', fromCh: 1, fromVs: 6, toCh: 1, toVs: 9),
  ];

  @override
  String normalizeParashaName(String uiName) => uiName;

  @override
  String aliyaDisplayName(String aliyaKey) =>
      aliyaKey == 'עליה א' ? 'ראשון' : 'שני';

  @override
  String? combinedParashaOf(String parashaName) => null;

  @override
  ({String bookId, String parashaName})? resolveParasha(String calendarName) =>
      calendarName.contains('נח')
      ? (bookId: 'bereshit', parashaName: 'נח')
      : null;
}

class FakeTikkunTextLoader implements TikkunTextLoader {
  final Map<String, String> texts;
  final List<String> requested = [];

  FakeTikkunTextLoader([Map<String, String>? texts])
    : texts = texts ?? const {};

  @override
  Future<String> loadRawText(String hebrewBookName) async {
    requested.add(hebrewBookName);
    return texts[hebrewBookName] ?? 'אחת שתים שלוש ארבע חמש שש שבע שמונה תשע';
  }
}

/// שמירת הגדרות בזיכרון — בלי Settings של אוצריא.
class FakeTikkunSettingsStore extends TikkunSettingsStore {
  TikkunSettings settings;
  TikkunNavState navState;
  int saveCount = 0;

  FakeTikkunSettingsStore({
    this.settings = const TikkunSettings(),
    this.navState = const TikkunNavState(),
  });

  @override
  TikkunSettings load() => settings;

  @override
  Future<void> save(TikkunSettings s) async {
    settings = s;
    saveCount++;
  }

  @override
  TikkunNavState loadNavState() => navState;

  @override
  Future<void> saveNavState(TikkunNavState state) async {
    navState = state;
  }
}

/// מריץ את החישוב בלי isolate.
Future<R> syncComputeRunner<R>(R Function() computation) async => computation();
