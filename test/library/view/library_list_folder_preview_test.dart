import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library/view/category_preview_panel.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

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

Category _folder(
  String title, {
  List<Category> subCategories = const [],
  List<Book> books = const [],
}) {
  final folder = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: List.of(subCategories),
    books: List.of(books),
    parent: null,
  );
  for (final sub in folder.subCategories) {
    sub.parent = folder;
  }
  return folder;
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
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('לחיצה על תיקייה בתצוגת רשימה מציגה אותה בתצוגה המקדימה '
      'ועדיין פותחת אותה (issue #2163)', (tester) async {
    final folder = _folder(
      'תיקייה',
      books: [TextBook(title: 'ספר פנימי', author: 'מחבר')],
    );
    final library = Library(categories: [folder]);
    folder.parent = library;

    final libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: library, currentCategory: library),
    );
    await _pumpBrowser(tester, libraryBloc);

    expect(find.text('ספר פנימי'), findsNothing);
    await tester.tap(find.text('תיקייה'));
    await tester.pumpAndSettle();

    verify(() => libraryBloc.add(SelectCategoryForPreview(folder))).called(1);
    expect(find.text('ספר פנימי'), findsOneWidget, reason: 'התיקייה נפתחת');
  });

  group('כניסה לתת-תיקייה מהתצוגה המקדימה (issue #1983)', () {
    late Category tanach;
    late Category torah;
    late Category meforshim;
    late LibraryBloc bloc;
    late List<LibraryState> states;

    setUp(() {
      meforshim = _folder(
        'מפרשים',
        subCategories: [
          _folder('ראשונים', books: [TextBook(title: 'רמב״ן')]),
        ],
        books: [TextBook(title: 'רש״י')],
      );
      torah = _folder(
        'תורה',
        subCategories: [meforshim],
        books: [TextBook(title: 'בראשית')],
      );
      tanach = _folder('תנ״ך', subCategories: [torah]);
    });

    Finder inPane(String text) => find.descendant(
      of: find.byType(CategoryPreviewPanel),
      matching: find.text(text),
    );

    /// התצוגה המקדימה מציגה את "תורה"; [headerOpen] — היא גם התיקייה הנוכחית.
    Future<void> pumpTorahPreview(
      WidgetTester tester, {
      required bool headerOpen,
    }) async {
      final library = Library(categories: [tanach]);
      tanach.parent = library;
      bloc = LibraryBloc()
        ..emit(
          LibraryState(
            library: library,
            currentCategory: headerOpen ? torah : tanach,
            previewCategory: torah,
          ),
        );
      await _pumpBrowser(tester, bloc);
      expect(inPane('תורה'), findsOneWidget);
      states = [];
      final subscription = bloc.stream.listen(states.add);
      addTearDown(subscription.cancel);
    }

    void expectEnteredMeforshimOnce() {
      expect(bloc.state.currentCategory, same(meforshim));
      expect(states, hasLength(1), reason: 'עדכון יחיד של הספרייה והתצוגה');
      expect(states.single.previewCategory, same(meforshim));
      expect(inPane('ראשונים'), findsOneWidget);
      expect(find.text('פתח תיקייה'), findsNothing);
    }

    for (final headerOpen in [false, true]) {
      final when = headerOpen ? 'כשתיקיית הכותרת פתוחה' : 'מתיקייה שנבחרה';

      testWidgets('לחיצה על תת-תיקייה נכנסת אליה $when (issue #1983)', (
        tester,
      ) async {
        await pumpTorahPreview(tester, headerOpen: headerOpen);
        await tester.tap(inPane('מפרשים'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expectEnteredMeforshimOnce();
      });

      testWidgets('לחיצה כפולה על תת-תיקייה נכנסת אליה פעם אחת $when '
          '(issue #1983)', (tester) async {
        await pumpTorahPreview(tester, headerOpen: headerOpen);
        final row = tester.getCenter(inPane('מפרשים'));
        await tester.tapAt(row);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(row);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expectEnteredMeforshimOnce();
      });

      testWidgets('Enter על תת-תיקייה ממוקדת נכנס אליה $when (issue #1983)', (
        tester,
      ) async {
        await pumpTorahPreview(tester, headerOpen: headerOpen);
        Focus.of(tester.element(inPane('מפרשים'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expectEnteredMeforshimOnce();
      });
    }
  });
}
