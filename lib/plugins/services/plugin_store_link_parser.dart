import 'package:otzaria/plugins/models/plugin_store_install_request.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';

class PluginStoreLinkParser {
  static PluginStoreInstallRequest? parseUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'otzaria') {
      return null;
    }

    final host = uri.host.toLowerCase();
    final pathSegments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.toLowerCase())
        .toList();

    final isPluginInstall =
        host == 'plugin' &&
        pathSegments.length == 1 &&
        pathSegments.first == 'install';
    if (!isPluginInstall) {
      return null;
    }

    final rawUrl = uri.queryParameters['url']?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      return null;
    }

    final downloadUri = Uri.tryParse(rawUrl);
    if (downloadUri == null) {
      return null;
    }

    final scheme = downloadUri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }

    final forceOverwrite = _parseBoolFlag(
      uri.queryParameters['overwrite'],
    );

    // token+callback אופציונליים — דיווח תוצאת ההתקנה חזרה לאתר.
    // callback לא-תקין (או שאינו באותו origin של כתובת ההורדה) — מתעלמים
    // משניהם וההתקנה ממשיכה כרגיל, בלי דיווח.
    PluginInstallReportContext? reportContext;
    final token = uri.queryParameters['token']?.trim();
    if (token != null && token.isNotEmpty) {
      final callbackUrl = PluginInstallReportService.validateCallback(
        uri.queryParameters['callback'],
        downloadUri,
      );
      if (callbackUrl != null) {
        reportContext = PluginInstallReportContext(
          token: token,
          callbackUrl: callbackUrl,
        );
      }
    }

    return PluginStoreInstallRequest(
      downloadUri: downloadUri,
      forceOverwrite: forceOverwrite,
      reportContext: reportContext,
    );
  }

  /// מארחי החנות הרשמית — רק אליהם נשלחת גרסת האוצריא.
  static const _storeHosts = {'otzaria.org', 'www.otzaria.org'};

  /// האם [uri] הוא כתובת הורדה של החנות הרשמית. `plugin.requestInstall` מגודר
  /// בזה: בלעדיו כל תוסף היה גורם להורדה מכל כתובת, בלי הרשאת רשת.
  /// https בלבד: המניפסט שמוצג בדיאלוג ההרשאות מגיע מתוך הארכיון, ולכן
  /// MITM על http היה מציג מניפסט תמים ומתקין ארכיון אחר.
  static bool isStoreDownloadUri(Uri uri) =>
      uri.scheme == 'https' && _storeHosts.contains(uri.host.toLowerCase());

  /// גרסה שהשרת מקבל: X[.Y[.Z[.W]]] עם סיומת prerelease/build אופציונלית.
  static final _appVersionPattern = RegExp(
    r'^\d+(?:\.\d+){0,3}(?:[-+][A-Za-z0-9.]+)?$',
  );

  /// מוסיפה `appVersion` לכתובת הורדה של החנות, כדי שהשרת יגיש את גרסת
  /// התוסף הגבוהה ביותר שתואמת לגרסת האוצריא הזו במקום את הגרסה האחרונה.
  ///
  /// מחזירה את [downloadUri] כמו-שהוא כשההוספה לא מתאימה: מארח שאינו החנות
  /// (אין לדלוף את גרסת האפליקציה לשרת זר), כתובת שאינה הורדת תוסף, גרסה
  /// מפורשת בנתיב (`<id>@<version>`) או `pending` — שילובים שהשרת דוחה ב-400.
  static Uri appendAppVersion(Uri downloadUri, String? appVersion) {
    final version = appVersion?.trim();
    if (version == null || !_appVersionPattern.hasMatch(version)) {
      return downloadUri;
    }
    if (!_storeHosts.contains(downloadUri.host.toLowerCase())) {
      return downloadUri;
    }

    final segments = downloadUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty || segments.last.toLowerCase() != 'download') {
      return downloadUri;
    }
    if (segments.any((segment) => segment.contains('@'))) {
      return downloadUri;
    }

    final query = downloadUri.queryParameters;
    if (query.containsKey('appVersion') || query.containsKey('pending')) {
      return downloadUri;
    }

    return downloadUri.replace(
      queryParameters: {...query, 'appVersion': version},
    );
  }

  static bool _parseBoolFlag(String? value) {
    if (value == null) {
      return false;
    }

    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      default:
        return false;
    }
  }
}
