import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────────────────────────────────────────────────────
  // הקבצים הקשורים לבאג: בעת פתיחת תפריט הקשר, הסימון הוויזואלי של
  // SelectionArea היה נעלם כשהעכבר נכנס לאזור התפריט. הסיבה: MenuItemButton
  // ו-SubmenuButton של Flutter קוראים requestFocus() על focusNode פנימי
  // בריחוף, מה שגורם ל-SelectableRegion להפסיד את הפוקוס ולהפעיל
  // clearSelection(). כעת שני הסוגים אינם גוזלים פוקוס.
  // ───────────────────────────────────────────────────────────────────────

  Future<void> openContextMenu(
    WidgetTester tester, {
    required List<AppContextMenuEntry> entries,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppContextMenuRegion(
              menuBuilder: (_, __) => entries,
              child: const SizedBox(
                width: 100,
                height: 100,
                child: ColoredBox(color: Colors.amber),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final regionCenter = tester.getCenter(find.byType(AppContextMenuRegion));
    await gesture.moveTo(regionCenter);
    await gesture.down(regionCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
      'MenuItemButton בתפריט הקשר אינו גוזל פוקוס בריחוף - שומר את סימון הטקסט',
      (tester) async {
    await openContextMenu(
      tester,
      entries: [
        AppContextMenuEntry(label: 'העתק', onTap: () {}),
      ],
    );

    final button = tester.widget<MenuItemButton>(find.byType(MenuItemButton));
    expect(
      button.requestFocusOnHover,
      isFalse,
      reason:
          'הריחוף מעל פריט תפריט אסור שיגרור requestFocus, אחרת SelectableRegion '
          'יקבל focus loss וינקה את הסימון הוויזואלי',
    );
  });

  testWidgets('SubmenuButton בתפריט הקשר משתמש ב-FocusNode שלא יכול לגזול פוקוס',
      (tester) async {
    await openContextMenu(
      tester,
      entries: [
        AppContextMenuEntry(
          label: 'תת-תפריט',
          children: [AppContextMenuEntry(label: 'פנימי', onTap: () {})],
        ),
      ],
    );

    final submenu = tester.widget<SubmenuButton>(find.byType(SubmenuButton));
    expect(
      submenu.focusNode,
      isNotNull,
      reason:
          'SubmenuButton חייב לקבל focusNode חיצוני שנשלוט בו, אחרת יווצר focusNode '
          'פנימי שיגזול פוקוס בעת ריחוף ובעת פתיחת התת-תפריט',
    );
    expect(
      submenu.focusNode!.canRequestFocus,
      isFalse,
      reason:
          'ה-focusNode של SubmenuButton חייב להיות עם canRequestFocus:false כדי '
          'שקריאות requestFocus() הפנימיות לא יגזלו פוקוס מ-SelectableRegion',
    );
  });

  testWidgets(
      'ריחוף מעל פריט תפריט הקשר אינו מעביר את primaryFocus מ-FocusNode חיצוני',
      (tester) async {
    final externalFocusNode = FocusNode(debugLabel: 'ExternalSelection');
    addTearDown(externalFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(
                focusNode: externalFocusNode,
                child: const SizedBox(width: 50, height: 50),
              ),
              Center(
                child: AppContextMenuRegion(
                  menuBuilder: (_, __) => [
                    AppContextMenuEntry(label: 'העתק', onTap: () {}),
                    AppContextMenuEntry(label: 'גזור', onTap: () {}),
                  ],
                  child: const SizedBox(
                    width: 100,
                    height: 100,
                    child: ColoredBox(color: Colors.amber),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    externalFocusNode.requestFocus();
    await tester.pump();
    expect(externalFocusNode.hasFocus, isTrue);

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final regionCenter = tester.getCenter(find.byType(AppContextMenuRegion));
    await gesture.moveTo(regionCenter);
    await gesture.down(regionCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // ריחוף מעל פריט בתפריט - לפני התיקון היה גורר requestFocus
    final itemCenter = tester.getCenter(find.text('העתק'));
    await gesture.moveTo(itemCenter);
    await tester.pumpAndSettle();

    expect(
      externalFocusNode.hasFocus,
      isTrue,
      reason:
          'ריחוף מעל פריט בתפריט הקשר אסור לגזול פוקוס מ-FocusNode חיצוני - '
          'אחרת SelectableRegion יקבל focus loss וינקה את הסימון',
    );
  });

  testWidgets(
      'ריחוף מעל SubmenuButton אינו מעביר את primaryFocus מ-FocusNode חיצוני',
      (tester) async {
    final externalFocusNode = FocusNode(debugLabel: 'ExternalSelection');
    addTearDown(externalFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(
                focusNode: externalFocusNode,
                child: const SizedBox(width: 50, height: 50),
              ),
              Center(
                child: AppContextMenuRegion(
                  menuBuilder: (_, __) => [
                    AppContextMenuEntry(
                      label: 'תת-תפריט',
                      children: [
                        AppContextMenuEntry(label: 'פנימי', onTap: () {}),
                      ],
                    ),
                  ],
                  child: const SizedBox(
                    width: 100,
                    height: 100,
                    child: ColoredBox(color: Colors.amber),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    externalFocusNode.requestFocus();
    await tester.pump();
    expect(externalFocusNode.hasFocus, isTrue);

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final regionCenter = tester.getCenter(find.byType(AppContextMenuRegion));
    await gesture.moveTo(regionCenter);
    await gesture.down(regionCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // ריחוף מעל SubmenuButton - בלי התיקון, פותח את התת-תפריט וגוזל פוקוס.
    final submenuCenter = tester.getCenter(find.text('תת-תפריט'));
    await gesture.moveTo(submenuCenter);
    await tester.pumpAndSettle();

    expect(
      externalFocusNode.hasFocus,
      isTrue,
      reason:
          'ריחוף מעל SubmenuButton אסור לגזול פוקוס מ-FocusNode חיצוני, '
          'גם כשהוא פותח את התת-תפריט',
    );
  });

  testWidgets(
      'capturedText: פעולת תפריט משתמשת בערך שנלכד בזמן הבנייה, לא בזמן הלחיצה',
      (tester) async {
    // ——————————————————————————————————————————————————————————————————————
    // מדמה את תבנית savedTextAtBuild ב-_buildLine של SimpleTextViewer:
    //   final savedTextAtBuild = _savedSelectedText;  // נלכד בזמן BUILD
    //   menuBuilder: (ctx, pos) => _buildContextMenu(..., savedTextAtBuild)
    //
    // הסצנריו המבדוק: ה-menuBuilder נבנה כשיש טקסט נבחר. לאחר פתיחת התפריט,
    // onSelectionChanged(null) מנקה את _savedSelectedText (= liveValue=null).
    // הפעולה בתפריט חייבת להשתמש בערך שנלכד בזמן הבנייה ולא בערך המנוקה.
    // ——————————————————————————————————————————————————————————————————————
    String? capturedInAction;
    String? liveValue = 'טקסט נבחר';
    late StateSetter outerSetState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              outerSetState = setState;
              final valueAtBuild = liveValue; // כמו savedTextAtBuild ב-_buildLine
              return AppContextMenuRegion(
                menuBuilder: (_, __) => [
                  AppContextMenuEntry(
                    label: 'העתק',
                    enabled: valueAtBuild != null,
                    onTap: () => capturedInAction = valueAtBuild,
                  ),
                ],
                child: const SizedBox(
                  width: 200,
                  height: 200,
                  child: ColoredBox(color: Colors.amber),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // פתיחת תפריט הקשר — בונה entries עם valueAtBuild = 'טקסט נבחר'
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final regionCenter = tester.getCenter(find.byType(AppContextMenuRegion));
    await gesture.moveTo(regionCenter);
    await gesture.down(regionCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // מדמה onSelectionChanged(null) שמנקה את _savedSelectedText אחרי פתיחת התפריט
    outerSetState(() => liveValue = null);
    await tester.pump();

    // לחיצה על הפריט בתפריט — חייב להשתמש בערך שנלכד בזמן הבנייה
    await tester.tap(find.text('העתק'));
    await tester.pumpAndSettle();

    expect(
      capturedInAction,
      'טקסט נבחר',
      reason:
          'הפעולה חייבת להשתמש ב-capturedText שנלכד בזמן הבנייה, '
          'גם אחרי ניקוי הערך ע"י onSelectionChanged(null)',
    );
  });
}
