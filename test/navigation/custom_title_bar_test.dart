import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/custom_title_bar.dart';
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
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('tooltip של TextBookTab כולל את כותרת המיקום בפועל',
      (tester) async {
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

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.byTooltip('ספר א, פרק א'), findsOneWidget);
  });

  testWidgets('אייקון pin מוצג כשהכרטיסיה מוצמדת', (tester) async {
    final tab = _makeTextTab('ספר א');
    tab.isPinned = true;
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

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.pin_24_filled,
      ),
      findsOneWidget,
    );
  });

  testWidgets('אייקון pin מוסתר כשהכרטיסיה אינה מוצמדת', (tester) async {
    final tab = _makeTextTab('ספר א');
    // isPinned = false כברירת מחדל
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

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.pin_24_filled,
      ),
      findsNothing,
    );
  });

  testWidgets('כרטיסיות אינן עטופות ב-SizedBox בעל רוחב קבוע', (tester) async {
    final tab1 = _makeTextTab('ספר קצר');
    final tab2 = _makeTextTab('ספר עם שם ארוך מאוד שנמשך הרחק');
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab1, tab2], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab1.dispose();
      tab2.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(900, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    // אין SizedBox בעל רוחב קבוע עוטף Listener (שימוש ב-tabWidth שהוסר)
    final fixedWidthBoxes = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((box) =>
            box.width != null &&
            box.width! >= 72 &&
            box.width! <= 200 &&
            box.child is Listener)
        .toList();

    expect(fixedWidthBoxes, isEmpty,
        reason: 'כרטיסיות צריכות להיות ברוחב טבעי, לא קבוע שוויוני');
  });

  testWidgets('CommentatorsTab לא מפיל את שורת הכותרת', (tester) async {
    final sourceTab = _makeTextTab('ספר א', currentTitle: 'פרק א');
    final tab = CommentatorsTab(sourceTab: sourceTab);
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose();
      sourceTab.dispose();
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
    });

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );

    expect(find.text('מפרשים | ספר א'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('בחירה וגרירת-סידור של טאבים', () {
    testWidgets('לחיצה על טאב שולחת SetCurrentTab עם האינדקס שלו',
        (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      // הבחירה מתבצעת ב-onPointerDown (Listener פסיבי), כך שקליק רגיל מספיק.
      // warnIfMissed:false כי ה-drag recognizer של ReorderableListView עשוי
      // לתפוס את ה-tap; pumpAndSettle מנקה את ה-timer של אנימציית הגרירה.
      await tester.tap(find.text('ספר ב'), warnIfMissed: false);
      await tester.pumpAndSettle();

      final selected = tabsBloc.addedEvents.whereType<SetCurrentTab>().toList();
      expect(selected, isNotEmpty,
          reason: 'לחיצה על טאב צריכה לשלוח SetCurrentTab');
      expect(selected.last.index, 1, reason: 'האינדקס הנבחר הוא של הטאב שנלחץ');
    });

    testWidgets('גרירת טאב בוחרת אותו (כמו כרום) ושולחת MoveTab לסידור מחדש',
        (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      // גרירת הטאב השני (אינדקס 1) לכיוון הטאב הראשון. ה-drag listener מיידי
      // (לא long-press), כך ש-startGesture + moveBy מתחילים reorder.
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ספר ב')));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(-150, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();

      // onReorderStart בוחר את הטאב הנגרר.
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>().map((e) => e.index),
        contains(1),
        reason: 'תחילת גרירה בוחרת את הטאב הנגרר (אינדקס 1)',
      );
      // onReorderItem שולח MoveTab עם הטאב הנכון.
      final moves = tabsBloc.addedEvents.whereType<MoveTab>().toList();
      expect(moves, isNotEmpty, reason: 'שחרור הגרירה צריך לשלוח MoveTab');
      expect(moves.last.tab, same(second),
          reason: 'הטאב שמועבר הוא הטאב שנגרר');
    });

    testWidgets('כשהטאבים גולשים מעבר לרוחב — חיצי הגלילה מופיעים בטעינה',
        (tester) async {
      // הרבה טאבים ברוחב מצומצם → overflow כבר בטעינה הראשונית, לפני כל גלילה.
      final tabs = List.generate(15, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      // pumpAndSettle מאפשר ל-ScrollMetricsNotification + ה-setState הדחוי
      // (post-frame) להציג את החיצים גם בלי שום אירוע גלילה.
      await tester.pumpAndSettle();

      // לפחות חץ אחד מופיע (הכיוון תלוי-RTL/מצב גלילה).
      final hasArrow = find
              .byIcon(FluentIcons.chevron_left_24_regular)
              .evaluate()
              .isNotEmpty ||
          find
              .byIcon(FluentIcons.chevron_right_24_regular)
              .evaluate()
              .isNotEmpty;
      expect(hasArrow, isTrue,
          reason: 'overflow של טאבים צריך להציג חיצי גלילה כבר בטעינה');
    });
  });

  group('סגירת טאב בלחיצה על כפתור ה-X', () {
    testWidgets('לחיצה על ה-X של טאב שאינו הנבחר סוגרת אותו (RemoveTab)',
        (tester) async {
      // התרחיש שבו הבאג הופיע: לחיצה על ה-X של טאב לא-נבחר בחרה אותו
      // (SetCurrentTab) וה-rebuild תחת ה-GlobalKey הנבחר הרס את ה-IconButton
      // לפני שה-onPressed שלו ירה — כך שהטאב התחלף במקום להיסגר.
      // _SelectingTabsBloc מדמה את אותו emit/rebuild בבחירה.
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _SelectingTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
        historyBloc: historyBloc,
      );

      final closeButton = find.descendant(
        of: find.ancestor(
          of: find.text('ספר ב'),
          matching: find.byType(Tab),
        ),
        matching: find.byIcon(FluentIcons.dismiss_24_regular),
      );
      expect(closeButton, findsOneWidget);

      // לחיצה (pointer-down) על ה-X של טאב לא-נבחר אסור שתבחר אותו: בחירה כאן
      // גורמת ל-rebuild תחת ה-GlobalKey הנבחר שמשמיד את ה-IconButton לפני
      // שה-onPressed שלו יורה — כך הטאב התחלף במקום להיסגר (שורש הבאג).
      final gesture = await tester.startGesture(tester.getCenter(closeButton));
      await tester.pump();
      expect(tabsBloc.addedEvents.whereType<SetCurrentTab>(), isEmpty,
          reason:
              'לחיצה על ה-X לא צריכה לבחור את הטאב (שתהרוס את כפתור הסגירה)');
      await gesture.up();
      await tester.pumpAndSettle();

      // ה-onPressed של ה-X מחובר לסגירה. נקרא ישירות כי ה-drag recognizer של
      // ReorderableListView בולע כל סימולציית tap ב-arena בסביבת הטסט.
      final iconButton = tester.widget<IconButton>(
        find.ancestor(of: closeButton, matching: find.byType(IconButton)),
      );
      iconButton.onPressed!();
      await tester.pump();

      final removed = tabsBloc.addedEvents.whereType<RemoveTab>().toList();
      expect(removed, isNotEmpty, reason: 'כפתור ה-X חייב לסגור את הטאב');
      expect(removed.last.tab, same(second),
          reason: 'הטאב שנסגר הוא הטאב שעל ה-X שלו נלחץ');
    });
  });

  group('גלילה אוטומטית לטאב הנבחר', () {
    testWidgets('בטעינה ראשונית עם טאב נבחר מחוץ לתצוגה — נגלל אליו',
        (tester) async {
      // הרבה טאבים שגולשים מעבר לרוחב, והטאב הנבחר הוא האחרון (מחוץ לתצוגה
      // ב-offset 0). ללא גלילה אוטומטית הוא היה נשאר גלול מחוץ לראייה.
      final tabs = List.generate(20, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 19),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      // שורת הטאבים נגללה מ-offset 0 כדי להראות את הטאב הנבחר.
      final scrollableFinder = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      final position =
          tester.state<ScrollableState>(scrollableFinder.first).position;
      expect(position.pixels, greaterThan(0),
          reason: 'הטאב הנבחר האחרון מחוץ לתצוגה צריך לגרום לגלילה');

      // והטאב הנבחר אכן רונדר (נכנס לתחום אחרי הגלילה).
      expect(find.text('ספר מספר 19'), findsOneWidget,
          reason: 'הטאב הנבחר צריך להיות גלוי אחרי הגלילה האוטומטית');
    });

    testWidgets('שינוי בחירה אחרי הטעינה הראשונית גם גורר גלילה',
        (tester) async {
      // מאמת שהמנגנון אינו חד-פעמי: גם rebuild עוקב (כאן — בחירת טאב אחר דרך
      // עדכון ה-state) מפעיל את הגלילה האוטומטית.
      final tabs = List.generate(20, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      // הטאב הראשון נבחר → אין גלילה בטעינה.
      expect(
          tester.state<ScrollableState>(scrollableFinder.first).position.pixels,
          0);

      // בחירת הטאב האחרון אחרי הטעינה.
      tabsBloc.emitState(TabsState(tabs: tabs, currentTabIndex: 19));
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(scrollableFinder.first).position.pixels,
        greaterThan(0),
        reason: 'בחירת טאב נסתר אחרי הטעינה צריכה לגלול אליו',
      );
    });

    testWidgets('כיווץ רוחב המסך (resize) שמוציא את הטאב הנבחר — נגלל אליו',
        (tester) async {
      // מסך רחב מאוד שבו כל הטאבים נכנסים; הטאב הנבחר האחרון נראה ללא גלילה.
      // כיווץ הרוחב יוצר overflow ומוציא אותו — ובלי תלות בשינוי אינדקס,
      // הגלילה האוטומטית צריכה להחזירו לתצוגה.
      final tabs = List.generate(15, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 14),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      tester.view.physicalSize = const Size(4000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // בנייה ברוחב מלא (ללא SizedBox קבוע) כדי ש-resize ישפיע על שורת הטאבים.
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CustomTitleBar(onReadingSettingsPressed: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      // ברוחב 4000 הכל נכנס — אין גלילה.
      expect(
          tester.state<ScrollableState>(scrollableFinder.first).position.pixels,
          0,
          reason: 'במסך רחב מאוד אין overflow');

      // כיווץ ל-900px (עדיין landscape) — נוצר overflow והטאב האחרון יוצא.
      tester.view.physicalSize = const Size(900, 800);
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(scrollableFinder.first).position.pixels,
        greaterThan(0),
        reason: 'כיווץ הרוחב מוציא את הטאב הנבחר → גלילה אוטומטית אליו',
      );
    });

    testWidgets(
        'חזרה למסך עיון אחרי יציאה — הטאב הנבחר נגלל לתצוגה גם ללא שינוי בחירה',
        (tester) async {
      // הטאב הנבחר היה גלוי, המשתמש עבר למסך אחר (שורת הטאבים יוצאת מהעץ
      // וה-ScrollController מאבד את ה-offset), וחזר למסך עיון — אותו state בדיוק.
      // ה-signature זהה ולכן לבדו אינו מפעיל גלילה; הטריגר על כניסה-מחדש לעץ
      // (hasClients) מחזיר את הטאב הנבחר לתצוגה.
      final tabs = List.generate(20, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 19),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      expect(
          tester.state<ScrollableState>(scrollableFinder.first).position.pixels,
          greaterThan(0));

      // יציאה למסך אחר וחזרה — אותו state, ללא שינוי בחירה. (settings ולא
      // library — library דורש LibraryBloc שאינו מסופק בטסט.)
      navigationBloc.emitScreen(Screen.settings);
      await tester.pumpAndSettle();
      navigationBloc.emitScreen(Screen.reading);
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(scrollableFinder.first).position.pixels,
        greaterThan(0),
        reason: 'בחזרה למסך עיון הטאב הנבחר צריך להיגלל שוב לתצוגה',
      );
    });

    testWidgets('טאב נבחר ראשון — אין גלילה מיותרת (נשאר ב-offset 0)',
        (tester) async {
      final tabs = List.generate(20, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      final position =
          tester.state<ScrollableState>(scrollableFinder.first).position;
      expect(position.pixels, 0,
          reason: 'הטאב הראשון כבר נראה — אין צורך לגלול');
    });
  });

  group('פריסת מסך צר (portrait) — טאבים בשורה תחתונה', () {
    testWidgets('landscape: הטאבים באותה שורה של כפתורי הפעולה',
        (tester) async {
      final tab = _makeTextTab('ספר א');
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

      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      final tabsBarSize = tester.getSize(find.byType(ReorderableListView));
      expect(tabsBarSize.height, lessThanOrEqualTo(40),
          reason: 'במצב רחב הטאבים בתוך שורת הכותרת 40px');

      final tabsTop = tester.getTopLeft(find.byType(ReorderableListView)).dy;
      expect(tabsTop, lessThan(40),
          reason: 'בלנדסקייפ הטאבים בשורה העליונה (y < 40)');
    });

    testWidgets('portrait: הטאבים בשורה תחתונה מתחת לשורת הכותרת',
        (tester) async {
      final tab = _makeTextTab('ספר א');
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

      await _setSurfaceSize(tester, const Size(400, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      final tabsTop = tester.getTopLeft(find.byType(ReorderableListView)).dy;
      expect(tabsTop, greaterThanOrEqualTo(40),
          reason:
              'ב-portrait הטאבים בשורה תחתונה (y ≥ 40, כי השורה העליונה היא 40)');
    });

    testWidgets('portrait: הטאבים מקבלים רוחב מלא ולא נדחסים', (tester) async {
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(400, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      final tabsBarWidth =
          tester.getSize(find.byType(ReorderableListView)).width;
      expect(tabsBarWidth, greaterThan(300),
          reason: 'בשורה התחתונה הטאבים מקבלים את הרוחב כמעט-מלא');
    });

    testWidgets('portrait בלי טאבים פתוחים: השורה התחתונה לא מופיעה',
        (tester) async {
      final tabsBloc = _TestTabsBloc(
        const TabsState(tabs: [], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      await _setSurfaceSize(tester, const Size(400, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      expect(find.byType(ReorderableListView), findsNothing);
    });
  });

  group('לחיצה כפולה: על טאב נבלעת, על האזור הריק עושה maximize', () {
    // DragToMoveArea (window_manager) עושה maximize/restore ב-onDoubleTap דרך
    // ה-MethodChannel 'window_manager' (isMaximized → maximize/unmaximize).
    // תופסים את הקריאות כדי לוודא שלחיצה כפולה על טאב אינה מגיעה לשם.
    // אוספים רק את פעולות שינוי-הגודל (maximize/unmaximize). את isMaximized
    // מתעלמים: WindowCaption (כפתורי החלון) קורא לו בכל build לבחירת האייקון,
    // והוא אינו מעיד על לחיצה כפולה.
    late List<String> resizeCalls;

    void installWindowChannelSpy(WidgetTester tester) {
      resizeCalls = [];
      const channel = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          if (call.method == 'maximize' || call.method == 'unmaximize') {
            resizeCalls.add(call.method);
          }
          if (call.method == 'isMaximized') return false;
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
    }

    testWidgets('לחיצה כפולה על טאב אינה משנה את גודל החלון', (tester) async {
      // שני טאבים, השני אינו הנבחר — כך לחיצה ראשונה משגרת SetCurrentTab
      // ו-rebuild בין שתי הלחיצות, התרחיש שבו הבליעה נכשלה בעבר (ה-recognizer
      // נהרס כשהוא ממוקם מתחת ל-GlobalKey של הטאב הנבחר).
      final first = _makeTextTab('ספר א');
      final second = _makeTextTab('ספר ב');
      final tabsBloc = _SelectingTabsBloc(
        TabsState(tabs: [first, second], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        first.dispose();
        second.dispose();
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      installWindowChannelSpy(tester);
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      await _doubleTapAt(tester, tester.getCenter(find.text('ספר ב')));

      expect(resizeCalls, isEmpty,
          reason: 'לחיצה כפולה על טאב לא צריכה לשנות את גודל החלון');
    });

    testWidgets('לחיצה כפולה על האזור הריק שבשורת הטאבים עושה maximize',
        (tester) async {
      // טאב יחיד קצר ברוחב גדול → אזור ריק נרחב בשורת הטאבים, שבו ה-DragToMoveArea
      // צריך לפעול כרגיל (maximize/restore).
      final tab = _makeTextTab('ספר א');
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

      installWindowChannelSpy(tester);
      await _setSurfaceSize(tester, const Size(1200, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );

      // נקודה ריקה: בקצה ה-ListView שרחוק מהטאב (עמיד לכיווניות LTR/RTL).
      final listRect = tester.getRect(find.byType(ReorderableListView));
      final tabRect = tester.getRect(find.text('ספר א'));
      final emptyX = tabRect.center.dx < listRect.center.dx
          ? listRect.right - 10
          : listRect.left + 10;
      await _doubleTapAt(tester, Offset(emptyX, listRect.center.dy));

      expect(resizeCalls, contains('maximize'),
          reason: 'לחיצה כפולה על אזור ריק צריכה לשנות את גודל החלון');
    });

    testWidgets('לחיצה כפולה על חץ גלילת הטאבים אינה משנה את גודל החלון',
        (tester) async {
      // הרבה טאבים ברוחב מצומצם → overflow וחיצי גלילה מופיעים. לחיצה כפולה על
      // חץ לא צריכה לבלוע ל-maximize (החץ מסומן כרכיב שורת הטאבים).
      final tabs = List.generate(15, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: tabs, currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());

      addTearDown(() async {
        for (final t in tabs) {
          t.dispose();
        }
        await tabsBloc.close();
        await navigationBloc.close();
        await settingsBloc.close();
      });

      installWindowChannelSpy(tester);
      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      final arrow =
          find.byIcon(FluentIcons.chevron_left_24_regular).evaluate().isNotEmpty
              ? find.byIcon(FluentIcons.chevron_left_24_regular)
              : find.byIcon(FluentIcons.chevron_right_24_regular);
      expect(arrow, findsWidgets, reason: 'overflow צריך להציג חץ גלילה');

      await _doubleTapAt(tester, tester.getCenter(arrow.first));

      expect(resizeCalls, isEmpty,
          reason: 'לחיצה כפולה על חץ גלילה לא צריכה לשנות את גודל החלון');
    });
  });
}

/// לחיצה כפולה במיקום נתון: שתי הקשות עם השהיה תקפה ל-double-tap, ואז המתנה
/// להשלמת ה-onDoubleTap (שהוא async ב-DragToMoveArea).
Future<void> _doubleTapAt(WidgetTester tester, Offset pos) async {
  await tester.tapAt(pos);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(pos);
  await tester.pumpAndSettle();
}

Future<void> _pumpTitleBar(
  WidgetTester tester, {
  required TabsBloc tabsBloc,
  required NavigationBloc navigationBloc,
  required SettingsBloc settingsBloc,
  HistoryBloc? historyBloc,
}) async {
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
        if (historyBloc != null)
          BlocProvider<HistoryBloc>.value(value: historyBloc),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: CustomTitleBar(
              onReadingSettingsPressed: () {},
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
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

  final tab = TextBookTab(
    book: book,
    index: 0,
    blocOverride: bloc,
  );
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

  /// מתעד את כל ה-events שנשלחו, לבדיקת בחירה/סידור-מחדש של טאבים.
  final List<TabsEvent> addedEvents = [];

  /// מאפשר לטסט לדמות שינוי מצב (בחירה/החלפת רשימת טאבים) אחרי הטעינה.
  void emitState(TabsState state) => emit(state);

  @override
  void add(TabsEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// כמו [_TestTabsBloc], אך SetCurrentTab גם מעדכן את ה-state (emit) — כדי לדמות
/// את ה-rebuild שמתרחש בבחירת טאב, התרחיש שבו בליעת הלחיצה הכפולה נכשלה בעבר.
class _SelectingTabsBloc extends _TestTabsBloc {
  _SelectingTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {
    super.add(event);
    if (event is SetCurrentTab) {
      emit(TabsState(tabs: state.tabs, currentTabIndex: event.index));
    }
  }
}

class _TestNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState);

  /// מאפשר לטסט לדמות מעבר מסך (למשל library → reading).
  void emitScreen(Screen screen) =>
      emit(NavigationState(currentScreen: screen));

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

class _TestHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _TestHistoryBloc() : super(HistoryInitial());

  @override
  void add(HistoryEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
