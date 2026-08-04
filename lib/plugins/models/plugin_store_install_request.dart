import 'package:otzaria/plugins/services/plugin_install_report_service.dart';

class PluginStoreInstallRequest {
  final Uri downloadUri;
  final bool forceOverwrite;

  /// הקשר דיווח תוצאה חזרה לאתר (טוקן + callback). null כשהקישור לא כלל
  /// טוקן — התנהגות זהה לגרסאות קודמות, ללא דיווח.
  final PluginInstallReportContext? reportContext;

  const PluginStoreInstallRequest({
    required this.downloadUri,
    this.forceOverwrite = false,
    this.reportContext,
  });
}
