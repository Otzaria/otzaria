import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_wrapper.dart';

/// מצב מסך מלא של חלון אחד. נשמר במפתח ההגדרות ששחזור החלון בעלייה
/// (window_persistence) קורא.
class WindowFullscreenCubit extends Cubit<bool> {
  WindowFullscreenCubit({
    bool? initial,
    Future<void> Function(bool value)? persist,
  }) : _persist = persist ?? SettingsRepository().updateIsFullscreen,
       super(
         initial ??
             SettingsWrapper().getValue<bool>(
               SettingsRepository.keyIsFullscreen,
               defaultValue: false,
             ),
       );

  final Future<void> Function(bool value) _persist;

  /// מעדכן את המצב ושומר אותו; ערך זהה לנוכחי אינו פולט ואינו כותב.
  Future<void> set(bool value) async {
    if (value == state) return;
    emit(value);
    await _persist(value);
  }
}
