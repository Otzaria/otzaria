import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/book_aliases/book_aliases.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

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
  int _revision = 0;

  /// משתנה כשכינויי הספרים משתנים, כולל השלמת טעינה של מסד מצורף.
  int get revision => _revision;

  static const _empty = AcronymCacheData(
    acronymsByBookId: {},
    bookIdsByBigram: {},
    rowCount: 0,
  );

  /// כינויי הקטלוג הרשמי ואינדקס הביגרמים שלהם.
  AcronymCacheData _official = _empty;

  /// כינויי ספרי המסדים המצורפים, לפי slug — מרחב id נפרד לכל מסד.
  final Map<String, Map<int, List<String>>> _attachedAcronyms = {};
  Future<void>? _attachedLoading;
  int _attachedGeneration = 0;

  bool get isLoaded => _isLoaded;

  /// Returns all normalized acronyms for a given book ID.
  /// כל ערך כבר עבר [normalizeForFindRefMatch] בעת הטעינה.
  List<String>? getAcronymsForBook(int bookId) =>
      _official.acronymsByBookId[bookId];

  /// ראו [AcronymCacheData.quotedWordsByBookId]. רק לקטלוג הרשמי.
  Set<String> quotedWordsForBook(int bookId) =>
      _official.quotedWordsByBookId[bookId] ?? const <String>{};

  /// הכינויים המילוליים של ספר [bookId] במסד של [source]. לספר אישי אין.
  List<String>? acronymsFor(BookSource source, int bookId) => switch (source) {
    OfficialBookSource() => _official.acronymsByBookId[bookId],
    AttachedBookSource(:final slug) => _attachedAcronyms[slug]?[bookId],
    UserBookSource() => null,
  };

  /// כל הכינויים של ספר לחיפוש — המילוליים של המסד שלו ואחריהם הנגזרים מכותרתו
  /// ([bookAliasesOf]). כך מקבל כינויים גם ספר אישי, ספר בלי מזהה ומסד מצורף
  /// בלי טבלת `book_acronym`.
  List<String> aliasesFor(BookSource source, int? bookId, String title) =>
      bookAliasesForTitle(
        bookId == null ? null : acronymsFor(source, bookId),
        title,
      );

  /// כל הכינויים של מסד מצורף, או `null` כשלא נטענו. מוחלף בכל טעינה מחדש.
  Map<int, List<String>>? attachedAcronymsOf(String slug) =>
      _attachedAcronyms[slug];

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
            if (terms.isNotEmpty) _revision++;
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
    _revision++;
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
      return collectBookAliasTerms(
        [
          for (final row in db.select('SELECT bookId, term FROM book_acronym'))
            if (row['bookId'] case final int bookId)
              if (row['term'] case final String term) (bookId, term),
        ],
        normalizeForFindRefMatch,
        withQuotedWords: false,
      ).aliasesByBookId;
    } finally {
      db.close();
    }
  }

  /// ראו [AcronymCacheData.candidatesFor]; `null` גם כשהקאש עוד לא נטען.
  AcronymCandidateBooks? candidatesFor(String normalizedQuery) =>
      _isLoaded ? _official.candidatesFor(normalizedQuery) : null;

  Future<void> warmUp() async {
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;

    final loading = _loadInternal();
    _loadingFuture = loading;
    try {
      await loading;
    } finally {
      // clear() may have started a newer generation while this one awaited.
      // Never detach that newer in-flight load.
      if (identical(_loadingFuture, loading)) _loadingFuture = null;
    }
  }

  Future<void> _loadInternal() async {
    final myGen = _generation;
    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      debugPrint('[AcronymsCache] DB not initialized; skipping warmup');
      if (myGen == _generation) {
        _official = _empty;
        _isLoaded = false;
      }
      return;
    }

    try {
      final data = await (await FindRefDbIsolate.instance())
          .getBookAcronymCache();

      if (myGen != _generation) return;
      _official = data;
      _isLoaded = true;
      _revision++;
      debugPrint(
        '[AcronymsCache] Loaded ${data.rowCount} acronyms for ${data.acronymsByBookId.length} books',
      );
    } catch (e) {
      debugPrint('[AcronymsCache] Warmup failed: $e');
      // לא מסמנים loaded: כשל זמני (למשל DB locked בעלייה) יאופשר retry
      // ב-warmUp הבא, במקום ראשי-תיבות ריקים לכל ה-session.
      if (myGen == _generation) {
        _official = _empty;
      }
    }
  }

  void clear() {
    _generation++;
    clearAttached();
    _official = _empty;
    _isLoaded = false;
    _loadingFuture = null;
  }

  @visibleForTesting
  void setAcronymsForTesting(Map<int, List<String>> rawTermsByBookId) {
    final data = buildAcronymCacheData(
      rawTermsByBookId.entries.expand(
        (entry) => entry.value.map((term) => (entry.key, term)),
      ),
      normalizeForFindRefMatch,
    );
    _official = data;
    _isLoaded = true;
    _revision++;
  }
}
