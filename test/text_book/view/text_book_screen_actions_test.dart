import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FocusRepository focusRepository;
  late _FakeShamorZachorDataProvider shamorZachorDataProvider;
  late _FakeShamorZachorProgressProvider shamorZachorProgressProvider;
  late _TestBookmarkBloc bookmarkBloc;
  late PersonalNotesBloc personalNotesBloc;
  late TourCubit tourCubit;

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    focusRepository = FocusRepository()..resetForTesting();
    shamorZachorDataProvider = _FakeShamorZachorDataProvider();
    shamorZachorProgressProvider = _FakeShamorZachorProgressProvider();
    bookmarkBloc = _TestBookmarkBloc();
    personalNotesBloc = PersonalNotesBloc();
    tourCubit = TourCubit();
  });

  tearDown(() async {
    await bookmarkBloc.close();
    await personalNotesBloc.close();
    await tourCubit.close();
    focusRepository.resetForTesting();
  });

  group('TextBookViewerBloc actions', () {
    testWidgets('במצב רגיל ה-overflow כולל איפוס, ייצוא והדפסה', (
      tester,
    ) async {
      final book = TextBook(title: 'ספר בדיקה');
      final bloc = _TestTextBookBloc(_loadedState(book));
      final tab = TextBookTab(
        book: book,
        index: 0,
        blocOverride: bloc,
      );
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final settingsBloc = _TestSettingsBloc(
        SettingsState.initial().copyWith(enablePerBookSettings: true),
      );

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bloc.close();
        await tabsBloc.close();
        await settingsBloc.close();
        tab.dispose();
      });

      await _setSurfaceSize(tester, const Size(1600, 900));
      await _pumpTextBookScreen(
        tester,
        tab: tab,
        textBookBloc: bloc,
        tabsBloc: tabsBloc,
        settingsBloc: settingsBloc,
        focusRepository: focusRepository,
        shamorZachorDataProvider: shamorZachorDataProvider,
        shamorZachorProgressProvider: shamorZachorProgressProvider,
        bookmarkBloc: bookmarkBloc,
        personalNotesBloc: personalNotesBloc,
        tourCubit: tourCubit,
        isInCombinedView: false,
      );

      final overflowButton = find.byIcon(FluentIcons.more_vertical_24_regular);
      expect(overflowButton, findsOneWidget);
      await tester.tap(overflowButton);
      await tester.pumpAndSettle();

      expect(find.text('אפס הגדרות ספר זה'), findsOneWidget);
      expect(find.text('ייצוא הספר'), findsOneWidget);
      expect(find.text('הדפסה'), findsOneWidget);
      expect(find.text('אודות הספר'), findsOneWidget);
    });

    testWidgets(
      'תפריט תצוגת המפרשים כולל "פתח כרטיסיית מפרשים"',
      (tester) async {
        final book = TextBook(title: 'ספר בדיקה');
        final bloc = _TestTextBookBloc(_loadedState(book));
        final tab = TextBookTab(
          book: book,
          index: 0,
          blocOverride: bloc,
        );
        final tabsBloc = _TestTabsBloc(
          TabsState(tabs: [tab], currentTabIndex: 0),
        );
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await bloc.close();
          await tabsBloc.close();
          await settingsBloc.close();
          tab.dispose();
        });

        await _setSurfaceSize(tester, const Size(1600, 900));
        await _pumpTextBookScreen(
          tester,
          tab: tab,
          textBookBloc: bloc,
          tabsBloc: tabsBloc,
          settingsBloc: settingsBloc,
          focusRepository: focusRepository,
          shamorZachorDataProvider: shamorZachorDataProvider,
          shamorZachorProgressProvider: shamorZachorProgressProvider,
          bookmarkBloc: bookmarkBloc,
          personalNotesBloc: personalNotesBloc,
          tourCubit: tourCubit,
          isInCombinedView: false,
        );

        final viewModeButton = find.byTooltip('בחר סוג תצוגת מפרשים');
        expect(viewModeButton, findsOneWidget);
        await tester.tap(viewModeButton);
        await tester.pumpAndSettle();

        // ודא שזה התפריט הנכון (מצבי התצוגה) ושנוסף פריט הפעולה החדש
        expect(find.text('מפרשים בצד'), findsOneWidget);
        expect(find.text('צורת הדף'), findsOneWidget);
        expect(find.text('פתח כרטיסיית מפרשים'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'openNotesTabNotifier פותח פאנל כשסיפליט ויו כבר פעיל והפאנל סגור',
      (tester) async {
        // P2 regression: ToggleSplitView(true) is swallowed by the bloc when
        // showSplitView is already true (Equatable). The fix fires openNotesTabNotifier
        // directly on the tab so SplitedViewScreen always opens the panel.
        final book = TextBook(title: 'ספר בדיקה');
        final bloc = _TestTextBookBloc(
          _loadedState(book).copyWith(showSplitView: true),
        );
        final tab = TextBookTab(
          book: book,
          index: 0,
          blocOverride: bloc,
        );
        final tabsBloc = _TestTabsBloc(
          TabsState(tabs: [tab], currentTabIndex: 0),
        );
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await bloc.close();
          await tabsBloc.close();
          await settingsBloc.close();
          tab.dispose();
        });

        await _setSurfaceSize(tester, const Size(1600, 900));
        await _pumpTextBookScreen(
          tester,
          tab: tab,
          textBookBloc: bloc,
          tabsBloc: tabsBloc,
          settingsBloc: settingsBloc,
          focusRepository: focusRepository,
          shamorZachorDataProvider: shamorZachorDataProvider,
          shamorZachorProgressProvider: shamorZachorProgressProvider,
          bookmarkBloc: bookmarkBloc,
          personalNotesBloc: personalNotesBloc,
          tourCubit: tourCubit,
          isInCombinedView: false,
        );

        // הפאנל סגור — טאב ההערות לא בעץ (AdaptiveSidePane לא בנה תוכן עדיין)
        expect(find.text('הערות'), findsNothing);

        // הפעלת הנוטיפייר ישירות (מדמה קריאה ל-_openPersonalNotesForCurrentView
        // כשסיפליט ויו כבר פעיל — ToggleSplitView(true) היה נבלע על ידי הבלוק)
        tab.openNotesTabNotifier.value++;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // הפאנל נפתח — שלוש הכרטיסיות גלויות
        expect(find.text('הערות'), findsOneWidget);
      },
    );

    testWidgets('במצב משולב כפתורי הניווט עוברים ל-overflow', (tester) async {
      final book = TextBook(title: 'ספר בדיקה');
      final bloc = _TestTextBookBloc(_loadedState(book));
      final tab = TextBookTab(
        book: book,
        index: 0,
        blocOverride: bloc,
      );
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bloc.close();
        await tabsBloc.close();
        await settingsBloc.close();
        tab.dispose();
      });

      await _setSurfaceSize(tester, const Size(1200, 900));
      await _pumpTextBookScreen(
        tester,
        tab: tab,
        textBookBloc: bloc,
        tabsBloc: tabsBloc,
        settingsBloc: settingsBloc,
        focusRepository: focusRepository,
        shamorZachorDataProvider: shamorZachorDataProvider,
        shamorZachorProgressProvider: shamorZachorProgressProvider,
        bookmarkBloc: bookmarkBloc,
        personalNotesBloc: personalNotesBloc,
        tourCubit: tourCubit,
        isInCombinedView: true,
      );

      final overflowButton = find.byIcon(FluentIcons.more_vertical_24_regular);
      expect(overflowButton, findsOneWidget);
      await tester.tap(overflowButton);
      await tester.pumpAndSettle();

      expect(find.text('הדף/פרק הקודם'), findsOneWidget);
      expect(find.text('הקטע הקודם'), findsOneWidget);
      expect(find.text('הקטע הבא'), findsOneWidget);
      expect(find.text('הדף/פרק הבא'), findsOneWidget);
    });

    testWidgets('במצב רגיל כפתורי הניווט גלויים ישירות במרכז הסרגל', (
      tester,
    ) async {
      final book = TextBook(title: 'ספר בדיקה');
      final bloc = _TestTextBookBloc(_loadedState(book));
      final tab = TextBookTab(
        book: book,
        index: 0,
        blocOverride: bloc,
      );
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bloc.close();
        await tabsBloc.close();
        await settingsBloc.close();
        tab.dispose();
      });

      await _setSurfaceSize(tester, const Size(1600, 900));
      await _pumpTextBookScreen(
        tester,
        tab: tab,
        textBookBloc: bloc,
        tabsBloc: tabsBloc,
        settingsBloc: settingsBloc,
        focusRepository: focusRepository,
        shamorZachorDataProvider: shamorZachorDataProvider,
        shamorZachorProgressProvider: shamorZachorProgressProvider,
        bookmarkBloc: bookmarkBloc,
        personalNotesBloc: personalNotesBloc,
        tourCubit: tourCubit,
        isInCombinedView: false,
      );

      // כפתורי הניווט גלויים ישירות במרכז הסרגל — לא דרך תפריט overflow
      expect(find.byTooltip('הדף/פרק הקודם'), findsOneWidget);
      expect(find.byTooltip('הקטע הקודם'), findsOneWidget);
      expect(find.byTooltip('הקטע הבא'), findsOneWidget);
      expect(find.byTooltip('הדף/פרק הבא'), findsOneWidget);
    });

    testWidgets(
      'תצוגה משולבת מכבדת את מצב התצוגה ומאפשרת לשנות אותו',
      (tester) async {
        // רגרסיה: בעבר תצוגה משולבת כפתה "מפרשים מתחת" ל-state (ההעדפה אבדה
        // בפירוק ההצמדה) ונטרלה את תפריט בחירת התצוגה.
        final book = TextBook(title: 'ספר בדיקה');
        final bloc = _TestTextBookBloc(_loadedState(book, showSplitView: true));
        final tab = TextBookTab(
          book: book,
          index: 0,
          blocOverride: bloc,
        );
        final tabsBloc = _TestTabsBloc(
          TabsState(tabs: [tab], currentTabIndex: 0),
        );
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await bloc.close();
          await tabsBloc.close();
          await settingsBloc.close();
          tab.dispose();
        });

        await _setSurfaceSize(tester, const Size(1600, 900));
        await _pumpTextBookScreen(
          tester,
          tab: tab,
          textBookBloc: bloc,
          tabsBloc: tabsBloc,
          settingsBloc: settingsBloc,
          focusRepository: focusRepository,
          shamorZachorDataProvider: shamorZachorDataProvider,
          shamorZachorProgressProvider: shamorZachorProgressProvider,
          bookmarkBloc: bookmarkBloc,
          personalNotesBloc: personalNotesBloc,
          tourCubit: tourCubit,
          isInCombinedView: true,
        );

        final splitedView = tester.widget<SplitedViewScreen>(
          find.byType(SplitedViewScreen).first,
        );
        expect(
          splitedView.showSplitView,
          isTrue,
          reason: 'מצב "מפרשים בצד" של הטאב מכובד גם בתצוגה משולבת',
        );

        // תפריט בחירת התצוגה פעיל — למשתמש יש שליטה גם בתצוגה משולבת
        await tester.tap(find.byTooltip('בחר סוג תצוגת מפרשים'));
        await tester.pumpAndSettle();
        expect(find.text('מפרשים מתחת'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  });

  group('reanchor בפתיחת/סגירת החלונית', () {
    // רגרסיה: ב-overlay (מסך צר) רוחב הטקסט לא משתנה, ולכן ה-reanchor אסור
    // שירוץ — ה-jumpTo שלו מבטל את אנימציית הניווט מבחירה בסרגל הצד ומשאיר
    // את המשתמש במקום. ב-push (מסך רחב) הרוחב משתנה וה-reanchor נחוץ.

    Future<int> pumpAndToggleLeftPane(
      WidgetTester tester, {
      required Size size,
    }) async {
      final book = TextBook(title: 'ספר בדיקה');
      final loaded = _loadedState(book);
      final bloc = _TestTextBookBloc(loaded);
      final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bloc.close();
        await tabsBloc.close();
        await settingsBloc.close();
        tab.dispose();
      });

      await _setSurfaceSize(tester, size);
      await _pumpTextBookScreen(
        tester,
        tab: tab,
        textBookBloc: bloc,
        tabsBloc: tabsBloc,
        settingsBloc: settingsBloc,
        focusRepository: focusRepository,
        shamorZachorDataProvider: shamorZachorDataProvider,
        shamorZachorProgressProvider: shamorZachorProgressProvider,
        bookmarkBloc: bookmarkBloc,
        personalNotesBloc: personalNotesBloc,
        tourCubit: tourCubit,
        isInCombinedView: false,
      );
      // מתן זמן ל-onLayoutModeChanged (post-frame) לעדכן את _paneUsesPushLayout
      await tester.pump();

      // פתיחת החלונית (false→true) מפעילה את בדיקת ה-reanchor
      bloc.emitStateForTest(loaded.copyWith(showLeftPane: true));
      await tester.pump();

      final dynamic state = tester.state(find.byType(TextBookViewerBloc));
      return state.reanchorOnPaneToggleCount as int;
    }

    testWidgets('במסך רחב (push) ה-reanchor רץ בפתיחת החלונית', (tester) async {
      final count = await pumpAndToggleLeftPane(
        tester,
        size: const Size(1600, 900),
      );
      expect(count, greaterThan(0));
    });

    testWidgets('במסך צר (overlay) ה-reanchor מדוכא בפתיחת החלונית', (
      tester,
    ) async {
      final count = await pumpAndToggleLeftPane(
        tester,
        size: const Size(820, 900),
      );
      expect(count, 0);
    });
  });

  group('שמירת פוקוס מקלדת', () {
    testWidgets(
      'מסך הספר לא חוטף פוקוס משדה קלט בדיאלוג כשה-viewport משתנה (מקלדת וירטואלית)',
      (tester) async {
        // רגרסיה: באנדרואיד/מסך מגע, כשספר פתוח בעיון ופותחים את דיאלוג
        // החיפוש, פתיחת המקלדת משנה את ה-viewport וגורמת rebuild של מסך
        // הספר שמתחת לדיאלוג. ה-postFrameCallback של המסך היה קורא
        // requestFocus וחוטף את הפוקוס משדה החיפוש — והמקלדת נסגרה מיד.
        final book = TextBook(title: 'ספר בדיקה');
        final bloc = _TestTextBookBloc(_loadedState(book));
        final tab = TextBookTab(
          book: book,
          index: 0,
          blocOverride: bloc,
        );
        final tabsBloc = _TestTabsBloc(
          TabsState(tabs: [tab], currentTabIndex: 0),
        );
        final settingsBloc = _TestSettingsBloc(SettingsState.initial());
        final dialogFieldFocusNode = FocusNode(debugLabel: 'DialogSearchField');

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          dialogFieldFocusNode.dispose();
          await bloc.close();
          await tabsBloc.close();
          await settingsBloc.close();
          tab.dispose();
        });

        await _setSurfaceSize(tester, const Size(1200, 900));
        await _pumpTextBookScreen(
          tester,
          tab: tab,
          textBookBloc: bloc,
          tabsBloc: tabsBloc,
          settingsBloc: settingsBloc,
          focusRepository: focusRepository,
          shamorZachorDataProvider: shamorZachorDataProvider,
          shamorZachorProgressProvider: shamorZachorProgressProvider,
          bookmarkBloc: bookmarkBloc,
          personalNotesBloc: personalNotesBloc,
          tourCubit: tourCubit,
          isInCombinedView: false,
        );

        // פתיחת דיאלוג עם שדה טקסט ממוקד מעל מסך הספר (כמו דיאלוג החיפוש)
        final screenContext = tester.element(find.byType(TextBookViewerBloc));
        showDialog<void>(
          context: screenContext,
          builder: (_) => Dialog(
            child: TextField(focusNode: dialogFieldFocusNode, autofocus: true),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          dialogFieldFocusNode.hasFocus,
          isTrue,
          reason: 'שדה הדיאלוג אמור לקבל פוקוס בפתיחה',
        );

        // הקטנת גובה ה-viewport — מדמה פתיחת מקלדת וירטואלית שמכווצת את
        // המסך וגורמת rebuild של מסך הספר שברקע.
        tester.view.physicalSize = const Size(1200, 500);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          dialogFieldFocusNode.hasFocus,
          isTrue,
          reason:
              'מסך הספר שמתחת לדיאלוג אסור שיחטוף את הפוקוס '
              'משדה הקלט — חטיפה כזו סוגרת את המקלדת מיד',
        );
      },
    );
  });
}

Future<void> _pumpTextBookScreen(
  WidgetTester tester, {
  required TextBookTab tab,
  required TextBookBloc textBookBloc,
  required TabsBloc tabsBloc,
  required SettingsBloc settingsBloc,
  required FocusRepository focusRepository,
  required ShamorZachorDataProvider shamorZachorDataProvider,
  required ShamorZachorProgressProvider shamorZachorProgressProvider,
  required BookmarkBloc bookmarkBloc,
  required PersonalNotesBloc personalNotesBloc,
  required TourCubit tourCubit,
  required bool isInCombinedView,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<FocusRepository>.value(value: focusRepository),
        ChangeNotifierProvider<ShamorZachorDataProvider>.value(
          value: shamorZachorDataProvider,
        ),
        ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
          value: shamorZachorProgressProvider,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<TourCubit>.value(value: tourCubit),
        ],
        child: MaterialApp(
          home: TextBookViewerBloc(
            tab: tab,
            isInCombinedView: isInCombinedView,
            openBookCallback: (_) {},
          ),
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

TextBookLoaded _loadedState(TextBook book, {bool showSplitView = false}) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב', 'שורה ג'],
    fontSize: 18,
    showSplitView: showSplitView,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const <Link>[],
    visibleLinks: const <Link>[],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    removePunctuation: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    currentTitle: 'סימן א',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
    searchMode: SearchMode.exact,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitStateForTest(TextBookState state) => emit(state);

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

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _TestBookmarkBloc() : super(BookmarkState.initial());

  @override
  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) {
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShamorZachorDataProvider extends ShamorZachorDataProvider {
  _FakeShamorZachorDataProvider();

  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeShamorZachorProgressProvider extends ShamorZachorProgressProvider {
  _FakeShamorZachorProgressProvider();

  @override
  Future<void> ensureLoaded() async {}
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
