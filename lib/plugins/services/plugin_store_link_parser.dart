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
