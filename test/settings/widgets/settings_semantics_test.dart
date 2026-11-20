// סליידר ושורת מתג בהגדרות חושפים לקורא מסך שם, ערך
// ומצב בצומת אחד.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/settings/widgets/settings_slider_tile.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  testWidgets('SettingsSliderTile: שם הפקד והערך המוצג, לא אחוז מהטווח', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      SettingsSliderTile(
        icon: Icons.abc,
        title: 'גודל גופן',
        valueLabel: '24',
        value: 24,
        min: 10,
        max: 60,
        onChanged: (_) {},
      ),
    );

    final data = tester.getSemantics(find.byType(Slider)).getSemanticsData();
    expect(data.label, contains('גודל גופן'));
    expect(data.value, '24', reason: 'לא "28%"');
    expect(data.increasedValue, '24');
    handle.dispose();
  });

  testWidgets('SettingsSwitchTile: צומת אחד עם שם, תיאור ומצב מופעל', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final on in [true, false]) {
      await _pump(
        tester,
        SettingsSwitchTile(
          title: 'הצג הערות',
          subtitle: 'תיאור',
          value: on,
          onChanged: (_) {},
        ),
      );
      final node = tester.getSemantics(find.text('הצג הערות'));
      expect(node.getSemanticsData().label, contains('הצג הערות'));
      expect(
        node,
        isSemantics(hasToggledState: true, isToggled: on, hasTapAction: true),
        reason: 'מצב המתג על אותו צומת שנושא את השם (מופעל=$on)',
      );
    }
    handle.dispose();
  });
}
