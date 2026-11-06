import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const pluginWarningAndErrorConsoleLevels = [
  ConsoleMessageLevel.WARNING,
  ConsoleMessageLevel.ERROR,
];

/// מסדר עדכוני console וחוקי רשת בלי לדרוס הגדרות שנקראו בעדכון קודם.
class PluginWebViewSettingsUpdater {
  PluginWebViewSettingsUpdater({required this.onError});

  final void Function(Object error) onError;
  static final _controllers = Expando<_ControllerSettingsUpdate>();
  _ControllerSettingsUpdate? _update;
  Object? _owner;
  bool _disposed = false;

  Future<void> attach(
    InAppWebViewController controller, {
    required List<ConsoleMessageLevel>? consoleMessageLevels,
    required List<ContentBlocker>? contentBlockers,
  }) {
    if (_disposed) return Future.value();
    detach();
    final owner = _owner = Object();
    final update = _update = _controllers[controller.platform] ??=
        _ControllerSettingsUpdate();
    return update.claim(
      owner,
      controller,
      consoleMessageLevels,
      contentBlockers,
      onError,
    );
  }

  _ControllerSettingsUpdate? get _ownedUpdate =>
      _owner != null && identical(_update?.owner, _owner) ? _update : null;

  Future<void> setConsoleMessageLevels(List<ConsoleMessageLevel>? levels) =>
      _ownedUpdate?.setConsoleMessageLevels(levels) ?? Future.value();

  Future<void> setContentBlockers(List<ContentBlocker> blockers) =>
      _ownedUpdate?.setContentBlockers(blockers) ?? Future.value();

  void detach() {
    _ownedUpdate?.release();
    _update = null;
    _owner = null;
  }

  void dispose() {
    _disposed = true;
    detach();
  }
}

class _ControllerSettingsUpdate {
  Object? owner;
  InAppWebViewController? _controller;
  List<ConsoleMessageLevel>? _consoleMessageLevels;
  List<ContentBlocker>? _contentBlockers;
  void Function(Object error)? _onError;
  Future<void>? _inFlight;
  int _revision = 0;
  int _attemptedRevision = 0;

  Future<void> claim(
    Object newOwner,
    InAppWebViewController controller,
    List<ConsoleMessageLevel>? levels,
    List<ContentBlocker>? blockers,
    void Function(Object error) onError,
  ) {
    owner = newOwner;
    _controller = controller;
    _consoleMessageLevels = levels == null ? null : List.unmodifiable(levels);
    _contentBlockers = blockers == null ? null : List.unmodifiable(blockers);
    _onError = onError;
    return _request();
  }

  Future<void> setConsoleMessageLevels(List<ConsoleMessageLevel>? levels) {
    _consoleMessageLevels = levels == null ? null : List.unmodifiable(levels);
    return _request();
  }

  Future<void> setContentBlockers(List<ContentBlocker> blockers) {
    _contentBlockers = List.unmodifiable(blockers);
    return _request();
  }

  void release() {
    owner = null;
    _controller = null;
    _contentBlockers = null;
    _onError = null;
  }

  Future<void> _request() {
    _revision++;
    return _queue();
  }

  Future<void> _queue() => _inFlight ??= _drain().whenComplete(() {
    _inFlight = null;
    if (owner != null && _revision != _attemptedRevision) {
      return _queue();
    }
  });

  Future<void> _drain() async {
    while (owner != null && _revision != _attemptedRevision) {
      final currentOwner = owner;
      final controller = _controller!;
      _attemptedRevision = _revision;
      try {
        final settings = await controller.getSettings();
        if (!identical(owner, currentOwner)) continue;
        _attemptedRevision = _revision;
        if (settings == null) continue;
        final levels = _consoleMessageLevels;
        final blockers = _contentBlockers;
        final sameBlockers =
            blockers == null ||
            const DeepCollectionEquality().equals(
              settings.contentBlockers?.map((rule) => rule.toMap()).toList(),
              blockers.map((rule) => rule.toMap()).toList(),
            );
        if (listEquals(settings.consoleMessageLevels, levels) && sameBlockers) {
          continue;
        }
        settings.consoleMessageLevels = levels;
        if (blockers != null) settings.contentBlockers = blockers;
        await controller.setSettings(settings: settings);
      } catch (error) {
        if (identical(owner, currentOwner)) _onError?.call(error);
      }
    }
  }
}
