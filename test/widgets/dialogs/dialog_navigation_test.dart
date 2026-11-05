import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

void main() {
  group('ConfirmationDialog Tests', () {
    testWidgets('ConfirmationDialog shows title and content', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test Content'), findsOneWidget);
      expect(find.text('אישור'), findsOneWidget);
      expect(find.text('ביטול'), findsOneWidget);
    });
  });

  group('InputDialog Tests', () {
    testWidgets('InputDialog shows title and label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );

      await tester.tap(find.text('Show Input'));
      await tester.pumpAndSettle();

      expect(find.text('Input Title'), findsOneWidget);
      expect(find.text('Input Label'), findsOneWidget);
      expect(find.text('שמור'), findsOneWidget);
      expect(find.text('ביטול'), findsOneWidget);
    });
  });

  group('showTwoActionsDialog — isDirty', () {
    late ValueNotifier<bool> hasChanges;
    late List<String> sounds;
    bool? result;

    setUp(() {
      hasChanges = ValueNotifier(false);
      sounds = [];
      result = null;
    });

    tearDown(() => hasChanges.dispose());

    Future<void> open(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemSound.play') {
            sounds.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showTwoActionsDialog(
                  context: context,
                  title: 'עריכה',
                  content: 'תוכן',
                  isDirty: hasChanges,
                ),
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
      sounds.clear();
    }

    testWidgets('בלי שינויים לחיצה מחוץ לדיאלוג סוגרת אותו', (tester) async {
      await open(tester);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('עריכה'), findsNothing);
      expect(sounds, isEmpty);
    });

    testWidgets('עם שינויים לחיצה מחוץ לדיאלוג וביטול שואלים לפני הסגירה', (
      tester,
    ) async {
      await open(tester);
      hasChanges.value = true;
      await tester.pump();

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
      await tester.tap(find.text('המשך לערוך'));
      await tester.pumpAndSettle();
      expect(find.text('עריכה'), findsOneWidget);

      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('סגור בלי לשמור'));
      await tester.pumpAndSettle();
      expect(find.text('עריכה'), findsNothing);
      expect(result, isFalse);
      expect(sounds, isNot(contains('SystemSoundType.alert')));
    });
  });
}
