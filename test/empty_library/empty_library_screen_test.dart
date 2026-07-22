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
          (w) => w is ActionButton && w.text == 'בחר מיקום או הורד ספריה',
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
  });
}
