import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/theme/app_theme_data.dart';
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

Category _category(
  String title,
  Category parent, {
  String description = '',
  String shortDescription = '',
}) {
  final category = Category(
    title: title,
    description: description,
    shortDescription: shortDescription,
    order: 0,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent.subCategories.add(category);
  return category;
}

Future<void> _pumpLibraryBrowser(
  WidgetTester tester,
  LibraryState state, {
  required Size size,
  double textScale = 1,
  bool showPreview = true,
}) async {
  final libraryBloc = _MockLibraryBloc();
  final settingsBloc = _MockSettingsBloc();
  final navigationBloc = _MockNavigationBloc();
  final libraryUpdateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());

  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: state,
  );
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(
      libraryShowPreview: showPreview,
    ),
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
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    await libraryBloc.close();
    await settingsBloc.close();
    await navigationBloc.close();
    await libraryUpdateBloc.close();
    await calendarCubit.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(),
      locale: const Locale('he', 'IL'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: FocusRepository()),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
          BlocProvider<CalendarCubit>.value(value: calendarCubit),
        ],
        child: const LibraryBrowser(),
      ),
    ),
  );
  await tester.pump();
  // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
  tester.takeException();
}

ThemeData _theme() => AppThemeData.light(
  ColorScheme.fromSeed(seedColor: Colors.blue),
  compactMenuMode: false,
);

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
  });

  testWidgets('רשת תוצאות החיפוש במסך צר אינה מייצרת כרטיסים גבוהים', (
    tester,
  ) async {
    final library = Library(categories: []);
    await _pumpLibraryBrowser(
      tester,
      LibraryState(
        library: library,
        currentCategory: library,
        searchResults: [
          TextBook(title: 'משנה ברורה', author: 'החפץ חיים'),
          TextBook(title: 'שולחן ערוך', author: 'מרן הבית יוסף'),
        ],
        searchQuery: 'ברורה',
      ),
      size: const Size(411, 731),
    );

    expect(find.byType(BookGridItem), findsWidgets);
    expect(
      tester.getSize(find.byType(BookGridItem).first).height,
      lessThanOrEqualTo(130),
    );
  });

  testWidgets(
    'תיקיות באותו שם בתוצאות החיפוש ברשת מציגות את נתיב האב (issue #1718)',
    (tester) async {
      final library = Library(categories: []);
      final shasCommentaries = _category(
        'מפרשים',
        _category('תלמוד בבלי', library),
      );
      final shulchanAruchCommentaries = _category(
        'מפרשים',
        _category('שולחן ערוך', _category('הלכה', library)),
      );
      await _pumpLibraryBrowser(
        tester,
        LibraryState(
          library: library,
          currentCategory: library,
          searchResults: const [],
          searchCategoryResults: [
            _category('בית מאיר', shasCommentaries),
            _category('בית מאיר', shulchanAruchCommentaries),
          ],
          searchQuery: 'בית מאיר',
        ),
        size: const Size(1200, 800),
      );

      final cards = find.byType(CategoryGridItem);
      expect(cards, findsNWidgets(2));
      Finder inCard(int index, String text) =>
          find.descendant(of: cards.at(index), matching: find.text(text));
      expect(inCard(0, 'תלמוד בבלי, מפרשים'), findsOneWidget);
      expect(inCard(1, 'הלכה, שולחן ערוך, מפרשים'), findsOneWidget);
    },
  );

  testWidgets('סינון לפי קטגוריה מסנן גם את התיקיות בתוצאות (issue #2070)', (
    tester,
  ) async {
    final library = Library(categories: []);
    await _pumpLibraryBrowser(
      tester,
      LibraryState(
        library: library,
        currentCategory: library,
        searchResults: [TextBook(title: 'דברי תורה', topics: 'קבלה, רמח"ל')],
        searchCategoryResults: [
          _category(
            'דברי חיים',
            _category('שות', _category('אחרונים', library)),
          ),
          _category('דברי שלום', _category('קבלה', library)),
        ],
        selectedTopics: const ['קבלה'],
        searchQuery: 'דברי',
      ),
      size: const Size(1200, 800),
    );

    expect(find.byType(CategoryGridItem), findsOneWidget);
    expect(find.text('דברי חיים'), findsNothing);
  });

  for (final width in [
    320.0,
    411.0,
    600.0,
    799.0,
    800.0,
    999.0,
    1000.0,
    1099.0,
    1100.0,
    1249.0,
    1250.0,
    1400.0,
  ]) {
    for (final scale in [1.0, 1.5, 2.0, 2.25]) {
      testWidgets('נתיבי תיקיות נראים ללא גלישה ברוחב $width ובהגדלה $scale', (
        tester,
      ) async {
        final library = Library(categories: []);
        const title = 'הגהות מהר״ם די לונזאנו על תלמוד ירושלמי';
        final parent = _category(
          'תלמוד ירושלמי, מפרשים, הגהות מהר״ם די לונזאנו על תלמוד ירושלמי',
          library,
        );
        await _pumpLibraryBrowser(
          tester,
          LibraryState(
            library: library,
            currentCategory: library,
            searchResults: const [],
            searchCategoryResults: [
              _category(
                title,
                parent,
                description: 'תיאור מלא של הקטגוריה',
                shortDescription: 'תיאור קצר של הקטגוריה',
              ),
              _category(title, parent),
              _category(title, library),
            ],
            searchQuery: 'הגהות',
          ),
          size: Size(width, 900),
          textScale: scale,
          showPreview: false,
        );

        final cards = find.byType(CategoryGridItem);
        expect(cards, findsNWidgets(3));
        for (var index = 0; index < 3; index++) {
          final card = cards.at(index);
          final texts = find.descendant(of: card, matching: find.byType(Text));
          final bounds = tester.getRect(card).deflate(10);
          for (final text in texts.evaluate()) {
            final rect = tester.getRect(find.byWidget(text.widget));
            expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.01));
            expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
            expect(Directionality.of(text), TextDirection.rtl);
            expect(MediaQuery.textScalerOf(text).scale(16), 16 * scale);
          }
          expect(
            tester
                .widget<LibraryItemTitle>(
                  find.descendant(
                    of: card,
                    matching: find.byType(LibraryItemTitle),
                  ),
                )
                .maxLines,
            2,
          );
        }
        expect(find.text(parent.title), findsNWidgets(2));
        for (final text in tester.widgetList<Text>(find.text(parent.title))) {
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
        }
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Tooltip && widget.message == parent.title,
          ),
          findsNWidgets(2),
        );
      });
    }
  }

  for (final scale in [1.0, 2.25]) {
    testWidgets('דפדוף ותוצאות ללא נתיב שומרים על גובה הכרטיס בהגדלה $scale', (
      tester,
    ) async {
      final library = Library(categories: []);
      final category = _category(
        'הגהות מהר״ם די לונזאנו על תלמוד ירושלמי',
        library,
      )..books.add(TextBook(title: 'ספר'));
      await _pumpLibraryBrowser(
        tester,
        LibraryState(library: library, currentCategory: library),
        size: const Size(800, 900),
        textScale: scale,
        showPreview: false,
      );
      final browsingHeight = tester
          .getSize(find.byType(CategoryGridItem))
          .height;
      final ratio = scale == 1 ? 1.8 : 1.45;
      expect(browsingHeight, closeTo((800 - 60 - 28) / 3 / ratio, 0.001));
      expect(
        tester.widget<MyGridView>(find.byType(MyGridView)).minItemHeight,
        0,
      );
      expect(
        (tester.widget<GridView>(find.byType(GridView)).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount)
            .mainAxisExtent,
        isNull,
      );
      await _pumpLibraryBrowser(
        tester,
        LibraryState(
          library: library,
          currentCategory: library,
          searchResults: const [],
          searchCategoryResults: [category],
          searchQuery: 'הגהות',
        ),
        size: const Size(800, 900),
        textScale: scale,
        showPreview: false,
      );
      expect(
        tester.getSize(find.byType(CategoryGridItem)).height,
        browsingHeight,
      );
      expect(
        tester.widget<MyGridView>(find.byType(MyGridView)).minItemHeight,
        0,
      );
      expect(find.byType(LibraryOverflowTooltipText), findsOneWidget);
    });
  }
}
