import 'package:equatable/equatable.dart';

enum Screen { library, find, reading, search, settings }

class NavigationState extends Equatable {
  final Screen currentScreen;
  final bool isLibraryEmpty;
  final bool hasCheckedLibrary;

  const NavigationState({
    required this.currentScreen,
    this.isLibraryEmpty = false,
    this.hasCheckedLibrary = false,
  });

  factory NavigationState.initial(bool hasTabs) {
    return NavigationState(
      currentScreen: hasTabs ? Screen.reading : Screen.library,
      isLibraryEmpty: false,
    );
  }

  NavigationState copyWith({
    Screen? currentScreen,
    bool? isLibraryEmpty,
    bool? hasCheckedLibrary,
  }) {
    return NavigationState(
      currentScreen: currentScreen ?? this.currentScreen,
      isLibraryEmpty: isLibraryEmpty ?? this.isLibraryEmpty,
      hasCheckedLibrary: hasCheckedLibrary ?? this.hasCheckedLibrary,
    );
  }

  @override
  List<Object?> get props => [currentScreen, isLibraryEmpty, hasCheckedLibrary];
}
