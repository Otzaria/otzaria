import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/bridge/plugin_semantic_api.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticPool;

/// איתור ספרים רשמיים לפי זהות ה-SDK ולפי הנתיב באינדקס.
typedef PluginSemanticBookLookup = ({
  Book? Function(Map<String, dynamic> identity) find,
  Map<String, Book> byIndexedPath,
  List<String> officialPaths,
  bool Function() isCurrent,
});

typedef PluginSemanticEventSink =
    Future<void> Function(
      String topic,
      Map<String, dynamic> payload,
    );

/// ממשק החיפוש החכם עבור דף תוסף אחד.
class PluginSemanticBridge {
  PluginSemanticBridge({
    required this.books,
    required this.onPermissionRevoked,
    SemanticSearchRepository Function()? repository,
  }) : _repository = repository ?? (() => SemanticSearchRepository.instance);

  final Future<PluginSemanticBookLookup> Function(void Function()) books;
  final void Function() Function(void Function()) onPermissionRevoked;
  final SemanticSearchRepository Function() _repository;

  static const streamEvent = '__otzaria.semantic.nearest.chunk';
  static const _streamIdKey = '__streamId';
  static const _cancelStreamIdKey = '__cancelStreamId';
  static final _streamIdPattern = RegExp(
    r'^semantic_([0-9a-f]{32})_[0-9]{1,16}$',
  );

  /// מזהה המסמך שה-SDK הצמיד למזהה הזרם.
  static String? streamDocumentId(String id) =>
      _streamIdPattern.firstMatch(id)?.group(1);

  @visibleForTesting
  static Duration maxDuration = const Duration(minutes: 2);

  final _pendingCancellations = <String>{};
  final _calls = <SemanticBackgroundCall>{};
  ({String id, SemanticBackgroundCall call})? _nearest;
  bool _countingTokens = false;

  Future<dynamic> handle(
    String action,
    Map<String, dynamic> args, {
    required PluginSemanticEventSink? eventSink,
  }) async {
    switch (action) {
      case 'getStatus':
        _requireEmpty(args);
        final repository = _repository();
        final availability = await repository.refresh();
        if (!availability.isUsable) {
          return PluginSemanticApi.statusToJson(availability);
        }
        final vectors = await repository.vectorsInfo();
        final snapshot = await repository.engineSnapshot();
        final current = await repository.refresh();
        return PluginSemanticApi.statusToJson(
          current,
          vectors: current.isUsable ? vectors : null,
          modelFamilyId: current.isUsable ? snapshot.modelFamilyId : null,
          dim: current.isUsable ? snapshot.embeddingDim : null,
          vectorsReleaseTag: current.isUsable
              ? snapshot.vectorsReleaseTag
              : null,
        );
      case 'countTokens':
        final texts = PluginSemanticApi.parseTokenTexts(args);
        return _run((repository, call) async {
          if (_countingTokens) {
            throw Exception('error.preempted: token counting is still active');
          }
          _countingTokens = true;
          try {
            final tokens = await repository.queryTokens(texts, call: call);
            return PluginSemanticApi.tokensToJson(tokens);
          } finally {
            _countingTokens = false;
          }
        });
      case 'getCoveredBooks':
        _requireEmpty(args);
        return _run((repository, call) async {
          final lookup = await books(
            () => repository.checkBackgroundCall(call),
          );
          final paths = await repository.loadBackgroundCoveredBooks(call);
          repository.checkBackgroundCall(call);
          if (paths == null) {
            throw Exception('error.unavailable: coverage is unavailable');
          }
          _checkCatalog(lookup);
          return PluginSemanticApi.coveredBooksToJson(
            paths,
            lookup.byIndexedPath,
          );
        });
      case 'nearest':
        if (args[_cancelStreamIdKey] case final String id) {
          return _cancelStream(id);
        }
        return _runNearest(args, eventSink);
      default:
        throw Exception(
          'error.unknown_method: Unknown semantic action: $action',
        );
    }
  }

  /// מבטל את הפעולות של הדף היוצא.
  void release() {
    for (final call in _calls) {
      call.cancel();
    }
    _nearest = null;
    _pendingCancellations.clear();
  }

  static void _checkCatalog(PluginSemanticBookLookup lookup) {
    if (!lookup.isCurrent()) {
      throw Exception('error.unavailable: library catalog changed');
    }
  }

  static void _requireEmpty(Map<String, dynamic> args) {
    if (args.isNotEmpty) {
      throw Exception('error.invalid_params: this method takes no parameters');
    }
  }

  Map<String, dynamic> _cancelStream(String id) {
    if (streamDocumentId(id) == null) {
      throw Exception('error.invalid_params: invalid internal stream id');
    }
    final active = _nearest;
    if (active?.id == id) {
      _nearest = null;
      active!.call.cancel();
      return {'cancelled': true};
    }
    if (_pendingCancellations.length < 16) _pendingCancellations.add(id);
    return {'cancelled': false};
  }

  Future<Map<String, dynamic>> _runNearest(
    Map<String, dynamic> args,
    PluginSemanticEventSink? eventSink,
  ) async {
    final id = args[_streamIdKey];
    if (id is! String || streamDocumentId(id) == null || _nearest?.id == id) {
      throw Exception('error.invalid_params: invalid or duplicate stream id');
    }
    if (eventSink == null) {
      throw Exception('error.internal: semantic stream transport unavailable');
    }
    if (_pendingCancellations.remove(id)) {
      return {'completed': false, 'cancelled': true};
    }
    final call = SemanticBackgroundCall();
    _nearest?.call.cancel();
    _nearest = (id: id, call: call);
    var chunks = 0;
    try {
      return await _run(
        (repository, call) async {
          final request = Map<String, dynamic>.of(args)..remove(_streamIdKey);
          final lookup = await books(
            () => repository.checkBackgroundCall(call),
          );
          repository.checkBackgroundCall(call);
          final input = PluginSemanticApi.parseNearest(
            request,
            findBook: lookup.find,
            bookPaths: lookup.officialPaths,
          );

          Future<void> send(Map<String, dynamic> chunk) async {
            repository.checkBackgroundCall(call);
            _checkCatalog(lookup);
            await eventSink(streamEvent, {'streamId': id, 'chunk': chunk});
            repository.checkBackgroundCall(call);
            chunks++;
          }

          if (lookup.officialPaths.isEmpty) {
            final vectors = await repository.vectorsInfo();
            final lists = input.pool == SemanticPool.perPoint
                ? input.points.length
                : 1;
            for (var point = 0; point < lists; point++) {
              await send({
                'type': 'hits',
                if (input.pool == SemanticPool.perPoint) 'point': point,
                'hits': const [],
              });
            }
            await send({
              'type': 'done',
              'generation': vectors.generation,
              'vectorsLibraryVersion': vectors.libraryVersion,
              'clipped': false,
            });
            return {'completed': true, 'cancelled': false, 'chunks': chunks};
          }

          final response = await repository.nearest(
            input,
            call: call,
            onSearching: () =>
                send(const {'type': 'progress', 'phase': 'searching'}),
          );
          repository.checkBackgroundCall(call);
          _checkCatalog(lookup);
          for (final chunk in PluginSemanticApi.responseChunks(
            response,
            lookup.byIndexedPath,
            rescored: input.rescore,
          )) {
            await send(chunk);
          }
          return {'completed': true, 'cancelled': false, 'chunks': chunks};
        },
        call: call,
        onCancelled: () => {
          'completed': false,
          'cancelled': true,
          'chunks': chunks,
        },
        wasCancelledByPage: () => _nearest?.call != call,
      );
    } finally {
      if (identical(_nearest?.call, call)) _nearest = null;
    }
  }

  Future<T> _run<T>(
    Future<T> Function(SemanticSearchRepository, SemanticBackgroundCall) run, {
    SemanticBackgroundCall? call,
    T Function()? onCancelled,
    bool Function()? wasCancelledByPage,
  }) async {
    final request = call ?? SemanticBackgroundCall();
    final repository = _repository();
    _calls.add(request);
    var expired = false;
    var revoked = false;
    final removePermissionListener = onPermissionRevoked(() {
      revoked = true;
      request.cancel();
    });
    final unregister = repository.registerBackgroundCall(request);
    final cancelled = Completer<T>();
    final removeCancellation = request.onCancel(() {
      cancelled.completeError(
        const SemanticFailure(SemanticFailureKind.cancelled),
      );
    });
    final deadline = Timer(maxDuration, () {
      expired = true;
      request.cancel();
    });
    try {
      return await Future.any([
        cancelled.future,
        Future<T>.sync(() async {
          repository.checkBackgroundCall(request);
          final availability = await repository.refresh();
          repository.checkBackgroundCall(request);
          if (!availability.isUsable) {
            throw const SemanticFailure(SemanticFailureKind.notReady);
          }
          final result = await run(repository, request);
          repository.checkBackgroundCall(request);
          return result;
        }),
      ]);
    } on SemanticFailure catch (failure) {
      if (expired) throw TimeoutException('Semantic request timed out');
      if (revoked) {
        throw Exception('error.permission_denied: semantic access revoked');
      }
      if (request.preempted) {
        throw Exception('error.preempted: a search in Otzaria took precedence');
      }
      if (wasCancelledByPage?.call() == true) return onCancelled!();
      throw switch (failure.kind) {
        SemanticFailureKind.invalidInput => Exception(
          'error.invalid_params: invalid semantic input',
        ),
        SemanticFailureKind.queryFailed || SemanticFailureKind.internal =>
          Exception('error.internal: semantic ${failure.kind.name}'),
        _ => Exception('error.unavailable: semantic ${failure.kind.name}'),
      };
    } finally {
      deadline.cancel();
      removeCancellation();
      unregister();
      removePermissionListener();
      _calls.remove(request);
    }
  }
}
