import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/find_ref/book_name_match.dart';
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

/// ספר ממסד משני עם השם המנורמל — מחושב פעם אחת בטעינה, לא בכל הקלדה.
/// [folderNameTokens] [i] = סיומת שרשרת התיקיות מ-i ואחריה הכותרת.
class _SecondaryBook {
  _SecondaryBook(this.record)
    : normalizedTitle = _normalizedName(record.title),
      folderNameTokens = [
        for (var i = 0; i < record.folderTitles.length; i++)
          _tokens(
            _normalizedName(
              '${record.folderTitles.sublist(i).join(' ')} ${record.title}',
            ),
          ),
      ];

  final _UserBookRecord record;
  final String normalizedTitle;
  final List<List<String>> folderNameTokens;

  late final List<String> titleTokens = _tokens(normalizedTitle);

  static String _normalizedName(String name) {
    FindRefRepository.debugSecondaryNameNormalizations++;
    return normalizeForFindRefMatch(name);
  }

  static List<String> _tokens(String normalized) =>
      normalized.split(' ').where((t) => t.isNotEmpty).toList(growable: false);
}

/// ספרי מסד משני ומנוע ההתאמה שלהם — אותו מנוע של הקטלוג הרשמי, נבנה פעם
/// אחת לכל גרסת תוכן של המסד.
class _SecondaryIndex {
  _SecondaryIndex(this.books, {Map<int, List<String>>? acronyms})
    : byId = {for (final book in books) book.record.id: book},
      titles = BookTitleIndex(
        books: [
          for (final book in books)
            BookCacheEntry(
              id: book.record.id,
              title: book.record.title,
              filePath: book.record.filePath,
              fileType: book.record.fileType,
              categoryId: 0,
              orderIndex: book.record.orderIndex,
            ),
        ],
        normalizedTitles: {
          for (final book in books) book.record.id: book.normalizedTitle,
        },
        acronymsOf: acronyms == null ? null : (id) => acronyms[id],
      );

  final List<_SecondaryBook> books;
  final Map<int, _SecondaryBook> byId;
  final BookTitleIndex titles;

  static Future<_SecondaryIndex> build(
    List<_SecondaryBook> books, {
    Map<int, List<String>>? acronyms,
  }) async {
    if (books.length < FindRefRepository.secondaryIndexIsolateThreshold) {
      return _SecondaryIndex(books, acronyms: acronyms);
    }
    return Isolate.run(() => _SecondaryIndex(books, acronyms: acronyms));
  }
}

final Object _searchGenerationZoneKey = Object();

final RegExp _rangeDash = RegExp('[-–־]');

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
  final Future<List<Map<String, dynamic>>> Function(
    GlobalAltTocRequest request,
  )?
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
  /// הטווח המחושב להם שונה. LRU: סדר ההכנסה הוא סדר השימוש.
  final Map<String, List<DbCommentatorEntry>> _commentatorsCache = {};

  /// כ-15 שורות גלויות לכל תוצאה — מספיק לעשרות חיפושים אחרונים.
  static const int _maxCommentatorsCacheEntries = 500;

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

  static const int _substringTailQuota = findRefSubstringTailQuota;

  /// מילות-דור של טוקן יחיד שמפעילות את מצב "דור + נושא".
  static const Map<String, CommentaryEra> _singleTokenEras = {
    'ראשונים': CommentaryEra.rishonim,
    'אחרונים': CommentaryEra.acharonim,
  };

  /// מפתח לרשומות המפרשים של [ref]: תוצאות שחולקות אותו מחשבות אותו טווח.
  static String commentatorsKeyFor(DbReferenceResult ref) =>
      '${ref.bookId}:${ref.sourceLineId}:${ref.isAltToc ? 1 : 0}'
      ':${ref.isSourceLine ? 1 : 0}:${ref.tocLevel}:${ref.segment.toInt()}';

  /// קאש שטוח של כל ערכי ה-AltToc על פני כל הספרים. נבנה lazy בקריאה
  /// הראשונה ל-fallback הגלובלי, ומשרת את כל ה-sessions שלאחר מכן.
  /// השדה נשמר ברמת ה-instance של [FindRefRepository] (singleton באפליקציה).
  List<AltTocFlatEntry>? _altTocFlatCache;

  /// קאש מזהי הספרים בעלי מבנה AltToc (ראה [getAltStructureBookIds]).
  Set<int>? _altBookIdsCache;

  /// מפתחות הדירוג של ספרים רשמיים ונתיב הקטגוריה שממנו חושבו.
  final Map<int, ({String? path, String title, FindRefBookRank rank})>
  _bookRanks = {};

  ({
    Set<int> ids,
    int generation,
    Map<int, ({String title, FindRefBookRank rank})> ranks,
  })?
  _altBookRanksCache;

  /// הספרים האישיים (user_books.db). נבנה מחדש כשתוכן המסד השתנה (ראו
  /// [_userBooksJob]), ב-[clearCaches] ובסגירת המסד.
  _SecondaryIndex? _userBooksIndex;

  /// גרסת התוכן שממנה נבנה [_userBooksIndex].
  _UserBooksVersion? _userBooksContentVersion;

  /// ריענון הספרים האישיים שרץ כעת, משותף לכל הקוראים.
  Future<_SecondaryIndex>? _userBooksRefresh;

  /// מתחלף באיפוס, כדי שריענון שהתחיל לפניו לא ישמור אינדקס ישן.
  int _userBooksEpoch = 0;

  @visibleForTesting
  Future<void>? get debugUserBooksRefresh => _userBooksRefresh;

  @visibleForTesting
  Object? get debugUserBooksIndex => _userBooksIndex;

  /// נתיב user_books.db, לשאילתות ה-TOC ב-worker; נקבע בטעינת הרשימה.
  String? _userBooksDbPath;

  /// גרסת החיבור של ה-worker ל-user_books.db — מתחלפת בכל [clearCaches].
  int _userBooksVersion = 0;

  /// קאש ספרי המסדים המצורפים לפי slug, עם רשומת המסד והכינויים שמהם נבנה.
  final Map<
    String,
    ({
      AttachedLibrary library,
      Map<int, List<String>>? acronyms,
      _SecondaryIndex index,
    })
  >
  _attachedBooksCache = {};

  /// מעל מספר ספרים זה, מנוע ההתאמה של מסד משני נבנה ב-isolate.
  @visibleForTesting
  static int secondaryIndexIsolateThreshold = 1000;

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
    _bookRanks.clear();
    _altBookRanksCache = null;
    _dropUserBooks();
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

  void _dropUserBooks() {
    _userBooksIndex = null;
    _userBooksContentVersion = null;
    _userBooksRefresh = null;
    _userBooksEpoch++;
  }

  /// הספרים האישיים ומנוע ההתאמה שלהם — דרך [getAllUserBooks] (בדיקות,
  /// פעם אחת עד [clearCaches]) או מ-`user_books.db` דרך ה-worker.
  ///
  /// כשיש אינדקס הוא מוחזר מיד והבדיקה אם המסד השתנה רצה ברקע: המתנה לה
  /// הייתה מעכבת כל הקלדה מאחורי עבודה כבדה בתור הסדרתי של ה-worker.
  Future<_SecondaryIndex> _loadUserBooks() async {
    final injected = getAllUserBooks;
    if (injected != null) {
      final cached = _userBooksIndex;
      if (cached != null) return cached;
      final epoch = _userBooksEpoch;
      final records = await injected();
      final index = await _SecondaryIndex.build([
        for (final record in records) _SecondaryBook(record),
      ]);
      // נשמר גם כשהחיפוש בוטל בינתיים — החיפוש הבא ישתמש בו.
      if (epoch == _userBooksEpoch) _userBooksIndex = index;
      throwIfSearchCancelled();
      return index;
    }

    // הפתיחה דרך ה-holder מריצה את המיגרציות לפני שה-worker קורא מהקובץ.
    final userRepo = await _awaitCurrent(
      openUserBooksRepository?.call() ??
          UserBooksDatabaseHolder.instance.repository,
    );
    final path = userRepo.database.path;
    _userBooksDbPath = path;
    UserBooksDatabaseHolder.instance.addCloseListener(_resetSecondaryWorker);
    final cached = _userBooksIndex;
    if (cached != null) {
      _revalidateUserBooks(path);
      return cached;
    }
    return _awaitCurrent(_refreshUserBooks(path, background: false));
  }

  /// בדיקת רקע אם user_books.db השתנה; כשל אינו נוגע באינדקס הקיים.
  void _revalidateUserBooks(String path) {
    unawaited(
      _refreshUserBooks(path, background: true).then<void>(
        (_) {},
        onError: (Object e) =>
            debugPrint('[FindRef] personal books revalidation failed: $e'),
      ),
    );
  }

  /// קורא מה-worker את הספרים האישיים אם התוכן השתנה, ובונה את האינדקס.
  /// האינדקס נשמר גם כשהחיפוש שהתחיל את הקריאה כבר בוטל.
  Future<_SecondaryIndex> _refreshUserBooks(
    String path, {
    required bool background,
  }) {
    final running = _userBooksRefresh;
    if (running != null) return running;
    final epoch = _userBooksEpoch;
    final known = _userBooksIndex == null ? null : _userBooksContentVersion;
    late final Future<_SecondaryIndex> refresh;
    refresh = () async {
      try {
        final loaded = await AttachedFindRefWorker.instance.run(
          path,
          immutable: false,
          version: '$_userBooksVersion',
          job: _userBooksJob(known),
          background: background,
        );
        final current = _userBooksIndex;
        final books = loaded.books;
        final index = books == null && current != null
            ? current
            : await _SecondaryIndex.build(books ?? const []);
        if (epoch == _userBooksEpoch) {
          _userBooksIndex = index;
          _userBooksContentVersion = loaded.version;
        }
        return index;
      } finally {
        if (identical(_userBooksRefresh, refresh)) _userBooksRefresh = null;
      }
    }();
    return _userBooksRefresh = refresh;
  }

  /// מרענן ברקע את הספרים האישיים בכל המופעים — אחרי כתיבה מתוך האפליקציה.
  static void revalidateUserBooks() {
    for (final repo in _liveInstances) {
      final path = repo._userBooksDbPath;
      if (path != null && repo._userBooksIndex != null) {
        repo._revalidateUserBooks(path);
      }
    }
  }

  /// הקאש הגלובלי של ה-AltToc במסלול המקומי (בלי worker), נטען פעם אחת.
  /// כשל מחזיר רשימה ריקה, כדי שהמסלול הפר-ספר ימשיך.
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
      // הקאש לא נקבע לריק: בכשל זמני (DB נבנה מחדש, נעילה רגעית) השאילתה
      // הבאה תנסה שוב.
      return const [];
    }
  }

  /// מוסיף ל-[results] ערכי AltToc מהקאש הגלובלי שכל טוקני השאילתה מופיעים
  /// בהם — רק מה שהדירוג יכול להציג ([selectGlobalAltTocMatches]).
  /// [maxRefTokens] (מסלול מילה אחת) מגביל את אורך הערך — רק כותרות קצרות
  /// ("נח", "פרשת נח") נכללות, כדי לא להציף בצאצאים ("נח עליה ב").
  Future<void> _addGlobalAltTocMatches(
    List<DbReferenceResult> results,
    List<String> queryTokens, {
    int? maxRefTokens,
    FindRefVisibility? visibility,
  }) async {
    try {
      final occupied = <AltTocResultKey>[];
      final replaceable = <AltTocResultKey>[];
      for (final r in results) {
        if (!r.source.isOfficial || r.isPdf || r.bookId <= 0) continue;
        // התאמה חלקית אינה תופסת את השורה: `_dedupeRefs` מחליף אותה בהתאמה מלאה.
        (r.isPartialTocMatch ? replaceable : occupied).add((
          bookId: r.bookId,
          title: r.title,
          segment: r.segment,
          reference: r.reference,
        ));
      }
      final singleWord = maxRefTokens != null;
      final request = GlobalAltTocRequest(
        queryTokens: queryTokens,
        maxRefTokens: maxRefTokens,
        occupied: occupied,
        replaceable: replaceable,
        hiddenBookIds: visibility?.hiddenOfficialTextIds ?? const {},
        bookRanks: await _altBookRanks(),
        perBookCap: globalAltTocPerBookCap(
          queryTokens,
          singleWord: singleWord,
        ),
        substringQuota: singleWord ? _substringTailQuota : 0,
      );

      final searchFn = searchAltTocFlatEntries;
      if (searchFn != null) {
        for (final r in await searchFn(request)) {
          if (request.hiddenBookIds.contains(r['bookId'])) continue;
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
      final dafCitation = parseDafCitationFromDafToken(queryTokens);
      // מילות ההקשר נדרשות גם כשמספר הדף והעמוד נבדקים מיקומית.
      final matches = [
        for (final entry in flat)
          if (altTocFlatMatches(
            entry.refTokens,
            queryTokens,
            maxRefTokens: maxRefTokens,
            dafCitation: dafCitation,
          ))
            entry,
      ];
      final selected = selectGlobalAltTocMatches(
        matches,
        request: request,
        bookIdOf: (e) => e.bookId,
        bookTitleOf: (e) => e.bookTitle,
        orderIndexOf: (e) => e.bookOrderIndex,
        segmentOf: (e) => e.segment,
        referenceOf: (e) => qualifyAltTocReference(e.bookTitle, e.reference),
        rankOf: _officialBookRank,
      );
      for (final entry in selected) {
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

  /// דירוג הספרים בעלי AltToc, לבחירה ב-worker. ספר בלי כותרת ידועה חסר כאן,
  /// וה-worker שולח אותו במלואו. בתוך דור של [ReferenceBooksCache] הטבלה
  /// קבועה, וכך היא נשלחת ל-worker פעם אחת.
  Future<Map<int, ({String title, FindRefBookRank rank})>>
  _altBookRanks() async {
    final ids = await _getAltBookIds();
    if (ids == null) return const {};
    final generation = getCategoryPathSync == null
        ? ReferenceBooksCache.instance.generation
        : null;
    final cached = _altBookRanksCache;
    if (generation != null &&
        cached != null &&
        identical(cached.ids, ids) &&
        cached.generation == generation) {
      return cached.ranks;
    }
    final books = BooksCache.instance;
    final ranks = {
      for (final id in ids)
        if (books.getBookById(id)?.title case final title?)
          id: (title: title, rank: _officialBookRank(id, title)),
    };
    if (generation != null) {
      _altBookRanksCache = (ids: ids, generation: generation, ranks: ranks);
    }
    return ranks;
  }

  /// מפתחות הדירוג של ספר רשמי, לפי נתיב הקטגוריה העדכני שלו. נשמרים בין
  /// שאילתות: ה-AltToc הגלובלי מביא אלפי שורות מעשרות ספרים בלבד.
  FindRefBookRank _officialBookRank(int bookId, String title) {
    final path =
        (getCategoryPathSync ??
        ReferenceBooksCache.instance.getCategoryPathForBookSync)(bookId);
    final cached = _bookRanks[bookId];
    if (cached != null && cached.path == path && cached.title == title) {
      return cached.rank;
    }
    final rank = _bookRankFor(path, title);
    _bookRanks[bookId] = (path: path, title: title, rank: rank);
    return rank;
  }

  static FindRefBookRank _bookRankFor(String? categoryPath, String title) => (
    foundationalTier: FoundationalBookClassifier.classify(categoryPath, title),
    eraOrder:
        (categoryPath == null
                ? CommentaryEra.other
                : ReferenceBooksCache.eraFromCategoryPath(categoryPath))
            .order,
  );

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

    final cacheKey = commentatorsKeyFor(ref);
    await _currentVisibility();
    final cached = _commentatorsCache.remove(cacheKey);
    if (cached != null) return _commentatorsCache[cacheKey] = cached;

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
      _cacheCommentators(cacheKey, const []);
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
    _cacheCommentators(cacheKey, sorted);
    return sorted;
  }

  void _cacheCommentators(String key, List<DbCommentatorEntry> entries) {
    _commentatorsCache
      ..remove(key)
      ..[key] = entries;
    if (_commentatorsCache.length > _maxCommentatorsCacheEntries) {
      _commentatorsCache.remove(_commentatorsCache.keys.first);
    }
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
    return _runSearch(ref, includePersonalBooks: includePersonalBooks);
  }

  /// כמו [findRefs] בלי לבטל איתורים קודמים — לקוראים שמריצים כמה במקביל
  /// (תוספים). עדיין מתבטל ב-[cancelPendingSearch], ב-[findRefs] וב-dispose.
  Future<List<DbReferenceResult>> findRefsConcurrently(
    String ref, {
    bool includePersonalBooks = false,
  }) {
    if (_disposed) return Future.error(const FindRefQueryCancelled());
    return _runSearch(ref, includePersonalBooks: includePersonalBooks);
  }

  Future<List<DbReferenceResult>> _runSearch(
    String ref, {
    required bool includePersonalBooks,
  }) {
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
    final query = _parseQuery(rawRef);
    if (query == null) return const [];
    final queryTokens = query.tokens;

    final SeforimRepository? repository =
        SqliteDataProvider.instance.repository;
    if (repository == null && getTocEntriesForReference == null) {
      debugPrint('[FindRef] Database not initialized');
      await _throwLibraryUnavailable();
    }
    await _ensureReferenceBooksLoaded();

    final visibility = await _currentVisibility();
    // בדיקת הגרסה ב-worker רצה בזמן הזיהוי הרשמי, ולא אחריו.
    final userBooks = includePersonalBooks
        ? (_loadUserBooks()..ignore())
        : null;

    // מצב "דור + נושא": "ראשונים סנהדרין" / "סנהדרין ראשונים" → כל הראשונים על
    // סנהדרין. בלי תוצאות — נופלים למסלול הרגיל.
    final eraQuery = _detectEraQuery(queryTokens);
    if (eraQuery != null) {
      final eraResults = await _awaitCurrent(
        _findByEra(eraQuery.era, eraQuery.topicTokens, visibility),
      );
      if (eraResults.isNotEmpty) return eraResults;
    }

    final books = _BookSearch(
      injected: searchReferenceBooks,
      queryTokens: queryTokens,
      visibility: visibility,
    );
    final detection = _detectBooks(books, queryTokens);
    final search = _FindRefSearch(
      rawQuery: query.ref,
      queryTokens: queryTokens,
      isDibburQuery: query.dibbur != null,
      visibility: visibility,
      books: books,
      detection: detection,
      bookMatchRanks: _bookMatchRanks(detection.hits),
      dibburim: query.dibbur == null
          ? const <int, List<_Dibbur>>{}
          : await _awaitCurrent(
              _resolveDibburim(detection.hits, query.dibbur!.prefix),
            ),
      includePersonalBooks: includePersonalBooks,
      userBooks: userBooks,
    );

    return queryTokens.length == 1
        ? _singleWordResults(search)
        : _multiWordResults(search, repository);
  }

  /// הטוקנים המנורמלים של השאילתה; `null` כשלא נשאר בה דבר לחפש.
  ({
    String ref,
    List<String> tokens,
    ({List<String> headTokens, String prefix})? dibbur,
  })?
  _parseQuery(String rawRef) {
    // לפני הנרמול: הוא מוחק את הגרשיים, ו"ע"א" נהפך למספר הדף "עא".
    final ref = expandQueryAmudMarks(rawRef);
    final cleanedQuery = _normalizeForMatch(ref);
    if (cleanedQuery.isEmpty) return null;
    final tokens = _tokenize(cleanedQuery);
    if (tokens.isEmpty) return null;

    // "תוספות ברכות ד"ה מאימתי": הזנב שאחרי הסמן נפתר מול `line_dh`, והראש
    // ממשיך במסלול הרגיל — כאילו הוקלד שם הספר לבדו.
    final dibbur = _detectDibburQuery(tokens);
    return (ref: ref, tokens: dibbur?.headTokens ?? tokens, dibbur: dibbur);
  }

  Future<void> _ensureReferenceBooksLoaded() async {
    bool cacheLoaded() =>
        isReferenceBooksCacheLoaded?.call() ??
        ReferenceBooksCache.instance.isLoaded;
    if (cacheLoaded()) return;
    await _awaitCurrent(
      warmUpReferenceBooksCache?.call() ??
          ReferenceBooksCache.instance.warmUp(),
    );
    // ה-warmUp חוזר בלי לזרוק גם כשהוא נכשל (DB נעול, יציאה ממצב שינה).
    // בלי הבדיקה השנייה נחפש על מטמון ריק ונדווח "לא נמצא ספר".
    if (!cacheLoaded()) await _throwLibraryUnavailable();
  }

  /// אילו ספרים השאילתה מזכירה, ובכמה מטוקני הראש השתמש שם הספר.
  _BookDetection _detectBooks(_BookSearch books, List<String> queryTokens) {
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

    for (var n = books.maxPhraseTokens; n >= 1; n--) {
      final phrase = queryTokens.take(n).join(' ');
      final hits = books.search(phrase, limit: books.bookSearchLimit);
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
      for (final hit in books.search(queryTokens.first, limit: 50)) {
        if (!seen.add((hit.bookId, hit.filePath))) continue;
        secondaryHits.add(hit);
        secondaryPhraseTokenCount[hit] = 1;
      }
    }

    // ה-secondary בסוף, כך שיופיעו אחרי ה-primary בדירוג — גם כשאין primary.
    if (secondaryHits.isNotEmpty) {
      bookHits = [...bookHits, ...secondaryHits];
    }
    return (
      hits: bookHits,
      phraseTokenCount: bookQueryTokenCount,
      secondaryPhraseTokenCount: secondaryPhraseTokenCount,
    );
  }

  /// דרגת ההתאמה של שם הספר חייבת לשרוד עד למיון הסופי: תוצאה מקורבת
  /// אינה רשאית לדחוק כינוי מדויק רק בגלל סדר הספרייה או תקרת התוצאות.
  static Map<_BookKey, int> _bookMatchRanks(
    List<ReferenceBookHit> hits, {
    BookSource source = BookSource.official,
    Map<_BookKey, int>? into,
  }) {
    final bookMatchRanks = into ?? <_BookKey, int>{};
    for (final hit in hits) {
      if (hit.bookId > 0 || hit.filePath.isNotEmpty) {
        final key = _bookKey(source, hit.bookId, hit.filePath);
        final previous = bookMatchRanks[key];
        if (previous == null || hit.matchRank < previous) {
          bookMatchRanks[key] = hit.matchRank;
        }
      }
    }
    return bookMatchRanks;
  }

  static DbReferenceResult _bookResult(
    ReferenceBookHit hit, {
    bool isCategoryMatch = false,
  }) => DbReferenceResult(
    title: hit.title,
    reference: hit.title,
    segment: 0,
    isPdf: hit.fileType == 'pdf',
    filePath: hit.filePath,
    orderIndex: hit.orderIndex,
    bookId: hit.bookId,
    isCategoryMatch: isCategoryMatch,
  );

  static Iterable<DbReferenceResult> _dibburResults(
    ReferenceBookHit hit,
    Map<int, List<_Dibbur>> dibburim,
  ) => [
    for (final dibbur in dibburim[hit.bookId] ?? const <_Dibbur>[])
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
  ];

  /// מילה אחת: בלי חיפוש TOC פר-ספר, אבל כותרות AltToc קצרות נמצאות גלובלית
  /// ("נח" / "פרשת האזינו") — issue #983.
  Future<List<DbReferenceResult>> _singleWordResults(
    _FindRefSearch search,
  ) async {
    final queryTokens = search.queryTokens;
    final results = <DbReferenceResult>[];
    final directMatches = <DbReferenceResult>{};
    for (final hit in search.detection.hits) {
      results.addAll(_dibburResults(hit, search.dibburim));
      results.add(_bookResult(hit));
    }

    if (queryTokens.first.length >= 2) {
      final start = results.length;
      await _awaitCurrent(
        _addGlobalAltTocMatches(
          results,
          queryTokens,
          maxRefTokens: 2,
          visibility: search.visibilityFilter,
        ),
      );
      directMatches.addAll(results.skip(start));
    }

    await _addSecondaryBookResults(results, search);

    final unique = _dedupeRefs(results, queryTokens: queryTokens);
    final ranked = _rankResults(
      unique,
      queryTokens,
      bookMatchRanks: search.bookMatchRanks,
      directMatches: directMatches,
      preserveSubstringTail: true,
      rawQuery: search.rawQuery,
    );
    return await _awaitCurrent(_enrichWithPaths(ranked));
  }

  Future<List<DbReferenceResult>> _multiWordResults(
    _FindRefSearch search,
    SeforimRepository? repository,
  ) async {
    final queryTokens = search.queryTokens;
    final detection = search.detection;

    // כשהטוקן הראשון תפס ספרים רבים (כמו "ראש") בלי אקרוניום שמצמצם, הספר
    // המכוון עלול לשבת עמוק ברשימה ולהיחתך ע"י התקרה (למשל "ראש בבא בתרא"
    // בלי אקרוניום → הרא"ש על ב"ב במקום ~138). ממיינים כך שספרים שכותרתם
    // מכסה יותר מטוקני-השאילתה (מעבר לאותיות-מיקום בודדות) ייבדקו קודם.
    final bookHits = _prioritizeByTitleCoverage(
      detection.hits,
      queryTokens,
      _maxTocLookups,
    );

    // אורך ה-phrase שזיהה כל hit: זה שנקבע בלולאה, או קצר יותר ל-hits שנאספו
    // בפירוש חלופי — חיתוך לפי האורך הגלובלי היה בולע להם טוקן-קטע.
    final remainingByHit = <ReferenceBookHit, List<String>>{};
    for (final hit in bookHits) {
      final phraseTokenCount =
          detection.secondaryPhraseTokenCount[hit] ??
          detection.phraseTokenCount;
      remainingByHit[hit] = _getRemainingTokens(
        queryTokens,
        hit.titleTokens,
        stripLeadingTokensCount: hit.matchRank >= 3 ? phraseTokenCount : 0,
        prefixMatchTokensCount: hit.matchRank >= 3 ? 0 : phraseTokenCount,
      );
    }

    final plans = await _planTocLookups(search, bookHits, remainingByHit);
    final exactLines = await _awaitCurrent(
      _resolveExactLines(
        bookHits,
        remainingByHit,
        // זנב הדיבור כבר נחתך מהטוקנים, וספירת טווח מול השאילתה הגולמית
        // הייתה מודדת אותו.
        tokensAfterRange: search.isDibburQuery
            ? 0
            : _tokensAfterRange(search.rawQuery, queryTokens),
      ),
    );
    final tocResponses = plans.requests.isEmpty
        ? const <TocBatchResult>[]
        : await _awaitCurrent(_fetchTocBatch(repository, plans.requests));

    // התוצאות, בסדר הספרים.
    final results = <DbReferenceResult>[];
    for (var i = 0; i < bookHits.length; i++) {
      final hit = bookHits[i];
      final plan = plans.plans[i];
      final remainingTokens = remainingByHit[hit]!;
      if (hit.bookId == -1) {
        results.addAll(await _pdfHitResults(hit, plan, remainingTokens));
        continue;
      }
      final requestIndex = plan.requestIndex;
      results.addAll(
        _dbHitResults(
          hit,
          remainingTokens,
          dibburim: search.dibburim,
          exactLines: exactLines[hit.bookId] ?? const <_ExactLine>[],
          toc: requestIndex == null ? null : tocResponses[requestIndex],
          isOverCap: plan.isOverCap,
        ),
      );
    }

    final directMatches = <DbReferenceResult>{};
    // AltToc גלובלי רק כשהלולאה הפר-ספר לא מצאה שום כותרת פנימית (AltToc או
    // TOC ברמה 2+), למשל "נח עליה ב" בלי שם ספר. אחרת התאמות ה-`every(contains)`
    // מספרים מוקדמים דוחקות תוצאות ספציפיות ("ברכות ב" מאבד את ה-PDF של ברכות).
    final perBookHasSpecificMatch = results.any(
      (r) => r.isAltToc || r.tocLevel >= 2,
    );
    if (!perBookHasSpecificMatch) {
      final start = results.length;
      await _awaitCurrent(
        _addGlobalAltTocMatches(
          results,
          queryTokens,
          visibility: search.visibilityFilter,
        ),
      );
      directMatches.addAll(results.skip(start));
    }

    await _addSecondaryBookResults(results, search);

    final unique = _dedupeRefs(results, queryTokens: queryTokens);
    final pruned = _suppressDeeperVariants(unique);
    final ranked = _rankResults(
      pruned,
      queryTokens,
      bookMatchRanks: search.bookMatchRanks,
      directMatches: directMatches,
      rawQuery: search.rawQuery,
    );
    return await _awaitCurrent(_enrichWithPaths(ranked));
  }

  /// תקרה על חיפושי ה-TOC היקרים (שאילתת DB / outline לכל ספר). ה-limit הגבוה
  /// מאפשר לטוקן ראשון רחב ("ראש") להתאים מאות ספרים; ה-suppress מסנן את רובם
  /// בחינם, אך כשאין טוקן-ספר הבא (אין suppress) התקרה מונעת הצפת שאילתות.
  static const int _maxTocLookups = 50;

  /// אילו ספרים מגיעים לחיפוש תוכן העניינים. התקרה משותפת ל-PDF ולספרי המסד
  /// ונספרת לפי סדר הספרים.
  Future<({List<_TocPlan> plans, List<TocBatchRequest> requests})>
  _planTocLookups(
    _FindRefSearch search,
    List<ReferenceBookHit> bookHits,
    Map<ReferenceBookHit, List<String>> remainingByHit,
  ) async {
    final queryTokens = search.queryTokens;
    // If the *next* token after the matched book-phrase is an exact book match,
    // avoid TOC search to prevent cross-book false positives.
    final nextTokenIndex = search.detection.phraseTokenCount;
    final nextToken = queryTokens.length > nextTokenIndex
        ? queryTokens[nextTokenIndex]
        : '';
    final hasExactNextTokenMatch =
        nextToken.isNotEmpty && search.books.hasExactTitle(nextToken);

    // רק ~5% מהספרים הם בעלי מבנה AltToc — לשאר לא מבקשים AltToc כלל.
    final altBookIds = await _awaitCurrent(_getAltBookIds());

    var tocLookups = 0;
    final plans = <_TocPlan>[];
    final requests = <TocBatchRequest>[];
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
      } else if (tocLookups >= _maxTocLookups) {
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
        plans.add(_TocPlan.request(requests.length));
        requests.add((
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
    return (plans: plans, requests: requests);
  }

  /// PDF ממערכת הקבצים שאינו במסד: ה-outline שלו משמש כתוכן עניינים.
  Future<List<DbReferenceResult>> _pdfHitResults(
    ReferenceBookHit hit,
    _TocPlan plan,
    List<String> remainingTokens,
  ) async {
    final title = hit.title;
    // בלי זנב לא נסקר ה-outline: ב-PDF רבים הוא ברמת דף-לדף, והדפים
    // דחקו החוצה ספרי מסד.
    if (remainingTokens.isEmpty) {
      return [
        DbReferenceResult(
          title: title,
          reference: title,
          segment: 0,
          isPdf: true,
          filePath: hit.filePath,
          orderIndex: hit.orderIndex,
        ),
      ];
    }
    if (!plan.isPdfOutline) return const [];

    final outlineFn =
        getPdfOutlineEntries ??
        ReferenceBooksCache.instance.getPdfOutlineEntries;
    final outlineEntries = await _awaitCurrent(outlineFn(hit.filePath));
    final normalizedBookTitle = _normalizeForMatch(title);

    // ציטוט דף: התאמה מיקומית (מספר מול מספר, עמוד מול עמוד) — כדי ש-"ב"
    // בודד לא ייתפס ע"י סימון צד ע"ב ("דף ג:") של כל דף ב-outline.
    final cite = parseDafCitation(remainingTokens);

    final results = <DbReferenceResult>[];
    for (final (normChapter, origChapter, pageNumber) in outlineEntries) {
      if (normChapter == normalizedBookTitle) continue;
      final chapterWords = _tokenize(normChapter);
      final matches =
          (cite == null ? null : matchDafCitation(chapterWords, cite)) ??
          remainingTokens.every(
            (t) => chapterWords.any((w) => w.startsWith(t)),
          );
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
    return results;
  }

  /// תוצאות ספר מהמסד: דיבורים, שורות מדויקות, ותוכן העניינים וה-AltToc
  /// שלו מתוך [toc] (`null` = הספר לא הגיע לחיפוש TOC).
  List<DbReferenceResult> _dbHitResults(
    ReferenceBookHit hit,
    List<String> remainingTokens, {
    required Map<int, List<_Dibbur>> dibburim,
    required List<_ExactLine> exactLines,
    required TocBatchResult? toc,
    bool isOverCap = false,
  }) {
    final title = hit.title;
    final bookId = hit.bookId;
    final isPdf = hit.fileType == 'pdf';
    final results = <DbReferenceResult>[..._dibburResults(hit, dibburim)];

    for (final exact in exactLines) {
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

    // הוקלדה רק כותרת הספר — הספר בלבד, בלי ערכי TOC.
    if (remainingTokens.isEmpty) return results..add(_bookResult(hit));
    if (toc == null) {
      // בדיקת הקטגוריה אינה שאילתה, ולכן אינה כפופה לתקרת ה-TOC: "רמבם זמנים"
      // תופס עשרות ספרי "רמבם על משנה" שקודמים לספרי משנה תורה.
      // כשה-TOC דולג כי הזנב הוא שם ספר ("רמבם שופטים"), נדרש שם התיקייה כולו.
      if (_remainingTokensAreLeafCategory(
        bookId,
        remainingTokens,
        wholeName: !isOverCap,
      )) {
        results.add(_bookResult(hit, isCategoryMatch: true));
      }
      return results;
    }

    final resultsBeforeToc = results.length;
    for (final entry in toc.toc) {
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
          isPartialTocMatch: entry['partialMatch'] == true,
        ),
      );
    }

    // ה-reference של AltToc יחסי לספר ("פרשת לך לך עליה ו" בתוך "בראשית"),
    // ולכן שם הספר מצורף כדי שהתצוגה תזהה לאיזה ספר התוצאה שייכת.
    for (final entry in toc.altToc) {
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
      results.add(_bookResult(hit, isCategoryMatch: true));
    }
    return results;
  }

  /// הספרים האישיים והמסדים המצורפים, כשהמתג פעיל.
  Future<void> _addSecondaryBookResults(
    List<DbReferenceResult> results,
    _FindRefSearch search,
  ) async {
    if (!search.includePersonalBooks) return;
    results.addAll(await _awaitCurrent(_searchPersonalBooks(search)));
    results.addAll(await _awaitCurrent(_searchAttachedLibraries(search)));
  }

  Future<List<Map<String, dynamic>>> _fetchTocEntries(
    SeforimRepository? repository,
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

  Future<List<Map<String, dynamic>>> _fetchAltTocEntries(
    SeforimRepository? repository,
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

  Future<List<TocBatchResult>> _fetchTocBatch(
    SeforimRepository? repository,
    List<TocBatchRequest> books,
  ) async {
    final batch = getTocForBooks;
    if (batch != null) return batch(books);
    final out = <TocBatchResult>[];
    for (final book in books) {
      var toc = await _awaitCurrent(
        _fetchTocEntries(
          repository,
          book.bookId,
          book.bookTitle,
          queryTokens: book.queryTokens,
        ),
      );
      final fallback = book.fallbackTokens;
      if (toc.isEmpty && fallback != null) {
        toc = await _awaitCurrent(
          _fetchTocEntries(
            repository,
            book.bookId,
            book.bookTitle,
            queryTokens: fallback,
          ),
        );
      }
      final altTokens = book.altTocTokens;
      out.add((
        toc: toc,
        altToc: altTokens == null
            ? const <Map<String, dynamic>>[]
            : await _awaitCurrent(
                _fetchAltTocEntries(
                  repository,
                  book.bookId,
                  book.bookTitle,
                  queryTokens: altTokens,
                ),
              ),
      ));
    }
    return out;
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

    // reference → האם כל הערכים שלו התאמות חלקיות; אב חלקי אינו מסתיר צאצא מלא.
    final referencesByGroup =
        <(int, BookSource, bool, bool), Map<String, bool>>{};
    for (final e in entries) {
      final refs =
          referencesByGroup[(e.bookId, e.source, e.isAltToc, e.isPdf)] ??= {};
      refs[e.reference] = (refs[e.reference] ?? true) && e.isPartialTocMatch;
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
        final ancestorIsPartial = siblings[reference.substring(0, i)];
        if (ancestorIsPartial == null) continue;
        if (!ancestorIsPartial || entry.isPartialTocMatch) return false;
      }
      return true;
    }).toList();
  }

  Future<List<DbReferenceResult>> _searchPersonalBooks(
    _FindRefSearch search,
  ) async {
    try {
      final index = await _awaitCurrent(
        search.userBooks ?? _loadUserBooks(),
      );
      if (index.books.isEmpty) return const [];
      return await _searchSecondaryBooks(
        search,
        index: index,
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
    _FindRefSearch search,
  ) async {
    final out = <DbReferenceResult>[];
    final registry = AttachedLibraryRegistry.instance;
    final List<AttachedLibrary> libraries;
    try {
      libraries = registry.visibleLibraries;
      _attachedBooksCache.removeWhere(
        (slug, _) => !libraries.any((library) => library.slug == slug),
      );
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
        final index = await _awaitCurrent(_loadAttachedBooks(library));
        if (index.books.isEmpty) continue;
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
              search,
              index: index,
              source: BookSource.attached(library.slug),
              rootPath: library.displayName,
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

  /// כמה ספרים ממסד משני אחד נשאלים בתוכן העניינים בכל הקלדה — כמו בקטלוג
  /// הרשמי. בלעדיה התאמת "מכיל" רחבה שלחה מאות ספרים לבקשה אחת ב-worker.
  @visibleForTesting
  static int maxSecondaryTocLookups = _maxTocLookups;

  /// תוכן העניינים של כל הספרים האישיים המועמדים — בבקשה אחת ל-worker, כדי
  /// שהשאילתה הסינכרונית לא תחסום את ההקלדה. כשל מדלג על ה-TOC בלבד.
  Future<List<List<Map<String, dynamic>>>> _fetchUserBookTocs(
    List<_SecondaryTocRequest> books,
  ) async {
    final injected = getUserBookTocEntries;
    if (injected != null) {
      final out = <List<Map<String, dynamic>>>[];
      for (final book in books) {
        var toc = await _awaitCurrent(
          injected(book.bookId, book.bookTitle, queryTokens: book.queryTokens),
        );
        final fallback = book.fallbackTokens;
        if (toc.isEmpty && fallback != null) {
          toc = await _awaitCurrent(
            injected(book.bookId, book.bookTitle, queryTokens: fallback),
          );
        }
        out.add(toc);
      }
      return out;
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

  /// סגירת user_books.db: ה-worker משחרר את הקובץ, והספרים האישיים ייטענו
  /// מחדש — גרסת התוכן של החיבור הישן אינה ברת-השוואה לחדש.
  static void _resetSecondaryWorker() {
    AttachedFindRefWorker.instance.reset();
    for (final repo in _liveInstances) {
      repo._dropUserBooks();
    }
  }

  static AttachedDbJob<List<Map<String, dynamic>>> _userBookTocJob(
    _SecondaryTocRequest book, {
    required bool invalidateCache,
  }) => (repository) async {
    if (invalidateCache) {
      await repository.invalidateTocCacheIfChangedExternally();
    }
    return _tocOf(repository, book);
  };

  /// ה-TOC של ספר משני; ריק עם זנב ראש-תיבות — חיפוש חוזר בלעדיו, כמו במסד הרשמי.
  static Future<List<Map<String, dynamic>>> _secondaryToc(
    SeforimRepository repository,
    _SecondaryTocRequest book,
  ) async {
    final toc = await repository.getTocEntriesForReference(
      book.bookId,
      book.bookTitle,
      queryTokens: book.queryTokens,
    );
    final fallback = book.fallbackTokens;
    if (toc.isNotEmpty || fallback == null) return toc;
    return repository.getTocEntriesForReference(
      book.bookId,
      book.bookTitle,
      queryTokens: fallback,
    );
  }

  /// מזהה חיבור ייחודי גם בין מופעי worker: מונה החיבורים מתאפס ב-isolate חדש.
  static final int _workerNonce = Random().nextInt(1 << 32);
  static final Expando<int> _connectionSerials = Expando();
  static int _lastConnectionSerial = 0;

  /// רשימת הספרים האישיים, רק אם התוכן השתנה מאז [known]. באותו חיבור PRAGMA
  /// data_version מספיק; בחיבור חדש (אחרי idleClose) מכריעה חתימת התוכן.
  static AttachedDbJob<
    ({_UserBooksVersion version, List<_SecondaryBook>? books})
  >
  _userBooksJob(_UserBooksVersion? known) => (repository) async {
    final db = await repository.database.database;
    final dataVersion =
        db.select('PRAGMA data_version').first.columnAt(0) as int;
    final serial = _connectionSerials[repository] ??= ++_lastConnectionSerial;
    final connection = '$_workerNonce:$serial';
    if (known != null &&
        known.connection == connection &&
        known.dataVersion == dataVersion) {
      return (version: known, books: null);
    }
    final version = (
      connection: connection,
      dataVersion: dataVersion,
      signature: _userBooksSignature(db),
    );
    if (known != null && known.signature == version.signature) {
      return (version: version, books: null);
    }
    return (version: version, books: await _readSecondaryBooksFrom(repository));
  };

  /// FNV-1a על כל שורות `book` ו-`category` — משתנה בכל הוספה, מחיקה או
  /// שינוי שם, בלי לבנות את רשימת הספרים.
  static int _userBooksSignature(sqlite3.Database db) {
    var hash = 0x811c9dc5;
    for (final table in const ['book', 'category']) {
      for (final row in db.select('SELECT * FROM $table ORDER BY id')) {
        for (final value in row.values) {
          for (final unit in '$value\u0001'.codeUnits) {
            hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
          }
        }
      }
    }
    return hash;
  }

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
      return await _secondaryToc(repository, book);
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

  /// ספרי מסד מצורף ומנוע ההתאמה שלהם, מקאש שנבנה מחדש כשרשומת המסד או
  /// הכינויים שלו השתנו.
  Future<_SecondaryIndex> _loadAttachedBooks(AttachedLibrary library) async {
    final acronyms = AcronymsCache.instance.attachedAcronymsOf(library.slug);
    final cached = _attachedBooksCache[library.slug];
    final sameLibrary = cached != null && cached.library == library;
    if (sameLibrary && identical(cached.acronyms, acronyms)) {
      return cached.index;
    }
    final books = sameLibrary
        ? cached.index.books
        : await AttachedFindRefWorker.instance.run(
            library.path,
            immutable: library.immutable,
            version: _attachedVersion(library),
            job: _attachedBooksJob,
          );
    final index = await _SecondaryIndex.build(books, acronyms: acronyms);
    _attachedBooksCache[library.slug] = (
      library: library,
      acronyms: acronyms,
      index: index,
    );
    return index;
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

  /// ספרי מסד משני (אישי או מצורף): זיהוי הספר ב-[_detectBooks], כמו בקטלוג
  /// הרשמי; ואחריו שורה מדויקת דרך [resolveLineRefs] או תוכן העניינים שבמסד.
  Future<List<DbReferenceResult>> _searchSecondaryBooks(
    _FindRefSearch search, {
    required _SecondaryIndex index,
    required BookSource source,
    required String rootPath,
    required Future<List<List<Map<String, dynamic>>>> Function(
      List<_SecondaryTocRequest> books,
    )
    fetchTocBatch,
    Future<Map<int, _ExactLine>> Function(List<int> bookIds, String refKey)?
    resolveLineRefs,
  }) async {
    final queryTokens = search.queryTokens;
    final folderMatchLengths = <ReferenceBookHit, int>{};
    // רק המילה האחרונה עשויה להיות באמצע הקלדה, וראשי-תיבות בגרשיים הם מילה שלמה
    final quoted = quotedWordsOf(search.rawQuery, _normalizeForMatch);
    final partialFolderToken = quoted.contains(queryTokens.last)
        ? -1
        : queryTokens.length - 1;
    final books = _BookSearch(
      queryTokens: queryTokens,
      visibility: search.visibility,
      index: index.titles,
      source: source,
      extraHits: (phrase, hits) => _folderNameHits(
        index,
        queryTokens,
        phrase,
        hits,
        search.visibility,
        source,
        folderMatchLengths,
        partialFolderToken,
      ),
    );
    final detection = _detectBooks(books, queryTokens);
    _bookMatchRanks(
      detection.hits,
      source: source,
      into: search.bookMatchRanks,
    );

    // ספר יכול לעלות בכמה אורכי צירוף ("ספר המצות" מקורב, "ספר" תחילית), וכל
    // פירוש משאיר זנב אחר — כמו בקטלוג הרשמי; רק זנב זהה הוא כפילות.
    final matches = <({_SecondaryBook book, ReferenceBookHit hit})>[];
    final remainingByHit = <ReferenceBookHit, List<String>>{};
    final seen = <String>{};
    for (final hit in detection.hits) {
      final book = index.byId[hit.bookId];
      if (book == null) continue;
      final phraseTokenCount =
          detection.secondaryPhraseTokenCount[hit] ??
          detection.phraseTokenCount;
      // שם תיקייה + כותרת אינו מוגבל ל-3 הטוקנים של שם ספר.
      final folderLength = folderMatchLengths[hit] ?? 0;
      final remaining = _getRemainingTokens(
        queryTokens,
        hit.titleTokens,
        stripLeadingTokensCount: hit.matchRank >= 3 ? phraseTokenCount : 0,
        prefixMatchTokensCount: hit.matchRank >= 3
            ? 0
            : (folderLength > phraseTokenCount
                  ? folderLength
                  : phraseTokenCount),
      );
      if (!seen.add('${hit.bookId}|${remaining.join(' ')}')) continue;
      matches.add((book: book, hit: hit));
      remainingByHit[hit] = remaining;
    }

    // שאילתה מאוגדת אחת לכל מפתח קנוני, כמו במסלול הספרייה הרשמית.
    final exactLines = <int, _ExactLine>{};
    if (resolveLineRefs != null && queryTokens.length > 1) {
      final bookIdsByKey = <String, List<int>>{};
      for (final (:book, :hit) in matches) {
        final remaining = remainingByHit[hit]!;
        if (book.record.fileType == 'pdf' || remaining.length < 2) continue;
        final key = buildRefKey(remaining.join(' '));
        if (key != null) (bookIdsByKey[key] ??= []).add(book.record.id);
      }
      for (final entry in bookIdsByKey.entries) {
        exactLines.addAll(
          await _awaitCurrent(resolveLineRefs(entry.value, entry.key)),
        );
      }
    }

    // התקרה נותנת את חיפושי ה-TOC לפי איכות ההתאמה (זהה, תחילית, מכיל,
    // מקורב) ואז לפי כיסוי השם ("שות פלוני חלק טו ג" → "חלק טו").
    final wantsToc = <ReferenceBookHit>[
      for (final (book: _, :hit) in matches)
        if (queryTokens.length > 1 &&
            (remainingByHit[hit]!.isNotEmpty ||
                _acronymSectionTokens(hit).isNotEmpty))
          hit,
    ];
    final significant = _significantTokens(queryTokens);
    final ranked = [
      for (var i = 0; i < wantsToc.length; i++)
        (
          index: i,
          hit: wantsToc[i],
          coverage: _titleCoverage(wantsToc[i].titleTokens, significant),
        ),
    ];
    mergeSort(
      ranked,
      compare: (a, b) {
        final byRank = a.hit.matchRank.compareTo(b.hit.matchRank);
        if (byRank != 0) return byRank;
        final byCoverage = b.coverage.compareTo(a.coverage);
        return byCoverage != 0 ? byCoverage : a.index.compareTo(b.index);
      },
    );
    final tocAllowed = {
      for (final e in ranked.take(maxSecondaryTocLookups)) e.hit,
    };

    // מילה אחת, רק כותרת, או ספר מעבר לתקרה — הספר בלבד, בלי ערכי TOC.
    final tocRequests = <_SecondaryTocRequest>[];
    final tocIndexByMatch = <int?>[];
    for (final (:book, :hit) in matches) {
      if (!tocAllowed.contains(hit)) {
        tocIndexByMatch.add(null);
        continue;
      }
      final remainingTokens = remainingByHit[hit]!;
      final sectionTokens = _acronymSectionTokens(hit);
      tocIndexByMatch.add(tocRequests.length);
      tocRequests.add((
        bookId: book.record.id,
        bookTitle: book.record.title,
        queryTokens: [...sectionTokens, ...remainingTokens],
        fallbackTokens: sectionTokens.isEmpty || remainingTokens.isEmpty
            ? null
            : remainingTokens,
      ));
    }
    final tocs = tocRequests.isEmpty
        ? const <List<Map<String, dynamic>>>[]
        : await _awaitCurrent(fetchTocBatch(tocRequests));

    final out = <DbReferenceResult>[];
    for (var m = 0; m < matches.length; m++) {
      final (:book, :hit) = matches[m];
      final record = book.record;
      final remainingTokens = remainingByHit[hit]!;
      final isPdf = record.fileType == 'pdf';
      final bookPath = record.folderTitles.isEmpty
          ? rootPath
          : record.folderTitles.join(', ');
      DbReferenceResult result({
        required String reference,
        required int segment,
        int tocLevel = 1,
        int sourceLineId = 0,
        bool isSourceLine = false,
        bool isPartialTocMatch = false,
      }) => DbReferenceResult(
        title: record.title,
        reference: reference,
        segment: segment,
        isPdf: isPdf,
        filePath: record.filePath ?? '',
        orderIndex: record.orderIndex,
        tocLevel: tocLevel,
        bookId: record.id,
        bookPath: bookPath,
        sourceLineId: sourceLineId,
        source: source,
        isSourceLine: isSourceLine,
        isPartialTocMatch: isPartialTocMatch,
      );

      final exact = exactLines[record.id];
      if (exact != null) {
        out.add(
          result(
            reference:
                exact.heRef ?? '${record.title} ${remainingTokens.join(' ')}',
            segment: exact.lineIndex,
            tocLevel: 3,
            sourceLineId: exact.lineId,
            isSourceLine: true,
          ),
        );
      }

      final tocIndex = tocIndexByMatch[m];
      if (tocIndex == null) {
        out.add(result(reference: record.title, segment: 0));
        continue;
      }
      final toc = tocs[tocIndex];
      for (final entry in toc) {
        out.add(
          result(
            reference: entry['reference'] as String,
            segment: entry['segment'] as int,
            tocLevel: entry['level'] as int,
            sourceLineId: entry['dbLineId'] as int? ?? 0,
            isPartialTocMatch: entry['partialMatch'] == true,
          ),
        );
      }
      // כשכינוי אינו מציין חלק, או שהזנב הוא שם התיקייה, מציגים את הספר.
      if (toc.isEmpty &&
          (remainingTokens.isEmpty ||
              (record.folderTitles.isNotEmpty &&
                  _tokensNameLeafCategory(
                    record.folderTitles.last,
                    remainingTokens,
                  )))) {
        out.add(result(reference: record.title, segment: 0));
      }
    }
    return out;
  }

  /// שם התיקייה ואחריו הכותרת ('שות פלוני חלק א'): בספרים אישיים שם הספר יושב
  /// לרוב על התיקייה. רק לספרים שהמנוע לא מצא בצירוף [phrase].
  static List<ReferenceBookHit> _folderNameHits(
    _SecondaryIndex index,
    List<String> queryTokens,
    String phrase,
    List<ReferenceBookHit> hits,
    FindRefVisibility visibility,
    BookSource source,
    Map<ReferenceBookHit, int> matchLengths,
    int partialFolderToken,
  ) {
    final phraseLength = phrase.split(' ').length;
    final found = {for (final hit in hits) hit.bookId};
    final restrict = !visibility.selection.isEmpty;
    final out = <ReferenceBookHit>[];
    for (final book in index.books) {
      final record = book.record;
      if (book.folderNameTokens.isEmpty || found.contains(record.id)) continue;
      if (restrict &&
          !visibility.allowsCandidate(
            source,
            record.id,
            record.filePath ?? '',
            fileType: record.fileType,
          )) {
        continue;
      }
      for (var i = book.folderNameTokens.length - 1; i >= 0; i--) {
        final candidate = book.folderNameTokens[i];
        final n = _leadingPrefixMatch(
          candidate,
          queryTokens,
          queryTokens.length.clamp(0, candidate.length),
          wholeWords: candidate.length - book.titleTokens.length,
          partialIndex: partialFolderToken,
        );
        // ההתאמה חייבת לכסות את כל מילות התיקייה שבשם — אחרת 'שות' לבדה
        // הייתה גוררת את כל תוכן התיקייה.
        if (n == null ||
            n < candidate.length - book.titleTokens.length ||
            n < phraseLength) {
          continue;
        }
        final name = candidate.join(' ');
        final hit = ReferenceBookHit(
          bookId: record.id,
          title: record.title,
          normalizedTitle: name,
          filePath: record.filePath ?? '',
          fileType: record.fileType,
          matchRank: name == phrase ? 0 : 1,
          orderIndex: record.orderIndex,
          titleTokens: candidate,
        );
        matchLengths[hit] = n;
        out.add(hit);
        break;
      }
    }
    return out;
  }

  /// מספר הטוקנים המובילים הארוך ביותר (עד [cap]) שכל אחד מהם תחילית של
  /// הטוקן שבאותו מקום ב-[nameTokens]. [wholeWords] הראשונים (מילות התיקייה)
  /// נדרשים במלואם, חוץ מ-[partialIndex] — אחרת "רא"ש" התאים לכל תיקיית "ראשונים".
  static int? _leadingPrefixMatch(
    List<String> nameTokens,
    List<String> queryTokens,
    int cap, {
    int wholeWords = 0,
    int partialIndex = -1,
  }) {
    for (var n = cap; n >= 1; n--) {
      if (n > nameTokens.length) continue;
      var ok = true;
      for (var i = 0; i < n; i++) {
        final name = bookNameMatchToken(nameTokens[i]);
        final query = bookNameMatchToken(queryTokens[i]);
        final whole = i < wholeWords && i != partialIndex;
        if (whole ? name != query : !name.startsWith(query)) {
          ok = false;
          break;
        }
      }
      if (ok) return n;
    }
    return null;
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
    final significant = _significantTokens(queryTokens);
    if (hits.length <= maxTocLookups || significant.length < 2) return hits;

    final indexed =
        [
          for (var i = 0; i < hits.length; i++)
            (
              index: i,
              hit: hits[i],
              score: _titleCoverage(hits[i].titleTokens, significant),
            ),
        ]..sort((a, b) {
          final c = b.score.compareTo(a.score);
          return c != 0 ? c : a.index.compareTo(b.index);
        });
    return [for (final e in indexed) e.hit];
  }

  /// טוקני שאילתה שאינם אותיות-מיקום בודדות.
  static List<String> _significantTokens(List<String> queryTokens) =>
      queryTokens.where((t) => t.length >= 2).toList(growable: false);

  /// כמה מ-[significant] מופיעים כטוקן שלם ב-[titleTokens].
  static int _titleCoverage(
    List<String> titleTokens,
    List<String> significant,
  ) {
    var score = 0;
    for (final qt in significant) {
      // התאמת טוקן שלם, כולל אות-חיבור בכותרת — אותם כללים כמו
      // ב-[_getRemainingTokens], אחרת ספר שהותאם דרך ו' החיבור ייחתך בתקרה.
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

  /// זנב כינוי שאינו בשם הספר מציין חלק בתוכו: "טור יורה דעה" → "יורה דעה".
  /// כינוי שמזהה רק את הספר, כמו "שוע אוח", אינו מוסיף טוקני חלק.
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

  static int _specificityRank(DbReferenceResult r) => findRefSpecificityRank(
    isSourceLine: r.isSourceLine,
    isAltToc: r.isAltToc,
    tocLevel: r.tocLevel,
    isPartialTocMatch: r.isPartialTocMatch,
  );

  /// האם כל [remainingTokens] הם מילים בשם הקטגוריה *הישירה* של הספר. רק
  /// העלה נבדק — segment אב ("הלכה", "מפרשים") משותף לאלפי ספרים והיה מחזיר
  /// כל אחד מהם. טוקן בן אות-שתיים הוא טוקן מיקום ולא שם קטגוריה.
  /// [wholeName] — הזנב חייב לכסות גם את כל מילות השם, מלבד "ספר".
  bool _remainingTokensAreLeafCategory(
    int bookId,
    List<String> remainingTokens, {
    bool wholeName = false,
  }) {
    final leaf = _leafCategory(bookId);
    if (leaf == null) return false;
    return _tokensNameLeafCategory(
      leaf,
      remainingTokens,
      wholeName: wholeName,
    );
  }

  String? _leafCategory(int bookId) {
    final resolver =
        getCategoryPathSync ??
        ReferenceBooksCache.instance.getCategoryPathForBookSync;
    final path = resolver(bookId);
    if (path == null || path.isEmpty) return null;
    return path.split(', ').last;
  }

  Set<String> _leafCategoryTokens(int bookId) {
    final leaf = _leafCategory(bookId);
    if (leaf == null) return const {};
    return titleMatchTokens(_normalizeForMatch(leaf));
  }

  /// האם כל [remainingTokens] הם מילים בשם הקטגוריה [leaf].
  bool _tokensNameLeafCategory(
    String leaf,
    List<String> remainingTokens, {
    bool wholeName = false,
  }) {
    if (remainingTokens.isEmpty) return false;
    if (remainingTokens.any((t) => t.length < 3)) return false;
    final leafWords = _normalizeForMatch(leaf).split(' ');
    final leafTokens = titleMatchTokensOf(leafWords);
    final matched = <String>{};
    for (final qt in remainingTokens) {
      if (leafTokens.contains(qt)) {
        matched.add(qt);
        continue;
      }
      final bare = titleTokenWithoutConjunction(qt, allowVav: true);
      if (bare == null || !leafTokens.contains(bare)) return false;
      matched.add(bare);
    }
    if (!wholeName) return true;
    for (var i = 0; i < leafWords.length; i++) {
      final word = leafWords[i];
      if (word.isEmpty || word == 'ספר' || matched.contains(word)) continue;
      final bare = titleTokenWithoutConjunction(word, allowVav: i > 0);
      if (bare == null || !matched.contains(bare)) return false;
    }
    return true;
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
      // כמו בזיהוי הספר: וו/יי כפולות וה"א לפני ראשי-תיבות ([bookNameMatchToken]).
      if (idx == -1) {
        final matchToken = bookNameMatchToken(token);
        idx = remaining.indexWhere(
          (t) =>
              t.length >= 2 &&
              (bookNameMatchToken(t) == matchToken ||
                  (prefixEligible.contains(t) &&
                      matchToken.startsWith(bookNameMatchToken(t)))),
        );
      }
      if (idx != -1) {
        remaining.removeAt(idx);
      }
    }

    return remaining;
  }

  List<DbReferenceResult> _dedupeRefs(
    List<DbReferenceResult> results, {
    List<String> queryTokens = const [],
  }) {
    final seen = <String>{};
    final out = <DbReferenceResult>[];
    // Reference tokens of TOC results, per book and heading line.
    final headings = <String, Map<num, Set<String>>>{};
    for (final r in results) {
      if (r.isAltToc || r.isSourceLine || r.isPdf || r.sourceLineId == 0) {
        continue;
      }
      headings
          .putIfAbsent(_dedupeBookKey(r), () => {})
          .putIfAbsent(r.segment, () => {})
          .addAll(_tokenize(_normalizeForMatch(r.reference)));
    }

    // המלאות תופסות את המפתחות תחילה, בלי להחליף תוצאה שכבר נשמרה.
    for (final partial in [false, true]) {
      for (final r in results) {
        if (r.isPartialTocMatch != partial) continue;
        final bookKey = _dedupeBookKey(r);
        final segmentKey = '$bookKey|${r.segment}';
        final referenceKey = '$bookKey|ref:${r.reference}';
        // גם שורה או כתובת של כפילה נשארות מוכרות לרשומות הבאות.
        final newSegment = seen.add(segmentKey);
        final newReference = seen.add(referenceKey);
        if (newSegment &&
            newReference &&
            !_restatesHeadingAbove(r, headings[bookKey], queryTokens)) {
          out.add(r);
        }
      }
    }

    return out;
  }

  /// An AltToc leaf on the line right under a TOC heading ("[סימן כה] ..." vs
  /// "סימן כה") that covers no query token the heading lacks: same place.
  bool _restatesHeadingAbove(
    DbReferenceResult r,
    Map<num, Set<String>>? headings,
    List<String> queryTokens,
  ) {
    if (!r.isAltToc) return false;
    final heading = headings?[r.segment - 1];
    if (heading == null) return false;
    final own = _tokenize(_normalizeForMatch(r.reference));
    return queryTokens.every((t) => heading.contains(t) || !own.contains(t));
  }

  /// האם הספר כותב בגרשיים את כל [quotedWords] — בשמו או באחד מכינוייו.
  static bool _spellsQuotedWords(
    DbReferenceResult r,
    Set<String> quotedWords,
  ) {
    final own = quotedWordsOf(r.title, normalizeForFindRefMatch);
    final aliases = r.source.isOfficial && r.bookId > 0
        ? AcronymsCache.instance.quotedWordsForBook(r.bookId)
        : const <String>{};
    return quotedWords.every((w) => own.contains(w) || aliases.contains(w));
  }

  static String _dedupeBookKey(DbReferenceResult r) {
    // ל-PDF מהדיסק אין bookId ייחודי; ב-DB נתיב ריק של fallback אינו ספר אחר.
    final filePathKey = r.bookId == -1 ? r.filePath : '';
    return '${r.bookId}|${r.source.wireKey}|${r.title}|${r.isPdf}|$filePathKey';
  }

  List<DbReferenceResult> _rankResults(
    List<DbReferenceResult> results,
    List<String> queryTokens, {
    Map<_BookKey, int> bookMatchRanks = const {},
    Set<DbReferenceResult> directMatches = const {},
    bool preserveSubstringTail = false,
    String rawQuery = '',
  }) {
    if (results.length < 2) return results;
    final quotedWords = quotedWordsOf(rawQuery, _normalizeForMatch);
    final punctuationAgrees = <String, bool>{};

    final query = FindRefRankQuery(queryTokens);
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

    // מפתחות הכותרת פעם אחת לכל כותרת; השאילתה מנורמלת במלואה, וכותרת בנרמול
    // חלקי (עם גרשיים) לא תשתווה לה.
    final titleKeys =
        <
          String,
          ({
            String normTitle,
            ({bool exactMatch, bool startsWithMatch, List<String> titleTokens})
            match,
          })
        >{};
    final decorated = List<FindRefRankKey<DbReferenceResult>>.generate(
      results.length,
      (i) {
        final r = results[i];
        final title = titleKeys.putIfAbsent(r.title, () {
          final normTitle = _normalizeForMatch(r.title);
          return (normTitle: normTitle, match: query.titleMatch(normTitle));
        });
        return FindRefRankKey(
          item: r,
          normTitle: title.normTitle,
          fuzzyBookMatch:
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
              bookMatchRanks[_bookKey(r.source, r.bookId, r.filePath)] ==
                  ReferenceBooksCache.fuzzyMatchRank,
          exactMatch: title.match.exactMatch,
          startsWithMatch: title.match.startsWithMatch,
          punctuationAgrees:
              quotedWords.isEmpty ||
              punctuationAgrees.putIfAbsent(
                '${r.bookId}|${r.source.wireKey}|${r.title}',
                () => _spellsQuotedWords(r, quotedWords),
              ),
          titleTokens: title.match.titleTokens,
          citationMatch: findRefCitationMatch(
            query.isDafCitation,
            r.reference,
          ),
          // ספר שאינו רשמי: ה-bookId שלו במרחב של מסד אחר ועלול להתנגש במזהה
          // רשמי — שליפת נתיב לפיו הייתה מסווגת אותו לפי ספר זר.
          bookRank: r.bookId > 0 && r.source.isOfficial
              ? _officialBookRank(r.bookId, r.title)
              : _bookRankFor(null, r.title),
          isOfficial: r.source.isOfficial,
          orderIndex: r.orderIndex,
          specificity: _specificityRank(r),
          reference: r.reference,
          segment: r.segment,
          bookId: r.bookId,
          categoryTokens: r.isCategoryMatch
              ? _leafCategoryTokens(r.bookId)
              : const {},
        );
      },
    );

    decorated.sort((a, b) => compareFindRefRank(a, b, query));

    // cap מודע-רלוונטיות: חותכים ב-[_baseResultCap], אך מרחיבים לכל מי שחולק
    // את מפתח-הרלוונטיות של התוצאה האחרונה שבחיתוך — כך שתוצאות שווֹת-רלוונטיות
    // מוצגות יחד. הרשימה נעצרת רק כשמגיעים לתוצאה *פחות* רלוונטית.
    if (decorated.length <= _baseResultCap) {
      return decorated.map((d) => d.item).toList();
    }
    final boundary = decorated[_baseResultCap - 1];
    var end = _baseResultCap;
    while (end < decorated.length &&
        compareFindRefRelevance(decorated[end], boundary, query) == 0) {
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
      var quota =
          _substringTailQuota -
          capped.where((d) => d.isSubstringMatch(query.text)).length;
      for (
        var i = end;
        i < decorated.length && quota > 0 && capped.length < _maxResultCap;
        i++
      ) {
        if (decorated[i].isSubstringMatch(query.text)) {
          capped.add(decorated[i]);
          quota--;
        }
      }
    }

    return [for (final d in capped) d.item];
  }

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
  /// ו"קמא" אינם רצופים שם. ההשוואה ב-[bookNameMatchToken], כמו זיהוי הספר.
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
        if (!bookNameMatchToken(
          titleTokens[start + i],
        ).startsWith(bookNameMatchToken(phraseTokens[i]))) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }
}

typedef _ExactLine = ({int lineIndex, int lineId, String? heRef});

/// גרסת התוכן של user_books.db: חיבור ה-worker, data_version שלו וחתימת התוכן.
typedef _UserBooksVersion = ({
  String connection,
  int dataVersion,
  int signature,
});

/// ספר בכל מסד: מקור, מזהה, ונתיב הקובץ רק ל-PDF שמחוץ למסד (מזהה שלילי).
typedef _BookKey = (String source, int bookId, String filePath);

_BookKey _bookKey(BookSource source, int bookId, String filePath) =>
    (source.wireKey, bookId, bookId > 0 ? '' : filePath);

typedef _SecondaryTocRequest = ({
  int bookId,
  String bookTitle,
  List<String> queryTokens,
  List<String>? fallbackTokens,
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

/// הספרים שהשאילתה מזכירה ([FindRefRepository._detectBooks]).
typedef _BookDetection = ({
  List<ReferenceBookHit> hits,
  int phraseTokenCount,
  Map<ReferenceBookHit, int> secondaryPhraseTokenCount,
});

/// חיפוש שמות ספרים לשאילתה אחת, בכפוף להסתרה: בקטלוג הרשמי, או ב-[index]
/// של מסד משני ([source]).
class _BookSearch {
  _BookSearch({
    required this.queryTokens,
    required this.visibility,
    this.injected,
    this.index,
    this.source = BookSource.official,
    this.extraHits,
  }) : maxPhraseTokens = queryTokens.length >= 3 ? 3 : queryTokens.length,
       // גבוה בכוונה: ה-hits מסוננים אחרי החיפוש לפי שאר הטוקנים, וחיתוך מוקדם
       // זרק ספרים רלוונטיים. מילה אחת: 200, אחרת "מא" לא מחזיר את יומא (#839).
       bookSearchLimit = queryTokens.length >= 2 ? 1000 : 200;

  final List<ReferenceBookHit> Function(String query, {int limit})? injected;
  final List<String> queryTokens;
  final FindRefVisibility visibility;
  final BookTitleIndex? index;
  final BookSource source;

  /// התאמות שמעבר למנוע, לצירוף [query] — בהינתן מה שהמנוע מצא בו.
  final List<ReferenceBookHit> Function(
    String query,
    List<ReferenceBookHit> hits,
  )?
  extraHits;

  /// הצירוף הארוך ביותר (עד 3 טוקנים) שנבדק כשם ספר — כך "שוע אוח" מזוהה.
  final int maxPhraseTokens;
  final int bookSearchLimit;

  ReferenceBookSearchBatch? _batch;

  late final bool Function(int, String, String)? _allows =
      visibility.selection.isEmpty
      ? null
      : (int id, String path, String type) =>
            visibility.allowsCandidate(source, id, path, fileType: type);

  // שם הספר בכל אורך, והשאלה אם הטוקן שאחריו הוא כותרת של ספר, נענים
  // מסריקה אחת של הקטלוג במקום סריקה לכל קריאה.
  ReferenceBookSearchBatch _searchBatch() {
    final cached = _batch;
    if (cached != null) return cached;
    final queries = [
      for (var n = maxPhraseTokens; n >= 1; n--) queryTokens.take(n).join(' '),
    ];
    final exactTitles = {
      for (var i = 1; i <= maxPhraseTokens && i < queryTokens.length; i++)
        queryTokens[i],
    };
    final index = this.index;
    return _batch = index == null
        ? ReferenceBooksCache.instance.searchBatch(
            queries,
            limit: bookSearchLimit,
            allowsBook: _allows,
            exactTitles: exactTitles,
          )
        : index.searchBatch(
            queries,
            limit: bookSearchLimit,
            allowsBook: _allows,
            exactTitles: exactTitles,
          );
  }

  List<ReferenceBookHit> search(String query, {int limit = 50}) {
    final injected = this.injected;
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
    final hits =
        _searchBatch().hitsFor(query, limit: limit) ??
        (index?.search(query, limit: limit, allowsBook: _allows) ??
            ReferenceBooksCache.instance.search(
              query,
              limit: limit,
              allowsBook: _allows,
            ));
    final extraHits = this.extraHits;
    return extraHits == null ? hits : [...hits, ...extraHits(query, hits)];
  }

  /// האם [token] הוא בעצמו כותרת מדויקת של ספר.
  bool hasExactTitle(String token) =>
      (injected == null ? _searchBatch().hasExactTitle(token) : null) ??
      search(token, limit: 50).any((hit) => hit.matchRank == 0);
}

/// מה שנקבע לשאילתה אחת לפני איסוף התוצאות, משותף לשלבי [FindRefRepository].
class _FindRefSearch {
  _FindRefSearch({
    required this.rawQuery,
    required this.queryTokens,
    required this.isDibburQuery,
    required this.visibility,
    required this.books,
    required this.detection,
    required this.bookMatchRanks,
    required this.dibburim,
    required this.includePersonalBooks,
    this.userBooks,
  });

  /// השאילתה אחרי הרחבת ע"א/ע"ב, לפני הנרמול.
  final String rawQuery;
  final List<String> queryTokens;
  final bool isDibburQuery;
  final FindRefVisibility visibility;
  final _BookSearch books;
  final _BookDetection detection;
  final Map<_BookKey, int> bookMatchRanks;
  final Map<int, List<_Dibbur>> dibburim;
  final bool includePersonalBooks;

  /// טעינת הספרים האישיים, שהתחילה עם השאילתה.
  final Future<_SecondaryIndex>? userBooks;

  FindRefVisibility? get visibilityFilter =>
      visibility.selection.isEmpty ? null : visibility;
}
