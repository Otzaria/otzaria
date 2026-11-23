import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/bridge/plugin_semantic_api.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

/// איתור ספרים לפי זהות ה-SDK, ומפת הספרים לפי הנתיב שבו הם מאונדקסים.
typedef PluginSemanticBookLookup = ({
  Book? Function(Map<String, dynamic> identity) find,
  Map<String, Book> byIndexedPath,
});

/// `semantic.*` של מופע תוסף אחד, מעל [SemanticSearchRepository].
///
/// הכללים: הכול מלבד `getStatus` ו-`openSettings` דורש שהחיפוש הסמנטי יהיה
/// שמיש (הסכמה ונתונים מותקנים); `nearest` חדש של המופע מחליף את הקודם שלו;
/// חיפוש של המשתמש מבטל פעולות של תוספים, והן מסתיימות ב-`error.preempted`.
class PluginSemanticBridge {
  PluginSemanticBridge({
    required this._books,
    required this._openSettings,
    SemanticSearchRepository Function()? repository,
  }) : _repository = repository ?? (() => SemanticSearchRepository.instance);

  final Future<PluginSemanticBookLookup> Function() _books;
  final Future<bool> Function() _openSettings;
  final SemanticSearchRepository Function() _repository;

  static const streamEvent = '__otzaria.semantic.nearest.chunk';

  // אותם מפתחות פנימיים כמו בזרמי search.query (PluginBridgeAdapter).
  static const _streamIdKey = '__streamId';
  static const _cancelStreamIdKey = '__cancelStreamId';
  static final _streamIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  @visibleForTesting
  static Duration maxDuration = const Duration(minutes: 2);

  /// הסריקה הרצה של המופע: חדשה מחליפה אותה, כמו הקלדה במסך החיפוש.
  SemanticBackgroundCall? _nearestCall;

  final Map<String, void Function()> _activeStreams = {};
  final Set<String> _pendingCancellations = {};
  final Set<SemanticBackgroundCall> _calls = {};

  /// עולה בכל [release]: פעולות של הדף הקודם אינן ממשיכות בדף הבא.
  int _page = 0;

  Future<dynamic> handle(
    String action,
    Map<String, dynamic> args, {
    required Future<void> Function(String topic, Map<String, dynamic> payload)?
    eventSink,
  }) async {
    try {
      switch (action) {
        case 'getStatus':
          return await _status();
        case 'countTokens':
          return await _countTokens(args);
        case 'getCoveredBooks':
          return await _coveredBooks(args);
        case 'openSettings':
          return await _openSettings();
        case 'nearest':
          if (args[_cancelStreamIdKey] case final String streamId) {
            return _cancelStream(streamId);
          }
          return await _nearest(args, eventSink);
        default:
          throw Exception(
            'error.unknown_method: Unknown action in semantic: $action',
          );
      }
    } on SemanticFailure catch (failure) {
      throw _pluginError(failure);
    }
  }

  /// מבטל את כל מה שהמופע מריץ; נקרא כשהדף נסגר או נטען מחדש.
  void release() {
    _page++;
    for (final cancel in _activeStreams.values) {
      cancel();
    }
    _activeStreams.clear();
    _pendingCancellations.clear();
    for (final call in _calls) {
      call.cancel();
    }
    _calls.clear();
  }

  // ── getStatus ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _status() async {
    final repository = _repository();
    final availability = await repository.refresh();
    if (availability.phase == SemanticAvailabilityPhase.hidden) {
      return PluginSemanticApi.statusToJson(availability);
    }
    final vectors = await repository.vectorsInfo();
    final snapshot = await repository.engineSnapshot();
    return PluginSemanticApi.statusToJson(
      availability,
      vectors: vectors,
      modelFamilyId: snapshot.modelFamilyId,
      dim: snapshot.embeddingDim,
      vectorsReleaseTag: snapshot.vectorsReleaseTag,
    );
  }

  // ── countTokens ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _countTokens(Map<String, dynamic> args) async {
    final texts = PluginSemanticApi.parseTokenTexts(args);
    await _requireReady();
    final tokens = await _background(
      (call) => _repository().queryTokens(texts, call: call),
    );
    return PluginSemanticApi.tokensToJson(tokens);
  }

  // ── getCoveredBooks ───────────────────────────────────────────────────────

  /// התשובה האחרונה, לפי מצב הסט ומספר הפעמים שהאינדקס השתנה מאז.
  static ({String key, engine.SemanticCoveredBooks books})? _coveredCache;
  static int _indexEpoch = 0;
  static ValueNotifier<bool>? _watchedIndexing;

  @visibleForTesting
  static ValueNotifier<bool> Function() indexingNotifier = () =>
      TantivyDataProvider.instance.isIndexing;

  /// כל אינדוקס עשוי לשנות את הכיסוי גם כשהסט לא השתנה.
  static void _watchIndexing() {
    final notifier = indexingNotifier();
    if (identical(notifier, _watchedIndexing)) return;
    _watchedIndexing = notifier;
    _indexEpoch++;
    notifier.addListener(() {
      if (identical(notifier, _watchedIndexing)) _indexEpoch++;
    });
  }

  Future<Map<String, dynamic>> _coveredBooks(Map<String, dynamic> args) async {
    if (args.isNotEmpty) {
      throw Exception('error.invalid_params: getCoveredBooks takes no params');
    }
    await _requireReady();
    _watchIndexing();
    final vectors = await _repository().vectorsInfo();
    final key =
        '${vectors.identityDigest}:${vectors.generation}:'
        '${vectors.libraryVersion}:$_indexEpoch';
    final cached = _coveredCache;
    final engine.SemanticCoveredBooks covered;
    if (cached != null && cached.key == key) {
      covered = cached.books;
    } else {
      covered = await _background(
        (call) => _repository().coveredBooks(call: call),
      );
      _coveredCache = (key: key, books: covered);
    }
    final lookup = await _books();
    return PluginSemanticApi.coveredBooksToJson(covered, lookup.byIndexedPath);
  }

  @visibleForTesting
  static void resetForTesting() => _coveredCache = null;

  // ── nearest ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _cancelStream(String streamId) {
    if (!_streamIdPattern.hasMatch(streamId)) {
      throw Exception('error.invalid_params: invalid internal stream id');
    }
    final cancel = _activeStreams[streamId];
    if (cancel == null) {
      if (_pendingCancellations.length < 16) {
        _pendingCancellations.add(streamId);
      }
      return {'cancelled': false};
    }
    cancel();
    return {'cancelled': true};
  }

  Future<Map<String, dynamic>> _nearest(
    Map<String, dynamic> args,
    Future<void> Function(String topic, Map<String, dynamic> payload)?
    eventSink,
  ) async {
    final streamId = args[_streamIdKey];
    if (streamId is! String || !_streamIdPattern.hasMatch(streamId)) {
      throw Exception('error.invalid_params: invalid internal stream id');
    }
    if (eventSink == null) {
      throw Exception('error.internal: semantic stream transport unavailable');
    }
    if (_pendingCancellations.remove(streamId)) {
      return {'completed': false, 'cancelled': true};
    }
    if (_activeStreams.containsKey(streamId)) {
      throw Exception('error.invalid_params: duplicate semantic stream id');
    }
    final publicArgs = Map<String, dynamic>.of(args)..remove(_streamIdKey);
    final input = PluginSemanticApi.parseNearest(
      publicArgs,
      findBook: (await _books()).find,
    );
    final page = _page;
    await _requireReady();
    if (_pendingCancellations.remove(streamId) || page != _page) {
      return {'completed': false, 'cancelled': true};
    }

    final call = SemanticBackgroundCall();
    _nearestCall?.cancel();
    _nearestCall = call;
    var cancelledByPlugin = false;
    _activeStreams[streamId] = () {
      cancelledByPlugin = true;
      call.cancel();
    };
    var expired = false;
    final deadline = Timer(maxDuration, () {
      expired = true;
      call.cancel();
    });
    var chunks = 0;
    Future<void> send(Map<String, dynamic> chunk) {
      chunks++;
      return eventSink(streamEvent, {'streamId': streamId, 'chunk': chunk});
    }

    try {
      Future<void>? progress;
      final response = await _repository().nearest(
        input,
        call: call,
        onSearching: () =>
            progress = send(const {'type': 'progress', 'phase': 'searching'}),
      );
      await progress;
      if (response == null) {
        if (expired) throw TimeoutException('Semantic nearest timed out');
        if (cancelledByPlugin || page != _page) {
          return {'completed': false, 'cancelled': true, 'chunks': chunks};
        }
        if (!identical(_nearestCall, call)) {
          return {
            'completed': false,
            'cancelled': true,
            'superseded': true,
            'chunks': chunks,
          };
        }
        throw await _interrupted(call, page);
      }
      final lookup = await _books();
      for (final chunk in PluginSemanticApi.responseChunks(
        response,
        lookup.byIndexedPath,
        rescored: input.rescore,
      )) {
        if (cancelledByPlugin || page != _page) {
          return {'completed': false, 'cancelled': true, 'chunks': chunks};
        }
        await send(chunk);
      }
      return {'completed': true, 'cancelled': false, 'chunks': chunks};
    } finally {
      deadline.cancel();
      _activeStreams.remove(streamId);
      if (identical(_nearestCall, call)) _nearestCall = null;
    }
  }

  // ── כללים משותפים ─────────────────────────────────────────────────────────

  Future<void> _requireReady() async {
    final availability = await _repository().refresh();
    if (!availability.isUsable) {
      throw Exception(
        'error.unavailable: semantic search is not ready '
        '(phase: ${PluginSemanticApi.phaseOf(availability)})',
      );
    }
  }

  /// פעולה קצרה שאינה זרם; בוטלה רק בגלל ההסכמה, המשתמש או הזמן.
  Future<T> _background<T>(
    Future<T?> Function(SemanticBackgroundCall call) run,
  ) async {
    final call = SemanticBackgroundCall();
    final page = _page;
    _calls.add(call);
    var expired = false;
    final deadline = Timer(maxDuration, () {
      expired = true;
      call.cancel();
    });
    try {
      final result = await run(call);
      if (result != null) return result;
      if (expired) throw TimeoutException('Semantic call timed out');
      throw await _interrupted(call, page);
    } finally {
      deadline.cancel();
      _calls.remove(call);
    }
  }

  /// למה פעולה שלא בוטלה בידי התוסף לא הסתיימה.
  Future<Exception> _interrupted(SemanticBackgroundCall call, int page) async {
    if (call.preempted) {
      return Exception(
        'error.preempted: a search in Otzaria took precedence; try again',
      );
    }
    if (page != _page) {
      return Exception('error.unavailable: the plugin page was closed');
    }
    final availability = await _repository().refresh();
    return Exception(
      'error.unavailable: semantic search was interrupted '
      '(phase: ${PluginSemanticApi.phaseOf(availability)})',
    );
  }

  static Exception _pluginError(SemanticFailure failure) =>
      switch (failure.kind) {
        SemanticFailureKind.invalidInput => Exception(
          'error.invalid_params: ${failure.message}',
        ),
        SemanticFailureKind.queryFailed || SemanticFailureKind.internal =>
          Exception('error.internal: semantic ${failure.kind.name}'),
        _ => Exception('error.unavailable: semantic ${failure.kind.name}'),
      };
}
