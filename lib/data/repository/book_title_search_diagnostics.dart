import 'dart:async';

import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/repository/book_search_worker.dart';
import 'package:otzaria/search/active_lexical_searches.dart'
    show SearchStallWriter;

/// ההמתנה שבה נמצא חיפוש שם ספר, לפי סדר השלבים ב-findBooksAndCategories.
enum BookTitleSearchStage {
  started,
  library,
  externalCatalogs,
  acronyms,
  attachedAcronyms,
  generations,
  catalog,
  worker,
  results,
}

/// מעקב זול אחרי חיפוש שמות הספרים: המקטע `bookTitleSearch` בדוח, ורשומה
/// ב-errors.txt כשחיפוש לא הסתיים תוך [stallThreshold], שנשמרת גם אחרי הפעלה מחדש.
class BookTitleSearchDiagnostics {
  BookTitleSearchDiagnostics({
    this.stallThreshold = const Duration(seconds: 60),
    DateTime Function()? now,
    SearchStallWriter? writeLog,
  }) : _now = now ?? DateTime.now,
       _writeLog = writeLog ?? ErrorLogFile.appendInBackground;

  static BookTitleSearchDiagnostics instance = BookTitleSearchDiagnostics();
  static const _maxActiveDetails = 32;

  /// `null` מכבה את רשומת התקיעה.
  final Duration? stallThreshold;
  final DateTime Function() _now;
  final SearchStallWriter _writeLog;
  final Set<TrackedBookTitleSearch> _active = {};
  Map<String, Object?> Function()? _repositoryState;
  Map<String, Object?>? _last;
  Timer? _stallTimer;
  TrackedBookTitleSearch? _watchedSearch;
  DateTime? _unsampledSince;
  int? _stallId;
  int _activeCount = 0;
  int _started = 0;
  int _failed = 0;
  int _superseded = 0;
  bool _emptyCatalogLogged = false;
  int _nextId = 0;

  /// [repositoryState] מתאר את ה-worker והמטמונים; נקרא רק בדוח וברשומת יומן.
  TrackedBookTitleSearch start({
    required int words,
    required bool wholeLibrary,
    Map<String, Object?> Function()? repositoryState,
  }) {
    _started++;
    _repositoryState = repositoryState ?? _repositoryState;
    final search = TrackedBookTitleSearch._(
      this,
      ++_nextId,
      words,
      wholeLibrary,
      _now(),
    );
    _activeCount++;
    // החיפושים הראשונים נשמרים לאבחון גם כשההמתנה חוסמת הקלדות נוספות.
    if (_active.length < _maxActiveDetails) {
      _active.add(search);
      if (_active.length == 1) _watchOldest();
    } else {
      _unsampledSince ??= search.startedAt;
    }
    return search;
  }

  void _watchOldest() {
    final threshold = stallThreshold;
    if (threshold == null ||
        _activeCount == 0 ||
        _stallId != null ||
        _stallTimer != null) {
      return;
    }
    final oldest = _active.firstOrNull;
    final unsampledSince = _unsampledSince;
    final watchUnsampled =
        unsampledSince != null &&
        (oldest == null || unsampledSince.isBefore(oldest.startedAt));
    final watched = _watchedSearch = watchUnsampled ? null : oldest;
    final startedAt = watched?.startedAt ?? unsampledSince!;
    final elapsed = _now().difference(startedAt);
    _stallTimer = Timer(threshold - elapsed, () {
      _stallTimer = null;
      _watchedSearch = null;
      final stallId = _stallId = watched?.id ?? ++_nextId;
      final duration = '${threshold.inSeconds}s';
      _log(
        'Library title search stall',
        watched == null
            ? 'Pending book title searches not sampled by diagnostics '
                  'did not clear within $duration'
            : 'Book title search #${watched.id} did not finish within $duration',
        {
          if (watched != null) ...watched.describe(),
          if (watched == null)
            'Unsampled active searches': _activeCount - _active.length,
          'Stall id': stallId,
          'Active searches': _activeCount,
        },
      );
    });
  }

  void _finished(TrackedBookTitleSearch search, String outcome) {
    final last = _last = search.describe()..['outcome'] = outcome;
    _active.remove(search);
    _activeCount--;
    if (_activeCount == _active.length) _unsampledSince = null;

    final stallId = _stallId;
    if (stallId != null) {
      final oldest = _active.firstOrNull;
      // כשיש חיפושים מחוץ למדגם, מחכים לסיומם לפני דיווח על התאוששות.
      if (_activeCount > _active.length ||
          (oldest != null &&
              _now().difference(oldest.startedAt) >= stallThreshold!)) {
        return;
      }
      _stallId = null;
      _log(
        'Library title search stall resolved',
        'Book title search stall #$stallId ended (last: $outcome)',
        {...last, 'Stall id': stallId, 'Active searches': _activeCount},
      );
    } else if (_watchedSearch == null
        ? _activeCount > _active.length
        : !identical(_watchedSearch, search)) {
      return;
    }

    _stallTimer?.cancel();
    _stallTimer = null;
    _watchedSearch = null;
    _watchOldest();
  }

  /// המפתח `bookTitleSearch` ב-diagnostics.json.
  Map<String, dynamic> collect() => {
    'started': _started,
    'failed': _failed,
    'superseded': _superseded,
    'activeCount': _activeCount,
    'stallId': ?_stallId,
    'active': [for (final search in _active) search.describe()],
    'last': ?_last,
    'repository': ?_describeRepository(),
  };

  Map<String, Object?>? _describeRepository() {
    try {
      return _repositoryState?.call();
    } catch (error) {
      return {'error': error.runtimeType.toString()};
    }
  }

  void _log(String title, String error, Map<String, Object?> details) {
    try {
      _writeLog(
        title: title,
        error: error,
        details: {
          for (final MapEntry(:key, :value) in details.entries) key: '$value',
          'Repository': '${_describeRepository()}',
        },
      );
    } catch (_) {}
  }
}

class TrackedBookTitleSearch {
  TrackedBookTitleSearch._(
    this._owner,
    this.id,
    this.words,
    this.wholeLibrary,
    this.startedAt,
  ) : _stageSince = startedAt;

  final BookTitleSearchDiagnostics _owner;
  final int id;
  final int words;
  final bool wholeLibrary;
  final DateTime startedAt;
  BookTitleSearchStage _stage = BookTitleSearchStage.started;
  DateTime _stageSince;
  int? _catalogBooks;
  int? _books;
  int? _categories;
  bool _finished = false;

  BookTitleSearchStage get stage => _stage;

  void enter(BookTitleSearchStage stage) {
    if (_finished) return;
    _stage = stage;
    _stageSince = _owner._now();
  }

  void catalogBuilt(int books) => _catalogBooks = books;

  void found({required int books, required int categories}) {
    enter(BookTitleSearchStage.results);
    _books = books;
    _categories = categories;
    if (books == 0 &&
        wholeLibrary &&
        _catalogBooks == 0 &&
        !_owner._emptyCatalogLogged) {
      _owner._emptyCatalogLogged = true;
      _owner._log(
        'Library title search: empty catalog',
        'Book title search #$id ran on a library with no books',
        describe(),
      );
    }
  }

  /// מסיר מהרישום; קריאה נוספת אינה עושה דבר.
  void finish([Object? error]) {
    if (_finished) return;
    final outcome = switch (error) {
      null when _books != null => 'ok',
      null => 'noQuery',
      BookSearchSupersededException() => 'superseded',
      _ => 'error:${error.runtimeType}',
    };
    if (error is BookSearchSupersededException) {
      _owner._superseded++;
    } else if (error != null) {
      _owner._failed++;
    }
    _finished = true;
    _owner._finished(this, outcome);
  }

  Map<String, Object?> describe() {
    final now = _owner._now();
    return {
      'id': id,
      'stage': _stage.name,
      'elapsedMs': now.difference(startedAt).inMilliseconds,
      'stageMs': now.difference(_stageSince).inMilliseconds,
      'words': words,
      'wholeLibrary': wholeLibrary,
      'catalogBooks': ?_catalogBooks,
      'books': ?_books,
      'categories': ?_categories,
    };
  }
}
