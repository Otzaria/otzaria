import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/models/crash_signature.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// טופס הדיווח על התוכנה: איסוף הצרופות, עריכה ושליחה.
class AppReportBloc extends Bloc<AppReportEvent, AppReportState> {
  AppReportBloc({
    required this.trigger,
    AppReportService? service,
    AppReportCollector? collector,
    AppReportRedactor? redactor,
    this.initialType = AppReportType.bug,
    this.initialTitle = '',
    String? initialEmail,
    this.signature,
    this.appVersion,
    DateTime Function()? clock,
  }) : _service = service ?? AppReportService(),
       _collector = collector ?? AppReportCollector(),
       _redactor = redactor ?? AppReportRedactor.fromPlatform(),
       _clock = clock ?? DateTime.now,
       _initialEmail = initialEmail ?? savedSenderEmail(),
       super(const AppReportCollecting()) {
    on<AppReportAttachmentsRequested>(_onAttachmentsRequested);
    on<AppReportTypeChanged>(_onFieldChanged);
    on<AppReportTitleChanged>(_onFieldChanged);
    on<AppReportDescriptionChanged>(_onFieldChanged);
    on<AppReportStepsChanged>(_onFieldChanged);
    on<AppReportEmailChanged>(_onFieldChanged);
    on<AppReportDiagnosticsToggled>(_onFieldChanged);
    on<AppReportErrorLogToggled>(_onFieldChanged);
    on<AppReportImagesChanged>(_onFieldChanged);
    on<AppReportSubmitted>(_onSubmitted);
  }

  final AppReportTrigger trigger;
  final CrashSignature? signature;
  final String? appVersion;

  final AppReportService _service;
  final AppReportCollector _collector;
  final AppReportRedactor _redactor;
  final DateTime Function() _clock;
  final AppReportType initialType;
  final String initialTitle;
  final String _initialEmail;

  /// כתובת הזיהוי השמורה בהגדרות, המשותפת לדיווחי הטעויות.
  static String savedSenderEmail() {
    if (!Settings.isInitialized) return '';
    return (Settings.getValue<String>(
              SettingsRepository.keyErrorReportSenderEmail,
            ) ??
            '')
        .trim();
  }

  Future<void> _onAttachmentsRequested(
    AppReportAttachmentsRequested event,
    Emitter<AppReportState> emit,
  ) async {
    AppReportAttachments? attachments;
    try {
      attachments = await _collector.collect();
    } catch (error, stackTrace) {
      debugPrint('App report collection failed: $error\n$stackTrace');
    }
    emit(
      AppReportEditing(
        type: initialType,
        title: initialTitle,
        description: '',
        steps: '',
        email: _initialEmail,
        diagnostics: attachments?.diagnostics,
        errorLog: attachments?.errorLog,
      ),
    );
  }

  void _onFieldChanged(AppReportEvent event, Emitter<AppReportState> emit) {
    final current = state;
    if (current is! AppReportEditing || current.isSending) return;
    emit(switch (event) {
      AppReportTypeChanged(:final type) => current.copyWith(type: type),
      AppReportTitleChanged(:final title) => current.copyWith(
        title: title,
        clearInvalidField: true,
      ),
      AppReportDescriptionChanged(:final description) => current.copyWith(
        description: description,
        clearInvalidField: true,
      ),
      AppReportStepsChanged(:final steps) => current.copyWith(steps: steps),
      AppReportEmailChanged(:final email) => current.copyWith(
        email: email,
        clearInvalidField: true,
      ),
      AppReportDiagnosticsToggled(:final include) => current.copyWith(
        includeDiagnostics: include,
      ),
      AppReportErrorLogToggled(:final include) => current.copyWith(
        includeErrorLog: include,
      ),
      AppReportImagesChanged(:final images) => current.copyWith(
        images: List.unmodifiable(images),
      ),
      _ => current,
    });
  }

  Future<void> _onSubmitted(
    AppReportSubmitted event,
    Emitter<AppReportState> emit,
  ) async {
    final current = state;
    if (current is! AppReportEditing || current.isSending) return;

    final report = buildReport(current);
    final invalidField = report.validate();
    if (invalidField != null) {
      emit(current.copyWith(invalidField: invalidField));
      return;
    }

    emit(current.copyWith(submission: AppReportSubmission.sending));
    await _saveSenderEmail(report.reporterEmail);
    final result = await _service.send(report);
    emit(
      current.copyWith(
        submission: AppReportSubmission.finished,
        result: result,
      ),
    );
  }

  /// בונה את הדיווח מהמצב הנוכחי, אחרי הסתרת מידע אישי בכל הטקסטים.
  @visibleForTesting
  AppReport buildReport(AppReportEditing form) {
    return AppReport(
      reportId: AppReport.generateReportId(),
      type: form.type,
      trigger: trigger,
      title: form.title,
      description: form.description,
      stepsToReproduce: form.steps,
      reporterEmail: form.email.trim(),
      appVersion: appVersion ?? ErrorLogFile.appVersion,
      platform: AppReport.currentPlatform(),
      osVersion: AppReportCollector.osVersion(),
      arch: AppReportCollector.detectArch(),
      signature: signature,
      createdAt: _clock(),
      diagnostics: form.includeDiagnostics ? form.diagnostics : null,
      errorLog: form.includeErrorLog ? form.errorLog : null,
      images: form.images,
    ).redactedWith(_redactor);
  }

  Future<void> _saveSenderEmail(String email) async {
    if (email.isEmpty || !Settings.isInitialized) return;
    if (email == savedSenderEmail()) return;
    await Settings.setValue(
      SettingsRepository.keyErrorReportSenderEmail,
      email,
    );
  }
}
