import 'package:flutter/foundation.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/alt_toc_flat_entry.dart';
import 'package:otzaria/find_ref/repository/db_commentator_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/search/utils/foundational_book_classifier.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// רשומת ספר אישי מתומצתת (user_books.db) כפי שמשמשת את חיפוש הספרים האישיים.
typedef _UserBookRecord = ({
  int id,
  String title,
  String? filePath,
  String fileType,
  double orderIndex,
});

class FindRefRepository {
  /// שמור לצורך תאימות לאחור עם call-sites קיימים.
  /// אינו בשימוש בפועל בקוד ה-repository.
  final DataRepository? dataRepository;

  final Future<void> Function()? warmUpReferenceBooksCache;
  final bool Function()? isReferenceBooksCacheLoaded;
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

  /// Injection for testing: returns the global flat list of AltToc entries
  /// across all books, as raw rows. In production this calls
  /// [SeforimRepository.getAllAltTocFlatEntries].
  ///
  /// כל row כולל את המפתחות: `bookId`, `bookTitle`, `bookOrderIndex`,
  /// `reference` (נתיב מלא יחסי לספר), `segment`, `level`, `dbLineId`.
  final Future<List<Map<String, dynamic>>> Function()? getAllAltTocFlatEntries;

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

  /// Injection for testing: מחזיר את שורות המפרשים הגולמיות עבור תוצאה.
  /// In production calls [SeforimRepository.getCommentatorsForReference].
  ///
  /// כל row צפוי לכלול לפחות `targetBookTitle` ו-`targetLineIndex` (השורה
  /// הראשונה בספר המפרש על פני טווח הקטע). חישוב הטווח (כותרת עד הכותרת
  /// הבאה / כל הספר כשאין כותרות פנימיות) מתבצע ב-repository ה-DB.
  final Future<List<Map<String, dynamic>>> Function(DbReferenceResult ref)?
  fetchCommentatorRows;

  /// Injection for testing: מחזירה את הדור של מפרש לפי שם.
  /// In production calls [CommentaryService.getBookEra].
  final Future<CommentaryEra> Function(String bookTitle)? getBookEra;

  /// Injection for testing: גרסה סינכרונית של [getCategoryPath], משמשת את
  /// `_rankResults` כדי לסווג "ספר יסוד" מול "מפרש" לפי הנתיב המלא של
  /// קטגוריית הספר. In production: [ReferenceBooksCache.instance.getCategoryPathForBookSync].
  final String? Function(int bookId)? getCategoryPathSync;

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
  static const int _maxResultCap = 100;

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

  /// קאש בזיכרון של רשימת הספרים האישיים (user_books.db). נטענת פעם אחת
  /// בחיפוש הראשון עם `includePersonalBooks`, ומשרתת חיפושים הבאים בלי
  /// שאילתת DB לכל הקלדה. מתאפסת ב-[clearCaches] (רענון/החלפת ספרייה או
  /// מוטציה של ספרים אישיים, ששניהם עוברים דרך מסלולי ה-refresh).
  List<_UserBookRecord>? _userBooksCache;

  FindRefRepository({
    this.dataRepository,
    this.warmUpReferenceBooksCache,
    this.isReferenceBooksCacheLoaded,
    this.searchReferenceBooks,
    this.getTocEntriesForReference,
    this.getAltTocEntriesForReference,
    this.getAllAltTocFlatEntries,
    this.getCategoryPath,
    this.getPdfOutlineEntries,
    this.getAllUserBooks,
    this.getUserBookTocEntries,
    this.fetchCommentatorRows,
    this.getBookEra,
    this.getCategoryPathSync,
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

  /// בדיקות בלבד: מבטל את ההרשמה של ה-instance מ-[_liveInstances]. שימושי
  /// בטסטים שיוצרים הרבה repositories מבלי לשמור שיורי state בין מבחנים.
  @visibleForTesting
  void disposeForTesting() {
    _liveInstances.remove(this);
  }

  /// מנקה את ה-caches הפנימיים של ה-repository (מפרשים ו-AltToc שטוח).
  ///
  /// יש לקרוא לזה במסלולי refresh של הספרייה / איפוס runtime, כדי שתוצאות
  /// מספרייה ישנה לא ידלפו לחיפוש שאחרי הרענון. ה-repository עצמו חי לכל
  /// אורך חיי האפליקציה (singleton ב-main), ולכן בלי ניקוי יזום הקאש ישרוד
  /// עד restart מלא.
  void clearCaches() {
    _commentatorsCache.clear();
    _altTocFlatCache = null;
    _userBooksCache = null;
  }

  /// מחזיר את רשימת הספרים האישיים מהקאש, וטוען אותה פעם אחת אם עוד לא נטענה.
  /// הטעינה היא דרך ה-injection [getAllUserBooks] (בדיקות) או ישירות מ-
  /// `user_books.db`. הקאש חוסך שאילתת DB סינכרונית בכל הקלדה כשהסוויץ'
  /// "כלול ספרים אישיים" דלוק.
  Future<List<_UserBookRecord>> _loadUserBooks() async {
    final cached = _userBooksCache;
    if (cached != null) return cached;

    final List<_UserBookRecord> list;
    if (getAllUserBooks != null) {
      list = await getAllUserBooks!();
    } else {
      final userRepo = await UserBooksDatabaseHolder.instance.repository;
      final raw = await userRepo.database.bookDao.getAllLocalBooks();
      list = raw
          .map(
            (b) => (
              id: b.id,
              title: b.title,
              filePath: b.filePath,
              fileType: b.fileType ?? 'txt',
              orderIndex: b.order,
            ),
          )
          .toList();
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
    } catch (e, st) {
      debugPrint('[FindRef] AltToc flat cache build failed: $e\n$st');
      // אל **תקבע** את הקאש לריק במקרה כשל — אם הסיבה הייתה זמנית
      // (rebuild של DB, lock רגעי), שאילתה הבאה תקבל ניסיון חוזר.
      // אם הכשל קבוע, ההשהיה ב-await יחזור ולא מקסים נזק.
      return const [];
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
  /// PDFs / ספרים מחוץ ל-DB (bookId <= 0) / ספרים אישיים — מחזיר ריק מיידית.
  /// ספרים אישיים: ה-bookId/sourceLineId שלהם שייכים ל-user_books.db ולא
  /// מתאימים ל-link table של ה-DB הראשי — שאילתה תחזיר מפרשים שגויים.
  ///
  /// תוצאות נשמרות בקאש בזיכרון לאורך חיי ה-repository.
  Future<List<DbCommentatorEntry>> getCommentatorsForResult(
    DbReferenceResult ref,
  ) async {
    if (ref.isPdf || ref.bookId <= 0 || ref.isUserBook) return const [];

    final cacheKey = _cacheKeyFor(ref);
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
              ));

    if (fetchFn == null) return const [];

    final rows = await fetchFn(ref);

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
    final eraResolver = getBookEra ?? CommentaryService.getBookEra;
    final eras = await Future.wait(entries.map((e) => eraResolver(e.title)));
    final indices = List<int>.generate(entries.length, (i) => i)
      ..sort((a, b) {
        final ea = eras[a];
        final eb = eras[b];
        if (ea.order != eb.order) return ea.order.compareTo(eb.order);
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

    _commentatorsCache[cacheKey] = sorted;
    return sorted;
  }

  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
  }) async {
    final cleanedQuery = _normalizeForMatch(ref);
    if (cleanedQuery.isEmpty) {
      return const [];
    }

    final queryTokens = _tokenize(cleanedQuery);
    if (queryTokens.isEmpty) {
      return const [];
    }

    final SeforimRepository? repository =
        SqliteDataProvider.instance.repository;
    if (repository == null && getTocEntriesForReference == null) {
      debugPrint('[FindRef] Database not initialized');
      return const [];
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

    final cacheLoaded =
        isReferenceBooksCacheLoaded?.call() ??
        ReferenceBooksCache.instance.isLoaded;
    if (!cacheLoaded) {
      await (warmUpReferenceBooksCache?.call() ??
          ReferenceBooksCache.instance.warmUp());
    }

    // מצב "דור + נושא": "ראשונים סנהדרין" / "סנהדרין ראשונים" → כל הראשונים על
    // סנהדרין. מזוהה בכל מיקום בשאילתה. אם הוא לא מחזיר תוצאות — נופלים למסלול
    // הרגיל כדי שהשאילתה תמיד תעשה משהו סביר.
    final eraQuery = _detectEraQuery(queryTokens);
    if (eraQuery != null) {
      final eraResults = await _findByEra(eraQuery.era, eraQuery.topicTokens);
      if (eraResults.isNotEmpty) return eraResults;
    }

    final searchBooks =
        searchReferenceBooks ?? ReferenceBooksCache.instance.search;

    // Prefer matching the longest leading phrase (up to 3 tokens) as the book key.
    // This supports multi-word acronyms like "שוע אוח".
    final maxPhraseTokens = queryTokens.length >= 3 ? 3 : queryTokens.length;

    // כש-query רב-מילים, ה-hits מסוננים *אחרי* החיפוש לפי שאר הטוקנים (suppress
    // וכותרות פנימיות), ולכן אסור לחתוך מוקדם: ספר רלוונטי כמו "פסקי הרא"ש על
    // ברכות" נדחק ע"י עשרות התאמות "ראש" קצרות יותר ונזרק לפני הסינון. ה-cap
    // הגבוה הוא רשת ביטחון נגד ספריות ענק; החיתוך הפונקציונלי הוא 15 הסופיות.
    final bookSearchLimit = queryTokens.length >= 2 ? 1000 : 50;
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
        if (hit.matchRank >= 4) {
          if (hit.matchRank == 4 && hit.acronymTailIsTitleWords) {
            joinablePrefixHits.add(hit);
          }
          continue;
        }
        // הכותרת המנורמלת כבר מחושבת מראש בתוך הקאש.
        final titleTokens = _tokenize(hit.normalizedTitle);
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

    // צרף את ה-secondary hits בסוף, כך שיופיעו אחרי ה-primary בדירוג.
    // ההצמדה היא בכל מקרה — בין אם נמצאו hits ראשיים ובין אם לא.
    if (secondaryHits.isNotEmpty) {
      bookHits = [...bookHits, ...secondaryHits];
    }

    final results = <DbReferenceResult>[];

    // Single-word query: do NOT search TOC at all.
    if (queryTokens.length == 1) {
      for (final hit in bookHits) {
        final isPdf = hit.fileType == 'pdf';

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

      if (includePersonalBooks) {
        results.addAll(await _searchPersonalBooks(queryTokens));
      }

      final unique = _dedupeRefs(results);
      final ranked = _rankResults(unique, queryTokens);
      return await _enrichWithPaths(ranked);
    }

    // If the *next* token after the matched book-phrase is an exact book match,
    // avoid TOC search to prevent cross-book false positives.
    final nextTokenIndex = bookQueryTokenCount;
    final nextToken = queryTokens.length > nextTokenIndex
        ? queryTokens[nextTokenIndex]
        : '';
    final nextTokenMatches = nextToken.isEmpty
        ? const <ReferenceBookHit>[]
        : searchBooks(nextToken, limit: 50);
    final hasExactNextTokenMatch = nextTokenMatches.any(
      (hit) => hit.matchRank == 0,
    );

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

    for (final hit in bookHits) {
      final bookId = hit.bookId;
      final title = hit.title;
      final isPdf = hit.fileType == 'pdf';

      // הכותרת המנורמלת כבר זמינה מהקאש — אין צורך לנרמל מחדש.
      final titleTokens = _tokenize(hit.normalizedTitle);
      final matchedByAcronym = hit.matchRank >= 3;
      final remainingTokens = _getRemainingTokens(
        queryTokens,
        titleTokens,
        stripLeadingTokensCount: matchedByAcronym ? bookQueryTokenCount : 0,
        prefixMatchTokensCount: matchedByAcronym
            ? 0
            : (secondaryPhraseTokenCount[hit] ?? bookQueryTokenCount),
      );

      // הטוקן שאחרי שם-הספר עלול להיות בעצמו ספר עצמאי ("תורה אור" — "אור" ספר),
      // ואז חיפוש TOC לפיו יוצר התאמות-שווא חוצות-ספרים. אבל אם הטוקן הוא חלק
      // מכותרת הספר הנוכחי ("ברכות" בתוך "פסקי הרא"ש על ברכות") — אין חציית ספר,
      // ומותר לרדת לכותרות הפנימיות.
      final suppressTocForCrossBook =
          hasExactNextTokenMatch && !titleTokens.contains(nextToken);

      // bookId == -1: file-system PDF not in DB — use PDF outline as TOC,
      // mirroring the regular book flow as closely as possible.
      if (bookId == -1) {
        if (remainingTokens.isEmpty) {
          // המשתמש הקליד רק את כותרת הספר — מחזירים את הספר בלבד, בלי לסקור
          // את כל ערכי ה-outline. PDFs רבים שומרים את ה-outline בגרנולריות
          // של דף-לדף (50+ ערכים למסכת), וטעינה אוטומטית הציפה את רשימת
          // התוצאות בדפים בודדים שדחקו החוצה ספרי DB תואמים. סימטרי למסלול
          // של מילה אחת — שם גם לא נסקרים ערכי TOC.
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

        if (suppressTocForCrossBook) continue;
        if (tocLookups >= maxTocLookups) continue;
        tocLookups++;

        final outlineFn =
            getPdfOutlineEntries ??
            ReferenceBooksCache.instance.getPdfOutlineEntries;
        final outlineEntries = await outlineFn(hit.filePath);
        final normalizedBookTitle = _normalizeForMatch(title);

        // ציטוט דף: התאמה מיקומית (מספר מול מספר, עמוד מול עמוד) — כדי ש-"ב"
        // בודד לא ייתפס ע"י סימון צד ע"ב ("דף ג:") של כל דף ב-outline.
        final cite = parseDafCitation(remainingTokens);

        // Mirror regular book: add ALL matching outline entries (not just first).
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
        // FS PDFs have no DB category path — bookPath stays ''.
        continue;
      }

      if (remainingTokens.isEmpty) {
        // המשתמש הקליד רק את כותרת הספר — מחזירים את הספר בלבד, ללא ערכי
        // TOC. סימטרי למסלול של מילה אחת ולמסלול ה-PDF למעלה.
        results.add(
          DbReferenceResult(
            title: title,
            reference: title,
            segment: 0,
            isPdf: isPdf,
            filePath: hit.filePath,
            orderIndex: hit.orderIndex,
            bookId: bookId,
          ),
        );
      } else if (!suppressTocForCrossBook) {
        if (tocLookups >= maxTocLookups) continue;
        tocLookups++;

        final tocEntries = await fetchTocEntries(
          bookId,
          title,
          queryTokens: remainingTokens,
        );

        for (final entry in tocEntries) {
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

        // חיפוש בכותרות-משנה (AltToc): עליות, פרשות ומבנים חלופיים נוספים.
        // ה-reference שמחזיר ה-DB עבור AltToc הוא יחסי — אינו כולל את שם
        // הספר (למשל "פרשת לך לך עליה ו" בתוך "בראשית"). אנו מצרפים את שם
        // הספר ב-prefix כדי שהתצוגה תזהה לאיזה ספר התוצאה שייכת — תוצאת
        // AltToc "הלכות בבא קמא" בתוך "הלכות גדולות" הוצגה לבדה ללא רמז
        // לזהות הספר. ה-prefix מתבצע רק אם אין כפילות — defensive guard.
        final altTocEntries = await fetchAltTocEntries(
          bookId,
          title,
          queryTokens: remainingTokens,
        );
        for (final entry in altTocEntries) {
          final ref = entry['reference'] as String;
          // Require that all remaining tokens appear in the reference.
          // Prevents partial AltToc matches when the book was loosely matched
          // (e.g., "נחל שורק" matching "נח" returning "הפטרת נח" for "נח עליה ב").
          final refTokens = _tokenize(_normalizeForMatch(ref));
          if (!remainingTokens.every((qt) => refTokens.contains(qt))) continue;

          results.add(
            DbReferenceResult(
              title: title,
              reference: _qualifyAltTocReference(title, ref),
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
    // היסטורית הוזרמו 339 שאילתות SQL סדרתיות (אחת לכל ספר עם AltToc).
    // עכשיו אנחנו מחזיקים קאש שטוח שנבנה פעם אחת ב-session, וכל הסינון
    // הוא O(N) ב-Dart על רשימה in-memory.
    //
    // נעטף ב-try/catch כדי שכשלון במסלול ה-fallback לא יבלע את התוצאות
    // הקיימות מהלולאת ה-per-book.
    final bool perBookHasSpecificMatch = results.any(
      (r) => r.isAltToc || r.tocLevel >= 2,
    );
    if (!perBookHasSpecificMatch && queryTokens.length >= 2) {
      try {
        final flat = await _getAltTocFlatCache();
        for (final entry in flat) {
          // Require that ALL query tokens appear in the matched reference.
          // Prevents partial matches from unrelated books (e.g., "הפטרת נח"
          // matching only "נח" when the query is "נח עליה ב").
          if (!queryTokens.every((qt) => entry.refTokens.contains(qt))) {
            continue;
          }

          results.add(
            DbReferenceResult(
              title: entry.bookTitle,
              reference: _qualifyAltTocReference(
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
      } catch (e, st) {
        debugPrint('[FindRef] Global AltToc fallback failed: $e\n$st');
      }
    }

    if (includePersonalBooks) {
      results.addAll(await _searchPersonalBooks(queryTokens));
    }

    final unique = _dedupeRefs(results);
    final pruned = _suppressDeeperVariants(unique);
    final ranked = _rankResults(pruned, queryTokens);

    return await _enrichWithPaths(ranked);
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
  ) async {
    final searchFn =
        searchByEraAndTopic ?? ReferenceBooksCache.instance.searchByEraAndTopic;
    final hits = searchFn(era, topicTokens, limit: _maxResultCap);
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
  /// ההשוואה היא לפי `(bookId, isUserBook, isAltToc, isPdf)`: TOC ו-AltToc
  /// הם מבנים חלופיים — אחד לא מסתיר את השני. ספרים שונים בכלל אינם
  /// משפיעים אחד על השני. רמת ה-TOC המוחלטת לא רלוונטית כי מבני AltToc
  /// מתחילים ב-DB מ-level 0 בעוד TOC רגיל מ-1 — מה שחשוב הוא היחס prefix
  /// בלבד (כולל רווח בסוף, להבטיח גבול מילה שלמה).
  List<DbReferenceResult> _suppressDeeperVariants(
    List<DbReferenceResult> entries,
  ) {
    if (entries.length < 2) return entries;

    return entries.where((entry) {
      for (final other in entries) {
        if (identical(other, entry)) continue;
        if (other.bookId != entry.bookId) continue;
        if (other.isUserBook != entry.isUserBook) continue;
        if (other.isAltToc != entry.isAltToc) continue;
        if (other.isPdf != entry.isPdf) continue;
        // משווים אורך reference ולא tocLevel — TOC ו-AltToc מתחילים ברמות
        // שונות, וגם אם הרמות זהות, ה-prefix הקצר יותר הוא ה"אב" הלוגי.
        if (other.reference.length >= entry.reference.length) continue;
        // ה-prefix המלא — כולל רווח בסוף — מבטיח התאמת "מילה שלמה" ולא
        // התאמה חלקית של מחרוזת ("פרק א" לא חוסם "פרק אבות").
        if (entry.reference.startsWith('${other.reference} ')) return false;
      }
      return true;
    }).toList();
  }

  Future<List<DbReferenceResult>> _searchPersonalBooks(
    List<String> queryTokens,
  ) async {
    final out = <DbReferenceResult>[];
    try {
      // רשימת הספרים האישיים נטענת מקאש בזיכרון (ראה [_loadUserBooks]) — כך
      // אין שאילתת DB לכל הקלדה, רק בחיפוש הראשון אחרי רענון.
      final allBooks = await _loadUserBooks();
      SeforimRepository? userRepo;

      if (allBooks.isEmpty) return out;

      // Resolve user TOC fetcher (injection or live DB)
      Future<List<Map<String, dynamic>>> fetchUserToc(
        int bookId,
        String bookTitle, {
        List<String>? qt,
      }) async {
        final injected = getUserBookTocEntries;
        if (injected != null) {
          return injected(bookId, bookTitle, queryTokens: qt);
        }
        // `UserBooksDatabaseHolder.instance.repository` הוא `Future<SeforimRepository>`,
        // לכן נדרש `await` ולא cast — הקאסט הקודם היה זורק TypeError כש-userRepo
        // לא הוזרק מראש (תרחיש שטחי בטסטים, אך bug רדום שראוי לתקן).
        userRepo ??= await UserBooksDatabaseHolder.instance.repository;
        return userRepo!.getTocEntriesForReference(
          bookId,
          bookTitle,
          queryTokens: qt,
        );
      }

      const personalBookPath = 'ספרים אישיים';
      final maxN = queryTokens.length >= 3 ? 3 : queryTokens.length;

      for (final book in allBooks) {
        final normalizedTitle = _normalizeForMatch(book.title);
        final titleTokens = _tokenize(normalizedTitle);

        // Find the longest leading phrase that matches position-by-position
        int? matchedN;
        for (var n = maxN; n >= 1; n--) {
          final phrase = queryTokens.take(n).toList();
          if (phrase.length > titleTokens.length) continue;
          var ok = true;
          for (var i = 0; i < phrase.length; i++) {
            if (!titleTokens[i].startsWith(phrase[i])) {
              ok = false;
              break;
            }
          }
          if (ok) {
            matchedN = n;
            break;
          }
        }
        if (matchedN == null) continue;

        final isPdf = book.fileType == 'pdf';
        final remainingTokens = _getRemainingTokens(
          queryTokens,
          titleTokens,
          prefixMatchTokensCount: matchedN,
        );

        if (queryTokens.length == 1) {
          // Single-word: only the book title, no TOC (mirrors main loop)
          out.add(
            DbReferenceResult(
              title: book.title,
              reference: book.title,
              segment: 0,
              isPdf: isPdf,
              filePath: book.filePath ?? '',
              orderIndex: book.orderIndex,
              bookId: book.id,
              bookPath: personalBookPath,
              isUserBook: true,
            ),
          );
        } else if (remainingTokens.isEmpty) {
          // המשתמש הקליד רק את כותרת הספר — מחזירים את הספר בלבד, סימטרי
          // למסלול הראשי ולמסלול מילה-אחת לעיל.
          out.add(
            DbReferenceResult(
              title: book.title,
              reference: book.title,
              segment: 0,
              isPdf: isPdf,
              filePath: book.filePath ?? '',
              orderIndex: book.orderIndex,
              bookId: book.id,
              bookPath: personalBookPath,
              isUserBook: true,
            ),
          );
        } else {
          // Only TOC entries matching remainingTokens
          final toc = await fetchUserToc(
            book.id,
            book.title,
            qt: remainingTokens,
          );
          for (final entry in toc) {
            out.add(
              DbReferenceResult(
                title: book.title,
                reference: entry['reference'] as String,
                segment: entry['segment'] as int,
                isPdf: isPdf,
                filePath: book.filePath ?? '',
                orderIndex: book.orderIndex,
                tocLevel: entry['level'] as int,
                bookId: book.id,
                bookPath: personalBookPath,
                sourceLineId: entry['dbLineId'] as int? ?? 0,
                isUserBook: true,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[FindRef] Personal books search failed: $e');
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

    final pathFn =
        getCategoryPath ?? ReferenceBooksCache.instance.getCategoryPathForBook;
    final pathMap = <int, String>{};
    await Future.wait(
      uniqueIds.map((id) async {
        pathMap[id] = await pathFn(id);
      }),
    );

    final enriched = results.map((r) {
      if (r.bookPath.isNotEmpty) return r; // already set — don't overwrite
      final path = r.bookId > 0 ? (pathMap[r.bookId] ?? '') : '';
      if (path.isEmpty) return r;
      return DbReferenceResult(
        title: r.title,
        reference: r.reference,
        segment: r.segment,
        isPdf: r.isPdf,
        filePath: r.filePath,
        orderIndex: r.orderIndex,
        isAltToc: r.isAltToc,
        tocLevel: r.tocLevel,
        bookId: r.bookId,
        bookPath: path,
        sourceLineId: r.sourceLineId,
        isUserBook: r.isUserBook,
      );
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
      final titleTokens = _tokenize(hit.normalizedTitle);
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
      // Deduplicate by (bookId, isUserBook, title, segment, isPdf [, filePath]):
      //   - title|segment|isPdf — שני TOC/AltToc שמובילים לאותה שורה באותו ספר
      //     הם כפילות, ללא תלות בפורמט ה-reference
      //     ("בראשית תולדות עליה ב" מול "תולדות עליה ב").
      //   - bookId + isUserBook — שני ספרים *שונים* (למשל ספר רשמי וספר אישי,
      //     או שני רשמיים) בעלי אותה כותרת *אינם* כפילות; ה-namespace של
      //     user_books.db נפרד מזה של seforim.db ובלעדיהם מפתח אחיד היה
      //     מוחק את אחד מהם משרירותיות.
      //   - filePath נוסף **רק** עבור FS PDFs (`bookId == -1`): לכולם אותו
      //     bookId שלילי, וההבדלה היחידה ביניהם היא הקובץ עצמו. שני קבצי PDF
      //     שונים מהדיסק עם אותה כותרת חייבים לשרוד את ה-dedupe. עבור
      //     תוצאות DB אנחנו דווקא רוצים שה-filePath *לא* יבדיל — מסלול
      //     ה-global AltToc fallback מייצר תוצאה עם filePath ריק, וצריך
      //     להתמזג עם תוצאת ה-per-book של אותו bookId שיש לה filePath ידוע.
      final filePathKey = r.bookId == -1 ? r.filePath : '';
      final key =
          '${r.bookId}|${r.isUserBook}|${r.title}|${r.segment}|${r.isPdf}|$filePathKey';
      if (seen.add(key)) {
        out.add(r);
      }
    }

    return out;
  }

  List<DbReferenceResult> _rankResults(
    List<DbReferenceResult> results,
    List<String> queryTokens,
  ) {
    if (results.length < 2) return results;

    final query = queryTokens.join(' ');
    final needsTokenWiseRanking = queryTokens.length >= 2;

    // זיהוי סגנון ציון גמרא: הטוקן האחרון הוא "א" או "ב" + לפחות עוד טוקן.
    // כשמזוהה — ערכים שה-reference שלהם מכיל "דף" יקבלו עדיפות על פני ערכים
    // שאינם מכילים "דף" (כגון משנה), כדי ש-"שבת עא ב" יציג גמרא לפני משנה.
    final isDafCitation = _queryLooksDafCitation(queryTokens);

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
      final citationMatch = !isDafCitation || r.reference.contains('דף');
      // tier יסוד: 1=מקרא ... 10=שו"ע, null=מפרש/ספרות עזר.
      // ספרים אישיים: ה-bookId שלהם ב-namespace של user_books.db ועלול להתנגש
      // במזהה רשמי — שליפת נתיב לפיו הייתה מסווגת אותם לפי ספר זר.
      final categoryPath = (r.bookId > 0 && !r.isUserBook)
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
      final aRank = a.result.isAltToc
          ? 3
          : (a.result.tocLevel <= 2
                ? a.result.tocLevel
                : a.result.tocLevel + 1);
      final bRank = b.result.isAltToc
          ? 3
          : (b.result.tocLevel <= 2
                ? b.result.tocLevel
                : b.result.tocLevel + 1);
      if (aRank != bRank) return aRank.compareTo(bRank);

      return 0;
    }

    decorated.sort((a, b) {
      final rel = compareRelevance(a, b);
      if (rel != 0) return rel;
      // שובר-שוויון לתצוגה בלבד: ציון קצר יותר עולה קודם.
      final lenCmp = a.result.reference.length.compareTo(
        b.result.reference.length,
      );
      if (lenCmp != 0) return lenCmp;
      // "כג." ו-"כג:" שווי-אורך — בלי הכרעה לפי מיקום בספר, המיון (הלא-יציב)
      // עלול להציג עמוד ב לפני עמוד א.
      return a.result.segment.compareTo(b.result.segment);
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
    return [for (var i = 0; i < end; i++) decorated[i].result];
  }

  /// מחזיר true כשהשאילתה נראית כציון בסגנון גמרא (דף + עמוד).
  ///
  /// תנאי הזיהוי (כולם נדרשים):
  ///   1. הטוקן האחרון הוא "א" או "ב" (עמוד א/ב).
  ///   2. לפחות עוד טוקן קיים לפניו.
  ///   3. OR:  מופיע "דף" / "עמוד" במפורש בשאילתה
  ///      OR:  הטוקן לפני האחרון הוא מספר עברי של 2–4 אותיות (כמו "עא", "לט", "קה", "קמד"),
  ///           ואינו מילת מבנה ("פרק", "משנה", "פסוק", ...).
  ///           טוקן של אות בודדת או שם ספר ארוך אינם מפעילים את הבוסט.
  ///
  /// דוגמות שמפעילות: ["שבת","עא","ב"], ["ברכות","דף","כ","א"], ["נדה","ל","ב"]
  /// דוגמות שלא מפעילות: ["בראשית","א","ב"], ["ברכות","ב"], ["ברכות","פרק","א","ב"]
  bool _queryLooksDafCitation(List<String> tokens) {
    if (tokens.length < 2) return false;
    final last = tokens.last;
    if (last != 'א' && last != 'ב') {
      return false;
    }
    // מפורש — מילת "דף" או "עמוד" בשאילתה
    if (tokens.contains('דף') || tokens.contains('עמוד')) return true;
    // מספר דף עברי: 2–4 אותיות עבריות, ואינו מילת מבנה
    const structureWords = {
      'פרק',
      'משנה',
      'פסוק',
      'הלכה',
      'סעיף',
      'סימן',
      'חלק',
      'שאלה',
    };
    final penultimate = tokens[tokens.length - 2];
    if (structureWords.contains(penultimate)) return false;
    return penultimate.length >= 2 &&
        penultimate.length <= 4 &&
        penultimate.codeUnits.every(
          (c) => c >= 0x05D0 && c <= 0x05EA,
        ); // אותיות עבריות בלבד
  }

  String _normalize(String? s) =>
      (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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

  /// מצרף את שם הספר ל-prefix של reference יחסי מ-AltToc. אם ה-reference
  /// כבר מתחיל בשם הספר (אם פעם תתווסף שכבת ספרים שבה ה-DB מחזיר ערכים
  /// כוללים) — אין הכפלה.
  static String _qualifyAltTocReference(String bookTitle, String reference) {
    if (bookTitle.isEmpty) return reference;
    if (reference == bookTitle) return reference;
    if (reference.startsWith('$bookTitle ')) return reference;
    return '$bookTitle $reference';
  }
}

/// מפתחות מיון מחושבים מראש לדירוג תוצאות (decorate-sort-undecorate).
/// מאפשר ל-comparator להישאר זול — בלי נורמליזציה/טוקניזציה חוזרת.
class _RankKey {
  final DbReferenceResult result;
  final String normTitle;
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
    required this.exactMatch,
    required this.startsWithMatch,
    required this.titleTokens,
    required this.citationMatch,
    required this.foundationalTier,
    required this.era,
  });
}
