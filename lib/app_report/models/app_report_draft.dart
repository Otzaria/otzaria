import 'package:equatable/equatable.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// טיוטה של טופס הדיווח על התוכנה, כפי שהמשתמש הקליד אותה (לפני הסתרה).
class AppReportDraft extends Equatable {
  const AppReportDraft({
    required this.type,
    required this.title,
    required this.description,
    required this.steps,
    required this.email,
    this.includeDiagnostics = true,
    this.includeErrorLog = true,
    this.images = const [],
    this.diagnostics,
    this.errorLog,
    this.reportId,
    this.trigger = AppReportTrigger.manual,
    this.signature,
    this.minidump,
    this.includeMinidump = true,
  });

  final AppReportType type;
  final String title;
  final String description;
  final String steps;
  final String email;
  final bool includeDiagnostics;
  final bool includeErrorLog;
  final List<AppReportImage> images;
  final Map<String, dynamic>? diagnostics;
  final String? errorLog;
  final String? reportId;
  final AppReportTrigger trigger;
  final CrashSignature? signature;
  final AppReportMinidump? minidump;
  final bool includeMinidump;

  Map<String, dynamic> toJson({bool includeAttachments = true}) => {
    'reportId': reportId,
    'trigger': trigger.name,
    'signature': signature?.toJson(),
    'includeMinidump': includeMinidump,
    'type': type.name,
    'title': title,
    'description': description,
    'steps': steps,
    'email': email,
    'includeDiagnostics': includeDiagnostics,
    'includeErrorLog': includeErrorLog,
    if (includeAttachments) ...attachmentsJson(),
  };

  Map<String, dynamic> attachmentsJson() => {
    'images': [for (final image in images) image.toJson()],
    'diagnostics': diagnostics,
    'errorLog': errorLog,
    'minidump': minidump?.toJson(),
  };

  /// `null` לרשומה פגומה.
  static AppReportDraft? fromJson(Map<String, dynamic> json) {
    final type = AppReportType.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    if (type == null) return null;
    return AppReportDraft(
      type: type,
      reportId: json['reportId'] as String?,
      trigger:
          AppReportTrigger.values
              .where((t) => t.name == json['trigger'])
              .firstOrNull ??
          AppReportTrigger.manual,
      signature: CrashSignature.fromJson(json['signature']),
      minidump: AppReportMinidump.fromJson(json['minidump']),
      includeMinidump: json['includeMinidump'] as bool? ?? true,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      steps: json['steps'] as String? ?? '',
      email: json['email'] as String? ?? '',
      includeDiagnostics: json['includeDiagnostics'] as bool? ?? true,
      includeErrorLog: json['includeErrorLog'] as bool? ?? true,
      diagnostics: json['diagnostics'] is Map
          ? Map<String, dynamic>.from(json['diagnostics'] as Map)
          : null,
      errorLog: json['errorLog'] as String?,
      images: [
        if (json['images'] case final List<dynamic> images)
          for (final image in images.map(AppReportImage.fromJson)) ?image,
      ],
    );
  }

  @override
  List<Object?> get props => [
    reportId,
    trigger,
    signature,
    minidump,
    includeMinidump,
    type,
    title,
    description,
    steps,
    email,
    includeDiagnostics,
    includeErrorLog,
    images,
    diagnostics,
    errorLog,
  ];
}
