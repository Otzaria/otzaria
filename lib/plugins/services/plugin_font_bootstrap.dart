import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/services/plugin_font_scheme.dart';
import 'package:otzaria/plugins/services/plugin_fonts.dart';
import 'package:otzaria/theme/app_fonts.dart';

const pluginMacFontSchemeOptIn = bool.fromEnvironment(
  'OTZARIA_EXPERIMENTAL_MACOS_PLUGIN_FONTS',
  defaultValue: false,
);

bool pluginFontSchemeExperimentAllowed({
  required String platform,
  required bool enabled,
}) => !kIsWeb && platform == 'macos' && enabled;

bool get pluginMacFontSchemeEnabled =>
    !kIsWeb &&
    pluginFontSchemeExperimentAllowed(
      platform: Platform.operatingSystem,
      enabled: pluginMacFontSchemeOptIn,
    );

const pluginFontDocumentMarkerJs = r'''
(function () {
  Object.defineProperty(document, '__otzariaFontDocumentId', {
    value: Date.now().toString(36) + Math.random().toString(36).slice(2)
  });
})();
''';

const _claimDocumentJs = r'''
var id = document.__otzariaFontDocumentId;
if (typeof id !== 'string' || !id) return {ready: false, reason: 'document-marker-unavailable'};
if (Date.now() > deadlineMs) return {ready: false, reason: 'expired'};
document.__otzariaFontBootAttempt = owner;
return {ready: true, reason: 'document-claimed', documentId: id};
''';

const _beginDocumentJs = r'''
if (document.__otzariaFontDocumentId !== documentId || document.__otzariaFontBootAttempt !== owner) {
  return {ready: false, reason: 'stale-document'};
}
if (Date.now() > deadlineMs) return {ready: false, reason: 'expired'};
var previous = document.__otzariaFontDocument;
if (previous && previous.style) previous.style.remove();
document.__otzariaFontDocument = {id: owner, style: null};
return {ready: true, reason: 'document-bound'};
''';

const pluginStrictFontInstallJs = r'''
var state = document.__otzariaFontDocument;
if (document.__otzariaFontDocumentId !== documentId || document.__otzariaFontBootAttempt !== owner || !state || state.id !== owner) return {ready: false, reason: 'stale-document'};
if (Date.now() > deadlineMs) return {ready: false, reason: 'expired'};
if (!document.fonts || !document.fonts.load || !document.fonts.has) {
  return {ready: false, reason: 'font-api-unavailable'};
}
var before = new Set(Array.from(document.fonts));
var style = document.createElement('style');
style.setAttribute('data-otzaria-fonts', owner);
style.textContent = css;
if (state.style) state.style.remove();
state.style = style;
try {
  (document.head || document.documentElement).appendChild(style);
  if (!style.sheet || !style.sheet.cssRules.length) {
    style.remove();
    return {ready: false, reason: 'style-blocked'};
  }
} catch (_) {
  style.remove();
  return {ready: false, reason: 'style-blocked'};
}
var ownFaces = new Set(Array.from(document.fonts).filter(function (f) {
  return !before.has(f);
}));
var timer;
var outcome = await Promise.race([
  Promise.all(targets.map(function (target) {
    return document.fonts.load(target, 'אבג ABC 012');
  })).then(function (groups) {
    var valid = groups.every(function (faces) {
      return faces.length > 0 && faces.some(function (face) {
        return ownFaces.has(face) && document.fonts.has(face) && face.status === 'loaded';
      });
    });
    return {ready: valid, reason: valid ? 'loaded' : 'missing-loaded-face'};
  }, function () { return {ready: false, reason: 'font-load-failed'}; }),
  new Promise(function (resolve) {
    timer = setTimeout(function () {
      resolve({ready: false, reason: 'font-timeout'});
    }, Math.max(0, Math.min(timeoutMs, deadlineMs - Date.now())));
  })
]);
clearTimeout(timer);
if (document.__otzariaFontDocumentId !== documentId || document.__otzariaFontBootAttempt !== owner || document.__otzariaFontDocument !== state || state.id !== owner) {
  style.remove();
  return {ready: false, reason: 'stale-document'};
}
if (Date.now() > deadlineMs) outcome = {ready: false, reason: 'expired'};
if (!outcome.ready && !keepOnFailure) style.remove();
outcome.faces = Array.from(ownFaces).map(function (face) {
  return {family: face.family, weight: face.weight, status: face.status};
});
return outcome;
''';

class PluginFontBootstrapResult {
  PluginFontBootstrapResult({
    required this.owner,
    required this.documentBound,
    required this.documentId,
    required this.transport,
    required this.outcome,
    required this.elapsedMicroseconds,
    required this.javascriptUtf8Bytes,
    required this.argumentJsonUtf8Bytes,
    required this.cssUtf8Bytes,
    this.schemeFailure,
  });

  final String owner;
  final bool documentBound;
  final String? documentId;
  final String transport;
  final Map<String, dynamic> outcome;
  final String? schemeFailure;
  final int elapsedMicroseconds;
  final int javascriptUtf8Bytes;
  final int argumentJsonUtf8Bytes;
  final int cssUtf8Bytes;

  bool get ready => outcome['ready'] == true;

  /// Font binding can fail after the document and boot attempt were identified.
  String guardBoot(String source, {DateTime? deadline}) {
    final expires = deadline ?? DateTime.now().add(const Duration(seconds: 5));
    return '''
(function () {
  var expectedId = ${jsonEncode(documentId)}, expectedOwner = ${jsonEncode(owner)};
  function rejected() {
    if (typeof expectedId !== 'string' || !expectedId) return 'document-identity-unavailable';
    if (document.__otzariaFontDocumentId !== expectedId || document.__otzariaFontBootAttempt !== expectedOwner) return 'stale-document';
    if (Date.now() > ${expires.millisecondsSinceEpoch}) return 'boot-expired';
    return null;
  }
  var reason = rejected();
  if (reason) return {booted: false, reason: reason};
  var eventOptions = $source\n;
  reason = rejected();
  if (reason) return {booted: false, reason: reason};
  return {booted: true, documentId: expectedId, owner: expectedOwner, eventOptions: eventOptions};
})();
''';
  }

  Future<({List<dynamic> eventOptions, int javascriptUtf8Bytes})> evaluateBoot(
    InAppWebViewController controller, {
    required String source,
    required bool Function() isCurrent,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (documentId == null || documentId!.isEmpty) {
      throw StateError('Plugin boot: document-identity-unavailable');
    }
    if (!isCurrent()) throw StateError('Plugin boot: stale-document');
    final guarded = guardBoot(
      source,
      deadline: DateTime.now().add(timeout),
    );
    final response = await controller
        .evaluateJavascript(source: guarded)
        .timeout(timeout);
    if (!isCurrent()) throw StateError('Plugin boot: stale-document');
    if (response is! Map ||
        response['booted'] != true ||
        response['documentId'] != documentId ||
        response['owner'] != owner ||
        response['eventOptions'] is! List) {
      final reason = response is Map ? response['reason'] : null;
      throw StateError(
        'Plugin boot: ${reason ?? 'missing-acknowledgement'}',
      );
    }
    return (
      eventOptions: List<dynamic>.from(response['eventOptions'] as List),
      javascriptUtf8Bytes: utf8.encode(guarded).length,
    );
  }

  Map<String, Object?> toJson() => {
    'transport': transport,
    'ready': ready,
    'outcome': outcome,
    'schemeFailure': ?schemeFailure,
    'elapsedMicroseconds': elapsedMicroseconds,
    'javascriptUtf8Bytes': javascriptUtf8Bytes,
    'argumentJsonUtf8Bytes': argumentJsonUtf8Bytes,
    'cssUtf8Bytes': cssUtf8Bytes,
  };
}

/// A bounded pre-boot experiment. The data control uses the same readiness check.
Future<PluginFontBootstrapResult> preparePluginFontExperiment(
  InAppWebViewController controller, {
  required PluginFontSchemeLease lease,
  required Map<String, dynamic> theme,
  required bool Function() isCurrent,
  bool useScheme = true,
  Duration timeout = const Duration(seconds: 6),
  Duration fontTimeout = pluginFontWaitTimeout,
}) async {
  final clock = Stopwatch()..start();
  final deadline = DateTime.now().add(timeout);
  final families = {...AppFonts.fontPaths.keys};
  final typography = theme['typography'];
  if (typography is Map) {
    for (final key in const [
      'fontFamily',
      'commentatorsFontFamily',
      'uiFontFamily',
    ]) {
      final family = typography[key];
      if (family is String && family.isNotEmpty) families.add(family);
    }
  }
  final targets = {
    ...pluginFontLoadTargets(theme),
    '16px "${AppFonts.defaultFont}"',
  }.toList();
  var javascriptBytes = 0;
  var argumentBytes = 0;
  var cssBytes = 0;
  var documentBound = false;
  String? documentId;
  String? schemeFailure;
  var transport = 'unavailable';
  Map<String, dynamic> outcome = {'ready': false, 'reason': 'stale-document'};

  bool current() => lease.isActive && isCurrent();
  Future<T> bounded<T>(Future<T> future) {
    final remaining = deadline.difference(DateTime.now());
    return future.timeout(
      remaining > Duration.zero ? remaining : Duration.zero,
    );
  }

  Future<Map<String, dynamic>> run(
    String body,
    Map<String, dynamic> arguments,
  ) async {
    if (!current()) return {'ready': false, 'reason': 'stale-document'};
    final args = {
      ...arguments,
      'owner': lease.id,
      'documentId': documentId,
      'deadlineMs': deadline.millisecondsSinceEpoch,
    };
    javascriptBytes += utf8.encode(body).length;
    argumentBytes += utf8.encode(jsonEncode(args)).length;
    final response = await bounded(
      controller.callAsyncJavaScript(functionBody: body, arguments: args),
    );
    if (!current()) return {'ready': false, 'reason': 'stale-document'};
    if (response?.error != null || response?.value is! Map) {
      return {'ready': false, 'reason': 'javascript-unavailable'};
    }
    return Map<String, dynamic>.from(response!.value as Map);
  }

  Future<Map<String, dynamic>> install({required bool embedded}) async {
    final css = await bounded(
      buildPluginFontFaceCss(
        embedded: embedded,
        lease: embedded ? null : lease,
        families: families,
      ),
    );
    if (!current()) return {'ready': false, 'reason': 'stale-document'};
    if (css.isEmpty) return {'ready': false, 'reason': 'no-font-css'};
    cssBytes += utf8.encode(css).length;
    return run(pluginStrictFontInstallJs, {
      'css': css,
      'targets': targets,
      'timeoutMs': fontTimeout.inMilliseconds,
      'keepOnFailure': embedded,
    });
  }

  try {
    outcome = await run(_claimDocumentJs, const {});
    final claimedId = outcome['documentId'];
    if (outcome['ready'] == true &&
        claimedId is String &&
        claimedId.isNotEmpty) {
      documentId = claimedId;
      outcome = await run(_beginDocumentJs, const {});
      documentBound = outcome['ready'] == true;
    } else if (outcome['ready'] == true) {
      outcome = {'ready': false, 'reason': 'document-marker-unavailable'};
    }
    if (documentBound && current()) {
      if (useScheme) {
        outcome = await install(embedded: false);
        if (outcome['ready'] == true) {
          transport = 'scheme';
        } else {
          schemeFailure = outcome['reason'] as String?;
        }
      }
      if (transport != 'scheme' && current()) {
        outcome = await install(embedded: true);
        transport = outcome['ready'] == true ? 'data' : 'unavailable';
      }
    }
  } on TimeoutException {
    outcome = {'ready': false, 'reason': 'preparation-timeout'};
  } catch (error) {
    outcome = {'ready': false, 'reason': 'preparation-error'};
    debugPrint('Plugin font experiment unavailable: $error');
  }
  if (!current()) {
    outcome = {'ready': false, 'reason': 'stale-document'};
    transport = 'unavailable';
  }
  return PluginFontBootstrapResult(
    owner: lease.id,
    documentBound: documentBound,
    documentId: documentId,
    transport: transport,
    outcome: outcome,
    schemeFailure: schemeFailure,
    elapsedMicroseconds: clock.elapsedMicroseconds,
    javascriptUtf8Bytes: javascriptBytes,
    argumentJsonUtf8Bytes: argumentBytes,
    cssUtf8Bytes: cssBytes,
  );
}
