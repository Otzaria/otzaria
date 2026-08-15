import 'package:equatable/equatable.dart';
import 'package:otzaria/anki_native/models/anki_native_window.dart';

sealed class AnkiNativeEvent extends Equatable {
  const AnkiNativeEvent();
}

class StartAnkiNative extends AnkiNativeEvent {
  const StartAnkiNative();
  @override
  List<Object?> get props => [];
}

class RefreshAnkiWindows extends AnkiNativeEvent {
  const RefreshAnkiWindows();
  @override
  List<Object?> get props => [];
}

class SelectAnkiWindow extends AnkiNativeEvent {
  final String targetId;
  const SelectAnkiWindow(this.targetId);
  @override
  List<Object?> get props => [targetId];
}

class CloseSelectedAnkiWindow extends AnkiNativeEvent {
  const CloseSelectedAnkiWindow();
  @override
  List<Object?> get props => [];
}

class UpdateAnkiNativeBounds extends AnkiNativeEvent {
  final AnkiNativeBounds bounds;
  const UpdateAnkiNativeBounds(this.bounds);
  @override
  List<Object?> get props => [bounds];
}

class SetAnkiNativeVisibility extends AnkiNativeEvent {
  final bool visible;
  const SetAnkiNativeVisibility(this.visible);
  @override
  List<Object?> get props => [visible];
}
