import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_font_scheme.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:path/path.dart' as p;

/// האם הגופנים מוגשים כקבצים משרת הקבצים, או מוטבעים כ-`data:` בכלל עצמו.
/// ב-WKWebView נשארים עם data: כדי לא להרחיב את הרשאות ה-ATS של האפליקציה.
bool get pluginFontsFromFileServer =>
    kIsWeb || (!Platform.isIOS && !Platform.isMacOS);

@visibleForTesting
bool? debugPluginFontsFromFileServer;

bool get _fromFileServer =>
    debugPluginFontsFromFileServer ?? pluginFontsFromFileServer;

/// המשפחות שנרשמות בכל דף תוסף: המובנים, ושתי המשפחות שנבחרו בהגדרות.
Set<String> pluginFontFamilies() => {
  ...AppFonts.fontPaths.keys,
  Settings.getValue<String>(SettingsRepository.keyFontFamily) ??
      AppFonts.defaultFont,
  Settings.getValue<String>(SettingsRepository.keyCommentatorsFontFamily) ??
      AppFonts.defaultCommentatorsFont,
};

typedef _Face = ({String id, String weight, PluginFontLoader load});

/// הגופנים הארוזים נשמרים בזיכרון (כ-1.5MB לכל עשרת הקבצים, ורק מה שנדרש):
/// כל טאב מבקש אותם מחדש, כי תשובת יירוט אינה נשמרת במטמון של ה-WebView.
/// גופן מערכת אינו נשמר — הוא עשוי להיות עשרות MB, ונבחר אחד בכל פעם.
final Map<String, Future<Uint8List>> _assetCache = {};

Future<Uint8List> _assetBytes(String asset) =>
    _assetCache[asset] ??= _loadAsset(asset)
      ..catchError((Object _) {
        _assetCache.remove(asset);
        return Uint8List(0);
      });

Future<Uint8List> _loadAsset(String asset) async {
  final data = await rootBundle.load(asset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

@visibleForTesting
SystemFontFamilyFaces? Function(String family)? debugPluginSystemFaces;

Future<SystemFontFamilyFaces?> _systemFaces(String family) async {
  final override = debugPluginSystemFaces;
  if (override != null) return override(family);
  await AppFonts.warmUpSystemFontsCache();
  return AppFonts.pluginSystemFamilyFaces(family);
}

String _assetId(String asset) =>
    'b-${p.basename(asset).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';

/// גופן מערכת מקבל id לפי הנתיב, כדי שהנתיב עצמו לא ייחשף לתוסף.
final Map<String, String> _systemIds = {};

String _systemId(String path) => _systemIds.putIfAbsent(
  path,
  () => 's${_systemIds.length}${p.extension(path).toLowerCase()}',
);

/// ה-faces של [family]. גופן משתנה מקבל טווח משקלים — בלעדיו ה-WebView נעול
/// על מופע ברירת המחדל ומסנתז בולד מרוח במקום להשתמש בציר ה-wght.
Future<List<_Face>> _faces(String family) async {
  if (family.isEmpty) return const [];
  final asset = AppFonts.fontPaths[family];
  if (asset != null) {
    final bold = AppFonts.boldFontPaths[family];
    return [
      (
        id: _assetId(asset),
        weight: AppFonts.variableWeightFonts.contains(family)
            ? '100 900'
            : '400',
        load: () => _assetBytes(asset),
      ),
      if (bold != null)
        (id: _assetId(bold), weight: '700', load: () => _assetBytes(bold)),
    ];
  }
  final faces = await _systemFaces(family);
  if (faces == null || !await File(faces.regularPath).exists()) {
    return const [];
  }
  final regularPath = faces.regularPath;
  final boldPath = faces.boldPath;
  return [
    (
      id: _systemId(regularPath),
      weight: faces.hasWeightAxis ? '100 900' : '400',
      load: () => File(regularPath).readAsBytes(),
    ),
    if (boldPath != null && await File(boldPath).exists())
      (
        id: _systemId(boldPath),
        weight: '700',
        load: () => File(boldPath).readAsBytes(),
      ),
  ];
}

final Map<String, String> _dataSources = {};

Future<String> _source(
  _Face face, {
  required bool embedded,
  required bool cache,
  PluginFontSchemeLease? lease,
}) async {
  if (!embedded && lease != null) return lease.register(face.id, face.load);
  if (!embedded && _fromFileServer) {
    return PluginFileServer.instance.fontUrl(face.id, face.load);
  }
  final cached = cache ? _dataSources[face.id] : null;
  if (cached != null) return cached;
  final source = 'data:font/ttf;base64,${base64Encode(await face.load())}';
  if (cache) _dataSources[face.id] = source;
  return source;
}

String _rule(String family, String source, String weight) =>
    "@font-face{font-family:'$family';font-style:normal;"
    'font-weight:$weight;src:url($source) format(\'truetype\');'
    'font-display:block;}';

/// [asFamily] מגיש את הגופן תחת שם אחר. כך `fonts.resolveFamilies` עונה על
/// בקשה לגופן שאינו במכונה: הגופן של תחליף, בשם שהמסמך מבקש.
Future<List<String>> _familyRules(
  String family, {
  String? asFamily,
  bool embedded = false,
  PluginFontSchemeLease? lease,
}) async {
  try {
    return [
      for (final face in await _faces(family))
        _rule(
          asFamily ?? family,
          await _source(
            face,
            embedded: embedded,
            cache: asFamily == null,
            lease: lease,
          ),
          face.weight,
        ),
    ];
  } catch (error) {
    // משפחה שאינה נטענת נופלת בדף לשרשרת ה-fallback של התוסף.
    debugPrint('Plugin font $family unavailable: $error');
    return const [];
  }
}

/// כללי `@font-face` לכל [pluginFontFamilies]. [embedded] מטביע את הבייטים
/// כשהדף אינו יכול לטעון משרת הקבצים, למשל בגלל CSP משלו.
Future<String> buildPluginFontFaceCss({
  bool embedded = false,
  PluginFontSchemeLease? lease,
  Set<String>? families,
}) async {
  final rules = <String>[];
  for (final family in families ?? pluginFontFamilies()) {
    rules.addAll(await _familyRules(family, embedded: embedded, lease: lease));
  }
  return rules.join('\n');
}

({String css, String json})? _jsonCache;

/// [css] מקודד ל-JSON לסקריפט ה-boot. הבייטים המוטבעים הם כ-2MB ונשמרים לאותו CSS.
String pluginFontFaceJson(String css) {
  final cached = _jsonCache;
  if (cached != null && cached.css == css) return cached.json;
  final json = jsonEncode(css);
  _jsonCache = (css: css, json: json);
  return json;
}

/// כמה משפחות ותחליפים בקשה אחת יכולה לבקש.
const int _maxResolveFamilies = 24;
const int _maxResolveSubstitutes = 12;

/// עונה על `fonts.resolveFamilies`: לכל משפחה מבוקשת, ה-`@font-face` של
/// התחליף הראשון שאפשר להרכיב — **בשם שהמסמך מבקש**.
///
/// `src: local()` ב-WebView רואה רק גופנים מותקנים במערכת, ולא את אלה שאוצריא
/// רושמת. המדיניות — אילו תחליפים ובאיזה סדר — נשארת אצל התוסף.
Future<Map<String, dynamic>> resolvePluginFontFamilies(
  List<dynamic> requested,
) async {
  final css = <String>[];
  final resolved = <String>[];
  for (final entry in requested.take(_maxResolveFamilies)) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String || name.isEmpty) continue;
    final substitutes = entry['substitutes'];
    final candidates = substitutes is List
        ? substitutes.whereType<String>().take(_maxResolveSubstitutes)
        : const <String>[];
    for (final candidate in candidates) {
      final rules = await _familyRules(
        candidate,
        asFamily: name,
        embedded: true,
      );
      if (rules.isEmpty) continue;
      css.addAll(rules);
      resolved.add(name);
      break;
    }
  }
  return {'css': css.join('\n'), 'resolved': resolved};
}

/// המטרות ל-`document.fonts.load`: הרגיל והבולד של גופן הקריאה ושל
/// המפרשים, והרגיל של גופן הממשק.
List<String> pluginFontLoadTargets(Map<String, dynamic> theme) {
  final typography = theme['typography'];
  if (typography is! Map) return const [];
  String quoted(String family) =>
      '"${family.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  final targets = <String>{};
  for (final key in const ['fontFamily', 'commentatorsFontFamily']) {
    final family = typography[key];
    if (family is String && family.isNotEmpty) {
      targets
        ..add('16px ${quoted(family)}')
        ..add('bold 16px ${quoted(family)}');
    }
  }
  final ui = typography['uiFontFamily'];
  if (ui is String && ui.isNotEmpty) targets.add('16px ${quoted(ui)}');
  return targets.toList();
}

const Duration pluginFontWaitTimeout = Duration(milliseconds: 1500);

const String _installFontsJs = r'''
if (css) {
  var style = document.createElement('style');
  style.setAttribute('data-otzaria-fonts', '1');
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);
}
var loaded = await Promise.race([
  Promise.all(targets.map(function (t) {
    return document.fonts.load(t);
  })).then(function () { return true; }, function () { return false; }),
  new Promise(function (resolve) {
    setTimeout(function () { resolve(false); }, timeoutMs);
  })
]);
if (!loaded && style) style.remove();
return loaded;
''';

/// רושם את [css] בדף וממתין עד [timeout] ל-[targets], כדי שתוסף שמודד טקסט
/// ב-plugin.ready לא יקבל מדידה של גופן חלופי. מחזיר false כשהכללים לא
/// נרשמו בוודאות — ואז סקריפט ה-boot מזריק אותם בעצמו.
Future<bool> installPluginFonts(
  InAppWebViewController controller, {
  required String css,
  required List<String> targets,
  Duration timeout = pluginFontWaitTimeout,
}) async {
  if (!_fromFileServer) return false;
  try {
    final result = await controller
        .callAsyncJavaScript(
          functionBody: _installFontsJs,
          arguments: {
            'css': css,
            // משפחה חסרה נטענת כ-[] בלי בקשה; face מוכר בודק את הרשאות ה-transport.
            'targets': {...targets, '16px "${AppFonts.defaultFont}"'}.toList(),
            'timeoutMs': timeout.inMilliseconds,
          },
        )
        .timeout(timeout + const Duration(seconds: 1));
    return result?.error == null && result?.value == true;
  } catch (error) {
    // ההמתנה אינה תנאי ל-boot; הכללים יוזרקו בסקריפט ה-boot.
    debugPrint('Plugin fonts install failed: $error');
    return false;
  }
}

/// תשובת היירוט (Windows, Android) לבקשת גופן משרת הקבצים, או null כשאינה כזו.
///
/// בקשת גופן היא תמיד CORS; ה-origin משתקף לפי אותה מדיניות של השרת.
Future<WebResourceResponse?> pluginFontResponse(
  WebResourceRequest request,
) async {
  final data = await PluginFileServer.instance.fontBytesFor(request.url);
  if (data == null) return null;
  final origin = _header(request.headers, 'origin');
  return WebResourceResponse(
    contentType: pluginAssetContentType(request.url.path),
    statusCode: 200,
    reasonPhrase: 'OK',
    headers: {
      'Cache-Control': pluginFontCacheControl,
      // לא בכל פלטפורמה היירוט חושף את Origin; תשובת יירוט מגיעה רק ל-WebView
      // של תוסף, והגופנים אינם סוד — לכן בלעדיו `*`.
      if (origin == null)
        'Access-Control-Allow-Origin': '*'
      else if (PluginFileServer.isAllowedOrigin(origin)) ...{
        'Access-Control-Allow-Origin': origin,
        'Vary': 'Origin',
      },
    },
    data: data,
  );
}

String? _header(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

@visibleForTesting
void debugResetPluginFonts() {
  _assetCache.clear();
  debugPluginSystemFaces = null;
  _systemIds.clear();
  _dataSources.clear();
  _jsonCache = null;
}
