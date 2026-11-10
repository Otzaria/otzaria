import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

void main() {
  late _MockTabsBloc tabsBloc;
  late _MockHistoryBloc historyBloc;
  late _MockNavigationBloc navigationBloc;
  late BookOpenCoordinator coordinator;
  late OpenedTab openTab;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    registerFallbackValue(CloseAllTabs());
    registerFallbackValue(CaptureStateForHistory(openTabFallback()));
    registerFallbackValue(const NavigateToScreen(Screen.reading));
  });

  setUp(() {
    openTab = TextBookTab(book: TextBook(title: 'פתוח'), index: 0);
    tabsBloc = _MockTabsBloc();
    historyBloc = _MockHistoryBloc();
    navigationBloc = _MockNavigationBloc();
    whenListen(
      tabsBloc,
      const Stream<TabsState>.empty(),
      initialState: TabsState(tabs: [openTab], currentTabIndex: 0),
    );
    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.library),
    );
    coordinator = BookOpenCoordinator(
      tabsBloc: tabsBloc,
      historyBloc: historyBloc,
      navigationBloc: navigationBloc,
    );
  });

  test('פתיחה רגילה שומרת היסטוריה לטאב הנוכחי ועוברת למסך הקריאה', () {
    coordinator.openBook(TextBook(title: 'חדש'), 0, '');

    verify(
      () => historyBloc.add(any(that: isA<CaptureStateForHistory>())),
    ).called(1);
    verify(() => tabsBloc.add(any(that: isA<OpenOrFocusTab>()))).called(1);
    verify(
      () => navigationBloc.add(const NavigateToScreen(Screen.reading)),
    ).called(1);
  });

  test('פתיחה בתוך אצווה (navigate ו-captureHistory כבויים) רק פותחת טאב', () {
    coordinator.openBook(
      TextBook(title: 'חדש'),
      0,
      '',
      navigate: false,
      captureHistory: false,
    );

    verifyNever(() => historyBloc.add(any()));
    verifyNever(() => navigationBloc.add(any()));
    verify(() => tabsBloc.add(any(that: isA<OpenOrFocusTab>()))).called(1);
  });

  test('showReadingScreen מנווט פעם אחת', () {
    coordinator.showReadingScreen();

    verify(
      () => navigationBloc.add(const NavigateToScreen(Screen.reading)),
    ).called(1);
  });
}

OpenedTab openTabFallback() =>
    TextBookTab(book: TextBook(title: 'fallback'), index: 0);
