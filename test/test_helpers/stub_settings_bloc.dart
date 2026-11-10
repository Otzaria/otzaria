import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

/// [SettingsBloc] שמחזיק מצב קבוע ומתעלם מכל אירוע.
/// בלי מצב — [SettingsState.initial].
class StubSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  StubSettingsBloc([SettingsState? initialState])
    : super(initialState ?? SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
