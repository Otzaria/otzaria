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
  });

  final AppReportType type;
  final String title;
  final String description;
  final String steps;
  final String email;
  final bool includeDiagnostics;
  final bool includeErrorLog;
  final List<AppReportImage> images;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'title': title,
    'description': description,
    'steps': steps,
    'email': email,
    'includeDiagnostics': includeDiagnostics,
    'includeErrorLog': includeErrorLog,
    'images': [for (final image in images) image.toJson()],
  };

  /// `null` לרשומה פגומה.
  static AppReportDraft? fromJson(Map<String, dynamic> json) {
    final type = AppReportType.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    if (type == null) return null;
    return AppReportDraft(
      type: type,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      steps: json['steps'] as String? ?? '',
      email: json['email'] as String? ?? '',
      includeDiagnostics: json['includeDiagnostics'] as bool? ?? true,
      includeErrorLog: json['includeErrorLog'] as bool? ?? true,
      images: [
        if (json['images'] case final List<dynamic> images)
          for (final image in images.map(AppReportImage.fromJson)) ?image,
      ],
    );
  }

  @override
  List<Object?> get props => [
    type,
    title,
    description,
    steps,
    email,
    includeDiagnostics,
    includeErrorLog,
    images,
  ];
}
