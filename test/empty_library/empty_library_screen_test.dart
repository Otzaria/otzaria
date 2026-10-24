import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/empty_library/empty_library_screen.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibrarySetupView', () {
    Widget wrap(Future<void> Function() onLibraryLoaded) => MaterialApp(
      home: Scaffold(
        body: LibrarySetupView(onLibraryLoaded: onLibraryLoaded),
      ),
    );

    testWidgets('מציג את כפתור הגדרת המיקום', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(() async {}));
      await tester.pump();

      // ActionButton עם textAlign.center עשוי לשבור את הטקסט לשתי שורות,
      // לכן בודקים לפי מאפיין ה-text של הכפתור ולא לפי טקסט מדויק ב-Text.
      expect(
        find.byWidgetPredicate(
          (w) => w is ActionButton && w.text == 'בחר מיקום או הורד ספרייה',
        ),
        findsOneWidget,
      );
    });

    testWidgets('מציג את הכותרת "לא נמצאה ספריית ספרים"', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(() async {}));
      await tester.pump();

      expect(find.text('לא נמצאה ספריית ספרים'), findsOneWidget);
    });

    testWidgets('ספרייה בסכמה שאינה נתמכת — מסביר שיש לעדכן את התוכנה', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibrarySetupView(
              onLibraryLoaded: () async {},
              unsupportedDbSchemaVersion: 99,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ספריית הספרים חדשה מגרסת התוכנה'), findsOneWidget);
      expect(find.text('לא נמצאה ספריית ספרים'), findsNothing);
      expect(find.textContaining('בפורמט מסד 99'), findsOneWidget);
      expect(find.textContaining('יש לעדכן את התוכנה'), findsOneWidget);
    });

    // חלון נמוך (טלפון לרוחב, מסך מפוצל): בלי גלילה הכפתור נחתך מחוץ למסך
    // ואי אפשר בכלל להגדיר ספרייה.
    testWidgets('בחלון נמוך הכפתור נשאר נגיש דרך גלילה', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(640, 360);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrap(() async {}));
      await tester.pump();

      final button = find.byWidgetPredicate(
        (w) => w is ActionButton && w.text == 'בחר מיקום או הורד ספרייה',
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(button);
      expect(button.hitTestable(), findsOneWidget);
    });
  });
}
