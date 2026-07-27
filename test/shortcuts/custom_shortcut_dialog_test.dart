import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/view/custom_shortcut_dialog.dart';

/// אירוע מקש אות בפריסה עברית כפי ש-Flutter מדווח ב-Windows: `physicalKey`
/// תקין ו-`logicalKey` הוא התו העברי.
KeyDownEvent _hebrewLetter(PhysicalKeyboardKey physicalKey, int hebrewKeyId) =>
    KeyDownEvent(
      physicalKey: physicalKey,
      logicalKey: LogicalKeyboardKey(hebrewKeyId),
      timeStamp: Duration.zero,
    );

KeyDownEvent _modifier(LogicalKeyboardKey key, PhysicalKeyboardKey physical) =>
    KeyDownEvent(
      physicalKey: physical,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // הטסטים שולחים Control פיזי; ב-macOS `ctrl` מתורגם ל-Meta ולכן הפלטפורמה
  // מקובעת כדי שהערך הקנוני יהיה זהה בכל סביבת ריצה.
  setUp(() {
    ShortcutHelper.isMacForTesting = false;
    FocusRepository().resetForTesting();
  });
  tearDown(() {
    ShortcutHelper.isMacForTesting = null;
    FocusRepository().resetForTesting();
  });

  /// פותח את דיאלוג ההקלטה ומחזיר את ה-Future של הערך שיוחזר ממנו.
  Future<Future<String?>> openDialog(
    WidgetTester tester, {
    String? initialShortcut,
    bool startRecording = true,
  }) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox(width: 100, height: 100)),
      ),
    );

    final result = showDialog<String>(
      context: navigatorKey.currentContext!,
      builder: (_) => CustomShortcutDialog(
        initialShortcut: initialShortcut,
        actionName: 'חיפוש חדש בכל הספרים',
      ),
    );
    await tester.pumpAndSettle();

    if (startRecording) {
      await tester.tap(find.text('התחל הקלטה'));
      await tester.pump();
    }
    return result;
  }

  /// מזריק אירועי מקלדת ישירות ל-KeyboardListener של הדיאלוג — הדרך היחידה
  /// לדמות logicalKey לא-לטיני, שסימולטור המקלדת של Flutter אינו מכיר.
  void sendKeys(WidgetTester tester, List<KeyEvent> events) {
    final listener = tester.widget<KeyboardListener>(
      find.descendant(
        of: find.byType(CustomShortcutDialog),
        matching: find.byType(KeyboardListener),
      ),
    );
    for (final event in events) {
      listener.onKeyEvent!(event);
    }
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('עצור הקלטה'));
    await tester.pump();
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();
  }

  List<KeyEvent> ctrlShift(KeyEvent mainKey) => [
    _modifier(LogicalKeyboardKey.control, PhysicalKeyboardKey.controlLeft),
    _modifier(LogicalKeyboardKey.shift, PhysicalKeyboardKey.shiftLeft),
    mainKey,
  ];

  group('CustomShortcutDialog — הקלטה בפריסת מקלדת עברית', () {
    testWidgets('Ctrl+Shift+F בפריסה עברית נשמר כ-ctrl+shift+f', (
      tester,
    ) async {
      final result = await openDialog(tester);

      sendKeys(
        tester,
        ctrlShift(_hebrewLetter(PhysicalKeyboardKey.keyF, 0x2000000f3)),
      );
      await tester.pump();
      await confirm(tester);

      expect(await result, 'ctrl+shift+f');
    });

    testWidgets('התצוגה בזמן ההקלטה מציגה את האות הלטינית ולא את התו העברי', (
      tester,
    ) async {
      await openDialog(tester);

      sendKeys(
        tester,
        ctrlShift(_hebrewLetter(PhysicalKeyboardKey.keyG, 0x2000000e2)),
      );
      await tester.pump();

      expect(find.text('CTRL + SHIFT + G'), findsOneWidget);
      // 'ע' הוא התו שמקש G מייצר בפריסה עברית — הוא לא אמור להגיע לתצוגה.
      expect(find.text('CTRL + SHIFT + ע'), findsNothing);
    });

    testWidgets('הקיצור שנשמר מזוהה על ידי matchesShortcut באותו אירוע', (
      tester,
    ) async {
      final event = _hebrewLetter(PhysicalKeyboardKey.keyD, 0x2000000d2);
      final result = await openDialog(tester);

      sendKeys(tester, ctrlShift(event));
      await tester.pump();
      await confirm(tester);

      final shortcut = await result;
      expect(shortcut, 'ctrl+shift+d');
      expect(
        ShortcutHelper.matchesShortcut(
          event,
          shortcut!,
          isControlPressed: true,
          isShiftPressed: true,
        ),
        isTrue,
      );
    });

    testWidgets('Ctrl בלבד + אות עברית נשמר כ-ctrl+<אות לטינית>', (
      tester,
    ) async {
      final result = await openDialog(tester);

      sendKeys(tester, [
        _modifier(LogicalKeyboardKey.control, PhysicalKeyboardKey.controlLeft),
        _hebrewLetter(PhysicalKeyboardKey.keyY, 0x2000000d8),
      ]);
      await tester.pump();
      await confirm(tester);

      expect(await result, 'ctrl+y');
    });

    testWidgets('Alt + אות עברית נשמר כ-alt+<אות לטינית>', (tester) async {
      final result = await openDialog(tester);

      sendKeys(tester, [
        _modifier(LogicalKeyboardKey.alt, PhysicalKeyboardKey.altLeft),
        _hebrewLetter(PhysicalKeyboardKey.keyQ, 0x2000000e9),
      ]);
      await tester.pump();
      await confirm(tester);

      expect(await result, 'alt+q');
    });
  });

  group('CustomShortcutDialog — הקלטה בפריסה לטינית (ללא שינוי התנהגות)', () {
    testWidgets('Ctrl+Shift+F נשמר כ-ctrl+shift+f', (tester) async {
      final result = await openDialog(tester);

      sendKeys(
        tester,
        ctrlShift(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyF,
            logicalKey: LogicalKeyboardKey.keyF,
            character: 'F',
            timeStamp: Duration.zero,
          ),
        ),
      );
      await tester.pump();
      await confirm(tester);

      expect(await result, 'ctrl+shift+f');
    });

    testWidgets('מקש F שאינו אות נשמר כ-f8', (tester) async {
      final result = await openDialog(tester);

      sendKeys(tester, [
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.f8,
          logicalKey: LogicalKeyboardKey.f8,
          timeStamp: Duration.zero,
        ),
      ]);
      await tester.pump();
      await confirm(tester);

      expect(await result, 'f8');
    });

    testWidgets('Alt + חץ למעלה נשמר כ-alt+arrowup', (tester) async {
      final result = await openDialog(tester);

      sendKeys(tester, [
        _modifier(LogicalKeyboardKey.alt, PhysicalKeyboardKey.altLeft),
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowUp,
          logicalKey: LogicalKeyboardKey.arrowUp,
          timeStamp: Duration.zero,
        ),
      ]);
      await tester.pump();
      await confirm(tester);

      expect(await result, 'alt+arrowup');
    });

    testWidgets('Ctrl + פסיק נשמר כ-ctrl+comma', (tester) async {
      final result = await openDialog(tester);

      sendKeys(tester, [
        _modifier(LogicalKeyboardKey.control, PhysicalKeyboardKey.controlLeft),
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.comma,
          logicalKey: LogicalKeyboardKey.comma,
          character: ',',
          timeStamp: Duration.zero,
        ),
      ]);
      await tester.pump();
      await confirm(tester);

      expect(await result, 'ctrl+comma');
    });
  });

  group('CustomShortcutDialog — מצב הדיאלוג', () {
    testWidgets('מציג את הקיצור הקיים בפתיחה ואת שם הפעולה', (tester) async {
      await openDialog(
        tester,
        initialShortcut: 'ctrl+shift+f',
        startRecording: false,
      );

      expect(find.text('CTRL + SHIFT + F'), findsOneWidget);
      expect(find.text('חיפוש חדש בכל הספרים'), findsOneWidget);
    });

    testWidgets('אירועי מקלדת לפני "התחל הקלטה" אינם נקלטים', (tester) async {
      await openDialog(
        tester,
        initialShortcut: 'ctrl+shift+f',
        startRecording: false,
      );

      sendKeys(
        tester,
        ctrlShift(_hebrewLetter(PhysicalKeyboardKey.keyG, 0x2000000e2)),
      );
      await tester.pump();

      expect(find.text('CTRL + SHIFT + F'), findsOneWidget);
      expect(find.text('CTRL + SHIFT + G'), findsNothing);
    });

    testWidgets('התחלת הקלטה מחדש מאפסת קיצור שהוקלט קודם', (tester) async {
      final result = await openDialog(tester);

      sendKeys(
        tester,
        ctrlShift(_hebrewLetter(PhysicalKeyboardKey.keyG, 0x2000000e2)),
      );
      await tester.pump();
      await tester.tap(find.text('עצור הקלטה'));
      await tester.pump();

      await tester.tap(find.text('התחל הקלטה'));
      await tester.pump();
      sendKeys(tester, [
        _modifier(LogicalKeyboardKey.control, PhysicalKeyboardKey.controlLeft),
        _hebrewLetter(PhysicalKeyboardKey.keyY, 0x2000000d8),
      ]);
      await tester.pump();
      await confirm(tester);

      expect(await result, 'ctrl+y');
    });

    testWidgets('ביטול אינו מחזיר קיצור', (tester) async {
      final result = await openDialog(tester);

      sendKeys(
        tester,
        ctrlShift(_hebrewLetter(PhysicalKeyboardKey.keyG, 0x2000000e2)),
      );
      await tester.pump();
      await tester.tap(find.text('עצור הקלטה'));
      await tester.pump();
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(await result, isNull);
    });
  });
}
