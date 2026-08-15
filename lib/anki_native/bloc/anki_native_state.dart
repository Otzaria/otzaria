import 'package:equatable/equatable.dart';
import 'package:otzaria/anki_native/models/anki_native_window.dart';

sealed class AnkiNativeState extends Equatable {
  const AnkiNativeState();
}

class AnkiNativeInitial extends AnkiNativeState {
  const AnkiNativeInitial();
  @override
  List<Object?> get props => [];
}

class AnkiNativeLoading extends AnkiNativeState {
  const AnkiNativeLoading();
  @override
  List<Object?> get props => [];
}

class AnkiNativeReady extends AnkiNativeState {
  final int processId;
  final String generation;
  final List<AnkiNativeWindow> windows;
  final String? selectedTargetId;
  final bool visible;

  const AnkiNativeReady({
    required this.processId,
    required this.generation,
    required this.windows,
    required this.selectedTargetId,
    this.visible = true,
  });

  AnkiNativeWindow? get selectedWindow {
    for (final window in windows) {
      if (window.targetId == selectedTargetId) return window;
    }
    return null;
  }

  AnkiNativeReady copyWith({
    int? processId,
    String? generation,
    List<AnkiNativeWindow>? windows,
    String? selectedTargetId,
    bool? visible,
  }) => AnkiNativeReady(
    processId: processId ?? this.processId,
    generation: generation ?? this.generation,
    windows: windows ?? this.windows,
    selectedTargetId: selectedTargetId ?? this.selectedTargetId,
    visible: visible ?? this.visible,
  );

  @override
  List<Object?> get props => [
    processId,
    generation,
    windows,
    selectedTargetId,
    visible,
  ];
}

class AnkiNativeFailure extends AnkiNativeState {
  final String message;
  final bool canUseFallback;
  const AnkiNativeFailure(this.message, {this.canUseFallback = false});
  @override
  List<Object?> get props => [message, canUseFallback];
}
