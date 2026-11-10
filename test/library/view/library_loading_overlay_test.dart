import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../support/golden_fonts.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

/// מספק CalendarState קבוע בלי להריץ את אתחול ה-cubit האמיתי.
class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpBrowser(WidgetTester tester, LibraryBloc libraryBloc) async {
  final settingsBloc = _MockSettingsBloc();
  final navigationBloc = _MockNavigationBloc();
  final libraryUpdateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());

  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(libraryViewMode: 'list'),
  );
  whenListen(
    navigationBloc,
    const Stream<NavigationState>.empty(),
    initialState: const NavigationState(currentScreen: Screen.library),
  );
  whenListen(
    libraryUpdateBloc,
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
    await libraryUpdateBloc.close();
    await calendarCubit.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: goldenPlatform),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: FocusRepository()),
          // create ולא value: הספק סוגר את ה-bloc בהסרת העץ, בתוך השעון
          // המדומה. close() שנקרא מה-tearDown אינו מסתיים.
          BlocProvider<LibraryBloc>(create: (_) => libraryBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
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

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('מסך טעינת הספרייה: טבעת דקה עם אייקון ספרייה וכיתוב "ספרייה" '
      '(issue #4238)', (tester) async {
    final library = Library(categories: []);
    final libraryBloc = LibraryBloc()
      ..emit(
        LibraryState(
          library: library,
          currentCategory: library,
          isLoading: true,
        ),
      );
    await _pumpBrowser(tester, libraryBloc);

    final loader = tester.widget<LoadingIndicator>(
      find.byType(LoadingIndicator),
    );
    expect(loader.strokeWidth, 3);
    expect(loader.icon, OtzariaIcons.bookshelf_24_regular);
    expect(find.text('טוען את הספרייה'), findsOneWidget);
    expect(find.text('טוען את הספר'), findsNothing);

    // הכיתוב סטטי: לא זז בין פריימים של האנימציה.
    final before = tester.getRect(find.text('טוען את הספרייה'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(find.text('טוען את הספרייה')), before);
  });
}
