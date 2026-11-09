import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
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
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// השורה הנבחרת ברשימת הספרייה ב"לבן" בבהיר (סקירה רביעית 4.11,
/// q-white-selected): מילוי E0 וקו 9F ברוחב borderThin. שורה עצמאית (תוצאות
/// איתור, שורש) מקבלת אותו במסגרת ה-AppCard שלה, כי מסגרת הכרטיס מצוירת מעל
/// התוכן והייתה מכסה קו פנימי. שורה מקובצת מקבלת קו למעלה ולמטה בלבד. בערכות
/// הרגילות אין קו, והמראה הקודם נשמר.

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

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

ThemeData _theme(Color seed, Brightness brightness) {
  final cs = AppThemeData.createColorScheme(seed, brightness);
  final variant = AppThemeVariant.ofSeed(seed);
  return brightness == Brightness.dark
      ? AppThemeData.dark(cs, compactMenuMode: false, variant: variant)
      : AppThemeData.light(cs, compactMenuMode: false, variant: variant);
}

final _themes = <String, (Color, Brightness)>{
  'לבן בהיר': (AppSeedColors.white, Brightness.light),
  'רגיל בהיר': (AppSeedColors.defaultLight, Brightness.light),
  'רגיל כהה': (AppSeedColors.defaultDark, Brightness.dark),
};

/// הקו של "לבן" בבהיר: [AppSurfaceColors.selectedBorder], אפור 9F (159).
Color _line(ThemeData theme) {
  final c = theme.extension<AppSurfaceColors>()!.selectedBorder!;
  expect((c.r * 255).round(), 0x9F);
  return c;
}

({Library library, Category halacha}) _library() {
  Category cat(String title, int order, List<Book> books) => Category(
    title: title,
    description: '',
    shortDescription: '',
    order: order,
    subCategories: [],
    books: books,
    parent: null,
  );
  final halacha = cat('הלכה', 1, [
    TextBook(title: 'שולחן ערוך', author: 'רבי יוסף קארו'),
    TextBook(title: 'משנה תורה', author: 'רמב"ם'),
    TextBook(title: 'ערוך השולחן', author: 'רבי יחיאל מיכל'),
  ]);
  final chasidut = cat('חסידות', 2, [TextBook(title: 'תניא')]);
  final library = Library(categories: [halacha, chasidut]);
  halacha.parent = library;
  chasidut.parent = library;
  return (library: library, halacha: halacha);
}

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  LibraryState Function(Library library, Category halacha) state,
) async {
  final (:library, :halacha) = _library();
  final libraryBloc = _MockLibraryBloc();
  final settingsBloc = _MockSettingsBloc();
  final navigationBloc = _MockNavigationBloc();
  final updateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: state(library, halacha),
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
      theme: theme,
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
        child: const Material(child: LibraryBrowser()),
      ),
    ),
  );
  await tester.pump();
  // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
  tester.takeException();
}

/// ה-Material של השורה עצמה: הקרוב ביותר לכותרת.
Material _rowMaterial(WidgetTester tester, String title) => tester.widget(
  find.ancestor(of: find.text(title), matching: find.byType(Material)).first,
);

/// ה-Material של ה-AppCard שעוטף שורה עצמאית.
Material _cardMaterial(WidgetTester tester, String title) => tester.widget(
  find
      .descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(AppCard)),
        matching: find.byType(Material),
      )
      .first,
);

BorderSide _cardSide(WidgetTester tester, String title) =>
    (_cardMaterial(tester, title).shape! as RoundedRectangleBorder).side;

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final MapEntry(key: name, value: (seed, brightness))
      in _themes.entries) {
    final white = name == 'לבן בהיר';

    testWidgets('$name: שורה נבחרת בתוצאות האיתור', (tester) async {
      final theme = _theme(seed, brightness);
      final cs = theme.colorScheme;
      await _pump(
        tester,
        theme,
        (library, halacha) => LibraryState(
          library: library,
          currentCategory: library,
          searchQuery: 'ה',
          searchResults: halacha.books,
          previewBook: halacha.books[1],
        ),
      );

      final row = _rowMaterial(tester, 'משנה תורה');
      expect(row.color, cs.secondaryContainer);
      if (white) expect(row.color, AppThemeData.whiteSelectedFill);
      // הקו לא על השורה: מסגרת הכרטיס מעליה הייתה מכסה אותו.
      expect(row.shape, isNull);

      final selected = _cardSide(tester, 'משנה תורה');
      expect(selected.width, AppTokens.borderThin);
      expect(selected.color, white ? _line(theme) : cs.outlineVariant);
      expect(_cardMaterial(tester, 'משנה תורה').color, cs.secondaryContainer);

      // השכנה שאינה נבחרת: מסגרת כרטיס רגילה ורקע כרטיס.
      expect(_cardSide(tester, 'שולחן ערוך').color, cs.outlineVariant);
      expect(_rowMaterial(tester, 'שולחן ערוך').color, Colors.transparent);
      expect(_rowMaterial(tester, 'שולחן ערוך').shape, isNull);
    });

    testWidgets('$name: שורה נבחרת בתצוגה המקובצת', (tester) async {
      final theme = _theme(seed, brightness);
      final cs = theme.colorScheme;
      await _pump(
        tester,
        theme,
        (library, halacha) => LibraryState(
          library: library,
          currentCategory: library,
          previewBook: halacha.books[1],
        ),
      );
      await tester.tap(find.text('הלכה'));
      await tester.pumpAndSettle();
      tester.takeException();

      final row = _rowMaterial(tester, 'משנה תורה');
      expect(row.color, cs.secondaryContainer);
      if (white) {
        expect(row.color, AppThemeData.whiteSelectedFill);
        // קו למעלה ולמטה בלבד: בצדדים השורה נוגעת בגבול הקבוצה.
        final border = row.shape! as Border;
        for (final side in [border.top, border.bottom]) {
          expect(side.color, _line(theme));
          expect(side.width, AppTokens.borderThin);
        }
        expect(border.left, BorderSide.none);
        expect(border.right, BorderSide.none);
      } else {
        expect(row.shape, isNull);
        expect(theme.extension<AppSurfaceColors>()!.selectedBorder, isNull);
      }
      expect(_rowMaterial(tester, 'שולחן ערוך').shape, isNull);
      expect(_rowMaterial(tester, 'שולחן ערוך').color, Colors.transparent);
    });
  }
}
