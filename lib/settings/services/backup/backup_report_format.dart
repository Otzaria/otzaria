const appReportsBackupPendingV2 = 'pendingV2';

/// Keep current report payloads out of the field an older backup reader queues.
/// The separate field also survives older archive writers that reset version.
void setReportAwareBackupVersion(Map<String, dynamic> manifest) {
  manifest['version'] = '2.0';
  final queues = manifest['reportQueues'];
  if (queues is! Map) return;
  final appQueue = queues['app_reports_queue'];
  if (appQueue is! Map) return;

  final legacy = <Object?>[];
  final protectedReports = appQueue[appReportsBackupPendingV2];
  final current = protectedReports is List
      ? List<Object?>.of(protectedReports)
      : <Object?>[];
  final reports = appQueue['pending'];
  if (reports is List) {
    for (final report in reports) {
      if (report is Map && (report['schema'] ?? 1) != 1) {
        current.add(report);
      } else {
        legacy.add(report);
      }
    }
  }

  if (current.isEmpty) return;
  manifest['version'] = '3.0';
  manifest['reportQueues'] = {
    ...Map<String, dynamic>.from(queues),
    'app_reports_queue': {
      ...Map<String, dynamic>.from(appQueue),
      'pending': legacy,
      appReportsBackupPendingV2: current,
    },
  };
}
