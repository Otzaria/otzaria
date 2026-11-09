import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';

Widget _wrap(Widget child, {Size size = const Size(400, 300)}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox.fromSize(size: size, child: child),
    ),
  ),
);

Scrollbar _scrollbar(WidgetTester tester) =>
    tester.widget<Scrollbar>(find.byType(Scrollbar));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PanelScrollableContent', () {
    testWidgets('ברירת מחדל: פס הגלילה אינו נעוץ', (tester) async {
      await tester.pumpWidget(
        _wrap(const PanelScrollableContent(child: SizedBox(height: 900))),
      );
      expect(_scrollbar(tester).thumbVisibility, isNot(true));
    });

    testWidgets('thumbVisibility מועבר ל-Scrollbar', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelScrollableContent(
            thumbVisibility: true,
            child: SizedBox(height: 900),
          ),
        ),
      );
      expect(_scrollbar(tester).thumbVisibility, isTrue);
    });

    testWidgets('גם בפס בצד שמאל thumbVisibility נשמר', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelScrollableContent(
            scrollbarSide: ScrollbarOrientation.left,
            thumbVisibility: true,
            child: SizedBox(height: 900),
          ),
        ),
      );
      expect(_scrollbar(tester).thumbVisibility, isTrue);
      expect(
        _scrollbar(tester).scrollbarOrientation,
        ScrollbarOrientation.left,
      );
    });

    testWidgets('ברירת מחדל: הפס בימין הפיזי', (tester) async {
      await tester.pumpWidget(
        _wrap(const PanelScrollableContent(child: SizedBox(height: 900))),
      );
      expect(
        _scrollbar(tester).scrollbarOrientation,
        ScrollbarOrientation.right,
      );
    });

    testWidgets('התוכן נשאר גליל', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelScrollableContent(
            thumbVisibility: true,
            child: SizedBox(height: 900),
          ),
        ),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
    });
  });

  group('AppDialogFrame', () {
    testWidgets('אזור התוכן מציג פס גלילה נעוץ', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppDialogFrame(
            title: 'כותרת',
            icon: Icons.list,
            scrollable: true,
            child: SizedBox(height: 2000),
          ),
          size: const Size(400, 400),
        ),
      );
      final content = tester.widget<PanelScrollableContent>(
        find.byType(PanelScrollableContent),
      );
      expect(content.thumbVisibility, isTrue);
    });

    testWidgets('scrollable=false אינו עוטף בגלילה', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AppDialogFrame(
            title: 'כותרת',
            icon: Icons.list,
            child: SizedBox(height: 50),
          ),
          size: const Size(400, 400),
        ),
      );
      expect(find.byType(PanelScrollableContent), findsNothing);
    });
  });
}
