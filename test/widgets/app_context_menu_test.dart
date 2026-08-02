import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';

import '../support/preview_selection_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // חלונית מקובעת שורדת את סגירת התפריט — יש לסגור אותה בין טסטים.
  tearDown(LinkPreviewOverlay.dismiss);

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
              menuBuilder: (_, _) => entries,
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
    },
  );

  testWidgets('SubmenuButton בתפריט הקשר משתמש ב-FocusNode שלא יכול לגזול פוקוס', (
    tester,
  ) async {
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
                    menuBuilder: (_, _) => [
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
    },
  );

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
                    menuBuilder: (_, _) => [
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
    },
  );

  testWidgets('ריחוף מעל SubmenuButton פותח את התת-תפריט אחרי השהיה (בלי לחיצה)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppContextMenuRegion(
              menuBuilder: (_, _) => [
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
        ),
      ),
    );

    // פתיחת תפריט ההקשר עם לחיצה ימנית
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

    expect(
      find.text('פנימי'),
      findsNothing,
      reason: 'התת-תפריט אמור להיות סגור לפני הריחוף',
    );

    // ריחוף מעל פריט התת-תפריט — אמור לפתוח אותו אחרי השהיית 300ms, בלי לחיצה.
    // (לפני התיקון: השבתת הפוקוס ביטלה את הפתיחה-בריחוף המובנית של SubmenuButton.)
    await gesture.moveTo(tester.getCenter(find.text('תת-תפריט')));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();

    expect(
      find.text('פנימי'),
      findsOneWidget,
      reason: 'ריחוף מעל פריט התת-תפריט חייב לפתוח אותו בלי צורך בלחיצה',
    );
  });

  testWidgets('מעבר עכבר חולף (פחות מההשהיה) אינו פותח את התת-תפריט', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppContextMenuRegion(
              menuBuilder: (_, _) => [
                AppContextMenuEntry(
                  label: 'תת-תפריט',
                  children: [
                    AppContextMenuEntry(label: 'פנימי', onTap: () {}),
                  ],
                ),
                AppContextMenuEntry(label: 'פריט רגיל', onTap: () {}),
              ],
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

    // ריחוף קצר מעל התת-תפריט ויציאה ממנו לפני שההשהיה הסתיימה
    await gesture.moveTo(tester.getCenter(find.text('תת-תפריט')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(find.text('פריט רגיל')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(
      find.text('פנימי'),
      findsNothing,
      reason: 'יציאה מהפריט לפני תום ההשהיה חייבת לבטל את הפתיחה-בריחוף',
    );
  });

  testWidgets('גרירה לבחירת טקסט מחוץ לתפריט סוגרת את התפריט', (tester) async {
    // בדיקה עצמאית — מנהלת את כל ה-gestures ידנית כדי לשלוט בסדר down/up
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppContextMenuRegion(
              menuBuilder: (_, _) => [
                AppContextMenuEntry(label: 'העתק', onTap: () {}),
              ],
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

    // פתיחת התפריט עם לחיצה ימנית
    final rightGesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await rightGesture.addPointer(location: Offset.zero);
    addTearDown(rightGesture.removePointer);

    final regionCenter = tester.getCenter(find.byType(AppContextMenuRegion));
    await rightGesture.moveTo(regionCenter);
    await rightGesture.down(regionCenter);
    await tester.pump();
    await rightGesture.up();
    await tester.pumpAndSettle();

    expect(
      find.text('העתק'),
      findsOneWidget,
      reason: 'התפריט צריך להיות פתוח לפני הגרירה',
    );

    // מסיר את ה-gesture הימני לפני יצירת ה-gesture השמאלי —
    // mouse tracker דורש שה-pointer יוסר לפני הוספת pointer חדש מאותו device kind
    await rightGesture.removePointer();

    // מדמה תחילת גרירה לבחירת טקסט: רק pointer DOWN, ללא UP
    final leftGesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await leftGesture.addPointer(location: Offset.zero);
    addTearDown(leftGesture.removePointer);

    await leftGesture.down(const Offset(10, 10));
    await tester.pump();

    expect(
      find.text('העתק'),
      findsNothing,
      reason:
          'pointer DOWN מחוץ לתפריט (תחילת גרירה) חייב לסגור את התפריט — '
          'לפני התיקון רק onTap (down+up ללא תנועה) היה סוגר',
    );

    await leftGesture.moveBy(const Offset(50, 0));
    await tester.pumpAndSettle();

    expect(
      find.text('העתק'),
      findsNothing,
      reason: 'התפריט צריך להישאר סגור גם לאחר המשך הגרירה',
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
                final valueAtBuild =
                    liveValue; // כמו savedTextAtBuild ב-_buildLine
                return AppContextMenuRegion(
                  menuBuilder: (_, _) => [
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
    },
  );

  // ───────────────────────────────────────────────────────────────────────
  // shouldPreserveSelectionOnSecondaryTap — חסימת שחרור הבחירה בלחיצה ימנית
  //
  // ב-Windows, ה-recognizer של SelectableRegion (אב) יורה onSecondaryTapDown
  // אחרי kPressTimeout (100ms) ומשחרר את הבחירה. כשיש בחירה, AppContextMenuRegion
  // זוכה באופן eager בכפתור הימני ודוחה את האב לפני ה-deadline. אנו מדמים את
  // SelectableRegion עם GestureDetector אב, ובודקים שה-onSecondaryTapDown שלו
  // אינו נורה — גם בהחזקה ארוכה (>100ms).
  // ───────────────────────────────────────────────────────────────────────

  Future<bool> rightClickAndReportOuterFired(
    WidgetTester tester, {
    required bool preserveSelection,
  }) async {
    var outerFired = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // מדמה את ה-TapGestureRecognizer לכפתור הימני של SelectableRegion (אב)
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onSecondaryTapDown: (_) => outerFired = true,
              child: AppContextMenuRegion(
                shouldPreserveSelectionOnSecondaryTap: (_) => preserveSelection,
                menuBuilder: (_, _) => [
                  AppContextMenuEntry(label: 'העתק', onTap: () {}),
                ],
                child: const SizedBox(
                  width: 100,
                  height: 100,
                  child: ColoredBox(color: Colors.amber),
                ),
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
    // החזקה מעבר ל-kPressTimeout (100ms) — כך שאצל האב ה-deadline היה יורה
    // onSecondaryTapDown אלמלא נדחה מהזירה.
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    return outerFired;
  }

  testWidgets(
    'בחירה פעילה: לחיצה ימנית חוסמת את ה-recognizer החיצוני (הבחירה נשמרת)',
    (tester) async {
      final outerFired = await rightClickAndReportOuterFired(
        tester,
        preserveSelection: true,
      );

      expect(
        outerFired,
        isFalse,
        reason:
            'כשיש בחירה, AppContextMenuRegion זוכה eager בכפתור הימני — '
            'SelectableRegion (האב) נדחה ולא משחרר את הבחירה',
      );
      expect(
        find.text('העתק'),
        findsOneWidget,
        reason: 'התפריט עדיין נפתח דרך ה-Listener שאינו תלוי בזירה',
      );
    },
  );

  testWidgets(
    'בלי בחירה: לחיצה ימנית אינה חוסמת את ה-recognizer החיצוני (התנהגות רגילה)',
    (tester) async {
      final outerFired = await rightClickAndReportOuterFired(
        tester,
        preserveSelection: false,
      );

      expect(
        outerFired,
        isTrue,
        reason: 'בלי בחירה ה-recognizer אינו מתערב — האב מקבל את הלחיצה כרגיל',
      );
      expect(
        find.text('העתק'),
        findsOneWidget,
        reason: 'התפריט נפתח גם כשאין בחירה',
      );
    },
  );

  testWidgets('onSecondaryTapDown נקרא בלחיצה ימנית עבור שמירת ההקשר', (
    tester,
  ) async {
    var savedContext = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppContextMenuRegion(
              onSecondaryTapDown: (_) => savedContext = true,
              menuBuilder: (_, _) => [
                AppContextMenuEntry(label: 'העתק', onTap: () {}),
              ],
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

    expect(
      savedContext,
      isTrue,
      reason: 'onSecondaryTapDown חייב להיקרא כדי לשמור את הקשר השורה לתפריט',
    );
  });

  group('onHoverEnter — טעינה מקדימה של תוכן התפריט', () {
    Future<int> hoverEnterCount(
      WidgetTester tester, {
      required bool withCallback,
      bool moveAwayAndBack = false,
    }) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppContextMenuRegion(
                onHoverEnter: withCallback ? () => calls++ : null,
                menuBuilder: (_, _) => [
                  AppContextMenuEntry(label: 'העתק', onTap: () {}),
                ],
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

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final center = tester.getCenter(find.byType(AppContextMenuRegion));
      await gesture.moveTo(center);
      await tester.pumpAndSettle();
      if (moveAwayAndBack) {
        await gesture.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        await gesture.moveTo(center);
        await tester.pumpAndSettle();
      }
      return calls;
    }

    testWidgets('ריחוף על האזור מפעיל את ה-callback', (tester) async {
      expect(await hoverEnterCount(tester, withCallback: true), 1);
    });

    testWidgets('יציאה וחזרה מפעילות שוב (ה-prefetch עצמו אידמפוטנטי)', (
      tester,
    ) async {
      expect(
        await hoverEnterCount(
          tester,
          withCallback: true,
          moveAwayAndBack: true,
        ),
        2,
      );
    });

    testWidgets('בלי onHoverEnter לא נוסף MouseRegion עוטף', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppContextMenuRegion(
                menuBuilder: (_, _) => [
                  AppContextMenuEntry(label: 'העתק', onTap: () {}),
                ],
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(AppContextMenuRegion),
          matching: find.byType(MouseRegion),
        ),
        findsNothing,
      );
    });

    testWidgets('הריחוף אינו פותח את התפריט מעצמו', (tester) async {
      await hoverEnterCount(tester, withCallback: true);
      expect(find.text('העתק'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // openMenuAt — פתיחה פרוגרמטית (משמש ל-long press ב-PDF)
  // ───────────────────────────────────────────────────────────────────────

  testWidgets(
    'AppContextMenuRegionState נגישה דרך GlobalKey ומאפשרת openMenuAt',
    (tester) async {
      final key = GlobalKey<AppContextMenuRegionState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppContextMenuRegion(
              key: key,
              menuBuilder: (_, _) => [
                AppContextMenuEntry(label: 'העתק', onTap: () {}),
              ],
              child: const SizedBox(
                width: 200,
                height: 200,
                child: ColoredBox(color: Colors.amber),
              ),
            ),
          ),
        ),
      );

      expect(
        key.currentState,
        isNotNull,
        reason: 'AppContextMenuRegionState חייב להיות נגיש דרך GlobalKey',
      );

      await key.currentState!.openMenuAt(const Offset(100, 100));
      await tester.pumpAndSettle();

      expect(
        find.text('העתק'),
        findsOneWidget,
        reason: 'openMenuAt חייב לפתוח את התפריט עם הפריטים שנבנו',
      );
    },
  );

  testWidgets('openMenuAt: לחיצה על פריט מפעילה את onTap ומכסה את התפריט', (
    tester,
  ) async {
    final key = GlobalKey<AppContextMenuRegionState>();
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppContextMenuRegion(
            key: key,
            menuBuilder: (_, _) => [
              AppContextMenuEntry(label: 'פעולה א', onTap: () => tapped = true),
              AppContextMenuEntry(label: 'פעולה ב', onTap: () {}),
            ],
            child: const SizedBox(
              width: 200,
              height: 200,
              child: ColoredBox(color: Colors.amber),
            ),
          ),
        ),
      ),
    );

    await key.currentState!.openMenuAt(const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(find.text('פעולה א'), findsOneWidget);
    expect(find.text('פעולה ב'), findsOneWidget);

    await tester.tap(find.text('פעולה א'));
    await tester.pumpAndSettle();

    expect(
      tapped,
      isTrue,
      reason: 'לחיצה על פריט אחרי openMenuAt חייבת להפעיל את ה-onTap שלו',
    );
    expect(
      find.text('פעולה א'),
      findsNothing,
      reason: 'התפריט חייב להיסגר לאחר בחירת פריט',
    );
  });

  testWidgets(
    'childrenRefreshStream: פעימה מסירה שורה מתת-התפריט בלי לסגור אותו',
    (tester) async {
      // משחזר את רשימת "כרטיסיות פתוחות": לחיצה על X מסירה כרטיסייה ממקור
      // הנתונים, פעימת הסטרים בונה מחדש את תת-התפריט והשורה נעלמת — התפריט נשאר.
      final controller = StreamController<Object?>.broadcast();
      addTearDown(controller.close);
      final tabs = ['ראב"ד', 'עירובין'];
      final key = GlobalKey<AppContextMenuRegionState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppContextMenuRegion(
              key: key,
              menuBuilder: (_, _) => [
                AppContextMenuEntry(
                  label: 'כרטיסיות פתוחות',
                  childrenRefreshStream: controller.stream,
                  childrenBuilder: () => tabs
                      .map(
                        (t) => AppContextMenuEntry(
                          label: t,
                          onTap: () {},
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              tabs.remove(t);
                              controller.add(null);
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              child: const SizedBox(
                width: 200,
                height: 200,
                child: ColoredBox(color: Colors.amber),
              ),
            ),
          ),
        ),
      );

      await key.currentState!.openMenuAt(const Offset(100, 100));
      await tester.pumpAndSettle();

      await tester.tap(find.text('כרטיסיות פתוחות'));
      await tester.pumpAndSettle();
      expect(find.text('ראב"ד'), findsOneWidget);
      expect(find.text('עירובין'), findsOneWidget);

      // לחיצה על ה-X של "ראב"ד" — מסירה אותו ופולטת בסטרים
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(
        find.text('ראב"ד'),
        findsNothing,
        reason: 'שורת הכרטיסייה שנסגרה חייבת להיעלם מתת-התפריט',
      );
      expect(
        find.text('עירובין'),
        findsOneWidget,
        reason: 'שאר הכרטיסיות נשארות',
      );
      expect(
        find.text('כרטיסיות פתוחות'),
        findsOneWidget,
        reason: 'התפריט נשאר פתוח — רק השורה הוסרה',
      );
    },
  );

  testWidgets('openMenuAt: קריאה כפולה אינה פותחת שני תפריטים', (tester) async {
    final key = GlobalKey<AppContextMenuRegionState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppContextMenuRegion(
            key: key,
            menuBuilder: (_, _) => [
              AppContextMenuEntry(label: 'פריט', onTap: () {}),
            ],
            child: const SizedBox(
              width: 200,
              height: 200,
              child: ColoredBox(color: Colors.amber),
            ),
          ),
        ),
      ),
    );

    await key.currentState!.openMenuAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(find.text('פריט'), findsOneWidget);

    // פתיחה שנייה — אמור להחליף את הקיים ולא ליצור כפול
    await key.currentState!.openMenuAt(const Offset(100, 100));
    await tester.pumpAndSettle();

    expect(
      find.text('פריט'),
      findsOneWidget,
      reason: 'קריאה כפולה ל-openMenuAt לא אמורה לפתוח שני תפריטים',
    );
  });

  testWidgets(
    'תפריט ארוך שאין לו מקום מתחת ללחיצה עולה כלפי מעלה ואינו נחתך בתחתית',
    (tester) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      // 12 פריטים (~448px) — גבוה מהמרחב שמתחת ללחיצה אך נכנס בגובה המסך (600).
      final entries = [
        for (var i = 0; i < 12; i++)
          AppContextMenuEntry(label: 'פריט $i', onTap: () {}),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppContextMenuRegion(
              key: key,
              menuBuilder: (_, _) => entries,
              child: const SizedBox.expand(
                child: ColoredBox(color: Colors.amber),
              ),
            ),
          ),
        ),
      );

      // לחיצה בחצי העליון (y=200): אין מקום מספיק מתחת והמרחב מעל קטן מהמרחב מתחת,
      // כך שהתפריט נפתח כלפי מטה — לפני התיקון נחתך/נגלל ופריטיו האחרונים נסתרו.
      await key.currentState!.openMenuAt(const Offset(400, 200));
      await tester.pumpAndSettle();

      final overlaySize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final lastItem = find.text('פריט 11');
      expect(lastItem, findsOneWidget);
      expect(
        tester.getRect(lastItem).bottom,
        lessThanOrEqualTo(overlaySize.height),
        reason:
            'הפריט האחרון חייב להישאר בגבולות המסך — '
            'כשאין מקום מתחת ללחיצה התפריט עולה מעלה ולא נחתך',
      );
    },
  );

  // ───────────────────────────────────────────────────────────────────────
  // hoverPreviewBuilder — חלונית תצוגה מקדימה צפה ברפרוף על פריט
  //
  // משמש את תת-תפריט "קישורים": רפרוף על קישור פותח חלונית צפה עם תוכן
  // הקישור, שנעלמת כשהסמן עוזב גם את הפריט וגם את החלונית עצמה.
  // ───────────────────────────────────────────────────────────────────────

  group('hoverPreviewBuilder', () {
    const previewText = 'תוכן תצוגה מקדימה';

    Future<TestGesture> pumpMenuWithPreviewEntry(
      WidgetTester tester, {
      bool insideSubmenu = false,
      WidgetBuilder? previewBuilder,
    }) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      final previewEntry = AppContextMenuEntry(
        label: 'קישור א',
        onTap: () {},
        hoverPreviewBuilder: previewBuilder ?? (_) => const Text(previewText),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppContextMenuRegion(
              key: key,
              menuBuilder: (_, _) => [
                if (insideSubmenu)
                  AppContextMenuEntry(
                    label: 'קישורים',
                    childrenBuilder: () => [previewEntry],
                  )
                else
                  previewEntry,
              ],
              child: const SizedBox(
                width: 400,
                height: 400,
                child: ColoredBox(color: Colors.amber),
              ),
            ),
          ),
        ),
      );

      await key.currentState!.openMenuAt(const Offset(100, 100));
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      return gesture;
    }

    testWidgets('ריחוף על פריט עם תצוגה מקדימה פותח חלונית צפה אחרי השהיה', (
      tester,
    ) async {
      final gesture = await pumpMenuWithPreviewEntry(tester);

      await gesture.moveTo(tester.getCenter(find.text('קישור א')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text(previewText),
        findsNothing,
        reason: 'החלונית לא נפתחת לפני תום השהיית הפתיחה',
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        find.text(previewText),
        findsOneWidget,
        reason: 'אחרי תום ההשהיה החלונית הצפה מוצגת',
      );
    });

    testWidgets('ריחוף חולף (פחות מההשהיה) אינו פותח חלונית', (tester) async {
      final gesture = await pumpMenuWithPreviewEntry(tester);

      await gesture.moveTo(tester.getCenter(find.text('קישור א')));
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.moveTo(const Offset(10, 590));
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.text(previewText),
        findsNothing,
        reason: 'יציאה מהפריט לפני תום ההשהיה מבטלת את פתיחת החלונית',
      );
    });

    testWidgets('יציאה מהפריט סוגרת את החלונית אחרי השהיה קצרה', (
      tester,
    ) async {
      final gesture = await pumpMenuWithPreviewEntry(tester);

      await gesture.moveTo(tester.getCenter(find.text('קישור א')));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.text(previewText), findsOneWidget);

      await gesture.moveTo(const Offset(10, 590));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.text(previewText),
        findsNothing,
        reason: 'כשהסמן עוזב את הפריט (ולא נכנס לחלונית) — החלונית נעלמת',
      );
    });

    testWidgets('מעבר מהפריט אל החלונית משאיר אותה פתוחה, ויציאה ממנה סוגרת', (
      tester,
    ) async {
      final gesture = await pumpMenuWithPreviewEntry(tester);

      await gesture.moveTo(tester.getCenter(find.text('קישור א')));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.text(previewText), findsOneWidget);

      // מעבר אל תוך החלונית — ההשהיה הקצרה מאפשרת לחצות את הרווח
      await gesture.moveTo(tester.getCenter(find.text(previewText)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        find.text(previewText),
        findsOneWidget,
        reason: 'ריחוף על החלונית עצמה משאיר אותה פתוחה',
      );

      // יציאה מהחלונית — נסגרת אחרי ההשהיה
      await gesture.moveTo(const Offset(10, 590));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        find.text(previewText),
        findsNothing,
        reason: 'יציאה מהחלונית הצפה סוגרת אותה',
      );
    });

    testWidgets('תצוגה מקדימה פועלת גם על פריט בתוך תת-תפריט (כמו "קישורים")', (
      tester,
    ) async {
      final gesture = await pumpMenuWithPreviewEntry(
        tester,
        insideSubmenu: true,
      );

      await tester.tap(find.text('קישורים'));
      await tester.pumpAndSettle();
      expect(find.text('קישור א'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(find.text('קישור א')));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(
        find.text(previewText),
        findsOneWidget,
        reason: 'רפרוף על קישור בתת-תפריט פותח את חלונית התוכן',
      );
    });

    testWidgets(
      'חלונית שגדלה אחרי טעינת תוכן אסינכרוני אינה נחתכת בתחתית המסך',
      (tester) async {
        final key = GlobalKey<AppContextMenuRegionState>();
        const smallKey = ValueKey('loading-content');
        const grownKey = ValueKey('grown-content');
        // מדמה את טעינת תוכן הקישור: בהתחלה קטן (כמו ספינר), ואחרי
        // שהחלונית כבר מוקמה — גדל משמעותית.
        final grownNotifier = ValueNotifier(false);
        addTearDown(grownNotifier.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppContextMenuRegion(
                key: key,
                menuBuilder: (_, _) => [
                  AppContextMenuEntry(
                    label: 'קישור א',
                    onTap: () {},
                    hoverPreviewBuilder: (_) => ValueListenableBuilder<bool>(
                      valueListenable: grownNotifier,
                      builder: (context, grown, _) => grown
                          ? const SizedBox(
                              key: grownKey,
                              width: 200,
                              height: 500,
                            )
                          : const SizedBox(
                              key: smallKey,
                              width: 200,
                              height: 40,
                            ),
                    ),
                  ),
                ],
                child: const SizedBox.expand(
                  child: ColoredBox(color: Colors.amber),
                ),
              ),
            ),
          ),
        );

        // פתיחת התפריט סמוך לתחתית המסך (ברירת מחדל בטסטים: 800x600)
        await key.currentState!.openMenuAt(const Offset(400, 560));
        await tester.pumpAndSettle();

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);

        await gesture.moveTo(tester.getCenter(find.text('קישור א')));
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        expect(
          find.byKey(smallKey),
          findsOneWidget,
          reason: 'החלונית נפתחת עם תוכן הטעינה הקטן',
        );

        // התוכן "נטען" והחלונית גדלה — אחרי שכבר מוקמה לפי הגודל הקטן
        grownNotifier.value = true;
        await tester.pumpAndSettle();

        final grown = find.byKey(grownKey);
        expect(
          grown,
          findsOneWidget,
          reason: 'התוכן המלא אמור להופיע אחרי הטעינה',
        );

        final overlaySize =
            tester.view.physicalSize / tester.view.devicePixelRatio;
        final panelRect = tester.getRect(
          find.ancestor(of: grown, matching: find.byType(Material)).first,
        );
        expect(
          panelRect.bottom,
          lessThanOrEqualTo(overlaySize.height),
          reason:
              'החלונית חייבת להישאר בגבולות המסך גם אחרי שהתוכן גדל — '
              'גדילה אסינכרונית מחייבת הצמדה מחדש של המיקום',
        );
      },
    );

    testWidgets('לחיצה על הפריט סוגרת את התפריט ואת החלונית יחד', (
      tester,
    ) async {
      final gesture = await pumpMenuWithPreviewEntry(tester);

      await gesture.moveTo(tester.getCenter(find.text('קישור א')));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.text(previewText), findsOneWidget);

      await tester.tap(find.text('קישור א'));
      await tester.pumpAndSettle();

      expect(
        find.text('קישור א'),
        findsNothing,
        reason: 'התפריט נסגר לאחר בחירת הפריט',
      );
      expect(
        find.text(previewText),
        findsNothing,
        reason: 'החלונית הצפה מוסרת יחד עם סגירת התפריט',
      );
    });

    // ─────────────────────────────────────────────────────────────────────
    // קיבוע התצוגה המקדימה: לחיצה בתוכה הופכת אותה לחלונית עצמאית שנשארת
    // אחרי סגירת התפריט. חובה שאותו עץ widgets יישמר — בנייה מחדש בקיבוע
    // מאבדת את גרירת הסימון (המשתמש נדרש לגרור פעמיים) ומהבהבת את החלונית.
    // ─────────────────────────────────────────────────────────────────────
    group('קיבוע בלחיצה בתוך החלונית', () {
      Future<TestGesture> hoverUntilPreview(
        WidgetTester tester, {
        WidgetBuilder? previewBuilder,
        bool insideSubmenu = false,
      }) async {
        final gesture = await pumpMenuWithPreviewEntry(
          tester,
          previewBuilder: previewBuilder,
          insideSubmenu: insideSubmenu,
        );
        if (insideSubmenu) {
          await tester.tap(find.text('קישורים'));
          await tester.pumpAndSettle();
        }
        await gesture.moveTo(tester.getCenter(find.text('קישור א')));
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        return gesture;
      }

      testWidgets('גרירה לסימון טקסט מסמנת מיד, והחלונית נשארת בלי התפריט', (
        tester,
      ) async {
        const selectableText = 'אבגד הוזח טיכל';
        await hoverUntilPreview(
          tester,
          previewBuilder: (_) => const Text(selectableText),
        );
        expect(find.text(selectableText), findsOneWidget);

        await dragAcross(tester, find.text(selectableText));

        expect(
          find.text('קישור א'),
          findsNothing,
          reason: 'הלחיצה בתוך החלונית סוגרת את תפריט ההקשר',
        );
        expect(
          find.text(selectableText),
          findsOneWidget,
          reason: 'החלונית מקובעת ושורדת את סגירת התפריט',
        );
        expect(
          await selectionExistsInPanel(tester, find.text(selectableText)),
          isTrue,
          reason:
              'הגרירה הראשונה חייבת לסמן טקסט — בנייה מחדש של החלונית בקיבוע '
              'הייתה קוטעת אותה ומחייבת גרירה שנייה',
        );
      });

      testWidgets('הקיבוע אינו בונה מחדש את החלונית ואינו מזיז אותה', (
        tester,
      ) async {
        CountingPreviewContent.builds = 0;
        await hoverUntilPreview(
          tester,
          previewBuilder: (_) => const CountingPreviewContent(),
        );
        expect(CountingPreviewContent.builds, 1);
        final panel = find
            .ancestor(
              of: find.byType(CountingPreviewContent),
              matching: find.byType(Material),
            )
            .first;
        final rectBefore = tester.getRect(panel);

        await tester.tapAt(
          tester.getCenter(find.byType(CountingPreviewContent)),
        );
        await tester.pumpAndSettle();

        expect(
          CountingPreviewContent.builds,
          1,
          reason: 'אותו עץ widgets נשמר — בנייה מחדש היא ההבהוב שדווח',
        );
        expect(
          tester.getRect(panel),
          rectBefore,
          reason: 'החלונית אינה זזה בקיבוע',
        );
      });

      testWidgets('חלונית מקובעת נשארת גם כשהסמן יוצא ממנה', (tester) async {
        final gesture = await hoverUntilPreview(tester);

        final previewCenter = tester.getCenter(find.text(previewText));
        await gesture.moveTo(previewCenter);
        await gesture.down(previewCenter);
        await gesture.up();
        await tester.pumpAndSettle();

        await gesture.moveTo(const Offset(10, 590));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(
          find.text(previewText),
          findsOneWidget,
          reason: 'קיבוע מבטל את הסגירה ביציאת הסמן',
        );
      });

      testWidgets('הקשה מחוץ לחלונית המקובעת סוגרת אותה', (tester) async {
        await hoverUntilPreview(tester);

        await tester.tapAt(tester.getCenter(find.text(previewText)));
        await tester.pumpAndSettle();
        expect(find.text(previewText), findsOneWidget);

        await tester.tapAt(const Offset(700, 550));
        await tester.pumpAndSettle();
        expect(find.text(previewText), findsNothing);
      });

      testWidgets('קיבוע פועל גם על תצוגה מקדימה של פריט בתת-תפריט', (
        tester,
      ) async {
        await hoverUntilPreview(tester, insideSubmenu: true);
        expect(find.text(previewText), findsOneWidget);

        await tester.tapAt(tester.getCenter(find.text(previewText)));
        await tester.pumpAndSettle();

        expect(find.text('קישור א'), findsNothing);
        expect(
          find.text(previewText),
          findsOneWidget,
          reason: 'החלונית שורדת גם את סגירת התת-תפריט',
        );
      });
    });

    group('מגע — לחיצה ארוכה במקום רפרוף', () {
      Future<void> pumpTouchMenu(WidgetTester tester) async {
        final key = GlobalKey<AppContextMenuRegionState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppContextMenuRegion(
                key: key,
                menuBuilder: (_, _) => [
                  AppContextMenuEntry(
                    label: 'קישור א',
                    onTap: () {},
                    hoverPreviewBuilder: (_) => const Text(previewText),
                  ),
                ],
                child: const SizedBox(
                  width: 400,
                  height: 400,
                  child: ColoredBox(color: Colors.amber),
                ),
              ),
            ),
          ),
        );
        await key.currentState!.openMenuAt(const Offset(100, 100));
        await tester.pumpAndSettle();
      }

      testWidgets('לחיצה ארוכה על הפריט פותחת את החלונית הצפה', (tester) async {
        await pumpTouchMenu(tester);

        await tester.longPress(find.text('קישור א'));
        await tester.pumpAndSettle();

        expect(
          find.text(previewText),
          findsOneWidget,
          reason: 'לחיצה ארוכה מחליפה את הרפרוף ופותחת את התצוגה',
        );
      });

      testWidgets('הקשה מחוץ לחלונית סוגרת אותה ומשאירה את התפריט פתוח', (
        tester,
      ) async {
        await pumpTouchMenu(tester);

        await tester.longPress(find.text('קישור א'));
        await tester.pumpAndSettle();
        expect(find.text(previewText), findsOneWidget);

        await tester.tapAt(const Offset(10, 590));
        await tester.pumpAndSettle();

        expect(
          find.text(previewText),
          findsNothing,
          reason: 'הקשה על המחסום מחוץ לחלונית סוגרת את התצוגה',
        );
        expect(
          find.text('קישור א'),
          findsOneWidget,
          reason: 'התפריט עצמו נשאר פתוח להמשך בחירה',
        );
      });
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // לחיצה ארוכה פותחת תפריט הקשר רק במגע/עט — בעכבר משתמשים בלחיצה ימנית
  // ───────────────────────────────────────────────────────────────────────
  group('לחיצה ארוכה פותחת תפריט הקשר רק במגע', () {
    Future<void> pumpRegion(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppContextMenuRegion(
                menuBuilder: (_, _) => [
                  AppContextMenuEntry(label: 'העתק', onTap: () {}),
                ],
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
    }

    testWidgets('לחיצה ארוכה במגע פותחת את התפריט', (tester) async {
      await pumpRegion(tester);

      final center = tester.getCenter(find.byType(AppContextMenuRegion));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.touch,
      );
      addTearDown(() async => gesture.up());
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(
        find.text('העתק'),
        findsOneWidget,
        reason: 'לחיצה ארוכה במגע צריכה לפתוח את תפריט ההקשר',
      );
    });

    testWidgets('החזקת לחיצה שמאלית בעכבר אינה פותחת את התפריט', (
      tester,
    ) async {
      await pumpRegion(tester);

      final center = tester.getCenter(find.byType(AppContextMenuRegion));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      addTearDown(() async => gesture.up());
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(
        find.text('העתק'),
        findsNothing,
        reason: 'החזקת לחיצה שמאלית בעכבר אסור שתפתח תפריט — רק לחיצה ימנית',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // AppContextMenuEntry.iconRow — שורת כפתורי אייקון בראש התפריט (Windows 11)
  // ───────────────────────────────────────────────────────────────────────

  group('iconRow', () {
    Future<void> pumpWithIconRow(
      WidgetTester tester, {
      required GlobalKey<AppContextMenuRegionState> key,
      required List<AppContextMenuIconAction> actions,
      List<AppContextMenuEntry> trailingEntries = const [],
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppContextMenuRegion(
              key: key,
              menuBuilder: (_, _) => [
                AppContextMenuEntry.iconRow(actions),
                const AppContextMenuEntry.divider(),
                ...trailingEntries,
              ],
              child: const SizedBox(
                width: 200,
                height: 200,
                child: ColoredBox(color: Colors.amber),
              ),
            ),
          ),
        ),
      );
      await key.currentState!.openMenuAt(const Offset(100, 100));
      await tester.pumpAndSettle();
    }

    testWidgets('כל האייקונים מרונדרים בראש התפריט', (tester) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      await pumpWithIconRow(
        tester,
        key: key,
        actions: const [
          AppContextMenuIconAction(
            label: 'חיפוש',
            tooltip: 'חיפוש בכל המאגר',
            icon: FluentIcons.library_24_regular,
          ),
          AppContextMenuIconAction(
            label: 'העתקה',
            tooltip: 'העתק',
            icon: FluentIcons.copy_24_regular,
          ),
          AppContextMenuIconAction(
            label: 'הערה',
            tooltip: 'הוסף הערה אישית',
            icon: FluentIcons.note_add_24_regular,
          ),
        ],
        trailingEntries: [AppContextMenuEntry(label: 'פריט', onTap: () {})],
      );

      expect(find.byIcon(FluentIcons.library_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.copy_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.note_add_24_regular), findsOneWidget);
      expect(
        find.text('פריט'),
        findsOneWidget,
        reason: 'הרשימה הרגילה נשארת מתחת לשורת האייקונים',
      );
    });

    test('AppContextMenuEntry.iconRow דורש לפחות פעולה אחת', () {
      expect(
        () => AppContextMenuEntry.iconRow(const []),
        throwsAssertionError,
        reason: 'שורת אייקונים ריקה חסרת משמעות — assert חוסם אותה',
      );
    });

    testWidgets('שורת אייקונים עם פעולה אחת מרונדרת ונלחצת', (tester) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      var tapped = false;
      await pumpWithIconRow(
        tester,
        key: key,
        actions: [
          AppContextMenuIconAction(
            label: 'יחיד',
            icon: FluentIcons.copy_24_regular,
            onTap: () => tapped = true,
          ),
        ],
        trailingEntries: [AppContextMenuEntry(label: 'פריט', onTap: () {})],
      );

      expect(find.byIcon(FluentIcons.copy_24_regular), findsOneWidget);
      await tester.tap(find.byIcon(FluentIcons.copy_24_regular));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
      expect(
        find.text('פריט'),
        findsNothing,
        reason: 'התפריט נסגר אחרי לחיצה על האייקון היחיד',
      );
    });

    testWidgets('לחיצה על אייקון מפעילה רק את ה-onTap שלו עצמו', (
      tester,
    ) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      final tapped = <String>[];
      await pumpWithIconRow(
        tester,
        key: key,
        actions: [
          AppContextMenuIconAction(
            label: 'א',
            icon: FluentIcons.library_24_regular,
            onTap: () => tapped.add('a'),
          ),
          AppContextMenuIconAction(
            label: 'ב',
            icon: FluentIcons.copy_24_regular,
            onTap: () => tapped.add('b'),
          ),
          AppContextMenuIconAction(
            label: 'ג',
            icon: FluentIcons.note_add_24_regular,
            onTap: () => tapped.add('c'),
          ),
        ],
      );

      await tester.tap(find.byIcon(FluentIcons.copy_24_regular));
      await tester.pumpAndSettle();

      expect(tapped, ['b'], reason: 'רק ה-onTap של האייקון האמצעי שנלחץ הופעל');
    });

    testWidgets('בשורה מעורבת — אייקון מושבת אינו סוגר/מפעיל, מאופשר כן', (
      tester,
    ) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      var enabledTapped = false;
      var disabledTapped = false;
      await pumpWithIconRow(
        tester,
        key: key,
        actions: [
          AppContextMenuIconAction(
            label: 'מאופשר',
            icon: FluentIcons.copy_24_regular,
            onTap: () => enabledTapped = true,
          ),
          AppContextMenuIconAction(
            label: 'מושבת',
            icon: FluentIcons.library_24_regular,
            enabled: false,
            onTap: () => disabledTapped = true,
          ),
        ],
        trailingEntries: [AppContextMenuEntry(label: 'פריט', onTap: () {})],
      );

      await tester.tap(find.byIcon(FluentIcons.library_24_regular));
      await tester.pumpAndSettle();
      expect(disabledTapped, isFalse);
      expect(
        find.text('פריט'),
        findsOneWidget,
        reason: 'לחיצה על אייקון מושבת אינה סוגרת את התפריט',
      );

      await tester.tap(find.byIcon(FluentIcons.copy_24_regular));
      await tester.pumpAndSettle();
      expect(enabledTapped, isTrue);
    });

    testWidgets('label ארוך נחתך ואינו גורם ל-overflow', (tester) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      await pumpWithIconRow(
        tester,
        key: key,
        actions: const [
          AppContextMenuIconAction(
            label: 'כיתוב ארוך מאוד שלא נכנס לכפתור צר',
            icon: FluentIcons.library_24_regular,
          ),
          AppContextMenuIconAction(
            label: 'עוד כיתוב ארוך במיוחד לבדיקה',
            icon: FluentIcons.copy_24_regular,
          ),
          AppContextMenuIconAction(
            label: 'כיתוב שלישי ארוך מאוד מאוד',
            icon: FluentIcons.note_add_24_regular,
          ),
        ],
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'maxWidth חותך label ארוך במקום לגרום ל-RenderFlex overflow',
      );
      expect(find.byIcon(FluentIcons.copy_24_regular), findsOneWidget);
    });

    testWidgets('label מוצג ככיתוב מתחת לאייקון, נפרד מה-tooltip', (
      tester,
    ) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      await pumpWithIconRow(
        tester,
        key: key,
        actions: const [
          AppContextMenuIconAction(
            label: 'חיפוש',
            tooltip: 'חיפוש בכל המאגר',
            icon: FluentIcons.library_24_regular,
          ),
        ],
      );

      expect(
        find.text('חיפוש'),
        findsOneWidget,
        reason: 'label הקצר מוצג ככיתוב מתחת לאייקון',
      );
      expect(
        find.text('חיפוש בכל המאגר'),
        findsNothing,
        reason: 'ה-tooltip המלא אינו מוצג ככיתוב (מופיע רק בריחוף)',
      );
    });

    testWidgets('בהיעדר label, ה-tooltip משמש ככיתוב', (tester) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      await pumpWithIconRow(
        tester,
        key: key,
        actions: const [
          AppContextMenuIconAction(
            tooltip: 'העתק',
            icon: FluentIcons.copy_24_regular,
          ),
        ],
      );

      expect(
        find.text('העתק'),
        findsOneWidget,
        reason: 'בהיעדר label, ה-tooltip מוצג ככיתוב',
      );
    });

    testWidgets('Tooltip נוצר רק לפעולה עם tooltip מוגדר', (tester) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      await pumpWithIconRow(
        tester,
        key: key,
        actions: const [
          AppContextMenuIconAction(
            label: 'הערה',
            icon: FluentIcons.note_add_24_regular,
          ),
          AppContextMenuIconAction(
            label: 'חיפוש',
            tooltip: 'חיפוש בכל הספרים',
            icon: FluentIcons.library_24_regular,
          ),
        ],
      );

      expect(
        find.byType(Tooltip),
        findsOneWidget,
        reason: 'רק לאייקון עם tooltip מוגדר נוצר Tooltip; להערה אין',
      );
    });

    testWidgets('לחיצה על כפתור אייקון מפעילה onTap וסוגרת את התפריט', (
      tester,
    ) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      var tapped = false;
      await pumpWithIconRow(
        tester,
        key: key,
        actions: [
          AppContextMenuIconAction(
            tooltip: 'העתק',
            icon: FluentIcons.copy_24_regular,
            onTap: () => tapped = true,
          ),
        ],
        trailingEntries: [AppContextMenuEntry(label: 'פריט', onTap: () {})],
      );

      await tester.tap(find.byIcon(FluentIcons.copy_24_regular));
      await tester.pumpAndSettle();

      expect(
        tapped,
        isTrue,
        reason: 'לחיצה על כפתור האייקון חייבת להפעיל את ה-onTap שלו',
      );
      expect(
        find.text('פריט'),
        findsNothing,
        reason: 'התפריט חייב להיסגר אחרי לחיצה על כפתור בשורת האייקונים',
      );
    });

    testWidgets('כפתור אייקון מושבת (enabled:false) אינו מפעיל onTap', (
      tester,
    ) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      var tapped = false;
      await pumpWithIconRow(
        tester,
        key: key,
        actions: [
          AppContextMenuIconAction(
            tooltip: 'חיפוש בכל המאגר',
            icon: FluentIcons.library_24_regular,
            enabled: false,
            onTap: () => tapped = true,
          ),
        ],
      );

      await tester.tap(find.byIcon(FluentIcons.library_24_regular));
      await tester.pumpAndSettle();

      expect(
        tapped,
        isFalse,
        reason: 'פעולת אייקון מושבתת לא צריכה להגיב ללחיצה',
      );
    });

    Future<void> pumpFullScreenIconRow(
      WidgetTester tester, {
      required GlobalKey<AppContextMenuRegionState> key,
      required Offset openAt,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppContextMenuRegion(
              key: key,
              menuBuilder: (_, _) => [
                AppContextMenuEntry.iconRow(const [
                  AppContextMenuIconAction(
                    tooltip: 'העתק',
                    icon: FluentIcons.copy_24_regular,
                  ),
                ]),
                const AppContextMenuEntry.divider(),
                AppContextMenuEntry(label: 'פריט', onTap: () {}),
              ],
              child: const SizedBox.expand(
                child: ColoredBox(color: Colors.amber),
              ),
            ),
          ),
        ),
      );
      await key.currentState!.openMenuAt(openAt);
      await tester.pumpAndSettle();
    }

    testWidgets('בפתיחה כלפי מעלה שורת האייקונים עוברת לתחתית (צמודה לעכבר)', (
      tester,
    ) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      // פתיחה סמוך לתחתית (ברירת מחדל 800x600) — אין מקום מתחת, נפתח כלפי מעלה
      await pumpFullScreenIconRow(
        tester,
        key: key,
        openAt: const Offset(100, 590),
      );

      final iconDy = tester
          .getCenter(find.byIcon(FluentIcons.copy_24_regular))
          .dy;
      final itemDy = tester.getCenter(find.text('פריט')).dy;
      expect(
        iconDy,
        greaterThan(itemDy),
        reason: 'בפתיחה כלפי מעלה שורת האייקונים צריכה להיות מתחת לרשימה',
      );
    });

    testWidgets('בפתיחה כלפי מטה שורת האייקונים נשארת בראש', (tester) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      await pumpFullScreenIconRow(
        tester,
        key: key,
        openAt: const Offset(100, 10),
      );

      final iconDy = tester
          .getCenter(find.byIcon(FluentIcons.copy_24_regular))
          .dy;
      final itemDy = tester.getCenter(find.text('פריט')).dy;
      expect(
        iconDy,
        lessThan(itemDy),
        reason: 'בפתיחה כלפי מטה שורת האייקונים נשארת בראש התפריט',
      );
    });

    testWidgets('פעולת אייקון עם submenuBuilder מציגה חץ ופותחת תת-תפריט', (
      tester,
    ) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      var optionTapped = false;
      await pumpWithIconRow(
        tester,
        key: key,
        actions: [
          AppContextMenuIconAction(
            label: 'קישור ישיר',
            tooltip: 'העתק קישור ישיר',
            icon: FluentIcons.link_24_regular,
            submenuBuilder: () => [
              AppContextMenuSubAction(
                label: 'העתק קישור למקטע',
                onTap: () => optionTapped = true,
              ),
            ],
          ),
        ],
        trailingEntries: [AppContextMenuEntry(label: 'פריט', onTap: () {})],
      );

      expect(
        find.byIcon(FluentIcons.chevron_down_12_regular),
        findsOneWidget,
        reason: 'פעולה עם submenuBuilder מציגה חץ למטה',
      );

      await tester.tap(find.byIcon(FluentIcons.link_24_regular));
      await tester.pumpAndSettle();
      expect(
        find.text('העתק קישור למקטע'),
        findsOneWidget,
        reason: 'לחיצה על הכפתור פותחת את תת-התפריט',
      );

      await tester.tap(find.text('העתק קישור למקטע'));
      await tester.pumpAndSettle();
      expect(
        optionTapped,
        isTrue,
        reason: 'בחירת אפשרות מפעילה את ה-onTap שלה',
      );
      expect(
        find.text('פריט'),
        findsNothing,
        reason: 'בחירת אפשרות סוגרת את כל תפריט ההקשר',
      );
    });
  });
}
