import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';

/// The native creation response is a snapshot, not a live rendering query.
Map<String, Object?> observeWebViewBackend(
  InAppWebViewController controller, {
  String? platform,
  Map<String, String>? environment,
}) {
  final os = platform ?? Platform.operatingSystem;
  final requested = requestedWebViewBackend(
    environment ?? Platform.environment,
  );
  final implementation = controller.platform;
  final details = implementation is WindowsInAppWebViewController
      ? implementation.creationDetails
      : null;
  final supported = os == 'windows';
  final verified = supported && details?.isRenderModeVerified == true;
  return Map.unmodifiable({
    'schemaVersion': 1,
    'scope': 'nativeCreation',
    'source': 'WindowsInAppWebViewController.creationDetails',
    'availability': !supported
        ? 'unsupported'
        : verified
        ? 'collected'
        : 'unavailable',
    'reason': !supported
        ? 'platform_unsupported'
        : implementation is! WindowsInAppWebViewController
        ? 'windows_controller_unavailable'
        : details == null
        ? 'creation_details_unavailable'
        : !verified
        ? 'native_render_mode_unknown'
        : null,
    'requested': supported ? requested : null,
    'nativeViewId': supported ? details?.nativeViewId : null,
    'observed': verified ? details!.renderMode!.name : null,
    'verified': verified,
    'fallbackStage': supported ? details?.fallbackStage : null,
    'fallbackHresult': supported ? details?.fallbackHresult : null,
    'fallbackReasonAvailable':
        supported && details?.isFallbackReasonAvailable == true,
    'ongoingModeVerified': false,
  });
}

/// Native treats only the exact value "1" as forced HWND; "0" requests default.
String requestedWebViewBackend(Map<String, String> environment) =>
    environment['FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND'] == '1'
    ? 'hwnd'
    : 'composition';

/// Owns only immutable diagnostics, never a controller or a native-id cache.
class WebViewBackendDiagnostics {
  WebViewBackendDiagnostics({
    ValueListenable<bool>? collecting,
    void Function(String type, Map<String, Object?> fields)? record,
  }) : _collecting =
           collecting ?? DeveloperDiagnostics.instance.collectionState,
       _record = record ?? DeveloperDiagnostics.instance.recordEvent {
    _collecting.addListener(_onCollectionChanged);
  }

  final ValueListenable<bool> _collecting;
  final void Function(String, Map<String, Object?>) _record;
  Map<String, Object?>? _attachment;
  String? _attachmentId;
  bool _disposed = false;

  void attach(
    InAppWebViewController controller, {
    required Map<String, Object?> host,
    String? platform,
    Map<String, String>? environment,
  }) {
    if (_disposed) return;
    detach();
    _attachment = Map.unmodifiable({
      ...host,
      'createdUtc': DateTime.now().toUtc().toIso8601String(),
      'backend': observeWebViewBackend(
        controller,
        platform: platform,
        environment: environment,
      ),
    });
    _emit('attached');
  }

  void detach() {
    _emit('detached');
    _attachment = null;
    _attachmentId = null;
  }

  void _onCollectionChanged() => _emit('present');

  void _emit(String event) {
    if (_disposed || !_collecting.value || _attachment == null) return;
    if (_attachmentId == null) {
      final random = Random.secure();
      _attachmentId = List.generate(
        4,
        (_) => random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
      ).join();
    }
    _record('webview_backend', {
      ..._attachment!,
      'attachmentId': _attachmentId,
      'event': event,
    });
  }

  void dispose() {
    if (_disposed) return;
    detach();
    _disposed = true;
    _collecting.removeListener(_onCollectionChanged);
  }
}
