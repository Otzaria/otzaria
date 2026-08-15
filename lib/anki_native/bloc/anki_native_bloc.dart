import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/anki_native/bloc/anki_native_event.dart';
import 'package:otzaria/anki_native/bloc/anki_native_state.dart';
import 'package:otzaria/anki_native/models/anki_native_window.dart';
import 'package:otzaria/anki_native/repository/anki_native_repository.dart';

class AnkiNativeBloc extends Bloc<AnkiNativeEvent, AnkiNativeState> {
  final AnkiNativeRepository repository;
  Timer? _refreshTimer;
  bool _refreshing = false;
  AnkiNativeBounds? _lastBounds;
  bool _desiredVisible = true;

  AnkiNativeBloc({required this.repository})
    : super(const AnkiNativeInitial()) {
    on<AnkiNativeEvent>(_onEvent, transformer: sequential());
  }

  Future<void> _onEvent(
    AnkiNativeEvent event,
    Emitter<AnkiNativeState> emit,
  ) => switch (event) {
    StartAnkiNative() => _onStart(event, emit),
    RefreshAnkiWindows() => _onRefresh(event, emit),
    SelectAnkiWindow() => _onSelect(event, emit),
    CloseSelectedAnkiWindow() => _onCloseSelected(event, emit),
    UpdateAnkiNativeBounds() => _onBounds(event, emit),
    SetAnkiNativeVisibility() => _onVisibility(event, emit),
  };

  Future<void> _onStart(
    StartAnkiNative event,
    Emitter<AnkiNativeState> emit,
  ) async {
    emit(const AnkiNativeLoading());
    try {
      await repository.ensureAnkiRunning();
      final snapshot = await repository.fetchWindows();
      final selected = _preferredWindow(snapshot.windows, null);
      emit(
        AnkiNativeReady(
          processId: snapshot.processId,
          generation: snapshot.generation,
          windows: snapshot.windows,
          selectedTargetId: selected?.targetId,
          visible: _desiredVisible,
        ),
      );
      _refreshTimer ??= Timer.periodic(
        const Duration(milliseconds: 750),
        (_) => add(const RefreshAnkiWindows()),
      );
    } catch (error) {
      await _emitFailure(emit, error);
    }
  }

  Future<void> _onRefresh(
    RefreshAnkiWindows event,
    Emitter<AnkiNativeState> emit,
  ) async {
    final current = state;
    if (current is! AnkiNativeReady || _refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await repository.fetchWindows();
      final selected = _preferredWindow(
        snapshot.windows,
        current.selectedTargetId,
      );
      if (selected != null && _lastBounds != null) {
        final attached = await repository.attach(
          selected,
          snapshot.processId,
          snapshot.generation,
        );
        if (attached && _lastBounds != null) {
          await repository.setBounds(_lastBounds!);
        }
      }
      emit(
        AnkiNativeReady(
          processId: snapshot.processId,
          generation: snapshot.generation,
          windows: snapshot.windows,
          selectedTargetId: selected?.targetId,
          visible: _desiredVisible,
        ),
      );
    } catch (error) {
      await _emitFailure(emit, error);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _onSelect(
    SelectAnkiWindow event,
    Emitter<AnkiNativeState> emit,
  ) async {
    final current = state;
    if (current is! AnkiNativeReady) return;
    final selected = current.windows
        .where((window) => window.targetId == event.targetId)
        .firstOrNull;
    if (selected == null) return;
    try {
      if (_lastBounds != null) {
        await repository.attach(
          selected,
          current.processId,
          current.generation,
        );
        await repository.setBounds(_lastBounds!);
      }
      emit(current.copyWith(selectedTargetId: selected.targetId));
    } catch (error) {
      await _emitFailure(emit, error);
    }
  }

  Future<void> _onCloseSelected(
    CloseSelectedAnkiWindow event,
    Emitter<AnkiNativeState> emit,
  ) async {
    final current = state;
    if (current is! AnkiNativeReady) return;
    final selected = current.selectedWindow;
    if (selected == null || !selected.closable) return;
    try {
      await repository.detach();
      await repository.closeWindow(selected.targetId);
      final snapshot = await repository.fetchWindows();
      final next = _preferredWindow(snapshot.windows, null);
      if (next != null && _lastBounds != null) {
        await repository.attach(next, snapshot.processId, snapshot.generation);
      }
      if (_lastBounds != null) await repository.setBounds(_lastBounds!);
      emit(
        AnkiNativeReady(
          processId: snapshot.processId,
          generation: snapshot.generation,
          windows: snapshot.windows,
          selectedTargetId: next?.targetId,
          visible: _desiredVisible,
        ),
      );
    } catch (error) {
      await _emitFailure(emit, error);
    }
  }

  Future<void> _onBounds(
    UpdateAnkiNativeBounds event,
    Emitter<AnkiNativeState> emit,
  ) async {
    if (_lastBounds == event.bounds) return;
    _lastBounds = event.bounds;
    try {
      final current = state;
      if (current is AnkiNativeReady && current.selectedWindow != null) {
        await repository.attach(
          current.selectedWindow!,
          current.processId,
          current.generation,
        );
        await repository.setVisible(_desiredVisible);
      }
      await repository.setBounds(event.bounds);
    } catch (error) {
      await _emitFailure(emit, error);
    }
  }

  Future<void> _onVisibility(
    SetAnkiNativeVisibility event,
    Emitter<AnkiNativeState> emit,
  ) async {
    _desiredVisible = event.visible;
    final current = state;
    if (current is AnkiNativeReady && current.visible == event.visible) return;
    try {
      await repository.setVisible(event.visible);
      if (current is AnkiNativeReady) {
        emit(current.copyWith(visible: event.visible));
      }
    } catch (error) {
      await _emitFailure(emit, error);
    }
  }

  Future<void> _emitFailure(
    Emitter<AnkiNativeState> emit,
    Object error,
  ) async {
    try {
      await repository.setVisible(false);
      await repository.detach();
    } catch (_) {}
    emit(
      AnkiNativeFailure(
        _message(error),
        canUseFallback:
            error is PlatformException || error is MissingPluginException,
      ),
    );
  }

  AnkiNativeWindow? _preferredWindow(
    List<AnkiNativeWindow> windows,
    String? currentTargetId,
  ) {
    for (final window in windows) {
      if (window.modal && window.active) return window;
    }
    for (final window in windows) {
      if (window.targetId == currentTargetId) return window;
    }
    for (final window in windows) {
      if (window.active) return window;
    }
    for (final window in windows) {
      if (window.kind == 'mainWindow') return window;
    }
    return windows.firstOrNull;
  }

  String _message(Object error) {
    final text = error.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    try {
      await repository.detach();
    } catch (_) {}
    repository.dispose();
    return super.close();
  }
}
