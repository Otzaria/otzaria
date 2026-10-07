import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

void main() {
  Widget buildHarness({required Widget child, TargetPlatform? platform}) {
    return MaterialApp(
      locale: const Locale('he', 'IL'),
      theme: ThemeData(platform: platform ?? TargetPlatform.windows),
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: AppSelectionArea(child: child),
        ),
      ),
    );
  }

  Future<void> rightClickAt(WidgetTester tester, Offset position) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(position);
    await gesture.down(position);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> selectAll(WidgetTester tester) async {
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll();
    await tester.pump();
  }

  testWidgets('לחיצה ימנית פותחת את תפריט אוצריא ולא את תפריט ברירת המחדל', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(child: const Text('טקסט לדוגמה')));
    await tester.pumpAndSettle();

    await rightClickAt(tester, tester.getCenter(find.text('טקסט לדוגמה')));

    expect(
      find.text('העתק'),
      findsOneWidget,
      reason: 'תפריט ההקשר של אוצריא חייב להכיל "העתק"',
    );
    expect(
      find.byType(AdaptiveTextSelectionToolbar),
      findsNothing,
      reason: 'תפריט ברירת המחדל של Flutter חייב להיות מדוכא',
    );
  });

  testWidgets('"העתק" מנוטרל כשאין טקסט נבחר', (tester) async {
    await tester.pumpWidget(buildHarness(child: const Text('טקסט לדוגמה')));
    await tester.pumpAndSettle();

    await rightClickAt(tester, tester.getCenter(find.text('טקסט לדוגמה')));

    final copyItem = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('העתק'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(
      copyItem.onPressed,
      isNull,
      reason: 'ללא בחירה פעילה "העתק" צריך להיות מנוטרל',
    );
  });

  testWidgets('בחירה נשמרת בלחיצה ימנית והעתקה מעבירה את הטקסט ללוח', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
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

    const text = 'טקסט שנבחר להעתקה';
    await tester.pumpWidget(buildHarness(child: const Text(text)));
    await tester.pumpAndSettle();
    await selectAll(tester);

    await rightClickAt(tester, tester.getCenter(find.text(text)));

    final copyItem = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('העתק'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(copyItem.onPressed, isNotNull);

    await tester.tap(find.text('העתק'));
    await tester.pump();
    expect(clipboardText, text);
  });

  testWidgets('מקור בחירה מועתק כשהלחיצה עליו, גם כשיש בחירה חיצונית', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
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
      buildHarness(
        child: const Column(
          children: [Text('בחירה חיצונית'), Text('הערה פנימית')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    const sourceText = 'בחירת Quill';
    String selectionSource() => sourceText;
    final sourceBounds = tester.getRect(find.text('הערה פנימית'));
    tester
        .state<AppSelectionAreaState>(find.byType(AppSelectionArea))
        .addSelectionSource(
          selectionSource,
          containsPosition: sourceBounds.contains,
        );
    await selectAll(tester);

    await rightClickAt(tester, sourceBounds.center);
    await tester.tap(find.text('העתק'));
    await tester.pump();

    expect(clipboardText, sourceText);
  });

  testWidgets('לחיצה מחוץ למקור נוסף מעתיקה את בחירת SelectionArea', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
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

    const text = 'טקסט לבחירה חיצונית';
    await tester.pumpWidget(buildHarness(child: const Text(text)));
    await tester.pumpAndSettle();

    String selectionSource() => 'בחירת Quill';
    tester
        .state<AppSelectionAreaState>(find.byType(AppSelectionArea))
        .addSelectionSource(selectionSource, containsPosition: (_) => false);
    await selectAll(tester);

    await rightClickAt(tester, tester.getCenter(find.text(text)));
    await tester.tap(find.text('העתק'));
    await tester.pump();

    expect(clipboardText, text);
  });

  testWidgets('מקור ריק בלחיצה לא מעתיק בחירה חיצונית ישנה', (tester) async {
    await tester.pumpWidget(
      buildHarness(
        child: const Column(
          children: [Text('בחירה חיצונית'), Text('עורך ריק')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    String selectionSource() => '';
    final sourceBounds = tester.getRect(find.text('עורך ריק'));
    tester
        .state<AppSelectionAreaState>(find.byType(AppSelectionArea))
        .addSelectionSource(
          selectionSource,
          containsPosition: sourceBounds.contains,
        );
    await selectAll(tester);

    await rightClickAt(tester, sourceBounds.center);

    final copyItem = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('העתק'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(copyItem.onPressed, isNull);
  });

  testWidgets('ב-Android לחיצה ארוכה משתמשת בבחירה ובתפריט המגע המקוריים', (
    tester,
  ) async {
    const text = 'טקסט למגע';
    await tester.pumpWidget(
      buildHarness(child: const Text(text), platform: TargetPlatform.android),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();

    expect(
      find.byType(AdaptiveTextSelectionToolbar),
      findsOneWidget,
      reason: 'תפריט המגע חייב להיפתח לאחר ש-SelectionArea יצר בחירה',
    );
    expect(
      find.descendant(
        of: find.byType(AppContextMenuRegion),
        matching: find.byType(MenuItemButton),
      ),
      findsNothing,
      reason: 'תפריט הלחיצה הימנית לא צריך להתחרות בבחירת המגע',
    );
  });

  testWidgets('AppContextMenuRegion עוטף את התוכן', (tester) async {
    await tester.pumpWidget(buildHarness(child: const Text('טקסט לדוגמה')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppContextMenuRegion),
        matching: find.text('טקסט לדוגמה'),
      ),
      findsOneWidget,
    );
  });

  group('תוכן ספר מוגן', () {
    late List<String> clipboard;

    setUp(() {
      clipboard = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    Future<void> pumpProtected(WidgetTester tester, String text) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppSelectionArea(
              protection: () async => const BookProtection(level: 1),
              child: Text(text),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await selectAll(tester);
    }

    Future<void> invokeCopy(WidgetTester tester) async {
      Actions.invoke(
        tester.element(find.byType(SelectableRegion)),
        CopySelectionTextIntent.copy,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+C על יותר מ-5 שורות נחסם', (tester) async {
      await pumpProtected(tester, 'א\nב\nג\nד\nה\nו');
      await invokeCopy(tester);
      expect(clipboard, isEmpty);
    });

    testWidgets('Ctrl+C על עד 5 שורות מועתק', (tester) async {
      await pumpProtected(tester, 'א\nב\nג');
      await invokeCopy(tester);
      expect(clipboard, ['א\nב\nג']);
    });
  });
}
