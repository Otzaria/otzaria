import 'package:equatable/equatable.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/models/app_report_image.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';

/// שלב השליחה של הטופס.
enum AppReportSubmission { idle, sending, finished }

sealed class AppReportState extends Equatable {
  const AppReportState();

  @override
  List<Object?> get props => const [];
}

/// אוסף את האבחון ואת קטע הלוג; הטופס עדיין לא מוצג.
class AppReportCollecting extends AppReportState {
  const AppReportCollecting();
}

/// הטופס הפעיל, על שדותיו, הצרופות שנאספו ותוצאת השליחה.
class AppReportEditing extends AppReportState {
  const AppReportEditing({
    required this.type,
    required this.title,
    required this.description,
    required this.steps,
    required this.email,
    this.diagnostics,
    this.errorLog,
    this.includeDiagnostics = true,
    this.includeErrorLog = true,
    this.images = const [],
    this.submission = AppReportSubmission.idle,
    this.result,
    this.invalidField,
  });

  final AppReportType type;
  final String title;
  final String description;
  final String steps;
  final String email;

  /// הצרופות שנאספו, כבר אחרי הסתרת מידע אישי. `null` כשהאיסוף נכשל.
  final Map<String, dynamic>? diagnostics;
  final String? errorLog;

  final bool includeDiagnostics;
  final bool includeErrorLog;

  /// צילומי המסך שצורפו לדיווח.
  final List<AppReportImage> images;
  final AppReportSubmission submission;
  final AppReportDeliveryResult? result;

  /// השדה שנכשל בבדיקת התקינות המקומית (`title`/`description`/`reporterEmail`).
  final String? invalidField;

  bool get isSending => submission == AppReportSubmission.sending;
  bool get isFinished => submission == AppReportSubmission.finished;

  AppReportEditing copyWith({
    AppReportType? type,
    String? title,
    String? description,
    String? steps,
    String? email,
    Map<String, dynamic>? diagnostics,
    String? errorLog,
    bool? includeDiagnostics,
    bool? includeErrorLog,
    List<AppReportImage>? images,
    AppReportSubmission? submission,
    AppReportDeliveryResult? result,
    String? invalidField,
    bool clearInvalidField = false,
  }) {
    return AppReportEditing(
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      steps: steps ?? this.steps,
      email: email ?? this.email,
      diagnostics: diagnostics ?? this.diagnostics,
      errorLog: errorLog ?? this.errorLog,
      includeDiagnostics: includeDiagnostics ?? this.includeDiagnostics,
      includeErrorLog: includeErrorLog ?? this.includeErrorLog,
      images: images ?? this.images,
      submission: submission ?? this.submission,
      result: result ?? this.result,
      invalidField: clearInvalidField
          ? null
          : (invalidField ?? this.invalidField),
    );
  }

  @override
  List<Object?> get props => [
    type,
    title,
    description,
    steps,
    email,
    diagnostics,
    errorLog,
    includeDiagnostics,
    includeErrorLog,
    images,
    submission,
    result,
    invalidField,
  ];
}
