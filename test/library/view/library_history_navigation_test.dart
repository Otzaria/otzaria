import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/library_breadcrumb_bar.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import '../../test_helpers/stub_tabs_bloc.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Category _folder(String title, {List<Book> books = const []}) => Category(
  title: title,
  description: '',
  shortDescription: '',
  order: 1,
  subCategories: [],
  books: List.of(books),
  parent: null,
);

/// היסטוריית ביקורים בספרייה: כפתורים, לחצני הצד של העכבר והחלקה במשטח מגע
/// (issues #4012, #5078).
void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late Library library;
  late Category halacha;
  late Category tanach;
  late LibraryBloc bloc;

  Future<void> pump(WidgetTester tester) async {
    halacha = _folder('הלכה', books: [TextBook(title: 'שולחן ערוך')]);
    tanach = _folder('תנ״ך', books: [TextBook(title: 'בראשית')]);
    library = Library(categories: [tanach, halacha]);
    for (final c in library.subCategories) {
      c.parent = library;
    }
    bloc = LibraryBloc()
      ..emit(LibraryState(library: library, currentCategory: library));

    final settingsBloc = _MockSettingsBloc();
    final navigationBloc = _MockNavigationBloc();
    final updateBloc = _MockLibraryUpdateBloc();
    final calendarCubit = _StubCalendarCubit(CalendarState.initial());
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.library),
    );
    whenListen(
      updateBloc,
      const Stream<LibraryUpdateState>.empty(),
      initialState: const LibraryUpdateState(),
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      await settingsBloc.close();
      await navigationBloc.close();
      await updateBloc.close();
      await calendarCubit.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: MultiProvider(
          providers: [
            Provider<FocusRepository>.value(value: FocusRepository()),
            BlocProvider<LibraryBloc>(create: (_) => bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<TabsBloc>(
              create: (_) => StubTabsBloc(TabsState.initial()),
            ),
            BlocProvider<LibraryUpdateBloc>.value(value: updateBloc),
            BlocProvider<CalendarCubit>.value(value: calendarCubit),
            BlocProvider<CustomFoldersBloc>(
              create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
            ),
          ],
          child: const LibraryBrowser(),
        ),
      ),
    );
    await tester.pump();
    // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
    tester.takeException();
  }

  final backButton = find.byKey(const ValueKey('library-history-back'));
  final forwardButton = find.byKey(const ValueKey('library-history-forward'));

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<BarButton>(button).onPressed != null;

  Future<void> navigateTo(WidgetTester tester, Category category) async {
    bloc.add(NavigateToCategory(category));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('לחיצות חזרה רצופות לפני עיבוד האירועים שומרות קדימה', (
    tester,
  ) async {
    await pump(tester);
    await navigateTo(tester, halacha);
    await navigateTo(tester, tanach);
    final center = tester.getCenter(find.byType(MyGridView));
    final pointer = TestPointer(24, PointerDeviceKind.mouse, 24);
    for (var i = 0; i < 2; i++) {
      tester.binding.handlePointerEvent(
        pointer.down(center, buttons: kBackMouseButton),
      );
      tester.binding.handlePointerEvent(pointer.up());
    }
    await settle(tester);
    expect(bloc.state.currentCategory, same(library));
    expect(enabled(tester, forwardButton), isTrue);
    expect(enabled(tester, backButton), isFalse);
    for (var i = 0; i < 2; i++) {
      tester.binding.handlePointerEvent(
        pointer.down(center, buttons: kForwardMouseButton),
      );
      tester.binding.handlePointerEvent(pointer.up());
    }
    await settle(tester);
    expect(bloc.state.currentCategory, same(tanach));
    expect(enabled(tester, forwardButton), isFalse);
    expect(enabled(tester, backButton), isTrue);
  });

  testWidgets('כפתורי חזרה וקדימה עוברים בין התיקיות שבוקרו', (tester) async {
    await pump(tester);
    expect(enabled(tester, backButton), isFalse);
    expect(enabled(tester, forwardButton), isFalse);

    await navigateTo(tester, halacha);
    await navigateTo(tester, tanach);
    expect(enabled(tester, backButton), isTrue);
    expect(
      tester.widget<BarButton>(backButton).tooltip,
      contains('הלכה'),
    );

    await tester.tap(backButton);
    await settle(tester);
    expect(bloc.state.currentCategory, same(halacha));
    expect(enabled(tester, forwardButton), isTrue);

    await tester.tap(backButton);
    await settle(tester);
    expect(bloc.state.currentCategory, same(library));
    expect(enabled(tester, backButton), isFalse);

    await tester.tap(forwardButton);
    await settle(tester);
    expect(bloc.state.currentCategory, same(halacha));

    // ניווט חדש מבטל את מסלול הקדימה.
    await navigateTo(tester, library);
    expect(enabled(tester, forwardButton), isFalse);
    expect(enabled(tester, backButton), isTrue);
  });

  testWidgets('חזרה מדלגת על תיקייה שנמחקה מהספרייה', (tester) async {
    await pump(tester);
    await navigateTo(tester, halacha);
    await navigateTo(tester, tanach);
    library.subCategories.remove(halacha);

    await tester.tap(backButton);
    await settle(tester);
    expect(bloc.state.currentCategory, same(library));
  });

  testWidgets('לחצני הצד של העכבר חוזרים וממשיכים', (tester) async {
    await pump(tester);
    await navigateTo(tester, halacha);
    final center = tester.getCenter(find.byType(MyGridView));

    Future<void> click(int buttons) async {
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      await gesture.down(center);
      await gesture.up();
      await settle(tester);
    }

    await click(kBackMouseButton);
    expect(bloc.state.currentCategory, same(library));
    await click(kForwardMouseButton);
    expect(bloc.state.currentCategory, same(halacha));
  });

  testWidgets('החלקה אופקית בשתי אצבעות מנווטת פעם אחת, ואנכית לא', (
    tester,
  ) async {
    await pump(tester);
    await navigateTo(tester, halacha);
    await navigateTo(tester, tanach);
    final center = tester.getCenter(find.byType(MyGridView));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);

    Future<void> swipe(List<Offset> pans) async {
      await tester.sendEventToBinding(pointer.panZoomStart(center));
      for (final pan in pans) {
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(center, pan: pan),
        );
      }
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await settle(tester);
    }

    await swipe(const [Offset(0, 40), Offset(5, 160), Offset(10, 300)]);
    expect(bloc.state.currentCategory, same(tanach));

    // אצבעות ימינה = חזרה; המשך התנועה באותה מחווה אינו מנווט שוב.
    await swipe(const [Offset(40, 2), Offset(120, 5), Offset(260, 8)]);
    expect(bloc.state.currentCategory, same(halacha));

    await swipe(const [Offset(-50, 0), Offset(-150, 4), Offset(-300, 6)]);
    expect(bloc.state.currentCategory, same(tanach));
  });

  testWidgets('החלקה על נתיב התיקיות אינה מנווטת, ואחריה החלקה רגילה כן', (
    tester,
  ) async {
    await pump(tester);
    await navigateTo(tester, halacha);
    await navigateTo(tester, tanach);
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);

    Future<void> swipeRight(Offset at) async {
      await tester.sendEventToBinding(pointer.panZoomStart(at));
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(at, pan: const Offset(260, 4)),
      );
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await settle(tester);
    }

    await swipeRight(tester.getCenter(find.byType(LibraryBreadcrumbBar)));
    expect(bloc.state.currentCategory, same(tanach));

    await swipeRight(tester.getCenter(find.byType(MyGridView)));
    expect(bloc.state.currentCategory, same(halacha));
  });
}
