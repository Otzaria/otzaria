import 'dart:convert';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/book_versions_dialog.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/printing/export_restriction_service.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/book_versions_action.dart';
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

      expect(find.byType(NavPanelToggleButton), findsOneWidget);
      expect(
        find.byIcon(OtzariaIcons.alef_deletion_24_regular),
        findsOneWidget,
      );

      final overflowButton = find.byIcon(FluentIcons.more_vertical_24_regular);
      expect(overflowButton, findsOneWidget);
      await tester.tap(overflowButton);
      await tester.pumpAndSettle();

      expect(find.text('אפס הגדרות ספר זה'), findsOneWidget);
      expect(find.text('ייצוא הספר'), findsOneWidget);
      expect(find.text('הדפסה'), findsOneWidget);
      expect(find.text('אודות הספר'), findsOneWidget);
      // ספר בלי מהדורות במאגר — אין מה להציע
      expect(find.text('הצג נוסחאות נוספות'), findsNothing);
    });

    testWidgets('ספר מוגבל לייצוא — הפריט נעדר בלי טעינה מוקדמת של הרשימה', (
      tester,
    ) async {
      // בלי הטעינה שהמסך עושה בעצמו הרשימה ריקה, והפריט היה מוצג.
      ExportRestrictionService.resetForTesting();
      addTearDown(ExportRestrictionService.resetForTesting);
      _mockRestrictedBooksAsset(const ['שמירת שבת כהלכתה - א']);

      final book = TextBook(title: 'שמירת שבת כהלכתה - א');
      final bloc = _TestTextBookBloc(_loadedState(book));
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

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();

      expect(find.text('ייצוא הספר'), findsNothing);
      expect(find.text('הדפסה'), findsOneWidget);
    });

    testWidgets('הלחצן למהדורה המובנית כתוב "פתח בתצוגת PDF"', (
      tester,
    ) async {
      final book = TextBook(title: 'ספר בדיקה');
      final pdfBook = PdfBook(title: 'ספר בדיקה', path: 'ספר בדיקה.pdf');
      DataRepository.instance.library = Future.value(
        Library(
          categories: [
            Category(
              title: 'קטגוריה',
              description: '',
              shortDescription: '',
              order: 1,
              subCategories: [],
              books: [book, pdfBook],
              parent: null,
            ),
          ],
        ),
      );

      final bloc = _TestTextBookBloc(_loadedState(book));
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
      // איתור המהדורות המקבילות נדחה ל-listener של טעינת התוכן.
      bloc.emitStateForTest(_loadedState(book));
      await tester.pumpAndSettle();

      expect(find.byTooltip('פתח בתצוגת PDF'), findsOneWidget);
      expect(find.byTooltip('פתח מהדורה מקבילה'), findsNothing);
    });

    testWidgets('לספר עם נוסחאות התפריט פותח את רשימת הנוסחאות', (
      tester,
    ) async {
      bookVersionsProbeForTesting = (_) async => true;
      addTearDown(() => bookVersionsProbeForTesting = null);

      final book = TextBook(title: 'ספר בדיקה', categoryId: 7);
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

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      expect(find.text('הצג נוסחאות נוספות'), findsOneWidget);

      await tester.tap(find.text('הצג נוסחאות נוספות'));
      await tester.pumpAndSettle();

      expect(find.text('נוסחאות נוספות — ספר בדיקה'), findsOneWidget);
      expect(
        find.text('הנוסח שייבחר ייפתח בכרטיסייה חדשה, באותו מיקום.'),
        findsOneWidget,
      );
    });

    testWidgets('בחירת נוסח פותחת אותו בכרטיסייה חדשה, בשורה הנראית', (
      tester,
    ) async {
      bookVersionsProbeForTesting = (_) async => true;
      bookVersionsListProbeForTesting = (_) async => const [
        BookVersionInfo(
          versionTitle: 'Davidson',
          heVersionTitle: 'מהדורת דיווידסון',
          hasContent: true,
        ),
      ];
      addTearDown(() {
        bookVersionsProbeForTesting = null;
        bookVersionsListProbeForTesting = null;
      });

      final book = TextBook(title: 'ספר בדיקה', categoryId: 7);
      final state = _loadedState(book);
      // הנוסח נפתח בשורה שגלולה כרגע לראש התצוגה, לא ב-tab.index שבו נפתח הספר.
      (state.positionsListener.itemPositions as dynamic).value = const [
        ItemPosition(index: 42, itemLeadingEdge: 0.1, itemTrailingEdge: 0.6),
      ];
      final bloc = _TestTextBookBloc(state);
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

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הצג נוסחאות נוספות'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('מהדורת דיווידסון'));
      await tester.pumpAndSettle();

      expect(
        tabsBloc.receivedEvents.whereType<OpenTabInSidePane>(),
        isEmpty,
        reason: 'נוסח נפתח בכרטיסייה, לא בחלונית לצד',
      );
      final event = tabsBloc.receivedEvents.whereType<OpenOrFocusTab>();
      expect(event, hasLength(1));
      final openedTab = event.single.tab as TextBookTab;
      addTearDown(openedTab.dispose);
      expect(openedTab.book.versionTitle, 'Davidson');
      expect(openedTab.index, 42);
      expect(event.single.insertAdjacent, isTrue);
      // הנוסח כבר פתוח בכרטיסייה אחרת — עליה להיגלל לשורה המבוקשת, לא רק לקבל מיקוד.
      expect(event.single.navigateToPositionIfReused, isTrue);
    });

    testWidgets('גם בכרטיסייה מפוצלת הפעולה מוצעת — היעד הוא כרטיסייה חדשה', (
      tester,
    ) async {
      bookVersionsProbeForTesting = (_) async => true;
      addTearDown(() => bookVersionsProbeForTesting = null);

      final book = TextBook(title: 'ספר בדיקה', categoryId: 7);
      final bloc = _TestTextBookBloc(_loadedState(book));
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

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();

      expect(find.text('הצג נוסחאות נוספות'), findsOneWidget);
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

        expect(
          find.byIcon(OtzariaIcons.book_open_tzurat_hadaf_24_regular),
          findsOneWidget,
        );
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

      // שורה אחת של כפתורי אייקון בראש התפריט — לא שורת טקסט לכל כיוון
      expect(find.byTooltip('הדף/פרק הקודם'), findsOneWidget);
      expect(find.byTooltip('הקטע הקודם'), findsOneWidget);
      expect(find.byTooltip('הקטע הבא'), findsOneWidget);
      expect(find.byTooltip('הדף/פרק הבא'), findsOneWidget);
      expect(find.text('הקטע הבא'), findsNothing);

      // ארבעת הכפתורים באותה שורה, מעל שאר פריטי התפריט
      final navRects = [
        tester.getRect(find.byTooltip('הדף/פרק הקודם')),
        tester.getRect(find.byTooltip('הקטע הקודם')),
        tester.getRect(find.byTooltip('הקטע הבא')),
        tester.getRect(find.byTooltip('הדף/פרק הבא')),
      ];
      for (final rect in navRects) {
        expect(rect.top, closeTo(navRects.first.top, 0.5));
      }
      expect(
        navRects.first.center.dy,
        lessThan(tester.getCenter(find.text('סימניות בספר זה')).dy),
      );
    });

    testWidgets('במצב משולב לחיצה על "הקטע הבא" משאירה את התפריט פתוח', (
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

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();

      // מעבר קטע נלחץ שוב ושוב — סגירת התפריט בכל לחיצה הייתה מחייבת
      // פתיחה מחדש לכל קטע
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('הקטע הבא'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('הקטע הבא'), findsOneWidget);
      }
    });

    testWidgets('במצב רגיל אין שורת ניווט בתפריט ה-overflow', (tester) async {
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

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();

      // הניווט במרכז הסרגל — הכפתור היחיד לכל כיוון הוא זה שבסרגל
      expect(find.byTooltip('הקטע הבא'), findsOneWidget);
      expect(find.byTooltip('הדף/פרק הבא'), findsOneWidget);
      expect(
        tester.getCenter(find.byTooltip('הקטע הבא')).dy,
        lessThan(tester.getCenter(find.text('סימניות בספר זה')).dy),
      );
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
      bool pinned = true,
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
      // הנעיצה נקבעת לפני הפתיחה, כמו אצל משתמש: מצב הפריסה מדווח ב-post-frame.
      bloc.emitStateForTest(loaded.copyWith(pinLeftPane: pinned));
      await tester.pump();
      await tester.pump();
      bloc.emitStateForTest(
        loaded.copyWith(showLeftPane: true, pinLeftPane: pinned),
      );
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

    testWidgets('חלונית לא נעוצה מרחפת מעל הטקסט — ה-reanchor מדוכא', (
      tester,
    ) async {
      final count = await pumpAndToggleLeftPane(
        tester,
        size: const Size(1600, 900),
        pinned: false,
      );
      expect(count, 0);
    });

    testWidgets('במסך צר (overlay) ה-reanchor מדוכא בפתיחת החלונית', (
      tester,
    ) async {
      final count = await pumpAndToggleLeftPane(
        tester,
        size: const Size(780, 900),
      );
      expect(count, 0);
    });
  });

  group('reanchor בשינוי גודל גופן', () {
    // רגרסיה (issue #915): שינוי גודל גופן משנה את גובה כל הפריטים, ובלי
    // עיגון-מחדש ההיסט בפיקסלים נוחת על מקום אחר והקורא מאבד את מקומו.

    Future<int> pumpAndChangeFontSize(
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
      await tester.pump();

      bloc.emitStateForTest(loaded.copyWith(fontSize: loaded.fontSize + 3));
      await tester.pump();

      final dynamic state = tester.state(find.byType(TextBookViewerBloc));
      return state.reanchorOnFontSizeCount as int;
    }

    testWidgets('שינוי גודל גופן מפעיל עיגון-מחדש', (tester) async {
      final count = await pumpAndChangeFontSize(
        tester,
        size: const Size(1600, 900),
      );
      expect(count, greaterThan(0));
    });

    testWidgets('העיגון רץ גם במסך צר — גובה הפריטים משתנה בכל פריסה', (
      tester,
    ) async {
      final count = await pumpAndChangeFontSize(
        tester,
        size: const Size(780, 900),
      );
      expect(count, greaterThan(0));
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

  group('ניווט בין קטעים בקיצור (issue #1516)', () {
    Future<(TextBookTab, TextBookLoaded)> pumpLongBook(
      WidgetTester tester,
    ) async {
      final book = TextBook(title: 'ספר בדיקה');
      final state = _loadedState(
        book,
        content: List.generate(200, (i) => 'שורה מספר $i'),
      );
      final bloc = _TestTextBookBloc(state);
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
      await _setSurfaceSize(tester, const Size(1200, 700));
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
      final wired = state.copyWith(
        scrollController: tab.scrollController,
        positionsListener: tab.positionsListener,
      );
      bloc.emitStateForTest(wired);
      await tester.pumpAndSettle();
      return (tab, wired);
    }

    testWidgets('Alt+↓ באזור הקריאה מגיע למטפל הקיצורים הגלובלי', (
      tester,
    ) async {
      await pumpLongBook(tester);
      var reached = 0;
      KeyEventResult handler(KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown &&
            HardwareKeyboard.instance.isAltPressed) {
          reached++;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      FocusManager.instance.addLateKeyEventHandler(handler);
      addTearDown(
        () => FocusManager.instance.removeLateKeyEventHandler(handler),
      );

      await tester.tap(find.text('שורה מספר 2'));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<SelectionArea>(),
        isNotNull,
        reason: 'הפוקוס צריך להיות באזור הקריאה, כמו אצל המדווח',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      // מסיים את טיימר הלחיצה הכפולה שנפתח בהקשה על הטקסט.
      await tester.pump(kDoubleTapTimeout);

      expect(reached, 1);
    });

    testWidgets('לחיצות רצופות על "הבא" מתקדמות קטע בכל לחיצה', (
      tester,
    ) async {
      final (tab, state) = await pumpLongBook(tester);

      for (var i = 0; i < 10; i++) {
        tab.navNextSegmentNotifier.value++;
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      final top = state.positionsListener.itemPositions.value
          .where((p) => p.itemTrailingEdge > 0)
          .map((p) => p.index)
          .reduce(min);
      expect(top, 10);
    });
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
  // openBook (מסלול פתיחת נוסח) קורא גם ל-HistoryBloc ול-NavigationBloc.
  final historyBloc = _TestHistoryBloc();
  final navigationBloc = _TestNavigationBloc();
  addTearDown(() async {
    await historyBloc.close();
    await navigationBloc.close();
  });

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
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
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

/// מגיש את רשימת הספרים המוגבלים מהזיכרון. קריאה אמיתית ל-asset נתקעת תחת
/// ה-FakeAsync של testWidgets ולא הייתה מסתיימת לעולם.
void _mockRestrictedBooksAsset(List<String> titles) {
  rootBundle.clear();
  addTearDown(rootBundle.clear);
  final payload = ByteData.sublistView(
    Uint8List.fromList(utf8.encode(jsonEncode({'books': titles}))),
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        return key == ExportRestrictionService.assetPath ? payload : null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null),
  );
}

TextBookLoaded _loadedState(
  TextBook book, {
  bool showSplitView = false,
  List<String> content = const ['שורה א', 'שורה ב', 'שורה ג'],
}) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: content,
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

  final List<TabsEvent> receivedEvents = [];

  @override
  void add(TabsEvent event) => receivedEvents.add(event);

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

class _TestHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _TestHistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc()
    : super(const NavigationState(currentScreen: Screen.reading));

  @override
  void add(NavigationEvent event) {}

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
