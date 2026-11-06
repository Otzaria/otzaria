import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_font_bootstrap.dart';
import 'package:otzaria/plugins/services/plugin_font_scheme.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/theme/app_fonts.dart';

import 'macos_font_probe.dart';

const appleFontProbeMeasureJs = r'''
var started = performance.now();
var progress = window.__otzariaFontProbeRendering = {
  documentId: document.__otzariaFontDocumentId, owner: document.__otzariaFontBootAttempt,
  startedAtEpochMilliseconds: Date.now(), events: [], droppedEvents: 0
};
function mark(phase, key) {
  progress.phase = phase;
  progress.elapsedMilliseconds = performance.now() - started;
  if (progress.events.length === 40) { progress.droppedEvents++; return; }
  progress.events.push({phase: phase, fontKey: key || null,
    elapsedMilliseconds: progress.elapsedMilliseconds, visibilityState: document.visibilityState});
}
mark('started');
var samples = [];
function render(family, weight) {
  var canvas = document.createElement('canvas');
  canvas.width = 650; canvas.height = 80;
  var ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, 650, 80);
  ctx.font = weight + ' 28px "' + family + '"';
  ctx.fillStyle = '#000'; ctx.textBaseline = 'top';
  var text = 'שלום עולם אבגדה ABC 012345';
  ctx.fillText(text, 8, 8);
  var pixels = ctx.getImageData(0, 0, 650, 80).data;
  var hash = 2166136261, ink = 0;
  for (var i = 0; i < pixels.length; i++) {
    hash = Math.imul(hash ^ pixels[i], 16777619) >>> 0;
    if (i % 4 === 0 && pixels[i] < 128) ink++;
  }
  return {width: ctx.measureText(text).width, pixelHash: hash.toString(16), inkPixels: ink};
}
for (var spec of specs) {
  var target = spec.weight + ' 28px "' + spec.family + '"';
  mark('font-load-started', spec.key);
  var faces = await document.fonts.load(target, 'אבג ABC 012');
  mark('font-load-completed', spec.key);
  var span = document.createElement('span');
  span.textContent = 'שלום עולם אבגדה ABC 012345';
  span.style.cssText = 'display:block;white-space:nowrap;font:' + spec.weight + ' 18px "' + spec.family + '"';
  document.body.appendChild(span);
  mark('canvas-started', spec.key);
  samples.push({key: spec.key, family: spec.family, weight: spec.weight,
    loadedFaces: faces.map(f => ({family: f.family, weight: f.weight, status: f.status})),
    ...render(spec.family, spec.weight)});
  mark('canvas-completed', spec.key);
}
mark('frames-requested');
await new Promise(resolve => requestAnimationFrame(() => {
  mark('frame-1');
  requestAnimationFrame(() => { mark('frame-2'); resolve(); });
}));
mark('fallback-started');
var fallback = render('monospace', '400');
mark('fallback-completed');
mark('completed');
return {samples: samples, fallbackControl: fallback, renderingProgress: progress,
  visible: document.visibilityState === 'visible',
  bootCount: window.fontProbeBootCount, bootTheme: window.fontProbeBootTheme,
  readyFacesAtBoot: window.fontProbeReadyFacesAtBoot,
  viewport: {width: innerWidth, height: innerHeight, dpr: devicePixelRatio},
  userAgent: navigator.userAgent};
''';

const appleFontProbePolicyJs = r'''
return {href: location.href, origin: location.origin,
  secureContext: window.isSecureContext,
  documentId: document.__otzariaFontDocumentId,
  owner: document.__otzariaFontBootAttempt,
  violations: window.fontProbeViolations || [],
  droppedViolations: window.fontProbeDroppedViolations || 0};
''';

String? _header(Map<String, String>? headers, String name) {
  for (final entry in (headers ?? const <String, String>{}).entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

Future<Map<String, Object?>> loadFreshAppleSurvivorFont(
  AppleFontProbeResult survivor,
) async {
  final lease = survivor.lease;
  final requests = lease.requestCount;
  final responses = lease.responseCount;
  final bytes = lease.responseBytes;
  var loaderReads = 0;
  final url = lease.register('post-close-survivor', () async {
    loaderReads++;
    final data = await rootBundle.load(AppFonts.fontPaths['FrankRuhlCLM']!);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });
  expect(loaderReads, 0);
  final result = await survivor.controller
      .callAsyncJavaScript(
        functionBody: r'''
if (document.__otzariaFontBootAttempt !== owner) return {loaded: false, reason: 'stale-document'};
var face = new FontFace('OtzariaLeaseSurvivor', 'url(' + JSON.stringify(url) + ')');
document.fonts.add(face);
try {
  await face.load();
  return {loaded: document.__otzariaFontBootAttempt === owner && document.fonts.has(face) && face.status === 'loaded', status: face.status};
} finally {
  document.fonts.delete(face);
}
''',
        arguments: {'url': url, 'owner': lease.id},
      )
      .timeout(const Duration(seconds: 5));
  expect(result?.error, isNull);
  expect(result?.value, isA<Map>());
  final value = result!.value as Map;
  expect(value['loaded'], isTrue);
  final requestDelta = lease.requestCount - requests;
  final responseDelta = lease.responseCount - responses;
  final responseBytesDelta = lease.responseBytes - bytes;
  expect(loaderReads, greaterThan(0));
  expect(requestDelta, greaterThan(0));
  expect(responseDelta, greaterThan(0));
  expect(responseBytesDelta, greaterThan(0));
  return {
    'availability': 'verified',
    'loaderReads': loaderReads,
    'requestDelta': requestDelta,
    'responseDelta': responseDelta,
    'responseBytesDelta': responseBytesDelta,
    'faceStatus': value['status'],
  };
}

Future<Map<String, Object?>> loadFreshAppleDataSurvivorFont(
  AppleFontProbeResult survivor,
) async {
  if (!survivor.lease.isActive) {
    throw StateError('Surviving font owner is no longer active');
  }
  final data = await rootBundle.load(AppFonts.fontPaths['FrankRuhlCLM']!);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final result = await survivor.controller
      .callAsyncJavaScript(
        functionBody: r'''
if (document.__otzariaFontDocumentId !== documentId || document.__otzariaFontBootAttempt !== owner) {
  return {loaded: false, reason: 'stale-document'};
}
var face = new FontFace('OtzariaDataSurvivor', 'url(' + JSON.stringify(url) + ')');
document.fonts.add(face);
try {
  await face.load();
  return {loaded: document.__otzariaFontDocumentId === documentId &&
    document.__otzariaFontBootAttempt === owner && document.fonts.has(face) && face.status === 'loaded',
    status: face.status};
} finally {
  document.fonts.delete(face);
}
''',
        arguments: {
          'url': 'data:font/ttf;base64,${base64Encode(bytes)}',
          'owner': survivor.lease.id,
          'documentId': survivor.preparation.documentId,
        },
      )
      .timeout(const Duration(seconds: 5));
  expect(result?.error, isNull);
  expect(result?.value, isA<Map>());
  final value = result!.value as Map;
  expect(value['loaded'], isTrue);
  expect(survivor.lease.isActive, isTrue);
  return {
    'availability': 'verified',
    'transport': 'data',
    'sourceBytes': bytes.length,
    'faceStatus': value['status'],
    'owner': survivor.lease.id,
    'documentId': survivor.preparation.documentId,
  };
}

class AppleFontProbeResult {
  AppleFontProbeResult(
    this.controller,
    this.lease,
    this.preparation,
    this.report,
  );
  final InAppWebViewController controller;
  final PluginFontSchemeLease lease;
  final PluginFontBootstrapResult preparation;
  final Map<String, Object?> report;
}

class AppleFontProbeView extends StatefulWidget {
  const AppleFontProbeView({
    super.key,
    required this.root,
    required this.scenario,
    required this.csp,
    required this.theme,
    required this.specs,
    required this.index,
    required this.completed,
    required this.progress,
    required this.documentUrl,
    required this.fontOrigin,
    required this.pluginId,
    required this.appPlatform,
    required this.useScheme,
    required this.settings,
    this.capturePolicyDiagnostics = false,
    this.navigationUrl,
  });
  final String root;
  final String scenario;
  final String csp;
  final Map<String, dynamic> theme;
  final List<Map<String, String>> specs;
  final int index;
  final Completer<AppleFontProbeResult> completed;
  final FontProbeViewProgress progress;
  final String documentUrl;
  final String fontOrigin;
  final String pluginId;
  final String appPlatform;
  final bool useScheme;
  final InAppWebViewSettings settings;
  final bool capturePolicyDiagnostics;
  final String? navigationUrl;
  @override
  State<AppleFontProbeView> createState() => _AppleFontProbeViewState();
}

class _AppleFontProbeViewState extends State<AppleFontProbeView> {
  final _fontOwner = PluginFontSchemeOwner();
  bool _started = false;

  bool get _current => mounted && widget.progress.isActive;

  void _fail(Object error, StackTrace stack) {
    widget.progress.fail(error, stack);
    if (!widget.completed.isCompleted) {
      widget.completed.completeError(error, stack);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.progress.mounted();
  }

  @override
  void dispose() {
    _fontOwner.attach(null);
    widget.progress.dispose();
    if (!widget.completed.isCompleted) {
      widget.completed.completeError(
        StateError('Font probe view disposed before completion'),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InAppWebView(
    initialUrlRequest: URLRequest(
      url: WebUri(widget.documentUrl),
    ),
    initialSettings: widget.settings,
    initialUserScripts: UnmodifiableListView([
      UserScript(
        source: pluginSdkStubScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: pluginFontDocumentMarkerJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]),
    onWebViewCreated: (controller) {
      if (!_current) return;
      widget.progress.record('controller-created', {
        'nativeViewId': controller.getViewId(),
      });
      _fontOwner.attach(controller.platform);
    },
    shouldOverrideUrlLoading: (controller, navigation) async {
      if (!_current) return NavigationActionPolicy.CANCEL;
      final url = navigation.request.url?.rawValue;
      final allowed =
          navigation.isForMainFrame &&
          (url == widget.documentUrl ||
              (widget.progress.report['status'] == 'completed' &&
                  widget.navigationUrl != null &&
                  url == widget.navigationUrl));
      widget.progress.record('navigation-decision', {
        'url': url,
        'isForMainFrame': navigation.isForMainFrame,
        'policy': allowed ? 'allow' : 'cancel',
      });
      if (!allowed) {
        _fail(
          StateError('Unexpected font probe navigation: $url'),
          StackTrace.current,
        );
      }
      return allowed
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL;
    },
    onLoadStart: (controller, url) {
      if (!_current) return;
      widget.progress.record('load-start', {'url': url?.rawValue});
      _fontOwner.release(controller: controller.platform);
    },
    onLoadResourceWithCustomScheme: (controller, request) async {
      if (!_current) return null;
      widget.progress.record('scheme-request', {
        'url': request.url.rawValue,
        if (widget.capturePolicyDiagnostics)
          'originHeader': _header(request.headers, 'origin'),
      });
      try {
        final response = await servePluginAsset(
          url: request.url,
          pluginId: widget.pluginId,
          rootPath: widget.root,
          fontLease: _fontOwner.lease,
          contentSecurityPolicy: widget.csp,
        );
        if (!_current) return null;
        widget.progress.record('scheme-response', {
          'url': request.url.rawValue,
          'bytes': response?.data.length,
          'contentType': response?.contentType,
          if (widget.capturePolicyDiagnostics) ...{
            'accessControlAllowOrigin': _header(
              response?.headers,
              'access-control-allow-origin',
            ),
            'contentSecurityPolicy': _header(
              response?.headers,
              'content-security-policy',
            ),
          },
        });
        return response;
      } catch (error, stack) {
        _fail(error, stack);
        rethrow;
      }
    },
    onConsoleMessage: widget.capturePolicyDiagnostics
        ? (controller, message) {
            if (!_current) return;
            widget.progress.record('console', {
              'level': message.messageLevel.toNativeValue(),
              'message': message.message,
            });
          }
        : null,
    onReceivedError: (controller, request, error) {
      if (!_current) return;
      widget.progress.record('navigation-error', {
        'url': request.url.rawValue,
        'isForMainFrame': request.isForMainFrame,
        'type': error.type.toNativeValue(),
        'description': error.description,
      });
      if (request.isForMainFrame == true ||
          request.url.rawValue == widget.documentUrl) {
        _fail(StateError(error.description), StackTrace.current);
      }
    },
    onWebContentProcessDidTerminate: (controller) {
      if (!_current) return;
      _fail(
        StateError('WKWebView content process terminated'),
        StackTrace.current,
      );
    },
    onLoadStop: (controller, url) async {
      if (!_current || _started) return;
      _started = true;
      final progress = widget.progress;
      progress.record('load-stop', {'url': url?.rawValue});
      try {
        if (url?.rawValue != widget.documentUrl) {
          throw StateError('Unexpected font probe document: $url');
        }
        final lease = _fontOwner.begin(
          controller: controller.platform,
          origin: widget.fontOrigin,
        );
        if (lease == null) {
          throw StateError('Font probe controller is not attached');
        }
        final loadedAt = progress.elapsedMicroseconds;
        final preparation = await progress.observe(
          'font-preparation',
          () => preparePluginFontExperiment(
            controller,
            lease: lease,
            theme: widget.theme,
            isCurrent: () => _current && identical(_fontOwner.lease, lease),
            useScheme: widget.useScheme,
          ),
        );
        progress.report.addAll({
          'documentLoadMicroseconds': loadedAt,
          'fontReadyFromViewCreationMicroseconds': preparation.ready
              ? progress.elapsedMicroseconds
              : null,
          'preparation': preparation.toJson(),
        });
        progress.registerFailureSnapshot(() async {
          if (!mounted ||
              !identical(_fontOwner.lease, lease) ||
              !lease.isActive) {
            throw StateError('Font probe snapshot owner is no longer current');
          }
          final box = context.findRenderObject();
          if (box is RenderBox && box.hasSize) {
            final position = box.localToGlobal(Offset.zero);
            progress.record('failure-widget-bounds', {
              'x': position.dx,
              'y': position.dy,
              'width': box.size.width,
              'height': box.size.height,
            });
          }
          return await controller.evaluateJavascript(
                source: buildFontProbeFailureSnapshotScript(
                  documentId: preparation.documentId,
                  owner: lease.id,
                ),
              )
              as String?;
        });
        final boot = await progress.observe(
          'boot',
          () => preparation.evaluateBoot(
            controller,
            source: buildPluginBootScript(
              nonceJson: jsonEncode('font-probe'),
              payloadJson: jsonEncode({
                'plugin': {'id': widget.pluginId},
                'app': {
                  'platform': widget.appPlatform,
                  'runMode': 'foreground',
                },
                'theme': widget.theme,
                'permissions': [],
              }),
            ),
            isCurrent: () => _current && identical(_fontOwner.lease, lease),
          ),
        );
        progress.report.addAll({
          'bootJavascriptUtf8Bytes': boot.javascriptUtf8Bytes,
          'bootAcknowledged': true,
          'schemeBytesAtBoot': lease.responseBytes,
        });
        progress.report['renderingRequestedAtEpochMilliseconds'] =
            DateTime.now().millisecondsSinceEpoch;
        final rendering = await progress.observe(
          'rendering',
          () => controller.callAsyncJavaScript(
            functionBody: widget.scenario == 'style-src-none'
                ? 'return {bootCount: window.fontProbeBootCount, bootTheme: window.fontProbeBootTheme, visible: document.visibilityState === "visible", samples: []};'
                : appleFontProbeMeasureJs,
            arguments: {'specs': widget.specs},
          ),
        );
        if (rendering?.error != null || rendering?.value is! Map) {
          throw StateError('Font rendering probe failed: ${rendering?.error}');
        }
        progress.report.addAll({
          'schemeResponseBytes': lease.responseBytes,
          'schemeRequests': lease.requestCount,
          'schemeResponses': lease.responseCount,
          'rendering': Map<String, dynamic>.from(rendering!.value as Map),
        });
        if (widget.capturePolicyDiagnostics) {
          final policy = await progress.observe(
            'policy-diagnostics',
            () => controller.callAsyncJavaScript(
              functionBody: appleFontProbePolicyJs,
            ),
          );
          if (policy?.error != null || policy?.value is! Map) {
            throw StateError('Font policy diagnostics unavailable');
          }
          progress.report['policyDiagnostics'] = Map<String, dynamic>.from(
            policy!.value as Map,
          );
          progress.report['documentIdentity'] = {
            'documentId': preparation.documentId,
            'owner': preparation.owner,
            'leaseId': lease.id,
          };
        }
        final screenshot = widget.scenario == 'style-src-none'
            ? null
            : await progress.observe(
                'screenshot',
                () => controller.takeScreenshot(),
              );
        progress.report['screenshotBase64'] = screenshot == null
            ? null
            : base64Encode(screenshot);
        progress.complete();
        widget.completed.complete(
          AppleFontProbeResult(controller, lease, preparation, progress.report),
        );
      } catch (error, stack) {
        _fail(error, stack);
      }
    },
  );
}
