// Responsive: כלים אישיים (לוח שנה והדפסת לוח, הדפסה, שמור וזכור, הערות
// אישיות, סימניות, היסטוריה, שולחנות עבודה, סיור, סטטוס עבודה, דיווחים) מול
// מטריצת החלונות. כל מסך נבנה עם ה-stubs וה-fakes הקיימים.

import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/app_report/view/crash_prompt_dialog.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/view/tour_overlay_screen.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/work_status/work_status_overlay.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/view/personal_notes_screen.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/error_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/screens/shamor_zachor_main_screen.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/completion_animation_overlay.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_event_dialog.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_print_dialog.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../test_helpers/memory_cache_provider.dart';
import '../../app_report/app_report_test_fakes.dart';
import '../../support/golden_fonts.dart' show goldenPlatform;
import '../../tools/calendar/support/calendar_cubit_fakes.dart';
import 'responsive_harness.dart';

/// מחליף את העץ ב-SizedBox: סוגר את ה-cubit והטיימרים שלו לפני סוף הבדיקה.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// כמו [testResponsive]. [settle] false למצבי טעינה: הספינר מונפש לנצח, ו-
/// `pumpAndSettle` לא היה מסתיים. הם רצים על אותה מטריצה, בלי רישום הכשלים
/// ל-RESPONSIVE_REPORT.
void _scene(
  String description, {
  required Widget Function(BuildContext context) build,
  Widget Function(Widget app)? wrapApp,
  bool scaffold = true,
  ResponsiveAct? act,
  ResponsiveAct? verify,
  bool settle = true,
}) {
  if (settle) {
    testResponsive(
      description,
      build: build,
      wrapApp: wrapApp,
      scaffold: scaffold,
      act: act,
      verify: verify,
    );
    return;
  }
  for (final viewport in viewportsFor(activeTier)) {
    testWidgets(
      '$description @ ${viewport.label}',
      (tester) async {
        final run = await pumpResponsive(
          tester,
          viewport,
          build,
          wrapApp: wrapApp,
          scaffold: scaffold,
          settle: false,
        );
        try {
          await tester.pump(const Duration(milliseconds: 300));
          if (act != null) await act(tester, run);
          if (verify != null) await verify(tester, run);
          expectNoHorizontalScroll(tester, run);
          run.release();
          run.expectClean();
        } on Object {
          run.release();
          rethrow;
        }
      },
      variant: TargetPlatformVariant.only(
        viewport.touch ? TargetPlatform.android : goldenPlatform,
      ),
    );
  }
}

/// פותח את הדיאלוג בלי להמתין לסיום אנימציות (מצבי טעינה).
Future<void> _openNoSettle(WidgetTester tester) async {
  await tester.tap(find.text('פתח'));
  await tester.pump(const Duration(milliseconds: 400));
}
// ─── לוח שנה ───────────────────────────────────────────────────────────────

CalendarCubit? _calendarCubit;

Widget _calendarProviders(Widget app) {
  final settingsBloc = SettingsBloc(repository: SettingsRepository())
    ..add(LoadSettings());
  final cubit = CalendarCubit(
    notificationService: FakeNotificationService(),
    googleCalendarService: FakeGoogleCalendarService(),
  );
  _calendarCubit = cubit;
  return MultiBlocProvider(
    providers: [
      BlocProvider.value(value: settingsBloc),
      BlocProvider.value(value: cubit),
    ],
    child: app,
  );
}

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip).first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() async {
    final cubit = _calendarCubit;
    _calendarCubit = null;
    if (cubit != null && !cubit.isClosed) await cubit.close();
  });

  group('לוח שנה', () {
    for (final view in CalendarView.values) {
      _scene(
        'לוח שנה, תצוגת ${view.name}',
        wrapApp: _calendarProviders,
        build: (_) => const CalendarWidget(),
        act: (tester, run) async {
          _calendarCubit!.changeCalendarView(view);
          await tester.pumpAndSettle();
        },
        verify: (tester, run) async {
          // כל פעולות הסרגל נשארות גלויות ונגישות, בכל רוחב: אחרת הן נדחפות
          // לשורה שמתחת לגובה הסרגל ונסתרות מאחורי שורת התאריך.
          for (final tooltip in const [
            'הדפסה',
            'הגדרות לוח שנה',
            'אירועים',
            'זמנים',
            'קודם',
            'הבא',
            'מעבר לתאריך',
          ]) {
            expectVisible(
              tester,
              run,
              find.byTooltip(tooltip),
              name: 'כפתור "$tooltip"',
            );
          }
          expectVisible(tester, run, find.text('היום'), name: 'כפתור "היום"');
          expectVisible(tester, run, find.text('חודש'), name: 'מעבר לחודש');
          expectVisible(tester, run, find.text('שבוע'), name: 'מעבר לשבוע');
          await _unmount(tester);
        },
      );
    }

    _scene(
      'לוח שנה, קפיצה לתאריך',
      wrapApp: _calendarProviders,
      build: (_) => const CalendarWidget(),
      act: (tester, run) => _tapTooltip(tester, 'מעבר לתאריך'),
      verify: (tester, run) async {
        expectInsideViewport(
          tester,
          run,
          find.text('מעבר לתאריך'),
          name: 'כותרת הקפיצה לתאריך',
        );
        await _unmount(tester);
      },
    );

    _scene(
      'לוח שנה, הגדרות',
      wrapApp: _calendarProviders,
      build: (_) => const CalendarWidget(),
      act: (tester, run) => _tapTooltip(tester, 'הגדרות לוח שנה'),
      verify: (tester, run) async {
        expectVisible(
          tester,
          run,
          find.byTooltip('הגדרות לוח שנה'),
          name: 'כפתור הגדרות',
        );
        await _unmount(tester);
      },
    );

    _scene(
      'לוח שנה, פאנל אירועים וזמנים',
      wrapApp: _calendarProviders,
      build: (_) => const CalendarWidget(),
      act: (tester, run) async {
        await _tapTooltip(tester, 'אירועים');
        await _tapTooltip(tester, 'זמנים');
      },
      verify: (tester, run) => _unmount(tester),
    );

    _scene(
      'דיאלוג אירוע חדש',
      wrapApp: _calendarProviders,
      build: (context) => Center(
        child: TextButton(
          onPressed: () => showCalendarEventDialog(
            context: context,
            state: context.read<CalendarCubit>().state,
          ),
          child: const Text('פתח'),
        ),
      ),
      act: (tester, run) async {
        await tester.tap(find.text('פתח'));
        await tester.pumpAndSettle();
      },
      verify: (tester, run) async {
        expectInsideViewport(
          tester,
          run,
          find.byType(CalendarEventDialog),
          name: 'דיאלוג האירוע',
        );
        await _unmount(tester);
      },
    );

    for (final view in CalendarView.values) {
      _scene(
        'דיאלוג הדפסת לוח, ${view.name}',
        build: (context) => Center(
          child: TextButton(
            onPressed: () =>
                showCalendarPrintDialog(context: context, calendarView: view),
            child: const Text('פתח'),
          ),
        ),
        act: (tester, run) async {
          await tester.tap(find.text('פתח'));
          await tester.pumpAndSettle();
        },
        verify: (tester, run) async {
          expectInsideViewport(
            tester,
            run,
            find.byType(CalendarPrintDialog),
            name: 'דיאלוג ההדפסה',
          );
        },
      );
    }
  });

  _bookmarksScenes();
  _historyScenes();
  _workspaceScenes();
  _personalNotesScenes();
  _reportScenes();
  _workStatusScenes();
  _tourScenes();
  _shamorZachorScenes();
  _printingScenes();
}

// ─── עזרים משותפים ─────────────────────────────────────────────────────────

const _longTitle =
    'שו"ת רבי עקיבא איגר החדשות עם הוספות והערות מאת בנו ותלמידיו וקובץ מכתבים '
    'שנדפס לראשונה, מהדורה מבוארת ומנוקדת, כרך שלישי';

/// כפתור שפותח את הדיאלוג ([open]) ואז מוודא שהוא בתוך החלון.
Widget _opener(Future<Object?> Function(BuildContext context) open) => Builder(
  builder: (context) => Center(
    child: TextButton(
      onPressed: () => open(context),
      child: const Text('פתח'),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

/// משנה את גודל החלון בזמן שהדיאלוג פתוח: הוא נשאר בתוך החלון החדש.
Future<void> _resizeTo(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump(const Duration(milliseconds: 300));
}

class _StubTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _StubTabsBloc() : super(const TabsState(tabs: [], currentTabIndex: 0));

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _StubNavigationBloc()
    : super(const NavigationState(currentScreen: Screen.reading));

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget Function(Widget) _navProviders(List<BlocProvider> extra) =>
    (app) => MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>(create: (_) => _StubTabsBloc()),
        BlocProvider<NavigationBloc>(create: (_) => _StubNavigationBloc()),
        ...extra,
      ],
      child: app,
    );

// ─── סימניות ───────────────────────────────────────────────────────────────

class _StubBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _StubBookmarkBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Bookmark _bookmark(int i, {String? title}) => Bookmark(
  ref: '${title ?? 'ספר $i'} פרק ${i % 40 + 1}',
  book: TextBook(title: title ?? 'ספר $i', filePath: '/fake/$i.txt'),
  index: i,
);

void _bookmarksScenes() {
  final scenarios = <String, List<Bookmark>>{
    'ריק': const [],
    'שם ארוך': [_bookmark(1, title: _longTitle), _bookmark(2)],
    'מאות פריטים': [for (var i = 0; i < 300; i++) _bookmark(i)],
  };
  scenarios.forEach((name, bookmarks) {
    _scene(
      'סימניות, $name',
      wrapApp: _navProviders([
        BlocProvider<BookmarkBloc>(
          create: (_) => _StubBookmarkBloc(BookmarkState(bookmarks: bookmarks)),
        ),
      ]),
      build: (_) => _opener(
        (context) => showDialog<void>(
          context: context,
          builder: (_) => const BookmarksDialog(),
        ),
      ),
      act: (tester, run) => _open(tester),
      verify: (tester, run) async {
        expectInsideViewport(
          tester,
          run,
          find.byType(BookmarksDialog),
          name: 'דיאלוג סימניות',
        );
        if (bookmarks.isNotEmpty) {
          await expectReachable(
            tester,
            run,
            find.byTooltip('מחק').first,
            name: 'מחיקת סימניה',
            scrollable: find.byType(Scrollable).first,
          );
        }
        await _resizeTo(tester, const Size(320, 400));
        expectInsideViewport(
          tester,
          run,
          find.byType(BookmarksDialog),
          name: 'דיאלוג סימניות אחרי הקטנת החלון',
        );
      },
    );
  });
}

// ─── היסטוריה ──────────────────────────────────────────────────────────────

class _StubHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _StubHistoryBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _historyScenes() {
  final scenarios = <String, HistoryState>{
    'ריק': HistoryLoaded(const []),
    'טעינה': HistoryLoading(const []),
    'שגיאה': HistoryError(const [], 'לא ניתן לקרוא את ההיסטוריה'),
    'שם ארוך': HistoryLoaded([_bookmark(1, title: _longTitle), _bookmark(2)]),
    'מאות פריטים': HistoryLoaded([for (var i = 0; i < 300; i++) _bookmark(i)]),
  };
  scenarios.forEach((name, state) {
    _scene(
      'היסטוריה, $name',
      settle: name != 'טעינה',
      wrapApp: _navProviders([
        BlocProvider<HistoryBloc>(create: (_) => _StubHistoryBloc(state)),
      ]),
      build: (_) => _opener(
        (context) => showDialog<void>(
          context: context,
          builder: (_) => const HistoryDialog(),
        ),
      ),
      act: (tester, run) =>
          name == 'טעינה' ? _openNoSettle(tester) : _open(tester),
      verify: (tester, run) async {
        expectInsideViewport(
          tester,
          run,
          find.byType(HistoryDialog),
          name: 'דיאלוג היסטוריה',
        );
      },
    );
  });
}

// ─── שולחנות עבודה ─────────────────────────────────────────────────────────

class _StubWorkspaceBloc extends Cubit<WorkspaceState>
    implements WorkspaceBloc {
  _StubWorkspaceBloc(super.initialState);

  @override
  void add(WorkspaceEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _workspaceScenes() {
  WorkspaceState stateOf(List<String> names, {bool loading = false}) {
    final workspaces = [
      for (final name in names) Workspace(name: name, tabs: const []),
    ];
    return WorkspaceState(
      workspaces: workspaces,
      isLoading: loading,
      activeWorkspaceId: workspaces.isEmpty ? null : workspaces.first.id,
    );
  }

  final scenarios = <String, WorkspaceState>{
    'ריק': stateOf(const []),
    'טעינה': stateOf(const [], loading: true),
    'שם ארוך': stateOf([_longTitle, 'שולחן ב']),
    'מאות פריטים': stateOf([for (var i = 0; i < 200; i++) 'שולחן $i']),
  };
  scenarios.forEach((name, state) {
    _scene(
      'שולחנות עבודה, $name',
      settle: name != 'טעינה',
      wrapApp: _navProviders([
        BlocProvider<WorkspaceBloc>(create: (_) => _StubWorkspaceBloc(state)),
      ]),
      build: (_) => _opener(
        (context) => showDialog<void>(
          context: context,
          builder: (_) => const WorkspaceSwitcherDialog(),
        ),
      ),
      act: (tester, run) =>
          name == 'טעינה' ? _openNoSettle(tester) : _open(tester),
      verify: (tester, run) async {
        expectInsideViewport(
          tester,
          run,
          find.byType(WorkspaceSwitcherDialog),
          name: 'דיאלוג שולחנות עבודה',
        );
        await _resizeTo(tester, const Size(320, 400));
        expectInsideViewport(
          tester,
          run,
          find.byType(WorkspaceSwitcherDialog),
          name: 'דיאלוג שולחנות עבודה אחרי הקטנת החלון',
        );
      },
    );
  });
}

// ─── הערות אישיות ──────────────────────────────────────────────────────────

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _FakeNotesRepository extends PersonalNotesRepository {
  _FakeNotesRepository(this.notesByBook);

  final Map<String, List<PersonalNote>> notesByBook;

  @override
  Future<List<BookNotesInfo>> listBooksWithNotes() async => [
    for (final entry in notesByBook.entries)
      BookNotesInfo(
        bookId: entry.key,
        noteCount: entry.value.length,
        lastUpdated: DateTime(2025, 1, 2),
      ),
  ];

  @override
  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async => notesByBook[bookId] ?? const [];
}

PersonalNote _note(String bookId, int i, {String? body}) {
  final text = body ?? 'תוכן הערה מספר $i';
  return PersonalNote(
    id: 'note-$bookId-$i',
    bookId: bookId,
    lineNumber: i,
    displayTitle: 'כותרת $i',
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: jsonEncode([
      {'insert': '$text\n'},
    ]),
    contentPlain: text,
    contentFormat: PersonalNoteContentFormat.quillDelta,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 2),
  );
}

/// ספק את מסך ההערות: מאגר מזויף, ספרייה ריקה וכל ה-blocs שהוא קורא.
Widget Function(Widget) _notesProviders(
  PersonalNotesRepository Function() makeRepository,
) => (app) {
  final libraryBloc = _MockLibraryBloc();
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(
      library: Library(categories: []),
      isLoading: false,
      currentCategory: null,
    ),
  );
  return MultiBlocProvider(
    providers: [
      RepositoryProvider<SettingsRepository>(
        create: (_) => SettingsRepository(),
      ),
      BlocProvider<SettingsBloc>(
        create: (context) =>
            SettingsBloc(repository: context.read<SettingsRepository>()),
      ),
      BlocProvider<LibraryBloc>.value(value: libraryBloc),
      BlocProvider<PersonalNotesBloc>(
        create: (_) => PersonalNotesBloc(repository: makeRepository()),
      ),
    ],
    child: app,
  );
};

void _personalNotesScenes() {
  final longBody = List.filled(
    12,
    'הערה ארוכה מאוד שחוזרת על עצמה כדי לבדוק גלישת שורות בכרטיס צר ',
  ).join();
  final scenarios = <String, Map<String, List<PersonalNote>>>{
    'מצב ריק': {},
    'שם ספר והערה ארוכים': {
      _longTitle: [_note(_longTitle, 1, body: longBody), _note(_longTitle, 2)],
    },
    'מאות הערות': {
      'ספר עמוס': [for (var i = 0; i < 300; i++) _note('ספר עמוס', i)],
    },
  };
  scenarios.forEach((name, notes) {
    _scene(
      'מסך הערות אישיות, $name',
      scaffold: false,
      wrapApp: _notesProviders(() => _FakeNotesRepository(notes)),
      build: (_) => Scaffold(
        body: PersonalNotesManagerScreen(
          repository: _FakeNotesRepository(notes),
        ),
      ),
      verify: (tester, run) async {
        // "חפש בהערות..." הוא placeholder של שדה החיפוש: קיצור שלו בשדה צר מכוון.
        expectNoClippedText(
          tester,
          run,
          within: find.byType(Scaffold),
          ignoreLabels: const {'חפש בהערות...'},
        );
      },
    );
  });

  _scene(
    'עורך הערה, מקלדת וירטואלית וטקסט ארוך',
    wrapApp: _notesProviders(() => _FakeNotesRepository(const {})),
    build: (_) => _opener(
      (context) => showDialog<void>(
        context: context,
        builder: (_) => PersonalNoteEditorDialog(
          title: 'עריכת הערה עם כותרת ארוכה במיוחד מתוך הספר',
          referenceText: List.filled(
            40,
            'טקסט ארוך מן הספר עם הקשר להערה.',
          ).join(' '),
          initialContent: List.filled(50, 'שורת הערה לעריכה').join('\n'),
        ),
      ),
    ),
    act: (tester, run) async {
      await _open(tester);
      // מקלדת וירטואלית: שליש מהחלון (עד 300), כמו במכשיר.
      final height = run.viewport.height;
      tester.view.viewInsets = FakeViewPadding(
        bottom: height < 700 ? height / 3 : 300,
      );
      await tester.pumpAndSettle();
    },
    verify: (tester, run) async {
      expectInsideViewport(
        tester,
        run,
        find.byType(PersonalNoteEditorDialog),
        name: 'דיאלוג העורך',
      );
      expectVisible(
        tester,
        run,
        find.widgetWithText(ActionButton, 'שמור'),
        name: 'כפתור שמירה',
      );
    },
  );
}

// ─── דיווחים ───────────────────────────────────────────────────────────────

void _reportScenes() {
  AppReportBloc newBloc({
    AppReportTrigger trigger = AppReportTrigger.manual,
    String initialTitle = '',
    String details = '',
    CrashSignature? signature,
  }) => AppReportBloc(
    trigger: trigger,
    initialTitle: initialTitle,
    details: details,
    signature: signature,
    service: FakeAppReportService(),
    collector: FakeAppReportCollector(),
    redactor: AppReportRedactor(environment: const {}),
    appVersion: '0.9.98',
  );

  final longText = List.filled(
    10,
    'תיאור ארוך מאוד של התקלה, כולל נתיב C:\\Users\\Someone\\Documents\\Otzaria\\ספרים\\ספר ארוך.pdf ',
  ).join();

  for (final (name, bloc) in <(String, AppReportBloc Function())>[
    ('טופס ריק', () => newBloc()),
    (
      'כותרת ותיאור ארוכים',
      () => newBloc(initialTitle: longText, details: longText),
    ),
  ]) {
    _scene(
      'דיווח על תקלה, $name',
      build: (_) =>
          _opener((context) => showAppReportDialog(context, createBloc: bloc)),
      act: (tester, run) async {
        await tester.tap(find.text('פתח'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      },
      verify: (tester, run) async {
        expectInsideViewport(
          tester,
          run,
          find.byType(AppReportDialog),
          name: 'דיאלוג הדיווח',
        );
        await expectReachable(
          tester,
          run,
          find.byKey(const ValueKey('app-report-send')),
          name: 'כפתור שליחה',
          scrollable: find.byType(Scrollable).first,
        );
      },
    );
  }

  _scene(
    'הצעת דיווח על קריסה',
    build: (_) => _opener(
      (context) => showCrashPromptDialog(
        context,
        candidate: CrashCandidate(
          previousSession: SessionLock(
            pid: 1,
            version: '0.9.97',
            startedAt: DateTime.utc(2026, 9, 16),
          ),
          entries: const [],
          signature: const CrashSignature(
            exceptionType: 'StateError',
            frames: ['main.dart'],
          ),
          hasStartupStall: false,
          hasMinidump: false,
        ),
        createBloc: () => newBloc(trigger: AppReportTrigger.crashPrompt),
        saveMode: (_) async {},
      ),
    ),
    act: (tester, run) async {
      await tester.tap(find.text('פתח'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    },
    verify: (tester, run) async {
      expectInsideViewport(
        tester,
        run,
        find.byType(CrashPromptDialog),
        name: 'דיאלוג הקריסה',
      );
      expectVisible(
        tester,
        run,
        find.byKey(const ValueKey('crash-prompt-send')),
        name: 'כפתור שליחה',
      );
    },
  );
}

// ─── סטטוס עבודה ───────────────────────────────────────────────────────────

void _workStatusScenes() {
  final scenarios = <String, List<WorkStatusItem>>{
    'פריט יחיד עם כפתורים': [
      WorkStatusItem(
        id: 'indexing',
        title: 'אינדוקס ספרים',
        message: 'התוכנה בתהליך אינדוקס, ייתכנו האטות בחיפוש',
        detail: 'התקדמות: 133/1633',
        progress: 0.08,
        actions: [
          WorkStatusAction(
            label: 'השהה',
            icon: FluentIcons.pause_24_regular,
            onPressed: () {},
          ),
          WorkStatusAction(
            label: 'מצב חסכוני',
            icon: FluentIcons.leaf_one_24_regular,
            onPressed: () {},
          ),
          WorkStatusAction(
            label: 'ביטול',
            icon: FluentIcons.dismiss_24_regular,
            onPressed: () {},
          ),
        ],
      ),
    ],
    'כותרת והודעה ארוכות': [
      WorkStatusItem(
        id: 'long',
        title: _longTitle,
        message: List.filled(6, _longTitle).join(' '),
        detail: 'התקדמות: 1,500,000/2,167,384',
        progress: 0.69,
      ),
    ],
    'כשל': [
      const WorkStatusItem(
        id: 'failed',
        title: 'אינדוקס נכשל',
        message: 'לא ניתן לכתוב לתיקיית האינדקס',
        kind: WorkStatusKind.failed,
      ),
    ],
    'עשר עבודות': [
      for (var i = 0; i < 10; i++)
        WorkStatusItem(
          id: 'job$i',
          title: 'עבודה $i',
          message: 'הודעה על עבודה מספר $i',
          progress: i / 10,
        ),
    ],
  };
  scenarios.forEach((name, items) {
    _scene(
      'חיווי עבודה, $name',
      wrapApp: (app) => BlocProvider<WorkStatusCubit>(
        create: (_) {
          final cubit = WorkStatusCubit();
          items.forEach(cubit.upsert);
          return cubit;
        },
        child: app,
      ),
      build: (_) => const Stack(children: [WorkStatusOverlay()]),
      verify: (tester, run) async {
        expectInsideViewport(
          tester,
          run,
          find.byType(DecoratedBox).first,
          name: 'כרטיס החיווי',
        );
        expectNoClippedText(
          tester,
          run,
          within: find.byType(WorkStatusOverlay),
        );
      },
    );
  });
}

// ─── סיור ──────────────────────────────────────────────────────────────────

void _tourScenes() {
  for (final steps in [0, 1, 3]) {
    _scene(
      'סיור מודרך, אחרי $steps מעברים',
      wrapApp: (app) => BlocProvider<TourCubit>(
        create: (_) => TourCubit()..start(libraryLoaded: true),
        child: app,
      ),
      build: (_) => Stack(
        fit: StackFit.expand,
        children: [
          TourOverlayScreen(
            onStepChanged: (_) {},
            targetRectResolver: (_) => const Rect.fromLTWH(24, 40, 120, 48),
          ),
        ],
      ),
      act: (tester, run) async {
        for (var i = 0; i < steps; i++) {
          final cubit = tester
              .element(find.byType(TourOverlayScreen))
              .read<TourCubit>();
          await cubit.next();
          await tester.pumpAndSettle();
        }
      },
      verify: (tester, run) async {
        final buttons = find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        );
        for (var i = 0; i < buttons.evaluate().length; i++) {
          expectVisible(tester, run, buttons.at(i), name: 'כפתור סיור $i');
        }
      },
    );
  }
}

// ─── שמור וזכור ────────────────────────────────────────────────────────────

class _SzData extends ShamorZachorDataProvider {
  _SzData({this.data = const {}, this.loading = false, this.failure});

  final Map<String, BookCategory> data;
  final bool loading;
  final ShamorZachorError? failure;

  @override
  Map<String, BookCategory> get allBookData => data;

  @override
  bool get isLoading => loading;

  @override
  ShamorZachorError? get error => failure;

  @override
  bool get hasData => data.isNotEmpty;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> loadAllData() async {}

  @override
  bool isBookTrackedById(int bookId) => false;
}

class _SzProgress extends ShamorZachorProgressProvider {
  @override
  Future<void> ensureLoaded() async {}

  @override
  bool get isLoading => false;

  @override
  ShamorZachorError? get error => null;

  @override
  Map<String, PageProgress> getProgressForBookById(int bookId) => {};

  @override
  PageProgress getProgressForItemById(int bookId, int absoluteIndex) =>
      PageProgress();

  @override
  double getLearnProgressPercentageById(int bookId, BookDetails bookDetails) =>
      0.0;

  @override
  String? getCompletionDateSyncById(int bookId) => null;

  @override
  bool isBookCompletedById(int bookId, BookDetails bookDetails) => false;

  @override
  bool isBookConsideredInProgressById(int bookId, BookDetails bookDetails) =>
      false;
}

BookCategory _szCategory(String name, int books, {String? bookTitle}) =>
    BookCategory(
      name: name,
      contentType: 'דף',
      books: {
        for (var i = 0; i < books; i++)
          bookTitle ?? 'מסכת $i': BookDetails(
            contentType: 'דף',
            id: 1000 + i,
            categoryPath: name,
            parts: const [BookPart(name: 'ראשי', startPage: 2, endPage: 60)],
          ),
      },
      defaultStartPage: 2,
      isCustom: false,
      sourceFile: 'test',
    );

Widget Function(Widget) _szProviders(_SzData Function() makeData) => (app) {
  final libraryBloc = _MockLibraryBloc();
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(
      library: Library(categories: []),
      isLoading: false,
      currentCategory: null,
    ),
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ShamorZachorDataProvider>(
        create: (_) => makeData(),
      ),
      ChangeNotifierProvider<ShamorZachorProgressProvider>(
        create: (_) => _SzProgress(),
      ),
      RepositoryProvider<SettingsRepository>(
        create: (_) => SettingsRepository(),
      ),
      BlocProvider<SettingsBloc>(
        create: (context) =>
            SettingsBloc(repository: context.read<SettingsRepository>()),
      ),
      BlocProvider<LibraryBloc>.value(value: libraryBloc),
    ],
    child: app,
  );
};

void _shamorZachorScenes() {
  final scenarios = <String, _SzData Function()>{
    'מצב ריק': () => _SzData(),
    'טעינה': () => _SzData(loading: true),
    'שגיאה': () => _SzData(
      failure: const ShamorZachorError(
        type: ShamorZachorErrorType.parseError,
        message: 'לא ניתן לקרוא את רשימת הספרים',
        details: 'FormatException: Unexpected character at line 1',
      ),
    ),
    'מאות ספרים': () => _SzData(
      data: {
        'תלמוד בבלי': _szCategory('תלמוד בבלי', 300),
        'משנה': _szCategory('משנה', 60),
      },
    ),
    'שם ספר ארוך': () => _SzData(
      data: {'תלמוד בבלי': _szCategory('תלמוד בבלי', 3, bookTitle: _longTitle)},
    ),
  };
  scenarios.forEach((name, makeData) {
    _scene(
      'שמור וזכור, $name',
      settle: name != 'טעינה',
      scaffold: false,
      wrapApp: _szProviders(makeData),
      build: (_) => const Scaffold(body: ShamorZachorMainScreen()),
    );
  });

  _scene(
    'שמור וזכור, מסך הצלחה (completion_animation_overlay)',
    build: (_) => _opener(
      (context) async => CompletionAnimationOverlay.show(context, 'סיימת!'),
    ),
    act: (tester, run) async {
      await tester.tap(find.text('פתח'));
      await tester.pump(const Duration(milliseconds: 300));
    },
    verify: (tester, run) async {
      expectInsideViewport(
        tester,
        run,
        find.text('סיימת!'),
        name: 'הודעת הסיום',
      );
      await tester.pumpAndSettle();
    },
  );
}

// ─── הדפסה ─────────────────────────────────────────────────────────────────

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _FakePrintSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

Widget _printProviders(Widget app) {
  final settingsBloc = _MockSettingsBloc();
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  return RepositoryProvider<SettingsRepository>.value(
    value: _FakePrintSettingsRepository(),
    child: BlocProvider<SettingsBloc>.value(value: settingsBloc, child: app),
  );
}

void _printingScenes() {
  // הנתונים לא נטענים לעולם: מסך ההדפסה במצב טעינה, בלי PDF ובלי רסטור.
  _scene(
    'מסך הדפסה, טעינה',
    settle: false,
    wrapApp: _printProviders,
    build: (_) => _opener(
      (context) => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PrintingScreen(
          data: Completer<String>().future,
          bookId: _longTitle,
          startLine: 0,
        ),
      ),
    ),
    act: (tester, run) => _openNoSettle(tester),
    verify: (tester, run) async {
      expectInsideViewport(
        tester,
        run,
        find.byType(PrintingScreen),
        name: 'מסך ההדפסה',
      );
    },
  );
}
