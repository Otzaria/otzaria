import 'package:equatable/equatable.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/models/tab.dart' show OpenedTab;

abstract class NavigationEvent extends Equatable {
  const NavigationEvent();

  @override
  List<Object?> get props => [];
}

class NavigateToScreen extends NavigationEvent {
  final Screen screen;

  const NavigateToScreen(this.screen);

  @override
  List<Object?> get props => [screen];
}

class CheckLibrary extends NavigationEvent {
  const CheckLibrary();
}

/// החלונית הפעילה בעמוד הטאבים השתנתה; המסך מיושר אליה (חיפוש/עיון).
/// ההשוואה לפי זהות החלונית — לטאבים אין שוויון ערכי.
class SyncScreenWithActivePane extends NavigationEvent {
  final OpenedTab? activePane;

  const SyncScreenWithActivePane(this.activePane);

  @override
  List<Object?> get props => [activePane];
}
