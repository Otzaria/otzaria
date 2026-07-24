import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/models/tab.dart' show OpenedTab;

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _DummyTab extends OpenedTab {
  _DummyTab() : super('dummy');

  @override
  Map<String, dynamic> toJson() => {'title': title};
}

class _FakeNavigationRepository implements NavigationRepository {
  bool libraryIsEmpty;
  _FakeNavigationRepository({this.libraryIsEmpty = false});

  @override
  bool checkLibraryIsEmpty() => libraryIsEmpty;

  @override
  Future<void> refreshLibrary() async {}
}

class _FakeTabsRepository implements TabsRepository {
  final bool hasTabs;
  _FakeTabsRepository({this.hasTabs = false});

  @override
  List<OpenedTab> loadTabs() => hasTabs ? [_DummyTab()] : [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

NavigationBloc _makeBloc({
  bool libraryIsEmpty = false,
  bool hasTabs = false,
}) => NavigationBloc(
  repository: _FakeNavigationRepository(libraryIsEmpty: libraryIsEmpty),
  tabsRepository: _FakeTabsRepository(hasTabs: hasTabs),
);

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('NavigationBloc', () {
    group('initial state', () {
      test('מתחיל במסך הספרייה כשאין טאבים', () {
        final bloc = _makeBloc(hasTabs: false);
        expect(bloc.state.currentScreen, Screen.library);
      });

      test('מתחיל במסך הקריאה כשיש טאבים', () {
        final bloc = _makeBloc(hasTabs: true);
        expect(bloc.state.currentScreen, Screen.reading);
      });

      test('isLibraryEmpty מתחיל כ-false', () {
        final bloc = _makeBloc();
        expect(bloc.state.isLibraryEmpty, isFalse);
      });

      test('hasCheckedLibrary מתחיל כ-false', () {
        final bloc = _makeBloc();
        expect(bloc.state.hasCheckedLibrary, isFalse);
      });
    });

    group('NavigateToScreen', () {
      test('מנווט למסך הקריאה', () async {
        final bloc = _makeBloc();
        bloc.add(const NavigateToScreen(Screen.reading));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.currentScreen, Screen.reading);
        await bloc.close();
      });

      test('מנווט למסך ההגדרות', () async {
        final bloc = _makeBloc();
        bloc.add(const NavigateToScreen(Screen.settings));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.currentScreen, Screen.settings);
        await bloc.close();
      });

      test('מנווט בין מסכים מרובים בסדר', () async {
        final bloc = _makeBloc();
        bloc.add(const NavigateToScreen(Screen.search));
        bloc.add(const NavigateToScreen(Screen.find));
        bloc.add(const NavigateToScreen(Screen.more));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.currentScreen, Screen.more);
        await bloc.close();
      });

      test('אינו משנה isLibraryEmpty בניווט', () async {
        final bloc = _makeBloc(libraryIsEmpty: false);
        bloc.add(const CheckLibrary());
        bloc.add(const NavigateToScreen(Screen.settings));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.isLibraryEmpty, isFalse);
        await bloc.close();
      });
    });

    group('CheckLibrary', () {
      test('מסמן hasCheckedLibrary כ-true', () async {
        final bloc = _makeBloc();
        bloc.add(const CheckLibrary());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.hasCheckedLibrary, isTrue);
        await bloc.close();
      });

      test('מעדכן isLibraryEmpty ל-true כשהספרייה ריקה', () async {
        final bloc = _makeBloc(libraryIsEmpty: true);
        bloc.add(const CheckLibrary());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.isLibraryEmpty, isTrue);
        await bloc.close();
      });

      test('מעדכן isLibraryEmpty ל-false כשהספרייה אינה ריקה', () async {
        final bloc = _makeBloc(libraryIsEmpty: false);
        bloc.add(const CheckLibrary());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.isLibraryEmpty, isFalse);
        await bloc.close();
      });

      test('אינו משנה את המסך הנוכחי', () async {
        final bloc = _makeBloc(hasTabs: true);
        expect(bloc.state.currentScreen, Screen.reading);
        bloc.add(const CheckLibrary());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.currentScreen, Screen.reading);
        await bloc.close();
      });
    });

    group('NavigationState', () {
      test('copyWith מעדכן רק currentScreen', () {
        const state = NavigationState(
          currentScreen: Screen.library,
          isLibraryEmpty: true,
          hasCheckedLibrary: true,
        );
        final updated = state.copyWith(currentScreen: Screen.reading);
        expect(updated.currentScreen, Screen.reading);
        expect(updated.isLibraryEmpty, isTrue);
        expect(updated.hasCheckedLibrary, isTrue);
      });

      test('copyWith מעדכן רק isLibraryEmpty', () {
        const state = NavigationState(
          currentScreen: Screen.library,
          isLibraryEmpty: false,
          hasCheckedLibrary: false,
        );
        final updated = state.copyWith(isLibraryEmpty: true);
        expect(updated.currentScreen, Screen.library);
        expect(updated.isLibraryEmpty, isTrue);
        expect(updated.hasCheckedLibrary, isFalse);
      });

      test('equatable - שני states זהים שווים', () {
        const a = NavigationState(currentScreen: Screen.reading);
        const b = NavigationState(currentScreen: Screen.reading);
        expect(a, equals(b));
      });

      test('equatable - states שונים אינם שווים', () {
        const a = NavigationState(currentScreen: Screen.reading);
        const b = NavigationState(currentScreen: Screen.library);
        expect(a, isNot(equals(b)));
      });
    });
  });
}
