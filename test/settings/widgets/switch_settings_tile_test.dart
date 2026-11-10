import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';

void main() {
  testWidgets('SwitchSettingsTile toggles when tapping the row', (
    tester,
  ) async {
    bool currentValue = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SettingsSwitchTile(
              title: 'אפשרות',
              subtitle: 'תיאור',
              value: currentValue,
              onChanged: (value) => setState(() => currentValue = value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(currentValue, isTrue);
  });

  testWidgets('SwitchSettingsTile toggles with Space and Enter while focused', (
    tester,
  ) async {
    bool currentValue = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SettingsSwitchTile(
              title: 'אפשרות',
              subtitle: 'תיאור',
              value: currentValue,
              onChanged: (value) => setState(() => currentValue = value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var listTile = tester.widget<ListTile>(find.byType(ListTile));
    listTile.focusNode!.requestFocus();
    await tester.pump();

    expect(listTile.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump();

    listTile = tester.widget<ListTile>(find.byType(ListTile));
    expect(currentValue, isTrue);
    expect(listTile.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    listTile = tester.widget<ListTile>(find.byType(ListTile));
    expect(currentValue, isFalse);
    expect(listTile.focusNode!.hasFocus, isTrue);
  });
  group('focus style', () {
    final ring = find.descendant(
      of: find.byType(SettingsSwitchTile),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.position == DecorationPosition.foreground &&
            (w.decoration as BoxDecoration).border != null,
      ),
    );

    Future<void> pumpTile(WidgetTester tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SettingsSwitchTile(
                title: 'אפשרות',
                value: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('mouse click leaves no focus fill or ring', (tester) async {
      await pumpTile(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byType(ListTile)));
      await mouse.down(tester.getCenter(find.byType(ListTile)));
      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.focusNode!.hasFocus, isTrue);
      expect(tile.focusColor, Colors.transparent);
      expect(ring, findsNothing);
    });

    testWidgets('keyboard focus shows the focused row style', (tester) async {
      await pumpTile(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      final cs = Theme.of(tester.element(find.byType(ListTile))).colorScheme;
      expect(tile.focusNode!.hasFocus, isTrue);
      expect(tile.focusColor, AppSurfaces.focusedRow(cs));
      expect(ring, findsOneWidget);
    });
  });
}
