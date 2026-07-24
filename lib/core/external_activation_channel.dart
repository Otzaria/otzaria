import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExternalActivationChannel {
  static const String channelName = 'otzaria/external_activation';
  static const String getPendingUriStringsMethod = 'getPendingUriStrings';
  static const String externalActivationMethod = 'externalActivation';

  final MethodChannel _channel;
  final StreamController<String> _uriStringsController =
      StreamController<String>.broadcast();

  bool _isInitialized = false;

  ExternalActivationChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  Stream<String> get uriStrings => _uriStringsController.stream;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _channel.setMethodCallHandler(_handleMethodCall);
    _isInitialized = true;
  }

  Future<List<String>> takePendingUriStrings() async {
    try {
      final pendingUris = await _channel.invokeMethod<List<Object?>>(
        getPendingUriStringsMethod,
      );
      return normalizeUriStrings(pendingUris);
    } on MissingPluginException {
      return const [];
    }
  }

  void dispose() {
    if (!_isInitialized) {
      return;
    }

    _channel.setMethodCallHandler(null);
    unawaited(_uriStringsController.close());
    _isInitialized = false;
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != externalActivationMethod) {
      return;
    }

    for (final uriString in normalizeUriStrings(call.arguments)) {
      _uriStringsController.add(uriString);
    }
  }

  @visibleForTesting
  static List<String> normalizeUriStrings(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? const [] : [trimmed];
    }

    if (raw is List) {
      return raw
          .whereType<String>()
          .map((uriString) => uriString.trim())
          .where((uriString) => uriString.isNotEmpty)
          .toList(growable: false);
    }

    return const [];
  }
}
