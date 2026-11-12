import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';

/// [NavigationBloc] שמחזיק מצב קבוע ומתעלם מכל אירוע.
/// בלי מצב — [NavigationState.initial] כשיש לשוניות פתוחות (מסך הקריאה).
class StubNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  StubNavigationBloc([NavigationState? initialState])
    : super(initialState ?? NavigationState.initial(true)) {
    on<NavigationEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
