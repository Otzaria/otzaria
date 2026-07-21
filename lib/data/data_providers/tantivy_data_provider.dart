import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:otzaria/core/app_paths.dart';

/// A singleton class that manages search functionality using Tantivy search engine.
///
/// This provider handles the search operations for both text-based and PDF books,
/// maintaining an index for full-text search capabilities.
///
/// מצב האינדקס (אילו ספרים מאונדקסים, האם נדרשת בנייה מחדש) נקרא מהאינדקס
/// עצמו דרך מנוע החיפוש — לא מאחסון חיצוני של האפליקציה.
class TantivyDataProvider {
  static const SearchEngineGateway _searchGateway = SearchEngineGateway();

  /// סטטוסים של [checkIndexCompatibility] שמשמעותם שהאינדקס הקיים אינו
  /// תואם למנוע הנוכחי וחובה לאפס ולבנות אותו מחדש.
  static const Set<String> _rebuildRequiredStatuses = {
    'rebuild_required',
    'engine_too_old',
  };

  /// Instance of the search engine pointing to the index directory
  late Future<SearchEngine> engine;

  /// Track if index is being reopened to prevent concurrent reopens
  final ReopenGate _reopenGate = ReopenGate();
  Future<bool>? _magicDictionaryDownload;

  static final TantivyDataProvider _singleton = TantivyDataProvider._internal();
  static TantivyDataProvider instance = _singleton;

  // Global cache for facet counts
  static final Map<String, int> _globalFacetCache = {};
  static String _lastCachedQuery = '';

  // ספירות שכבר רצות: קריאה חוזרת לאותו מפתח ממתינה על אותו Future במקום
  // לרוץ שוב (מחליף את לולאת ה-polling הישנה של 50ms).
  static final Map<String, Future<int>> _inflightCounts = {};

  /// תוצאת בדיקת התאימות של האינדקס, כפי שנקראה מהאינדקס עצמו
  /// (otzaria_index_meta.json או meta.json של Tantivy) דרך מנוע החיפוש.
  IndexCompatibility? _indexCompatibility;
  IndexCompatibility? get indexCompatibility => _indexCompatibility;

  /// Clear global cache when starting new search
  static void clearGlobalCache() {
    debugPrint(
      '🧹 Clearing global facet cache (${_globalFacetCache.length} entries)',
    );
    _globalFacetCache.clear();
    _inflightCounts.clear();
    _lastCachedQuery = '';
  }

  /// Indicates whether the indexing process is currently running
  ValueNotifier<bool> isIndexing = ValueNotifier(false);

  /// המנוע רץ על אינדקס זמני כי פתיחת אינדקס הדיסק נכשלה. במצב זה אסור
  /// לאנדקס — הכתיבות היו הולכות לתיקייה זמנית שנזרקת בהפעלה הבאה.
  bool isTempFallback = false;

  /// מסמן שקריאת מצב האינדקס מהאינדקס עצמו ([indexedFilePaths]) הסתיימה.
  /// עד שהערך הופך ל-true, אסור להסיק "אין אינדקס" מ-indexedFilePaths.isEmpty.
  final ValueNotifier<bool> isInitialized = ValueNotifier(false);

  /// נתיבי הספרים (שדה filePath של המסמכים) שיש להם לפחות מסמך חי באינדקס.
  /// נקרא מהאינדקס עצמו בעת פתיחת המנוע, ומתעדכן בזיכרון תוך כדי אינדוקס.
  final Set<String> indexedFilePaths = {};

  TantivyDataProvider._internal() {
    engine = _initAll();
  }

  /// בודק את תאימות האינדקס, פותח את המנוע, וקורא ממנו את רשימת
  /// הספרים המאונדקסים. בדיקת התאימות רצה לפני פתיחת המנוע, כי המנוע
  /// יוצר את תיקיית האינדקס (וכותב otzaria_index_meta.json) אם אינה קיימת.
  Future<SearchEngine> _initAll() async {
    // בפתיחה מחדש (reopen/clear) הערך כבר true; איפוס מונע מהצרכנים
    // להסיק "אין אינדקס" מ-indexedFilePaths בזמן שהטעינה מחדש רצה.
    isInitialized.value = false;

    final indexPath = await AppPaths.getIndexPath();
    _indexCompatibility = _checkIndexCompatibility(indexPath);

    final engine = await _initEngine();
    await _loadIndexedFilePaths(engine);

    // indexedFilePaths כעת משקפת את מצב האינדקס בפועל. צרכנים שמסיקים
    // "אין אינדקס" מתוך הקבוצה צריכים לחכות לסימן הזה כדי לא להציג שגוי בהפעלה.
    isInitialized.value = true;
    return engine;
  }

  /// קורא את תוצאת בדיקת התאימות מהאינדקס עצמו. כשל בבדיקה אינו עוצר את
  /// האתחול — המנוע ייפתח כרגיל והסטטוס יישאר לא ידוע (null).
  IndexCompatibility? _checkIndexCompatibility(String indexPath) {
    try {
      final compatibility = checkIndexCompatibility(path: indexPath);
      debugPrint(
        '🔎 תאימות אינדקס: ${compatibility.status} '
        '(נמצא: ${compatibility.foundSchemaVersion}, '
        'נדרש: ${compatibility.requiredSchemaVersion})',
      );
      return compatibility;
    } catch (e) {
      debugPrint('⚠️ בדיקת תאימות האינדקס נכשלה: $e');
      return null;
    }
  }

  /// טוען מהאינדקס עצמו את רשימת הספרים שיש להם מסמכים חיים.
  Future<void> _loadIndexedFilePaths(SearchEngine engine) async {
    indexedFilePaths.clear();
    try {
      indexedFilePaths.addAll(await engine.getIndexedFilePaths());
      debugPrint(
        '📚 נקראו ${indexedFilePaths.length} ספרים מאונדקסים מהאינדקס',
      );
    } catch (e) {
      debugPrint('⚠️ קריאת הספרים המאונדקסים מהאינדקס נכשלה: $e');
    }
  }

  /// טוען את מילון `lexical.db` (חיפוש מקורב) אל המנוע, אם הוא קיים.
  /// פעולה best-effort: כשל או קובץ חסר אינם שוברים את אתחול המנוע —
  /// החיפוש המקורב פשוט ימשיך ללא הרחבה מורפולוגית. מחזיר האם המילון נטען.
  Future<bool> _attachMagicDictionary(SearchEngine engine) async {
    try {
      final dictPath = await AppPaths.getMagicDictionaryPath();
      final loaded = engine.setMagicDictionaryPath(path: dictPath);
      debugPrint(
        loaded
            ? '🔤 מילון מורפולוגי נטען לחיפוש המקורב: $dictPath'
            : 'ℹ️ אין מילון מורפולוגי ($dictPath) — חיפוש מקורב ללא הרחבה',
      );
      return loaded;
    } catch (e) {
      debugPrint('⚠️ טעינת המילון המורפולוגי נכשלה: $e');
      return false;
    }
  }

  /// האם החיפוש המקורב משתמש כרגע בהרחבה מורפולוגית (מילון טעון).
  Future<bool> get hasMagicDictionary async =>
      (await engine).hasMagicDictionary();

  /// טוען אל המנוע את מילוני ההרחבה של החיפוש המתקדם — מילון התרגום
  /// הארמי-עברי (אפשרות "תרגום ארמי") ומילון ראשי-התיבות (אפשרות
  /// "ראשי תיבות"). המילונים הם assets מוטמעים, אך המנוע קורא רק מנתיב
  /// קובץ — לכן הם מחולצים לדיסק תחילה. best-effort: כשל אינו שובר את
  /// אתחול המנוע, האפשרות פשוט לא תרחיב דבר.
  Future<void> _attachSearchLexicons(SearchEngine engine) async {
    final translationPath = await _materializeBundledAsset(
      'assets/dictionary.json',
      'dictionary.json',
    );
    if (translationPath != null) {
      final loaded = engine.setTranslationDictionaryPath(path: translationPath);
      debugPrint(
        loaded
            ? '🔤 מילון תרגום ארמי נטען: $translationPath'
            : '⚠️ מילון התרגום הארמי לא נטען ($translationPath)',
      );
    }
    final acronymsPath = await _materializeBundledAsset(
      'assets/Acronyms.json',
      'Acronyms.json',
    );
    if (acronymsPath != null) {
      final loaded = engine.setAcronymsDictionaryPath(path: acronymsPath);
      debugPrint(
        loaded
            ? '🔤 מילון ראשי-תיבות נטען: $acronymsPath'
            : '⚠️ מילון ראשי-התיבות לא נטען ($acronymsPath)',
      );
    }
  }

  /// מחלץ asset מוטמע לקובץ בדיסק ומחזיר את נתיבו, או null בכשל.
  /// נכתב מחדש כשהתוכן בדיסק שונה מה-asset — השוואת בייטים מלאה, לא רק
  /// גודל: עדכון מילון ששומר על אותו אורך (תיקון ערך בודד) חייב להתפיס.
  /// הקריאה החוזרת זולה יחסית (המילונים 1-3MB, פעם אחת באתחול).
  Future<String?> _materializeBundledAsset(
    String assetKey,
    String fileName,
  ) async {
    try {
      final data = await rootBundle.load(assetKey);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final dir = Directory(
        p.join(await AppPaths.getDataRootPath(), 'dictionaries'),
      );
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, fileName));
      final upToDate =
          await file.exists() &&
          await file.length() == bytes.length &&
          _bytesEqual(await file.readAsBytes(), bytes);
      if (!upToDate) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.path;
    } catch (e) {
      debugPrint('⚠️ חילוץ $assetKey נכשל: $e');
      return null;
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// מוריד את מילון המורפולוגיה האחרון (אם חסר/ישן) וטוען אותו אל המנוע
  /// החי, כך שהחיפוש המקורב יתחיל להשתמש בו מיד — בלי הפעלה מחדש.
  ///
  /// מחזיר `true` אם בסיום קיים מילון טעון. best-effort: כשל הורדה אינו
  /// משפיע על שאר המנוע.
  Future<bool> downloadMagicDictionary({
    void Function(double progress)? onProgress,
    bool force = false,
  }) async {
    final currentDownload = _magicDictionaryDownload;
    if (currentDownload != null) return currentDownload;

    final download = _downloadMagicDictionary(
      onProgress: onProgress,
      force: force,
    );
    _magicDictionaryDownload = download;
    try {
      return await download;
    } finally {
      if (identical(_magicDictionaryDownload, download)) {
        _magicDictionaryDownload = null;
      }
    }
  }

  Future<bool> _downloadMagicDictionary({
    void Function(double progress)? onProgress,
    required bool force,
  }) async {
    final downloader = MagicDictionaryDownloader();
    try {
      final ok = await downloader.ensureLatest(
        onProgress: onProgress,
        force: force,
      );
      if (!ok) return false;
      return await _attachMagicDictionary(await engine);
    } finally {
      downloader.dispose();
    }
  }

  /// מספר ניסיונות הפתיחה שנכשלו לפי תוכן קובץ הסנטינל. תוכן לא-מספרי
  /// (פורמט ישן ששמר תאריך) נספר ככישלון יחיד.
  @visibleForTesting
  static int sentinelFailedAttempts(String? content) =>
      int.tryParse(content?.trim() ?? '') ?? 1;

  /// האם להזיז את האינדקס הצידה: רק אחרי שני כשלונות פתיחה רצופים.
  /// כישלון בודד עשוי להיות kill של המשתמש בזמן האתחול — ניגוב מיידי
  /// היה זורק אינדקס תקין של שעות עבודה.
  @visibleForTesting
  static bool shouldDiscardIndex(int failedAttempts) => failedAttempts >= 2;

  Future<SearchEngine> _initEngine() async {
    String? indexPath;
    File? sentinelFile;
    isTempFallback = false;

    try {
      indexPath = await AppPaths.getIndexPath();
      final parentDir = Directory(indexPath).parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      sentinelFile = File('${parentDir.path}/.engine_init_started');

      // סנטינל שנשאר = הריצה הקודמת מתה בזמן פתיחת המנוע.
      var failedAttempts = 0;
      if (sentinelFile.existsSync()) {
        String? content;
        try {
          content = sentinelFile.readAsStringSync();
        } catch (_) {}
        failedAttempts = sentinelFailedAttempts(content);
        debugPrint('⚠️ נמצא סנטינל פתיחה ($failedAttempts כשלונות קודמים)');
      }

      if (shouldDiscardIndex(failedAttempts)) {
        debugPrint('⚠️ שני כשלונות פתיחה רצופים — מזיז את האינדקס הצידה');
        try {
          if (Directory(indexPath).existsSync()) {
            // Use rename instead of delete - much safer on Windows
            final corruptedPath =
                '${indexPath}_corrupted_${DateTime.now().millisecondsSinceEpoch}';
            Directory(indexPath).renameSync(corruptedPath);
            debugPrint('📦 Moved corrupted index to $corruptedPath');
          }
        } catch (e) {
          debugPrint('❌ Failed to rename corrupted index: $e');
          // If rename fails, force use a new path
          indexPath =
              '${indexPath}_new_${DateTime.now().millisecondsSinceEpoch}';
        }
        failedAttempts = 0;
      }

      // הסנטינל מכסה רק את קריאת הפתיחה הנייטיבית: קריסה בטעינת המילונים
      // שאחריה אינה מעידה על אינדקס פגום ואסור שתנגב אותו.
      try {
        await sentinelFile.writeAsString('${failedAttempts + 1}');
      } catch (e) {
        debugPrint('⚠️ Failed to create sentinel file: $e');
      }

      // Ensure the index directory exists before opening the engine.
      final indexDir = Directory(indexPath);
      if (!indexDir.existsSync()) {
        indexDir.createSync(recursive: true);
      }

      // Try to open engine
      // If this CRASHES the process, the sentinel remains for next run.
      // If it throws an Exception, we catch it below.
      final engine = SearchEngine(path: indexPath);

      // הפתיחה הנייטיבית הצליחה — האינדקס תקין, הסנטינל מוסר מיד.
      try {
        await sentinelFile.delete();
      } catch (_) {}

      // טעינת מילון מורפולוגי לחיפוש המקורב (best-effort, לא חוסם).
      await _attachMagicDictionary(engine);

      // מילוני החיפוש המתקדם: תרגום ארמי + ראשי-תיבות (best-effort).
      await _attachSearchLexicons(engine);

      return engine;
    } catch (e) {
      debugPrint('❌ Failed to initialize search engine: $e');

      // הסנטינל נשאר בכוונה: גם כשל פתיחה שנתפס כחריגה (לא קריסה) חייב
      // להיצבר במונה — אחרת אינדקס שפתיחתו נכשלת שוב ושוב לעולם לא היה
      // מגיע לסף שני הכשלונות ולא היה מוזז הצידה.

      // Recover by falling back to temp memory index
      debugPrint('⚠️ Falling back to temporary in-memory index');
      try {
        final tempDir = Directory.systemTemp.createTempSync(
          'otzaria_temp_index_',
        );
        final tempEngine = SearchEngine(path: tempDir.path);
        isTempFallback = true;
        return tempEngine;
      } catch (e2) {
        debugPrint('❌ CRITICAL: Failed to create temp index: $e2');
        rethrow;
      }
    }
  }

  /// האם האינדקס הקיים דורש איפוס ובנייה מחדש, לפי בדיקת התאימות
  /// שנקראה מהאינדקס עצמו בעת פתיחת המנוע.
  bool get requiresManualReindex =>
      isRebuildRequiredStatus(_indexCompatibility?.status);

  /// האם סטטוס תאימות נתון מחייב בנייה מחדש של האינדקס.
  @visibleForTesting
  static bool isRebuildRequiredStatus(String? status) =>
      _rebuildRequiredStatuses.contains(status);

  Future<void> _handleSchemaError() async {
    try {
      String indexPath = await AppPaths.getIndexPath();
      await resetIndex(indexPath);
      // force: אחרי reset המנוע סגור וחייב פתיחה; בלי force מגבלת חמש
      // השניות (פתיחה קודמת זה עתה) הייתה מדלגת ומשאירה מנוע סגור.
      await reopenIndex(force: true);
    } catch (e) {
      debugPrint('❌ Error handling schema error: $e');
    }
  }

  /// פותח את המנוע מחדש וקורא את מצב האינדקס מהדיסק. מחזיר האם הפתיחה
  /// אכן בוצעה (או הושלמה ע"י reopen שכבר רץ) — false רק בדילוג throttle.
  ///
  /// [force] עוקף את מגבלת חמש-השניות ומבטיח פתיחה שמתחילה אחרי הקריאה —
  /// למסלולי שחזור אחרי כשל כתיבה, שבהם reopen ישן עלול לקרוא מצב מעופש.
  Future<bool> reopenIndex({bool force = false}) =>
      _reopenGate.run(_doReopen, force: force);

  Future<void> _doReopen() async {
    debugPrint('🔄 Reopening search index...');

    // Dispose previous engine to release locks
    await dispose();

    // Reset engines (כולל קריאה מחדש של מצב האינדקס מהאינדקס עצמו)
    engine = _initAll();

    // await יחיד: כשל ב-_initAll מופץ לקורא. בלעדיו (engine.then נגזר
    // שנזרק) הכשל היה מדווח כשגיאה אסינכרונית לא-מטופלת. ההמתנה גם מבטיחה
    // ש-indexedFilePaths נקרא מחדש לפני דיווח ההצלחה.
    final value = await engine;
    debugPrint('✅ Search index reopened successfully');

    // בדיקת שפיות של המנוע — try/catch יחיד. שגיאת סכימה מפעילה איפוס
    // ובנייה מחדש; הקריאה fire-and-forget כי היא חוזרת ל-reopenIndex,
    // וההמתנה לה מתוך פתיחה פעילה הייתה ננעלת על השער (re-entrant).
    try {
      await _searchGateway.search(
        RustSearchEngineOperations(value),
        const SearchEngineRequest(
          query: 'a',
          limit: 10,
          offset: 0,
          facets: ["/"],
          order: ResultsOrder.catalogue,
          searchMode: SearchMode.exact,
        ),
      );
      debugPrint('✅ Search engine test successful');
    } catch (e) {
      debugPrint('❌ Engine test error: $e');
      if (e.toString() ==
          "PanicException(Failed to create index: SchemaError(\"An index exists but the schema does not match.\"))") {
        unawaited(_handleSchemaError());
      }
    }
  }

  Future<int> countTexts(
    String query,
    List<String> books,
    List<String> facets, {
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) async {
    // Global cache check
    final cacheKey =
        '$query|not=$negativeQuery|${facets.join(',')}|$fuzzy|$searchMode|$distance|${negativeDistance ?? distance}|$scope|${negativeScope ?? scope}|${customSpacing.toString()}|${negativeCustomSpacing.toString()}|${alternativeWords.toString()}|${negativeAlternativeWords.toString()}|${searchOptions.toString()}|${negativeSearchOptions.toString()}|$matchNikud|$matchTaamim|$wordMatchMode|$wordMatchCount';

    if (_lastCachedQuery == query && _globalFacetCache.containsKey(cacheKey)) {
      debugPrint(
        '🎯 GLOBAL CACHE HIT for $facets: ${_globalFacetCache[cacheKey]}',
      );
      return _globalFacetCache[cacheKey]!;
    }

    // ספירה זהה שכבר רצה: ממתינים על אותו Future במקום להריץ שוב
    // (ובלי לולאת ה-polling של 50ms שהייתה כאן).
    final inflight = _inflightCounts[cacheKey];
    if (inflight != null) {
      debugPrint('⏳ Count already in progress for $facets, awaiting...');
      return inflight;
    }

    final future = () async {
      final count = await _searchGateway.count(
        RustSearchEngineOperations(await engine),
        SearchEngineRequest(
          query: query,
          facets: facets,
          searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
          distance: distance,
          negativeQuery: negativeQuery,
          negativeDistance: negativeDistance ?? distance,
          scope: scope,
          negativeScope: negativeScope ?? scope,
          customSpacing: customSpacing ?? const {},
          negativeCustomSpacing: negativeCustomSpacing ?? const {},
          alternativeWords: alternativeWords ?? const {},
          negativeAlternativeWords: negativeAlternativeWords ?? const {},
          searchOptions: searchOptions ?? const {},
          negativeSearchOptions: negativeSearchOptions ?? const {},
          matchNikud: matchNikud,
          matchTaamim: matchTaamim,
          wordMatchMode: wordMatchMode,
          wordMatchCount: wordMatchCount,
        ),
      );

      // Save to global cache
      _lastCachedQuery = query;
      _globalFacetCache[cacheKey] = count;
      debugPrint('💾 GLOBAL CACHE SAVE for $facets: $count');

      return count;
    }();

    _inflightCounts[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inflightCounts.remove(cacheKey);
    }
  }

  Future<void> resetIndex(String indexPath) async {
    debugPrint('🔄 Resetting index at: $indexPath');

    // Close engines first to release locks
    try {
      await dispose();
      debugPrint('🔒 Engines disposed before reset');
    } catch (e) {
      debugPrint('⚠️ Error disposing engines before reset: $e');
    }

    Directory indexDirectory = Directory(indexPath);
    if (indexDirectory.existsSync()) {
      try {
        indexDirectory.deleteSync(recursive: true);
      } catch (e) {
        debugPrint('❌ Failed to delete index directory: $e');
        // On Windows, sometimes files are locked for a bit longer
        await Future.delayed(const Duration(seconds: 1));
        if (indexDirectory.existsSync()) {
          indexDirectory.deleteSync(recursive: true);
        }
      }
    }

    indexDirectory.createSync(recursive: true);

    debugPrint('✅ Index reset completed');
  }

  Future<Map<String, int>> countByBook(
    String query,
    List<String> facets, {
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) async {
    final results = await _searchGateway.countByBook(
      RustSearchEngineOperations(await engine),
      SearchEngineRequest(
        query: query,
        facets: facets,
        searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
        distance: distance,
        negativeQuery: negativeQuery,
        negativeDistance: negativeDistance ?? distance,
        scope: scope,
        negativeScope: negativeScope ?? scope,
        customSpacing: customSpacing ?? const {},
        negativeCustomSpacing: negativeCustomSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        negativeAlternativeWords: negativeAlternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
        negativeSearchOptions: negativeSearchOptions ?? const {},
        matchNikud: matchNikud,
        matchTaamim: matchTaamim,
        wordMatchMode: wordMatchMode,
        wordMatchCount: wordMatchCount,
      ),
    );

    return Map<String, int>.from(results);
  }

  /// Performs an asynchronous stream-based search operation across indexed texts.
  ///
  /// [query] The search query string
  /// [books] List of book identifiers to search within
  /// [limit] Maximum number of results to return
  /// [fuzzy] Whether to perform fuzzy matching
  ///
  /// Returns a Stream of search results that can be listened to for real-time updates
  Stream<List<SearchResult>> searchTextsStream(
    String query,
    List<String> facets,
    int limit,
    bool fuzzy,
  ) async* {
    yield* _searchGateway.searchStream(
      RustSearchEngineOperations(await engine),
      SearchEngineRequest(
        query: query,
        facets: facets,
        limit: limit,
        searchMode: fuzzy ? SearchMode.fuzzy : SearchMode.exact,
      ),
      chunkSize: 50,
    );
  }

  /// ספירה מקבצת של תוצאות עבור מספר facets בבת אחת - לשיפור ביצועים.
  /// מקבץ facets לפי parent prefix ומשתמש ב-getFacetCounts כשיש כמה siblings,
  /// כדי לחסוך קריאות FFI מיותרות.
  Future<Map<String, int>> countTextsForMultipleFacets(
    String query,
    List<String> books,
    List<String> facets, {
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
    bool allowEarlyStop = true,
  }) async {
    debugPrint(
      '🔍 TantivyDataProvider: Starting batch count for ${facets.length} facets',
    );
    final stopwatch = Stopwatch()..start();

    final operations = RustSearchEngineOperations(await engine);
    final results = <String, int>{};
    final baseRequest = SearchEngineRequest(
      query: query,
      facets: facets,
      searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
      distance: distance,
      negativeQuery: negativeQuery,
      negativeDistance: negativeDistance ?? distance,
      scope: scope,
      negativeScope: negativeScope ?? scope,
      customSpacing: customSpacing ?? const {},
      negativeCustomSpacing: negativeCustomSpacing ?? const {},
      alternativeWords: alternativeWords ?? const {},
      negativeAlternativeWords: negativeAlternativeWords ?? const {},
      searchOptions: searchOptions ?? const {},
      negativeSearchOptions: negativeSearchOptions ?? const {},
      matchNikud: matchNikud,
      matchTaamim: matchTaamim,
      wordMatchMode: wordMatchMode,
      wordMatchCount: wordMatchCount,
    );

    // קיבוץ facets לפי parent prefix כדי לחסוך קריאות FFI
    final Map<String, List<String>> byParent = {};
    for (final facet in facets) {
      final lastSlash = facet.lastIndexOf('/');
      final parent = lastSlash > 0 ? facet.substring(0, lastSlash) : '/';
      (byParent[parent] ??= []).add(facet);
    }

    // הקבוצות בלתי-תלויות והמנוע תומך בקריאות במקביל (RwLock — קוראים
    // אינם חוסמים זה את זה), לכן כל הקבוצות נשלחות יחד במקום await סדרתי
    // פר-קבוצה; מטמון הטרמים במנוע הופך את הקריאות לאותה שאילתה לזולות.
    Future<Map<String, int>> countGroup(
      String parent,
      List<String> siblings,
    ) async {
      final groupResults = <String, int>{};
      if (siblings.length > 1) {
        // כמה siblings מאותו parent - קריאה אחת ל-getFacetCounts מספיקה
        try {
          debugPrint(
            '🔍 getFacetCounts: parent=$parent (${siblings.length} siblings)',
          );
          final facetCounts = await _searchGateway.getFacetCounts(
            operations,
            baseRequest.copyWith(facets: [parent]),
            facetPrefix: parent,
          );
          final countMap = {
            for (final fc in facetCounts) fc.path: fc.count.toInt(),
          };
          for (final sibling in siblings) {
            groupResults[sibling] = countMap[sibling] ?? 0;
          }
          debugPrint(
            '✅ getFacetCounts: ${countMap.entries.where((e) => e.value > 0).length} non-zero',
          );
        } catch (e) {
          debugPrint('⚠️ getFacetCounts failed for $parent, fallback: $e');
          // fallback לקריאות count נפרדות
          for (final facet in siblings) {
            try {
              groupResults[facet] = await _searchGateway.count(
                operations,
                baseRequest.copyWith(facets: [facet]),
              );
            } catch (e2) {
              debugPrint('❌ count failed for $facet: $e2');
              groupResults[facet] = 0;
            }
          }
        }
      } else {
        // sibling יחיד - count ישיר יעיל יותר
        final facet = siblings[0];
        try {
          groupResults[facet] = await _searchGateway.count(
            operations,
            baseRequest.copyWith(facets: [facet]),
          );
        } catch (e) {
          debugPrint('❌ count failed for $facet: $e');
          groupResults[facet] = 0;
        }
      }
      return groupResults;
    }

    final groupResults = await Future.wait([
      for (final entry in byParent.entries) countGroup(entry.key, entry.value),
    ]);
    for (final group in groupResults) {
      results.addAll(group);
    }

    stopwatch.stop();
    debugPrint(
      '✅ TantivyDataProvider: Batch count completed in ${stopwatch.elapsedMilliseconds}ms',
    );
    debugPrint(
      '📊 Results: ${results.entries.where((e) => e.value > 0).map((e) => '${e.key}: ${e.value}').join(', ')}',
    );

    return results;
  }

  /// Clears the index and resets the list of indexed books.
  ///
  /// מוחק פיזית את תיקיית האינדקס הפעילה וכל תיקיות אינדקס ישנות שנשארו
  /// בנתיבי ברירת מחדל אחרים, ואז פותח מנוע חדש. כך, אם המשתמש העביר
  /// את הספרייה לכונן אחר, האינדקס הבא ייבנה ליד הספרייה החדשה.
  Future<void> clear() async {
    isIndexing.value = false;
    indexedFilePaths.clear();

    // שחרור משאבים לפני מחיקה פיזית של הקבצים (חשוב במיוחד ב-Windows
    // שבו קבצים פתוחים אינם ניתנים למחיקה).
    try {
      await dispose();
    } catch (e) {
      debugPrint('⚠️ Engine dispose during clear failed: $e');
    }

    // מחיקת תיקיית האינדקס הפעילה + כל ברירות המחדל הישנות. בלי זה,
    // אם נשארת תיקייה ב-APPDATA למשל, getIndexPath בהפעלה הבאה היה
    // ממשיך לבחור בה במקום בנתיב החדש ליד הספרייה.
    await _deleteAllKnownIndexDirectories();

    // פתיחה מחדש: getIndexPath יחזיר עכשיו את ברירת המחדל הנוכחית
    // (ליד הספרייה, אם אין הגדרה ידנית ב-keyIndexPath). ההמתנה מבטיחה
    // שתאימות האינדקס ורשימת הספרים נקראו מחדש לפני שממשיכים.
    engine = _initAll();
    await engine;
  }

  Future<void> _deleteAllKnownIndexDirectories() async {
    final paths = <String>{};
    try {
      paths.add(await AppPaths.getIndexPath());
    } catch (e) {
      debugPrint('⚠️ Failed to resolve active index path: $e');
    }
    try {
      paths.addAll(await AppPaths.getStaleDefaultIndexPaths());
    } catch (e) {
      debugPrint('⚠️ Failed to resolve stale index paths: $e');
    }

    for (final path in paths) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      try {
        dir.deleteSync(recursive: true);
        debugPrint('🧹 נמחקה תיקיית אינדקס: $path');
      } catch (e) {
        debugPrint('⚠️ כשל במחיקת תיקיית אינדקס $path: $e');
      }
    }
  }

  /// Dispose of resources and close engines
  Future<void> dispose() async {
    try {
      final index = await engine;
      index.dispose();
    } catch (e) {
      debugPrint('⚠️ Error disposing search engine: $e');
    }
  }
}

/// שער לפתיחות-מחדש של המנוע: מונע פתיחות מקבילות (קונפליקט נעילות),
/// אוכף מרווח מינימלי בין פתיחות, ומבטיח ל-[run] עם force פתיחה שמתחילה
/// אחרי הקריאה — ולא reopen ישן שרץ במקביל וקרא מצב שקדם לכשל.
@visibleForTesting
class ReopenGate {
  Future<void>? _inFlight;
  DateTime? _lastRun;

  Future<bool> run(
    Future<void> Function() reopen, {
    bool force = false,
  }) async {
    var inFlight = _inFlight;
    if (inFlight != null && !force) {
      debugPrint('⚠️ Index reopen already in progress, awaiting it...');
      await inFlight;
      return true;
    }

    // force: ממתינים ל-reopen הרץ (בלי לרשת את כשלו) ופותחים פתיחה חדשה.
    while (inFlight != null) {
      debugPrint('⚠️ Index reopen already in progress, awaiting it...');
      try {
        await inFlight;
      } catch (e) {
        debugPrint('⚠️ Awaited in-flight reopen failed: $e');
      }
      inFlight = _inFlight;
    }

    // Prevent too frequent reopens (less than 5 seconds apart)
    if (!force &&
        _lastRun != null &&
        DateTime.now().difference(_lastRun!).inSeconds < 5) {
      debugPrint('⚠️ Index reopen too soon after last reopen, skipping...');
      return false;
    }

    _lastRun = DateTime.now();
    final current = reopen();
    final wrapped = current.whenComplete(() => _inFlight = null);
    // כשל מטופל אצל הקורא (await current) ואצל ממתינים; בלי מאזין ריק,
    // העותק שב-_inFlight היה מדווח unhandled async error כשאין ממתין.
    unawaited(wrapped.catchError((_) {}));
    _inFlight = wrapped;
    await current;
    return true;
  }
}
