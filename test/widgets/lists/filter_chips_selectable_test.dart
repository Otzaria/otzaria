// צ׳יפ מותאם (chipBuilder) חייב להתנהג כצ׳יפ אמיתי: מיקוד מקלדת, הפעלה
// ב-Enter/רווח, וחשיפת מצב "נבחר" לקורא מסך.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';

void main() {
  Future<List<List<String>>> pumpSelector(
    WidgetTester tester, {
    List<String> selected = const [],
  }) async {
    final changes = <List<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilterChipsSelector<String>(
            items: const ['תרגום', 'מדרש'],
            selectedItems: selected,
            labelBuilder: (item) => item,
            onSelectionChanged: changes.add,
            chipBuilder: (context, item, isSelected) => Chip(
              label: Text(item),
              backgroundColor: isSelected
                  ? Theme.of(context).colorScheme.secondary
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return changes;
  }

  testWidgets('הצ׳יפ מדווח לקורא מסך על מצב נבחר', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSelector(tester, selected: const ['מדרש']);

    SemanticsNode nodeFor(String label) => tester.getSemantics(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(MergeSemantics),
      ),
    );

    expect(
      nodeFor('מדרש'),
      matchesSemantics(
        label: 'מדרש',
        isSelected: true,
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    expect(
      nodeFor('תרגום'),
      matchesSemantics(
        label: 'תרגום',
        isSelected: false,
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('אפשר למקד צ׳יפ ולהפעילו מהמקלדת', (tester) async {
    final changes = await pumpSelector(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(focused!.context, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(changes, isNotEmpty);
    expect(changes.last, hasLength(1));
    expect(const ['תרגום', 'מדרש'], contains(changes.last.single));
  });

  testWidgets('לחיצה על צ׳יפ עדיין מדווחת בחירה', (tester) async {
    final changes = await pumpSelector(tester);

    await tester.tap(find.text('תרגום'));
    await tester.pumpAndSettle();

    expect(changes.last, ['תרגום']);
  });

  testWidgets('לחיצה על צ׳יפ נבחר מסירה אותו מהבחירה', (tester) async {
    final changes = await pumpSelector(tester, selected: const ['תרגום']);

    await tester.tap(find.text('תרגום'));
    await tester.pumpAndSettle();

    expect(changes.last, isEmpty);
  });
}
