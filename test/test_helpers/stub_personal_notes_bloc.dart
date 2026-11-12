import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';

/// [PersonalNotesBloc] שמחזיק מצב קבוע ומתעלם מכל אירוע.
/// בלי מצב — [PersonalNotesState.initial].
class StubPersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  StubPersonalNotesBloc([PersonalNotesState? initialState])
    : super(initialState ?? const PersonalNotesState.initial()) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
