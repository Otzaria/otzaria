import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';

/// q10 שאלה 6: "מוריד..." הוא מצב ולא פעולה — אותם צבעים, בלי כפתור.
void main() {
  Future<void> pump(WidgetTester tester, Widget chip) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: chip)),
    ),
  );

  testWidgets('busy: צבעי הגלולה הלחיצה, לא מושבת ולא כפתור', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const StatusChip.busy(
        icon: Icon(Icons.download),
        label: 'מוריד...',
        tooltip: 'אנא המתן...',
      ),
    );
    final cs = Theme.of(tester.element(find.text('מוריד...'))).colorScheme;
    final text = tester.widget<RichText>(
      find.descendant(
        of: find.text('מוריד...'),
        matching: find.byType(RichText),
      ),
    );
    expect(text.text.style?.color, cs.onPrimaryContainer);

    final node = tester.getSemantics(find.byType(StatusChip));
    expect(node.label, 'מוריד...');
    expect(node.flagsCollection.isButton, isFalse);
    semantics.dispose();
  });

  testWidgets('רגיל: כפתור לחיץ', (tester) async {
    var taps = 0;
    await pump(
      tester,
      StatusChip(
        icon: const Icon(Icons.check),
        label: 'מוכן להתקנה',
        tooltip: 'לחץ להתקנה',
        onPressed: () => taps++,
      ),
    );
    await tester.tap(find.text('מוכן להתקנה'));
    expect(taps, 1);
  });
}
