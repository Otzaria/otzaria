import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/marker/bloc/marker_event.dart';
import 'package:otzaria/marker/bloc/marker_state.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/storage/marker_changes.dart';

/// רשימת הסימונים של מסך המרקר. נטענת בעמודים, והסינון והחיפוש רצים במסד,
/// כך שמאגר גדול אינו נטען לזיכרון בבת אחת.
class MarkerBloc extends Bloc<MarkerEvent, MarkerState> {
  static const int pageSize = 100;
  static const Duration _changeCoalesce = Duration(milliseconds: 150);

  MarkerBloc({
    MarkerRepository? repository,
    MarkerChanges? changes,
    MarkerSettings? settings,
  }) : _repository = repository ?? MarkerRepository(),
       _settings = settings ?? MarkerSettings.instance,
       super(const MarkerState()) {
    on<MarkerStarted>(_onStarted, transformer: droppable());
    on<MarkerQueryChanged>(_onQueryChanged, transformer: restartable());
    on<MarkerMoreRequested>(_onMore, transformer: droppable());
    on<MarkerStoreChanged>(_onStoreChanged, transformer: restartable());
    on<MarkerSelectionToggled>(_onSelectionToggled);
    on<MarkerSelectAllToggled>(_onSelectAll);
    on<MarkerSelectionCleared>(
      (event, emit) => emit(state.copyWith(selectedIds: const {})),
    );
    _changes = (changes ?? MarkerChanges.instance).stream.listen((_) {
      _pendingChange?.cancel();
      _pendingChange = Timer(_changeCoalesce, () {
        if (!isClosed) add(const MarkerStoreChanged());
      });
    });
  }

  final MarkerRepository _repository;
  final MarkerSettings _settings;
  late final StreamSubscription<MarkerChange> _changes;
  Timer? _pendingChange;

  /// כל טעינה מקבלת מספר; תוצאה של טעינה ישנה יותר אינה נכתבת למצב.
  int _generation = 0;
  MarkerQuery? _latestQuery;

  List<String> get _colorOrder => [
    for (final color in _settings.palette.colors) color.id,
  ];

  Future<void> _onStarted(MarkerStarted event, Emitter<MarkerState> emit) =>
      _load(
        emit,
        MarkerQuery(sort: _settings.sort, group: _settings.group),
        limit: pageSize,
      );

  Future<void> _onQueryChanged(
    MarkerQueryChanged event,
    Emitter<MarkerState> emit,
  ) async {
    final previous = state.query;
    if (event.query.sort != previous.sort ||
        event.query.group != previous.group) {
      unawaited(_settings.setListOrder(event.query.sort, event.query.group));
    }
    await _load(emit, event.query, limit: pageSize);
  }

  Future<void> _onStoreChanged(
    MarkerStoreChanged event,
    Emitter<MarkerState> emit,
  ) => _load(
    emit,
    _latestQuery ?? state.query,
    limit: state.items.length < pageSize ? pageSize : state.items.length,
    quiet: true,
  );

  Future<void> _load(
    Emitter<MarkerState> emit,
    MarkerQuery query, {
    required int limit,
    bool quiet = false,
  }) async {
    final generation = ++_generation;
    _latestQuery = query;
    if (!quiet) {
      emit(state.copyWith(status: MarkerListStatus.loading, query: query));
    }
    try {
      final page = await _repository.loadPage(
        query,
        limit: limit + 1,
        colorOrder: _colorOrder,
      );
      if (generation != _generation) return;
      final items = page.items;
      final visible = items.take(limit).toList();
      final ids = {for (final item in visible) item.id};
      emit(
        state.copyWith(
          status: MarkerListStatus.ready,
          query: query,
          items: visible,
          hasMore: items.length > limit,
          counts: page.counts,
          books: page.books,
          tags: page.tags,
          selectedIds: state.selectedIds.where(ids.contains).toSet(),
        ),
      );
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      debugPrint('MarkerBloc: load failed: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
      UiSnack.showError(MarkerMessages.loadFailed);
      emit(state.copyWith(status: MarkerListStatus.failure, query: query));
    }
  }

  Future<void> _onMore(
    MarkerMoreRequested event,
    Emitter<MarkerState> emit,
  ) async {
    // בזמן טעינה הרשימה שעל המסך עוד ישנה, וההיסט שלה אינו של השאילתה החדשה.
    if (!state.hasMore ||
        state.loadingMore ||
        state.status == MarkerListStatus.loading) {
      return;
    }
    final generation = _generation;
    emit(state.copyWith(loadingMore: true));
    try {
      final next = await _repository.query(
        state.query,
        offset: state.items.length,
        limit: pageSize + 1,
        colorOrder: _colorOrder,
      );
      // הרשימה נטענה מחדש בינתיים; העמוד הזה שייך לרשימה הקודמת.
      if (generation != _generation) {
        emit(state.copyWith(loadingMore: false));
        return;
      }
      emit(
        state.copyWith(
          items: [...state.items, ...next.take(pageSize)],
          hasMore: next.length > pageSize,
          loadingMore: false,
        ),
      );
    } catch (error) {
      debugPrint('MarkerBloc: next page failed: $error');
      UiSnack.showError(MarkerMessages.loadFailed);
      emit(state.copyWith(loadingMore: false));
    }
  }

  void _onSelectionToggled(
    MarkerSelectionToggled event,
    Emitter<MarkerState> emit,
  ) {
    final next = {...state.selectedIds};
    if (!next.remove(event.id)) next.add(event.id);
    emit(state.copyWith(selectedIds: next));
  }

  void _onSelectAll(MarkerSelectAllToggled event, Emitter<MarkerState> emit) {
    final all = {for (final item in state.items) item.id};
    final everything = all.every(state.selectedIds.contains);
    emit(state.copyWith(selectedIds: everything ? const {} : all));
  }

  @override
  Future<void> close() async {
    _pendingChange?.cancel();
    await _changes.cancel();
    return super.close();
  }
}
