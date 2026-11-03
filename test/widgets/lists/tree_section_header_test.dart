import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/lists/tree_section_header.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';

void main() {
  Future<List<bool>> pump(
    WidgetTester tester, {
    required bool expanded,
    Widget? trailing,
  }) async {
    final toggles = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: TreeSectionHeader(
              isExpanded: expanded,
              onToggle: () => toggles.add(true),
              leadingExtent: 54,
              child: Row(
                children: [
                  const Expanded(child: Text('פרק א')),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return toggles;
  }

  testWidgets('לחיצה בכל מקום בשורה מחליפה את המצב', (tester) async {
    final toggles = await pump(tester, expanded: true);
    await tester.tap(find.text('פרק א'));
    await tester.tap(find.byType(ExpandingChevron));
    expect(toggles, hasLength(2));
  });

  testWidgets('החץ בסגנון עץ, בתחילת השורה וברוחב leadingExtent', (
    tester,
  ) async {
    await pump(tester, expanded: false);
    final chevron = tester.widget<ExpandingChevron>(
      find.byType(ExpandingChevron),
    );
    expect(chevron.style, ExpandingChevronStyle.tree);
    expect(chevron.isExpanded, isFalse);

    final row = tester.getRect(find.byType(TreeSectionHeader));
    final chevronRect = tester.getRect(find.byType(ExpandingChevron));
    final title = tester.getRect(find.text('פרק א'));
    // RTL: התחלת השורה בימין. התוכן מתחיל אחרי 54 הפיקסלים של החץ.
    expect(chevronRect.center.dx, closeTo(row.right - 27, 0.5));
    expect(title.right, closeTo(row.right - 54, 0.5));
  });

  testWidgets('פקד בתוך השורה מקבל את הלחיצה, והשורה לא נסגרת', (
    tester,
  ) async {
    var checked = false;
    final toggles = await pump(
      tester,
      expanded: true,
      trailing: StatefulBuilder(
        builder: (context, setState) => Checkbox(
          value: checked,
          onChanged: (v) => setState(() => checked = v ?? false),
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(checked, isTrue);
    expect(toggles, isEmpty);
  });
}
