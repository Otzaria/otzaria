import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const _fontRoute = '__otzaria_fonts__';

typedef PluginSchemeFontLoader = Future<Uint8List> Function();

/// Reserved even without a live lease; never fall through to plugin files.
bool isPluginFontSchemeRoute(WebUri url) {
  var path =
      RegExp(r'^[^:]+://[^/?#]*([^?#]*)').firstMatch(url.rawValue)?.group(1) ??
      url.path;
  while (true) {
    final decoded = path.replaceAllMapped(
      RegExp(r'%([0-9a-fA-F]{2})'),
      (match) => String.fromCharCode(int.parse(match[1]!, radix: 16)),
    );
    if (decoded == path) break;
    path = decoded;
  }
  return path.toLowerCase().split(RegExp(r'[/\\]')).contains(_fontRoute);
}

String _opaqueId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// One document's allowlist. Neither the URL nor a request can name a disk file.
class PluginFontSchemeLease {
  PluginFontSchemeLease({required this.origin}) : id = _opaqueId() {
    if (!RegExp(r'^otzaria-plugin://[a-z0-9.-]+$').hasMatch(origin)) {
      throw ArgumentError.value(origin, 'origin');
    }
  }

  final String origin;
  final String id;
  final _urls = <String, String>{};
  final _loaders = <String, PluginSchemeFontLoader>{};
  bool _active = true;
  int requestCount = 0;
  int responseCount = 0;
  int responseBytes = 0;

  bool get isActive => _active;

  String register(String key, PluginSchemeFontLoader load) {
    if (!_active) throw StateError('Font document has been released');
    return _urls.putIfAbsent(key, () {
      final url = '$origin/$_fontRoute/$id/${_opaqueId()}.ttf';
      _loaders[url] = load;
      return url;
    });
  }

  Future<Uint8List?> read(WebUri url) async {
    if (!_active) return null;
    // Exact raw lookup also rejects encoded aliases, traversal, ports and queries.
    final loader = _loaders[url.rawValue];
    if (loader == null) return null;
    requestCount++;
    try {
      final bytes = await loader();
      if (!_active || bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<CustomSchemeResponse?> responseFor(
    WebUri url, {
    Map<String, String>? headers,
  }) async {
    final bytes = await read(url);
    if (!_active || bytes == null) return null;
    responseCount++;
    responseBytes += bytes.length;
    return CustomSchemeResponse(
      data: bytes,
      contentType: 'font/ttf',
      headers: {...?headers, 'Cache-Control': 'no-store'},
    );
  }

  void dispose() {
    _active = false;
    _loaders.clear();
    _urls.clear();
  }
}

/// Controller identity and document leases are local to a single Flutter host.
class PluginFontSchemeOwner {
  Object? _controller;
  PluginFontSchemeLease? _lease;

  PluginFontSchemeLease? get lease => _lease;

  void attach(Object? controller) {
    if (identical(controller, _controller)) return;
    release();
    _controller = controller;
  }

  PluginFontSchemeLease? begin({
    required Object controller,
    required String origin,
  }) {
    if (!identical(controller, _controller)) return null;
    release();
    return _lease = PluginFontSchemeLease(origin: origin);
  }

  void release({Object? controller}) {
    if (controller != null && !identical(controller, _controller)) return;
    _lease?.dispose();
    _lease = null;
  }
}
