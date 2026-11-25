// טולטיפ שחוזר על הטקסט הגלוי על הפקד מיותר: הפקדים המשותפים מציגים אותו
// רק כשהוא מוסיף מידע (הסבר, קיצור מקשים) או כשהתווית לא גלויה.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/controls/contained_tooltip.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';
import 'package:otzaria/widgets/controls/toggle_pill.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/navigation/nav_rail_item.dart';

void main() {
  group('tooltipRepeatsLabel', () {
    test('אותו טקסט, עד כדי רווחים, פיסוק וניקוד', () {
      expect(tooltipRepeatsLabel('אוטומטי', 'אוטומטי'), isTrue);
      expect(tooltipRepeatsLabel(' אוטומטי… ', 'אוטומטי'), isTrue);
      expect(tooltipRepeatsLabel('שָׁלוֹם', 'שלום'), isTrue);
    });

    test('טולטיפ ריק או חסר — אין מה להציג', () {
      expect(tooltipRepeatsLabel(null, 'א'), isTrue);
      expect(tooltipRepeatsLabel('  ', 'א'), isTrue);
    });

    test('טולטיפ שמוסיף מידע, או פקד בלי תווית', () {
      expect(tooltipRepeatsLabel('ספרייה (Ctrl+L)', 'ספרייה'), isFalse);
      expect(tooltipRepeatsLabel('Ctrl+L', 'ספרייה'), isFalse);
      expect(tooltipRepeatsLabel('סגור', null), isFalse);
    });
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  final cases = <String, (Widget, Widget)>{
    'BarButton.icon עם תווית': (
      BarButton.icon(
        tooltip: 'תצוגה',
        label: 'תצוגה',
        icon: FluentIcons.eye_24_regular,
        onPressed: () {},
      ),
      BarButton.icon(
        tooltip: 'הסבר',
        label: 'תצוגה',
        icon: FluentIcons.eye_24_regular,
        onPressed: () {},
      ),
    ),
    'ActionButton': (
      ActionButton.ghost(text: 'תצוגה', tooltip: 'תצוגה', onPressed: () {}),
      ActionButton.ghost(text: 'תצוגה', tooltip: 'הסבר', onPressed: () {}),
    ),
    'StatusChip': (
      StatusChip(
        icon: const Icon(Icons.download),
        label: 'תצוגה',
        tooltip: 'תצוגה',
        onPressed: () {},
      ),
      StatusChip(
        icon: const Icon(Icons.download),
        label: 'תצוגה',
        tooltip: 'הסבר',
        onPressed: () {},
      ),
    ),
    'MetaChip': (
      const MetaChip(label: 'תצוגה', tooltip: 'תצוגה'),
      const MetaChip(label: 'תצוגה', tooltip: 'הסבר'),
    ),
    'AppTogglePill': (
      AppTogglePill(
        label: 'תצוגה',
        tooltip: 'תצוגה',
        value: false,
        onChanged: (_) {},
      ),
      AppTogglePill(
        label: 'תצוגה',
        tooltip: 'הסבר',
        value: false,
        onChanged: (_) {},
      ),
    ),
    'NavRailItem': (
      NavRailItem(
        icon: FluentIcons.library_24_regular,
        label: 'תצוגה',
        tooltip: 'תצוגה',
        isSelected: false,
        onTap: () {},
      ),
      NavRailItem(
        icon: FluentIcons.library_24_regular,
        label: 'תצוגה',
        tooltip: 'הסבר',
        isSelected: false,
        onTap: () {},
      ),
    ),
  };

  for (final MapEntry(key: name, value: (repeats, adds)) in cases.entries) {
    testWidgets('$name: טולטיפ שחוזר על התווית לא מוצג', (tester) async {
      await pump(tester, repeats);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('$name: טולטיפ שמוסיף מידע נשאר', (tester) async {
      await pump(tester, adds);
      expect(find.byTooltip('הסבר'), findsOneWidget);
    });
  }

  testWidgets('MetaChip: תווית שנחתכת מוצגת בריחוף', (tester) async {
    const label = 'תווית ארוכה מאוד שלא נכנסת ברוחב הצר של התגית';
    await pump(
      tester,
      const SizedBox(
        width: 80,
        child: MetaChip(label: label, tooltip: label),
      ),
    );
    expect(find.byTooltip(label), findsOneWidget);
  });
}
