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

  /// `null` מכבה את רשומת התקיעה.
  final Duration? stallThreshold;
  final DateTime Function() _now;
  final SearchStallWriter _writeLog;
  final List<TrackedBookTitleSearch> _active = [];
  Map<String, Object?> Function()? _repositoryState;
  Map<String, Object?>? _last;
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
    _active.add(search);
    final threshold = stallThreshold;
    if (threshold != null) {
      search._stallTimer = Timer(threshold, search._onStall);
    }
    return search;
  }

  /// המפתח `bookTitleSearch` ב-diagnostics.json.
  Map<String, dynamic> collect() => {
    'started': _started,
    'failed': _failed,
    'superseded': _superseded,
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
  Timer? _stallTimer;
  bool _stallLogged = false;
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
    _owner._last = {...describe(), 'outcome': outcome};
    _finished = true;
    _stallTimer?.cancel();
    _stallTimer = null;
    _owner._active.remove(this);
    if (_stallLogged) {
      _owner._log(
        'Library title search stall resolved',
        'Book title search #$id ended ($outcome)',
        _owner._last!,
      );
    }
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

  void _onStall() {
    _stallTimer = null;
    if (_finished || _stallLogged) return;
    _stallLogged = true;
    _owner._log(
      'Library title search stall',
      'Book title search #$id did not finish within '
          '${_owner.stallThreshold?.inSeconds}s',
      {...describe(), 'Active searches': _owner._active.length},
    );
  }
}
