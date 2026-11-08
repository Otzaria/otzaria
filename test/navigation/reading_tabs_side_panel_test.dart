import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
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
import 'package:otzaria/theme/theme_exports.dart';
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
    ThemeData? theme,
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
          theme: theme,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: ReadingTabsSidePanel(
                    show: show,
                    child: const SizedBox.expand(key: ValueKey('content')),
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

  testWidgets('header buttons still occupy both edges without plugins', (
    tester,
  ) async {
    await pumpPanel(tester, width: 220);
    final button = find.byType(TabSearchButton);
    final row = tester.element(button).findAncestorWidgetOfExactType<Row>()!;
    final delta =
        tester.getRect(button).left - tester.getRect(find.byWidget(row)).left;
    expect(
      delta,
      moreOrLessEquals(0, epsilon: 0.5),
      reason: 'A hidden new-tab button must not reserve a spaceBetween slot',
    );
  });

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

  testWidgets('קו דק בקצה הפנימי מפריד בין העמודה לתוכן (q11 Q1)', (
    tester,
  ) async {
    BorderSide edge() {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ReadingTabsSidePanel),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(box.position, DecorationPosition.foreground);
      final border = (box.decoration as BoxDecoration).border!;
      return (border as BorderDirectional).end;
    }

    for (final collapsed in [false, true]) {
      await pumpPanel(tester, collapsed: collapsed);
      final cs = Theme.of(
        tester.element(find.byType(ReadingTabsSidePanel)),
      ).colorScheme;
      expect(edge().color, cs.outlineVariant, reason: 'collapsed=$collapsed');
      expect(edge().width, 1);
    }
    // בערכת "לבן" בבהיר הקו הוא קו האזורים, כמו בשאר האזורים (#1939).
    const white = AppSeedColors.white;
    await pumpPanel(
      tester,
      theme: AppThemeData.light(
        AppThemeData.createColorScheme(white, Brightness.light),
        compactMenuMode: false,
        variant: AppThemeVariant.ofSeed(white),
      ),
    );
    final context = tester.element(find.byType(ReadingTabsSidePanel));
    expect(edge().color, AppSurfaces.regionBorder(context));
    // הקו במנוחה הוא של העמודה; לידית אין קו שני לצדו.
    await pumpPanel(tester);
    expect(
      tester
          .widget<ResizableDragHandle>(find.byType(ResizableDragHandle))
          .showDivider,
      isFalse,
    );
  });

  testWidgets('ידית שינוי הרוחב גלויה במנוחה, בלי קו שני (סקירת 4.11)', (
    tester,
  ) async {
    await pumpPanel(tester);
    final handle = tester.widget<ResizableDragHandle>(
      find.byType(ResizableDragHandle),
    );
    expect(handle.showDivider, isFalse);
    expect(handle.showIdleGrip, isTrue);
  });

  testWidgets('במצב מכווץ האייקונים ממורכזים ברוחב העמודה', (tester) async {
    await pumpPanel(tester, collapsed: true);

    final panelCenter = _panelRect(tester).center;
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

  testWidgets('במצב מכווץ ריחוף מציג X בפינה השמאלית והוא סוגר (issue #1938)', (
    tester,
  ) async {
    // בדסקטופ הגרירה מיידית, ולכן זה המסלול שבו לחיצה על ה-X עלולה להיבלע.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpPanel(tester, collapsed: true);
    final closeButton = find.byTooltip('סגור כרטיסיה');
    expect(closeButton, findsNothing, reason: 'בלי ריחוף אין X');

    final strip = tester.getRect(find.byType(VerticalReadingTabStrip));
    final secondRow = Rect.fromLTWH(
      strip.left,
      strip.top + kVerticalTabHeight,
      strip.width,
      kVerticalTabHeight,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: secondRow.center);
    await tester.pump();

    final shown = closeButton.evaluate().length;
    final closeRect = shown == 1 ? tester.getRect(closeButton) : Rect.zero;
    if (shown == 1) {
      await mouse.moveTo(closeRect.center);
      await mouse.down(closeRect.center);
      await tester.pump(const Duration(milliseconds: 30));
      await mouse.up();
      await tester.pumpAndSettle();
    }
    debugDefaultTargetPlatformOverride = null;

    expect(shown, 1);
    expect(closeRect.center.dx, lessThan(secondRow.center.dx));
    expect(closeRect.center.dy, lessThan(secondRow.center.dy));
    expect(
      tabsBloc.addedEvents.whereType<RemoveTab>().single.tab,
      same(tabs[1]),
    );
    expect(tabsBloc.addedEvents.whereType<SetCurrentTab>(), isEmpty);
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
      _panelRect(tester).width,
      moreOrLessEquals(kCollapsedTabsColumnWidth, epsilon: 0.5),
    );
    expect(find.text('ספר א'), findsNothing);
    expect(find.byTooltip('הרחב את עמודת הכרטיסיות'), findsOneWidget);
  });

  testWidgets('העמודה נשארת בעץ ברוחב 0 כשהיא מוסתרת', (tester) async {
    await pumpPanel(tester, show: false);

    expect(find.byType(ReadingTabsSidePanel), findsOneWidget);
    expect(_panelRect(tester).width, 0);
  });

  testWidgets('גרירת הידית שומרת את הרוחב רק בסיום הגרירה', (tester) async {
    await pumpPanel(tester);

    final panel = _panelRect(tester);
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
    final draggedWidth = _panelRect(tester).width;
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

    final panel = _panelRect(tester);
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

    final panel = _panelRect(tester);
    final gesture = await tester.startGesture(
      Offset(panel.left + 2, panel.center.dy),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();

    expect(
      _panelRect(tester).width,
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

  // הנעץ בתחילת השורה ולחיץ, כמו ברצועה העליונה (q10 Q14 C). קודם הוא היה
  // אחרי ה-X, וזז כשה-X הופיע (issue #1134).
  testWidgets(
    'נעצי כרטיסיות מוצמדות בתחילת השורה, מיושרים גם כשהפעילה מציגה X',
    (
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
        find.byIcon(OtzariaIcons.document_pdf_24_regular),
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
          greaterThan(pdfIcon.dx),
          reason: 'הנעץ בתחילת השורה, לפני אייקון הסוג והכותרת',
        );
        expect(pin.dx, greaterThan(textTitle.dx));
      }
      // הנעצים של כרטיסיית PDF ושל כרטיסיית טקסט מיושרים באותו קו אנכי.
      expect(pins[0].dx, closeTo(pins[1].dx, 0.5));
    },
  );

  testWidgets('לחיצה על הנעץ מבטלת את ההצמדה ולא בוחרת את הכרטיסיה', (
    tester,
  ) async {
    final pinned = _StubTab('ספר מוצמד')..isPinned = true;
    final other = _StubTab('ספר אחר');
    await pumpPanel(tester, withTabs: [other, pinned]);

    await tester.tap(find.byIcon(FluentIcons.pin_24_filled));
    await tester.pump();

    expect(
      tabsBloc.addedEvents.whereType<TogglePinTab>().map((e) => e.tab),
      [pinned],
    );
    expect(tabsBloc.addedEvents.whereType<SetCurrentTab>(), isEmpty);
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

  testWidgets(
    'לחיצה ארוכה במגע על ה-X פותחת את תפריט הכרטיסיה (issue #2518)',
    (tester) async {
      await pumpPanel(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('סגור כרטיסיה')),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('הצמד כרטיסיה'), findsOneWidget);
      expect(tabsBloc.addedEvents.whereType<RemoveTab>(), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

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
    // בדסקטופ גרירת עכבר מתחילה ללא השהיה.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpPanel(tester);

    final target = tester.getCenter(find.text('ספר ג'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('ספר א')),
      kind: PointerDeviceKind.mouse,
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

  for (final collapsed in [false, true]) {
    for (final kind in [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    ]) {
      testWidgets(
        'משיכה לרוחב ואז לאורך מסדרת כרטיסיה: collapsed=$collapsed, $kind',
        (tester) async {
          await pumpPanel(tester, collapsed: collapsed);
          final first = collapsed
              ? find.byTooltip('ספר א')
              : find.text('ספר א');
          final third = collapsed
              ? find.byTooltip('ספר ג')
              : find.text('ספר ג');
          final start = tester.getCenter(first);
          final target = tester.getCenter(third);
          final gesture = await tester.startGesture(start, kind: kind);
          await gesture.moveBy(const Offset(-30, 0));
          await tester.pump();
          await gesture.moveTo(Offset(start.dx - 30, target.dy));
          await tester.pump();
          await gesture.moveTo(target);
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
          final moves = tabsBloc.addedEvents.whereType<MoveTab>().toList();
          expect(moves, hasLength(1));
          expect(moves.single.tab, same(tabs[0]));
          expect(moves.single.newIndex, 2);
          expect(find.text('הצמד כרטיסיה'), findsNothing);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );

      testWidgets(
        'החלקה אנכית ואלכסונית גוללות כרטיסיות: collapsed=$collapsed, $kind',
        (tester) async {
          final books = [for (var i = 0; i < 24; i++) _StubTab('ספר $i')];
          await pumpPanel(tester, collapsed: collapsed, withTabs: books);
          final strip = find.byType(ReadingTabStrip);
          final scrollable = tester.state<ScrollableState>(
            find.descendant(of: strip, matching: find.byType(Scrollable)),
          );
          for (final delta in [const Offset(0, -60), const Offset(-25, -60)]) {
            final first = collapsed
                ? find.byTooltip('ספר 5')
                : find.text('ספר 5');
            final before = scrollable.position.pixels;
            final gesture = await tester.startGesture(
              tester.getCenter(first),
              kind: kind,
            );
            await gesture.moveBy(delta);
            await tester.pump();
            await gesture.moveBy(const Offset(0, -30));
            await tester.pump();
            await gesture.up();
            await tester.pumpAndSettle();
            expect(scrollable.position.pixels, greaterThan(before));
            expect(tabsBloc.addedEvents.whereType<MoveTab>(), isEmpty);
            expect(find.text('הצמד כרטיסיה'), findsNothing);
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  testWidgets('בדסקטופ לחיצה ארוכה במגע שומרת את תפריט ההקשר', (tester) async {
    await pumpPanel(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('ספר א')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('הצמד כרטיסיה'), findsOneWidget);
    expect(tabsBloc.addedEvents.whereType<MoveTab>(), isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('בדסקטופ לחיצה ארוכה בעמודה מכווצת שומרת את ה־Tooltip', (
    tester,
  ) async {
    await pumpPanel(tester, collapsed: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('ספר א')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();
    expect(find.text('ספר א'), findsOneWidget);
    expect(tabsBloc.addedEvents.whereType<MoveTab>(), isEmpty);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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

  testWidgets('החלפת החלונית הפעילה אינה בונה מחדש את העמודה, '
      'ושינויי הכרטיסיות עצמן מתעדכנים בה', (tester) async {
    final right = _StubTab('ימין');
    final left = _StubTab('שמאל');
    final second = _StubTab('ספר ב');
    await pumpPanel(
      tester,
      withTabs: [
        CombinedTab(rightTab: right, leftTab: left),
        second,
      ],
    );

    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      var inStrip = element.widget is VerticalReadingTabStrip;
      element.visitAncestorElements((ancestor) {
        inStrip = inStrip || ancestor.widget is VerticalReadingTabStrip;
        return !inStrip;
      });
      if (inStrip) rebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    for (final pane in [left, right, left]) {
      tabsBloc.emitState(
        tabsBloc.state.copyWith(activePane: ActivePaneUpdate.set(pane)),
      );
      await tester.pumpAndSettle();
    }
    debugOnRebuildDirtyWidget = null;
    expect(identical(tabsBloc.state.activePane, left), isTrue);
    expect(rebuilds, 0, reason: 'שום דבר בעמודה אינו תלוי בחלונית הפעילה');

    Finder row(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_VerticalTabRow',
      ),
    );

    tabsBloc.emitState(tabsBloc.state.copyWith(currentTabIndex: 1));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: row('ספר ב'),
        matching: find.byTooltip('סגור כרטיסיה'),
      ),
      findsOneWidget,
      reason: 'הכרטיסיה הפעילה מציגה X',
    );
    Color? rowColor(String title) =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: row(title),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color;
    expect(
      rowColor('ספר ב'),
      AppSurfaces.topBarBackground(tester.element(row('ספר ב'))),
      reason: 'הפעילה בצבע הסרגל, כמו ברצועה האופקית (DD-06)',
    );
    expect(
      tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(ReadingTabsSidePanel),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color,
      AppSurfaces.readerBackground(tester.element(row('ספר ב'))),
      reason: 'רקע העמודה כרקע הרצועה האופקית, כדי שהריחוף ייראה אפור (q11 Q1)',
    );

    tabsBloc.emitState(tabsBloc.state.copyWith(selectedTabs: [second]));
    await tester.pumpAndSettle();
    expect(
      rowColor('ספר ב'),
      AppSurfaces.multiSelected(
        Theme.of(tester.element(row('ספר ב'))).colorScheme,
      ),
    );

    // שינוי שם והצמדה משנים את הכרטיסיה במקום ומסתמכים על forceUpdate.
    second.title = 'שם חדש';
    tabsBloc.emitState(tabsBloc.state.copyWith(forceUpdate: true));
    await tester.pumpAndSettle();
    expect(find.text('שם חדש'), findsOneWidget);

    tabsBloc.emitState(
      tabsBloc.state.copyWith(tabs: [...tabs, _StubTab('ספר נוסף')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('ספר נוסף'), findsOneWidget);
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

Rect _panelRect(WidgetTester tester) {
  final bounds = tester.getRect(find.byType(ReadingTabsSidePanel));
  final content = tester.getRect(find.byKey(const ValueKey('content')));
  return Rect.fromLTRB(content.right, bounds.top, bounds.right, bounds.bottom);
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
