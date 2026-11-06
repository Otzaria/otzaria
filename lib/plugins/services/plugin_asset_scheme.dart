import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/services/plugin_content_security_policy.dart';
import 'package:otzaria/plugins/services/plugin_headless_shell.dart';
import 'package:otzaria/plugins/services/plugin_font_scheme.dart';
import 'package:path/path.dart' as p;

/// הסכימה שדרכה מוגשים קובצי התוסף במקום `file://`.
const String pluginAssetScheme = 'otzaria-plugin';

/// האם התוסף מוגש דרך [pluginAssetScheme] בפלטפורמה הנוכחית.
///
/// רק במק: WKWebView חוסם `new Worker()` מ-origin של `file://`, וההיתר הגורף
/// `allowFileAccessFromFileURLs` היה נותן ל-JS של התוסף לקרוא כל קובץ בדיסק.
bool get pluginAssetSchemeEnabled => !kIsWeb && Platform.isMacOS;

/// האם תוסף מוגש דרך [pluginAssetScheme]. תוסף ללא ממשק מוגש כך גם בווינדוס:
/// רק מ-origin אמיתי אפשר לטעון מודולים (Chromium חוסם אותם מ-`file://`).
bool pluginUsesAssetScheme({required bool headless}) =>
    pluginAssetSchemeEnabled || (headless && !kIsWeb && Platform.isWindows);

/// ה-host שבו מוגש [pluginId] — origin נפרד לכל תוסף, כך שאחסון הדפדפן
/// (localStorage/IndexedDB) מבודד ביניהם.
String pluginAssetHost(String pluginId) =>
    pluginId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.-]'), '-');

/// ה-URI שבו מוגש [filePath] שבתוך [rootPath] של התוסף.
WebUri pluginAssetUri({
  required String pluginId,
  required String rootPath,
  required String filePath,
}) {
  final relative = p
      .split(p.relative(p.normalize(filePath), from: p.normalize(rootPath)))
      .map(Uri.encodeComponent)
      .join('/');
  return WebUri('$pluginAssetScheme://${pluginAssetHost(pluginId)}/$relative');
}

/// מגישה קובץ מתוך [rootPath] עבור בקשת [pluginAssetScheme].
///
/// מחזירה `null` כשהנתיב חורג מתיקיית התוסף או שהקובץ אינו קיים — ואז
/// ה-WebView מקבל כשל טעינה, בדיוק כמו בקובץ חסר תחת `file://`.
/// [headlessEntrypoint] מגיש גם את המעטפת הווירטואלית של תוסף ללא ממשק.
/// [contentSecurityPolicy] מצורף לכל תשובה — גם סקריפט של Worker מקבל ממנה את
/// המדיניות שלו.
Future<CustomSchemeResponse?> servePluginAsset({
  required WebUri url,
  required String pluginId,
  required String rootPath,
  String? headlessEntrypoint,
  String? contentSecurityPolicy,
  PluginFontSchemeLease? fontLease,
}) async {
  final headers = contentSecurityPolicy == null
      ? null
      : {pluginContentSecurityPolicyHeader: contentSecurityPolicy};
  // host אחר הוא origin אחר — התוסף אינו רשאי לייצר לעצמו כאלה.
  if (url.scheme != pluginAssetScheme ||
      url.host != pluginAssetHost(pluginId)) {
    return null;
  }
  if (isPluginFontSchemeRoute(url)) {
    return fontLease?.responseFor(url, headers: headers);
  }
  if (headlessEntrypoint != null &&
      url.path == '/$pluginHeadlessShellFileName') {
    return CustomSchemeResponse(
      data: utf8.encode(
        pluginHeadlessShellHtml(headlessEntrypoint, module: true),
      ),
      contentType: 'text/html',
      headers: headers,
    );
  }
  File? file;
  try {
    file = resolvePluginAssetFile(urlPath: url.path, rootPath: rootPath);
  } on FormatException {
    return null;
  }
  if (file == null) return null;
  try {
    return CustomSchemeResponse(
      data: await file.readAsBytes(),
      contentType: pluginAssetContentType(file.path),
      headers: headers,
    );
  } on FileSystemException {
    return null;
  }
}

/// ממפה את נתיב ה-URL לקובץ בתוך [rootPath], או `null` אם הוא חורג ממנה.
///
/// זו נקודת האכיפה היחידה של בידוד התוסף — בלעדיה `../` בנתיב היה מגיש כל
/// קובץ בדיסק.
@visibleForTesting
File? resolvePluginAssetFile({
  required String urlPath,
  required String rootPath,
}) {
  final root = p.normalize(rootPath);
  final decoded = Uri.decodeComponent(urlPath).replaceFirst(RegExp('^/+'), '');
  if (decoded.isEmpty) return null;
  final resolved = p.normalize(p.join(root, decoded));
  if (!p.isWithin(root, resolved)) return null;
  final file = File(resolved);
  return file.existsSync() ? file : null;
}

const Map<String, String> _contentTypes = {
  '.html': 'text/html',
  '.htm': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.map': 'application/json',
  '.wasm': 'application/wasm',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.ico': 'image/x-icon',
  '.bmp': 'image/bmp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.eot': 'application/vnd.ms-fontobject',
  '.txt': 'text/plain',
  '.md': 'text/markdown',
  '.xml': 'text/xml',
  '.csv': 'text/csv',
  '.pdf': 'application/pdf',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.ogg': 'audio/ogg',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
};

/// ה-Content-Type שיוגש עבור [filePath].
///
/// חובה שיהיה מדויק ל-JS: WebKit מסרב להריץ מודול או Worker שהוגש עם טיפוס
/// שאינו JavaScript.
String pluginAssetContentType(String filePath) =>
    _contentTypes[p.extension(filePath).toLowerCase()] ??
    'application/octet-stream';
