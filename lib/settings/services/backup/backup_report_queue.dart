/// Serialization and merge rules for persisted report queues in backups.
class BackupReportQueue {
  /// Converts a JSON/Hive value into maps with string keys.
  static List<Map<String, dynamic>> reportList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  static int sentTotal(Object? raw) => raw is int ? raw : 0;

  /// Error reports use `id`; plugin and app reports use `reportId`.
  static String? reportId(Map<String, dynamic> report) =>
      (report['id'] ?? report['reportId'])?.toString();

  static DateTime reportTime(Map<String, dynamic> report) =>
      DateTime.tryParse('${report['createdAt'] ?? ''}') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Local reports win; backed-up reports without an ID cannot be deduplicated.
  static List<Map<String, dynamic>> merge(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> backedUp,
  ) {
    final merged = [...local];
    final localIds = local.map(reportId).whereType<String>().toSet();
    for (final report in backedUp) {
      final id = reportId(report);
      if (id != null && localIds.contains(id)) continue;
      merged.add(report);
    }
    return merged;
  }
}
