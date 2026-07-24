import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// רגרסיה לבאג "טקסט מוסתר נסגר מיד": ב-combined view, בחירת שורה (onSingleTap)
// העבירה את ה-AnimatedContainer מ-decoration:null ל-BoxDecoration. Container
// מוסיף DecoratedBox רק כשיש decoration, כך שהמעבר שינה את עומק ה-HtmlWidget
// ב-tree, הרס את ה-Element שלו ואיפס את מצב ה-<details> הפתוח.
const _html =
    '<div dir="rtl">הטקסט שלפני כן <details><summary>הצג טקסט מוסתר</summary>'
    'PAYLOAD_VISIBLE</details> המשך הטקסט...</div>';

/// מדמה את מבנה ה-item של combined_book_screen סביב הטקסט המוסתר.
/// [stableDecoration] = התנהגות אחרי התיקון (decoration קבוע).
class _Harness extends StatefulWidget {
  final bool stableDecoration;
  const _Harness({required this.stableDecoration});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final selColor = Theme.of(
      context,
    ).colorScheme.primary.withValues(alpha: 0.08);
    return MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          child: ScrollablePositionedList.builder(
            itemCount: 30,
            itemBuilder: (c, index) {
              final isSelected = _selectedIndex == index;
              final decoration = widget.stableDecoration
                  ? BoxDecoration(color: isSelected ? selColor : null)
                  : (isSelected ? BoxDecoration(color: selColor) : null);
              return Column(
                key: PageStorageKey('segment-$index'),
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: decoration,
                    child: EnhancedGestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onSingleTap: () => setState(
                        () => _selectedIndex = isSelected ? null : index,
                      ),
                      child: index == 0
                          ? const HtmlWidget(_html, key: ValueKey('html_item'))
                          : SizedBox(height: 40, child: Text('row $index')),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

void main() {
  final payload = find.textContaining('PAYLOAD_VISIBLE', findRichText: true);
  final summary = find.textContaining('הצג טקסט מוסתר', findRichText: true);

  // לוחץ על summary (פותח details), וממתין 300ms עד שה-Listener מפעיל onSingleTap
  // שבוחר את השורה וגורם ל-rebuild.
  Future<void> openThenSelect(WidgetTester tester) async {
    expect(payload, findsNothing, reason: 'details starts closed');
    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(payload, findsOneWidget, reason: 'opens on summary tap');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'toggling decoration null<->BoxDecoration closes details (regression)',
    (tester) async {
      await tester.pumpWidget(const _Harness(stableDecoration: false));
      await tester.pumpAndSettle();
      await openThenSelect(tester);
      expect(
        payload,
        findsNothing,
        reason: 'old behavior: rebuild destroyed the details Element',
      );
    },
  );

  testWidgets('stable decoration keeps details open after selection', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(stableDecoration: true));
    await tester.pumpAndSettle();
    await openThenSelect(tester);
    expect(
      payload,
      findsOneWidget,
      reason: 'fix: constant tree depth preserves details state',
    );
  });
}
