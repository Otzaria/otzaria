import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/confirmation_dialog.dart';
import 'package:otzaria/widgets/input_dialog.dart';

void main() {
  group('ConfirmationDialog Tests', () {
    testWidgets('ConfirmationDialog shows title and content', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showConfirmationDialog(
                context: context,
                title: 'Test Title',
                content: 'Test Content',
              ),
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test Content'), findsOneWidget);
      expect(find.text('אישור'), findsOneWidget);
      expect(find.text('ביטול'), findsOneWidget);
    });
  });

  group('InputDialog Tests', () {
    testWidgets('InputDialog shows title and label', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showInputDialog(
                context: context,
                title: 'Input Title',
                labelText: 'Input Label',
              ),
              child: const Text('Show Input'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Show Input'));
      await tester.pumpAndSettle();

      expect(find.text('Input Title'), findsOneWidget);
      expect(find.text('Input Label'), findsOneWidget);
      expect(find.text('שמור'), findsOneWidget);
      expect(find.text('ביטול'), findsOneWidget);
    });
  });
}
