import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

/// [TextBookBloc] שמחזיק מצב קבוע ומתעלם מכל אירוע.
class StubTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  StubTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [StubTextBookBloc] שהבדיקה מחליפה את מצבו ב-[emitState].
class EmittingStubTextBookBloc extends StubTextBookBloc {
  EmittingStubTextBookBloc(super.initialState);

  void emitState(TextBookState state) => emit(state);
}
