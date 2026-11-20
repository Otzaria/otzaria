// Responsive: קורא הספרים (מסך הטקסט) בכל מטריצת החלונות. הסרגל העליון,
// הכותרת, חיצי הניווט ופעולות הסרגל נשארים בתוך החלון ונגישים גם בחלון צר,
// בשם ספר ארוך ובהגדלת הטקסט של המערכת.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/find_ref_preference_store.dart';
import 'package:otzaria/find_ref/find_ref_recent_store.dart';
import 'package:otzaria/find_ref/repository/db_commentator_entry.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/view/find_ref_dialog.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drag_handle.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_panel.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_display/view/text_display_bar_button.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:otzaria/widgets/navigation/reader_nav_center.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:provider/provider.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/fake_commentary_library_provider.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_navigation_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_tabs_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';
import 'responsive_harness.dart';

const _longBookTitle =
    'שולחן ערוך אורח חיים עם נושאי כלים ומפרשים רבים ושונים מאוד לבדיקת כותרת ארוכה';
const _longLocation =
    'סימן שא סעיף ג בהגה: ומילתא אגב אורחיה קמ"ל דמועד לאדם הוה מועד לבהמה, '
    'וצריך להבין את החילוק שבין הדברים';
const _longAuthor =
    'רבי יוסף קארו בן אפרים, מחבר הבית יוסף והשולחן ערוך, צפת תש"ה';

/// מצב מסך הקורא שהתרחיש מציג.
enum _Phase { loaded, loading, error }

/// כל מה שמסך הקורא צריך כדי לעלות בבדיקה: בלוקים מזויפים, ספק הגדרות בזיכרון
/// וספריית ספרים ריקה. נבנה פעם אחת בתוך [wrapApp] ונסגר בסיום הבדיקה.
class _Rig {
  _Rig._(this.book, this.bloc, this.tab, this.tabsBloc);

  final TextBook book;
  final StubTextBookBloc bloc;
  final TextBookTab tab;
  final StubTabsBloc tabsBloc;
  final settingsBloc = StubSettingsBloc(SettingsState.initial());
  final navigationBloc = StubNavigationBloc();
  final bookmarkBloc = _FakeBookmarkBloc();
  final personalNotesBloc = PersonalNotesBloc();
  final tourCubit = TourCubit();
  final focusRepository = FocusRepository()..resetForTesting();
  final shamorData = _FakeShamorZachorData();
  final shamorProgress = _FakeShamorZachorProgress();

  factory _Rig.create({
    String title = 'ספר בדיקה',
    String? author,
    String currentTitle = 'סימן א',
    bool showLeftPane = false,
    bool pinLeftPane = false,
    bool pageShape = false,
    List<String>? content,
    List<TocEntry> toc = const [],
    List<Link> links = const [],
    List<String> commentators = const [],
    bool showSplitView = false,
    _Phase phase = _Phase.loaded,
    double fontSize = 18,
  }) {
    final book = TextBook(title: title, author: author);
    final TextBookState state = switch (phase) {
      _Phase.loading => TextBookLoading(book, 0, false, const []),
      _Phase.error => TextBookError('שגיאה', book, 0, false, const []),
      _Phase.loaded => TextBookLoaded(
        book: book,
        showPageShapeView: pageShape,
        showLeftPane: showLeftPane,
        content: content ?? const ['שורה א', 'שורה ב', 'שורה ג'],
        fontSize: fontSize,
        showSplitView: showSplitView,
        activeCommentators: commentators,
        commentatorGroups: const [],
        availableCommentators: commentators,
        links: links,
        visibleLinks: const <Link>[],
        linksByLine: {if (links.isNotEmpty) 1: links},
        tableOfContents: toc,
        removeNikud: false,
        removePunctuation: false,
        visibleIndices: const [0],
        selectedIndex: 0,
        pinLeftPane: pinLeftPane,
        searchText: '',
        currentTitle: currentTitle,
        searchMode: SearchMode.exact,
      ),
    };
    final bloc = StubTextBookBloc(state);
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabsBloc = StubTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    return _Rig._(book, bloc, tab, tabsBloc);
  }

  Future<void> dispose() async {
    await bloc.close();
    await tabsBloc.close();
    await settingsBloc.close();
    await navigationBloc.close();
    await bookmarkBloc.close();
    // close() ממתין לטעינת הערות אמיתית שהמסך הפעיל, ואין לה מה לסיים כאן.
    await personalNotesBloc.close().timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
    await tourCubit.close();
    focusRepository.resetForTesting();
    tab.dispose();
  }

  Widget wrap(Widget app) => MultiProvider(
    providers: [
      Provider<FocusRepository>.value(value: focusRepository),
      ChangeNotifierProvider<ShamorZachorDataProvider>.value(value: shamorData),
      ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
        value: shamorProgress,
      ),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
        BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
        BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        BlocProvider<TourCubit>.value(value: tourCubit),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
      ],
      child: app,
    ),
  );
}

/// ה-rigs של הבדיקה הנוכחית. נסגרים ב-tearDown הרגיל ולא ב-addTearDown: סגירת
/// PersonalNotesBloc ממתינה לקלט/פלט אמיתי ותקועה באזור הזמן המזויף.
final List<_Rig> _liveRigs = [];

/// מרכיב את [_Rig] בתוך wrapApp של התשתית.
Widget Function(Widget) _wrapWith(
  _Rig Function() create, {
  void Function(_Rig rig)? onCreated,
}) {
  return (app) {
    final rig = create();
    onCreated?.call(rig);
    _liveRigs.add(rig);
    return rig.wrap(app);
  };
}

Widget _reader(BuildContext context) => const _ReaderHost();

class _ReaderHost extends StatelessWidget {
  const _ReaderHost();

  @override
  Widget build(BuildContext context) {
    final tab = context.read<TabsBloc>().state.tabs.single as TextBookTab;
    return TextBookViewerBloc(
      tab: tab,
      isInCombinedView: false,
      openBookCallback: (_) {},
    );
  }
}

/// כל שורות הטקסט במרכז הסרגל (כותרת, מחבר) בתוך גובה הסרגל. הגובה קבוע, ובלי
/// הבדיקה הזו טקסט מוגדל שיוצא מהסרגל לא נתפס: אין עליו שגיאת layout.
void _expectTitleInsideBar(WidgetTester tester, ResponsiveRun run) {
  final bar = tester.getRect(find.byType(AppTopBar).first);
  final paragraphs = find.descendant(
    of: find.byType(ReaderNavCenter),
    matching: find.byType(RichText),
  );
  for (final element in paragraphs.evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph) continue;
    final text = render.text.toPlainText();
    if (text.trim().isEmpty) continue;
    final rect = MatrixUtils.transformRect(
      render.getTransformTo(null),
      Offset.zero & render.size,
    );
    if (rect.top < bar.top - 0.5 || rect.bottom > bar.bottom + 0.5) {
      run.add(
        ResponsiveIssue(
          'clipped-text',
          'שורת הכותרת "${text.length > 20 ? text.substring(0, 20) : text}" '
              'יוצאת מגובה הסרגל: ${rect.top.toStringAsFixed(1)}..'
              '${rect.bottom.toStringAsFixed(1)} מול '
              '${bar.top.toStringAsFixed(1)}..${bar.bottom.toStringAsFixed(1)}',
        ),
      );
    }
  }
}

/// הסרגל העליון: כפתור הניווט, חיצי הניווט ופעולות הסרגל נגישים.
ResponsiveAct _topBarChecks() => (tester, run) async {
  _expectTitleInsideBar(tester, run);
  expectVisible(
    tester,
    run,
    find.byType(NavPanelToggleButton),
    name: 'כפתור חלונית הניווט',
  );
  // מרכז הסרגל ריק בין הכפתורים ולכן לא נתפס בנגיעה: בודקים את הכפתורים.
  expectInsideViewport(
    tester,
    run,
    find.byType(ResponsiveActionBar),
    name: 'סרגל הפעולות',
  );
  expectVisible(
    tester,
    run,
    find.descendant(
      of: find.byType(ResponsiveActionBar),
      matching: find.byType(IconButton),
    ),
    name: 'כפתור בסרגל הפעולות',
  );
  if (run.viewport.touch) {
    // במגע כפתורי הסרגל בגודל נגיעה (48), כולל חיצי הניווט.
    expectTapTarget(
      tester,
      run,
      find.descendant(
        of: find.byType(NavPanelToggleButton),
        matching: find.byType(IconButton),
      ),
      name: 'כפתור חלונית הניווט',
    );
    final arrows = find.descendant(
      of: find.byType(ReaderNavCenter),
      matching: find.byType(IconButton),
    );
    for (var i = 0; i < arrows.evaluate().length; i++) {
      expectTapTarget(tester, run, arrows.at(i), name: 'חץ ניווט $i');
    }
  }
  expectVisible(
    tester,
    run,
    find.byType(ReaderNavCenter),
    name: 'מרכז הניווט (חיצים וכותרת)',
  );
};

Future<void> main() async {
  // sanitizeQuery של חיפוש בספר מאציל למנוע ה-Rust.
  await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    for (final rig in _liveRigs) {
      await rig.dispose();
    }
    _liveRigs.clear();
    for (final close in _closers) {
      await close().timeout(const Duration(seconds: 1), onTimeout: () {});
    }
    _closers.clear();
    LibraryProviderManager.instance.resetForTesting();
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    // חימום מטמון הדורות מחוץ לזמן המזויף, כדי שתפריט המפרשים בצורת הדף לא
    // ייתקע על המסד.
    await text_utils.splitByEra(const []);
    FindRefRecentStore.clear();
    FindRefDialog.resetExamplesRotationForTesting();
    LibraryProviderManager.instance.resetForTesting();
    final commentaryProvider = FakeCommentaryLibraryProvider();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): commentaryProvider,
      },
      providers: [commentaryProvider],
    );
  });

  testResponsive(
    'קורא: סרגל עליון, ספר רגיל',
    wrapApp: _wrapWith(() => _Rig.create()),
    build: _reader,
    scaffold: false,
    verify: _topBarChecks(),
  );

  testResponsive(
    'קורא: כותרת ארוכה עם מחבר',
    wrapApp: _wrapWith(
      () => _Rig.create(
        title: _longBookTitle,
        author: _longAuthor,
        currentTitle: '$_longBookTitle, $_longLocation',
      ),
    ),
    build: _reader,
    scaffold: false,
    verify: _topBarChecks(),
  );

  testResponsive(
    'קורא: סרגל עליון בהגדלת טקסט, ספר רגיל',
    wrapApp: _wrapWith(() => _Rig.create()),
    build: _reader,
    scaffold: false,
    viewports: _textScaleViewports,
    verify: _topBarChecks(),
  );

  testResponsive(
    'קורא: כותרת ארוכה עם מחבר בהגדלת טקסט',
    wrapApp: _wrapWith(
      () => _Rig.create(
        title: _longBookTitle,
        author: _longAuthor,
        currentTitle: '$_longBookTitle, $_longLocation',
      ),
    ),
    build: _reader,
    scaffold: false,
    viewports: _textScaleViewports,
    verify: _topBarChecks(),
  );

  testResponsive(
    'קורא: צורת הדף',
    wrapApp: _wrapWith(() => _Rig.create(pageShape: true)),
    build: _reader,
    scaffold: false,
    verify: _topBarChecks(),
  );

  testResponsive(
    'קורא: טעינה',
    wrapApp: _wrapWith(() => _Rig.create(phase: _Phase.loading)),
    // מחוון הטעינה מנפיש לעד, ו-pumpAndSettle של התשתית לא היה מסתיים.
    build: (context) => TickerMode(enabled: false, child: _reader(context)),
    scaffold: false,
    verify: (tester, run) async {
      expectVisible(
        tester,
        run,
        find.byType(NavPanelToggleButton),
        name: 'כפתור חלונית הניווט בטעינה',
      );
    },
  );

  testResponsive(
    'קורא: שגיאת טעינה',
    wrapApp: _wrapWith(() => _Rig.create(phase: _Phase.error)),
    build: _reader,
    scaffold: false,
    verify: (tester, run) async {
      expectVisible(
        tester,
        run,
        find.byType(OtzariaErrorState),
        name: 'מצב שגיאה',
      );
      expectNoClippedText(tester, run, within: find.byType(OtzariaErrorState));
    },
  );

  testResponsive(
    'קורא: חלונית ניווט פתוחה עם תוכן עניינים',
    wrapApp: _wrapWith(() => _Rig.create(showLeftPane: true, toc: _longToc())),
    build: _reader,
    scaffold: false,
    // לשוניות החלונית הן TabBarView: גלילה אופקית בין לשוניות היא מכוונת.
    horizontalScroll: true,
    verify: (tester, run) async {
      expectVisible(
        tester,
        run,
        find.byType(NavPanelToggleButton),
        name: 'כפתור חלונית הניווט',
      );
      expectInsideViewport(
        tester,
        run,
        find.byType(NavSidePanel),
        name: 'חלונית הניווט',
      );
      await expectReachable(
        tester,
        run,
        find.textContaining('סימן 1,'),
        name: 'ערך בתוכן העניינים',
      );
    },
  );

  testResponsive(
    'קורא: חלונית ניווט נעוצה בהגדלת טקסט',
    wrapApp: _wrapWith(
      () => _Rig.create(
        showLeftPane: true,
        pinLeftPane: true,
        toc: _longToc(),
        title: _longBookTitle,
        author: _longAuthor,
        currentTitle: '$_longBookTitle, $_longLocation',
      ),
    ),
    build: _reader,
    scaffold: false,
    horizontalScroll: true,
    viewports: _textScaleViewports,
    verify: _topBarChecks(),
  );

  // סרגל מלא (ידית גרירה, ניווט, חזרה, נעיצה, צורת דף) בחלונית צרה: נעיצה
  // וצורת דף עוברות ל"עוד ⋮" כשאין להן מקום, ואינן גולשות מהסרגל. 210 הוא
  // חלונית של פיצול בחלון הצר ביותר במחשב (420 לשתי חלוניות).
  testResponsive(
    'קורא: סרגל מלא בחלונית צרה, נעיצה וצורת דף ב"עוד"',
    wrapApp: _wrapWith(
      () => _Rig.create(
        showLeftPane: true,
        pinLeftPane: true,
        pageShape: true,
        toc: _longToc(),
        title: _longBookTitle,
        author: _longAuthor,
      ),
    ),
    build: (context) {
      final tab = context.read<TabsBloc>().state.tabs.single;
      return PaneDragHandleScope(
        pane: tab,
        enabled: true,
        child: const _ReaderHost(),
      );
    },
    scaffold: false,
    horizontalScroll: true,
    viewports: const [
      ResponsiveViewport(210, 800),
      ResponsiveViewport(260, 800),
      ResponsiveViewport(320, 800, touch: true),
      ResponsiveViewport(380, 800, touch: true),
      ResponsiveViewport(420, 800),
    ],
    verify: (tester, run) async {
      expectVisible(
        tester,
        run,
        find.byType(NavPanelToggleButton),
        name: 'כפתור חלונית הניווט',
      );
      // כל אחת משתי הפעולות נגישה: בסרגל, או כשורה ב"עוד ⋮" של הקורא (בו
      // נכנסות גם פעולות ההתחלה שקופלו).
      final more = find.descendant(
        of: find.byType(ResponsiveActionBar),
        matching: find.byTooltip('עוד פעולות'),
      );
      for (final label in const ['בטל נעיצה', 'הגדרות צורת הדף']) {
        if (tester.any(find.byTooltip(label).hitTestable())) continue;
        if (!tester.any(more.hitTestable())) {
          run.add(
            ResponsiveIssue(
              'unreachable',
              '"$label" לא בסרגל, ואין "עוד ⋮" שמגיע אליה',
            ),
          );
          continue;
        }
        await tester.tap(more);
        await tester.pumpAndSettle();
        if (find.text(label).evaluate().isEmpty) {
          run.add(ResponsiveIssue('unreachable', '"$label" לא ב"עוד ⋮"'));
        }
        await tester.tapAt(const Offset(1, 1));
        await tester.pumpAndSettle();
      }
    },
  );

  testResponsive(
    'קורא: טקסט ארוך בלי רווחים ושורות רבות',
    wrapApp: _wrapWith(
      () => _Rig.create(
        content: [
          for (var i = 0; i < 200; i++)
            i == 3
                ? 'א' * 2500
                : 'בראשית ברא אלהים את השמים ואת הארץ והארץ היתה תהו ובהו $i',
        ],
      ),
    ),
    build: _reader,
    scaffold: false,
    verify: _topBarChecks(),
  );

  testResponsive(
    'קורא: חלונית מפרשים פתוחה',
    wrapApp: _wrapWith(() => _Rig.create(showSplitView: true)),
    build: _reader,
    scaffold: false,
    verify: _topBarChecks(),
  );

  testResponsive(
    'קורא: חלונית תצוגת טקסט',
    wrapApp: _wrapWith(() => _Rig.create()),
    build: (context) => const SingleChildScrollView(
      child: TextBookDisplayPanel(
        targets: [TextTarget.body, TextTarget.commentary],
      ),
    ),
    viewports: [..._panelViewports, ..._textScaleViewports],
    verify: (tester, run) async {
      expectNoClippedText(
        tester,
        run,
        within: find.byType(TextBookDisplayPanel),
      );
      await expectReachable(
        tester,
        run,
        find.text('גוף הספר'),
        name: 'כותרת מקטע גוף הספר',
      );
      await expectReachable(
        tester,
        run,
        find.text('מפרשים'),
        name: 'כותרת מקטע המפרשים',
      );
    },
  );

  testResponsive(
    'קורא: חלונית תצורת העמוד',
    build: (context) => const SingleChildScrollView(
      child: PageShapeSettingsPanel(
        availableCommentators: ['רש"י על בראשית', 'רמב"ן על בראשית'],
        bookTitle: 'בראשית',
      ),
    ),
    viewports: [..._panelViewports, ..._textScaleViewports],
    verify: (tester, run) async {
      // כותרות שורות ההגדרה הן עד שתי שורות (maxLines=2 ב-settings_card.dart,
      // בכל מסכי ההגדרות). בחלון של 320 בהגדלה גדולה כותרת ארוכה עדיין יכולה
      // להיקטע אחרי שתי שורות, ולכן כאן נדרש רק שבגודל רגיל שום טקסט לא נחתך.
      if (run.viewport.textScale == 1.0) {
        expectNoClippedText(
          tester,
          run,
          within: find.byType(PageShapeSettingsPanel),
        );
      }
      await expectReachable(
        tester,
        run,
        find.text('איפוס מפרשים'),
        name: 'כפתור איפוס מפרשים',
      );
    },
  );

  testResponsive(
    'קורא: רשימת מפרשים עם קישורים',
    wrapApp: _wrapWith(
      () => _Rig.create(
        commentators: const ['מפרש בדיקה'],
        links: [_commentaryLink(1), _commentaryLink(2)],
      ),
    ),
    build: (context) => CommentaryListBase(
      openBookCallback: (_) {},
      fontSize: 18,
      showSearch: true,
      shrinkWrap: false,
    ),
    viewports: [..._panelViewports, ..._textScaleViewports],
    verify: (tester, run) async {
      expectInsideViewport(
        tester,
        run,
        find.byType(CommentaryListBase),
        name: 'רשימת המפרשים',
      );
      await expectReachable(
        tester,
        run,
        find.text('מפרש בדיקה').first,
        name: 'כותרת המפרש',
      );
    },
  );

  testResponsive(
    'קורא: חיפוש בתוך הספר, מאות תוצאות',
    wrapApp: _wrapWith(() => _Rig.create()),
    build: (context) => TextBookSearchView(
      contentLoader: () async => ['את השמים ואת הארץ'],
      lines: LineScrollController(),
      focusNode: FocusNode(),
      closeLeftPaneCallback: () {},
      initialQuery: 'אבג',
      simpleSearchRunner: (content, query) async => [
        for (var i = 0; i < 300; i++)
          TextSearchResult(
            snippet: 'אבג $_longLocation אבג',
            index: i,
            query: 'אבג',
            address: _longLocation,
            matchOffset: 0,
          ),
      ],
    ),
    viewports: [..._panelViewports, ..._textScaleViewports],
    verify: (tester, run) async {
      await tester.pump(kSearchFieldDebounce + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expectVisible(
        tester,
        run,
        find.byType(TextField).first,
        name: 'שדה החיפוש בספר',
      );
    },
  );

  testResponsive(
    'חיפוש מקורות: מאות תוצאות עם שמות ארוכים',
    wrapApp: _findRefWrap,
    build: (context) => const FindRefDialog(),
    viewports: [..._panelViewports, ..._textScaleViewports],
    act: (tester, run) async {
      await tester.enterText(find.byType(TextField).first, 'בראשית');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 700));
    },
    verify: (tester, run) async {
      expectVisible(
        tester,
        run,
        find.byType(TextField).first,
        name: 'שדה חיפוש המקורות',
      );
      await expectReachable(
        tester,
        run,
        find.byType(ListTile).first,
        name: 'תוצאה ראשונה',
      );
    },
  );

  testWidgets('קורא: שינוי גודל חלון תוך כדי קריאה שומר את המקום בספר', (
    tester,
  ) async {
    const start = ResponsiveViewport(1280, 800);
    final run = await pumpResponsive(
      tester,
      start,
      _reader,
      wrapApp: _wrapWith(() => _Rig.create(content: _manyLines())),
      scaffold: false,
    );
    final lines = _liveRigs.single.tab.lines;
    unawaited(lines.jumpToLine(120));
    await tester.pumpAndSettle();
    final before = lines.captureAnchor()!.line;
    expect(before, inInclusiveRange(118, 122), reason: 'הקפיצה לא הגיעה');

    // מצמצמים עד רוחב טלפון ובחזרה, כמו גרירת קצה החלון באמצע קריאה.
    for (final size in const [
      Size(600, 700),
      Size(320, 640),
      Size(480, 500),
      Size(1280, 800),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final now = lines.captureAnchor()!.line;
      if ((now - before).abs() > 2) {
        run.add(
          ResponsiveIssue(
            'layout-error',
            'המקום בספר זז משורה $before לשורה $now בגודל חלון $size',
          ),
        );
      }
    }
    run.release();
    run.expectClean();
  });

  testWidgets('קורא: גודל טקסט הספר מול הגדלת הטקסט של המערכת (מאפיין)', (
    tester,
  ) async {
    // מאפיין את המצב הנוכחי, בלי לשנות אותו: הגדלת הטקסט של המערכת מגדילה
    // גם את טקסט הקריאה של הספר מעבר לגודל הגופן שבהגדרות.
    // ההכרעה (גודל טקסט הספר מול הגדרת המערכת) ממתינה לבעל הפרויקט; כשתתקבל תהפוך הבדיקה
    // הזו לנעילת ההכרעה.
    Future<double> lineHeightAt(double scale) async {
      final run = await pumpResponsive(
        tester,
        ResponsiveViewport(1280, 800, textScale: scale),
        _reader,
        wrapApp: _wrapWith(() => _Rig.create(content: _manyLines())),
        scaffold: false,
      );
      final heights = [
        for (final element in find.bySubtype<RichText>().evaluate())
          if (element.renderObject case final RenderParagraph p
              when p.text.toPlainText().startsWith('בראשית ברא'))
            p.size.height,
      ];
      run.release();
      expect(heights, isNotEmpty, reason: 'שורת טקסט לא נמצאה');
      await tester.pumpWidget(const SizedBox.shrink());
      return heights.first;
    }

    final normal = await lineHeightAt(1.0);
    final scaled = await lineHeightAt(1.5);
    expect(
      scaled / normal,
      greaterThan(1.3),
      reason: 'התנהגות נוכחית: טקסט הספר גדל עם הגדרת המערכת',
    );
  });
}

Link _commentaryLink(int index2) => Link(
  heRef: 'בראשית א',
  index1: 1,
  path2: 'מפרש בדיקה.txt',
  index2: index2,
  connectionType: 'COMMENTARY',
  targetCategoryId: 1,
  targetFileType: 'txt',
);

/// ספר ארוך מספיק כדי לגלול בו.
List<String> _manyLines() => [
  for (var i = 0; i < 400; i++)
    'בראשית ברא אלהים את השמים ואת הארץ והארץ היתה תהו ובהו וחשך על פני תהום $i',
];

/// חלוניות הקורא נפתחות בחלון צר ובחלון רחב.
const List<ResponsiveViewport> _panelViewports = [
  ResponsiveViewport(320, 640, touch: true),
  ResponsiveViewport(480, 600),
  ResponsiveViewport(800, 500),
  ResponsiveViewport(1280, 800),
];

/// תוכן עניינים ארוך: ערכים עם כותרות ארוכות בלי נקודות שבירה.
List<TocEntry> _longToc() => [
  for (var i = 1; i <= 40; i++)
    TocEntry(
      text: i % 7 == 0 ? 'סימן $i, $_longLocation' : 'סימן $i,',
      index: i,
    ),
];

/// הגדלות הטקסט של המערכת ברוחב טלפון וברוחב חלון צר (שלב 7).
const List<ResponsiveViewport> _textScaleViewports = [
  ResponsiveViewport(320, 640, textScale: 1.3, touch: true),
  ResponsiveViewport(320, 640, textScale: 1.5, touch: true),
  ResponsiveViewport(320, 640, textScale: 2.0, touch: true),
  ResponsiveViewport(600, 800, textScale: 1.3),
  ResponsiveViewport(600, 800, textScale: 1.5),
  ResponsiveViewport(600, 800, textScale: 2.0),
];

/// חיפוש מקורות: מאות תוצאות עם שמות ספרים ארוכים, בלי מנוע ובלי מסד.
class _ManyResultsRepository implements FindRefRepository {
  @override
  bool get respectHiddenLibrary => false;

  @override
  Stream<void> get userBooksChanges => const Stream.empty();

  @override
  void cancelPendingSearch() {}

  @override
  Future<List<DbReferenceResult>> findRefs(
    String ref, {
    bool includePersonalBooks = false,
    FindRefPreferences? preferences,
  }) async => [
    for (var i = 0; i < 300; i++)
      DbReferenceResult(
        title: i.isEven ? 'בראשית' : _longBookTitle,
        reference: 'פרק $i, $_longLocation',
        segment: i,
        bookId: i + 1,
        bookPath: 'תנ"ך, תורה, ספרי מקרא, $_longBookTitle',
      ),
  ];

  @override
  Future<List<DbCommentatorEntry>> getCommentatorsForResult(
    DbReferenceResult ref,
  ) async => const [];

  @override
  Future<void> prewarmGlobalAltToc() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}

class _EmptyHistoryRepository extends HistoryRepository {
  @override
  Future<List<Bookmark>> load() async => const [];

  @override
  Future<List<Bookmark>> mutate(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async => apply(const []);
}

class _NoLibraryNavigationRepository implements NavigationRepository {
  @override
  Future<bool> checkLibraryIsEmpty() async => false;
  @override
  Future<void> refreshLibrary() async {}
}

/// המסך הראשי אינו חלק מהבדיקה: מעבר המסך נבלע.
class _IgnoringNavigationBloc extends NavigationBloc {
  _IgnoringNavigationBloc()
    : super(
        repository: _NoLibraryNavigationRepository(),
        tabsRepository: _NoTabsRepository(),
      );

  @override
  void add(NavigationEvent event) {}
}

/// עטיפת התלויות של [FindRefDialog]. הבלוקים נסגרים ב-tearDown הרגיל.
Widget _findRefWrap(Widget app) {
  final tabsBloc = TabsBloc(repository: _NoTabsRepository());
  final historyBloc = HistoryBloc(_EmptyHistoryRepository());
  final navigationBloc = _IgnoringNavigationBloc();
  final findRefBloc = FindRefBloc(findRefRepository: _ManyResultsRepository());
  _closers.addAll([
    tabsBloc.close,
    historyBloc.close,
    navigationBloc.close,
    findRefBloc.close,
  ]);
  FocusRepository().findRefSearchController.text = '';
  return MultiProvider(
    providers: [Provider<FocusRepository>.value(value: FocusRepository())],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<FindRefBloc>.value(value: findRefBloc),
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<HistoryBloc>.value(value: historyBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
      ],
      child: app,
    ),
  );
}

/// סגירות שנדחות ל-tearDown הרגיל (מחוץ לזמן המזויף של הבדיקה).
final List<Future<void> Function()> _closers = [];

class _FakeBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _FakeBookmarkBloc() : super(BookmarkState.initial());

  @override
  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShamorZachorData extends ShamorZachorDataProvider {
  _FakeShamorZachorData();

  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeShamorZachorProgress extends ShamorZachorProgressProvider {
  _FakeShamorZachorProgress();

  @override
  Future<void> ensureLoaded() async {}
}
