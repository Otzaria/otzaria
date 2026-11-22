// Responsive: מסכי הספרייה וההתקנה בכל המטריצה (שלב 1/6/10 של סבב השלמת מערכת
// העיצוב). ספרייה (רשת, רשימה, תצוגה מקדימה, חיפוש, ריקה, גדולה, שמות ארוכים,
// שגיאה), ומסכי ההתקנה, העדכון והייבוא.
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart' show verify;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:otzaria/android_update/bloc/android_update_bloc.dart';
import 'package:otzaria/android_update/bloc/android_update_event.dart';
import 'package:otzaria/android_update/bloc/android_update_state.dart';
import 'package:otzaria/android_update/models/android_update.dart';
import 'package:otzaria/android_update/view/android_update_host.dart';
import 'package:otzaria/android_update/view/android_update_view.dart';
import 'package:otzaria/attached_libraries/bloc/attached_libraries_bloc.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_library_update_service.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/attached_libraries/view/attached_libraries_panel.dart';
import 'package:otzaria/attached_libraries/view/external_link_index_tile.dart';
import 'package:otzaria/attached_libraries/view/attached_library_update_view.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/library/view/book_versions_dialog.dart';
import 'package:otzaria/library/view/category_details_dialog.dart';
import 'package:otzaria/library/view/category_preview_panel.dart';
import 'package:otzaria/library/view/library_daf_yomi.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_dialog.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/update/hebrew_update_widgets.dart';
import 'package:otzaria/update/updat_compat.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:otzaria/widgets/feedback/indexing_warning.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_store.dart';
import 'package:otzaria/settings/dialogs/library_setup_dialog.dart';
import '../../android_update/support.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
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

import '../../test_helpers/memory_cache_provider.dart';
import '../../support/golden_fonts.dart';
import 'responsive_harness.dart';

/// היום בשנה שבו שורת התאריך והדף היומי הכי ארוכה: התוצאה לא תלויה בתאריך
/// שבו הבדיקה רצה.
final DateTime _longestDafDay = () {
  var best = DateTime(2026, 11, 18);
  var bestLength = 0;
  for (var i = 0; i < 400; i++) {
    final day = DateTime(2026, 1, 1).add(Duration(days: i));
    final daf = getDafYomi(day);
    final length =
        getHebrewDateFormattedAsString(day).length +
        '${daf.getMasechta()} ${formatAmud(daf.getDaf())}'.length;
    if (length > bestLength) {
      bestLength = length;
      best = day;
    }
  }
  return best;
}();

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

/// מספק CalendarState קבוע בלי להריץ את אתחול ה-cubit האמיתי.
class _MockAndroidUpdateBloc
    extends MockBloc<AndroidUpdateEvent, AndroidUpdateState>
    implements AndroidUpdateBloc {}

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _longTitle =
    'שו"ת מחכמי ספרד ואשכנז בדורות האחרונים עם הערות והארות ומראי מקומות לכל הדעות';
const _longAuthor = 'הרב רבי אברהם בן רבי יצחק בן רבי יעקב מקראקא ומלבוב';

Category _category(
  String title,
  Category parent, {
  List<Book> books = const [],
}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: List.of(books),
    parent: parent,
  );
  parent.subCategories.add(category);
  return category;
}

Book _book(String title, {String author = 'מחבר'}) =>
    TextBook(title: title, author: author);

/// ספרייה קטנה: כמה קטגוריות וספרים ברמה הראשית.
Library _smallLibrary() {
  final library = Library(categories: []);
  for (final name in ['תנ"ך', 'משנה', 'תלמוד בבלי']) {
    _category(name, library, books: [_book('ספר של $name')]);
  }
  library.books = [for (var i = 0; i < 6; i++) _book('ספר $i')];
  return library;
}

/// ספרייה גדולה: 40 קטגוריות, ובכל אחת עץ עמוק ו-12 ספרים; בשורש 300 ספרים.
Library _bigLibrary() {
  final library = Library(categories: []);
  for (var i = 0; i < 40; i++) {
    var parent = _category(
      'קטגוריה $i',
      library,
      books: [
        for (var b = 0; b < 12; b++) _book('ספר $i-$b'),
      ],
    );
    for (var depth = 0; depth < 6; depth++) {
      parent = _category(
        'רמה ${depth + 1} של $i',
        parent,
        books: [_book('ספר עמוק $depth')],
      );
    }
  }
  library.books = [
    for (var i = 0; i < 300; i++) _book('ספר בשורש $i', author: 'מחבר $i'),
  ];
  return library;
}

/// ספרייה עם שמות ארוכים מאוד של קטגוריות, ספרים ומחברים.
Library _longNamesLibrary() {
  final library = Library(categories: []);
  _category(_longTitle, library, books: [_book('ספר')]);
  _category('קטגוריה ללא רווחים ${'א' * 80}', library, books: [_book('ספר')]);
  library.books = [
    _book(_longTitle, author: _longAuthor),
    _book('${'ב' * 90} English${'X' * 60}', author: _longAuthor),
    _book('ספר רגיל'),
  ];
  return library;
}

typedef _Setup = ({
  LibraryState library,
  String viewMode,
  bool showPreview,
  bool isLibraryEmpty,
  bool hebrewBooks,
});

/// ה-blocs של מסך הספרייה סביב ה-MaterialApp של התשתית.
Widget Function(Widget) _libraryApp(_Setup s) {
  return (app) => MultiProvider(
    providers: [
      Provider<FocusRepository>(create: (_) => FocusRepository()),
      BlocProvider<LibraryBloc>(
        create: (_) {
          final bloc = _MockLibraryBloc();
          whenListen(
            bloc,
            const Stream<LibraryState>.empty(),
            initialState: s.library,
          );
          return bloc;
        },
      ),
      BlocProvider<SettingsBloc>(
        create: (_) {
          final bloc = _MockSettingsBloc();
          whenListen(
            bloc,
            const Stream<SettingsState>.empty(),
            initialState: SettingsState.initial().copyWith(
              libraryViewMode: s.viewMode,
              libraryShowPreview: s.showPreview,
              hebrewBooksPath: s.hebrewBooks ? 'C:/hebrewbooks' : '',
            ),
          );
          return bloc;
        },
      ),
      BlocProvider<NavigationBloc>(
        create: (_) {
          final bloc = _MockNavigationBloc();
          whenListen(
            bloc,
            const Stream<NavigationState>.empty(),
            initialState: NavigationState(
              currentScreen: Screen.library,
              isLibraryEmpty: s.isLibraryEmpty,
            ),
          );
          return bloc;
        },
      ),
      BlocProvider<LibraryUpdateBloc>(
        create: (_) {
          final bloc = _MockLibraryUpdateBloc();
          whenListen(
            bloc,
            const Stream<LibraryUpdateState>.empty(),
            initialState: const LibraryUpdateState(),
          );
          return bloc;
        },
      ),
      BlocProvider<CalendarCubit>(
        create: (_) => _StubCalendarCubit(
          CalendarState.initial().copyWith(todayGregorianDate: _longestDafDay),
        ),
      ),
      BlocProvider<CustomFoldersBloc>(
        create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
      ),
    ],
    child: app,
  );
}

_Setup _setup(
  Library library, {
  String viewMode = 'grid',
  bool showPreview = false,
  bool isLibraryEmpty = false,
  bool hebrewBooks = false,
  Category? currentCategory,
  List<Book>? searchResults,
  String? searchQuery,
  Category? previewCategory,
  String? error,
  bool isLoading = false,
  bool isSearching = false,
  Book? previewBook,
}) => (
  library: LibraryState(
    library: library,
    currentCategory: currentCategory ?? library,
    searchResults: searchResults,
    searchQuery: searchQuery,
    previewCategory: previewCategory,
    previewBook: previewBook,
    error: error,
    isLoading: isLoading,
    isSearching: isSearching,
  ),
  viewMode: viewMode,
  showPreview: showPreview,
  isLibraryEmpty: isLibraryEmpty,
  hebrewBooks: hebrewBooks,
);

/// פעולה בסרגל הספרייה נגישה בכל רוחב: ישירות, או בתפריט "עוד פעולות".
Future<void> _expectBarAction(
  WidgetTester tester,
  ResponsiveRun run,
  String tooltip,
) async {
  final direct = find.byTooltip(tooltip);
  if (direct.evaluate().isNotEmpty &&
      direct.hitTestable().evaluate().isNotEmpty) {
    expectVisible(tester, run, direct, name: 'כפתור "$tooltip"');
    return;
  }
  final more = find.byTooltip('עוד פעולות');
  if (more.evaluate().isEmpty) {
    run.add(
      ResponsiveIssue(
        'not-reachable',
        '"$tooltip": לא בסרגל ואין "עוד פעולות"',
      ),
    );
    return;
  }
  await tester.tap(more.first);
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  expectVisible(
    tester,
    run,
    find.text(tooltip),
    name: 'פריט "$tooltip" ב"עוד"',
  );
  await tester.tapAt(const Offset(1, 1));
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

/// סרגל הספרייה: שדה האיתור, הניווט, ההגדרות והרענון נגישים בכל רוחב.
Future<void> _libraryBarChecks(
  WidgetTester tester,
  ResponsiveRun run, {
  bool refresh = false,
}) async {
  expectVisible(
    tester,
    run,
    find.byType(TextField).first,
    name: 'שדה האיתור בספרייה',
  );
  // שדה האיתור נשאר שמיש בכל רוחב. ב-320 הוא צר (80px) והרמז נקטע ב"...":
  // ההכרעה ממתינה לבעל הפרויקט (DESIGN_DECISIONS, שאלות פתוחות), וכאן נשמר רק הרוחב הנוכחי כרצפה.
  final fieldWidth = tester.getSize(find.byType(TextField).first).width;
  if (fieldWidth < 80) {
    run.add(
      ResponsiveIssue('tap-target', 'שדה האיתור צר מדי: ${fieldWidth}px'),
    );
  }
  await _expectBarAction(tester, run, 'לתיקייה העליונה');
  await _expectBarAction(tester, run, 'חזרה לתיקיה הראשית');
  await _expectBarAction(tester, run, 'הגדרות ספרייה');
  if (refresh) await _expectBarAction(tester, run, 'טעינה מחדש');
}

/// כמו [testResponsive] למצבי טעינה: ספינר אינסופי, ולכן בלי `pumpAndSettle`.
void testResponsiveAnimating(
  String description, {
  required Widget Function(BuildContext context) build,
  required Widget Function(Widget app) wrapApp,
  required ResponsiveAct verify,
}) => testResponsive(
  description,
  build: build,
  wrapApp: wrapApp,
  settle: false,
  act: (tester, run) => tester.pump(const Duration(milliseconds: 300)),
  verify: verify,
);

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  void libraryScene(
    String name,
    _Setup Function() setup, {
    ResponsiveAct? act,
    ResponsiveAct? verify,
    bool refresh = false,
    bool bar = true,
    bool animating = false,
  }) {
    if (animating) {
      testResponsiveAnimating(
        name,
        build: (_) => const LibraryBrowser(),
        wrapApp: (app) => _libraryApp(setup())(app),
        verify: (tester, run) async {
          if (bar) await _libraryBarChecks(tester, run, refresh: refresh);
          await verify?.call(tester, run);
        },
      );
      return;
    }
    testResponsive(
      name,
      build: (_) => const LibraryBrowser(),
      wrapApp: (app) => _libraryApp(setup())(app),
      act: act,
      verify: (tester, run) async {
        if (bar) await _libraryBarChecks(tester, run, refresh: refresh);
        await verify?.call(tester, run);
      },
    );
  }

  for (final mode in const ['grid', 'list']) {
    final modeName = mode == 'grid' ? 'רשת' : 'רשימה';
    libraryScene(
      'ספרייה $modeName: רגילה עם טעינה מחדש',
      () => _setup(_smallLibrary(), viewMode: mode, hebrewBooks: true),
      refresh: true,
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.textContaining('תנ', findRichText: true),
          name: 'קטגוריה',
        );
        await expectReachable(tester, run, find.text('ספר 0'), name: 'ספר');
      },
    );
    libraryScene(
      'ספרייה $modeName: גדולה מאוד, קטגוריה עמוקה',
      () => _setup(_bigLibrary(), viewMode: mode),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.textContaining('קטגוריה', findRichText: true),
          name: 'קטגוריה',
        );
      },
    );
    libraryScene(
      'ספרייה $modeName: שמות ארוכים מאוד',
      () => _setup(_longNamesLibrary(), viewMode: mode),
    );
    libraryScene('ספרייה $modeName: תוצאות חיפוש ארוכות', () {
      final library = _bigLibrary();
      return _setup(
        library,
        viewMode: mode,
        searchResults: library.books,
        searchQuery: 'ספר',
      );
    });
    libraryScene(
      'ספרייה $modeName: חיפוש בלי תוצאות',
      () => _setup(
        _smallLibrary(),
        viewMode: mode,
        searchResults: const [],
        searchQuery: 'xyzxyz',
      ),
      verify: (tester, run) async {
        expectVisible(tester, run, find.text('בית'), name: 'כפתור "בית"');
        expectVisible(tester, run, find.text('חזור'), name: 'כפתור "חזור"');
      },
    );
    libraryScene(
      'ספרייה $modeName: חיפוש מתבצע',
      () => _setup(
        _smallLibrary(),
        viewMode: mode,
        searchQuery: 'ספר',
        isSearching: true,
      ),
      animating: true,
    );
    libraryScene(
      'ספרייה $modeName: טעינה',
      () => _setup(_smallLibrary(), viewMode: mode, isLoading: true),
      animating: true,
      // שכבת הטעינה מכסה את הסרגל בכוונה.
      bar: false,
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.text('טוען את הספרייה'),
          name: 'הודעת טעינה',
        );
      },
    );
    libraryScene('ספרייה $modeName: תצוגה מקדימה של קטגוריה', () {
      final library = _smallLibrary();
      return _setup(
        library,
        viewMode: mode,
        showPreview: true,
        previewCategory: library.subCategories.first,
      );
    });
  }

  libraryScene(
    'ספרייה: ריקה (מסך הגדרה)',
    () => _setup(Library(categories: []), isLibraryEmpty: true),
    bar: false,
    verify: (tester, run) async {
      // טקסט הכפתור נשבר לשתי שורות ('\n' במחרוזת) כשהוא רחב מהכפתור, ולכן לא
      // find.text. המסך גולל, ובחלון נמוך הכפתור מגיע אליו בגלילה.
      await expectReachable(
        tester,
        run,
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data?.replaceAll('\n', ' ') == 'בחר מיקום או הורד ספרייה',
        ),
        name: 'כפתור הגדרת הספרייה',
      );
    },
  );
  libraryScene(
    'ספרייה: שגיאת טעינה',
    () => _setup(_smallLibrary(), error: 'שגיאה בקריאת מסד הנתונים ' * 6),
    bar: false,
  );
  libraryScene(
    'ספרייה: שגיאת טעינה, "נסה שוב" טוען את הספרייה מחדש',
    () => _setup(_smallLibrary(), error: 'שגיאה בקריאת מסד הנתונים'),
    bar: false,
    verify: (tester, run) async {
      final retry = find.text('נסה שוב');
      await expectReachable(tester, run, retry, name: 'כפתור נסה שוב');
      final bloc = tester
          .element(find.byType(OtzariaErrorState))
          .read<LibraryBloc>();
      await tester.tap(retry);
      await tester.pump();
      verify(() => bloc.add(const RefreshLibrary())).called(1);
    },
  );
  libraryScene(
    'ספרייה: אין נתוני ספרייה',
    () => (
      library: const LibraryState(),
      viewMode: 'grid',
      showPreview: false,
      isLibraryEmpty: false,
      hebrewBooks: false,
    ),
    bar: false,
  );
  libraryScene(
    'ספרייה: אין נתוני ספרייה, "נסה שוב" טוען את הספרייה מחדש',
    () => (
      library: const LibraryState(),
      viewMode: 'grid',
      showPreview: false,
      isLibraryEmpty: false,
      hebrewBooks: false,
    ),
    bar: false,
    verify: (tester, run) async {
      final retry = find.text('נסה שוב');
      await expectReachable(tester, run, retry, name: 'כפתור נסה שוב');
      final bloc = tester
          .element(find.byType(OtzariaErrorState))
          .read<LibraryBloc>();
      await tester.tap(retry);
      await tester.pump();
      verify(() => bloc.add(const RefreshLibrary())).called(1);
    },
  );

  // ── עדכון אפליקציה באנדרואיד ────────────────────────────────────────────
  final androidStates = <String, AndroidUpdateState>{
    'ממתין': const AndroidUpdateState(),
    'גרסה זמינה': AndroidUpdateState(
      phase: AndroidUpdatePhase.available,
      environment: directEnvironment,
      release: fakeRelease,
    ),
    'הורדה בהתקדמות': AndroidUpdateState(
      phase: AndroidUpdatePhase.downloading,
      environment: directEnvironment,
      release: fakeRelease,
      bytesDownloaded: 3,
      totalBytes: 4,
    ),
    'ממתין ל-WiFi': AndroidUpdateState(
      phase: AndroidUpdatePhase.downloading,
      environment: directEnvironment,
      release: fakeRelease,
      waitingForWifi: true,
    ),
    'מוכן להתקנה': AndroidUpdateState(
      phase: AndroidUpdatePhase.ready,
      environment: directEnvironment,
      release: fakeRelease,
      prepared: fakePrepared,
    ),
    'כשל: חתימה שונה': AndroidUpdateState(
      phase: AndroidUpdatePhase.failed,
      environment: directEnvironment,
      release: fakeRelease,
      failure: AndroidUpdateFailure.signatureMismatch,
    ),
    'כשל: חסרים פרטי אימות': AndroidUpdateState(
      phase: AndroidUpdatePhase.failed,
      environment: directEnvironment,
      failure: AndroidUpdateFailure.metadataMissing,
    ),
    'Play: אין שירות': AndroidUpdateState(
      phase: AndroidUpdatePhase.failed,
      environment: playEnvironment,
      failure: AndroidUpdateFailure.playUnavailable,
    ),
    'מחכה להרשאה': AndroidUpdateState(
      phase: AndroidUpdatePhase.awaitingPermission,
      environment: directEnvironment,
      release: fakeRelease,
    ),
  };

  Widget Function(Widget) androidApp(AndroidUpdateState state) =>
      (app) => BlocProvider<AndroidUpdateBloc>(
        create: (_) {
          final bloc = _MockAndroidUpdateBloc();
          whenListen(
            bloc,
            const Stream<AndroidUpdateState>.empty(),
            initialState: state,
          );
          return bloc;
        },
        child: Builder(
          builder: (context) => AndroidUpdateScope(
            bloc: context.read<AndroidUpdateBloc>(),
            child: app,
          ),
        ),
      );

  for (final entry in androidStates.entries) {
    testResponsiveAnimating(
      'עדכון אנדרואיד, לוח: ${entry.key}',
      build: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AndroidUpdatePanel(bloc: context.read<AndroidUpdateBloc>()),
      ),
      wrapApp: androidApp(entry.value),
      verify: (tester, run) async {
        final scrollable = find.byType(Scrollable).first;
        for (final label in const [
          'המתן',
          'התקן עדכון',
          'הורד עדכון',
          'בדוק עדכונים',
          'בטל הורדה',
          'בדוק שוב',
          'פתח את דף ההורדה',
          'פתח את Google Play',
        ]) {
          if (find.text(label).evaluate().isEmpty) continue;
          await expectReachable(
            tester,
            run,
            find.text(label),
            name: 'כפתור "$label"',
            scrollable: scrollable,
          );
        }
      },
    );
    testResponsiveAnimating(
      'עדכון אנדרואיד, דיאלוג: ${entry.key}',
      build: (context) => Center(
        child: TextButton(
          onPressed: () => showAndroidUpdateDialog(
            context,
            context.read<AndroidUpdateBloc>(),
          ),
          child: const Text('פתח'),
        ),
      ),
      wrapApp: androidApp(entry.value),
      verify: (tester, run) async {
        await tester.tap(find.text('פתח'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
        expectVisible(tester, run, find.text('סגור'), name: 'כפתור "סגור"');
      },
    );
  }

  testResponsiveAnimating(
    'עדכון אנדרואיד: שורת ההגדרות והסמן',
    build: (_) => const SingleChildScrollView(
      child: Column(
        children: [
          AndroidUpdateSettingsTile(),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AndroidUpdateIndicator(),
          ),
        ],
      ),
    ),
    wrapApp: androidApp(androidStates['הורדה בהתקדמות']!),
    verify: (tester, run) async {
      await expectReachable(
        tester,
        run,
        find.text('בדוק ועדכן'),
        name: 'כפתור "בדוק ועדכן"',
        scrollable: find.byType(Scrollable).first,
      );
    },
  );

  // ── מסדים מצורפים ───────────────────────────────────────────────────────
  final longDb =
      'מסד ספרים אישי עם שם ארוך מאוד שממשיך ועוד ממשיך ${'ארוך' * 12}';
  final attachedLibraries = <AttachedLibrary>[
    _attachedLibrary('מסד רגיל', source: _attachedSource),
    _attachedLibrary(longDb, source: _attachedSource),
    _attachedLibrary('שונה מקור', source: _attachedSource, mismatch: true),
    _attachedLibrary('ללא מקור'),
    _attachedLibrary(
      'כונן מנותק',
      status: AttachedLibraryStatus.unreachable,
    ),
    _attachedLibrary(
      'מסד פגום',
      status: AttachedLibraryStatus.invalid,
      problem: AttachedLibraryProblem.notSqlite,
    ),
    _attachedLibrary('מוסתר', hidden: true),
    _attachedLibrary('מועתק', mode: AttachedLibraryMode.copy),
  ];
  final updateStatuses = <String, AttachedUpdateStatus>{
    'C:/dbs/מסד רגיל.db': AttachedUpdateAvailable(_attachedOffer()),
    'C:/dbs/$longDb.db': AttachedUpdateInProgress(
      _attachedOffer(),
      phase: AttachedUpdatePhase.download,
      received: 5 * 1024 * 1024,
      total: 12 * 1024 * 1024,
    ),
    'C:/dbs/שונה מקור.db': const AttachedUpdateFailed(
      AttachedUpdateError.verifyFailed,
    ),
  };

  Widget Function(Widget) attachedApp(
    List<AttachedLibrary> libraries,
    Map<String, AttachedUpdateStatus> statuses,
  ) =>
      (app) => BlocProvider<AttachedLibrariesBloc>(
        create: (_) => AttachedLibrariesBloc(
          addLibraryEvent: (_) {},
          repository: _FakeAttachedRepository(libraries),
          updates: _FakeAttachedUpdates()..notifier.value = statuses,
        ),
        child: app,
      );

  testResponsive(
    'מסדים מצורפים: רשימה ארוכה בכל המצבים',
    build: (_) => const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: AttachedLibrariesPanel(supportsLinking: true),
    ),
    wrapApp: attachedApp(attachedLibraries, updateStatuses),
    verify: (tester, run) async {
      await expectReachable(
        tester,
        run,
        find.text('עדכן').first,
        name: 'כפתור "עדכן"',
        scrollable: find.byType(Scrollable).first,
      );
    },
  );
  testResponsive(
    'מסדים מצורפים: רשימה ריקה',
    build: (_) => const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: AttachedLibrariesPanel(supportsLinking: true),
    ),
    wrapApp: attachedApp(const [], const {}),
  );
  testResponsive(
    'מסדים מצורפים: מובייל בלי קישור, 40 מסדים',
    build: (_) => const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: AttachedLibrariesPanel(supportsLinking: false),
    ),
    wrapApp: attachedApp([
      for (var i = 0; i < 40; i++)
        _attachedLibrary('מסד $i', source: _attachedSource),
    ], const {}),
  );

  // שורת העדכון בכל מצביה.
  final rowStatuses = <String, AttachedUpdateStatus>{
    'בדיקה': const AttachedUpdateIdle(),
    'בודק': const AttachedUpdateChecking(),
    'מעודכן': const AttachedUpdateUpToDate(),
    'זמין': AttachedUpdateAvailable(_attachedOffer()),
    'הורדה': AttachedUpdateInProgress(
      _attachedOffer(),
      phase: AttachedUpdatePhase.download,
      received: 1024 * 1024 * 700,
      total: 1024 * 1024 * 1024 * 3,
    ),
    'WiFi': AttachedUpdateInProgress(
      _attachedOffer(),
      phase: AttachedUpdatePhase.waitingForWifi,
    ),
    'התקנה': AttachedUpdateInProgress(
      _attachedOffer(),
      phase: AttachedUpdatePhase.install,
    ),
    'הותקן': const AttachedUpdateInstalled(7),
    'שגיאה עם הצעה': AttachedUpdateFailed(
      AttachedUpdateError.verifyFailed,
      offer: _attachedOffer(),
    ),
    'אין מקום': const AttachedUpdateFailed(
      AttachedUpdateError.noSpace,
      requiredBytes: 1024 * 1024 * 1024 * 8,
    ),
  };
  for (final entry in rowStatuses.entries) {
    testResponsiveAnimating(
      'שורת עדכון מסד: ${entry.key}',
      build: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: AttachedLibraryUpdateRow(
          status: entry.value,
          onCheck: () {},
          onInstall: (_) {},
          onCancel: () {},
        ),
      ),
      wrapApp: (app) => app,
      verify: (tester, run) async {
        for (final label in const ['בדוק עדכונים', 'עדכן', 'ביטול']) {
          if (find.text(label).evaluate().isEmpty) continue;
          expectVisible(tester, run, find.text(label), name: 'כפתור "$label"');
        }
        expectNoClippedText(tester, run, within: find.byType(Padding).first);
      },
    );
  }

  testResponsive(
    'מסדים מצורפים: דיאלוג אישור עדכון עם הערות ארוכות',
    build: (_) => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => confirmAttachedUpdate(
            context,
            _attachedLibrary(longDb, source: _attachedSource),
            _attachedOffer(notes: List.filled(60, 'שורת הערות ארוכה. ').join()),
          ),
          child: const Text('פתח'),
        ),
      ),
    ),
    act: (tester, run) async {
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    },
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.text('עדכן'), name: 'כפתור "עדכן"');
      expectVisible(tester, run, find.text('ביטול'), name: 'כפתור "ביטול"');
    },
  );

  // ── "מה חדש בספרים" ────────────────────────────────────────────────────
  String changesNotes(int version, int books) {
    final buffer = StringBuffer()
      ..write('# גרסת ספרייה $version\n\n**עדכון א\' חשון תשפ"ז**\n')
      ..write('\n## התווספו הספרים הבאים:\n');
    for (var i = 0; i < books; i++) {
      buffer.write('* ספרות/הלכה/ספר $i\n');
    }
    buffer
      ..write('\n## השתנו הספרים הבאים:\n')
      ..write('* $_longTitle - שינוי מהדורה ל-מהדורה ב (שונה גם מיקומו)\n');
    return buffer.toString();
  }

  for (final (name, notes) in [
    (
      'קטן',
      [
        LibraryChangesNote(
          releaseTag: 'v1',
          markdown: changesNotes(1, 3),
          path: 'v1.md',
        ),
      ],
    ),
    (
      'מאות פריטים בכמה גרסאות',
      [
        for (var v = 0; v < 4; v++)
          LibraryChangesNote(
            releaseTag: 'v$v',
            markdown: changesNotes(v, 150),
            path: 'v$v.md',
          ),
      ],
    ),
    ('ריק', <LibraryChangesNote>[]),
  ]) {
    testResponsive(
      'מה חדש בספרים: $name',
      build: (_) => Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showLibraryChangesDialog(context, notes),
            child: const Text('פתח'),
          ),
        ),
      ),
      act: (tester, run) async {
        await tester.tap(find.text('פתח'));
        await tester.pumpAndSettle();
      },
      verify: (tester, run) async {
        expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
        expectVisible(tester, run, find.text('סגור'), name: 'כפתור "סגור"');
        expectVisible(
          tester,
          run,
          find.byType(TextField),
          name: 'שדה חיפוש ספר ברשימה',
        );
      },
    );
  }
  // ── הגדרת ספרייה (התקנה ראשונית ועדכון מיקום) ───────────────────────────
  final longPath =
      r'C:\Users\Someone\Documents\Otzaria\ספרייה עם נתיב ארוך מאוד\תת תיקייה\עוד תת תיקייה\ספריית אוצריא';
  final setupStates = <String, EmptyLibraryState>{
    'התחלה': const EmptyLibraryInitial(),
    'הורדה חסומה עם סיבה ארוכה': EmptyLibraryInitial(
      downloadDisabledReason: 'ההורדה אינה זמינה כעת. ' * 6,
    ),
    'נתיב נבחר': EmptyLibraryDirectorySelected(selectedPath: longPath),
    'שגיאה': EmptyLibraryError(
      errorMessage: 'לא ניתן לפתוח את התיקייה שנבחרה. ' * 5,
      selectedPath: longPath,
    ),
    'הורדה': const EmptyLibraryDownloading(
      progress: 0.4,
      message: 'מוריד את הספרייה, נשארו כ-12 דקות (3.2GB מתוך 8.0GB)',
      cancellable: true,
    ),
    'חילוץ': EmptyLibraryExtracting(
      selectedPath: longPath,
      progress: 0.7,
      message: 'מחלץ קבצים מהארכיון ומעתיק אותם ליעד, אנא המתן',
      cancellable: true,
    ),
    'טעינה': EmptyLibraryLoading(selectedPath: longPath),
  };
  for (final hasLibrary in const [false, true]) {
    for (final entry in setupStates.entries) {
      testResponsiveAnimating(
        '${hasLibrary ? 'עדכון' : 'הגדרת'} ספרייה, דיאלוג: ${entry.key}',
        build: (_) => Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () {
                debugCreateLibrarySetupBloc = () {
                  final bloc = _MockEmptyLibraryBloc();
                  whenListen(
                    bloc,
                    const Stream<EmptyLibraryState>.empty(),
                    initialState: entry.value,
                  );
                  return bloc;
                };
                showLibrarySetupDialog(
                  context: context,
                  defaultTargetPath: longPath,
                  currentLibraryPath: hasLibrary ? '$longPath/books' : null,
                );
              },
              child: const Text('פתח'),
            ),
          ),
        ),
        wrapApp: (app) => app,
        verify: (tester, run) async {
          addTearDown(() => debugCreateLibrarySetupBloc = null);
          await tester.tap(find.text('פתח'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expectInsideViewport(
            tester,
            run,
            find.byType(Dialog),
            name: 'הדיאלוג',
          );
          final working = entry.value.isLoading;
          if (!working) {
            expectVisible(tester, run, find.text('ביטול'), name: 'ביטול');
            expectVisible(tester, run, find.text('אישור'), name: 'אישור');
          } else if (entry.value is EmptyLibraryExtracting ||
              entry.value is EmptyLibraryDownloading) {
            expectVisible(tester, run, find.text('ביטול'), name: 'ביטול');
          }
        },
      );
    }
  }
  // ── שינוי גודל וצפיפות תוך כדי עבודה ─────────────────────────────────────
  // הערכים שהוזנו (טקסט האיתור) והמיקום (גלילה) נשמרים כשהחלון משתנה, ושדה
  // האיתור והסרגל נשארים נגישים אחרי כל צעד.
  void resizeScene(
    String name,
    String viewMode,
    List<ResponsiveViewport> steps,
  ) {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await loadGoldenFonts();
      final roboto = FontLoader('Roboto')
        ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
      await roboto.load();
    });
    testWidgets('$name [${steps.map((s) => s.label).join(' -> ')}]', (
      tester,
    ) async {
      final wrap = _libraryApp(_setup(_bigLibrary(), viewMode: viewMode));
      Widget build(BuildContext _) => const LibraryBrowser();
      final run = await pumpResponsive(
        tester,
        steps.first,
        build,
        wrapApp: wrap,
      );
      try {
        FocusRepository repo() =>
            tester.element(find.byType(LibraryBrowser)).read<FocusRepository>();
        final original = repo();
        original.librarySearchController.text = 'בראשית';
        await tester.pump();
        double? scrolled;
        if (viewMode == 'grid') {
          final scrollable = find.byType(Scrollable).evaluate().where((e) {
            final s = e.widget as Scrollable;
            if (s.axis != Axis.vertical) return false;
            final position =
                ((e as StatefulElement).state as ScrollableState).position;
            return position.maxScrollExtent > 100;
          });
          if (scrollable.isNotEmpty) {
            final state =
                (scrollable.first as StatefulElement).state as ScrollableState;
            state.position.jumpTo(
              state.position.maxScrollExtent / 2,
            );
            await tester.pump();
            scrolled = state.position.pixels;
          }
        }
        for (final step in steps.skip(1)) {
          tester.view.physicalSize = step.size;
          tester.platformDispatcher.textScaleFactorTestValue = step.textScale;
          DeviceChrome.debugMobileOverride = step.touch;
          final before = run.issues.length;
          await tester.pumpWidget(
            buildResponsiveApp(step, build, wrapApp: wrap),
          );
          await tester.pumpAndSettle();
          for (var i = before; i < run.issues.length; i++) {
            run.issues[i] = ResponsiveIssue(
              run.issues[i].kind,
              '[${step.label}] ${run.issues[i].detail}',
            );
          }
          final now = repo();
          if (!identical(now, original) ||
              now.librarySearchController.text != 'בראשית') {
            run.add(
              ResponsiveIssue(
                'state-lost',
                'טקסט האיתור אבד ב-${step.label}: '
                    '"${now.librarySearchController.text}"',
              ),
            );
          }
          if (scrolled != null) {
            final positions = find
                .byType(Scrollable)
                .evaluate()
                .map(
                  (e) => ((e as StatefulElement).state as ScrollableState)
                      .position,
                )
                .where((p) => p.axis == Axis.vertical);
            if (positions.every((p) => p.pixels < 1)) {
              run.add(
                ResponsiveIssue(
                  'state-lost',
                  'מיקום הגלילה אופס ב-${step.label} (היה $scrolled)',
                ),
              );
            }
          }
          final stepRun = ResponsiveRun(step);
          await _libraryBarChecks(tester, stepRun);
          run.issues.addAll(stepRun.issues);
        }
        run.release();
        run.expectClean();
      } finally {
        run.release();
      }
    });
  }

  for (final mode in const ['grid', 'list']) {
    resizeScene('ספרייה $mode: שינוי גודל חלון', mode, const [
      ResponsiveViewport(1280, 800),
      ResponsiveViewport(320, 640, touch: true),
      ResponsiveViewport(800, 500),
      ResponsiveViewport(1280, 800),
    ]);
    resizeScene('ספרייה $mode: הגדלת טקסט בחלון צר', mode, const [
      ResponsiveViewport(320, 640),
      ResponsiveViewport(320, 640, textScale: 1.3),
      ResponsiveViewport(320, 640, textScale: 1.5),
      ResponsiveViewport(320, 640, textScale: 2.0),
      ResponsiveViewport(320, 640),
    ]);
    resizeScene('ספרייה $mode: מעבר צפיפות', mode, const [
      ResponsiveViewport(360, 640),
      ResponsiveViewport(360, 640, compact: true),
      ResponsiveViewport(1280, 800, compact: true),
      ResponsiveViewport(1280, 800),
    ]);
  }
  // ── דיאלוגים ולוחות של הספרייה ──────────────────────────────────────────
  testResponsive(
    'פרטי קטגוריה: שם ותיאור ארוכים',
    build: (_) => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showCategoryDetailsDialog(
            context,
            Category(
              title: _longTitle,
              description: List.filled(40, 'תיאור מורחב ארוך מאוד. ').join(),
              shortDescription: 'תיאור קצר של הקטגוריה. ' * 4,
              order: 0,
              subCategories: [],
              books: [],
              parent: null,
            ),
          ),
          child: const Text('פתח'),
        ),
      ),
    ),
    act: (tester, run) async {
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    },
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.text('סגור'), name: 'כפתור "סגור"');
    },
  );

  testResponsive(
    'גרסאות ספר: רשימה ארוכה והסבר',
    build: (_) => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () {
            bookVersionsListProbeForTesting = (_) async => [
              for (var i = 0; i < 25; i++)
                BookVersionInfo(
                  versionTitle: 'Version $i',
                  heVersionTitle: 'מהדורה $i - $_longTitle',
                  versionNotes: 'הערות על המהדורה. ' * 6,
                  hasContent: i.isEven,
                ),
            ];
            showBookVersionsDialog(
              context,
              TextBook(title: _longTitle),
              hint: 'בחירת מהדורה פותחת את הספר בנוסח שלה. ' * 3,
            );
          },
          child: const Text('פתח'),
        ),
      ),
    ),
    act: (tester, run) async {
      addTearDown(() => bookVersionsListProbeForTesting = null);
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    },
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.text('סגור'), name: 'כפתור "סגור"');
    },
  );

  for (final (name, subs, books) in [
    ('ריק', 0, 0),
    ('עשרות פריטים ושמות ארוכים', 12, 60),
  ]) {
    testResponsive(
      'תצוגה מקדימה של תיקייה: $name',
      build: (_) {
        final category = Category(
          title: _longTitle,
          description: 'תיאור התיקייה. ' * 12,
          shortDescription: '',
          order: 0,
          subCategories: [],
          books: [],
          parent: null,
        );
        return CategoryPreviewPanel(
          category: category,
          parentPath: 'תנ״ך, ראשונים, ' * 6,
          subCategories: [
            for (var i = 0; i < subs; i++)
              _category('$_longTitle $i', category, books: [_book('ספר')]),
          ],
          books: [for (var i = 0; i < books; i++) _book('$_longTitle $i')],
          onOpen: () {},
          onOpenSubCategory: (_) {},
        );
      },
      verify: (tester, run) async {
        expectVisible(tester, run, find.text('פתח תיקייה'), name: 'פתח תיקייה');
      },
    );
  }

  // ── תאריך ודף יומי בשורה השנייה של סרגל הספרייה ───────────────────────────
  testResponsive(
    'תאריך ודף יומי: היום הארוך בשנה בחלון צר',
    viewports: const [
      ResponsiveViewport(320, 640, touch: true),
      ResponsiveViewport(320, 640, touch: true, textScale: 1.3),
      ResponsiveViewport(320, 640, touch: true, textScale: 1.5),
      ResponsiveViewport(320, 640, touch: true, textScale: 2.0),
      ResponsiveViewport(360, 640, touch: true, textScale: 1.5),
      ResponsiveViewport(390, 844, touch: true, textScale: 2.0),
    ],
    build: (_) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Center(
        child: LibraryDafYomi(onDafYomiTap: (tractate, daf) {}),
      ),
    ),
    wrapApp: (app) => BlocProvider<CalendarCubit>(
      create: (_) => _StubCalendarCubit(
        CalendarState.initial().copyWith(todayGregorianDate: _longestDafDay),
      ),
      child: app,
    ),
    verify: (tester, run) async {
      expectVisible(tester, run, find.byType(LibraryDafYomi), name: 'דף יומי');
    },
  );

  // ── אזהרת אינדקס ────────────────────────────────────────────────────────
  for (final mode in IndexingWarningMode.values) {
    testResponsive(
      'אזהרת אינדקס: ${mode.name}',
      build: (_) => Padding(
        padding: const EdgeInsets.all(8),
        child: IndexingWarning(mode: mode, onDismiss: () {}),
      ),
      verify: (tester, run) async {
        expectNoClippedText(tester, run, within: find.byType(IndexingWarning));
        if (mode == IndexingWarningMode.inProgress) {
          expectVisible(
            tester,
            run,
            find.byTooltip('סגור'),
            name: 'סגירת האזהרה',
          );
        }
      },
    );
  }
  // ── אינדקס קישורים חיצוניים (הגדרות הספרייה) ─────────────────────────────
  final linkStates = <String, void Function(_FakeLinks)>{
    'מעודכן': (_) {},
    'בנייה': (l) => l.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1520000, total: 2167384),
    },
    'מושהה': (l) {
      l.buildProgress.value = const {
        'dbA': ExternalLinkBuildProgress(done: 1520000, total: 2167384),
      };
      l.buildPaused.value = true;
    },
    'לא הושלם': (l) => l.incompleteSlugs.value = {'dbA'},
    'יותר מדי שורות': (l) => l.tooLargeSlugs.value = {'dbA'},
  };
  for (final entry in linkStates.entries) {
    final links = _FakeLinks()..let(entry.value);
    testResponsive(
      'אינדקס קישורים: ${entry.key}',
      build: (_) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ExternalLinkIndexTile(
          slugs: const ['dbA'],
          links: links,
        ),
      ),
      verify: (tester, run) async {
        for (final label in const [
          'המשך',
          'עצור',
          'המשך בנייה',
          'בנה מחדש',
          'איפוס',
        ]) {
          if (find.text(label).evaluate().isEmpty) continue;
          await expectReachable(
            tester,
            run,
            find.text(label),
            name: 'כפתור "$label"',
            scrollable: find.byType(Scrollable).first,
          );
        }
      },
    );
  }

  // ── עדכון התוכנה: שבב וחלון (Windows, Linux, macOS) ──────────────────────
  for (final status in const [
    UpdatStatus.available,
    UpdatStatus.downloading,
    UpdatStatus.readyToInstall,
  ]) {
    testResponsiveAnimating(
      'עדכון תוכנה, שבב: ${status.name}',
      build: (context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: hebrewFlatChip(
          context: context,
          latestVersion: '0.9.99.12',
          appVersion: '0.9.98',
          status: status,
          checkForUpdate: () {},
          openDialog: () {},
          startUpdate: () {},
          launchInstaller: () async {},
          dismissUpdate: () {},
        ),
      ),
      wrapApp: (app) => app,
      verify: (tester, run) async {
        expectVisible(tester, run, find.byType(StatusChip), name: 'השבב');
      },
    );
  }

  testResponsive(
    'עדכון תוכנה, חלון: יומן שינויים ארוך',
    build: (_) => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => hebrewDefaultDialog(
            context: context,
            latestVersion: '0.9.99.12',
            appVersion: '0.9.98',
            status: UpdatStatus.availableWithChangelog,
            changelog: [
              '## מה חדש',
              for (var i = 0; i < 40; i++)
                '* שינוי מספר $i עם תיאור ארוך שממשיך ועוד ממשיך וכולל ${'מילים ' * 8}',
            ].join('\n'),
            checkForUpdate: () {},
            openDialog: () {},
            startUpdate: () {},
            launchInstaller: () async {},
            dismissUpdate: () {},
          ),
          child: const Text('פתח'),
        ),
      ),
    ),
    act: (tester, run) async {
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    },
    verify: (tester, run) async {
      expectInsideViewport(tester, run, find.byType(Dialog), name: 'הדיאלוג');
      expectVisible(tester, run, find.text('עדכן כעת'), name: 'עדכן כעת');
      expectVisible(tester, run, find.text('מאוחר יותר'), name: 'מאוחר יותר');
    },
  );
}

// ── עזרים של המסדים המצורפים ──────────────────────────────────────────────

const _attachedSource = AttachedLibraryUpdateSource(
  libraryId: 'lib-a',
  manifestUrl: 'https://updates.example.org/a/manifest.json',
  publicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
);

class _FakeAttachedRepository extends AttachedLibrariesRepository {
  _FakeAttachedRepository(this.items) : super(copyByDefault: false);

  final List<AttachedLibrary> items;

  @override
  List<AttachedLibrary> get libraries => items;

  @override
  List<String> get folders => const [r'D:\מסדים\תיקייה עם שם ארוך מאוד'];

  @override
  Stream<Set<String>> get changes => const Stream.empty();
}

class _FakeAttachedUpdates extends AttachedLibraryUpdateService {
  final notifier = ValueNotifier<Map<String, AttachedUpdateStatus>>({});

  @override
  ValueListenable<Map<String, AttachedUpdateStatus>> get statuses => notifier;

  @override
  AttachedUpdateStatus statusOf(AttachedLibrary library) =>
      notifier.value[library.path] ?? const AttachedUpdateIdle();

  @override
  Future<void> restorePending() async {}
}

AttachedLibrary _attachedLibrary(
  String name, {
  AttachedLibraryUpdateSource? source,
  bool mismatch = false,
  AttachedLibraryMode mode = AttachedLibraryMode.link,
  AttachedLibraryStatus status = AttachedLibraryStatus.ok,
  AttachedLibraryProblem? problem,
  bool hidden = false,
}) => AttachedLibrary(
  slug: name,
  displayName: name,
  path: 'C:/dbs/$name.db',
  mode: mode,
  status: status,
  problem: problem,
  hidden: hidden,
  bookCount: 12345,
  capabilities: AttachedLibraryCapability.values.toSet(),
  addedAt: DateTime(2026),
  updateSource: source,
  updateSourceMismatch: mismatch,
  fingerprint: const AttachedLibraryFingerprint(
    size: 1,
    modifiedMs: 1,
    dbVersion: '1',
  ),
);

AttachedUpdateOffer _attachedOffer({String notes = 'הערות שחרור'}) =>
    AttachedUpdateOffer(
      manifest: AttachedUpdateManifest(
        libraryId: 'lib-a',
        dbVersion: 2,
        releaseNotes: notes,
        full: const AttachedUpdateArtifact(
          compression: AttachedUpdateCompression.zstd,
          size: 3 * 1024 * 1024,
          sha256: '',
          parts: [
            AttachedUpdatePart(
              url: 'https://a.example.net/p1',
              size: 1024 * 1024,
              sha256: '',
            ),
          ],
        ),
      ),
      manifestBytes: Uint8List(0),
      signature: Uint8List(0),
      domain: 'updates.example.org',
    );

class _MockEmptyLibraryBloc
    extends MockBloc<EmptyLibraryEvent, EmptyLibraryState>
    implements EmptyLibraryBloc {}

class _FakeLinks extends ExternalLinkRepository {
  void let(void Function(_FakeLinks) configure) => configure(this);

  @override
  void cancelBuild() {}

  @override
  void resumeBuild() {}

  @override
  void requestResume(String slug) {}

  @override
  void requestRebuild(String slug) {}
}
