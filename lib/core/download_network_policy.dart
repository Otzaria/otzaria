import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

enum DownloadNetworkStatus { allowed, waitingForWifi }

/// אינו כשל תעבורה: ניסיונות חוזרים של HTTP אינם רשאים לעקוף את המדיניות.
class DownloadNetworkPaused implements Exception {
  const DownloadNetworkPaused(this.status);
  final DownloadNetworkStatus status;
}

/// מדיניות WiFi להורדות Android; אינה משנה מצב מנותק או גלישה בתוספים.
class DownloadNetworkPolicy {
  DownloadNetworkPolicy({
    bool? isAndroid,
    bool Function()? wifiOnlyReader,
    Stream<bool> Function()? wifiChanges,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _wifiOnlyReader = wifiOnlyReader ?? _readWifiOnly,
       _wifiChanges = wifiChanges ?? _platformWifiChanges;

  static DownloadNetworkPolicy instance = DownloadNetworkPolicy();
  static const _channel = EventChannel('otzaria/download_network');
  final bool _isAndroid;
  final bool Function() _wifiOnlyReader;
  final Stream<bool> Function() _wifiChanges;
  final _changes = StreamController<DownloadNetworkStatus>.broadcast(
    sync: true,
  );
  StreamSubscription<bool>? _wifiSubscription;
  StreamSubscription<String>? _settingsSubscription;
  Completer<void>? _firstWifi;
  bool _hasWifi = false;
  DownloadNetworkStatus? _lastStatus;

  static bool _readWifiOnly() =>
      Settings.isInitialized &&
      (Settings.getValue<bool>(SettingsRepository.keyDownloadsWifiOnly) ??
          false);

  static Stream<bool> _platformWifiChanges() =>
      _channel.receiveBroadcastStream().cast<bool>();

  DownloadNetworkStatus get status {
    if (!_isAndroid) return DownloadNetworkStatus.allowed;
    return !_wifiOnlyReader() || _hasWifi
        ? DownloadNetworkStatus.allowed
        : DownloadNetworkStatus.waitingForWifi;
  }

  Stream<DownloadNetworkStatus> get changes => _changes.stream;

  bool get isSupported => _isAndroid;

  /// נטען רק בשימוש ברשת; אינו מוסיף המתנה למסלול עליית האפליקציה.
  Future<DownloadNetworkStatus> refresh() async {
    if (!_isAndroid) return DownloadNetworkStatus.allowed;
    if (Settings.isInitialized) {
      _settingsSubscription ??= Settings.changes.listen((key) {
        if (key == SettingsRepository.keyDownloadsWifiOnly) {
          unawaited(refresh());
        }
      });
    }
    _publish();
    if (_wifiOnlyReader()) {
      if (_wifiSubscription == null) {
        _firstWifi = Completer<void>();
        _wifiSubscription = _wifiChanges().listen(
          (wifi) => _setWifi(wifi),
          onError: (Object error) {
            _setWifi(false);
            debugPrint('Network transport detection failed: $error');
          },
          onDone: () => _setWifi(false),
        );
      }
      await _firstWifi!.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    }
    _publish();
    return status;
  }

  void _setWifi(bool wifi) {
    _hasWifi = wifi;
    if (!_firstWifi!.isCompleted) _firstWifi!.complete();
    _publish();
  }

  void _publish() {
    final current = status;
    if (current == _lastStatus) return;
    _lastStatus = current;
    _changes.add(current);
  }

  Future<void> requireAccess() async {
    final current = await refresh();
    if (current != DownloadNetworkStatus.allowed) {
      throw DownloadNetworkPaused(current);
    }
  }

  /// ממתין בלי בקשות רשת, ומשמר את חריגת הביטול של הקורא.
  Future<void> waitUntilAllowed({
    void Function()? checkCancelled,
    void Function()? onWaiting,
  }) async {
    checkCancelled?.call();
    unawaited(refresh());
    if (status == DownloadNetworkStatus.allowed) return;
    onWaiting?.call();
    final ready = Completer<void>();
    final subscription = changes.listen((next) {
      if (next == DownloadNetworkStatus.allowed && !ready.isCompleted) {
        ready.complete();
      }
    });
    final timer = checkCancelled == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 200), (_) {
            try {
              checkCancelled();
            } catch (error, stack) {
              if (!ready.isCompleted) ready.completeError(error, stack);
            }
          });
    try {
      if (status == DownloadNetworkStatus.allowed && !ready.isCompleted) {
        ready.complete();
      }
      await ready.future;
      checkCancelled?.call();
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }

  /// מפעיל שוב רק הורדה שהמוריד יודע להמשיך מהקובץ החלקי.
  Future<T> runResumable<T>(
    Future<T> Function() download, {
    void Function()? checkCancelled,
    void Function()? onWaiting,
  }) async {
    if (!_isAndroid) return download();
    while (true) {
      await waitUntilAllowed(
        checkCancelled: checkCancelled,
        onWaiting: onWaiting,
      );
      try {
        return await download();
      } on DownloadNetworkPaused {
        checkCancelled?.call();
      }
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _wifiSubscription?.cancel();
    await _settingsSubscription?.cancel();
    await _changes.close();
  }
}
