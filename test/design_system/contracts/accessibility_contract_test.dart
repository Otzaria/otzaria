import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/search_result_navigator.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';
import 'package:otzaria/widgets/navigation/nav_rail_item.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';
import 'package:otzaria/widgets/navigation/sidebar_nav_item.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

import 'contract_harness.dart';

/// הצומת הסמנטי שמכיל את [finder] אחרי מיזוג.
SemanticsNode _node(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder);

void main() {
  group('NavTreeTile', () {
    testWidgets('שורה נבחרת ומורחבת: selected ו-expanded', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInApp(
        tester,
        NavTreeTile.category(
          title: 'תנ"ך',
          level: 0,
          isSelected: true,
          isExpanded: true,
          hasChildren: true,
          onTap: () {},
          onToggleExpand: () {},
        ),
      );
      final node = _node(tester, find.text('תנ"ך'));
      expect(node, isSemantics(isSelected: true));
      expect(node, isSemantics(hasExpandedState: true));
      expect(node, isSemantics(isExpanded: true));
      handle.dispose();
    });

    testWidgets('המצב expanded נקרא בשורה בלבד, לא שוב בכפתור החץ', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpInApp(
        tester,
        NavTreeTile.category(
          title: 'תנ"ך',
          level: 0,
          isExpanded: true,
          hasChildren: true,
          onTap: () {},
          onToggleExpand: () {},
        ),
      );
      final row = _node(tester, find.text('תנ"ך'));
      final button = _node(tester, find.byType(IconButton));
      expect(button.id, isNot(row.id));
      expect(row, isSemantics(hasExpandedState: true, isExpanded: true));
      expect(button, isSemantics(hasExpandedState: false, tooltip: 'כווץ'));
      handle.dispose();
    });

    testWidgets('לכפתור הצ\'בֺרן יש tooltip לפי המצב', (tester) async {
      await pumpInApp(
        tester,
        NavTreeTile.category(
          title: 'תנ"ך',
          level: 0,
          hasChildren: true,
          onToggleExpand: () {},
        ),
      );
      expect(find.byTooltip('הרחב'), findsOneWidget);
    });

    testWidgets('שורה בלי ילדים אינה מדווחת expanded', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInApp(
        tester,
        NavTreeTile.book(title: 'בראשית', level: 1, onTap: () {}),
      );
      final node = _node(tester, find.text('בראשית'));
      expect(node, isSemantics(hasExpandedState: false));
      expect(node, isSemantics(isSelected: false));
      handle.dispose();
    });
  });

  testWidgets('ExpandingChevron מוסר את המצב לכפתור שמכיל אותו', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInApp(
      tester,
      IconButton(
        tooltip: 'פתח',
        onPressed: () {},
        icon: const ExpandingChevron(isExpanded: false),
      ),
    );
    final node = _node(tester, find.byType(IconButton));
    expect(node, isSemantics(hasExpandedState: true));
    expect(node, isSemantics(isExpanded: false));
    handle.dispose();
  });

  group('PanelTabHeader', () {
    Widget header({required bool showLabel}) => DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => PanelTabHeader(
          controller: DefaultTabController.of(context),
          onClose: () {},
          tabs: [
            PanelTab(
              icon: FluentIcons.note_24_regular,
              label: 'הערות',
              showLabel: showLabel,
            ),
            PanelTab(
              icon: FluentIcons.link_24_regular,
              label: 'קישורים',
              showLabel: showLabel,
            ),
          ],
        ),
      ),
    );

    testWidgets('לכפתור הסגירה יש tooltip', (tester) async {
      await pumpInApp(tester, header(showLabel: true));
      expect(find.byTooltip('סגור חלונית'), findsOneWidget);
    });

    testWidgets('לשונית אייקון בלבד: התווית עוברת ל-tooltip', (tester) async {
      await pumpInApp(tester, header(showLabel: false));
      expect(find.text('הערות'), findsNothing);
      expect(find.byTooltip('הערות'), findsOneWidget);
      expect(find.byTooltip('קישורים'), findsOneWidget);
    });
  });

  group('PanelOpenHandle', () {
    testWidgets('כפתור עם שם, מקבל פוקוס ונפתח ב-Enter', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpInApp(tester, PanelOpenHandle(onTap: () => taps++));
      final node = _node(tester, find.byType(PanelOpenHandle));
      expect(node, isSemantics(isButton: true));
      expect(node.getSemanticsData().label, 'הצג מפרשים');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);

      await tester.tap(find.byType(PanelOpenHandle));
      await tester.pump();
      expect(taps, 2);
      handle.dispose();
    });
  });

  group('OtzariaSearchAction', () {
    testWidgets('קודם/הבא/נקה: לכל כפתור tooltip', (tester) async {
      await pumpInApp(
        tester,
        Row(
          children: [
            SearchResultNavigator(onPrevious: () {}, onNext: () {}),
            OtzariaSearchAction.clear(onPressed: () {}),
          ],
        ),
      );
      expect(find.byTooltip('תוצאה קודמת'), findsOneWidget);
      expect(find.byTooltip('תוצאה הבאה'), findsOneWidget);
      expect(find.byTooltip('נקה'), findsOneWidget);
    });
  });

  testWidgets('UiSnack מכריז על ההודעה לקורא מסך', (tester) async {
    addTearDown(UiSnack.hide);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    UiSnack.showError('הקובץ לא נמצא');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final error = tester.takeAnnouncements();
    expect(error, hasLength(1));
    expect(error.single.message, 'הקובץ לא נמצא');
    expect(error.single.assertiveness, Assertiveness.assertive);

    UiSnack.show('נשמר');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final info = tester.takeAnnouncements();
    expect(info.single.message, 'נשמר');
    expect(info.single.assertiveness, Assertiveness.polite);
    UiSnack.hide();
    await tester.pumpAndSettle();
  });

  group('AppDropdownField', () {
    testWidgets('labelText מוצג מעל הכפתור ונקרא יחד עמו', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpInApp(
        tester,
        SizedBox(
          width: 200,
          child: AppDropdownField<int>(
            value: 0,
            decoration: const InputDecoration(labelText: 'מיון'),
            entries: const [AppMenuEntry(value: 0, label: 'רלוונטיות')],
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.text('מיון'), findsOneWidget);
      final labelTop = tester.getTopLeft(find.text('מיון')).dy;
      final buttonTop = tester.getTopLeft(find.byType(FilledButton)).dy;
      expect(labelTop, lessThan(buttonTop));
      final node = _node(tester, find.byType(FilledButton));
      expect(node.getSemanticsData().label, contains('מיון'));
      expect(node.getSemanticsData().label, contains('רלוונטיות'));
      handle.dispose();
    });

    testWidgets('semanticLabel: שם נגיש ו-tooltip בלי תווית גלויה', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpInApp(
        tester,
        SizedBox(
          width: 200,
          child: AppDropdownField<int>(
            value: 0,
            semanticLabel: 'מיון',
            entries: const [AppMenuEntry(value: 0, label: 'רלוונטיות')],
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.text('מיון'), findsNothing);
      expect(find.byTooltip('מיון'), findsOneWidget);
      final node = _node(tester, find.byType(FilledButton));
      expect(node.getSemanticsData().label, contains('מיון'));
      expect(node.getSemanticsData().label, contains('רלוונטיות'));
      handle.dispose();
    });

    testWidgets('בלי labelText אין תווית נוספת', (tester) async {
      await pumpInApp(
        tester,
        SizedBox(
          width: 200,
          child: AppDropdownField<int>(
            value: 0,
            entries: const [AppMenuEntry(value: 0, label: 'רלוונטיות')],
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.byType(Column), findsNothing);
    });
  });

  testWidgets('SidebarNavItem נבחר: selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInApp(
      tester,
      SidebarNavItem(
        icon: FluentIcons.settings_24_regular,
        label: 'מראה',
        isSelected: true,
        onTap: () {},
      ),
    );
    final node = _node(tester, find.text('מראה'));
    expect(node, isSemantics(isSelected: true));
    handle.dispose();
  });

  testWidgets('NavRailItem: התווית היא השם הנגיש, והנבחר מסומן', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInApp(
      tester,
      NavRailItem(
        icon: FluentIcons.library_24_regular,
        label: 'ספרייה',
        isSelected: true,
        onTap: () {},
      ),
    );
    final node = _node(tester, find.byType(IconButton));
    expect(node.getSemanticsData().label, contains('ספרייה'));
    expect(node, isSemantics(isSelected: true));
    expect(node, isSemantics(isButton: true));
    handle.dispose();
  });

  testWidgets('SettingsActionTile.radioOption: checked בקבוצה בלעדית', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpInApp(
      tester,
      Column(
        children: [
          SettingsActionTile.radioOption(
            title: 'בהיר',
            selected: true,
            onTap: () {},
          ),
          SettingsActionTile.radioOption(
            title: 'כהה',
            selected: false,
            onTap: () {},
          ),
        ],
      ),
    );
    final on = _node(tester, find.text('בהיר'));
    final off = _node(tester, find.text('כהה'));
    expect(on, isSemantics(isInMutuallyExclusiveGroup: true));
    expect(on, isSemantics(isChecked: true));
    expect(off, isSemantics(hasCheckedState: true));
    expect(off, isSemantics(isChecked: false));
    handle.dispose();
  });
}
