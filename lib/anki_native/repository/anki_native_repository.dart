import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/anki_native/models/anki_native_window.dart';
import 'package:otzaria/core/http_client_registry.dart';

abstract class AnkiNativeRepository {
  Future<void> ensureAnkiRunning();
  Future<AnkiNativeSnapshot> fetchWindows();
  Future<bool> attach(
    AnkiNativeWindow window,
    int processId,
    String generation,
  );
  Future<void> setBounds(AnkiNativeBounds bounds);
  Future<void> setVisible(bool visible);
  Future<void> closeWindow(String targetId);
  Future<void> detach();
  void dispose();
}

class LocalAnkiNativeRepository implements AnkiNativeRepository {
  static const _baseUri = 'http://127.0.0.1:18765';
  static const _protocolVersion = 7;
  static const _channel = MethodChannel('otzaria/anki_native_host');

  final http.Client _client;
  final MethodChannel _nativeChannel;
  late final void Function() _closeClient;
  late final String _clientId =
      'otzaria-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
  Timer? _heartbeatTimer;
  String? _attachedTargetId;
  String? _attachedKey;

  LocalAnkiNativeRepository({
    http.Client? client,
    MethodChannel? nativeChannel,
  }) : _client = client ?? http.Client(),
       _nativeChannel = nativeChannel ?? _channel {
    _closeClient = _client.close;
    HttpClientRegistry.register(_closeClient);
  }

  @override
  Future<void> ensureAnkiRunning() async {
    final currentProtocol = await _bridgeProtocol();
    if (currentProtocol == _protocolVersion) return;
    if (currentProtocol != null) {
      throw StateError('נדרשת גרסה עדכנית של תוסף אוצריא ANKI ב־Anki.');
    }
    final launched = await _nativeChannel.invokeMethod<bool>('launchAnki');
    if (launched != true) {
      throw StateError('לא נמצאה התקנת Anki שניתן להפעיל.');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final protocol = await _bridgeProtocol();
      if (protocol == _protocolVersion) return;
      if (protocol != null) {
        throw StateError('נדרשת גרסה עדכנית של תוסף אוצריא ANKI ב־Anki.');
      }
    }
    throw StateError('Anki הופעלה, אך תוסף אוצריא ANKI לא נעשה זמין בזמן.');
  }

  Future<int?> _bridgeProtocol() async {
    try {
      final payload = await _get(
        '/health',
        timeout: const Duration(seconds: 1),
      );
      return payload['protocolVersion'] as int?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AnkiNativeSnapshot> fetchWindows() async {
    final payload = await _get('/v1/native/windows');
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('תשובת החלונות של Anki אינה תקינה');
    }
    final processId = data['pid'];
    final generation = data['generation'];
    final rawWindows = data['windows'];
    if (processId is! int ||
        processId <= 0 ||
        generation is! String ||
        generation.isEmpty ||
        rawWindows is! List) {
      throw const FormatException('פרטי התהליך של Anki אינם תקינים');
    }
    return AnkiNativeSnapshot(
      processId: processId,
      generation: generation,
      windows: rawWindows
          .whereType<Map<String, dynamic>>()
          .map(AnkiNativeWindow.fromJson)
          .toList(growable: false),
    );
  }

  @override
  Future<bool> attach(
    AnkiNativeWindow window,
    int processId,
    String generation,
  ) async {
    final attachmentKey = '$processId:$generation:${window.hwnd}';
    if (_attachedKey == attachmentKey) return false;
    await detach();
    final container = await _nativeChannel.invokeMethod<int>('prepare');
    if (container == null || container <= 0) {
      throw PlatformException(
        code: 'native_host_failed',
        message: 'אוצריא לא הצליחה ליצור אזור אירוח עבור Anki.',
      );
    }
    await _post('/v1/native/attach-started', {
      'targetId': window.targetId,
      'clientId': _clientId,
      'containerHwnd': container.toRadixString(16).toUpperCase(),
    });
    try {
      final attached = await _nativeChannel.invokeMethod<bool>('attach', {
        'hwnd': window.hwnd,
        'processId': processId,
      });
      if (attached != true) {
        throw PlatformException(
          code: 'native_attach_failed',
          message: 'לא ניתן להטמיע את חלון Anki באוצריא.',
        );
      }
      _attachedTargetId = window.targetId;
      _attachedKey = attachmentKey;
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_heartbeat()),
      );
      return true;
    } catch (_) {
      await _nativeChannel.invokeMethod<bool>('detach');
      await _endAttachment();
      rethrow;
    }
  }

  @override
  Future<void> setBounds(AnkiNativeBounds bounds) async {
    await _nativeChannel.invokeMethod<bool>('setBounds', bounds.toJson());
    if (_attachedTargetId != null) {
      await _post('/v1/native/resize', {
        'clientId': _clientId,
        'width': bounds.width,
        'height': bounds.height,
      });
    }
  }

  @override
  Future<void> setVisible(bool visible) async {
    await _nativeChannel.invokeMethod<bool>('setVisible', {
      'visible': visible,
    });
  }

  @override
  Future<void> closeWindow(String targetId) async {
    await _post('/v1/native/close-window', {'targetId': targetId});
  }

  @override
  Future<void> detach() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final hadAttachment = _attachedTargetId != null;
    _attachedTargetId = null;
    _attachedKey = null;
    try {
      if (hadAttachment) await _endAttachment();
    } finally {
      await _nativeChannel.invokeMethod<bool>('detach');
    }
  }

  Future<void> _heartbeat() async {
    if (_attachedTargetId == null) return;
    try {
      await _post('/v1/native/heartbeat', {'clientId': _clientId});
    } catch (_) {
      _attachedKey = null;
    }
  }

  Future<void> _endAttachment() async {
    try {
      await _post('/v1/native/attach-ended', {'clientId': _clientId});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final response = await _client
        .get(Uri.parse('$_baseUri$path'))
        .timeout(timeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUri$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 4));
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('תשובת Anki אינה JSON תקין');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['ok'] != true) {
      final error = decoded['error'];
      final code = error is Map<String, dynamic> ? error['code'] : null;
      final message =
          error is Map<String, dynamic> && error['message'] is String
          ? error['message'] as String
          : 'הבקשה ל־Anki נכשלה';
      if (code is String &&
          (code.startsWith('native_') || code == 'stale_container')) {
        throw PlatformException(code: code, message: message);
      }
      throw StateError(message);
    }
    return decoded;
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    HttpClientRegistry.unregister(_closeClient);
    _client.close();
  }
}
