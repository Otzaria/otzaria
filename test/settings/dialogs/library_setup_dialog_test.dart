import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/library_setup_dialog.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

Widget _host(void Function(BuildContext) onOpen) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => onOpen(ctx),
        child: const Text('פתח'),
      ),
    ),
  ),
);

Future<void> _openSetup(
  WidgetTester tester, {
  String defaultTargetPath = '/default/library',
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      (ctx) => showLibrarySetupDialog(
        context: ctx,
        defaultTargetPath: defaultTargetPath,
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

Future<void> _openUpdate(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      (ctx) => showLibrarySetupDialog(
        context: ctx,
        defaultTargetPath: '/lib',
        currentLibraryPath: '/lib/books',
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

VoidCallback? _actionOnPressed(WidgetTester tester, String text) {
  final btn = tester.widget<ActionButton>(
    find.byWidgetPredicate((w) => w is ActionButton && w.text == text),
  );
  return btn.onPressed;
}

Future<void> _select(WidgetTester tester, String optionTitle) async {
  // מקישים על כותרת האפשרות (ולא על מרכז השורה, שעלול לפגוע בכפתור ה-trailing).
  final title = find.text(optionTitle);
  await tester.ensureVisible(title);
  await tester.tap(title);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('showLibrarySetupDialog — ללא ספרייה קיימת (הגדרה)', () {
    testWidgets('כותרת: "הגדרת ספריית אוצריא"', (tester) async {
      await _openSetup(tester);
      expect(find.text('הגדרת ספריית אוצריא'), findsOneWidget);
    });

    testWidgets('כרטיס "פעולה" מוצג, ואפשרות ההעברה לא', (tester) async {
      await _openSetup(tester);
      expect(find.text('פעולה'), findsOneWidget);
      expect(find.text('העברת תוכן התיקייה'), findsNothing);
    });

    testWidgets('פעולות המקור: הורדה, תיקייה וארכיון', (tester) async {
      await _openSetup(tester);
      expect(find.text('הורדת הספרייה'), findsOneWidget);
      expect(find.text('בחירת תיקייה מהמחשב'), findsOneWidget);
      expect(find.text('בחירת קובץ דחוס'), findsOneWidget);
    });

    testWidgets('מקטע היעד: "תיקיית היעד לספריית אוצריא" עם ברירת מחדל', (
      tester,
    ) async {
      await _openSetup(tester, defaultTargetPath: '/default/library');
      expect(find.text('תיקיית היעד לספריית אוצריא'), findsOneWidget);
      expect(find.text('מיקום ברירת מחדל'), findsOneWidget);
    });

    testWidgets('לאפשרות יש רדיו ב-leading (בלי אייקון ובלי Checkbox)', (
      tester,
    ) async {
      await _openSetup(tester);
      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('הורדת הספרייה'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.leading, isNotNull);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('כפתור "אישור" פעיל בהורדה כשיש יעד ברירת מחדל', (
      tester,
    ) async {
      await _openSetup(tester, defaultTargetPath: '/default/library');
      // הורדה היא ברירת המחדל; היעד מולא מברירת המחדל → אישור פעיל.
      expect(_actionOnPressed(tester, 'אישור'), isNotNull);
    });

    testWidgets('כפתור "אישור" מושבת כשאין יעד', (tester) async {
      await _openSetup(tester, defaultTargetPath: '');
      expect(_actionOnPressed(tester, 'אישור'), isNull);
    });
  });

  group('showLibrarySetupDialog — עם ספרייה קיימת (עדכון)', () {
    testWidgets('כותרת: "עדכון ספריית אוצריא"', (tester) async {
      await _openUpdate(tester);
      expect(find.text('עדכון ספריית אוצריא'), findsOneWidget);
    });

    testWidgets('העברה גלויה; הורדה/ייבוא מקובצים תחת "מחיקה וייבוא ספרייה"', (
      tester,
    ) async {
      await _openUpdate(tester);
      expect(find.text('פעולה'), findsOneWidget);
      expect(find.text('העברת תוכן התיקייה'), findsOneWidget);
      expect(find.text('מחיקה וייבוא ספרייה'), findsOneWidget);
      // המקטע מקופל כברירת מחדל — אפשרויות ההחלפה מוסתרות.
      expect(find.text('הורדת הספרייה מחדש'), findsNothing);
      expect(find.text('בחירת תיקייה מהמחשב'), findsNothing);
      expect(find.text('בחירת קובץ דחוס'), findsNothing);

      // פריסת המקטע חושפת את אפשרויות ההחלפה.
      await _select(tester, 'מחיקה וייבוא ספרייה');
      expect(find.text('הורדת הספרייה מחדש'), findsOneWidget);
      expect(find.text('בחירת תיקייה מהמחשב'), findsOneWidget);
      expect(find.text('בחירת קובץ דחוס'), findsOneWidget);
    });

    testWidgets('מקטע היעד מוצג בכותרת "מיקום חדש"', (tester) async {
      await _openUpdate(tester);
      expect(find.text('מיקום חדש'), findsOneWidget);
    });

    testWidgets('כותרת המשנה של המקטע מציינת שהספרייה הקיימת תוחלף', (
      tester,
    ) async {
      await _openUpdate(tester);
      expect(find.textContaining('הספרייה הקיימת תוחלף'), findsOneWidget);
    });

    testWidgets(
      'אישור מושבת בהעברה ליעד הנוכחי (no-op) ובייבוא ללא תיקיית מקור',
      (tester) async {
        await _openUpdate(tester);
        // ברירת המחדל "העברה" + יעד זהה למיקום הנוכחי → אין מה להעביר, אישור מושבת.
        expect(_actionOnPressed(tester, 'אישור'), isNull);

        // מעבר ל"בחירת תיקייה" ללא בחירת מקור → אישור מושבת.
        await _select(tester, 'מחיקה וייבוא ספרייה');
        await _select(tester, 'בחירת תיקייה מהמחשב');
        expect(_actionOnPressed(tester, 'אישור'), isNull);
        // כפתור בחירת המקור מוצג.
        expect(find.text('בחר תיקייה'), findsOneWidget);
        expect(find.text('בחר קובץ ספרייה'), findsOneWidget);
      },
    );
  });
}
