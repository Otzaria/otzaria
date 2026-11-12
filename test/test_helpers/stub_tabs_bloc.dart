import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';

/// [TabsBloc] שמחזיק מצב קבוע ומתעלם מכל אירוע.
class StubTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  StubTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
