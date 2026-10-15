import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

// תרחישים חוצי-רכיבים של ESC (issue #2528): תפריט הקשר, פאנל צף, דיאלוג
// ותוכן שמתחת — ESC סוגר רק את השכבה הפנימית ביותר.
void main() {
  late int underlyingEscapes;
  late int panelCloseCount;
  late bool panelOpen;
  late StateSetter setHarnessState;
  late FocusNode contentFocus;

  setUp(() {
    underlyingEscapes = 0;
    panelCloseCount = 0;
    panelOpen = true;
    contentFocus = FocusNode(debugLabel: 'content');
  });

  tearDown(() => contentFocus.dispose());

  ContextOverlayPanel buildPanel({required Widget child}) {
    return ContextOverlayPanel(
      isOpen: panelOpen,
      onClose: () {
        panelCloseCount++;
        setHarnessState(() => panelOpen = false);
      },
      child: child,
    );
  }

  Widget buildApp(Widget Function() body) {
    return MaterialApp(
      home: Scaffold(
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                underlyingEscapes++,
          },
          child: Focus(
            focusNode: contentFocus,
            autofocus: true,
            child: StatefulBuilder(
              builder: (context, setState) {
                setHarnessState = setState;
                return body();
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pressEscape(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(
    WidgetTester tester,
    GlobalKey<AppContextMenuRegionState> key,
    Offset at,
  ) async {
    await key.currentState!.openMenuAt(at);
    await tester.pumpAndSettle();
  }

  List<AppContextMenuEntry> menuEntries() => [
    AppContextMenuEntry(label: 'העתק', onTap: () {}),
  ];

  testWidgets('תפריט בתוך פאנל: ESC סוגר תפריט, אחר כך פאנל, אחר כך התוכן', (
    tester,
  ) async {
    final menuKey = GlobalKey<AppContextMenuRegionState>();
    await tester.pumpWidget(
      buildApp(
        () => Stack(
          children: [
            const SizedBox.expand(),
            buildPanel(
              child: AppContextMenuRegion(
                key: menuKey,
                menuBuilder: (_, _) => menuEntries(),
                child: const SizedBox(width: 300, height: 300),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final panelCenter = tester.getCenter(find.byType(ContextOverlayPanel));
    await openMenu(tester, menuKey, panelCenter);
    expect(find.text('העתק'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('העתק'), findsNothing);
    expect(panelCloseCount, 0);
    expect(underlyingEscapes, 0);

    await pressEscape(tester);
    expect(panelCloseCount, 1);
    expect(panelOpen, isFalse);
    expect(underlyingEscapes, 0);

    await pressEscape(tester);
    expect(panelCloseCount, 1);
    expect(underlyingEscapes, 1);
  });

  testWidgets('תפריט מעל פאנל כשהפוקוס בשדה בתוך הפאנל: אותו סדר', (
    tester,
  ) async {
    final menuKey = GlobalKey<AppContextMenuRegionState>();
    await tester.pumpWidget(
      buildApp(
        () => Stack(
          children: [
            AppContextMenuRegion(
              key: menuKey,
              menuBuilder: (_, _) => menuEntries(),
              child: const SizedBox.expand(),
            ),
            buildPanel(child: const TextField()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await openMenu(tester, menuKey, const Offset(50, 50));
    expect(find.text('העתק'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('העתק'), findsNothing);
    expect(panelCloseCount, 0);

    await pressEscape(tester);
    expect(panelCloseCount, 1);
    expect(underlyingEscapes, 0);
  });

  testWidgets('דיאלוג מעל פאנל פתוח: ESC סוגר רק את הדיאלוג', (tester) async {
    await tester.pumpWidget(
      buildApp(
        () => Stack(
          children: [
            const SizedBox.expand(),
            buildPanel(child: const Text('תוכן פאנל')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.text('תוכן פאנל')),
      builder: (_) => const AlertDialog(content: Text('דיאלוג')),
    );
    await tester.pumpAndSettle();

    await pressEscape(tester);
    expect(find.text('דיאלוג'), findsNothing);
    expect(panelCloseCount, 0);
    expect(underlyingEscapes, 0);

    await pressEscape(tester);
    expect(panelCloseCount, 1);
    expect(underlyingEscapes, 0);
  });

  testWidgets('תפריט בתוך דיאלוג מעל פאנל: תפריט, דיאלוג, פאנל, תוכן', (
    tester,
  ) async {
    final menuKey = GlobalKey<AppContextMenuRegionState>();
    await tester.pumpWidget(
      buildApp(
        () => Stack(
          children: [
            const SizedBox.expand(),
            buildPanel(child: const Text('תוכן פאנל')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.text('תוכן פאנל')),
      builder: (_) => AlertDialog(
        content: AppContextMenuRegion(
          key: menuKey,
          menuBuilder: (_, _) => menuEntries(),
          child: const SizedBox(width: 100, height: 100, child: Text('דיאלוג')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openMenu(tester, menuKey, tester.getCenter(find.text('דיאלוג')));
    expect(find.text('העתק'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('העתק'), findsNothing);
    expect(find.text('דיאלוג'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('דיאלוג'), findsNothing);
    expect(panelCloseCount, 0);

    await pressEscape(tester);
    expect(panelCloseCount, 1);

    await pressEscape(tester);
    expect(underlyingEscapes, 1);
  });

  testWidgets('תפריט בעמוד גלוי כשפאנל פתוח בעמוד מוסתר: הפאנל לא נפגע', (
    tester,
  ) async {
    final menuKey = GlobalKey<AppContextMenuRegionState>();
    await tester.pumpWidget(
      buildApp(
        () => Stack(
          children: [
            Offstage(
              child: Stack(
                children: [
                  const SizedBox.expand(),
                  buildPanel(child: const Text('תוכן פאנל')),
                ],
              ),
            ),
            AppContextMenuRegion(
              key: menuKey,
              menuBuilder: (_, _) => menuEntries(),
              child: const SizedBox.expand(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openMenu(tester, menuKey, const Offset(50, 50));
    expect(find.text('העתק'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('העתק'), findsNothing);
    expect(panelCloseCount, 0);
    expect(underlyingEscapes, 0);

    await pressEscape(tester);
    expect(panelCloseCount, 0);
    expect(panelOpen, isTrue);
    expect(underlyingEscapes, 1);
  });

  testWidgets(
    'פאנל שנפתח כשהתפריט כבר פתוח: ESC סוגר קודם את התפריט',
    (
      tester,
    ) async {
      panelOpen = false;
      final menuKey = GlobalKey<AppContextMenuRegionState>();
      await tester.pumpWidget(
        buildApp(
          () => Stack(
            children: [
              AppContextMenuRegion(
                key: menuKey,
                menuBuilder: (_, _) => menuEntries(),
                child: const SizedBox.expand(),
              ),
              buildPanel(child: const Text('תוכן פאנל')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openMenu(tester, menuKey, const Offset(50, 50));
      // התפריט אינו מחזיק פוקוס, כך שקיצור מקלדת יכול לפתוח פאנל מתחתיו.
      setHarnessState(() => panelOpen = true);
      await tester.pumpAndSettle();
      expect(find.text('העתק'), findsOneWidget);

      await pressEscape(tester);
      expect(find.text('העתק'), findsNothing);
      expect(panelCloseCount, 0);
    },
  );

  testWidgets('דיאלוג שנפתח מעל תפריט פתוח מקבל את ה-ESC הראשון', (
    tester,
  ) async {
    final menuKey = GlobalKey<AppContextMenuRegionState>();
    await tester.pumpWidget(
      buildApp(
        () => AppContextMenuRegion(
          key: menuKey,
          menuBuilder: (_, _) => menuEntries(),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await openMenu(tester, menuKey, const Offset(50, 50));
    showDialog<void>(
      context: menuKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('דיאלוג')),
    );
    await tester.pumpAndSettle();

    await pressEscape(tester);
    expect(find.text('דיאלוג'), findsNothing);
    expect(find.text('העתק'), findsOneWidget);

    await pressEscape(tester);
    expect(find.text('העתק'), findsNothing);
    expect(underlyingEscapes, 0);
  });

  testWidgets('שדה קלט מחוץ לפאנל מקבל את ה-ESC ולא הפאנל', (tester) async {
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);
    var fieldEscapes = 0;
    await tester.pumpWidget(
      buildApp(
        () => Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      fieldEscapes++,
                },
                child: SizedBox(
                  width: 200,
                  child: TextField(focusNode: fieldFocus),
                ),
              ),
            ),
            buildPanel(child: const SizedBox(width: 300, height: 300)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    fieldFocus.requestFocus();
    await tester.pump();

    await pressEscape(tester);
    expect(fieldEscapes, 1);
    expect(panelCloseCount, 0);
  });
}
