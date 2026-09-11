/// שכבת הנתונים של "תיקון קוראים": טעינת טקסט הספרים מהספרייה, מטמון,
/// והרצת מנוע העימוד מחוץ ל-isolate הראשי.
library;

import 'dart:isolate';

import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/repository/tikkun_contracts.dart';

/// טוען את הטקסט הגולמי של ספר לפי שמו העברי בקטלוג.
abstract class TikkunTextLoader {
  Future<String> loadRawText(String hebrewBookName);
}

/// המסלול הרגיל — זהה למסלול שהגשר מספק לתוספים: TextBook מהקטלוג דרך
/// [TextBookRepository], וכל השאר דרך [DataRepository.getBookText].
class LibraryTikkunTextLoader implements TikkunTextLoader {
  const LibraryTikkunTextLoader();

  @override
  Future<String> loadRawText(String hebrewBookName) async {
    final library = await DataRepository.instance.library;
    Book? match;
    for (final book in library.getAllBooks()) {
      if (book.title == hebrewBookName) {
        match = book;
        if (book is TextBook) break;
      }
    }
    if (match is TextBook) {
      return TextBookRepository(
        fileSystem: FileSystemData.instance,
      ).getBookContent(match);
    }
    return DataRepository.instance.getBookText(hebrewBookName);
  }
}

/// מריץ חישוב כבד. ברירת המחדל היא [Isolate.run]; הבדיקות מזריקות ריצה
/// סינכרונית.
typedef TikkunComputeRunner = Future<R> Function<R>(R Function() computation);

Future<R> _defaultRunner<R>(R Function() computation) =>
    Isolate.run(computation);

class TikkunKorimRepository {
  final TikkunEngine engine;
  final TikkunDataSource data;
  final TikkunTextLoader textLoader;
  final TikkunComputeRunner _run;

  TikkunKorimRepository({
    required this.engine,
    required this.data,
    this.textLoader = const LibraryTikkunTextLoader(),
    TikkunComputeRunner? computeRunner,
  }) : _run = computeRunner ?? _defaultRunner;

  /// כמה ספרים מעובדים (מלבד התורה) נשמרים בו-זמנית — LRU.
  static const int maxCachedBooks = 3;

  final Map<String, ProcessedBook> _bookCache = {};
  final Map<String, List<TikkunPage>> _pagesCache = {};
  final Map<TikkunTradition, ProcessedTorah> _torahByTradition = {};
  String? _widthModelId;
  TikkunDecalogueTaam _decalogueTaam = TikkunDecalogueTaam.merged;

  /// הפריסה נגזרת מגופן הסת"ם — מודל רוחב אחר פוסל את כל המטמון.
  void _adoptWidthModel(StamWidthModel widths) {
    if (_widthModelId == widths.id) return;
    clearCaches();
    _widthModelId = widths.id;
  }

  /// טעמי עשרת הדברות משנים את הטקסט עצמו; הם מוחלפים לעיתים רחוקות, ולכן
  /// המעבר פוסל את כל המטמון במקום להיכנס לכל מפתח בנפרד.
  void useDecalogueTaam(TikkunDecalogueTaam taam) {
    if (_decalogueTaam == taam) return;
    final widthModelId = _widthModelId;
    clearCaches();
    _widthModelId = widthModelId;
    _decalogueTaam = taam;
  }

  /// הטקסט הגולמי אינו נשמר: הוא נזרק מיד אחרי הפירוק לאסימונים.
  Future<String> rawText(String hebrewBookName) =>
      textLoader.loadRawText(hebrewBookName);

  /// שמות הספרים שבמטמון, מהישן לחדש — לבדיקות.
  Iterable<String> get cachedBookNames => _bookCache.keys;

  /// כל חמשת החומשים מעובדים יחד. הפרשיות תלויות-הנוסח משתנות בין המסורות,
  /// ולכן הבסיס נשמר בנפרד לכל מסורת ולא לכל שיטה.
  Future<ProcessedTorah> processedTorah(
    StamWidthModel widths, {
    String methodId = '',
  }) async {
    _adoptWidthModel(widths);
    final tradition = TikkunTradition.forMethod(methodId);
    final taam = _decalogueTaam;
    final cached = _torahByTradition[tradition];
    if (cached != null) return cached;
    final raws = <String, String>{};
    for (final book in data.chumashim) {
      raws[book.id] = await rawText(book.name);
    }
    final engine = this.engine;
    final processed = await _run(
      () => engine.processTorah(
        raws,
        widths,
        tradition: tradition,
        decalogueTaam: taam,
      ),
    );
    _torahByTradition[tradition] = processed;
    return processed;
  }

  Future<List<TikkunPage>> torahPages(
    String methodId,
    StamWidthModel widths,
  ) async {
    _adoptWidthModel(widths);
    final cached = _pagesCache[methodId];
    if (cached != null) return cached;
    final processed = await processedTorah(widths, methodId: methodId);
    final engine = this.engine;
    final pages = await _run(() => engine.buildPages(processed, methodId));
    _pagesCache[methodId] = pages;
    return pages;
  }

  Future<ProcessedBook> processedBook(
    String hebrewBookName,
    StamWidthModel widths,
  ) async {
    _adoptWidthModel(widths);
    final cached = _bookCache.remove(hebrewBookName);
    if (cached != null) {
      _bookCache[hebrewBookName] = cached;
      return cached;
    }
    final raw = await rawText(hebrewBookName);
    final engine = this.engine;
    final taam = _decalogueTaam;
    final processed = await _run(
      () => engine.processBook(
        raw,
        hebrewBookName,
        widths,
        decalogueTaam: taam,
      ),
    );
    _bookCache[hebrewBookName] = processed;
    while (_bookCache.length > maxCachedBooks) {
      _bookCache.remove(_bookCache.keys.first);
    }
    return processed;
  }

  /// שורות ההפטרה שנבחרה, לפי הנוסח.
  Future<List<TikkunLine>> haftarahLines(
    Haftarah haftarah,
    String nusach,
    StamWidthModel widths,
  ) => _linesForRanges(
    haftarah.forNusach(nusach).map((r) => (range: r, label: null)).toList(),
    widths,
  );

  /// שורות קריאת המועד, כולל סימון שמות העליות.
  Future<List<TikkunLine>> readingLines(
    TorahReading reading,
    StamWidthModel widths,
  ) => _linesForRanges(
    reading.aliyot.map((a) => (range: a.range, label: a.aliyaLabel)).toList(),
    widths,
    aliyaKeys: reading.aliyot.map((a) => a.aliya).toList(),
  );

  Future<List<TikkunLine>> _linesForRanges(
    List<({VerseRange range, String? label})> parts,
    StamWidthModel widths, {
    List<String>? aliyaKeys,
  }) async {
    final combined = <TikkunToken>[];
    final markers = <({int tokenIdx, String label, String? scrollLabel})>[];
    String? lastAliyaKey;
    ({String book, int ch, int vs})? lastTo;
    var scrollIdx = 0;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final range = part.range;
      final processed = await processedBook(range.book, widths);
      final slice = engine.sliceTokensByVerseRange(
        processed.tokens,
        range.fromCh,
        range.fromVs,
        range.toCh,
        range.toVs,
      );

      final startsAfterSetuma = engine.precededBySetuma(
        processed.tokens,
        range.fromCh,
        range.fromVs,
      );
      final isNewAliya = aliyaKeys == null || aliyaKeys[i] != lastAliyaKey;
      String? scrollLabel;

      if (i == 0) {
        if (startsAfterSetuma) {
          combined.add(
            const TikkunToken(type: TikkunTokenType.leadingSetuma),
          );
        }
      } else if (_needsBreak(range, lastTo, isNewAliya)) {
        combined.add(
          TikkunToken(
            type: startsAfterSetuma
                ? TikkunTokenType.leadingSetuma
                : TikkunTokenType.petucha,
          ),
        );
        // מעבר לספר אחר = ספר תורה נוסף; באותו חומש רק אחרי שכבר הוחלף
        // ספר, שאם לא כן דילוג פנימי (תענית ציבור) ייחשב בטעות כהחלפה.
        if (aliyaKeys != null &&
            (range.book != lastTo!.book || scrollIdx > 0)) {
          scrollIdx++;
          scrollLabel = torahScrollLabel(scrollIdx);
        }
      }

      if (part.label != null && isNewAliya) {
        markers.add((
          tokenIdx: combined.length,
          label: part.label!,
          scrollLabel: scrollLabel,
        ));
      }
      combined.addAll(slice);
      if (aliyaKeys != null) lastAliyaKey = aliyaKeys[i];
      lastTo = (book: range.book, ch: range.toCh, vs: range.toVs);
    }

    final localEngine = engine;
    final lines = await _run(
      () => localEngine.paginateAllTokens(combined, widths),
    );
    _annotateAliyaMarkers(lines, combined, markers);
    if (lines.isNotEmpty && !lines.last.isSpecial) {
      lines.last.layout = LineLayout.petucha;
    }
    return lines;
  }

  /// הפסק מוסף רק במעבר לא רציף במקור (למשל מפטיר ממקום אחר).
  bool _needsBreak(
    VerseRange range,
    ({String book, int ch, int vs})? lastTo,
    bool isNewAliya,
  ) {
    if (lastTo == null) return false;
    if (!isNewAliya) return false;
    final sameBook = range.book == lastTo.book;
    final adjacent =
        sameBook &&
        ((range.fromCh == lastTo.ch && range.fromVs == lastTo.vs + 1) ||
            (range.fromCh == lastTo.ch + 1 && range.fromVs == 1));
    final overlap =
        sameBook &&
        (range.fromCh < lastTo.ch ||
            (range.fromCh == lastTo.ch && range.fromVs <= lastTo.vs));
    return !adjacent && !overlap;
  }

  void _annotateAliyaMarkers(
    List<TikkunLine> lines,
    List<TikkunToken> tokens,
    List<({int tokenIdx, String label, String? scrollLabel})> markers,
  ) {
    for (final marker in markers) {
      var firstWordIdx = -1;
      for (var j = marker.tokenIdx; j < tokens.length; j++) {
        if (tokens[j].isWord) {
          firstWordIdx = j;
          break;
        }
      }
      if (firstWordIdx < 0) continue;
      for (var i = 0; i < lines.length; i++) {
        final nextStart = i + 1 < lines.length
            ? lines[i + 1].startTokenIdx
            : 1 << 30;
        if (lines[i].startTokenIdx >= 0 &&
            lines[i].startTokenIdx <= firstWordIdx &&
            firstWordIdx < nextStart) {
          if (marker.label == kMaftirAliyaName) {
            lines[i].maftirName ??= marker.label;
          } else {
            lines[i].aliyaName ??= marker.label;
          }
          lines[i].torahScrollLabel ??= marker.scrollLabel;
          break;
        }
      }
    }
  }

  void clearCaches() {
    _bookCache.clear();
    _pagesCache.clear();
    _torahByTradition.clear();
    _widthModelId = null;
  }
}
