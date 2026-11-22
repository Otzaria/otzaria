import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/library/view/library_browser.dart';
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

import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

import '../../test_helpers/context_menu_description.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/plugin_menu_click_recorder.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  @override
  final navigationHistory = LibraryNavigationHistory();
}

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

/// פריטי תוספים בתפריט ההקשר של ספר בעץ הספרייה — ההקשר `library-book`.
({Library library, List<Book> books}) _library() {
  final halacha = Category(
    title: 'הלכה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: null,
  );
  final books = <Book>[
    TextBook(title: 'שולחן ערוך', id: 11, category: halacha),
    PdfBook(
      title: 'משנה ברורה',
      id: 12,
      path: 'משנה ברורה.pdf',
      category: halacha,
    ),
  ];
  halacha.books.addAll(books);
  final library = Library(categories: [halacha]);
  halacha.parent = library;
  return (library: library, books: books);
}

Future<void> _pump(
  WidgetTester tester,
  PluginMenuClickRecorder recorder,
) async {
  final (:library, :books) = _library();
  final libraryBloc = _MockLibraryBloc();
  final settingsBloc = _MockSettingsBloc();
  final navigationBloc = _MockNavigationBloc();
  final updateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(
      library: library,
      currentCategory: library,
      searchQuery: 'ה',
      searchResults: books,
    ),
  );
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
    updateBloc,
    const Stream<LibraryUpdateState>.empty(),
    initialState: const LibraryUpdateState(),
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    await libraryBloc.close();
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
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<LibraryUpdateBloc>.value(value: updateBloc),
          BlocProvider<CalendarCubit>.value(value: calendarCubit),
          BlocProvider<CustomFoldersBloc>(
            create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
          ),
        ],
        child: recorder.wrap(const Material(child: LibraryBrowser())),
      ),
    ),
  );
  await tester.pump();
  // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
  tester.takeException();
}

/// התפריט שנפתח בלחיצה ימנית על שורת הספר [title].
List<AppContextMenuEntry> _menuOf(WidgetTester tester, String title) {
  final finder = find
      .ancestor(
        of: find.text(title),
        matching: find.byType(AppContextMenuRegion),
      )
      .first;
  final region = tester.widget<AppContextMenuRegion>(finder);
  return region.menuBuilder(tester.element(finder), tester.getCenter(finder));
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('plugin items in the library book menu (issue #4466)', () {
    late PluginMenuClickRecorder recorder;

    setUp(() {
      recorder = PluginMenuClickRecorder('test.plan')
        ..register('add-to-plan', 'הוסף לתוכנית', ['library-book']);
      ContextMenuRegistry.instance.registerPayload('test.reader', {
        'id': 'reader-only',
        'title': 'פעולה על סימון',
      });
    });

    tearDown(() => ContextMenuRegistry.instance.removeAll('test.reader'));

    testWidgets('פריט library-book מופיע בסוף התפריט, ופריט של הקורא לא', (
      tester,
    ) async {
      await _pump(tester, recorder);
      final labels = describeContextMenu(_menuOf(tester, 'שולחן ערוך'));
      expect(labels.first, 'הוסף לבחירה');
      expect(labels.sublist(labels.length - 2), ['---', 'הוסף לתוכנית']);
      expect(labels, isNot(contains('פעולה על סימון')));
    });

    testWidgets('לחיצה מוסרת את זהות הספר ואת נתיב הקטגוריות', (tester) async {
      await _pump(tester, recorder);
      final payload = await recorder.click(
        tester,
        _menuOf(tester, 'משנה ברורה').last,
      );
      final selection = payload['selection'] as Map;
      expect(payload['currentBook'], 'משנה ברורה');
      expect(payload['id'], 12);
      expect(payload['type'], 'pdf');
      expect(payload['source'], 'library');
      expect(selection['bookId'], 'משנה ברורה');
      expect(selection['bookUid'], isNotEmpty);
      expect(selection['categoryPath'], '/הלכה');
      expect(payload['selectedText'], isEmpty);
    });

    testWidgets('bookTypes מגביל את הפריט לספרים מהסוג המבוקש', (tester) async {
      ContextMenuRegistry.instance.registerPayload('test.pdf', {
        'id': 'pdf-only',
        'title': 'פעולה ל-PDF',
        'contexts': ['library-book'],
        'bookTypes': ['pdf'],
        'action': kRecordedAction,
      });
      addTearDown(() => ContextMenuRegistry.instance.removeAll('test.pdf'));
      await _pump(tester, recorder);
      expect(
        describeContextMenu(_menuOf(tester, 'משנה ברורה')),
        contains('פעולה ל-PDF'),
      );
      expect(
        describeContextMenu(_menuOf(tester, 'שולחן ערוך')),
        isNot(contains('פעולה ל-PDF')),
      );
    });

    testWidgets('בלי פריטי library-book התפריט לא משתנה', (tester) async {
      ContextMenuRegistry.instance.removeAll('test.plan');
      await _pump(tester, recorder);
      expect(describeContextMenu(_menuOf(tester, 'שולחן ערוך')), [
        'הוסף לבחירה',
      ]);
    });
  });
}
