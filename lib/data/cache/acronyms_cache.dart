import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/cache/acronym_cache_data.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// קבוצת-על ממוינת של מזהי ספרים שכינוי שלהם עלול להתאים לשאילתה.
/// הבדיקה היא חיפוש בינארי — ללא הקצאות, כדי שתרוץ פעם אחת לכל ספר בכל הקלדה.
class AcronymCandidateBooks {
  const AcronymCandidateBooks._(this._sortedBookIds);

  final Int32List _sortedBookIds;

  /// האם ייתכן שכינוי של [bookId] מתאים לשאילתה. ההכרעה נשארת בידי הקורא —
  /// זו קבוצת-על.
  bool contains(int bookId) {
    var low = 0;
    var high = _sortedBookIds.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final value = _sortedBookIds[mid];
      if (value == bookId) return true;
      if (value < bookId) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return false;
  }

  /// בדיקות בלבד — מספר הספרים שנותרו לסריקה.
  @visibleForTesting
  int get length => _sortedBookIds.length;
}

/// In-memory cache for the `book_acronym` table, used for matching
/// book acronyms and alternative titles (FindRef, library book search).
///
/// המונחים נשמרים במצב מנורמל מראש (ללא ניקוד/גרשיים) כדי לחסוך
/// נורמליזציה חוזרת בכל חיפוש.
class AcronymsCache {
  AcronymsCache._();

  static final AcronymsCache instance = AcronymsCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;

  /// מונה דורות לזיהוי [clear] שקרה במהלך טעינה.
  int _generation = 0;

  final Map<int, List<String>> _acronymsByBookId = <int, List<String>>{};

  /// אינדקס ביגרמים: לכל צמד תווים סמוכים שמופיע במונח כלשהו — מזהי הספרים
  /// שלהם יש מונח כזה, ממוינים. המפתח הוא `(תו ראשון << 16) | תו שני`.
  final Map<int, Int32List> _bookIdsByBigram = <int, Int32List>{};

  static final AcronymCandidateBooks _noCandidates = AcronymCandidateBooks._(
    Int32List(0),
  );

  /// כינויי ספרי המסדים המצורפים, לפי slug — מרחב id נפרד לכל מסד.
  final Map<String, Map<int, List<String>>> _attachedAcronyms = {};
  Future<void>? _attachedLoading;
  int _attachedGeneration = 0;

  bool get isLoaded => _isLoaded;

  /// Returns all normalized acronyms for a given book ID.
  /// כל ערך כבר עבר [normalizeForFindRefMatch] בעת הטעינה.
  List<String>? getAcronymsForBook(int bookId) => _acronymsByBookId[bookId];

  /// הכינויים של ספר [bookId] במסד של [source]. לספר אישי אין כינויים.
  List<String>? acronymsFor(BookSource source, int bookId) => switch (source) {
    OfficialBookSource() => _acronymsByBookId[bookId],
    AttachedBookSource(:final slug) => _attachedAcronyms[slug]?[bookId],
    UserBookSource() => null,
  };

  /// טוען את טבלת `book_acronym` של כל מסד מצורף גלוי שעוד לא נטען, ב-isolate
  /// ובפתיחה מוקשחת. מסד בלי הטבלה או שקריאתו נכשלה נשאר בלי כינויים.
  Future<void> warmUpAttached() {
    final existing = _attachedLoading;
    if (existing != null) return existing;
    late final Future<void> loading;
    loading = _loadAttached().whenComplete(() {
      // clearAttached באמצע הטעינה כבר החליף אותה — לא מוחקים את הטעינה החדשה.
      if (identical(_attachedLoading, loading)) _attachedLoading = null;
    });
    return _attachedLoading = loading;
  }

  /// מסד שקריאתו נכשלה — מתי מותר לנסות שוב (כשל זמני אינו נשמר כ"אין כינויים").
  final Map<String, DateTime> _attachedRetryAfter = {};

  @visibleForTesting
  static Duration attachedRetryDelay = const Duration(minutes: 1);

  Future<void> _loadAttached() async {
    final myGen = _attachedGeneration;
    final now = DateTime.now();
    final pending = [
      for (final library in AttachedLibraryRegistry.instance.visibleLibraries)
        if (!_attachedAcronyms.containsKey(library.slug) &&
            !(_attachedRetryAfter[library.slug]?.isAfter(now) ?? false))
          library,
    ];
    await Future.wait([
      for (final library in pending)
        () async {
          final path = library.path;
          final immutable = library.immutable;
          try {
            final terms = await Isolate.run(
              () => readAttachedAcronyms(path, immutable: immutable),
            ).timeout(AttachedLibraryRegistry.openTimeout);
            if (myGen != _attachedGeneration) return;
            _attachedAcronyms[library.slug] = terms;
            _attachedRetryAfter.remove(library.slug);
          } catch (e) {
            debugPrint('[AcronymsCache] ${library.slug} acronyms skipped: $e');
            if (myGen != _attachedGeneration) return;
            _attachedRetryAfter[library.slug] = DateTime.now().add(
              attachedRetryDelay,
            );
          }
        }(),
    ]);
  }

  /// שוכח את כינויי המסדים המצורפים; הם נטענים שוב בגישה הבאה.
  void clearAttached() {
    _attachedGeneration++;
    _attachedAcronyms.clear();
    _attachedRetryAfter.clear();
    _attachedLoading = null;
  }

  /// קריאת הכינויים ממסד מצורף — רץ ב-isolate.
  @visibleForTesting
  static Map<int, List<String>> readAttachedAcronyms(
    String path, {
    bool immutable = false,
  }) {
    final db = openUntrustedReadOnlyDatabase(path, immutable: immutable);
    try {
      final hasTable = db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' "
        "AND name = 'book_acronym'",
      );
      if (hasTable.isEmpty) return const {};
      final rows = db.select('SELECT bookId, term FROM book_acronym');
      return buildAcronymCacheData([
        for (final row in rows)
          if (row['bookId'] is int && row['term'] is String)
            (row['bookId'] as int, row['term'] as String),
      ]).acronymsByBookId;
    } finally {
      db.close();
    }
  }

  /// קבוצת-על של הספרים שכינוי שלהם עלול להתאים ל-[normalizedQuery] — בזהות,
  /// בתחילית או בהכלה. `null` פירושו "אין צמצום, סרוק את כל הספרים".
  ///
  /// המסננת אינה מחמיצה: כל שלוש צורות ההתאמה דורשות מונח **שמכיל** את
  /// השאילתה, ומונח כזה מכיל בהכרח כל ביגרם שלה — ולכן הספר מופיע בכל רשימות
  /// הביגרמים, כולל הנדירה שבהן. שאילתה קצרה מ-2 תווים אינה ניתנת לאינדוקס.
  AcronymCandidateBooks? candidatesFor(String normalizedQuery) {
    // אינדקס ריק מול מונחים קיימים — נפילה לסריקה מלאה. קבוצה ריקה כאן
    // הייתה משתיקה כל התאמת כינויים, בלי שגיאה.
    if (!_isLoaded || _bookIdsByBigram.isEmpty) return null;
    if (normalizedQuery.length < 2) return null;

    Int32List? rarestBookIds;
    for (var i = 0; i + 1 < normalizedQuery.length; i++) {
      final bookIds =
          _bookIdsByBigram[_bigramKey(
            normalizedQuery.codeUnitAt(i),
            normalizedQuery.codeUnitAt(i + 1),
          )];
      // ביגרם שאינו במאגר — אף מונח אינו מכיל את השאילתה.
      if (bookIds == null) return _noCandidates;
      if (rarestBookIds == null || bookIds.length < rarestBookIds.length) {
        rarestBookIds = bookIds;
      }
    }
    return AcronymCandidateBooks._(rarestBookIds!);
  }

  Future<void> warmUp() async {
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;

    _loadingFuture = _loadInternal();

    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _loadInternal() async {
    final myGen = _generation;
    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      debugPrint('[AcronymsCache] DB not initialized; skipping warmup');
      if (myGen == _generation) {
        _acronymsByBookId.clear();
        _bookIdsByBigram.clear();
        _isLoaded = false;
      }
      return;
    }

    try {
      final data = await (await FindRefDbIsolate.instance())
          .getBookAcronymCache();

      if (myGen != _generation) return;
      _acronymsByBookId
        ..clear()
        ..addAll(data.acronymsByBookId);
      _bookIdsByBigram
        ..clear()
        ..addAll(data.bookIdsByBigram);
      _isLoaded = true;
      debugPrint(
        '[AcronymsCache] Loaded ${data.rowCount} acronyms for ${_acronymsByBookId.length} books',
      );
    } catch (e) {
      debugPrint('[AcronymsCache] Warmup failed: $e');
      // לא מסמנים loaded: כשל זמני (למשל DB locked בעלייה) יאופשר retry
      // ב-warmUp הבא, במקום ראשי-תיבות ריקים לכל ה-session.
      if (myGen == _generation) {
        _acronymsByBookId.clear();
        _bookIdsByBigram.clear();
      }
    }
  }

  void clear() {
    _generation++;
    _attachedGeneration++;
    _attachedAcronyms.clear();
    _attachedRetryAfter.clear();
    _attachedLoading = null;
    _acronymsByBookId.clear();
    _bookIdsByBigram.clear();
    _isLoaded = false;
    _loadingFuture = null;
  }

  /// בדיקות בלבד — מזריק מונחים גולמיים (כמו ב-DB) ומנרמל אותם כמו הטעינה
  /// האמיתית, כדי לבדוק את מסלול ההתאמה בלי DB.
  @visibleForTesting
  void setAttachedAcronymsForTesting(
    String slug,
    Map<int, List<String>> rawTermsByBookId,
  ) {
    _attachedAcronyms[slug] = buildAcronymCacheData(
      rawTermsByBookId.entries.expand(
        (entry) => entry.value.map((term) => (entry.key, term)),
      ),
    ).acronymsByBookId;
  }

  @visibleForTesting
  void setAcronymsForTesting(Map<int, List<String>> rawTermsByBookId) {
    final data = buildAcronymCacheData(
      rawTermsByBookId.entries.expand(
        (entry) => entry.value.map((term) => (entry.key, term)),
      ),
    );
    _acronymsByBookId
      ..clear()
      ..addAll(data.acronymsByBookId);
    _bookIdsByBigram
      ..clear()
      ..addAll(data.bookIdsByBigram);
    _isLoaded = true;
  }
}

int _bigramKey(int first, int second) => (first << 16) | second;
