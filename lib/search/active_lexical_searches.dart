import 'dart:async';

import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/search/search_query_builder.dart';

/// השלב של חיפוש מילולי פעיל, לפי האירוע האחרון שהגיע מהמנוע.
enum LexicalSearchPhase {
  waitingFirstPage,
  counting,
  streamingResults,
  loadingMore,
}

typedef SearchStallWriter =
    void Function({
      required String title,
      required Object error,
      Map<String, String?> details,
    });

/// רישום משותף לכל לשוניות החיפוש: מה רץ עכשיו, ורשומת `Search stall` ב-errors.txt
/// לחיפוש שלא הסתיים תוך [stallThreshold] — המנוע לא ענה, וה-UI לא נתקע.
class ActiveLexicalSearches {
  ActiveLexicalSearches({
    this.stallThreshold = const Duration(seconds: 60),
    DateTime Function()? now,
    SearchStallWriter? writeStall,
  }) : _now = now ?? DateTime.now,
       _writeStall = writeStall ?? ErrorLogFile.appendInBackground;

  static ActiveLexicalSearches instance = ActiveLexicalSearches();

  /// `null` מכבה את גילוי התקיעות (טסטים שמשאירים חיפוש פתוח).
  final Duration? stallThreshold;
  final DateTime Function() _now;
  final SearchStallWriter _writeStall;
  final List<TrackedLexicalSearch> _active = [];
  int _nextId = 0;

  List<TrackedLexicalSearch> get active => List.unmodifiable(_active);

  TrackedLexicalSearch start(
    Map<String, Object?> query, {
    LexicalSearchPhase phase = LexicalSearchPhase.waitingFirstPage,
    int received = 0,
  }) {
    final search = TrackedLexicalSearch._(
      this,
      ++_nextId,
      query,
      _now(),
      phase,
      received,
    );
    _active.add(search);
    final threshold = stallThreshold;
    if (threshold != null) {
      search._stallTimer = Timer(threshold, search._onStall);
    }
    return search;
  }

  /// המפתח `searches` ב-diagnostics.json.
  Map<String, dynamic> collect() => {
    'activeCount': _active.length,
    'lexical': [for (final search in _active) search.describe()],
  };

  /// מאפייני שאילתה בלי הטקסט עצמו: מילות השאילתה ומפתחות [searchOptions]
  /// מזהים את מה שהמשתמש חיפש.
  static Map<String, Object?> describeQuery({
    required String query,
    required String negativeQuery,
    required String mode,
    required Map<String, Map<String, bool>> searchOptions,
    required Map<int, List<String>> alternativeWords,
    required Map<String, String> customSpacing,
    required int facets,
    required bool isRegex,
  }) {
    final options = <String>{
      for (final wordOptions in searchOptions.values)
        for (final MapEntry(:key, :value) in wordOptions.entries)
          if (value)
            SearchQueryBuilder.pluginOptionIdByWordOptionKey[key] ?? 'other',
    }.toList()..sort();
    final trimmed = query.trim();
    return {
      'words': trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length,
      'mode': mode,
      'regex': isRegex,
      'prefixes': options.any((o) => o.contains('prefixes')),
      'suffixes': options.any((o) => o.contains('suffixes')),
      'options': options,
      'wordsWithAlternatives': alternativeWords.values
          .where((v) => v.isNotEmpty)
          .length,
      'customSpacing': customSpacing.length,
      'negative': negativeQuery.trim().isNotEmpty,
      'facets': facets,
    };
  }
}

class TrackedLexicalSearch {
  TrackedLexicalSearch._(
    this._owner,
    this.id,
    this.query,
    this.startedAt,
    this._phase,
    this._received,
  ) : _lastEventAt = startedAt;

  final ActiveLexicalSearches _owner;
  final int id;
  final Map<String, Object?> query;
  final DateTime startedAt;
  LexicalSearchPhase _phase;
  int _received;
  int? _total;
  DateTime _lastEventAt;
  Timer? _stallTimer;
  bool _stallLogged = false;
  bool _finished = false;

  LexicalSearchPhase get phase => _phase;
  bool get isFinished => _finished;

  void onEvent({LexicalSearchPhase? phase, int? received, int? total}) {
    if (_finished) return;
    _lastEventAt = _owner._now();
    if (phase != null) _phase = phase;
    if (received != null) _received = received;
    if (total != null) _total = total;
  }

  /// מסיר מהרישום ומבטל את הטיימר; קריאה נוספת אינה עושה דבר.
  void finish(String outcome) {
    if (_finished) return;
    _finished = true;
    _stallTimer?.cancel();
    _stallTimer = null;
    _owner._active.remove(this);
    if (!_stallLogged) return;
    try {
      _owner._writeStall(
        title: 'Search stall resolved',
        error: 'Lexical search #$id ended ($outcome)',
        details: _details()..['Outcome'] = outcome,
      );
    } catch (_) {}
  }

  Map<String, Object?> describe() {
    final now = _owner._now();
    return {
      'id': id,
      'phase': _phase.name,
      'elapsedMs': now.difference(startedAt).inMilliseconds,
      'sinceLastEventMs': now.difference(_lastEventAt).inMilliseconds,
      'received': _received,
      'total': _total,
      'query': query,
      'stallLogged': _stallLogged,
    };
  }

  Map<String, String?> _details() => {
    for (final MapEntry(:key, :value) in describe().entries)
      if (key != 'stallLogged') key: '$value',
    'Active searches': '${_owner._active.length}',
  };

  void _onStall() {
    _stallTimer = null;
    if (_finished || _stallLogged) return;
    _stallLogged = true;
    try {
      _owner._writeStall(
        title: 'Search stall',
        error:
            'Lexical search #$id did not finish within '
            '${_owner.stallThreshold?.inSeconds}s',
        details: _details(),
      );
    } catch (_) {}
  }
}
