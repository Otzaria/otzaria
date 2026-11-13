import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_library_book_provider.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

typedef FindRefDispatch =
    Future<void> Function(
      String pluginId,
      String topic,
      Map<String, dynamic> payload,
    );

@immutable
class PluginFindRefHit {
  const PluginFindRefHit({
    required this.pluginId,
    required this.provider,
    required this.providerTitle,
    required this.query,
    required this.reference,
    required this.choiceIndex,
  });
  final String pluginId;
  final String provider;
  final String providerTitle;
  final String query;
  final String reference;
  final int choiceIndex;
}

/// מראי מקומות חיצוניים נשארים נפרדים ממזהי הספרים המקומיים.
class PluginFindRefService {
  PluginFindRefService._()
    : _providers = (() =>
          PluginLibraryBooksRegistry.instance.referenceProviders),
      _dispatch = ((id, topic, payload) => PluginRuntimeDispatcher.instance
          .dispatchEventToPlugin(id, topic, payload, preferBackground: true)),
      timeout = const Duration(seconds: 115) {
    PluginLibraryBooksRegistry.instance.addListener(_providersChanged);
  }

  @visibleForTesting
  factory PluginFindRefService.forTesting({
    required FindRefDispatch dispatch,
    required Iterable<PluginLibraryBookProvider> Function() providers,
    Duration timeout = const Duration(seconds: 1),
  }) => PluginFindRefService._withDependencies(dispatch, providers, timeout);

  PluginFindRefService._withDependencies(
    this._dispatch,
    this._providers,
    this.timeout,
  );

  static final PluginFindRefService instance = PluginFindRefService._();
  static const requestTopic = 'findRef.external.requested';
  static const openTopic = 'findRef.external.openRequested';
  static const cancelTopic = 'findRef.external.cancelled';
  static const maxHits = 100;
  final Duration timeout;
  final FindRefDispatch _dispatch;
  final Iterable<PluginLibraryBookProvider> Function() _providers;
  final Map<String, _PendingFindRef> _pending = {};
  int _counter = 0;

  bool get hasProviders => _providers().any((p) => p.referenceSearch);

  bool _available(PluginLibraryBookProvider provider) =>
      _providers().any((p) => p.referenceSearch && p.sameAs(provider));

  void _providersChanged() {
    for (final entry in _pending.entries.toList()) {
      if (!_available(entry.value.provider)) _finish(entry.key, const []);
    }
  }

  void _finish(String id, List<PluginFindRefHit> hits) {
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.timer?.cancel();
    pending.completer.complete(hits);
  }

  /// ביטול שייך לחלון המבקש, כדי שלא יבטל חיפוש בחלון אחר.
  void cancel(Object owner) {
    for (final entry in _pending.entries.toList()) {
      if (!identical(entry.value.owner, owner)) continue;
      _finish(entry.key, const []);
      unawaited(
        _dispatch(entry.value.provider.pluginId, cancelTopic, {
          'requestId': entry.key,
        }).catchError((Object e) {
          debugPrint('FindRef cancellation dispatch failed: $e');
        }),
      );
    }
  }

  Future<List<PluginFindRefHit>> search(
    String query, {
    Object? owner,
    void Function(List<PluginFindRefHit>)? onUpdate,
  }) async {
    if (query.trim().length < 3) return const [];
    final providers = _providers().where((p) => p.referenceSearch).toList();
    final completed = <String, List<PluginFindRefHit>>{};
    List<PluginFindRefHit> snapshot() => List.unmodifiable(
      [
        for (final p in providers) ...?completed[p.provider],
      ].take(maxHits),
    );
    await Future.wait([
      for (final provider in providers)
        () async {
          final hits = await _searchOne(provider, query, owner);
          completed[provider.provider] = hits;
          onUpdate?.call(snapshot());
        }(),
    ]);
    return snapshot();
  }

  Future<List<PluginFindRefHit>> _searchOne(
    PluginLibraryBookProvider provider,
    String query,
    Object? owner,
  ) {
    final id = 'fr-${++_counter}';
    final pending = _PendingFindRef(provider, query, owner);
    _pending[id] = pending;
    pending.timer = Timer(timeout, () => _finish(id, const []));
    unawaited(
      Future.sync(
        () => _dispatch(provider.pluginId, requestTopic, {
          'requestId': id,
          'provider': provider.provider,
          'query': query,
          'limit': maxHits,
        }),
      ).catchError((Object error) {
        debugPrint('FindRef dispatch failed: $error');
        _finish(id, const []);
      }),
    );
    return pending.completer.future;
  }

  bool respond(
    String pluginId,
    String requestId, {
    List<Object?> results = const [],
    String? error,
  }) {
    final request = _pending[requestId];
    if (request == null || request.provider.pluginId != pluginId) return false;
    if (!_available(request.provider)) {
      _finish(requestId, const []);
      return false;
    }
    final hits = <PluginFindRefHit>[];
    final seen = <String>{};
    if (error == null) {
      for (final row in results.take(maxHits)) {
        if (row is! Map) continue;
        final reference = row['reference'];
        final choiceIndex = row['choiceIndex'];
        if (reference is! String ||
            reference.trim().isEmpty ||
            reference.length > 400 ||
            choiceIndex is! int ||
            choiceIndex < 0 ||
            choiceIndex >= 1000 ||
            !seen.add(reference)) {
          continue;
        }
        hits.add(
          PluginFindRefHit(
            pluginId: pluginId,
            provider: request.provider.provider,
            providerTitle: request.provider.title,
            query: request.query,
            reference: reference,
            choiceIndex: choiceIndex,
          ),
        );
      }
    }
    _finish(requestId, List.unmodifiable(hits));
    return true;
  }

  Future<void> open(PluginFindRefHit hit) async {
    if (!_providers().any(
      (p) =>
          p.referenceSearch &&
          p.pluginId == hit.pluginId &&
          p.provider == hit.provider,
    )) {
      throw StateError('Reference provider unavailable');
    }
    await _dispatch(hit.pluginId, openTopic, {
      'provider': hit.provider,
      'query': hit.query,
      'choiceIndex': hit.choiceIndex,
      'expectedChoice': hit.reference,
    });
  }
}

class _PendingFindRef {
  _PendingFindRef(this.provider, this.query, this.owner);
  final PluginLibraryBookProvider provider;
  final String query;
  final Object? owner;
  final Completer<List<PluginFindRefHit>> completer = Completer();
  Timer? timer;
}
