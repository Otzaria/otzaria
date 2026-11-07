import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';

/// Form data deliberately does not use the validated transport model: a draft
/// may contain an empty email, incomplete prose or an invalid correction.
class BookReportDraftState {
  const BookReportDraftState(this.form, {this.saveFailed = false});
  final Map<String, dynamic> form;
  final bool saveFailed;
}

class BookReportDraftCubit extends Cubit<BookReportDraftState> {
  BookReportDraftCubit({
    required Map<String, dynamic> target,
    required Map<String, dynamic> initialForm,
    ReportDraftRecord? restored,
    ReportDraftStore? store,
    this.autosaveDelay = const Duration(milliseconds: 600),
  }) : target = Map.unmodifiable(target),
       _initialForm = Map.unmodifiable(initialForm),
       _session = ReportDraftSession(
         store: store ?? ReportDraftStore.instance,
         id: restored?.id ?? AppReport.generateReportId(),
         revision: restored?.revision ?? 0,
       ),
       _reportId = restored?.payload['reportId'] as String? ?? restored?.id,
       _lastSavedReportId =
           restored?.payload['reportId'] as String? ?? restored?.id,
       _lastSaved = restored == null
           ? null
           : Map<String, dynamic>.from(
               restored.payload['form'] as Map? ?? initialForm,
             ),
       super(
         BookReportDraftState(
           Map<String, dynamic>.from(
             restored?.payload['form'] as Map? ?? initialForm,
           ),
         ),
       ) {
    PreCloseRegistry.register(_preCloseCallback);
  }

  /// Fixed at creation/resume, independent of the currently open book.
  final Map<String, dynamic> target;
  final Map<String, dynamic> _initialForm;
  final ReportDraftSession _session;
  final Duration autosaveDelay;
  Timer? _timer;
  Map<String, dynamic>? _lastSaved;
  String? _lastSavedReportId;
  String? _reportId;
  bool _completed = false;
  late final Future<void> Function() _preCloseCallback = flush;

  String get id => _session.id;
  String get reportId => _reportId ??= AppReport.generateReportId();

  bool get hasContent =>
      !const DeepCollectionEquality().equals(state.form, _initialForm);
  bool get isCompleted => _completed;

  void updateForm(Map<String, dynamic> form) {
    if (_completed || const DeepCollectionEquality().equals(form, state.form)) {
      return;
    }
    _reportId = AppReport.generateReportId();
    emit(BookReportDraftState(Map.unmodifiable(form)));
    _timer?.cancel();
    _timer = Timer(autosaveDelay, () async {
      try {
        await flush();
      } catch (error, stack) {
        debugPrint('Book draft autosave failed: $error\n$stack');
      }
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (_completed || (!hasContent && _session.revision == 0)) {
      await _session.flush();
      return;
    }
    final form = state.form;
    final reportId = this.reportId;
    if (reportId == _lastSavedReportId &&
        const DeepCollectionEquality().equals(form, _lastSaved)) {
      await _session.flush();
      return;
    }
    try {
      await _session.save(
        kind: ReportDraftStore.bookKind,
        title: target['bookTitle'] as String,
        payload: {'target': target, 'form': form, 'reportId': reportId},
      );
      _lastSaved = form;
      _lastSavedReportId = reportId;
      if (!isClosed && state.saveFailed) emit(BookReportDraftState(state.form));
    } catch (_) {
      if (!isClosed) {
        emit(BookReportDraftState(state.form, saveFailed: true));
      }
      rethrow;
    }
  }

  /// Used only for explicit discard or confirmed delivery/queue handoff.
  Future<void> complete() async {
    _completed = true;
    _timer?.cancel();
    try {
      await _session.finish(preserveNewerRevision: true);
    } catch (_) {
      _completed = false;
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    PreCloseRegistry.unregister(_preCloseCallback);
    _timer?.cancel();
    if (!_completed) {
      try {
        await flush();
      } catch (error, stack) {
        debugPrint('Book draft close save failed: $error\n$stack');
      }
    }
    return super.close();
  }
}
