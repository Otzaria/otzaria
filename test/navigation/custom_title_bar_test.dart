import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
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

  testWidgets('tooltip של TextBookTab כולל את כותרת המיקום בפועל', (
    tester,
  ) async {
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

  testWidgets('כרטיסיות מקבלות רוחב קבוע שווה, חסום בתקרה (~140px)', (
    tester,
  ) async {
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

    await _setSurfaceSize(tester, const Size(1200, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
    );
    await tester.pumpAndSettle();

    // כל טאב עטוף ב-SizedBox ברוחב המחושב (ילדו ה-Listener של _buildTab); שני
    // הטאבים זהים וחסומים בתקרה (140px) — לא רוחב טבעי לפי אורך הכותרת.
    final widths = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(ReorderableListView),
            matching: find.byType(SizedBox),
          ),
        )
        .where((b) => b.width != null && b.child is Listener)
        .map((b) => b.width!)
        .toList();

    expect(widths.length, 2, reason: 'שני טאבים → שני SizedBox ברוחב קבוע');
    expect(
      widths[0],
      moreOrLessEquals(widths[1], epsilon: 1.0),
      reason: 'כל הטאבים ברוחב קבוע שווה',
    );
    expect(
      widths[0],
      lessThanOrEqualTo(141.0),
      reason: 'רוחב הטאב חסום בתקרה (~140px) גם כשיש מקום',
    );
  });

  testWidgets('כותרת ארוכה נחתכת בדהייה (TextOverflow.fade) ללא שלוש נקודות', (
    tester,
  ) async {
    const longTitle = 'ספר עם שם ארוך מאוד שנמשך הרחק אל מעבר לרוחב הטאב';
    final tab = _makeTextTab(longTitle);
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

    // הכותרת המלאה מרונדרת (לא קוצרה ל-...) בשורה אחת.
    final titleText = tester.widget<Text>(find.text(longTitle));
    expect(titleText.maxLines, 1);
    expect(titleText.softWrap, false);
    // הדהייה בקצה הסוף נעשית ע"י ShaderMask עוטף (לא TextOverflow.fade, שמציג
    // בעברית את סוף הכותרת במקום ההתחלה).
    expect(
      find.ancestor(
        of: find.text(longTitle),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('...'),
      findsNothing,
      reason: 'אין שלוש נקודות — חיתוך בדהייה כמו כרום',
    );
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
    // רק טאב-PDF מקבל אייקון-סוג; בטאב מפרשים אין אייקון מוביל.
    expect(find.byIcon(FluentIcons.book_24_regular), findsNothing);
    expect(find.byIcon(FluentIcons.document_pdf_16_regular), findsNothing);
  });

  testWidgets('טאב PDF רחב מציג אייקון PDF ליד שם הספר', (tester) async {
    final tab = _makePdfTab('ספר PDF');
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

    expect(find.byIcon(FluentIcons.document_pdf_16_regular), findsOneWidget);
  });

  testWidgets('טאב PDF צר (רוחב < 100) מסתיר את אייקון ה-PDF', (tester) async {
    // הרבה טאבים ב-surface צר מצמצמים כל טאב מתחת ל-100px — האייקון נעלם.
    final tabs = List.generate(10, (i) => _makePdfTab('ספר $i'));
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: tabs, currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      for (final tab in tabs) {
        tab.dispose();
      }
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

    expect(find.byIcon(FluentIcons.document_pdf_16_regular), findsNothing);
  });

  testWidgets('CombinedTab מציג את התחלת שני הספרים, כל אחד בחצי', (
    tester,
  ) async {
    final right = _makeTextTab('תרגום אונקלוס על שמות');
    final left = _makeTextTab('רש"י על בראשית פרשת ויחי');
    final tab = CombinedTab(rightTab: right, leftTab: left);
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      tab.dispose(); // מפנה גם את right ו-left
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

    // שני הספרים מרונדרים בנפרד (כל אחד ב-Expanded משלו עם ShaderMask לדהייה),
    // ולא כמחרוזת "משולב:" מאוחדת אחת.
    expect(find.text('תרגום אונקלוס על שמות'), findsOneWidget);
    expect(find.text('רש"י על בראשית פרשת ויחי'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('תרגום אונקלוס על שמות'),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('רש"י על בראשית פרשת ויחי'),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('משולב:'),
      findsNothing,
      reason: 'בטאב מוצגים שני החצאים, לא מחרוזת מאוחדת',
    );

    // פס מפריד (2×14) בין שני החצאים בטאב רחב.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 2 &&
            w.constraints?.maxHeight == 14,
      ),
      findsOneWidget,
      reason: 'יש פס מפריד בין שני הספרים בטאב המפוצל',
    );
  });

  group('בחירה וגרירת-סידור של טאבים', () {
    testWidgets('לחיצה על טאב שולחת SetCurrentTab עם האינדקס שלו', (
      tester,
    ) async {
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
      expect(
        selected,
        isNotEmpty,
        reason: 'לחיצה על טאב צריכה לשלוח SetCurrentTab',
      );
      expect(selected.last.index, 1, reason: 'האינדקס הנבחר הוא של הטאב שנלחץ');
    });

    testWidgets('גרירת טאב בוחרת אותו (כמו כרום) ושולחת MoveTab לסידור מחדש', (
      tester,
    ) async {
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
      await tester.pumpAndSettle();

      // הבחירה מתבצעת ב-onPointerDown — תחילת גרירה (כמו לחיצה) בוחרת את הטאב.
      await tester.tap(find.text('ספר ב'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>().map((e) => e.index),
        contains(1),
        reason: 'תחילת גרירה בוחרת את הטאב הנגרר (אינדקס 1)',
      );

      // סימולציית long-press multidrag של ReorderableListView אינה אמינה בבדיקת
      // widget (recognizers של תפריט ההקשר/הגלילה מתחרים ב-arena). בודקים ישירות
      // את לוגיקת האפליקציה: onReorderItem ממפה oldIndex→טאב ושולח MoveTab.
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorderItem!(1, 0);
      await tester.pump();

      final moves = tabsBloc.addedEvents.whereType<MoveTab>().toList();
      expect(moves, isNotEmpty, reason: 'reorder צריך לשלוח MoveTab');
      expect(
        moves.last.tab,
        same(second),
        reason: 'הטאב שמועבר הוא הטאב שנגרר',
      );
      expect(moves.last.newIndex, 0, reason: 'היעד הוא אינדקס 0');
    });

    testWidgets(
      'בדסקטופ הטאבים עטופים ב-listener מיידי (גרירה מסדרת מיד)',
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

        // ReorderableDelayedDragStartListener יורש מ-ReorderableDragStartListener,
        // לכן בודקים את runtimeType בדיוק: בדסקטופ המיידי, ללא ה-Delayed.
        expect(
          find.byWidgetPredicate(
            (w) => w.runtimeType == ReorderableDragStartListener,
          ),
          findsOneWidget,
        );
        expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'בנייד הטאבים עטופים ב-listener מושהה (long-press)',
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

        expect(
          find.byType(ReorderableDelayedDragStartListener),
          findsOneWidget,
        );
      },
      variant: TargetPlatformVariant.mobile(),
    );

    testWidgets('הרבה טאבים מצטמצמים והכפתור X מתחבא בטאב צר, ללא חיצי גלילה', (
      tester,
    ) async {
      // ביטול הגלילה: הרבה טאבים מתכווצים, וכשהם צרים מ-80px כפתור ה-X מתחבא
      // (מופיע ב-hover/בנבחר) כדי שהם ימשיכו להצטמצם ויישארו נגישים.
      final tabs = List.generate(10, (i) => _makeTextTab('ספר מספר $i'));
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

      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsNothing);
      expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);

      // הטאבים התכווצו אל מתחת ל-80 (אזור הסתרת ה-X) — בלי רצפה ובלי גלילה.
      final widths = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ReorderableListView),
              matching: find.byType(SizedBox),
            ),
          )
          .where((b) => b.width != null && b.child is Listener)
          .map((b) => b.width!)
          .toList();
      expect(widths, isNotEmpty);
      expect(widths.first, greaterThan(0));
      expect(widths.first, lessThan(80.0));

      // בטאבים צרים כפתורי ה-X מתחבאים — פחות כפתורי סגירה ממספר הטאבים.
      final closeButtons = find
          .byIcon(FluentIcons.dismiss_24_regular)
          .evaluate()
          .length;
      expect(
        closeButtons,
        lessThan(tabs.length),
        reason: 'X מתחבא בטאבים צרים שאינם נבחרים/תחת hover',
      );
    });

    testWidgets('בצפיפות הטאב הנבחר שומר רוחב מזערי וכפתור ה-X שלו נשאר', (
      tester,
    ) async {
      // 20 טאבים ברוחב 900 → החלוקה השווה צונחת מתחת לרוחב שמכיל את ה-X. הטאב
      // הנבחר חייב לשמור רוחב מזערי (60px) כך שה-X שלו לא ייעלם, והשאר
      // מתחלקים ביתרה — עדיין ללא חיתוך וללא גלילה.
      final tabs = List.generate(20, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
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

      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      final widths = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ReorderableListView),
              matching: find.byType(SizedBox),
            ),
          )
          .where((b) => b.width != null && b.child is Listener)
          .map((b) => b.width!)
          .toList();
      expect(widths.length, 20);
      expect(
        widths.first,
        moreOrLessEquals(60.0, epsilon: 1.0),
        reason: 'הטאב הנבחר (אינדקס 0) שומר רוחב מזערי של 60px',
      );
      expect(
        widths[1],
        lessThan(widths.first),
        reason: 'שאר הטאבים צרים מהנבחר — מתחלקים ביתרה',
      );

      final sumWidth = widths.fold<double>(0, (a, b) => a + b);
      final listWidth = tester.getSize(find.byType(ReorderableListView)).width;
      expect(
        sumWidth,
        lessThanOrEqualTo(listWidth + 1.0),
        reason: 'גם עם הרצפה לנבחר — הכול נכנס ללא חיתוך',
      );

      // כפתור ה-X קיים בתוך הטאב הנבחר גם בצפיפות הזו.
      final selectedClose = find.descendant(
        of: find.ancestor(
          of: find.text('ספר מספר 0'),
          matching: find.byType(Tab),
        ),
        matching: find.byIcon(FluentIcons.dismiss_24_regular),
      );
      expect(
        selectedClose,
        findsOneWidget,
        reason: 'לטאב הנבחר תמיד יש כפתור סגירה, גם כשהשורה צפופה',
      );
    });

    testWidgets('מספר טאבים גדול — כולם נכנסים ללא חיתוך וללא גלילה', (
      tester,
    ) async {
      // ללא רצפת רוחב וללא גלילה: סכום רוחבי הטאבים לא חורג מהרוחב הזמין, כך
      // שאף טאב אינו נחתך/בלתי-נגיש (התיקון לרגרסיה של מנגנון הגלילה שהוסר).
      final tabs = List.generate(30, (i) => _makeTextTab('ספר מספר $i'));
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));
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

      await _setSurfaceSize(tester, const Size(900, 800));
      await _pumpTitleBar(
        tester,
        tabsBloc: tabsBloc,
        navigationBloc: navigationBloc,
        settingsBloc: settingsBloc,
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsNothing);
      expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);

      final widths = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ReorderableListView),
              matching: find.byType(SizedBox),
            ),
          )
          .where((b) => b.width != null && b.child is Listener)
          .map((b) => b.width!)
          .toList();
      expect(widths.length, 30, reason: 'כל 30 הטאבים רונדרו');
      final sumWidth = widths.fold<double>(0, (a, b) => a + b);
      final listWidth = tester.getSize(find.byType(ReorderableListView)).width;
      expect(
        sumWidth,
        lessThanOrEqualTo(listWidth + 1.0),
        reason: 'סכום רוחבי הטאבים נכנס ברוחב הזמין — אין חיתוך',
      );
    });
  });

  group('בחירה מרובה של כרטיסיות (Ctrl/Shift/Cmd+לחיצה)', () {
    late TextBookTab first;
    late TextBookTab second;
    late TextBookTab third;
    late _TestTabsBloc tabsBloc;
    late _TestHistoryBloc historyBloc;

    Future<void> pumpWithTabs(
      WidgetTester tester, {
      List<TextBookTab> selected = const [],
    }) async {
      first = _makeTextTab('ספר א');
      second = _makeTextTab('ספר ב');
      third = _makeTextTab('ספר ג');
      tabsBloc = _TestTabsBloc(
        TabsState(
          tabs: [first, second, third],
          currentTabIndex: 0,
          selectedTabs: selected,
        ),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        first.dispose();
        second.dispose();
        third.dispose();
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
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+לחיצה שולחת ToggleTabSelection ולא מחליפה טאב', (
      tester,
    ) async {
      await pumpWithTabs(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('ספר ב'), warnIfMissed: false);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final toggles = tabsBloc.addedEvents
          .whereType<ToggleTabSelection>()
          .toList();
      expect(toggles, hasLength(1));
      expect(toggles.single.tab, same(second));
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>(),
        isEmpty,
        reason: 'Ctrl+לחיצה בוחרת לקבוצה ואינה מחליפה את הטאב הפעיל',
      );
    });

    testWidgets('Shift+לחיצה שולחת SelectTabRange', (tester) async {
      await pumpWithTabs(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('ספר ג'), warnIfMissed: false);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      final ranges = tabsBloc.addedEvents.whereType<SelectTabRange>().toList();
      expect(ranges, hasLength(1));
      expect(ranges.single.tab, same(third));
      expect(tabsBloc.addedEvents.whereType<SetCurrentTab>(), isEmpty);
    });

    testWidgets(
      'במק: Command+לחיצה שולחת ToggleTabSelection',
      (tester) async {
        await pumpWithTabs(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.tap(find.text('ספר ב'), warnIfMissed: false);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        final toggles = tabsBloc.addedEvents
            .whereType<ToggleTabSelection>()
            .toList();
        expect(toggles, hasLength(1));
        expect(toggles.single.tab, same(second));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    testWidgets('לחיצה רגילה מנקה בחירה קיימת ומחליפה טאב', (tester) async {
      await pumpWithTabs(tester);
      tabsBloc.emitState(
        TabsState(
          tabs: [first, second, third],
          currentTabIndex: 0,
          selectedTabs: [first, second],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ספר ג'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        tabsBloc.addedEvents.whereType<ClearTabSelection>(),
        hasLength(1),
      );
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>().last.index,
        2,
      );
    });

    testWidgets('לחיצה על ה-X של כרטיסיה נבחרת סוגרת את כל הקבוצה', (
      tester,
    ) async {
      await pumpWithTabs(tester);
      tabsBloc.emitState(
        TabsState(
          tabs: [first, second, third],
          currentTabIndex: 0,
          selectedTabs: [first, second],
        ),
      );
      await tester.pumpAndSettle();

      // סימולציית tap נבלעת ע"י ה-reorder recognizer — קוראים ל-onPressed ישירות.
      final closeButton = find.descendant(
        of: find.ancestor(of: find.text('ספר א'), matching: find.byType(Tab)),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(closeButton).onPressed!();
      await tester.pump();

      final removals = tabsBloc.addedEvents.whereType<RemoveTabs>().toList();
      expect(removals, hasLength(1));
      expect(removals.single.tabs, [first, second]);
      expect(
        tabsBloc.addedEvents.whereType<RemoveTab>(),
        isEmpty,
        reason: 'סגירת חבר בקבוצה סוגרת את כולה, לא כרטיסיה בודדת',
      );
      // ההיסטוריה נשלחת באירוע קבוצתי אחד — לא אירועי AddHistory מקביליים.
      final historyEvents = historyBloc.addedEvents
          .whereType<AddHistoryForTabs>()
          .toList();
      expect(historyEvents, hasLength(1));
      expect(historyEvents.single.tabs, [first, second]);
      expect(historyBloc.addedEvents.whereType<AddHistory>(), isEmpty);
    });

    testWidgets('כרטיסיות נבחרות מסומנות ברקע (painter)', (tester) async {
      await pumpWithTabs(tester);
      tabsBloc.emitState(
        TabsState(
          tabs: [first, second, third],
          currentTabIndex: 0,
          selectedTabs: [second, third],
        ),
      );
      await tester.pumpAndSettle();

      // הנבחרות (2) + הפעילה (1) מצוירות ברקע טאב; ללא בחירה רק הפעילה.
      final paintedTabs = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(ReorderableListView),
              matching: find.byType(CustomPaint),
            ),
          )
          .where(
            (w) => w.painter.runtimeType.toString() == '_TabBackgroundPainter',
          )
          .length;
      expect(paintedTabs, 3);
    });
  });

  group('סגירת טאב בלחיצה על כפתור ה-X', () {
    testWidgets('לחיצה על ה-X סוגרת מיד — בלי המתנה ל-timeout של לחיצה כפולה', (
      tester,
    ) async {
      // רגרסיה: מזהה הלחיצה הכפולה (maximize על האזור הריק) החזיק את
      // ה-gesture arena על כל השורה, וה-X הגיב רק אחרי ~300ms. המזהה חייב
      // לדחות מצביעים שמעל טאב, כך שה-RemoveTab נשלח מיד בשחרור הלחיצה.
      final tab = _makeTextTab('ספר א');
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final navigationBloc = _TestNavigationBloc(
        const NavigationState(currentScreen: Screen.reading),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final historyBloc = _TestHistoryBloc();

      addTearDown(() async {
        tab.dispose();
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

      final closeButton = find.byIcon(FluentIcons.dismiss_24_regular);
      expect(closeButton, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(closeButton));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      // pump ללא קידום שעון: אסור שהסגירה תחכה ל-timer של הלחיצה הכפולה.
      await tester.pump();

      expect(
        tabsBloc.addedEvents.whereType<RemoveTab>(),
        isNotEmpty,
        reason: 'ה-X חייב לסגור מיד בשחרור הלחיצה, ללא השהיית arena',
      );
    });

    testWidgets('לחיצה על ה-X של טאב שאינו הנבחר סוגרת אותו (RemoveTab)', (
      tester,
    ) async {
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
      expect(
        tabsBloc.addedEvents.whereType<SetCurrentTab>(),
        isEmpty,
        reason: 'לחיצה על ה-X לא צריכה לבחור את הטאב (שתהרוס את כפתור הסגירה)',
      );
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
      expect(
        removed.last.tab,
        same(second),
        reason: 'הטאב שנסגר הוא הטאב שעל ה-X שלו נלחץ',
      );
    });
  });

  testWidgets('סגירת טאב כשהעכבר בשורה שומרת על רוחב הטאבים (לא מתרחבים)', (
    tester,
  ) async {
    // 6 טאבים ברוחב צר (מתחת לתקרה) — סגירה רגילה תרחיב את הנותרים. כל עוד
    // העכבר בשורה הרוחב אמור להישאר קפוא כדי שה-X של הטאב הבא יישאר תחת הסמן.
    final tabs = List.generate(6, (i) => _makeTextTab('ספר מספר $i'));
    final tabsBloc = _ClosingTabsBloc(
      TabsState(tabs: tabs, currentTabIndex: 0),
    );
    final navigationBloc = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final historyBloc = _TestHistoryBloc();

    addTearDown(() async {
      for (final t in tabs) {
        t.dispose();
      }
      await tabsBloc.close();
      await navigationBloc.close();
      await settingsBloc.close();
      await historyBloc.close();
    });

    await _setSurfaceSize(tester, const Size(700, 800));
    await _pumpTitleBar(
      tester,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      settingsBloc: settingsBloc,
      historyBloc: historyBloc,
    );
    await tester.pumpAndSettle();

    List<double> tabWidths() => tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(ReorderableListView),
            matching: find.byType(SizedBox),
          ),
        )
        .where((b) => b.width != null && b.child is Listener)
        .map((b) => b.width!)
        .toList();

    final widthBefore = tabWidths().first;

    // מביאים את העכבר אל מרכז השורה (hover) — כך _pointerInsideTabStrip=true.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(ReorderableListView)),
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    // סוגרים טאב דרך ה-onPressed של ה-X (סימולציית tap נבלעת ע"י ה-reorder
    // recognizer בסביבת הטסט, ולכן קוראים ישירות).
    void closeTabByTitle(String title) {
      final closeButton = find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(Tab)),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(closeButton).onPressed!();
    }

    closeTabByTitle('ספר מספר 2');
    await tester.pumpAndSettle();
    expect(
      tabWidths().first,
      moreOrLessEquals(widthBefore, epsilon: 1.0),
      reason: 'סגירה ראשונה: הרוחב נשאר קפוא',
    );

    // סגירה רצופה שנייה — הרוחב חייב להישאר קפוא על אותו ערך, לא להתרחב מחדש.
    closeTabByTitle('ספר מספר 3');
    await tester.pumpAndSettle();

    expect(tabWidths().length, 4, reason: 'שני טאבים נסגרו');
    expect(
      tabWidths().first,
      moreOrLessEquals(widthBefore, epsilon: 1.0),
      reason: 'בסגירות רצופות הרוחב נשאר קפוא על הערך המקורי ולא מתרחב',
    );
  });

  group('פריסת מסך צר (portrait) — טאבים בשורה תחתונה', () {
    testWidgets('landscape: הטאבים באותה שורה של כפתורי הפעולה', (
      tester,
    ) async {
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
      expect(
        tabsBarSize.height,
        lessThanOrEqualTo(40),
        reason: 'במצב רחב הטאבים בתוך שורת הכותרת 40px',
      );

      final tabsTop = tester.getTopLeft(find.byType(ReorderableListView)).dy;
      expect(
        tabsTop,
        lessThan(40),
        reason: 'בלנדסקייפ הטאבים בשורה העליונה (y < 40)',
      );
    });

    testWidgets('portrait: הטאבים בשורה תחתונה מתחת לשורת הכותרת', (
      tester,
    ) async {
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
      expect(
        tabsTop,
        greaterThanOrEqualTo(40),
        reason:
            'ב-portrait הטאבים בשורה תחתונה (y ≥ 40, כי השורה העליונה היא 40)',
      );
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

      final tabsBarWidth = tester
          .getSize(find.byType(ReorderableListView))
          .width;
      expect(
        tabsBarWidth,
        greaterThan(300),
        reason: 'בשורה התחתונה הטאבים מקבלים את הרוחב כמעט-מלא',
      );
    });

    testWidgets('portrait בלי טאבים פתוחים: השורה התחתונה לא מופיעה', (
      tester,
    ) async {
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
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
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

      expect(
        resizeCalls,
        isEmpty,
        reason: 'לחיצה כפולה על טאב לא צריכה לשנות את גודל החלון',
      );
    });

    testWidgets('לחיצה כפולה על האזור הריק שבשורת הטאבים עושה maximize', (
      tester,
    ) async {
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

      expect(
        resizeCalls,
        contains('maximize'),
        reason: 'לחיצה כפולה על אזור ריק צריכה לשנות את גודל החלון',
      );
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

PdfBookTab _makePdfTab(String title) {
  return PdfBookTab(
    book: PdfBook(title: title, path: '$title.pdf'),
    pageNumber: 1,
  );
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

/// מסיר טאב בפועל ב-RemoveTab — לבדיקת קפיאת רוחב הטאבים בסגירה.
class _ClosingTabsBloc extends _TestTabsBloc {
  _ClosingTabsBloc(super.initialState);

  @override
  void add(TabsEvent event) {
    super.add(event);
    if (event is RemoveTab) {
      final newTabs = state.tabs.where((t) => t != event.tab).toList();
      emit(TabsState(tabs: newTabs, currentTabIndex: 0));
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

  /// מתעד את אירועי ההיסטוריה שנשלחו, לבדיקת סגירה קבוצתית.
  final List<HistoryEvent> addedEvents = [];

  @override
  void add(HistoryEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
