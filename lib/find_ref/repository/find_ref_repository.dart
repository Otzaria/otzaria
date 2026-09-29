import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/find_ref/repository/db_commentator_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_ranking.dart';
import 'package:otzaria/find_ref/repository/find_ref_visibility.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/search/utils/foundational_book_classifier.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/ref_key.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// נזרקת כשמטמון הספרים של האיתור לא הצליח להיטען, ולכן אין במה לחפש.
/// בלעדיה חיפוש על מטמון ריק מחזיר רשימה ריקה — שאינה ניתנת להבחנה מ"הספר
/// לא קיים", והמשתמש מקבל "לא נמצא ספר" בזמן שהספרייה רק עוד לא נטענה.
class ReferenceLibraryNotReadyException implements Exception {
  const ReferenceLibraryNotReadyException();

  @override
  String toString() => 'ReferenceLibraryNotReadyException';
}

/// נזרקת כשקובץ הספרייה (seforim.db) לא קיים — מצב קבוע, לא טעינה שתסתיים.
class ReferenceLibraryMissingException implements Exception {
  const ReferenceLibraryMissingException();

  @override
  String toString() => 'ReferenceLibraryMissingException';
}

/// רשומת ספר אישי מתומצתת (user_books.db) כפי שמשמשת את חיפוש הספרים האישיים.
typedef _UserBookRecord = ({
  int id,
  String title,
  String? filePath,
  String fileType,
  double orderIndex,
  List<String> folderTitles,
});

/// ספר ממסד משני עם טוקני השם המנורמלים — מחושבים פעם אחת בטעינה, לא בכל
/// הקלדה. [folderNameTokens] [i] = סיומת שרשרת התיקיות מ-i ואחריה הכותרת.
class _SecondaryBook {
  _SecondaryBook(this.record)
    : titleTokens = _nameTokens(record.title),
      folderNameTokens = [
        for (var i = 0; i < record.folderTitles.length; i++)
          _nameTokens(
            '${record.folderTitles.sublist(i).join(' ')} ${record.title}',
          ),
      ];

  final _UserBookRecord record;
  final List<String> titleTokens;
  final List<List<String>> folderNameTokens;

  static List<String> _nameTokens(String name) {
    FindRefRepository.debugSecondaryNameNormalizations++;
    return normalizeForFindRefMatch(
      name,
    ).split(' ').where((t) => t.isNotEmpty).toList(growable: false);
  }
}

final Object _searchGenerationZoneKey = Object();

final RegExp _rangeDash = RegExp('[-–־]');
final RegExp _whitespaceRun = RegExp(r'\s+');

class FindRefRepository {
  int _searchGeneration = 0;
  final int _secondaryScope = AttachedFindRefWorker.allocateSearchScope();
  bool _disposed = false;
  final bool respectHiddenLibrary;
  HiddenLibrarySelection? _visibilitySelection;
  Library? _visibilityLibrary;
  FindRefVisibility? _visibility;

  Future<FindRefVisibility> _currentVisibility() async {
    if (!respectHiddenLibrary) return FindRefVisibility.empty();
    // פעם אחת לשאילתה: הקריאה מפענחת JSON מההגדרות.
    final selection = const HiddenLibraryStore().load();
    if (selection.isEmpty) {
      if (_visibilitySelection == selection && _visibility != null) {
        return _visibility!;
      }
      if (_visibilitySelection != selection) _commentatorsCache.clear();
      _visibilitySelection = selection;
      _visibilityLibrary = null;
      _visibility = FindRefVisibility.empty();
      return _visibility!;
    }
    final library = await _awaitCurrent(
      (dataRepository ?? DataRepository.instance).library,
    );
    if (selection == _visibilitySelection &&
        identical(library, _visibilityLibrary) &&
        _visibility != null) {
      return _visibility!;
    }
    _commentatorsCache.clear();
    _visibilitySelection = selection;
    _visibilityLibrary = library;
    return _visibility = FindRefVisibility(selection, library);
  }

  /// Invalidates an in-flight search before the debounce starts. Worker work
  /// already running may finish, but its continuation must not submit more.
  void cancelPendingSearch() {
    if (_disposed) return;
    _searchGeneration++;
    beginSearchEpoch?.call();
    AttachedFindRefWorker.instance.cancelSearchScope(
      _secondaryScope,
      _searchGeneration,
    );
  }

  /// The immutable generation captured by the current findRefs invocation.
  int get currentSearchGeneration =>
      Zone.current[_searchGenerationZoneKey] as int? ?? _searchGeneration;

  int get activeSearchGeneration => _searchGeneration;

  void throwIfSearchCancelled() {
    if (_disposed || currentSearchGeneration != _searchGeneration) {
      throw const FindRefQueryCancelled();
    }
  }

  void throwIfSearchGenerationCancelled(int generation) {
    if (_disposed || generation != _searchGeneration) {
      throw const FindRefQueryCancelled();
    }
  }

  Future<T> _awaitCurrent<T>(Future<T> future) async {
    final value = await future;
    throwIfSearchCancelled();
    return value;
  }

  /// שמור לצורך תאימות לאחור עם call-sites קיימים.
  /// אינו בשימוש בפועל בקוד ה-repository.
  final DataRepository? dataRepository;

  final Future<void> Function()? warmUpReferenceBooksCache;
  final bool Function()? isReferenceBooksCacheLoaded;
  final Future<bool> Function()? libraryDatabaseExists;
  final List<ReferenceBookHit> Function(String query, {int limit})?
  searchReferenceBooks;
  final Future<List<Map<String, dynamic>>> Function(
    int bookId,
    String bookTitle, {
    List<String>? queryTokens,
  })?
  getTocEntriesForReference;

  final Future<List<Map<String, dynamic>>> Function(
    int bookId,
    String bookTitle, {
    List<String>? queryTokens,
  })?
  getAltTocEntriesForReference;

  /// תוכן העניינים וה-AltToc של כל הספרים המועמדים בבקשה אחת. In production:
  /// [FindRefDbIsolate.getTocForBooks]; בלעדיו — קריאה לכל ספר דרך השניים שלמעלה.
  final Future<List<TocBatchResult>> Function(List<TocBatchRequest> books)?
  getTocForBooks;

  /// Injection for testing: returns the global flat list of AltToc entries
  /// across all books, as raw rows. In production this calls
  /// [SeforimRepository.getAllAltTocFlatEntries].
  ///
  /// כל row כולל את המפתחות: `bookId`, `bookTitle`, `bookOrderIndex`,
  /// `reference` (נתיב מלא יחסי לספר), `segment`, `level`, `dbLineId`.
  final Future<List<Map<String, dynamic>>> Function()? getAllAltTocFlatEntries;

  /// מסלול הייצור של ה-fallback הגלובלי: סינון קאש ה-AltToc השטוח בתוך
  /// ה-worker isolate, שמחזיר רק את ההתאמות. כשהוא `null` (בדיקות / אין
  /// isolate) — נופלים למסלול המקומי דרך [getAllAltTocFlatEntries].
  /// [occupied] — התוצאות שכבר נאספו, כדי שהצמצום ב-worker יראה את הכפילויות.
  final Future<List<Map<String, dynamic>>> Function(
    List<String> queryTokens, {
    int? maxRefTokens,
    List<AltTocResultKey> occupied,
  })?
  searchAltTocFlatEntries;

  /// בנייה מוקדמת של קאש ה-AltToc בתוך ה-worker (ראה
  /// [FindRefDbIsolate.prewarmAltTocFlat]); נקרא ברקע בפתיחת הדיאלוג.
  final Future<void> Function()? prewarmAltTocFlatEntries;

  /// מזהי הספרים בעלי מבנה AltToc — מאפשר לדלג על שאילתת AltToc פר-ספר
  /// עבור ~95% מהספרים. כשהוא `null` — אין דילוג (התנהגות קודמת).
  final Future<List<int>?> Function()? getAltStructureBookIds;

  /// Injection for testing: returns the category path string for a given bookId.
  /// In production this calls [ReferenceBooksCache.instance.getCategoryPathForBook].
  final Future<String> Function(int bookId)? getCategoryPath;

  /// Injection for testing: returns outline entries for a FS PDF file.
  /// In production this calls [ReferenceBooksCache.instance.getPdfOutlineEntries].
  final Future<List<(String, String, int)>> Function(String filePath)?
  getPdfOutlineEntries;

  /// Injection for testing: returns all books from the user personal books DB.
  /// Each record: (id, title, filePath, fileType, orderIndex).
  /// In production calls [UserBooksDatabaseHolder.instance.repository].
  final Future<
    List<
      ({
        int id,
        String title,
        String? filePath,
        String fileType,
        double orderIndex,
        List<String> folderTitles,
      })
    >
  >
  Function()?
  getAllUserBooks;

  /// Injection for testing: returns TOC entries from the user personal books DB.
  /// In production calls [UserBooksDatabaseHolder.instance.repository].
  final Future<List<Map<String, dynamic>>> Function(
    int bookId,
    String bookTitle, {
    List<String>? queryTokens,
  })?
  getUserBookTocEntries;

  /// Injection for testing: המאגר של user_books.db; בייצור — ה-holder.
  final Future<SeforimRepository> Function()? openUserBooksRepository;

  /// Injection for testing: מחזיר את שורות המפרשים הגולמיות עבור תוצאה.
  /// In production calls [SeforimRepository.getCommentatorsForReference].
  ///
  /// כל row צפוי לכלול לפחות `targetBookTitle` ו-`targetLineIndex` (השורה
  /// הראשונה בספר המפרש על פני טווח הקטע). חישוב הטווח (כותרת עד הכותרת
  /// הבאה / כל הספר כשאין כותרות פנימיות) מתבצע ב-repository ה-DB.
  final Future<List<Map<String, dynamic>>> Function(DbReferenceResult ref)?
  fetchCommentatorRows;

  /// Injection for testing: פותר מפתח הפניה קנוני מול אינדקס `line_ref`
  /// עבור כל הספרים המועמדים בשאילתה מאוגדת אחת (מפתח התוצאה = bookId).
  /// In production calls [FindRefDbIsolate.resolveLineRefs]; כשהאינדקס חסר
  /// במסד ישן מוחזר map ריק והתוצאה נשארת ברמת ה-TOC.
  final Future<Map<int, ({int lineIndex, int lineId, String? heRef})>> Function(
    List<int> bookIds,
    String refKey,
  )?
  resolveLineRefs;

  /// Injection for testing: פותר מפתח חלקי ([buildPartialRefKey]) — הפניה
  /// שהושמט ממנה שם החלק ("טור שט ג"). מחזיר מועמד לכל חלק שבו היא קיימת;
  /// מסד שנבנה לפני המפתחות החלקיים מחזיר map ריק.
  final Future<Map<int, List<({int lineIndex, int lineId, String? heRef})>>>
  Function(List<int> bookIds, String partialKey)?
  resolvePartialLineRefs;

  /// Injection for testing: מחזיר את דיבורי-המתחיל (`line_dh`) שתחילתם
  /// [prefix] בספרים המועמדים. In production calls
  /// [FindRefDbIsolate.resolveDibburim]; מסד בלי הטבלה מחזיר רשימה ריקה.
  final Future<List<Map<String, dynamic>>> Function(
    List<int> bookIds,
    String prefix, {
    List<int> containsBookIds,
  })?
  resolveDibburim;

  /// סדר הדור של ספר רשמי מקאש בזיכרון, או null כשהקאש לא נטען.
  /// In production: [GenerationCache].
  final int? Function(int bookId)? cachedEraOrder;

  /// דורות המפרשים שאין להם דור בקאש, לפי שם — בבקשה אחת.
  /// In production: [FindRefDbIsolate.getBookEras].
  final Future<List<CommentaryEra>> Function(List<String> bookTitles)?
  getBookEras;

  /// Injection for testing: גרסה סינכרונית של [getCategoryPath], משמשת את
  /// `_rankResults` כדי לסווג "ספר יסוד" מול "מפרש" לפי הנתיב המלא של
  /// קטגוריית הספר. In production: [ReferenceBooksCache.instance.getCategoryPathForBookSync].
  final String? Function(int bookId)? getCategoryPathSync;

  /// פותח מחזור שאילתה חדש ומורה ל-worker לזרוק את הבקשות הממתינות של
  /// המחזור הקודם. In production: [FindRefDbIsolate.cancelSearchScopeIfRunning].
  final void Function()? beginSearchEpoch;
  final void Function()? releaseSearchScope;

  /// Injection for testing: חיפוש מצב "דור + נושא". In production:
  /// [ReferenceBooksCache.instance.searchByEraAndTopic].
  final List<ReferenceBookHit> Function(
    CommentaryEra era,
    List<String> topicTokens, {
    int limit,
  })?
  searchByEraAndTopic;

  /// קאש בזיכרון. המפתח כולל את כל הפרמטרים שמשפיעים על תוצאת ה-loader
  /// (`bookId`, `sourceLineId`, `isAltToc`, `tocLevel`, `segment`) — לא מספיק
  /// `bookId:sourceLineId` בלבד: TOC רגיל ו-AltToc יכולים לחלוק את אותה שורת
  /// התחלה (למשל "בראשית פרק א" ו"פרשת בראשית" — שניהם בשורה הראשונה), אך
  /// הטווח המחושב להם שונה. חי כל זמן שה-repository חי; קטן יחסית בפועל.
  final Map<String, List<DbCommentatorEntry>> _commentatorsCache = {};

  /// חיתוך בסיס של רשימת התוצאות. מורחב ע"י [_rankResults] לכל מי שחולק את
  /// מפתח-הרלוונטיות של התוצאה ה-20, כך שתוצאות שווֹת-רלוונטיות לא נחתכות
  /// באמצע (ראה גם [_maxResultCap]).
  static const int _baseResultCap = 20;

  /// תקרת-ביטחון מוחלטת על מספר התוצאות — רשת מפני קבוצת-רלוונטיות פתולוגית
  /// (למשל נושא רחב במצב era). הסט הלגיטימי הגדול בפועל קטן בהרבה.
  static const int _maxResultCap = findRefMaxResultCap;

  /// תקרת הספרים שבהם מחפשים דיבור-מתחיל. שאילתה אחת מאוגדת, מוגשת
  /// מהאינדקס — התקרה היא רשת ביטחון מול טוקן-ספר רחב שתפס מאות ספרים.
  static const int _maxDibburBooks = 50;

  /// מסלול "מכיל" סורק את שורות הספר ולכן מוגבל לראש הרשימה בלבד.
  static const int _maxDibburContainsBooks = 10;

  /// issue #839: מכסת התאמות תת-מחרוזת המובטחת בזנב תוצאות של שאילתת
  /// מילה-אחת — בלעדיה ה-cap מחק אותן כליל ("מא" לא הציג את יומא).
  static const int _substringTailQuota = 10;

  /// מילות-דור של טוקן יחיד שמפעילות את מצב "דור + נושא".
  static const Map<String, CommentaryEra> _singleTokenEras = {
    'ראשונים': CommentaryEra.rishonim,
    'אחרונים': CommentaryEra.acharonim,
  };

  /// מפתח קאש לרשומות מפרשים — ראה [_commentatorsCache].
  static String _cacheKeyFor(DbReferenceResult ref) =>
      '${ref.bookId}:${ref.sourceLineId}:${ref.isAltToc ? 1 : 0}'
      ':${ref.tocLevel}:${ref.segment.toInt()}';

  /// קאש שטוח של כל ערכי ה-AltToc על פני כל הספרים. נבנה lazy בקריאה
  /// הראשונה ל-fallback הגלובלי, ומשרת את כל ה-sessions שלאחר מכן.
  /// השדה נשמר ברמת ה-instance של [FindRefRepository] (singleton באפליקציה).
  List<AltTocFlatEntry>? _altTocFlatCache;

  /// קאש מזהי הספרים בעלי מבנה AltToc (ראה [getAltStructureBookIds]).
  Set<int>? _altBookIdsCache;

  /// הספרים האישיים (user_books.db), עד [clearCaches] — שמתבצע במסלולי
  /// הרענון, גם אחרי שינוי בספרים האישיים.
  List<_SecondaryBook>? _userBooksCache;

  /// נתיב user_books.db, לשאילתות ה-TOC ב-worker; נקבע בטעינת הרשימה.
  String? _userBooksDbPath;

  /// גרסת החיבור של ה-worker ל-user_books.db — מתחלפת בכל [clearCaches].
  int _userBooksVersion = 0;

  /// קאש ספרי המסדים המצורפים לפי slug, עם רשומת המסד שממנה נבנה.
  final Map<String, ({AttachedLibrary library, List<_SecondaryBook> books})>
  _attachedBooksCache = {};

  /// בדיקות בלבד: כמה שמות של ספרים משניים נורמלו (ראו [_SecondaryBook]).
  @visibleForTesting
  static int debugSecondaryNameNormalizations = 0;

  FindRefRepository({
    this.dataRepository,
    this.respectHiddenLibrary = false,
    this.warmUpReferenceBooksCache,
    this.isReferenceBooksCacheLoaded,
    this.libraryDatabaseExists,
    this.searchReferenceBooks,
    this.getTocEntriesForReference,
    this.getAltTocEntriesForReference,
    this.getTocForBooks,
    this.getAllAltTocFlatEntries,
    this.searchAltTocFlatEntries,
    this.prewarmAltTocFlatEntries,
    this.getAltStructureBookIds,
    this.getCategoryPath,
    this.getPdfOutlineEntries,
    this.getAllUserBooks,
    this.getUserBookTocEntries,
    this.openUserBooksRepository,
    this.fetchCommentatorRows,
    this.resolveLineRefs,
    this.resolvePartialLineRefs,
    this.resolveDibburim,
    this.cachedEraOrder,
    this.getBookEras,
    this.getCategoryPathSync,
    this.beginSearchEpoch,
    this.releaseSearchScope,
    this.searchByEraAndTopic,
  }) {
    _liveInstances.add(this);
  }

  /// כל ה-instances הפעילים — כדי שמסלולי refresh/reset של הספרייה יוכלו
  /// לאפס את ה-caches שלהם בלי תלות ב-singleton או ב-context. ה-repository
  /// נוצר ב-BlocProvider, ולכן אין נקודה גלובלית אחת לפנות אליה.
  static final Set<FindRefRepository> _liveInstances = <FindRefRepository>{};

  /// מאפס את ה-caches הפנימיים של כל ה-instances הקיימים. נקרא ממסלולי
  /// refresh הספרייה (navigation_repository) ואיפוס runtime (app_runtime_reset).
  static void clearAllCaches() {
    for (final repo in _liveInstances) {
      repo.clearCaches();
    }
    // ה-isolate של איתור מקורות מחזיק חיבור RO וקאש TOC משלו — מאפסים אותם
    // כדי שלא ידלפו נתונים מספרייה ישנה אחרי רענון/החלפה. fire-and-forget.
    FindRefDbIsolate.resetIfRunning();
  }

  /// מסיר את ה-instance מרשימת ה-repositories הפעילים.
  void dispose() {
    if (_disposed) return;
    cancelPendingSearch();
    _disposed = true;
    releaseSearchScope?.call();
    AttachedFindRefWorker.instance.releaseSearchScope(_secondaryScope);
    _liveInstances.remove(this);
  }

  /// בדיקות בלבד: שם תאימות למחיקת הרישום.
  @visibleForTesting
  void disposeForTesting() => dispose();

  @visibleForTesting
  static int get debugLiveInstanceCount => _liveInstances.length;

  /// מנקה את ה-caches הפנימיים של ה-repository (מפרשים ו-AltToc שטוח).
  ///
  /// יש לקרוא לזה במסלולי refresh של הספרייה / איפוס runtime, כדי שתוצאות
  /// מספרייה ישנה לא ידלפו לחיפוש שאחרי הרענון. ה-repository עצמו חי לכל
  /// אורך חיי האפליקציה (singleton ב-main), ולכן בלי ניקוי יזום הקאש ישרוד
  /// עד restart מלא.
  void clearCaches() {
    _commentatorsCache.clear();
    _altTocFlatCache = null;
    _altBookIdsCache = null;
    _userBooksCache = null;
    _userBooksDbPath = null;
    _userBooksVersion++;
    _attachedBooksCache.clear();
    _visibility = null;
    _visibilityLibrary = null;
    _visibilitySelection = null;
  }

  /// חימום מוקדם (best-effort) של קאש ה-AltToc הגלובלי, כדי שהחיפוש הראשון
  /// שנופל ל-fallback לא ישלם את מחיר הבנייה. נקרא ברקע בפתיחת הדיאלוג.
  Future<void> prewarmGlobalAltToc() async {
    try {
      final fn = prewarmAltTocFlatEntries;
      if (fn != null) {
        await fn();
      } else if (searchAltTocFlatEntries == null) {
        await _getAltTocFlatCache();
      }
    } catch (e) {
      debugPrint('[FindRef] AltToc prewarm failed: $e');
    }
  }

  /// מזהי הספרים בעלי AltToc, מהקאש; `null` = אין מידע (אין לדלג על כלום).
  Future<Set<int>?> _getAltBookIds() async {
    final fn = getAltStructureBookIds;
    if (fn == null) return null;
    final cached = _altBookIdsCache;
    if (cached != null) return cached;
    try {
      final ids = await fn();
      if (ids == null) return null;
      return _altBookIdsCache = ids.toSet();
    } on FindRefQueryCancelled {
      rethrow;
    } catch (e) {
      debugPrint('[FindRef] alt book ids fetch failed: $e');
      return null;
    }
  }

  /// רשימת הספרים האישיים, נטענת פעם אחת עד [clearCaches] — דרך
  /// [getAllUserBooks] (בדיקות) או מ-`user_books.db`.
  Future<List<_SecondaryBook>> _loadUserBooks() async {
    final cached = _userBooksCache;
    if (cached != null) return cached;

    final List<_SecondaryBook> list;
    final injected = getAllUserBooks;
    if (injected != null) {
      list = [
        for (final record in await _awaitCurrent(injected()))
          _SecondaryBook(record),
      ];
    } else {
      // הפתיחה דרך ה-holder מריצה את המיגרציות לפני שה-worker קורא מהקובץ.
      final userRepo = await _awaitCurrent(
        openUserBooksRepository?.call() ??
            UserBooksDatabaseHolder.instance.repository,
      );
      list = await _awaitCurrent(_readSecondaryBooksFrom(userRepo));
      _userBooksDbPath = userRepo.database.path;
    }
    _userBooksCache = list;
    return list;
  }

  /// מחזיר את הקאש הגלובלי של AltToc; טוען אותו פעם אחת בקריאה הראשונה
  /// ושומר ב-[_altTocFlatCache]. כל קריאה לאחר מכן היא in-memory.
  ///
  /// הקריאה הזו אמורה להיות בטוחה לכשלון: אם השאילתה נופלת או שערך כלשהו
  /// אינו במבנה הצפוי — מוחזר רשימה ריקה (ולא מתפשטת חריגה). כך מסלול
  /// ה-per-book בתוך `findRefs` מתמיד גם אם ה-AltToc הגלובלי תקול.
  Future<List<AltTocFlatEntry>> _getAltTocFlatCache() async {
    final cached = _altTocFlatCache;
    if (cached != null) return cached;

    try {
      final fn = getAllAltTocFlatEntries;
      final rows = fn != null
          ? await fn()
          : (await SqliteDataProvider.instance.repository
                    ?.getAllAltTocFlatEntries() ??
                const <Map<String, dynamic>>[]);

      final list = <AltTocFlatEntry>[];
      for (final r in rows) {
        final reference = r['reference'] as String;
        final refTokens = _tokenize(_normalizeForMatch(reference));
        list.add(
          AltTocFlatEntry(
            bookId: r['bookId'] as int,
            bookTitle: r['bookTitle'] as String,
            // `book.orderIndex` הוא INTEGER NOT NULL בסכמה, אבל לא רוצים לסכן
            // ב-cast קשיח אם בעתיד יוסיפו ספרים בלי orderIndex.
            bookOrderIndex: (r['bookOrderIndex'] as num?)?.toDouble() ?? 999.0,
            reference: reference,
            segment: r['segment'] as int? ?? 0,
            level: r['level'] as int? ?? 0,
            dbLineId: r['dbLineId'] as int? ?? 0,
            refTokens: refTokens,
          ),
        );
      }
      _altTocFlatCache = list;
      return list;
    } on FindRefQueryCancelled {
      rethrow;
    } catch (e, st) {
      debugPrint('[FindRef] AltToc flat cache build failed: $e\n$st');
      // אל **תקבע** את הקאש לריק במקרה כשל — אם הסיבה הייתה זמנית
      // (rebuild של DB, lock רגעי), שאילתה הבאה תקבל ניסיון חוזר.
      // אם הכשל קבוע, ההשהיה ב-await יחזור ולא מקסים נזק.
      return const [];
    }
  }

  /// מוסיף ל-[results] ערכי AltToc מהקאש הגלובלי שכל טוקני השאילתה מופיעים
  /// בהם. [maxRefTokens] מגביל את אורך הערך — במילה אחת רק כותרות קצרות
  /// ("נח", "פרשת נח") נכללות, כדי לא להציף בצאצאים ("נח עליה ב").
  Future<void> _addGlobalAltTocMatches(
    List<DbReferenceResult> results,
    List<String> queryTokens, {
    int? maxRefTokens,
    FindRefVisibility? visibility,
  }) async {
    try {
      // מסלול הייצור: הסינון רץ ב-worker ומחזיר רק התאמות — הקאש כולו
      // והנרמול שלו לא חוצים את גבול ה-isolate.
      final occupied = [
        for (final r in results)
          if (r.source.isOfficial && !r.isPdf && r.bookId > 0)
            (
              bookId: r.bookId,
              title: r.title,
              segment: r.segment,
              reference: r.reference,
            ),
      ];
      final searchFn = searchAltTocFlatEntries;
      if (searchFn != null) {
        final rows = await searchFn(
          queryTokens,
          maxRefTokens: maxRefTokens,
          occupied: occupied,
        );
        for (final r in rows) {
          if (visibility != null &&
              !visibility.allowsCandidate(
                BookSource.official,
                r['bookId'] as int,
                '',
              )) {
            continue;
          }
          final bookTitle = r['bookTitle'] as String;
          results.add(
            DbReferenceResult(
              title: bookTitle,
              reference: qualifyAltTocReference(
                bookTitle,
                r['reference'] as String,
              ),
              segment: r['segment'] as int? ?? 0,
              orderIndex: (r['bookOrderIndex'] as num?)?.toDouble() ?? 999.0,
              tocLevel: r['level'] as int? ?? 0,
              isAltToc: true,
              bookId: r['bookId'] as int,
              sourceLineId: r['dbLineId'] as int? ?? 0,
            ),
          );
        }
        return;
      }

      final flat = await _getAltTocFlatCache();
      // כל טוקני השאילתה בנתיב הערך — אחרת "הפטרת נח" תואם את "נח עליה ב".
      final matches = [
        for (final entry in flat)
          if ((visibility == null ||
                  visibility.allowsCandidate(
                    BookSource.official,
                    entry.bookId,
                    '',
                  )) &&
              altTocFlatMatches(
                entry.refTokens,
                queryTokens,
                maxRefTokens: maxRefTokens,
              ))
            entry,
      ];
      final pruned = pruneGlobalAltTocMatches(
        matches,
        keyOf: (e) => (
          bookId: e.bookId,
          title: e.bookTitle,
          segment: e.segment,
          reference: qualifyAltTocReference(e.bookTitle, e.reference),
        ),
        queryTokens: queryTokens,
        suppressDescendants: maxRefTokens == null,
        occupied: occupied,
      );
      for (final entry in pruned) {
        results.add(
          DbReferenceResult(
            title: entry.bookTitle,
            reference: qualifyAltTocReference(
              entry.bookTitle,
              entry.reference,
            ),
            segment: entry.segment,
            orderIndex: entry.bookOrderIndex,
            tocLevel: entry.level,
            isAltToc: true,
            bookId: entry.bookId,
            sourceLineId: entry.dbLineId,
          ),
        );
      }
    } on FindRefQueryCancelled {
      rethrow; // הקלדה חדשה — התוצאה החלקית הזו כבר לא רלוונטית.
    } catch (e, st) {
      debugPrint('[FindRef] Global AltToc fallback failed: $e\n$st');
    }
  }

  /// מחזיר רשימת רשומות מפרשים זמינים עבור תוצאה, מוכנות לפתיחה ישירה.
  ///
  /// כל [DbCommentatorEntry.targetSegment] הוא `MIN(targetLineIndex)` על פני
  /// טווח הקטע — המיקום הראשון בספר המפרש על אותו קטע — או `null` אם ה-row
  /// אינו כולל `targetLineIndex`.
  ///
  /// המתודה רק מנקה כפילויות וממיינת לפי דורות; **חישוב טווח הקטע** (כותרת עד
  /// הכותרת הבאה, או כל הספר כשאין כותרות פנימיות) מתבצע ב-[fetchCommentatorRows]
  /// (בייצור: [SeforimRepository.getCommentatorsForReference]).
  ///
  /// PDFs / ספרים מחוץ ל-DB (bookId <= 0) / ספרים שאינם רשמיים — ריק מיידית:
  /// ה-bookId/sourceLineId שלהם שייכים למסד אחר ולא מתאימים ל-link table של
  /// ה-DB הראשי — שאילתה תחזיר מפרשים שגויים.
  ///
  /// תוצאות נשמרות בקאש בזיכרון לאורך חיי ה-repository.
  Future<List<DbCommentatorEntry>> getCommentatorsForResult(
    DbReferenceResult ref,
  ) async {
    if (ref.isPdf || ref.bookId <= 0 || !ref.source.isOfficial) return const [];

    final cacheKey = _cacheKeyFor(ref);
    await _currentVisibility();
    final cached = _commentatorsCache[cacheKey];
    if (cached != null) return cached;

    final repository = SqliteDataProvider.instance.repository;
    final fetchFn =
        fetchCommentatorRows ??
        (repository == null
            ? null
            : (DbReferenceResult r) => repository.getCommentatorsForReference(
                bookId: r.bookId,
                bookTitle: r.title,
                sourceLineId: r.sourceLineId,
                startLineIndex: r.segment.toInt(),
                level: r.tocLevel,
                isAltToc: r.isAltToc,
                isSourceLine: r.isSourceLine,
              ));

    if (fetchFn == null) return const [];

    final rows = await fetchFn(ref);
    final currentVisibility = await _currentVisibility();

    // dedupe על `(title, bookId)` ולא רק `title`: שני מפרשים שונים יכולים
    // לחלוק אותה כותרת ולהיבדל ב-`targetBookId` (למשל "רש"י" שיש לו
    // book records נפרדים על תורה ועל גמרא). dedupe לפי title בלבד היה מוחק
    // אחד מהם ומבטל את הנתון שבזכותו הצרכן יודע לאיזה ספר ללכת.
    //
    // עבור rows ישנים שאין להם `targetBookId` (תאימות לאחור), המפתח (title, null)
    // יחיד — כך שכפילויות אמיתיות עם אותו ספר חסר-id עדיין מסוננות.
    final entries = <({String title, int? bookId, int? segment})>[];
    final seen = <(String, int?)>{};
    for (final row in rows) {
      final title = row['targetBookTitle'] as String?;
      if (title == null || title.isEmpty) continue;
      final int? bookId = row['targetBookId'] as int?;
      if (!currentVisibility.allowsCommentator(title, bookId)) continue;
      if (!seen.add((title, bookId))) continue;

      // `targetLineIndex` — המיקום המקביל הראשון בספר המפרש על פני הקטע.
      final int? segment = row['targetLineIndex'] as int?;
      entries.add((title: title, bookId: bookId, segment: segment));
    }

    if (entries.isEmpty) {
      _commentatorsCache[cacheKey] = const [];
      return const [];
    }

    // מיון לפי סדר הדורות (תורה → חז"ל → ראשונים → אחרונים → מודרני → שאר),
    // ובתוך כל דור — אלפביתי. תואם להתנהגות תפריט המפרשים ב-text-book viewer.
    final eraOrders = await _eraOrdersFor(entries);
    final indices = List<int>.generate(entries.length, (i) => i)
      ..sort((a, b) {
        final ea = eraOrders[a];
        final eb = eraOrders[b];
        if (ea != eb) return ea.compareTo(eb);
        return entries[a].title.compareTo(entries[b].title);
      });
    final sorted = [
      for (final i in indices)
        DbCommentatorEntry(
          title: entries[i].title,
          bookId: entries[i].bookId,
          targetSegment: entries[i].segment,
        ),
    ];

    if (respectHiddenLibrary &&
        currentVisibility.selection != const HiddenLibraryStore().load()) {
      return const [];
    }
    _commentatorsCache[cacheKey] = sorted;
    return sorted;
  }

  /// הקאש מכריע לכל מפרש עם מזהה; השאר נפתרים לפי שם בבקשה מאוגדת אחת.
  Future<List<int>> _eraOrdersFor(
    List<({String title, int? bookId, int? segment})> entries,
  ) async {
    final orders = [
      for (final e in entries)
        e.bookId == null ? null : cachedEraOrder?.call(e.bookId!),
    ];
    final missing = [
      for (var i = 0; i < entries.length; i++)
        if (orders[i] == null) i,
    ];
    if (missing.isNotEmpty) {
      final titles = [for (final i in missing) entries[i].title];
      final eras =
          await (getBookEras?.call(titles) ??
              Future.wait(titles.map(CommentaryService.getBookEra)));
      for (var k = 0; k < missing.length; k++) {
        orders[missing[k]] = eras[k].order;
      }
    }
    return [for (final order in orders) order!];
  }

  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) {
    if (_disposed) return Future.error(const FindRefQueryCancelled());
    cancelPendingSearch();
    final generation = _searchGeneration;
    return runZoned(
      () => _findRefs(ref, includePersonalBooks: includePersonalBooks),
      zoneValues: {_searchGenerationZoneKey: generation},
    );
  }

  /// "אין ספרייה" מול "עוד לא עלתה": רשימה ריקה הייתה מוצגת כ"לא נמצא ספר",
  /// וקובץ חסר שמדווח כ"לא מוכן" משאיר את המשתמש בהמתנה לנצח.
  Future<Never> _throwLibraryUnavailable() async {
    final dbExists = await _awaitCurrent(
      libraryDatabaseExists?.call() ??
          File(DatabaseConstants.getDatabasePath()).exists(),
    );
    if (!dbExists) throw const ReferenceLibraryMissingException();
    throw const ReferenceLibraryNotReadyException();
  }

  Future<List<DbReferenceResult>> _findRefs(
    String rawRef, {
    bool includePersonalBooks = false,
  }) async {
    // לפני הנרמול: הוא מוחק את הגרשיים, ו"ע"א" נהפך למספר הדף "עא".
    final ref = expandQueryAmudMarks(rawRef);
    final cleanedQuery = _normalizeForMatch(ref);
    if (cleanedQuery.isEmpty) {
      return const [];
    }

    var queryTokens = _tokenize(cleanedQuery);
    if (queryTokens.isEmpty) {
      return const [];
    }

    // "תוספות ברכות ד"ה מאימתי": הזנב שאחרי הסמן נפתר מול `line_dh`, והראש
    // ממשיך במסלול הרגיל — כאילו הוקלד שם הספר לבדו.
    final dibburQuery = _detectDibburQuery(queryTokens);
    if (dibburQuery != null) queryTokens = dibburQuery.headTokens;

    final SeforimRepository? repository =
        SqliteDataProvider.instance.repository;
    if (repository == null && getTocEntriesForReference == null) {
      debugPrint('[FindRef] Database not initialized');
      await _throwLibraryUnavailable();
    }

    Future<List<Map<String, dynamic>>> fetchTocEntries(
      int bookId,
      String bookTitle, {
      List<String>? queryTokens,
    }) {
      final injected = getTocEntriesForReference;
      if (injected != null) {
        return injected(bookId, bookTitle, queryTokens: queryTokens);
      }
      return repository!.getTocEntriesForReference(
        bookId,
        bookTitle,
        queryTokens: queryTokens,
      );
    }

    Future<List<Map<String, dynamic>>> fetchAltTocEntries(
      int bookId,
      String bookTitle, {
      List<String>? queryTokens,
    }) {
      final injected = getAltTocEntriesForReference;
      if (injected != null) {
        return injected(bookId, bookTitle, queryTokens: queryTokens);
      }
      return repository?.getAltTocEntriesForReference(
            bookId,
            bookTitle,
            queryTokens: queryTokens,
          ) ??
          Future.value(const []);
    }

    Future<List<TocBatchResult>> fetchTocBatch(
      List<TocBatchRequest> books,
    ) async {
      final batch = getTocForBooks;
      if (batch != null) return batch(books);
      final out = <TocBatchResult>[];
      for (final book in books) {
        var toc = await _awaitCurrent(
          fetchTocEntries(
            book.bookId,
            book.bookTitle,
            queryTokens: book.queryTokens,
          ),
        );
        final fallback = book.fallbackTokens;
        if (toc.isEmpty && fallback != null) {
          toc = await _awaitCurrent(
            fetchTocEntries(book.bookId, book.bookTitle, queryTokens: fallback),
          );
        }
        final altTokens = book.altTocTokens;
        out.add((
          toc: toc,
          altToc: altTokens == null
              ? const <Map<String, dynamic>>[]
              : await _awaitCurrent(
                  fetchAltTocEntries(
                    book.bookId,
                    book.bookTitle,
                    queryTokens: altTokens,
                  ),
                ),
        ));
      }
      return out;
    }

    bool cacheLoaded() =>
        isReferenceBooksCacheLoaded?.call() ??
        ReferenceBooksCache.instance.isLoaded;
    if (!cacheLoaded()) {
      await _awaitCurrent(
        warmUpReferenceBooksCache?.call() ??
            ReferenceBooksCache.instance.warmUp(),
      );
      // ה-warmUp חוזר בלי לזרוק גם כשהוא נכשל (DB נעול, יציאה ממצב שינה).
      // בלי הבדיקה השנייה נחפש על מטמון ריק ונדווח "לא נמצא ספר".
      if (!cacheLoaded()) await _throwLibraryUnavailable();
    }

    final visibility = await _currentVisibility();

    // מצב "דור + נושא": "ראשונים סנהדרין" / "סנהדרין ראשונים" → כל הראשונים על
    // סנהדרין. מזוהה בכל מיקום בשאילתה. אם הוא לא מחזיר תוצאות — נופלים למסלול
    // הרגיל כדי שהשאילתה תמיד תעשה משהו סביר.
    final eraQuery = _detectEraQuery(queryTokens);
    if (eraQuery != null) {
      final eraResults = await _awaitCurrent(
        _findByEra(eraQuery.era, eraQuery.topicTokens, visibility),
      );
      if (eraResults.isNotEmpty) return eraResults;
    }

    // Prefer matching the longest leading phrase (up to 3 tokens) as the book key.
    // This supports multi-word acronyms like "שוע אוח".
    final maxPhraseTokens = queryTokens.length >= 3 ? 3 : queryTokens.length;

    // גבוה בכוונה: ה-hits מסוננים אחרי החיפוש לפי שאר הטוקנים, וחיתוך מוקדם
    // זרק ספרים רלוונטיים. מילה אחת: 200, אחרת "מא" לא מחזיר את יומא (#839).
    final bookSearchLimit = queryTokens.length >= 2 ? 1000 : 200;
    final allowsOfficial = visibility.selection.isEmpty
        ? null
        : (int id, String path, String type) => visibility.allowsCandidate(
            BookSource.official,
            id,
            path,
            fileType: type,
          );

    // שם הספר בכל אורך, והשאלה אם הטוקן שאחריו הוא כותרת של ספר, נענים
    // מסריקה אחת של הקטלוג במקום סריקה לכל קריאה.
    ReferenceBookSearchBatch? batch;
    ReferenceBookSearchBatch officialBatch() =>
        batch ??= ReferenceBooksCache.instance.searchBatch(
          [
            for (var n = maxPhraseTokens; n >= 1; n--)
              queryTokens.take(n).join(' '),
          ],
          limit: bookSearchLimit,
          allowsBook: allowsOfficial,
          exactTitles: {
            for (var i = 1; i <= maxPhraseTokens && i < queryTokens.length; i++)
              queryTokens[i],
          },
        );
    List<ReferenceBookHit> searchBooks(String query, {int limit = 50}) {
      final injected = searchReferenceBooks;
      if (injected != null) {
        final hits = injected(query, limit: limit);
        if (visibility.selection.isEmpty) return hits;
        return hits
            .where(
              (hit) => visibility.allowsCandidate(
                BookSource.official,
                hit.bookId,
                hit.filePath,
                fileType: hit.fileType,
              ),
            )
            .toList();
      }
      return officialBatch().hitsFor(query, limit: limit) ??
          ReferenceBooksCache.instance.search(
            query,
            limit: limit,
            allowsBook: allowsOfficial,
          );
    }

    var bookQueryTokenCount = 1;
    List<ReferenceBookHit> bookHits = const <ReferenceBookHit>[];

    // hits ב-matchRank=2 ("contains") נשמרים כצובר לכל אורך הלולאה: הם
    // לגיטימיים — פרשנויות כמו "פני יהושע על בבא קמא" כשמחפשים "בבא קמא" —
    // אבל לא ראויים "לתפוס" את ה-bookQueryTokenCount, כי הם לא התאמה ישירה
    // של תחילת הכותרת. אם אין hits ראשיים (matchRank<=1 או ==3) באף n, הם
    // עדיין יוצרפו לתוצאות אבל ה-loop ימשיך לנסות n קטן יותר כדי למצוא
    // התאמה ישירה לספר עצמו (למשל "בראשית" עבור "בראשית א").
    final secondaryHits = <ReferenceBookHit>[];

    // אורך ה-phrase שהתיר כל hit משני — הם נאספים ב-n גדול מזה שנקבע לבסוף
    // ב-bookQueryTokenCount, ובליעת ה-prefix שלהם חייבת את ה-n שלהם עצמם.
    final secondaryPhraseTokenCount = <ReferenceBookHit, int>{};

    for (var n = maxPhraseTokens; n >= 1; n--) {
      final phrase = queryTokens.take(n).join(' ');
      final hits = searchBooks(phrase, limit: bookSearchLimit);
      if (hits.isEmpty) continue;

      // For single-token queries, keep all hits as usual.
      if (n == 1) {
        bookHits = hits;
        bookQueryTokenCount = n;
        break;
      }

      // For multi-token phrases:
      //   matchRank=3 (complete acronym) — תמיד מקובל.
      //   matchRank=4 (acronym prefix) — נדחה כדי לא לבלוע טוקן-סעיף: "טור חושן"
      //     הוא prefix של ה-acronym "טור חושן משפט", וכ-book key לא היה משאיר
      //     remainingTokens לחיפוש TOC. החריג הוא
      //     [ReferenceBookHit.acronymTailIsTitleWords] — ראו למטה.
      //   matchRank=5 (acronym contains) — נדחה.
      //   matchRank=0,1,2 — מקובלים אם טוקני ה-phrase מופיעים כסיקוונס רציף
      //     ב-titleTokens (לאו דווקא בתחילת הכותרת). matchRank=2 נחשב
      //     "secondary" — מציפן בנפרד וממשיכים לחפש n קטן יותר; matchRank=0,1
      //     הם "primary" וגורמים ל-break.
      final phraseTokens = queryTokens.take(n).toList();
      final primaryHits = <ReferenceBookHit>[];

      // rank=4 שכל שאר מילות ראש-התיבות שלו הן מילות-כותרת ("רמב"ם תפילה" ⊂
      // "רמב"ם תפילה וברכת כהנים") — השאילתה מזהה את הספר במלואו, ולכן הוא
      // מצטרף ל-primary. אבל *רק* כשיש primary אחר: אסור שהצירוף עצמו יגרום
      // ל-break, שאחרת ספרים שנמצאים ב-n קטן יותר ("רש"י בראשית" → "רש"י על
      // בראשית") ייעלמו.
      final joinablePrefixHits = <ReferenceBookHit>[];

      for (final hit in hits) {
        if (hit.matchRank == 3) {
          primaryHits.add(hit);
          continue;
        }
        // התאמה מקורבת מצטרפת כמשנית בלבד, ובלי דרישת רצף-הטוקנים שהיא
        // נכשלת בה מעצם היותה מקורבת. אסור שתכריע אילו טוקנים הם שם הספר —
        // "חדושי הלכות" היה מקצץ אז את הטוקנים הלא-נכונים.
        if (hit.matchRank == ReferenceBooksCache.fuzzyMatchRank) {
          secondaryHits.add(hit);
          secondaryPhraseTokenCount[hit] = n;
          continue;
        }
        if (hit.matchRank >= 4) {
          if (hit.matchRank == 4 && hit.acronymTailIsTitleWords) {
            joinablePrefixHits.add(hit);
          }
          continue;
        }
        final titleTokens = hit.titleTokens;
        if (!_phraseAppearsAsTokens(titleTokens, phraseTokens)) continue;
        if (hit.matchRank == 2) {
          secondaryHits.add(hit);
          secondaryPhraseTokenCount[hit] = n;
        } else {
          primaryHits.add(hit);
        }
      }

      if (primaryHits.isNotEmpty) {
        bookHits = [...primaryHits, ...joinablePrefixHits];
        bookQueryTokenCount = n;
        break;
      }
    }

    // "זוהר בראשית דף לו": הצירוף הוא ראש-תיבות של מהדורה אחת ("הזוהר המתורגם -
    // בראשית") ולכן הלולאה נעצרת עליו, אבל בציטוט דף הטוקן השני יכול להיות
    // פרשה בתוך ספר שכותרתו הטוקן הראשון לבדו. מצרפים גם את הפירוש הקצר.
    if (bookQueryTokenCount > 1 &&
        _isSectionThenDafCitation(queryTokens.sublist(1))) {
      final seen = {
        for (final hit in [...bookHits, ...secondaryHits])
          (hit.bookId, hit.filePath),
      };
      for (final hit in searchBooks(queryTokens.first, limit: 50)) {
        if (!seen.add((hit.bookId, hit.filePath))) continue;
        secondaryHits.add(hit);
        secondaryPhraseTokenCount[hit] = 1;
      }
    }

    // צרף את ה-secondary hits בסוף, כך שיופיעו אחרי ה-primary בדירוג.
    // ההצמדה היא בכל מקרה — בין אם נמצאו hits ראשיים ובין אם לא.
    if (secondaryHits.isNotEmpty) {
      bookHits = [...bookHits, ...secondaryHits];
    }

    // דרגת ההתאמה של שם הספר חייבת לשרוד עד למיון הסופי: תוצאה מקורבת
    // אינה רשאית לדחוק כינוי מדויק רק בגלל סדר הספרייה או תקרת התוצאות.
    final bookMatchRanks = <(int, String), int>{};
    for (final hit in bookHits) {
      if (hit.bookId > 0 || hit.filePath.isNotEmpty) {
        final key = (hit.bookId, hit.bookId > 0 ? '' : hit.filePath);
        final previous = bookMatchRanks[key];
        if (previous == null || hit.matchRank < previous) {
          bookMatchRanks[key] = hit.matchRank;
        }
      }
    }

    final dibburim = dibburQuery == null
        ? const <int, List<_Dibbur>>{}
        : await _awaitCurrent(_resolveDibburim(bookHits, dibburQuery.prefix));

    final results = <DbReferenceResult>[];
    final directMatches = <DbReferenceResult>{};

    void addDibburim(ReferenceBookHit hit) {
      for (final dibbur in dibburim[hit.bookId] ?? const <_Dibbur>[]) {
        results.add(
          DbReferenceResult(
            title: hit.title,
            reference: '${hit.title} ד"ה ${dibbur.display}',
            segment: dibbur.lineIndex,
            filePath: hit.filePath,
            orderIndex: hit.orderIndex,
            tocLevel: 3,
            bookId: hit.bookId,
            sourceLineId: dibbur.lineId,
            isSourceLine: true,
          ),
        );
      }
    }

    // Single-word query: skip per-book TOC search, but still match short
    // AltToc headings globally ("נח" / "פרשת האזינו") — issue #983.
    if (queryTokens.length == 1) {
      for (final hit in bookHits) {
        final isPdf = hit.fileType == 'pdf';

        addDibburim(hit);
        results.add(
          DbReferenceResult(
            title: hit.title,
            reference: hit.title,
            segment: 0,
            isPdf: isPdf,
            filePath: hit.filePath,
            orderIndex: hit.orderIndex,
            bookId: hit.bookId,
          ),
        );
      }

      if (queryTokens.first.length >= 2) {
        final start = results.length;
        await _awaitCurrent(
          _addGlobalAltTocMatches(
            results,
            queryTokens,
            maxRefTokens: 2,
            visibility: visibility.selection.isEmpty ? null : visibility,
          ),
        );
        directMatches.addAll(results.skip(start));
      }

      if (includePersonalBooks) {
        results.addAll(
          await _awaitCurrent(_searchPersonalBooks(queryTokens, visibility)),
        );
        results.addAll(
          await _awaitCurrent(
            _searchAttachedLibraries(queryTokens, visibility),
          ),
        );
      }

      final unique = _dedupeRefs(results);
      final ranked = _rankResults(
        unique,
        queryTokens,
        bookMatchRanks: bookMatchRanks,
        directMatches: directMatches,
        preserveSubstringTail: queryTokens.length == 1,
      );
      return await _awaitCurrent(_enrichWithPaths(ranked));
    }

    // If the *next* token after the matched book-phrase is an exact book match,
    // avoid TOC search to prevent cross-book false positives.
    final nextTokenIndex = bookQueryTokenCount;
    final nextToken = queryTokens.length > nextTokenIndex
        ? queryTokens[nextTokenIndex]
        : '';
    final hasExactNextTokenMatch =
        nextToken.isNotEmpty &&
        ((searchReferenceBooks == null
                ? officialBatch().hasExactTitle(nextToken)
                : null) ??
            searchBooks(
              nextToken,
              limit: 50,
            ).any((hit) => hit.matchRank == 0));

    // תקרה על קריאות ה-TOC היקרות (שאילתת DB / outline לכל ספר). ה-limit הגבוה
    // מאפשר לטוקן ראשון רחב ("ראש") להתאים מאות ספרים; ה-suppress מסנן את רובם
    // בחינם, אך כשאין טוקן-ספר הבא (אין suppress) התקרה מונעת הצפת שאילתות.
    var tocLookups = 0;
    const maxTocLookups = 50;

    // כשהטוקן הראשון תפס ספרים רבים (כמו "ראש") בלי אקרוניום שמצמצם, הספר
    // המכוון עלול לשבת עמוק ברשימה ולהיחתך ע"י התקרה (למשל "ראש בבא בתרא"
    // בלי אקרוניום → הרא"ש על ב"ב במקום ~138). ממיינים כך שספרים שכותרתם
    // מכסה יותר מטוקני-השאילתה (מעבר לאותיות-מיקום בודדות) ייבדקו קודם.
    bookHits = _prioritizeByTitleCoverage(bookHits, queryTokens, maxTocLookups);

    // רק ~5% מהספרים הם בעלי מבנה AltToc — לשאר לא מבקשים AltToc כלל.
    final altBookIds = await _awaitCurrent(_getAltBookIds());

    // אורך ה-phrase שזיהה כל hit: זה שנקבע בלולאה, או קצר יותר ל-hits שנאספו
    // בפירוש חלופי — חיתוך לפי האורך הגלובלי היה בולע להם טוקן-קטע.
    final remainingByHit = <ReferenceBookHit, List<String>>{};
    for (final hit in bookHits) {
      final phraseTokenCount =
          secondaryPhraseTokenCount[hit] ?? bookQueryTokenCount;
      remainingByHit[hit] = _getRemainingTokens(
        queryTokens,
        hit.titleTokens,
        stripLeadingTokensCount: hit.matchRank >= 3 ? phraseTokenCount : 0,
        prefixMatchTokensCount: hit.matchRank >= 3 ? 0 : phraseTokenCount,
      );
    }
    final exactLines = await _awaitCurrent(
      _resolveExactLines(
        bookHits,
        remainingByHit,
        // זנב הדיבור כבר נחתך מהטוקנים, וספירת טווח מול השאילתה הגולמית
        // הייתה מודדת אותו.
        tokensAfterRange: dibburQuery != null
            ? 0
            : _tokensAfterRange(ref, queryTokens),
      ),
    );

    // שלב א: אילו ספרים מגיעים לחיפוש תוכן העניינים. התקרה משותפת ל-PDF
    // ולספרי המסד ונספרת לפי סדר הספרים.
    final plans = <_TocPlan>[];
    final tocRequests = <TocBatchRequest>[];
    for (final hit in bookHits) {
      final remainingTokens = remainingByHit[hit]!;
      // טוקן-ספר עצמאי אחרי השם ("תורה אור") יוצר התאמות חוצות-ספרים — אלא אם
      // הוא חלק מהכותרת הנוכחית, או שבזנב ציטוט דף ("זהר בראשית דף לו").
      final suppressTocForCrossBook =
          hasExactNextTokenMatch &&
          !hit.titleTokens.contains(nextToken) &&
          !_isSectionThenDafCitation(remainingTokens);
      if (remainingTokens.isEmpty || suppressTocForCrossBook) {
        plans.add(_TocPlan.none);
      } else if (tocLookups >= maxTocLookups) {
        plans.add(_TocPlan.overCap);
      } else {
        tocLookups++;
        if (hit.bookId == -1) {
          plans.add(_TocPlan.pdfOutline);
          continue;
        }
        // ראש-תיבות שזנבו אינו מילת-כותרת ("טור יורה דעה" מול הכותרת "טור")
        // מציין חלק בתוך הספר; הזנב אינו בהכרח חלק ("חזקוני על התורה") — ולכן נסיגה.
        final sectionTokens = _acronymSectionTokens(hit);
        plans.add(_TocPlan.request(tocRequests.length));
        tocRequests.add((
          bookId: hit.bookId,
          bookTitle: hit.title,
          queryTokens: [...sectionTokens, ...remainingTokens],
          fallbackTokens: sectionTokens.isEmpty ? null : remainingTokens,
          altTocTokens: altBookIds != null && !altBookIds.contains(hit.bookId)
              ? null
              : remainingTokens,
        ));
      }
    }

    final tocResponses = tocRequests.isEmpty
        ? const <TocBatchResult>[]
        : await _awaitCurrent(fetchTocBatch(tocRequests));

    // שלב ב: התוצאות, בסדר הספרים.
    for (var i = 0; i < bookHits.length; i++) {
      final hit = bookHits[i];
      final plan = plans[i];
      final bookId = hit.bookId;
      final title = hit.title;
      final isPdf = hit.fileType == 'pdf';
      final remainingTokens = remainingByHit[hit]!;

      // bookId == -1: file-system PDF not in DB — use PDF outline as TOC,
      // mirroring the regular book flow as closely as possible.
      if (bookId == -1) {
        // בלי זנב לא נסקר ה-outline: ב-PDF רבים הוא ברמת דף-לדף, והדפים
        // דחקו החוצה ספרי מסד.
        if (remainingTokens.isEmpty) {
          results.add(
            DbReferenceResult(
              title: title,
              reference: title,
              segment: 0,
              isPdf: true,
              filePath: hit.filePath,
              orderIndex: hit.orderIndex,
            ),
          );
          continue;
        }
        if (!plan.isPdfOutline) continue;

        final outlineFn =
            getPdfOutlineEntries ??
            ReferenceBooksCache.instance.getPdfOutlineEntries;
        final outlineEntries = await _awaitCurrent(outlineFn(hit.filePath));
        final normalizedBookTitle = _normalizeForMatch(title);

        // ציטוט דף: התאמה מיקומית (מספר מול מספר, עמוד מול עמוד) — כדי ש-"ב"
        // בודד לא ייתפס ע"י סימון צד ע"ב ("דף ג:") של כל דף ב-outline.
        final cite = parseDafCitation(remainingTokens);

        for (final (normChapter, origChapter, pageNumber) in outlineEntries) {
          if (normChapter == normalizedBookTitle) continue;
          final chapterWords = _tokenize(normChapter);
          bool matches;
          final dafMatch = cite == null
              ? null
              : matchDafCitation(chapterWords, cite);
          if (dafMatch != null) {
            matches = dafMatch;
          } else {
            matches = remainingTokens.every(
              (t) => chapterWords.any((w) => w.startsWith(t)),
            );
          }
          if (!matches) continue;
          results.add(
            DbReferenceResult(
              title: title,
              reference: '$title $origChapter',
              segment: pageNumber,
              isPdf: true,
              filePath: hit.filePath,
              orderIndex: hit.orderIndex,
              tocLevel: 2,
            ),
          );
        }
        continue;
      }

      addDibburim(hit);

      for (final exact in exactLines[bookId] ?? const <_ExactLine>[]) {
        results.add(
          DbReferenceResult(
            title: title,
            reference: exact.heRef ?? '$title ${remainingTokens.join(' ')}',
            segment: exact.lineIndex,
            filePath: hit.filePath,
            orderIndex: hit.orderIndex,
            tocLevel: 3,
            bookId: bookId,
            sourceLineId: exact.lineId,
            isSourceLine: true,
          ),
        );
      }

      DbReferenceResult bookResult() => DbReferenceResult(
        title: title,
        reference: title,
        segment: 0,
        isPdf: isPdf,
        filePath: hit.filePath,
        orderIndex: hit.orderIndex,
        bookId: bookId,
      );

      // הוקלדה רק כותרת הספר — הספר בלבד, בלי ערכי TOC.
      if (remainingTokens.isEmpty) {
        results.add(bookResult());
        continue;
      }
      final requestIndex = plan.requestIndex;
      if (requestIndex == null) continue;
      final response = tocResponses[requestIndex];

      final resultsBeforeToc = results.length;
      for (final entry in response.toc) {
        results.add(
          DbReferenceResult(
            title: title,
            reference: entry['reference'] as String,
            segment: entry['segment'] as int,
            isPdf: isPdf,
            filePath: hit.filePath,
            orderIndex: hit.orderIndex,
            tocLevel: entry['level'] as int,
            bookId: bookId,
            sourceLineId: entry['dbLineId'] as int? ?? 0,
          ),
        );
      }

      // ה-reference של AltToc יחסי לספר ("פרשת לך לך עליה ו" בתוך "בראשית"),
      // ולכן שם הספר מצורף כדי שהתצוגה תזהה לאיזה ספר התוצאה שייכת.
      for (final entry in response.altToc) {
        final ref = entry['reference'] as String;
        // כל טוקני הזנב בערך — אחרת ספר שהותאם ברפיון ("נחל שורק" מול "נח")
        // מחזיר את "הפטרת נח" עבור "נח עליה ב".
        final refTokens = _tokenize(_normalizeForMatch(ref));
        if (!remainingTokens.every((qt) => refTokens.contains(qt))) continue;

        results.add(
          DbReferenceResult(
            title: title,
            reference: qualifyAltTocReference(title, ref),
            segment: entry['segment'] as int,
            isPdf: isPdf,
            filePath: hit.filePath,
            orderIndex: hit.orderIndex,
            tocLevel: entry['level'] as int,
            isAltToc: true,
            bookId: bookId,
            sourceLineId: entry['dbLineId'] as int? ?? 0,
          ),
        );
      }

      // מפלט אחרון: הזנב הוא שם הקטגוריה שהספר יושב בה ("רמבם המדע" —
      // "מדע" אינו בשום כותרת או ראש-תיבות, רק בקטגוריה "ספר מדע"). רק
      // כשה-TOC לא החזיר כלום, כדי שכותרת פנימית תמיד תגבר.
      if (results.length == resultsBeforeToc &&
          _remainingTokensAreLeafCategory(bookId, remainingTokens)) {
        results.add(bookResult());
      }
    }

    // Global AltToc fallback: when no specific result was found in the per-book
    // loop, search AltToc across all books. This handles queries like
    // "נח עליה ב" where the user doesn't type the book name, even if some
    // other book matched the first token (e.g., "תולדות יצחק" matching "תולדות").
    //
    // התנאי הוא **AltToc *או* TOC L2+ ריקים** — כלומר, גם הפניות פנימיות
    // רגילות נחשבות "ספציפיות". הסיבה: עם המעבר לקאש השטוח הגלובלי, הפילטר
    // הוא רק `every(contains)`, שמייצר הרבה false-positives של AltToc
    // מספרים עם orderIndex נמוך. אלה דוחקים החוצה תוצאות TOC PDF מספרים עם
    // orderIndex גבוה (כי `_rankResults` בודק orderIndex לפני tocLevel),
    // ובפועל גורם ל"ברכות ב" לא להציג את ה-PDF של ברכות. אם ה-per-book כבר
    // החזיר התאמה ספציפית, אין צורך ב-fallback — שום שאילתה ש"דורשת" כותרת
    // פנימית של ספר אחר.
    //
    // נעטף ב-try/catch כדי שכשלון במסלול ה-fallback לא יבלע את התוצאות
    // הקיימות מהלולאת ה-per-book.
    final bool perBookHasSpecificMatch = results.any(
      (r) => r.isAltToc || r.tocLevel >= 2,
    );
    if (!perBookHasSpecificMatch && queryTokens.length >= 2) {
      final start = results.length;
      await _awaitCurrent(
        _addGlobalAltTocMatches(
          results,
          queryTokens,
          visibility: visibility.selection.isEmpty ? null : visibility,
        ),
      );
      directMatches.addAll(results.skip(start));
    }

    if (includePersonalBooks) {
      results.addAll(
        await _awaitCurrent(_searchPersonalBooks(queryTokens, visibility)),
      );
      results.addAll(
        await _awaitCurrent(_searchAttachedLibraries(queryTokens, visibility)),
      );
    }

    final unique = _dedupeRefs(results);
    final pruned = _suppressDeeperVariants(unique);
    final ranked = _rankResults(
      pruned,
      queryTokens,
      bookMatchRanks: bookMatchRanks,
      directMatches: directMatches,
    );

    return await _awaitCurrent(_enrichWithPaths(ranked));
  }

  /// תוצאות PDF של תלמוד בבלי אינן מוצגות באיתור — מהדורת הטקסט מייצגת את
  /// המסכת, ופורמט הפתיחה בפועל נקבע לפי הגדרת המשתמש בעת הפתיחה.
  static List<DbReferenceResult> _dropTalmudBavliPdfRefs(
    List<DbReferenceResult> results,
  ) => results.where((r) => !isTalmudBavliPdfRef(r)).toList();

  @visibleForTesting
  static bool isTalmudBavliPdfRef(DbReferenceResult r) {
    if (!r.isPdf) return false;
    const bavli = DatabaseConstants.talmudBavliFolderName;
    if (r.bookPath.isNotEmpty) {
      return r.bookPath.split(', ').first.trim() == bavli;
    }
    // PDF מחוץ ל-DB: זיהוי לפי תיקיית הקובץ.
    return r.filePath.contains('/$bavli/') || r.filePath.contains('\\$bavli\\');
  }

  /// מזהה מילת-דור בשאילתה (בכל מיקום) ומחזיר את הדור + טוקני-הנושא שנותרו.
  /// תומך ב"ראשונים"/"אחרונים" (טוקן יחיד) וב"מחברי זמננו" (שני טוקנים).
  ///
  /// מחזיר `null` אם אין מילת-דור, או אם לא נותר טוקן-נושא **משמעותי** (באורך
  /// 2 לפחות) — כדי ש"ראשונים" לבד או "ראשונים ב" לא יציפו מאות ספרים.
  ({CommentaryEra era, List<String> topicTokens})? _detectEraQuery(
    List<String> tokens,
  ) {
    CommentaryEra? era;
    final topic = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      // "מחברי זמננו" — שני טוקנים רצופים.
      if (era == null &&
          tok == 'מחברי' &&
          i + 1 < tokens.length &&
          tokens[i + 1] == 'זמננו') {
        era = CommentaryEra.modern;
        i++; // דלג על "זמננו"
        continue;
      }
      final single = _singleTokenEras[tok];
      if (era == null && single != null) {
        era = single;
        continue;
      }
      topic.add(tok);
    }
    if (era == null) return null;
    // משאירים רק טוקנים משמעותיים (אורך >=2). טוקן של אות בודדת הוא מציין
    // מיקום (דף/פרק) ולא חלק משם הספר — להשאירו בהתאמה היה דורש מילה בכותרת
    // שמתחילה בו ומסנן תוצאות לגיטימיות ("ראשונים סנהדרין ב").
    final meaningful = topic.where((t) => t.length >= 2).toList();
    if (meaningful.isEmpty) return null;
    return (era: era, topicTokens: meaningful);
  }

  /// בונה תוצאות עבור מצב "דור + נושא": כל הספרים בדור [era] שכותרתם תואמת את
  /// [topicTokens]. התוצאות הן ברמת-ספר (פתיחה לתחילת הספר), ועוברות את אותו
  /// דירוג + cap מודע-רלוונטיות של המסלול הרגיל ([_rankResults]).
  Future<List<DbReferenceResult>> _findByEra(
    CommentaryEra era,
    List<String> topicTokens,
    FindRefVisibility visibility,
  ) async {
    final injected = searchByEraAndTopic;
    final List<ReferenceBookHit> hits;
    if (injected != null) {
      final candidates = injected(era, topicTokens, limit: _maxResultCap);
      hits = visibility.selection.isEmpty
          ? candidates
          : candidates
                .where(
                  (hit) => visibility.allowsCandidate(
                    BookSource.official,
                    hit.bookId,
                    hit.filePath,
                    fileType: hit.fileType,
                  ),
                )
                .toList();
    } else {
      hits = ReferenceBooksCache.instance.searchByEraAndTopic(
        era,
        topicTokens,
        limit: _maxResultCap,
        allowsBook: visibility.selection.isEmpty
            ? null
            : (id, path, type) => visibility.allowsCandidate(
                BookSource.official,
                id,
                path,
                fileType: type,
              ),
      );
    }
    if (hits.isEmpty) return const [];

    final results = [
      for (final hit in hits)
        DbReferenceResult(
          title: hit.title,
          reference: hit.title,
          segment: 0,
          isPdf: hit.fileType == 'pdf',
          filePath: hit.filePath,
          orderIndex: hit.orderIndex,
          bookId: hit.bookId,
        ),
    ];

    final unique = _dedupeRefs(results);
    final ranked = _rankResults(unique, topicTokens);
    return await _enrichWithPaths(ranked);
  }

  /// מסיר ערכי TOC/AltToc כאשר קיים ערך-אב באותו ספר שה-reference שלו הוא
  /// prefix של הערך הנוכחי. הרציונל: השאילתה כבר תאמה ערך רחב (כמו
  /// "אור זרוע פסקי בבא קמא"), ולכן ערכי-ילדים שמרחיבים אותו
  /// ("... סימן ת", "... סימן ב", ...) אינם מוסיפים מידע לחיפוש — הם רק
  /// ממלאים את 15 התוצאות הזמינות בפירוט פנימי שאותו המשתמש לא ביקש.
  ///
  /// הסינון הזה הכרחי במיוחד עבור ה-fallback הגלובלי של AltToc: בניגוד לחיפוש
  /// הפר-ספר ([_searchAltTocFlat] ב-seforim_repository) שמחיל "anti-flood"
  /// (הטוקן האחרון חייב להופיע ב-ownTokens), ה-flat cache הגלובלי בודק רק
  /// אם כל הטוקנים מופיעים בנתיב המלא — וכך צאצאי entry שתואם משתחלים גם הם.
  ///
  /// ההשוואה היא לפי `(bookId, source, isAltToc, isPdf)`: TOC ו-AltToc
  /// הם מבנים חלופיים — אחד לא מסתיר את השני. ספרים שונים בכלל אינם
  /// משפיעים אחד על השני. רמת ה-TOC המוחלטת לא רלוונטית כי מבני AltToc
  /// מתחילים ב-DB מ-level 0 בעוד TOC רגיל מ-1 — מה שחשוב הוא היחס prefix
  /// בלבד (כולל רווח בסוף, להבטיח גבול מילה שלמה).
  List<DbReferenceResult> _suppressDeeperVariants(
    List<DbReferenceResult> entries,
  ) {
    if (entries.length < 2) return entries;

    final referencesByGroup = <(int, BookSource, bool, bool), Set<String>>{};
    for (final e in entries) {
      (referencesByGroup[(e.bookId, e.source, e.isAltToc, e.isPdf)] ??= {}).add(
        e.reference,
      );
    }
    return entries.where((entry) {
      // שורת מקור היא התוצאה הספציפית ביותר — לעולם אינה "וריאנט עמוק" של
      // כותרת. בלי הסייג, תוצאת ספר ("תוספות על ברכות") בלעה את הדיבור שתחתיה.
      if (entry.isSourceLine) return true;
      final siblings =
          referencesByGroup[(
            entry.bookId,
            entry.source,
            entry.isAltToc,
            entry.isPdf,
          )]!;
      // אב = reference אחר שהוא תחילית עד גבול רווח ("פרק א" לא חוסם "פרק אבות").
      final reference = entry.reference;
      for (
        var i = reference.indexOf(' ');
        i >= 0;
        i = reference.indexOf(' ', i + 1)
      ) {
        if (siblings.contains(reference.substring(0, i))) return false;
      }
      return true;
    }).toList();
  }

  Future<List<DbReferenceResult>> _searchPersonalBooks(
    List<String> queryTokens,
    FindRefVisibility visibility,
  ) async {
    try {
      // רשימת הספרים האישיים נטענת מקאש בזיכרון (ראה [_loadUserBooks]) — כך
      // אין שאילתת DB לכל הקלדה, רק בחיפוש הראשון אחרי רענון.
      final allBooks = await _awaitCurrent(_loadUserBooks());
      if (allBooks.isEmpty) return const [];
      return await _searchSecondaryBooks(
        queryTokens,
        books: allBooks,
        visibility: visibility,
        source: BookSource.user,
        rootPath: 'ספרים אישיים',
        fetchTocBatch: _fetchUserBookTocs,
      );
    } on FindRefQueryCancelled {
      rethrow;
    } catch (e) {
      debugPrint('[FindRef] Personal books search failed: $e');
      return const [];
    }
  }

  /// ספרי המסדים המצורפים הגלויים, מסד אחרי מסד לפי סדר העדיפות. כל מסד
  /// נחקר דרך המאגר המוקשח שלו: כותרת, כינויים, תוכן עניינים ו-`line_ref`.
  Future<List<DbReferenceResult>> _searchAttachedLibraries(
    List<String> queryTokens,
    FindRefVisibility visibility,
  ) async {
    final out = <DbReferenceResult>[];
    final registry = AttachedLibraryRegistry.instance;
    final List<AttachedLibrary> libraries;
    try {
      libraries = registry.visibleLibraries;
      if (libraries.isEmpty) return out;
      await _awaitCurrent(AcronymsCache.instance.warmUpAttached());
    } on FindRefQueryCancelled {
      rethrow;
    } catch (e) {
      debugPrint('[FindRef] attached libraries unavailable: $e');
      return out;
    }

    for (final library in libraries) {
      if (!library.isOk) continue;
      try {
        final books = await _awaitCurrent(_loadAttachedBooks(library));
        if (books.isEmpty) continue;
        final source = BookSource.attached(library.slug);
        final worker = AttachedFindRefWorker.instance;
        Future<R> run<R>(AttachedDbJob<R> job, {int calls = 1}) => worker.run(
          library.path,
          immutable: library.immutable,
          version: _attachedVersion(library),
          job: job,
          calls: calls,
        );
        out.addAll(
          await _awaitCurrent(
            _searchSecondaryBooks(
              queryTokens,
              books: books,
              visibility: visibility,
              source: source,
              rootPath: library.displayName,
              maxTocBooks: maxAttachedTocBooks,
              acronymsOf: (id) =>
                  AcronymsCache.instance.acronymsFor(source, id) ?? const [],
              fetchTocBatch: (books) => worker.runBatch(
                library.path,
                immutable: library.immutable,
                version: _attachedVersion(library),
                jobs: [for (final book in books) _attachedTocJob(book)],
                searchScope: _secondaryScope,
                searchEpoch: currentSearchGeneration,
              ),
              resolveLineRefs: (bookIds, refKey) =>
                  run(_attachedLineRefsJob(bookIds, refKey)),
            ),
          ),
        );
      } on FindRefQueryCancelled {
        rethrow;
      } catch (e) {
        debugPrint('[FindRef] attached ${library.slug} search failed: $e');
      }
    }
    return out;
  }

  /// כמה ספרים ממסד מצורף אחד מגיעים לשלב תוכן העניינים בכל הקלדה.
  @visibleForTesting
  static int maxAttachedTocBooks = 12;

  /// תוכן העניינים של כל הספרים האישיים המועמדים — בבקשה אחת ל-worker, כדי
  /// שהשאילתה הסינכרונית לא תחסום את ההקלדה. כשל מדלג על ה-TOC בלבד.
  Future<List<List<Map<String, dynamic>>>> _fetchUserBookTocs(
    List<_SecondaryTocRequest> books,
  ) async {
    final injected = getUserBookTocEntries;
    if (injected != null) {
      return [
        for (final book in books)
          await _awaitCurrent(
            injected(
              book.bookId,
              book.bookTitle,
              queryTokens: book.queryTokens,
            ),
          ),
      ];
    }
    final path = _userBooksDbPath;
    if (path == null) return [for (final _ in books) const []];
    // סגירת ה-holder (העברת ספרייה, יציאה) חייבת לשחרר גם את חיבור ה-worker.
    UserBooksDatabaseHolder.instance.addCloseListener(_resetSecondaryWorker);
    try {
      return await AttachedFindRefWorker.instance.runBatch(
        path,
        immutable: false,
        version: '$_userBooksVersion',
        jobs: [
          for (final (index, book) in books.indexed)
            _userBookTocJob(book, invalidateCache: index == 0),
        ],
        searchScope: _secondaryScope,
        searchEpoch: currentSearchGeneration,
      );
    } on FindRefQueryCancelled {
      rethrow;
    } catch (e) {
      debugPrint('[FindRef] personal TOC lookup failed: $e');
      return [for (final _ in books) const []];
    }
  }

  static void _resetSecondaryWorker() => AttachedFindRefWorker.instance.reset();

  static AttachedDbJob<List<Map<String, dynamic>>> _userBookTocJob(
    _SecondaryTocRequest book, {
    required bool invalidateCache,
  }) => (repository) async {
    if (invalidateCache) {
      await repository.invalidateTocCacheIfChangedExternally();
    }
    return _tocOf(repository, book);
  };

  static String _attachedVersion(AttachedLibrary library) {
    final fingerprint = library.fingerprint;
    return fingerprint == null
        ? ''
        : '${fingerprint.size}:${fingerprint.modifiedMs}';
  }

  // העבודות נבנות בפונקציות סטטיות כדי שהסגור לא יגרור את המופע ל-isolate.
  static AttachedDbJob<List<Map<String, dynamic>>> _attachedTocJob(
    _SecondaryTocRequest book,
  ) =>
      (repository) => _tocOf(repository, book);

  /// כשל בספר אחד אינו מונע איתור בשאר הספרים.
  static Future<List<Map<String, dynamic>>> _tocOf(
    SeforimRepository repository,
    _SecondaryTocRequest book,
  ) async {
    try {
      return await repository.getTocEntriesForReference(
        book.bookId,
        book.bookTitle,
        queryTokens: book.queryTokens,
      );
    } catch (e) {
      debugPrint('[FindRef] secondary TOC lookup failed: $e');
      return const [];
    }
  }

  static AttachedDbJob<Map<int, _ExactLine>> _attachedLineRefsJob(
    List<int> bookIds,
    String refKey,
  ) =>
      (repository) async => {
        for (final entry in (await repository.resolveRefKeyInBooks(
          bookIds,
          refKey,
        )).entries)
          entry.key: (
            lineIndex: entry.value.lineIndex,
            lineId: entry.value.lineId,
            heRef: entry.value.heRef,
          ),
      };

  static Future<List<_SecondaryBook>> _attachedBooksJob(
    SeforimRepository repository,
  ) => _readSecondaryBooksFrom(repository);

  /// רשימת הספרים של מסד מצורף, מקאש שנבנה מחדש כשרשומת המסד השתנתה.
  Future<List<_SecondaryBook>> _loadAttachedBooks(
    AttachedLibrary library,
  ) async {
    final cached = _attachedBooksCache[library.slug];
    if (cached != null && cached.library == library) return cached.books;
    final books = await AttachedFindRefWorker.instance.run(
      library.path,
      immutable: library.immutable,
      version: _attachedVersion(library),
      job: _attachedBooksJob,
    );
    _attachedBooksCache[library.slug] = (library: library, books: books);
    return books;
  }

  /// הספרים של מסד משני, כל אחד עם שרשרת הקטגוריות שמעליו וטוקני השם.
  static Future<List<_SecondaryBook>> _readSecondaryBooksFrom(
    SeforimRepository repository,
  ) async {
    final raw = await repository.database.bookDao.getAllLocalBooks();
    // שרשרת התיקיות של כל ספר — בספרים אישיים שם הספר יושב לרוב על
    // התיקייה ('חלק א' בתוך 'שות פלוני'), והיא חלק מהתאמת הכותרת.
    final categories = await repository.database.categoryDao.getAllCategories();
    final byId = {for (final c in categories) c.id: c};
    List<String> chainOf(int categoryId) {
      final titles = <String>[];
      for (
        var c = byId[categoryId];
        c != null && titles.length < 12;
        c = c.parentId == null ? null : byId[c.parentId]
      ) {
        titles.insert(0, c.title);
      }
      return titles;
    }

    return [
      for (final b in raw)
        _SecondaryBook((
          id: b.id,
          title: b.title,
          filePath: b.filePath,
          fileType: b.fileType ?? 'txt',
          orderIndex: b.order,
          folderTitles: chainOf(b.categoryId),
        )),
    ];
  }

  /// התאמת שאילתה לספרי מסד משני (אישי או מצורף): כותרת, שם תיקייה + כותרת,
  /// או כינוי מ-[acronymsOf]; ואחריה שורה מדויקת דרך [resolveLineRefs] או
  /// ערכי תוכן העניינים שתואמים את שארית השאילתה.
  Future<List<DbReferenceResult>> _searchSecondaryBooks(
    List<String> queryTokens, {
    required List<_SecondaryBook> books,
    required FindRefVisibility visibility,
    required BookSource source,
    required String rootPath,
    required Future<List<List<Map<String, dynamic>>>> Function(
      List<_SecondaryTocRequest> books,
    )
    fetchTocBatch,
    List<String> Function(int bookId)? acronymsOf,
    Future<Map<int, _ExactLine>> Function(List<int> bookIds, String refKey)?
    resolveLineRefs,
    int? maxTocBooks,
  }) async {
    final out = <DbReferenceResult>[];
    final maxN = queryTokens.length >= 3 ? 3 : queryTokens.length;

    // Find the longest leading phrase that matches position-by-position
    int? leadingPhraseMatch(List<String> nameTokens, int cap) {
      for (var n = cap; n >= 1; n--) {
        if (n > nameTokens.length) continue;
        var ok = true;
        for (var i = 0; i < n; i++) {
          if (!nameTokens[i].startsWith(queryTokens[i])) {
            ok = false;
            break;
          }
        }
        if (ok) return n;
      }
      return null;
    }

    final matches = <(_UserBookRecord, List<String>)>[];
    final matchedCounts = <int>[];
    final restrict = !visibility.selection.isEmpty;
    for (final secondary in books) {
      final book = secondary.record;
      if (restrict &&
          !visibility.allowsCandidate(
            source,
            book.id,
            book.filePath ?? '',
            fileType: book.fileType,
          )) {
        continue;
      }
      final titleTokens = secondary.titleTokens;

      var nameTokens = titleTokens;
      var matchedN = leadingPhraseMatch(titleTokens, maxN);

      // הכותרת לא התאימה — ניסיון מול שם תיקייה + כותרת, לכל סיומת של
      // שרשרת התיקיות ('שות פלוני חלק א'). כך שאילתת שם התיקייה מוצאת את
      // הקבצים שבתוכה. התקרה כאן לפי אורך השם המורחב, לא ה-3 של כותרת.
      if (matchedN == null) {
        for (var i = secondary.folderNameTokens.length - 1; i >= 0; i--) {
          final candidate = secondary.folderNameTokens[i];
          final n = leadingPhraseMatch(
            candidate,
            queryTokens.length.clamp(0, candidate.length),
          );
          // דרישת מינימום: ההתאמה חייבת לכסות את כל מילות התיקייה שבשם —
          // אחרת 'שות' לבדה הייתה גוררת את כל תוכן התיקייה.
          if (n != null && n >= candidate.length - titleTokens.length) {
            nameTokens = candidate;
            matchedN = n;
            break;
          }
        }
      }

      // כינוי מלא, או שאילתה שכולה תחילית של כינוי.
      if (matchedN == null && acronymsOf != null) {
        for (final term in acronymsOf(book.id)) {
          final termTokens = _tokenize(term);
          final cap = queryTokens.length < termTokens.length
              ? queryTokens.length
              : termTokens.length;
          final n = leadingPhraseMatch(termTokens, cap);
          if (n != null &&
              (n == termTokens.length || n == queryTokens.length)) {
            nameTokens = termTokens;
            matchedN = n;
            break;
          }
        }
      }
      if (matchedN == null) continue;

      matchedCounts.add(matchedN);
      matches.add((
        book,
        _getRemainingTokens(
          queryTokens,
          nameTokens,
          prefixMatchTokensCount: matchedN,
        ),
      ));
    }

    // שאילתה מאוגדת אחת לכל מפתח קנוני, כמו במסלול הספרייה הרשמית.
    final exactLines = <int, _ExactLine>{};
    if (resolveLineRefs != null && queryTokens.length > 1) {
      final bookIdsByKey = <String, List<int>>{};
      for (final (book, remaining) in matches) {
        if (book.fileType == 'pdf' || remaining.length < 2) continue;
        final key = buildRefKey(remaining.join(' '));
        if (key != null) (bookIdsByKey[key] ??= []).add(book.id);
      }
      for (final entry in bookIdsByKey.entries) {
        exactLines.addAll(
          await _awaitCurrent(resolveLineRefs(entry.value, entry.key)),
        );
      }
    }

    // תקרה (מסדים מצורפים) נותנת את ה-TOC לספרים שהשם שלהם כיסה הכי הרבה
    // מהשאילתה ("שות פלוני חלק טו ג" → "חלק טו"), לא לראשונים בסדר הקטלוג.
    Set<int>? tocAllowed;
    if (maxTocBooks != null) {
      final eligible = [
        for (var i = 0; i < matches.length; i++)
          if (queryTokens.length > 1 && matches[i].$2.isNotEmpty) i,
      ];
      mergeSort(
        eligible,
        compare: (a, b) => matchedCounts[b].compareTo(matchedCounts[a]),
      );
      tocAllowed = eligible.take(maxTocBooks).toSet();
    }

    // מילה אחת, רק כותרת, או ספר מעבר לתקרה — הספר בלבד, בלי ערכי TOC.
    final tocRequests = <_SecondaryTocRequest>[];
    final tocIndexByMatch = <int?>[];
    for (final (i, (book, remainingTokens)) in matches.indexed) {
      final wantsToc = queryTokens.length > 1 && remainingTokens.isNotEmpty;
      if (wantsToc && (tocAllowed == null || tocAllowed.contains(i))) {
        tocIndexByMatch.add(tocRequests.length);
        tocRequests.add((
          bookId: book.id,
          bookTitle: book.title,
          queryTokens: remainingTokens,
        ));
      } else {
        tocIndexByMatch.add(null);
      }
    }
    final tocs = tocRequests.isEmpty
        ? const <List<Map<String, dynamic>>>[]
        : await _awaitCurrent(fetchTocBatch(tocRequests));

    for (var m = 0; m < matches.length; m++) {
      final (book, remainingTokens) = matches[m];
      final isPdf = book.fileType == 'pdf';
      final bookPath = book.folderTitles.isEmpty
          ? rootPath
          : book.folderTitles.join(', ');
      DbReferenceResult result({
        required String reference,
        required int segment,
        int tocLevel = 1,
        int sourceLineId = 0,
        bool isSourceLine = false,
      }) => DbReferenceResult(
        title: book.title,
        reference: reference,
        segment: segment,
        isPdf: isPdf,
        filePath: book.filePath ?? '',
        orderIndex: book.orderIndex,
        tocLevel: tocLevel,
        bookId: book.id,
        bookPath: bookPath,
        sourceLineId: sourceLineId,
        source: source,
        isSourceLine: isSourceLine,
      );

      final exact = exactLines[book.id];
      if (exact != null) {
        out.add(
          result(
            reference:
                exact.heRef ?? '${book.title} ${remainingTokens.join(' ')}',
            segment: exact.lineIndex,
            tocLevel: 3,
            sourceLineId: exact.lineId,
            isSourceLine: true,
          ),
        );
      }

      final tocIndex = tocIndexByMatch[m];
      if (tocIndex == null) {
        out.add(result(reference: book.title, segment: 0));
        continue;
      }
      for (final entry in tocs[tocIndex]) {
        out.add(
          result(
            reference: entry['reference'] as String,
            segment: entry['segment'] as int,
            tocLevel: entry['level'] as int,
            sourceLineId: entry['dbLineId'] as int? ?? 0,
          ),
        );
      }
    }
    return out;
  }

  Future<List<DbReferenceResult>> _enrichWithPaths(
    List<DbReferenceResult> results,
  ) async {
    // Only fetch paths for results that don't already have one set.
    // Personal books have bookPath='ספרים אישיים' pre-set; enriching them via
    // the official DB would overwrite that with a colliding official book's path
    // (user_books.db and seforim.db share no bookId namespace).
    final uniqueIds = results
        .where((r) => r.bookPath.isEmpty)
        .map((r) => r.bookId)
        .where((id) => id > 0)
        .toSet();
    if (uniqueIds.isEmpty) return _dropTalmudBavliPdfRefs(results);

    // בייצור הנתיבים כבר בקאש מה-warmUp — Future לכל ספר רק למה שחסר בו.
    final cache = ReferenceBooksCache.instance;
    final pathMap = <int, String>{};
    final missing = <int>[];
    for (final id in uniqueIds) {
      final cached = getCategoryPath == null
          ? cache.getCategoryPathForBookSync(id)
          : null;
      if (cached == null) {
        missing.add(id);
      } else {
        pathMap[id] = cached;
      }
    }
    if (missing.isNotEmpty) {
      final pathFn = getCategoryPath ?? cache.getCategoryPathForBook;
      await Future.wait(
        missing.map((id) async {
          pathMap[id] = await pathFn(id);
        }),
      );
    }

    final enriched = results.map((r) {
      if (r.bookPath.isNotEmpty) return r; // already set — don't overwrite
      final path = r.bookId > 0 ? (pathMap[r.bookId] ?? '') : '';
      if (path.isEmpty) return r;
      return r.copyWith(bookPath: path);
    }).toList();
    return _dropTalmudBavliPdfRefs(enriched);
  }

  /// ממיין את [hits] כך שספרים שכותרתם מכסה יותר טוקני-שאילתה משמעותיים
  /// (אורך >= 2, כלומר לא אותיות-מיקום בודדות) יופיעו קודם — כדי שהספר המכוון
  /// ייכנס לתוך [maxTocLookups] גם כשטוקן ראשון רחב תפס מאות ספרים.
  ///
  /// לא-אופרטיבי כשיש מעט hits או שאין טוקן-מסנן מעבר לשם הספר — מוחזרת אז
  /// אותה רשימה. המיון יציב: שובר-השוויון הוא סדר ה-search המקורי (matchRank).
  List<ReferenceBookHit> _prioritizeByTitleCoverage(
    List<ReferenceBookHit> hits,
    List<String> queryTokens,
    int maxTocLookups,
  ) {
    final significant = queryTokens
        .where((t) => t.length >= 2)
        .toList(growable: false);
    if (hits.length <= maxTocLookups || significant.length < 2) return hits;

    int coverage(ReferenceBookHit hit) {
      final titleTokens = hit.titleTokens;
      var score = 0;
      for (final qt in significant) {
        // התאמת טוקן שלם, כולל אות-חיבור בכותרת — אותם כללים כמו
        // ב-[_getRemainingTokens], אחרת ספר שהותאם דרך ו' החיבור ייחתך ע"י
        // תקרת חיפושי ה-TOC דווקא כשהוא הספר המכוון.
        var inTitle = false;
        for (var ti = 0; ti < titleTokens.length && !inTitle; ti++) {
          final tt = titleTokens[ti];
          inTitle =
              tt == qt ||
              titleTokenWithoutConjunction(tt, allowVav: ti > 0) == qt;
        }
        if (inTitle) score++;
      }
      return score;
    }

    final indexed =
        [
          for (var i = 0; i < hits.length; i++)
            (index: i, hit: hits[i], score: coverage(hits[i])),
        ]..sort((a, b) {
          final c = b.score.compareTo(a.score);
          return c != 0 ? c : a.index.compareTo(b.index);
        });
    return [for (final e in indexed) e.hit];
  }

  /// טוקני הזנב של ראש-התיבות שהותאם שאינם מילים מכותרת הספר — הם מציינים חלק
  /// *בתוך* הספר ("טור יורה דעה" / "טור יו"ד" מול הכותרת "טור"), ולכן חייבים
  /// להגיע לחיפוש ה-TOC ולא להיבלע עם שם הספר. מוחזר ריק כשראש-התיבות כולו
  /// מזהה את הספר ("שוע אוח" ← "שולחן ערוך אורח חיים").
  static List<String> _acronymSectionTokens(ReferenceBookHit hit) {
    final term = hit.matchedTerm;
    if (hit.matchRank != 3 || term == null) return const [];

    final termTokens = term.split(' ').where((t) => t.isNotEmpty).toList();
    final titleTokens = hit.titleMatchTokens;
    var start = termTokens.length;
    while (start > 0 && !titleTokens.contains(termTokens[start - 1])) {
      start--;
    }
    if (start == 0) return const [];
    return termTokens.sublist(start);
  }

  /// "חומ" ← "חושן משפט": צורת החלק המלאה, כפי שהיא ב-heRef, מתוך כינוי אחר
  /// של אותו ספר ("טור חושן משפט").
  List<String> _spelledOutSection(int bookId, List<String> section) {
    if (section.length != 1) return section;
    final terms = AcronymsCache.instance.getAcronymsForBook(bookId) ?? const [];
    for (final term in terms) {
      final words = _tokenize(term);
      for (var i = 1; i < words.length; i++) {
        final tail = words.sublist(i);
        if (hebrewAbbreviationMatchesWords(section.single, tail)) return tail;
      }
    }
    return section;
  }

  /// מיפוי bookId → השורה המדויקת שאליה מצביעה ההפניה, דרך אינדקס `line_ref`.
  ///
  /// שאילתה מאוגדת אחת לכל מפתח קנוני — לא פנייה לכל ספר מועמד. ריק כשאין
  /// הזרקה (בדיקות) או כשהמסד נבנה לפני האינדקס, ואז נשאר מסלול ה-TOC.
  /// מזהה שאילתת דיבור-המתחיל: סמן ד"ה אחרי שם הספר, ואחריו לפחות מילה אחת.
  /// מחזיר את ראש השאילתה (שם הספר וציון פנימי) ואת טקסט הדיבור.
  @visibleForTesting
  static ({List<String> headTokens, String prefix})?
  detectDibburQueryForTesting(
    List<String> tokens,
  ) => _detectDibburQuery(tokens);

  static ({List<String> headTokens, String prefix})? _detectDibburQuery(
    List<String> tokens,
  ) {
    for (var i = 1; i < tokens.length - 1; i++) {
      final markerLength = _dibburMarkerLength(tokens, i);
      if (markerLength == 0) continue;
      final tail = tokens.sublist(i + markerLength);
      if (tail.isEmpty) return null;
      return (headTokens: tokens.sublist(0, i), prefix: tail.join(' '));
    }
    return null;
  }

  /// אורך הסמן שמתחיל ב-[index], או 0 אם אין שם סמן. הגרשיים כבר הוסרו
  /// בנרמול, ולכן ד"ה הוא הטוקן "דה".
  static int _dibburMarkerLength(List<String> tokens, int index) {
    final token = tokens[index];
    if (token == 'דה' || token == 'דהמתחיל') return 1;
    if (token != 'דיבור' && token != 'דבור') return 0;
    if (index + 1 >= tokens.length) return 0;
    final next = tokens[index + 1];
    return (next == 'המתחיל' || next == 'מתחיל') ? 2 : 0;
  }

  /// דיבורי-המתחיל שתחילתם [prefix] בספרים שזוהו, ממופתחים לפי bookId.
  Future<Map<int, List<_Dibbur>>> _resolveDibburim(
    List<ReferenceBookHit> bookHits,
    String prefix,
  ) async {
    final resolve = resolveDibburim;
    if (resolve == null || prefix.isEmpty) return const {};

    final bookIds = <int>[
      for (final hit in bookHits)
        if (hit.bookId > 0 && hit.fileType != 'pdf') hit.bookId,
    ];
    if (bookIds.isEmpty) return const {};

    final searched = bookIds.take(_maxDibburBooks).toList();
    final rows = await _awaitCurrent(
      resolve(
        searched,
        prefix,
        containsBookIds: searched.take(_maxDibburContainsBooks).toList(),
      ),
    );

    final resolved = <int, List<_Dibbur>>{};
    for (final row in rows) {
      final display = (row['display'] as String?) ?? '';
      if (display.isEmpty) continue;
      (resolved[row['bookId'] as int] ??= []).add(
        (
          lineIndex: row['lineIndex'] as int,
          lineId: row['lineId'] as int? ?? 0,
          display: display,
        ),
      );
    }
    return resolved;
  }

  Future<Map<int, List<_ExactLine>>> _resolveExactLines(
    List<ReferenceBookHit> bookHits,
    Map<ReferenceBookHit, List<String>> remainingByHit, {
    int tokensAfterRange = 0,
  }) async {
    final resolve = resolveLineRefs;
    if (resolve == null) return const {};

    final bookIdsByKey = <String, List<int>>{};
    final bookIdsBySectionKey = <String, List<int>>{};
    for (final hit in bookHits) {
      if (hit.bookId <= 0 || hit.fileType == 'pdf') continue;
      // רכיב יחיד ("ישעיהו לב") הוא ברמת TOC — אין מה לחפש ברמת שורה.
      var remaining = remainingByHit[hit] ?? const <String>[];
      // טווח ("לב יא-יג") נפתח בתחילתו; המקף כבר נבלע בנרמול השאילתה.
      if (tokensAfterRange > 0 && remaining.length > tokensAfterRange) {
        remaining = remaining.sublist(0, remaining.length - tokensAfterRange);
      }
      if (remaining.length < 2) continue;
      final key = buildRefKey(remaining.join(' '));
      if (key != null) (bookIdsByKey[key] ??= []).add(hit.bookId);
      // החלק שבזנב ראש-התיבות ("טור חושן משפט") הוא חלק מה-heRef של השורה.
      final section = _spelledOutSection(
        hit.bookId,
        _acronymSectionTokens(hit),
      );
      if (section.isEmpty) continue;
      final sectionKey = buildRefKey([...section, ...remaining].join(' '));
      if (sectionKey != null) {
        (bookIdsBySectionKey[sectionKey] ??= []).add(hit.bookId);
      }
    }

    final resolved = <int, List<_ExactLine>>{};
    // מפתח עם החלק נפתר אחרון כדי שיגבר על המפתח בלעדיו.
    for (final byKey in [bookIdsByKey, bookIdsBySectionKey]) {
      for (final entry in byKey.entries) {
        final lines = await _awaitCurrent(resolve(entry.value, entry.key));
        lines.forEach((bookId, line) => resolved[bookId] = [line]);
      }
    }

    // שם החלק הושמט ("טור שט ג"): ההפניה עשויה להתקיים בכמה חלקים, וכל אחד
    // מוצע. רק לספרים שהמפתח המלא לא פתר.
    final resolvePartial = resolvePartialLineRefs;
    if (resolvePartial != null) {
      for (final entry in bookIdsByKey.entries) {
        final unresolved = [
          for (final id in entry.value)
            if (!resolved.containsKey(id)) id,
        ];
        if (unresolved.isEmpty) continue;
        final partialKey = buildPartialRefKey(entry.key)!;
        resolved.addAll(
          await _awaitCurrent(resolvePartial(unresolved, partialKey)),
        );
      }
    }
    return resolved;
  }

  /// מספר הטוקנים שאחרי סימן הטווח בשאילתה הגולמית — הנרמול הופך את המקף
  /// לרווח, ובלי הספירה הזו "לב יא-יג" היה נראה כהפניה תלת-רכיבית.
  int _tokensAfterRange(String rawQuery, List<String> queryTokens) {
    final dash = rawQuery.indexOf(_rangeDash);
    if (dash <= 0) return 0;
    final head = _tokenize(_normalizeForMatch(rawQuery.substring(0, dash)));
    final after = queryTokens.length - head.length;
    return after > 0 ? after : 0;
  }

  /// האם [tokens] הם שם-קטע ואחריו ציטוט דף ("בראשית דף לו") — הצורה שבה
  /// מציינים פרשה בזוהר ואת הדף שבתוכה.
  static bool _isSectionThenDafCitation(List<String> tokens) =>
      tokens.length >= 2 && parseDafCitation(tokens.sublist(1)) != null;

  /// סדר הספציפיות בתוך אותו ספר: שורת מקור מדויקת < TOC L1 < TOC L2 <
  /// AltToc < TOC L3+.
  static int _specificityRank(DbReferenceResult r) => findRefSpecificityRank(
    isSourceLine: r.isSourceLine,
    isAltToc: r.isAltToc,
    tocLevel: r.tocLevel,
  );

  /// האם כל [remainingTokens] הם מילים בשם הקטגוריה *הישירה* של הספר. רק
  /// העלה נבדק — segment אב ("הלכה", "מפרשים") משותף לאלפי ספרים והיה מחזיר
  /// כל אחד מהם. טוקן בן אות-שתיים הוא טוקן מיקום ולא שם קטגוריה.
  bool _remainingTokensAreLeafCategory(
    int bookId,
    List<String> remainingTokens,
  ) {
    if (remainingTokens.isEmpty) return false;
    if (remainingTokens.any((t) => t.length < 3)) return false;

    final resolver =
        getCategoryPathSync ??
        ReferenceBooksCache.instance.getCategoryPathForBookSync;
    final path = resolver(bookId);
    if (path == null || path.isEmpty) return false;

    final leaf = path.split(', ').last;
    final leafTokens = titleMatchTokens(_normalizeForMatch(leaf));
    return remainingTokens.every((qt) {
      if (leafTokens.contains(qt)) return true;
      final bare = titleTokenWithoutConjunction(qt, allowVav: true);
      return bare != null && leafTokens.contains(bare);
    });
  }

  List<String> _getRemainingTokens(
    List<String> queryTokens,
    List<String> titleTokens, {
    int stripLeadingTokensCount = 0,
    int prefixMatchTokensCount = 0,
  }) {
    final remaining = List<String>.from(queryTokens);

    if (stripLeadingTokensCount > 0) {
      final toRemove = stripLeadingTokensCount.clamp(0, remaining.length);
      remaining.removeRange(0, toRemove);
    }

    // בליעת-תחילית מותרת רק לטוקנים שהרכיבו את התאמת שם-הספר — טוקן מיקום
    // (סימן בן 4 אותיות כמו "תרלד") לעולם אינו חלק מה-phrase המוביל הזה.
    final prefixEligible = queryTokens.take(prefixMatchTokensCount).toSet();

    for (var ti = 0; ti < titleTokens.length; ti++) {
      final token = titleTokens[ti];
      var idx = remaining.indexOf(token);
      // אות-חיבור בכותרת שהמשתמש לא הקליד — ראו
      // [titleTokenWithoutConjunction].
      if (idx == -1) {
        final bare = titleTokenWithoutConjunction(token, allowVav: ti > 0);
        if (bare != null) idx = remaining.indexOf(bare);
      }
      // כתיב מקוצר של שם הספר: "ירמיה" מול "ירמיהו". רצפת 2 תווים —
      // כמו בחריג אות-החיבור, אות בודדת נשארת תמיד טוקן מיקום.
      if (idx == -1 && prefixEligible.isNotEmpty) {
        idx = remaining.indexWhere(
          (t) =>
              t.length >= 2 &&
              prefixEligible.contains(t) &&
              token.startsWith(t),
        );
      }
      if (idx != -1) {
        remaining.removeAt(idx);
      }
    }

    return remaining;
  }

  List<DbReferenceResult> _dedupeRefs(List<DbReferenceResult> results) {
    final seen = <String>{};
    final out = <DbReferenceResult>[];

    for (final r in results) {
      // Deduplicate by (bookId, source, title, isPdf [, filePath]) +
      // segment, וגם + reference:
      //   - title|segment|isPdf — שני TOC/AltToc שמובילים לאותה שורה באותו ספר
      //     הם כפילות, ללא תלות בפורמט ה-reference
      //     ("בראשית תולדות עליה ב" מול "תולדות עליה ב").
      //   - bookId + source — שני ספרים *שונים* (למשל ספר רשמי וספר אישי,
      //     או שני רשמיים) בעלי אותה כותרת *אינם* כפילות; מרחבי ה-id של
      //     המסדים נפרדים, ובלעדיהם מפתח אחיד היה מוחק את אחד מהם משרירותיות.
      //   - filePath נוסף **רק** עבור FS PDFs (`bookId == -1`): לכולם אותו
      //     bookId שלילי, וההבדלה היחידה ביניהם היא הקובץ עצמו. שני קבצי PDF
      //     שונים מהדיסק עם אותה כותרת חייבים לשרוד את ה-dedupe. עבור
      //     תוצאות DB אנחנו דווקא רוצים שה-filePath *לא* יבדיל — מסלול
      //     ה-global AltToc fallback מייצר תוצאה עם filePath ריק, וצריך
      //     להתמזג עם תוצאת ה-per-book של אותו bookId שיש לה filePath ידוע.
      final filePathKey = r.bookId == -1 ? r.filePath : '';
      final bookKey =
          '${r.bookId}|${r.source.wireKey}|${r.title}|${r.isPdf}|$filePathKey';
      // אותה כתובת מלאה באותו ספר — גם כשה-segment שונה (כותרת "סעיף ג" ב-TOC
      // מול עלה "סעיף ג" במבנה הסעיפים המסונתז שמצביע לשורת התוכן, issue #1249).
      // למשתמש שתי השורות זהות; הראשונה (TOC) נשמרת.
      final newSegment = seen.add('$bookKey|${r.segment}');
      final newReference = seen.add('$bookKey|ref:${r.reference}');
      if (newSegment && newReference) {
        out.add(r);
      }
    }

    return out;
  }

  List<DbReferenceResult> _rankResults(
    List<DbReferenceResult> results,
    List<String> queryTokens, {
    Map<(int, String), int> bookMatchRanks = const {},
    Set<DbReferenceResult> directMatches = const {},
    bool preserveSubstringTail = false,
  }) {
    if (results.length < 2) return results;

    final query = queryTokens.join(' ');
    final needsTokenWiseRanking = queryTokens.length >= 2;
    // ה-dedupe עשוי לשמור תוצאת ספר שהופיעה לפני AltToc גלובלי באותו מקטע.
    // גם במקרה הזה התוצאה ששרדה מייצגת התאמה ישירה, ולא שם ספר מקורב בלבד.
    final directSegments = {
      for (final r in directMatches)
        (r.bookId, r.source, r.title, r.isPdf, r.segment),
    };
    final directReferences = {
      for (final r in directMatches)
        (r.bookId, r.source, r.title, r.isPdf, r.reference),
    };

    // זיהוי סגנון ציון גמרא: הטוקן האחרון הוא "א" או "ב" + לפחות עוד טוקן.
    // כשמזוהה — ערכים שה-reference שלהם מכיל "דף" יקבלו עדיפות על פני ערכים
    // שאינם מכילים "דף" (כגון משנה), כדי ש-"שבת עא ב" יציג גמרא לפני משנה.
    final isDafCitation = queryLooksDafCitation(queryTokens);

    // resolver של categoryPath לסיווג tier יסוד. בייצור — ReferenceBooksCache;
    // בטסטים — דרך ה-injection `getCategoryPathSync`.
    final pathResolver =
        getCategoryPathSync ??
        ReferenceBooksCache.instance.getCategoryPathForBookSync;

    // Decorate: כל מפתחות המיון מחושבים פעם אחת לכל תוצאה.
    final decorated = List<_RankKey>.generate(results.length, (i) {
      final r = results[i];
      final normTitle = _normalize(r.title);
      // citationMatch=true  → מתאים לסגנון הציון שהוזן
      // citationMatch=false → אינו מתאים (ירד מתחת לספרים שמתאימים)
      final citationMatch = findRefCitationMatch(isDafCitation, r.reference);
      // tier יסוד: 1=מקרא ... 10=שו"ע, null=מפרש/ספרות עזר.
      // ספר שאינו רשמי: ה-bookId שלו במרחב של מסד אחר ועלול להתנגש במזהה
      // רשמי — שליפת נתיב לפיו הייתה מסווגת אותו לפי ספר זר.
      final categoryPath = (r.bookId > 0 && r.source.isOfficial)
          ? pathResolver(r.bookId)
          : null;
      final foundationalTier = FoundationalBookClassifier.classify(
        categoryPath,
        r.title,
      );
      final era = categoryPath == null
          ? CommentaryEra.other
          : ReferenceBooksCache.eraFromCategoryPath(categoryPath);
      return _RankKey(
        result: r,
        normTitle: normTitle,
        fuzzyBookMatch:
            r.source.isOfficial &&
            !r.isSourceLine &&
            !directMatches.contains(r) &&
            !directSegments.contains((
              r.bookId,
              r.source,
              r.title,
              r.isPdf,
              r.segment,
            )) &&
            !directReferences.contains((
              r.bookId,
              r.source,
              r.title,
              r.isPdf,
              r.reference,
            )) &&
            bookMatchRanks[(r.bookId, r.bookId > 0 ? '' : r.filePath)] ==
                ReferenceBooksCache.fuzzyMatchRank,
        exactMatch: normTitle == query,
        startsWithMatch: normTitle.startsWith(query),
        titleTokens: needsTokenWiseRanking ? _tokenize(normTitle) : const [],
        citationMatch: citationMatch,
        foundationalTier: foundationalTier,
        era: era,
      );
    });

    // משווה שתי תוצאות לפי **רלוונטיות** בלבד (שכבות 1-8). שובר-השוויון
    // האלפביתי/אורך-ה-reference אינו רלוונטיות אלא סדר-תצוגה, ולכן אינו כאן —
    // כך ה-cap המודע-רלוונטיות לא יחתוך באמצע קבוצת תוצאות שווֹת-רלוונטיות.
    int compareRelevance(_RankKey a, _RankKey b) {
      // התאמה מקורבת בשם הספר תמיד מתחת להתאמה מילולית או לכינוי מדויק.
      if (a.fuzzyBookMatch != b.fuzzyBookMatch) {
        return a.fuzzyBookMatch ? 1 : -1;
      }

      // 1. התאמה מלאה של שם הספר
      if (a.exactMatch != b.exactMatch) return a.exactMatch ? -1 : 1;

      // 2. התאמה של התחלת שם הספר
      if (a.startsWithMatch != b.startsWithMatch) {
        return a.startsWithMatch ? -1 : 1;
      }

      // 3. התאמת מילים בודדות (מילה שנייה ואילך)
      // טוקנים שהם אות בודדת (מספר פרק/פסוק/דף) מדולגים — הם אינם חלק משם הספר.
      if (needsTokenWiseRanking) {
        for (int i = 1; i < queryTokens.length; i++) {
          final queryToken = queryTokens[i];
          if (queryToken.length == 1) {
            continue; // ← skip single-char location tokens
          }
          final aHasMatch =
              i < a.titleTokens.length &&
              a.titleTokens[i].startsWith(queryToken);
          final bHasMatch =
              i < b.titleTokens.length &&
              b.titleTokens[i].startsWith(queryToken);
          if (aHasMatch != bHasMatch) return aHasMatch ? -1 : 1;
        }
      }

      // 4. התאמה לסגנון הציון (גמרא/משנה/תנ"ך)
      if (a.citationMatch != b.citationMatch) return a.citationMatch ? -1 : 1;

      // 5. ספר יסוד — מקרא → משנה → בבלי → ירושלמי → מדרש → זוהר →
      // רמב"ם → טור → שו"ע. ספרים שאינם יסוד (מפרשים, ספרות עזר וכו')
      // יורדים מתחת לכל היסודות. מופיע **לפני** orderIndex כדי ש"שבת יג"
      // יחזיר את הספרים עצמם (משנה, בבלי, ירושלמי, רמב"ם) ולא את מפרשיהם.
      final aTier = a.foundationalTier;
      final bTier = b.foundationalTier;
      if (aTier != bTier) {
        if (aTier == null) return 1; // a לא יסוד → b קודם
        if (bTier == null) return -1; // a יסוד, b לא → a קודם
        return aTier.compareTo(bTier); // שניהם יסודות — tier קטן יותר ראשון
      }

      // 6. סדר הדורות בין מפרשים (ראשונים → אחרונים → מחברי זמננו) — לפי
      // תיוג הדור בנתיב הקטגוריה. orderIndex לבדו מערבב דורות מענפי-עץ שונים.
      if (aTier == null && a.era != b.era) {
        return a.era.order.compareTo(b.era.order);
      }

      // 7. סדר ספר בספרייה — ספרים בסדר הספרייה (בתוך אותו tier יסוד או
      // אותו דור, מיון לפי orderIndex).
      final orderCmp = a.result.orderIndex.compareTo(b.result.orderIndex);
      if (orderCmp != 0) return orderCmp;

      // 8. סדר: TOC L1 < TOC L2 < AltToc < TOC L3+
      // AltToc (כותרות-משנה) מופיע אחרי הכותרות הבסיסיות (רמה 2) אך לפני הכותרות הפנימיות (רמה 3+).
      final aRank = _specificityRank(a.result);
      final bRank = _specificityRank(b.result);
      if (aRank != bRank) return aRank.compareTo(bRank);

      return 0;
    }

    decorated.sort((a, b) {
      final rel = compareRelevance(a, b);
      if (rel != 0) return rel;
      return compareFindRefDisplayOrder(
        a.result.reference,
        a.result.segment,
        b.result.reference,
        b.result.segment,
      );
    });

    // cap מודע-רלוונטיות: חותכים ב-[_baseResultCap], אך מרחיבים לכל מי שחולק
    // את מפתח-הרלוונטיות של התוצאה האחרונה שבחיתוך — כך שתוצאות שווֹת-רלוונטיות
    // מוצגות יחד. הרשימה נעצרת רק כשמגיעים לתוצאה *פחות* רלוונטית.
    if (decorated.length <= _baseResultCap) {
      return decorated.map((d) => d.result).toList();
    }
    final boundary = decorated[_baseResultCap - 1];
    var end = _baseResultCap;
    while (end < decorated.length &&
        compareRelevance(decorated[end], boundary) == 0) {
      end++;
    }
    if (end > _maxResultCap) {
      debugPrint(
        '[FindRef] relevance-tie cap truncated ${decorated.length} → $_maxResultCap',
      );
      end = _maxResultCap;
    }

    final capped = [for (var i = 0; i < end; i++) decorated[i]];

    // issue #839: התאמות תת-מחרוזת מדורגות אחרי כל התאמות-התחילית, וחיתוך
    // שגבולו בתוכן מחק אותן כליל — מובטחת להן מכסה בזנב, בלי לשנות דירוג.
    if (preserveSubstringTail && end < decorated.length) {
      bool isSubstringMatch(_RankKey d) =>
          !d.startsWithMatch && d.normTitle.contains(query);
      var quota = _substringTailQuota - capped.where(isSubstringMatch).length;
      for (
        var i = end;
        i < decorated.length && quota > 0 && capped.length < _maxResultCap;
        i++
      ) {
        if (isSubstringMatch(decorated[i])) {
          capped.add(decorated[i]);
          quota--;
        }
      }
    }

    return [for (final d in capped) d.result];
  }

  String _normalize(String? s) =>
      (s ?? '').trim().toLowerCase().replaceAll(_whitespaceRun, ' ');

  String _normalizeForMatch(String input) => normalizeForFindRefMatch(input);

  List<String> _tokenize(String text) => text
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  /// בודק אם [phraseTokens] מופיעים כסיקוונס רציף ב-[titleTokens], כאשר
  /// כל title-token במיקום שלו מתחיל ב-phrase-token המקביל (startsWith).
  ///
  /// מקבל מיקום התחלה כלשהו, לא רק 0 — כדי שכותרת כמו "פני יהושע על בבא קמא"
  /// תתפוס שאילתה "בבא קמא" (start=3). שמירה על רציפות מונעת התאמות חוצות-
  /// ענפים: שאילתה "בבא קמא" לא תתפוס "פסקי בבא בתרא סימן קמא" כי "בבא"
  /// ו"קמא" אינם רצופים שם.
  static bool _phraseAppearsAsTokens(
    List<String> titleTokens,
    List<String> phraseTokens,
  ) {
    if (phraseTokens.isEmpty) return true;
    if (phraseTokens.length > titleTokens.length) return false;
    final maxStart = titleTokens.length - phraseTokens.length;
    for (var start = 0; start <= maxStart; start++) {
      var ok = true;
      for (var i = 0; i < phraseTokens.length; i++) {
        if (!titleTokens[start + i].startsWith(phraseTokens[i])) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }
}

/// מפתחות מיון מחושבים מראש לדירוג תוצאות (decorate-sort-undecorate).
/// מאפשר ל-comparator להישאר זול — בלי נורמליזציה/טוקניזציה חוזרת.
class _RankKey {
  final DbReferenceResult result;
  final String normTitle;
  final bool fuzzyBookMatch;
  final bool exactMatch;
  final bool startsWithMatch;
  final List<String> titleTokens;

  /// true = ה-reference מתאים לסגנון הציון שהוזן (למשל: מכיל "דף" כשמדובר
  /// בציון גמרא). false = אינו מתאים וירד בדירוג.
  final bool citationMatch;

  /// tier "ספר יסוד" של הספר: 1=מקרא, 2=משנה, ..., 10=שו"ע. `null` עבור
  /// ספרים שאינם יסוד (מפרשים וכד'). ראה [FoundationalBookClassifier.classify].
  final int? foundationalTier;

  /// דור הספר לפי נתיב הקטגוריה — ממיין מפרשים בסדר הדורות.
  final CommentaryEra era;

  const _RankKey({
    required this.result,
    required this.normTitle,
    required this.fuzzyBookMatch,
    required this.exactMatch,
    required this.startsWithMatch,
    required this.titleTokens,
    required this.citationMatch,
    required this.foundationalTier,
    required this.era,
  });
}

typedef _ExactLine = ({int lineIndex, int lineId, String? heRef});

typedef _SecondaryTocRequest = ({
  int bookId,
  String bookTitle,
  List<String> queryTokens,
});

typedef _Dibbur = ({int lineIndex, int lineId, String display});

/// מה נקבע לספר בשלב התכנון של חיפוש תוכן העניינים.
class _TocPlan {
  const _TocPlan._(
    this.requestIndex, {
    this.isOverCap = false,
    this.isPdfOutline = false,
  });

  const _TocPlan.request(int index) : this._(index);

  static const none = _TocPlan._(null);
  static const overCap = _TocPlan._(null, isOverCap: true);
  static const pdfOutline = _TocPlan._(null, isPdfOutline: true);

  /// מקומו של הספר בבקשת התוכן המאוגדת.
  final int? requestIndex;
  final bool isOverCap;
  final bool isPdfOutline;
}
