// ריחוף מעל כרטיסיה משנה רק אותה ואת המפריד של שכנתה, ולכן אינו בונה מחדש
// את שאר הכרטיסיות; ה-X שמוצג רק בריחוף עדיין מופיע ונעלם.
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<_TitleBarHarness> pumpTitleBar(
    WidgetTester tester, {
    required double width,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tabs = [for (var i = 0; i < 10; i++) _makeTextTab('ספר $i')];
    final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    addTearDown(() async {
      debugOnRebuildDirtyWidget = null;
      for (final tab in tabs) {
        tab.dispose();
      }
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await tester.pumpWidget(
      AppWindowScope(
        controller: const WindowManagerAppWindowController(),
        geometry: const WindowManagerAppWindowController(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<WorkStatusCubit>(create: (_) => WorkStatusCubit()),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<WindowFullscreenCubit>(
              create: (_) => WindowFullscreenCubit(
                initial: false,
                persist: (_) async {},
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CustomTitleBar(onReadingSettingsPressed: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 700));
    addTearDown(mouse.removePointer);
    await tester.pumpAndSettle();
    return _TitleBarHarness(tabs, mouse);
  }

  testWidgets('ריחוף מעל כרטיסיה אינו בונה מחדש את שאר הכרטיסיות', (
    tester,
  ) async {
    final harness = await pumpTitleBar(tester, width: 1400);

    var tabRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is TabTitleTooltip) tabRebuilds++;
    };
    await harness.mouse.moveTo(tester.getCenter(find.text('ספר 4')));
    await tester.pumpAndSettle();
    await harness.mouse.moveTo(tester.getCenter(find.text('ספר 6')));
    await tester.pumpAndSettle();
    await harness.mouse.moveTo(const Offset(10, 700));
    await tester.pumpAndSettle();
    debugOnRebuildDirtyWidget = null;

    // כל מעבר משנה את הכרטיסיה שבריחוף ואת השכנה שאחריה (המפריד שלה).
    expect(tabRebuilds, lessThanOrEqualTo(8));
  });

  testWidgets('ה-X של כרטיסיה צרה מופיע בריחוף ונעלם ביציאה', (tester) async {
    final harness = await pumpTitleBar(tester, width: 900);
    final closeButtons = find.byTooltip('סגור כרטיסיה');
    expect(closeButtons, findsNothing);

    await harness.mouse.moveTo(tester.getCenter(find.text('ספר 5')));
    await tester.pumpAndSettle();
    expect(closeButtons, findsOneWidget);

    await harness.mouse.moveTo(tester.getCenter(find.text('ספר 7')));
    await tester.pumpAndSettle();
    expect(closeButtons, findsOneWidget);

    await harness.mouse.moveTo(const Offset(10, 700));
    await tester.pumpAndSettle();
    expect(closeButtons, findsNothing);
    expect(harness.tabs, hasLength(10));
  });
}

class _TitleBarHarness {
  _TitleBarHarness(this.tabs, this.mouse);

  final List<TextBookTab> tabs;
  final TestGesture mouse;
}

TextBookTab _makeTextTab(String title) {
  final book = TextBook(title: title);
  final bloc = _TestTextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: const ['שורה א'],
      fontSize: 18,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      removePunctuation: false,
      visibleIndices: const [0],
      selectedIndex: 0,
      pinLeftPane: false,
      searchText: '',
      currentTitle: '',
    ),
  );
  return TextBookTab(book: book, index: 0, blocOverride: bloc);
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState);

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
