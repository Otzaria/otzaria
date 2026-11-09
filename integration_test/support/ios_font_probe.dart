import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_content_blockers.dart';
import 'package:otzaria/plugins/services/plugin_content_security_policy.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart'
    show buildPluginTabWebViewSettings;

/// מאשר לבקר המקומי שהמופע המקורי הגיע למסגרת הראשונה.
Future<void> notifyIosFontProbeStarted({
  required String coordinator,
  required String token,
  required String generation,
  required String nativeFork,
  required bool firstFrameRasterized,
  Map<String, Object?> vmService = const {},
}) async {
  if (coordinator.isEmpty) return;
  if (!firstFrameRasterized) {
    throw StateError('Font probe has not rasterized its first frame');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(
      Uri.parse(coordinator).resolve('/checkpoint'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('X-Apple-Quiet-Token', token);
    final encoded = utf8.encode(
      jsonEncode({
        'runId': generation,
        'hostPid': pid,
        'appBootToken': '$pid-${DateTime.now().microsecondsSinceEpoch}',
        'hostExecutable': Platform.resolvedExecutable,
        'nativeFork': nativeFork,
        'firstFrameRasterized': firstFrameRasterized,
        'vmServiceUri': vmService['vmServiceUri'],
        'vmServiceIsolate': vmService['vmServiceIsolate'],
      }),
    );
    request.contentLength = encoded.length;
    request.add(encoded);
    final response = await request.close().timeout(const Duration(seconds: 45));
    await response.drain<void>().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Font probe startup checkpoint was rejected');
    }
  } finally {
    client.close(force: true);
  }
}

const iosFontProbePluginId = 'ios.font.probe';
const iosFontProbeOrigin = '$pluginAssetScheme://$iosFontProbePluginId';
const iosFontProbeLabFilter = r'^otzaria-plugin://ios\.font\.probe/';
const iosFontProbeTheme = <String, dynamic>{
  'typography': {
    'fontFamily': 'FrankRuhlCLM',
    'commentatorsFontFamily': 'FrankRuhlCLM',
    'uiFontFamily': 'Rubik',
    'fontSize': 28,
  },
};
const iosFontProbeSpecs = [
  {'key': 'bundled-regular', 'family': 'FrankRuhlCLM', 'weight': '400'},
  {'key': 'bundled-bold', 'family': 'FrankRuhlCLM', 'weight': '700'},
  {'key': 'variable-light', 'family': 'Rubik', 'weight': '300'},
  {'key': 'variable-bold', 'family': 'Rubik', 'weight': '700'},
];

enum IosFontProbeRoute {
  fileProductionPolicy('file-production-policy'),
  fileLabPolicy('file-lab-policy'),
  schemePageLabPolicy('scheme-page-lab-policy');

  const IosFontProbeRoute(this.id);
  final String id;
  bool get lab => this != fileProductionPolicy;
  bool get file => this != schemePageLabPolicy;
}

class IosFontProbeCase {
  const IosFontProbeCase(this.route, this.scenario, this.useScheme);
  final IosFontProbeRoute route;
  final String scenario;
  final bool useScheme;
  String get transport => useScheme ? 'scheme' : 'data';
  String get id => '${route.id}-$transport-$scenario';
  bool get registersScheme => useScheme || !route.file;

  String documentUrl(String root, {bool navigation = false}) {
    final name = '$id${navigation ? '-navigation' : ''}.html';
    return route.file
        ? Uri.file('$root/$name').toString()
        : '$iosFontProbeOrigin/$name';
  }

  List<ContentBlocker> get blockers => [
    ...buildPluginContentBlockers(
      pluginId: iosFontProbePluginId,
      policy: PluginNetworkPolicy.none,
      fileServerPort: 1,
    ),
    if (route.lab)
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: iosFontProbeLabFilter,
          urlFilterIsCaseSensitive: true,
        ),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.IGNORE_PREVIOUS_RULES,
        ),
      ),
  ];

  InAppWebViewSettings get settings =>
      buildPluginTabWebViewSettings(
          isDevelopment: false,
          contentBlockers: blockers,
        )
        ..incognito = true
        ..resourceCustomSchemes = registersScheme ? [pluginAssetScheme] : [];

  String get csp {
    final base = buildPluginContentSecurityPolicy(
      pluginId: iosFontProbePluginId,
      policy: PluginNetworkPolicy.none,
      fileServerPort: 1,
    );
    return switch (scenario) {
      'font-src-data' => '$base; font-src data:',
      'style-src-none' => "$base; style-src 'none'",
      _ => base,
    };
  }

  Map<String, Object?> get policyReport => {
    'route': route.id,
    'documentScheme': route.file ? 'file' : pluginAssetScheme,
    'contentBlockers': route.lab ? 'lab-exact-origin-added' : 'production',
    'labAllowFilter': route.lab ? iosFontProbeLabFilter : null,
    'contentBlockerRules': blockers.map((b) => b.toMap()).toList(),
    'resourceCustomSchemes': settings.resourceCustomSchemes,
    'schemeRegistration': registersScheme ? 'experiment-added' : 'production',
    'handler': registersScheme
        ? 'production-servePluginAsset'
        : 'not-registered',
    'allowFileAccessFromFileURLs': settings.allowFileAccessFromFileURLs,
    'allowUniversalAccessFromFileURLs':
        settings.allowUniversalAccessFromFileURLs,
    'allowingReadAccessTo': settings.allowingReadAccessTo?.rawValue,
    'incognito': settings.incognito,
    'responseAddsAccessControlAllowOrigin': false,
    'csp': csp,
  };

  String get html =>
      '''
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="$csp"></head><body>
<script>
window.fontProbeBootCount = 0;
window.fontProbeViolations = [];
window.fontProbeDroppedViolations = 0;
window.addEventListener('securitypolicyviolation', e => {
  if (window.fontProbeViolations.length >= 64) { window.fontProbeDroppedViolations++; return; }
  window.fontProbeViolations.push({directive:e.effectiveDirective,
    blockedUri:e.blockedURI.slice(0, 512), disposition:e.disposition});
});
window.addEventListener('plugin.boot', e => {window.fontProbeBootTheme = e.detail.theme;});
window.addEventListener('plugin.ready', () => {
  window.fontProbeBootCount++;
  window.fontProbeReadyFacesAtBoot = Array.from(document.fonts).filter(f => f.status === 'loaded').map(f => ({family:f.family,weight:f.weight}));
});
</script></body></html>
''';
}

Iterable<IosFontProbeCase> get iosFontProbeCases sync* {
  for (final route in IosFontProbeRoute.values) {
    for (final scenario in ['normal', 'font-src-data', 'style-src-none']) {
      for (final scheme in [false, true]) {
        yield IosFontProbeCase(route, scenario, scheme);
      }
    }
  }
}
