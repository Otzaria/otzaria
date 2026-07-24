import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';

void main() {
  testWidgets('SwitchSettingsTile toggles when tapping the row', (
    tester,
  ) async {
    bool currentValue = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SettingsActionTile.switchTile(
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
            builder: (context, setState) => SettingsActionTile.switchTile(
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
}
