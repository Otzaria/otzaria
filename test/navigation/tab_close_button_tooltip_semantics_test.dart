// issue #1399: קריסת התוכנה ב-Windows בעקבות עץ נגישות שנשבר.
//
// ה-X של כרטיסיה נושא tooltip ("סגור כרטיסיה") ויושב בתוך הכרטיסיה, שגם לה יש
// tooltip (הכותרת המלאה). Tooltip חיצוני אינו יוצר צומת סמנטיקה משלו — הודעתו
// ועוגן ה-OverlayPortal של הבלון מתמזגים לצומת הקרוב, כאן צומת הכרטיסיה, ולצומת
// יש מקום לעוגן אחד בלבד. עוגן ה-X נשמט, ובריחוף עליו הבלון נשלח למערכת
// ההפעלה בלי אב: Windows דוחה את עדכון עץ הנגישות
// (`Failed to update ui::AXTree ... will not be in the tree`), העץ קופא,
// ובמעבר הפוקוס הבא התוכנה קורסת ב-flutter_windows.dll.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/semantics_update_recorder.dart';

void main() {
  // ה-binding המקליט חייב להיווצר לפני כל binding אחר בקובץ.
  SemanticsRecordingBinding.ensure();
  final recorder = SemanticsRecordingBinding.recorder;

  setUp(() async {
    recorder.reset();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  /// מרחף עם עכבר על הווידג'ט שה-tooltip שלו הוא [tooltip], ומוודא שהבלון נפתח.
  Future<TestGesture> hoverTooltip(WidgetTester tester, String tooltip) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byTooltip(tooltip).first));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(tooltip), findsOneWidget, reason: 'הבלון "$tooltip" נפתח');
    return mouse;
  }

  testWidgets(
    'ריחוף על ה-X של כרטיסיה בעלת tooltip כותרת אינו שולח צומת נגישות יתום '
    '(issue #1399)',
    (tester) async {
      final closeTooltip =
          'סגור כרטיסיה (${ShortcutHelper.formatShortcutForDisplay('ctrl+w')})';
      final tab = _makeTextTab('ספר א', currentTitle: 'פרק א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      final handle = tester.ensureSemantics();
      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('ספר א, פרק א'),
        findsOneWidget,
        reason: 'לכרטיסיה יש tooltip כותרת — התרחיש של הבאג',
      );

      final mouse = await hoverTooltip(tester, closeTooltip);
      expect(
        recorder.violations,
        isEmpty,
        reason: 'הבלון של ה-X חייב להישלח למנוע עם אב בסדר המעבר',
      );

      // ה-tooltip שייך לצומת של כפתור ה-X, לא לצומת הכרטיסיה.
      final closeNode = tester.getSemantics(find.byTooltip(closeTooltip));
      expect(
        closeNode,
        isSemantics(isButton: true, tooltip: closeTooltip),
      );
      expect(
        closeNode.traversalParentIdentifier,
        isNotNull,
        reason: 'עוגן הבלון של ה-X נשמר על צומת הכפתור',
      );
      expect(
        tester.getSemantics(find.text('ספר א')),
        isSemantics(tooltip: 'ספר א, פרק א'),
        reason: 'צומת הכרטיסיה ממשיך לשאת את tooltip הכותרת',
      );

      // גם סגירת הבלון (יציאת העכבר) עוברת בלי עדכון פגום.
      await mouse.moveTo(const Offset(5, 700));
      await tester.pump(const Duration(seconds: 1));
      expect(recorder.violations, isEmpty);
      handle.dispose();
    },
  );

  testWidgets(
    'ריחוף על ה-X של חלונית בלשונית מפוצלת אינו שולח צומת נגישות יתום '
    '(issue #1399)',
    (tester) async {
      final right = _makeTextTab('ימין');
      final left = _makeTextTab('שמאל');
      final tab = CombinedTab(rightTab: right, leftTab: left);
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      addTearDown(() async {
        tab.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      final handle = tester.ensureSemantics();
      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('סגור חלונית'), findsNWidgets(2));

      final mouse = await hoverTooltip(tester, 'סגור חלונית');
      expect(recorder.violations, isEmpty);
      expect(
        tester.getSemantics(find.byTooltip('סגור חלונית').first),
        isSemantics(isButton: true, tooltip: 'סגור חלונית'),
      );

      await mouse.moveTo(const Offset(5, 700));
      await tester.pump(const Duration(seconds: 1));
      expect(recorder.violations, isEmpty);
      handle.dispose();
    },
  );
}

Future<void> _pumpTitleBar(
  WidgetTester tester, {
  required TabsBloc tabsBloc,
  required NavigationBloc navigationBloc,
  required SettingsBloc settingsBloc,
}) async {
  await tester.pumpWidget(
    AppWindowScope(
      controller: const WindowManagerAppWindowController(),
      geometry: const WindowManagerAppWindowController(),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: CustomTitleBar(onReadingSettingsPressed: () {}),
            ),
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

TextBookTab _makeTextTab(String title, {String currentTitle = ''}) {
  final book = TextBook(title: title);
  final bloc = _TestTextBookBloc(
    TextBookLoaded(
      book: book,
      showLeftPane: false,
      content: const ['שורה א'],
      fontSize: 18,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      removePunctuation: false,
      visibleIndices: const [0],
      selectedIndex: 0,
      pinLeftPane: false,
      searchText: '',
      currentTitle: currentTitle,
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
    ),
  );
  final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
  tab.currentTitle.value = currentTitle;
  return tab;
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState);

  @override
  void add(NavigationEvent event) {}

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
