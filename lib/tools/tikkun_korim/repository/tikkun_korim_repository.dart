/// שכבת הנתונים של "תיקון קוראים": טעינת טקסט הספרים מהספרייה, מטמון,
/// והרצת מנוע העימוד מחוץ ל-isolate הראשי.
library;

import 'dart:isolate';

import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart';
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
  final Map<String, ProcessedTorah> _torahByMethod = {};
  String? _widthModelId;
  int _cacheGeneration = 0;
  TikkunDecalogueTaam _decalogueTaam = TikkunDecalogueTaam.merged;

  /// הפריסה נגזרת מגופן הסת"ם — מודל רוחב אחר פוסל את כל המטמון.
  void _adoptWidthModel(StamWidthModel widths) {
    if (_widthModelId == widths.cacheKey) return;
    clearCaches();
    _widthModelId = widths.cacheKey;
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

  /// כל חמשת החומשים מעובדים יחד. עוגני העמודים כופים שבירות שורה שונות בכל
  /// שיטה, ולכן העימוד נשמר לכל שיטה ולא לכל מסורת.
  Future<ProcessedTorah> processedTorah(
    StamWidthModel widths, {
    String methodId = '',
  }) async {
    _adoptWidthModel(widths);
    final generation = _cacheGeneration;
    final tradition = TikkunTradition.forMethod(methodId);
    final taam = _decalogueTaam;
    final cached = _torahByMethod[methodId];
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
        methodId: methodId,
      ),
    );
    if (generation == _cacheGeneration) {
      _torahByMethod[methodId] = processed;
    }
    return processed;
  }

  Future<List<TikkunPage>> torahPages(
    String methodId,
    StamWidthModel widths,
  ) async {
    _adoptWidthModel(widths);
    final generation = _cacheGeneration;
    final cached = _pagesCache[methodId];
    if (cached != null) return cached;
    final processed = await processedTorah(widths, methodId: methodId);
    final engine = this.engine;
    final pages = await _run(() => engine.buildPages(processed, methodId));
    if (generation == _cacheGeneration) _pagesCache[methodId] = pages;
    return pages;
  }

  Future<ProcessedBook> processedBook(
    String hebrewBookName,
    StamWidthModel widths,
  ) async {
    _adoptWidthModel(widths);
    final generation = _cacheGeneration;
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
    if (generation != _cacheGeneration) return processed;
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
  ) => _linesForParts(haftarahParts(haftarah, nusach), widths);

  /// שורות קריאת המועד, כולל סימון שמות העליות.
  Future<List<TikkunLine>> readingLines(
    TorahReading reading,
    StamWidthModel widths,
  ) => _linesForParts(readingParts(reading), widths);

  Future<List<TikkunLine>> _linesForParts(
    List<VersePart> parts,
    StamWidthModel widths,
  ) async {
    final tokensByBook = {
      for (final p in parts)
        p.range.book: (await processedBook(p.range.book, widths)).tokens,
    };
    // בלי `this` בסגירה — היא נשלחת ל-Isolate.
    final run = _run, localEngine = engine;
    return buildVersePartLines(
      localEngine,
      parts,
      tokensByBook,
      widths,
      paginate: (tokens) =>
          run(() => localEngine.paginateAllTokens(tokens, widths)),
    );
  }

  void clearCaches() {
    _cacheGeneration++;
    _bookCache.clear();
    _pagesCache.clear();
    _torahByMethod.clear();
    _widthModelId = null;
  }
}
