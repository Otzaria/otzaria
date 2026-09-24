import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/navigation/view/reading_tabs_side_panel.dart';
import 'package:otzaria/navigation/view/tab_search_menu.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';
import 'package:otzaria/navigation/view/vertical_reading_tab_strip.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import '../helpers/memory_settings_cache.dart';

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  /// stub חסר state — אין מה לשכפל.
  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  late _TestTabsBloc tabsBloc;
  late _TestSettingsBloc settingsBloc;
  late _TestHistoryBloc historyBloc;
  late _TestWorkspaceBloc workspaceBloc;
  late List<OpenedTab> tabs;

  Future<void> pumpPanel(
    WidgetTester tester, {
    bool show = true,
    bool collapsed = false,
    double width = 220,
    double textScale = 1.0,
    List<OpenedTab>? withTabs,
  }) async {
    tabs =
        withTabs ?? [_StubTab('ספר א'), _StubTab('ספר ב'), _StubTab('ספר ג')];
    tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
    settingsBloc = _TestSettingsBloc(
      SettingsState.initial().copyWith(
        readingTabsPlacement: SettingsRepository.readingTabsPlacementSide,
        readingTabsColumnCollapsed: collapsed,
        readingTabsColumnWidth: width,
      ),
    );
    historyBloc = _TestHistoryBloc();
    workspaceBloc = _TestWorkspaceBloc();

    addTearDown(() async {
      await tabsBloc.close();
      await settingsBloc.close();
      await historyBloc.close();
      await workspaceBloc.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<WorkspaceBloc>.value(value: workspaceBloc),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: Row(
                    children: [
                      ReadingTabsSidePanel(show: show),
                      const Expanded(child: SizedBox.expand()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('העמודה מציגה את כל הכרטיסיות בזו אחר זו', (tester) async {
    await pumpPanel(tester);

    expect(find.text('ספר א'), findsOneWidget);
    expect(find.text('ספר ג'), findsOneWidget);

    // הכרטיסיות מסודרות אנכית: כל אחת מתחת לקודמתה.
    final first = tester.getCenter(find.text('ספר א'));
    final third = tester.getCenter(find.text('ספר ג'));
    expect(third.dy, greaterThan(first.dy));
    expect(third.dx, moreOrLessEquals(first.dx, epsilon: 1.0));
  });

  testWidgets('לחיצה על כרטיסיה שולחת SetCurrentTab עם האינדקס שלה', (
    tester,
  ) async {
    await pumpPanel(tester);

    await tester.tap(find.text('ספר ב'), warnIfMissed: false);
    await tester.pumpAndSettle();

    final selected = tabsBloc.addedEvents.whereType<SetCurrentTab>().toList();
    expect(selected, isNotEmpty);
    expect(selected.last.index, 1);
  });

  testWidgets('לחיצת עכבר בדסקטופ בוחרת כרטיסיה ולא נבלעת כגרירה', (
    tester,
  ) async {
    // בדסקטופ הגרירה מיידית (לא לחיצה ארוכה כמו בנייד); בלי מזהה לחיצה
    // מתחרה היא זוכה בזירה כבר בלחיצה, והבחירה נבלעת.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await pumpPanel(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('ספר ב')),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.up();
    await tester.pumpAndSettle();

    final selected = tabsBloc.addedEvents.whereType<SetCurrentTab>().toList();
    // האיפוס בגוף הבדיקה ולא ב-tearDown: בדיקת ה-invariants של flutter_test
    // רצה לפניו ונכשלת על override שנשאר דלוק.
    debugDefaultTargetPlatformOverride = null;
    expect(selected.single.index, 1);
  });

  testWidgets('tooltip מוצג רק כשהכותרת נחתכת', (tester) async {
    await pumpPanel(tester, width: 300);
    expect(
      find.byTooltip('ספר א'),
      findsNothing,
      reason: 'כותרת קצרה נכנסת במלואה — אין צורך ב-tooltip',
    );

    await pumpPanel(tester, width: 120);
    tabsBloc.emitState(
      TabsState(
        tabs: [_StubTab('כותרת ארוכה במיוחד שאינה נכנסת בעמודה צרה')],
        currentTabIndex: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('כותרת ארוכה במיוחד שאינה נכנסת בעמודה צרה'),
      findsOneWidget,
    );
  });

  testWidgets('tooltip של טאב טקסט שטרם נבנה כולל את המיקום מה-DB', (
    tester,
  ) async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final original = TextBookTab.locationTitleResolver;
    TextBookTab.locationTitleResolver = (_, _) async => 'פרק ב';
    addTearDown(() => TextBookTab.locationTitleResolver = original);

    TextBookTab makeTab() {
      final tab = TextBookTab(
        book: TextBook(title: 'ספר א'),
        index: 0,
        splitedView: false,
        blocOverride: _StubTextBookBloc(),
      );
      addTearDown(tab.dispose);
      return tab;
    }

    await pumpPanel(tester, width: 300, withTabs: [makeTab()]);
    expect(find.byTooltip('ספר א, פרק ב'), findsOneWidget);

    await pumpPanel(tester, collapsed: true, withTabs: [makeTab()]);
    expect(find.byTooltip('ספר א, פרק ב'), findsOneWidget);
  });

  testWidgets('במצב מכווץ אין ידית לשינוי רוחב', (tester) async {
    await pumpPanel(tester, collapsed: true);
    expect(find.byType(ResizableDragHandle), findsNothing);

    await pumpPanel(tester);
    expect(find.byType(ResizableDragHandle), findsOneWidget);
  });

  testWidgets('במצב מכווץ האייקונים ממורכזים ברוחב העמודה', (tester) async {
    await pumpPanel(tester, collapsed: true);

    final panelCenter = tester
        .getRect(find.byType(ReadingTabsSidePanel))
        .center;
    final iconCenter = tester
        .getRect(find.byType(VerticalReadingTabStrip))
        .center;
    expect(iconCenter.dx, moreOrLessEquals(panelCenter.dx, epsilon: 0.5));
  });

  testWidgets('כפתור חיפוש הכרטיסיות זמין בשני מצבי העמודה', (tester) async {
    await pumpPanel(tester);
    expect(find.byType(TabSearchButton), findsOneWidget);

    await pumpPanel(tester, collapsed: true);
    expect(find.byType(TabSearchButton), findsOneWidget);
  });

  testWidgets('קו מפריד בין כפתורי הכותרת לכרטיסיות (issue #1503)', (
    tester,
  ) async {
    for (final collapsed in [false, true]) {
      await pumpPanel(tester, collapsed: collapsed);
      final divider = find.descendant(
        of: find.byType(ReadingTabsSidePanel),
        matching: find.byType(Divider),
      );
      expect(divider, findsOneWidget, reason: 'collapsed: $collapsed');
      final dividerRect = tester.getRect(divider);
      expect(
        dividerRect.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(TabSearchButton)).bottom,
        ),
      );
      expect(
        dividerRect.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byType(VerticalReadingTabStrip)).top,
        ),
      );
    }
  });

  testWidgets('לחיצת גלגלת סוגרת את הכרטיסיה ורושמת אותה בהיסטוריה', (
    tester,
  ) async {
    await pumpPanel(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('ספר ב')),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tabsBloc.addedEvents.whereType<RemoveTab>().map((e) => e.tab),
      contains(same(tabs[1])),
    );
    expect(
      historyBloc.addedEvents.whereType<AddHistory>().map((e) => e.tab),
      contains(same(tabs[1])),
    );
  });

  testWidgets('כפתור ה-X של הכרטיסיה הפעילה סוגר אותה', (tester) async {
    await pumpPanel(tester);

    final closeButton = find.byTooltip('סגור כרטיסיה');
    expect(closeButton, findsOneWidget, reason: 'X מוצג בכרטיסיה הפעילה בלבד');
    tester
        .widget<IconButton>(
          find.ancestor(of: closeButton, matching: find.byType(IconButton)),
        )
        .onPressed!();
    await tester.pump();

    expect(
      tabsBloc.addedEvents.whereType<RemoveTab>().map((e) => e.tab),
      contains(same(tabs[0])),
    );
  });

  testWidgets('כפתור הכיווץ משדר את ההגדרה', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.byTooltip('כווץ את עמודת הכרטיסיות'));
    await tester.pumpAndSettle();

    final events = settingsBloc.addedEvents
        .whereType<UpdateReadingTabsColumnCollapsed>()
        .toList();
    expect(events, hasLength(1));
    expect(events.single.collapsed, isTrue);
  });

  testWidgets('במצב מכווץ העמודה צרה ואין כותרות', (tester) async {
    await pumpPanel(tester, collapsed: true);

    expect(
      tester.getSize(find.byType(ReadingTabsSidePanel)).width,
      moreOrLessEquals(kCollapsedTabsColumnWidth, epsilon: 0.5),
    );
    expect(find.text('ספר א'), findsNothing);
    expect(find.byTooltip('הרחב את עמודת הכרטיסיות'), findsOneWidget);
  });

  testWidgets('העמודה נשארת בעץ ברוחב 0 כשהיא מוסתרת', (tester) async {
    await pumpPanel(tester, show: false);

    expect(find.byType(ReadingTabsSidePanel), findsOneWidget);
    expect(tester.getSize(find.byType(ReadingTabsSidePanel)).width, 0);
  });

  testWidgets('גרירת הידית שומרת את הרוחב רק בסיום הגרירה', (tester) async {
    await pumpPanel(tester);

    final panel = tester.getRect(find.byType(ReadingTabsSidePanel));
    // הידית בקצה הפנימי — שמאל ב-RTL. גרירה שמאלה מרחיבה את העמודה.
    final gesture = await tester.startGesture(
      Offset(panel.left + 2, panel.center.dy),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();

    expect(
      settingsBloc.addedEvents.whereType<UpdateReadingTabsColumnWidth>(),
      isEmpty,
      reason: 'בזמן הגרירה הרוחב מקומי בלבד',
    );
    final draggedWidth = tester
        .getSize(find.byType(ReadingTabsSidePanel))
        .width;
    expect(draggedWidth, greaterThan(220));

    await gesture.up();
    await tester.pumpAndSettle();

    final saved = settingsBloc.addedEvents
        .whereType<UpdateReadingTabsColumnWidth>()
        .toList();
    expect(saved, hasLength(1));
    expect(saved.single.width, moreOrLessEquals(draggedWidth, epsilon: 0.5));
  });

  testWidgets('גרירת הרוחב חסומה בתקרה', (tester) async {
    await pumpPanel(
      tester,
      width: SettingsRepository.maxReadingTabsColumnWidth,
    );

    final panel = tester.getRect(find.byType(ReadingTabsSidePanel));
    final gesture = await tester.startGesture(
      Offset(panel.left + 2, panel.center.dy),
    );
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final saved = settingsBloc.addedEvents
        .whereType<UpdateReadingTabsColumnWidth>()
        .toList();
    expect(saved, hasLength(1));
    expect(saved.single.width, SettingsRepository.maxReadingTabsColumnWidth);
  });

  testWidgets('עמודה ללא כרטיסיות פתוחות אינה בונה רשימה', (tester) async {
    await pumpPanel(tester);
    tabsBloc.emitState(const TabsState(tabs: [], currentTabIndex: 0));
    await tester.pumpAndSettle();

    expect(find.text('ספר א'), findsNothing);
    expect(find.byType(VerticalReadingTabStrip), findsOneWidget);
  });

  testWidgets('שתי תזוזות באותו פריים מצטברות זו על זו', (tester) async {
    // הדלתא נמדדת מול הרוחב החי ולא מול זה שנתפס ב-build: בלי זה התזוזה
    // הראשונה נמחקת והעמודה מפגרת אחרי הסמן.
    await pumpPanel(tester);

    final panel = tester.getRect(find.byType(ReadingTabsSidePanel));
    final gesture = await tester.startGesture(
      Offset(panel.left + 2, panel.center.dy),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();

    expect(
      tester.getSize(find.byType(ReadingTabsSidePanel)).width,
      moreOrLessEquals(260, epsilon: 0.5),
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('הגדלת סקייל הטקסט מחזירה tooltip לכותרת שנחתכה', (tester) async {
    // מדידת הכותרת מוטמנת; המפתח כולל את הסקייל, אחרת הערך הישן היה נשאר.
    await pumpPanel(tester, width: 300);
    expect(find.byTooltip('ספר א'), findsNothing);

    await pumpPanel(tester, width: 300, textScale: 6.0);
    expect(find.byTooltip('ספר א'), findsOneWidget);
  });

  testWidgets('ctrl+לחיצה משדר ToggleTabSelection', (tester) async {
    await pumpPanel(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('ספר ב'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(
      tabsBloc.addedEvents.whereType<ToggleTabSelection>().map((e) => e.tab),
      contains(same(tabs[1])),
    );
    expect(
      tabsBloc.addedEvents.whereType<SetCurrentTab>(),
      isEmpty,
      reason: 'בחירה מרובה אינה מחליפה את הכרטיסיה הפעילה',
    );
  });

  testWidgets('shift+לחיצה משדר SelectTabRange', (tester) async {
    await pumpPanel(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('ספר ג'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(
      tabsBloc.addedEvents.whereType<SelectTabRange>().map((e) => e.tab),
      contains(same(tabs[2])),
    );
    expect(tabsBloc.addedEvents.whereType<SetCurrentTab>(), isEmpty);
  });

  testWidgets('נעצי כרטיסיות מוצמדות מיושרים גם כשהפעילה מציגה X', (
    tester,
  ) async {
    final pdfTab = PdfBookTab(
      book: PdfBook(title: 'ספר PDF', path: '/tmp/book.pdf'),
      pageNumber: 1,
    )..isPinned = true;
    addTearDown(pdfTab.dispose);
    final textTab = _StubTab('ספר ב')..isPinned = true;
    await pumpPanel(tester, withTabs: [pdfTab, textTab]);

    final pdfIcon = tester.getCenter(
      find.byIcon(FluentIcons.document_pdf_16_regular),
    );
    final pdfTitle = tester.getCenter(find.text('ספר PDF'));
    final textTitle = tester.getCenter(find.text('ספר ב'));
    final pinFinder = find.byIcon(FluentIcons.pin_24_filled);
    expect(pinFinder, findsNWidgets(2));
    final pins = [
      tester.getCenter(pinFinder.at(0)),
      tester.getCenter(pinFinder.at(1)),
    ];

    // RTL: הפריט הראשון בשורה הוא הימני ביותר.
    expect(pdfIcon.dx, greaterThan(pdfTitle.dx));
    for (final pin in pins) {
      expect(
        pin.dx,
        lessThan(pdfTitle.dx),
        reason: 'הנעץ בקצה השמאלי, אחרי הכותרת (issue #1134)',
      );
      expect(pin.dx, lessThan(textTitle.dx));
    }
    // הנעצים של כרטיסיית PDF ושל כרטיסיית טקסט מיושרים באותו קו אנכי.
    expect(pins[0].dx, closeTo(pins[1].dx, 0.5));
  });

  testWidgets('לחיצה ימנית על כרטיסיה פותחת את תפריט ההקשר', (tester) async {
    await pumpPanel(tester);

    await tester.tapAt(
      tester.getCenter(find.text('ספר ב')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('הצמד כרטיסיה'), findsOneWidget);
    expect(find.text('סגור הכל'), findsOneWidget);

    await tester.tap(find.text('סגור הכל'));
    await tester.pumpAndSettle();
    expect(tabsBloc.addedEvents.whereType<CloseAllTabs>(), isNotEmpty);
  });

  testWidgets('"סגור את האחרים" שומר את הכרטיסייה שנלחצה, לא את הפעילה', (
    tester,
  ) async {
    await pumpPanel(tester);

    await tester.tapAt(
      tester.getCenter(find.text('ספר ג')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('סגור את האחרים'));
    await tester.pumpAndSettle();

    expect(
      tabsBloc.addedEvents.whereType<CloseOtherTabs>().single.keepTab,
      same(tabs[2]),
      reason: 'הכרטיסייה הפעילה היא "ספר א" — issue #1094',
    );
  });

  testWidgets('במגע הכרטיסיות נגררות בלחיצה ארוכה', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpPanel(tester);
    final draggables = find
        .byType(LongPressDraggable<OpenedTab>)
        .evaluate()
        .length;
    debugDefaultTargetPlatformOverride = null;

    expect(
      draggables,
      tabs.length,
      reason: 'במגע גרירה מיידית הייתה בולעת כל החלקה וגלילה',
    );
  });

  testWidgets('במגע לחיצה ארוכה פותחת את תפריט ההקשר ואינה מסדרת מחדש', (
    tester,
  ) async {
    // תפריט ההקשר זוכה בזירת המחוות מול הגרירה — התנהגות זהה לזו של הרצועה
    // העליונה, שגם בה לחיצה ארוכה במגע פותחת תפריט.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpPanel(tester);

    final target = tester.getCenter(find.text('ספר ג'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('ספר א')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final moves = tabsBloc.addedEvents.whereType<MoveTab>().toList();
    final menuOpen = find.text('הצמד כרטיסיה').evaluate().isNotEmpty;
    debugDefaultTargetPlatformOverride = null;

    expect(menuOpen, isTrue);
    expect(moves, isEmpty);
  });

  testWidgets('גרירה קצרה במגע אינה מסדרת מחדש', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpPanel(tester);

    final target = tester.getCenter(find.text('ספר ג'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('ספר א')),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final moves = tabsBloc.addedEvents.whereType<MoveTab>().toList();
    debugDefaultTargetPlatformOverride = null;
    expect(moves, isEmpty);
  });

  testWidgets('השהיית גרירה מעל כרטיסיה אחרת פותחת אותה', (tester) async {
    // דסקטופ בלבד: במגע הגרירה מתחילה רק בלחיצה ארוכה.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpPanel(tester);

    final target = tester.getCenter(find.text('ספר ג'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('ספר א')),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump(kTabSpringOpenDelay + const Duration(milliseconds: 20));

    final springOpened = tabsBloc.addedEvents
        .whereType<SetCurrentTab>()
        .map((e) => e.index)
        .toList();

    await gesture.up();
    await tester.pumpAndSettle();
    // האיפוס לפני ה-expect: בדיקת ה-invariants רצה לפני ה-tearDown.
    debugDefaultTargetPlatformOverride = null;
    expect(springOpened, contains(2));
  });

  testWidgets('כרטיסיה מפוצלת מוצגת עם אייקון הפיצול ושם משולב', (
    tester,
  ) async {
    final combined = CombinedTab(
      rightTab: _StubTab('בראשית'),
      leftTab: _StubTab('רש״י'),
    );
    await pumpPanel(tester, withTabs: [combined], width: 300);

    expect(find.text(combined.title), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.split_horizontal_24_regular,
      ),
      findsOneWidget,
    );
  });

  testWidgets('אייקון הכיווץ מתהפך לפי מצב העמודה', (tester) async {
    await pumpPanel(tester);
    expect(find.byTooltip('כווץ את עמודת הכרטיסיות'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.panel_right_24_regular,
      ),
      findsNothing,
      reason: 'RtlIcon ממיר את האייקון לגרסה ההפוכה ב-RTL',
    );
  });
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  final List<TabsEvent> addedEvents = [];

  void emitState(TabsState state) => emit(state);

  @override
  void add(TabsEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _TestSettingsBloc(super.initialState);

  final List<SettingsEvent> addedEvents = [];

  @override
  void add(SettingsEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestWorkspaceBloc extends Cubit<WorkspaceState>
    implements WorkspaceBloc {
  _TestWorkspaceBloc() : super(WorkspaceState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _TestHistoryBloc() : super(HistoryInitial());

  final List<HistoryEvent> addedEvents = [];

  @override
  void add(HistoryEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _StubTextBookBloc()
    : super(
        TextBookInitial.named(TextBook(title: 'ספר א'), 0, false, const []),
      ) {
    on<TextBookEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
