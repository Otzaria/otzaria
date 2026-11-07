import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

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
    this.minidumpFile,
    this.details = '',
    this.appVersion,
    this.draftId,
    this.autosaveDelay = const Duration(milliseconds: 600),
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
    on<AppReportMinidumpToggled>(_onFieldChanged);
    on<AppReportImagesChanged>(_onFieldChanged);
    on<AppReportSubmitted>(_onSubmitted);
    on<AppReportDraftSaved>(_onDraftSaved);
    on<AppReportDraftDiscarded>(_onDraftDiscarded);
    on<AppReportAutosaveRequested>(_onAutosave);
    PreCloseRegistry.register(_preCloseCallback);
  }

  final AppReportTrigger trigger;
  final CrashSignature? signature;

  /// ה-dump של הקריסה, כשההצעה נפתחה אחרי קריסה נייטיבית.
  final File? minidumpFile;

  /// מידע אבחון פרטי שמוצג בתצוגה המקדימה, למשל מחסנית של ANR.
  final String details;
  final String? appVersion;
  final String? draftId;
  final Duration autosaveDelay;
  Timer? _autosaveTimer;
  int _draftEpoch = 0;
  bool _draftTerminated = false;
  bool _draftOperation = false;
  bool _draftLoadFailed = false;
  String _reportId = AppReport.generateReportId();
  AppReportDeliveryResult? _delivered;
  AppReportDraft? _restoredDraft;
  Future<void> _draftWrite = Future.value();
  Future<void> _lastDraftOperation = Future.value();
  late final Future<void> Function() _preCloseCallback = _flushDraftBeforeExit;

  final AppReportService _service;
  final AppReportCollector _collector;
  final AppReportRedactor _redactor;
  final DateTime Function() _clock;
  final AppReportType initialType;
  final String initialTitle;
  final String _initialEmail;

  /// גם דיווח קריסה ניתן להשהות: החתימה והצרופות נשמרות באותה טיוטה.
  bool get supportsDraft => true;

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
    final dumpFile = minidumpFile;
    final minidump = dumpFile == null
        ? null
        : await AppReportMinidump.fromFile(dumpFile);
    final draft = await _loadDraft();
    _restoredDraft = draft;
    _reportId = draft?.reportId ?? _reportId;
    emit(
      AppReportEditing(
        type: draft?.type ?? initialType,
        title: draft?.title ?? initialTitle,
        description: draft?.description ?? '',
        steps: draft?.steps ?? '',
        email: draft?.email ?? _initialEmail,
        diagnostics: draft != null
            ? draft.diagnostics
            : (details.isEmpty
                  ? attachments?.diagnostics
                  : {
                      ...?attachments?.diagnostics,
                      'hangDetails': _redactor.redactText(details),
                    }),
        errorLog: draft != null ? draft.errorLog : attachments?.errorLog,
        includeDiagnostics: draft?.includeDiagnostics ?? true,
        includeErrorLog: draft?.includeErrorLog ?? true,
        images: draft?.images ?? const [],
        minidump: draft != null ? draft.minidump : minidump,
        includeMinidump: draft?.includeMinidump ?? true,
        hasDraft: draft != null,
        invalidField: _draftLoadFailed ? 'draftLoad' : null,
      ),
    );
  }

  Future<AppReportDraft?> _loadDraft() async {
    // A new crash must never load an unrelated saved report. Explicit resume
    // restores its own trigger/signature instead of the currently open prompt.
    if (draftId == null && trigger != AppReportTrigger.manual) return null;
    try {
      return await _service.loadDraft(draftId: draftId);
    } catch (error, stackTrace) {
      _draftLoadFailed = true;
      debugPrint('App report draft load failed: $error\n$stackTrace');
      return null;
    }
  }

  bool _hasMeaningfulContent(AppReportEditing form) =>
      (_restoredDraft?.trigger ?? trigger) != AppReportTrigger.manual ||
      (_restoredDraft?.signature ?? signature) != null ||
      form.minidump != null ||
      form.title.trim() != initialTitle.trim() ||
      form.description.trim().isNotEmpty ||
      form.steps.trim().isNotEmpty ||
      form.email != _initialEmail ||
      form.images.isNotEmpty ||
      form.type != initialType ||
      !form.includeDiagnostics ||
      !form.includeErrorLog ||
      !form.includeMinidump;

  Future<void> _saveCurrentDraft(AppReportEditing form) {
    if (!supportsDraft || _draftTerminated || _draftLoadFailed) {
      return Future.value();
    }
    final epoch = _draftEpoch;
    final reportId = _reportId;
    final write = _draftWrite.then((_) async {
      if (_draftTerminated || epoch != _draftEpoch) return;
      if (!_hasMeaningfulContent(form)) {
        await _service.deleteDraft();
        return;
      }
      await _service.saveDraft(
        AppReportDraft(
          reportId: reportId,
          trigger: _restoredDraft?.trigger ?? trigger,
          signature: _restoredDraft?.signature ?? signature,
          minidump: form.minidump,
          includeMinidump: form.includeMinidump,
          type: form.type,
          title: form.title,
          description: form.description,
          steps: form.steps,
          email: form.email,
          includeDiagnostics: form.includeDiagnostics,
          includeErrorLog: form.includeErrorLog,
          images: form.images,
          diagnostics: form.diagnostics,
          errorLog: form.errorLog,
        ),
      );
    });
    _lastDraftOperation = write;
    _draftWrite = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<void> _deleteCurrentDraft() {
    final write = _draftWrite.then((_) => _service.deleteDraft());
    _lastDraftOperation = write;
    _draftWrite = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<void> _flushDraftBeforeExit() async {
    _autosaveTimer?.cancel();
    // Field events queued by the final keystroke must reach the form first.
    await Future<void>.delayed(Duration.zero);
    _autosaveTimer?.cancel();
    final current = state;
    if (!_draftTerminated &&
        current is AppReportEditing &&
        !current.isFinished) {
      await _saveCurrentDraft(current);
    }
    await _lastDraftOperation;
  }

  Future<void> _onAutosave(
    AppReportAutosaveRequested event,
    Emitter<AppReportState> emit,
  ) async {
    final current = state;
    if (event.epoch != _draftEpoch ||
        _draftTerminated ||
        current is! AppReportEditing ||
        current.isSending ||
        current.isFinished) {
      return;
    }
    try {
      await _saveCurrentDraft(current);
    } catch (error, stack) {
      debugPrint('Draft save failed: $error\n$stack');
      if (!emit.isDone && state is AppReportEditing) {
        emit((state as AppReportEditing).copyWith(invalidField: 'draftSave'));
      }
    }
  }

  Future<void> _onDraftSaved(
    AppReportDraftSaved event,
    Emitter<AppReportState> emit,
  ) async {
    final current = state;
    if (current is! AppReportEditing ||
        current.isSending ||
        _draftTerminated ||
        _draftOperation ||
        _draftLoadFailed) {
      return;
    }
    _autosaveTimer?.cancel();
    _draftOperation = true;
    emit(current.copyWith(submission: AppReportSubmission.sending));
    try {
      await _saveCurrentDraft(current);
      _draftTerminated = true;
      emit(
        current.copyWith(
          hasDraft: _hasMeaningfulContent(current),
          draftSaved: true,
        ),
      );
    } catch (error, stack) {
      debugPrint('Draft save failed: $error\n$stack');
      emit(current.copyWith(invalidField: 'draftSave'));
    } finally {
      _draftOperation = false;
    }
  }

  Future<void> _onDraftDiscarded(
    AppReportDraftDiscarded event,
    Emitter<AppReportState> emit,
  ) async {
    final current = state;
    if (current is! AppReportEditing ||
        current.isSending ||
        _draftTerminated ||
        _draftOperation ||
        _draftLoadFailed) {
      return;
    }
    _draftTerminated = true;
    _draftEpoch++;
    _autosaveTimer?.cancel();
    emit(current.copyWith(submission: AppReportSubmission.sending));
    try {
      await _deleteCurrentDraft();
      emit(
        AppReportEditing(
          type: initialType,
          title: initialTitle,
          description: '',
          steps: '',
          email: _initialEmail,
          diagnostics: current.diagnostics,
          errorLog: current.errorLog,
          minidump: current.minidump,
          draftDiscarded: true,
        ),
      );
    } catch (error, stack) {
      debugPrint('Draft discard failed: $error\n$stack');
      emit(current.copyWith(invalidField: 'draftSave'));
    } finally {
      if (state is AppReportEditing &&
          !(state as AppReportEditing).draftDiscarded) {
        _draftTerminated = false;
      }
    }
  }

  void _onFieldChanged(AppReportEvent event, Emitter<AppReportState> emit) {
    final current = state;
    if (current is! AppReportEditing ||
        current.isSending ||
        _draftTerminated ||
        _draftOperation ||
        _draftLoadFailed) {
      return;
    }
    final updated = switch (event) {
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
      AppReportMinidumpToggled(:final include) => current.copyWith(
        includeMinidump: include,
      ),
      AppReportImagesChanged(:final images) => current.copyWith(
        images: List.unmodifiable(images),
      ),
      _ => current,
    };
    final contentChanged =
        current.type != updated.type ||
        current.title != updated.title ||
        current.description != updated.description ||
        current.steps != updated.steps ||
        current.email != updated.email ||
        current.includeDiagnostics != updated.includeDiagnostics ||
        current.includeErrorLog != updated.includeErrorLog ||
        current.includeMinidump != updated.includeMinidump ||
        !listEquals(current.images, updated.images);
    // Another open form may already be sending the old content under its ID.
    // Unchanged retries keep their identity; actual edits get a new one.
    if (contentChanged) _reportId = AppReport.generateReportId();
    emit(updated);
    if (!contentChanged) return;
    if (supportsDraft) {
      _autosaveTimer?.cancel();
      _autosaveTimer = Timer(autosaveDelay, () {
        if (!isClosed) add(AppReportAutosaveRequested(_draftEpoch));
      });
    }
  }

  Future<void> _onSubmitted(
    AppReportSubmitted event,
    Emitter<AppReportState> emit,
  ) async {
    final current = state;
    if (current is! AppReportEditing ||
        current.isSending ||
        current.isFinished ||
        _draftOperation ||
        _draftLoadFailed ||
        (_draftTerminated && _delivered == null)) {
      return;
    }
    if (_delivered != null) {
      await _finishDelivery(current, _delivered!, emit);
      return;
    }

    final report = buildReport(current);
    final invalidField = report.validate();
    if (invalidField != null) {
      emit(current.copyWith(invalidField: invalidField));
      return;
    }

    _autosaveTimer?.cancel();
    emit(current.copyWith(submission: AppReportSubmission.sending));
    try {
      await _saveCurrentDraft(current);
      await _saveSenderEmail(report.reporterEmail);
      final result = event.queueOnly
          ? await (() async {
              final queued = await _service.queueReport(report);
              return AppReportDeliveryResult(
                status: AppReportDeliveryStatus.queued,
                report: queued,
              );
            })()
          : await _service.send(report);
      _reportId = result.report.reportId;
      if (result.status == AppReportDeliveryStatus.failed) {
        emit(
          current.copyWith(
            submission: AppReportSubmission.idle,
            result: result,
            invalidField: 'delivery',
          ),
        );
        return;
      }
      _delivered = result;
      await _finishDelivery(current, result, emit);
    } catch (error, stack) {
      debugPrint('App report submission failed: $error\n$stack');
      emit(
        current.copyWith(
          submission: AppReportSubmission.idle,
          invalidField: 'draftSave',
        ),
      );
    }
  }

  Future<void> _finishDelivery(
    AppReportEditing current,
    AppReportDeliveryResult result,
    Emitter<AppReportState> emit,
  ) async {
    _draftTerminated = true;
    _draftEpoch++;
    emit(current.copyWith(submission: AppReportSubmission.sending));
    try {
      if (supportsDraft) await _deleteCurrentDraft();
      emit(
        current.copyWith(
          submission: AppReportSubmission.finished,
          result: result,
          clearInvalidField: true,
        ),
      );
    } catch (error, stack) {
      debugPrint('Delivered report draft cleanup failed: $error\n$stack');
      // Keep the confirmed delivery result. Retrying only finishes local
      // cleanup, never resubmits a report that has already been delivered.
      emit(
        current.copyWith(
          submission: AppReportSubmission.idle,
          result: result,
          invalidField: 'draftFinalize',
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    PreCloseRegistry.unregister(_preCloseCallback);
    _autosaveTimer?.cancel();
    final current = state;
    if (!_draftTerminated &&
        current is AppReportEditing &&
        !current.isSending) {
      try {
        await _saveCurrentDraft(current);
      } catch (error, stack) {
        debugPrint('Draft save on close failed: $error\n$stack');
      }
    }
    await _draftWrite;
    return super.close();
  }

  Map<String, dynamic>? _budgetDiagnostics;
  String? _budgetLog;
  AppReportMinidump? _budgetDump;
  (bool, bool, bool)? _budgetIncludes;
  int? _attachmentBudget;

  /// Encoding/redacting large diagnostics on each keystroke freezes the form.
  /// These inputs only change when attachments or their inclusion changes.
  int otherAttachmentBytes(AppReportEditing form) {
    final includes = (
      form.includeDiagnostics,
      form.includeErrorLog,
      form.includeMinidump,
    );
    if (_attachmentBudget != null &&
        identical(_budgetDiagnostics, form.diagnostics) &&
        identical(_budgetLog, form.errorLog) &&
        identical(_budgetDump, form.minidump) &&
        _budgetIncludes == includes) {
      return _attachmentBudget!;
    }
    _budgetDiagnostics = form.diagnostics;
    _budgetLog = form.errorLog;
    _budgetDump = form.minidump;
    _budgetIncludes = includes;
    return _attachmentBudget = buildReport(form).otherAttachmentBytes;
  }

  /// בונה את הדיווח מהמצב הנוכחי, אחרי הסתרת מידע אישי בכל הטקסטים.
  AppReport buildReport(AppReportEditing form) {
    return AppReport(
      reportId: _reportId,
      type: form.type,
      trigger: _restoredDraft?.trigger ?? trigger,
      title: form.title,
      description: form.description,
      stepsToReproduce: form.steps,
      reporterEmail: form.email.trim(),
      appVersion: appVersion ?? ErrorLogFile.appVersion,
      platform: AppReport.currentPlatform(),
      osVersion: AppReportCollector.osVersion(),
      arch: AppReportCollector.detectArch(),
      signature: _restoredDraft?.signature ?? signature,
      createdAt: _clock(),
      diagnostics: form.includeDiagnostics ? form.diagnostics : null,
      errorLog: form.includeErrorLog ? form.errorLog : null,
      images: form.images,
      minidump: form.includeMinidump ? form.minidump : null,
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
