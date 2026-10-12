import 'reports_queue_format.dart';

/// דיווח משתמש על תוסף, כפי שנשמר בתור המקומי ונשלח לשרת האתר.
class PluginReportRecord {
  final String reportId;
  final String pluginUid;
  final String pluginName;
  final String pluginVersion;
  final String reportType;
  final String details;
  final String? reporterEmail;
  final String? appVersion;
  final String platform;
  final DateTime createdAt;

  /// בהיסטוריה: מי לקח את הדיווח לשליחה במקום אוצריא, ומתי.
  final String? carriedBy;
  final DateTime? carriedAt;

  const PluginReportRecord({
    required this.reportId,
    required this.pluginUid,
    required this.pluginName,
    required this.pluginVersion,
    required this.reportType,
    required this.details,
    this.reporterEmail,
    this.appVersion,
    required this.platform,
    required this.createdAt,
    this.carriedBy,
    this.carriedAt,
  });

  bool get isCarriedByOfflineUpdate => carriedBy == kCarriedByOfflineUpdate;

  factory PluginReportRecord.fromJson(Map<String, dynamic> json) {
    return PluginReportRecord(
      reportId: json['reportId'] as String? ?? '',
      pluginUid: json['pluginUid'] as String? ?? '',
      pluginName: json['pluginName'] as String? ?? '',
      pluginVersion: json['pluginVersion'] as String? ?? '',
      reportType: json['reportType'] as String? ?? 'other',
      details: json['details'] as String? ?? '',
      reporterEmail: json['reporterEmail'] as String?,
      appVersion: json['appVersion'] as String?,
      platform: json['platform'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      carriedBy: switch (json['carriedBy']) {
        final String value => value,
        _ => null,
      },
      carriedAt: switch (json['carriedAt']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reportId': reportId,
      'pluginUid': pluginUid,
      'pluginName': pluginName,
      'pluginVersion': pluginVersion,
      'reportType': reportType,
      'details': details,
      if (reporterEmail != null) 'reporterEmail': reporterEmail,
      if (appVersion != null) 'appVersion': appVersion,
      'platform': platform,
      'createdAt': createdAt.toIso8601String(),
      if (carriedBy != null) 'carriedBy': carriedBy,
      if (carriedAt != null) 'carriedAt': carriedAt!.toUtc().toIso8601String(),
    };
  }

  PluginReportRecord copyWith({
    String? reportId,
    String? reportType,
    String? details,
  }) {
    return PluginReportRecord(
      reportId: reportId ?? this.reportId,
      pluginUid: pluginUid,
      pluginName: pluginName,
      pluginVersion: pluginVersion,
      reportType: reportType ?? this.reportType,
      details: details ?? this.details,
      reporterEmail: reporterEmail,
      appVersion: appVersion,
      platform: platform,
      createdAt: createdAt,
      carriedBy: carriedBy,
      carriedAt: carriedAt,
    );
  }

  /// גוף הבקשה לשרת — שמות השדות קבועים בחוזה מול האתר.
  Map<String, dynamic> toApiPayload() {
    return {
      'reportId': reportId,
      'pluginUid': pluginUid,
      'pluginName': pluginName,
      'pluginVersion': pluginVersion,
      'reportType': reportType,
      'details': details,
      if (reporterEmail != null && reporterEmail!.isNotEmpty)
        'reporterEmail': reporterEmail,
      if (appVersion != null) 'appVersion': appVersion,
      'platform': platform,
    };
  }
}
