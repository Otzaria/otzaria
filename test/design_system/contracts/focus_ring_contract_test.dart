import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

import 'contract_harness.dart';

/// טבעת פוקוס המקלדת של כפתורים (DD-07, q11 Q2 B): רק בניווט מקלדת (Tab
/// או חצים), מחוץ לכפתור ובלי לשנות את גודלו.
void main() {
  late FocusNode saveNode;

  Future<void> pumpButtons(WidgetTester tester) async {
    saveNode = FocusNode(debugLabel: 'save');
    addTearDown(saveNode.dispose);
    await pumpInApp(
      tester,
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ActionButton.recommended(
              text: 'שמור',
              onPressed: () {},
              focusNode: saveNode,
            ),
            ActionButton.warning(text: 'מחק', onPressed: () {}),
            ActionButton.ghost(text: 'סגור', onPressed: () {}),
            AppIconButton(
              icon: const Icon(OtzariaIcons.book_24_regular),
              tooltip: 'ספרייה',
              onPressed: () {},
            ),
            BarButton.icon(
              tooltip: 'חיפוש',
              icon: OtzariaIcons.search_24_regular,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  final isButton = find.byWidgetPredicate((w) => w is ButtonStyleButton);
  Finder buttonOf(String label) => find.ancestor(
    of: switch (label) {
      'ספרייה' => find.byIcon(OtzariaIcons.book_24_regular),
      'חיפוש' => find.byIcon(OtzariaIcons.search_24_regular),
      _ => find.text(label),
    },
    matching: isButton,
  );

  BorderSide sideOf(WidgetTester tester, String label) =>
      (tester
                  .widget<Material>(
                    find
                        .descendant(
                          of: buttonOf(label).first,
                          matching: find.byType(Material),
                        )
                        .first,
                  )
                  .shape!
              as OutlinedBorder)
          .side;

  BorderSide ring(WidgetTester tester) => AppFocusRing.side(
    Theme.of(tester.element(find.text('שמור'))).colorScheme,
  );

  const labels = ['שמור', 'מחק', 'סגור', 'ספרייה', 'חיפוש'];

  void useHighlight(FocusHighlightStrategy strategy) {
    final prev = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy = strategy;
    addTearDown(() => FocusManager.instance.highlightStrategy = prev);
  }

  testWidgets('Tab: טבעת על הכפתור הממוקד בלבד, בלי שינוי גודל', (
    tester,
  ) async {
    await pumpButtons(tester);
    final sizes = {for (final l in labels) l: tester.getSize(buttonOf(l))};
    for (var i = 0; i < labels.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      for (final l in labels) {
        expect(
          sideOf(tester, l),
          l == labels[i] ? ring(tester) : BorderSide.none,
          reason: 'אחרי ${i + 1} לחיצות Tab: "$l"',
        );
        expect(tester.getSize(buttonOf(l)), sizes[l], reason: l);
      }
    }
  });

  testWidgets('הטבעת מצוירת במרחק 2 מחוץ לכפתור, בעובי focusRingWidth', (
    tester,
  ) async {
    await pumpButtons(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final side = sideOf(tester, 'שמור');
    expect(side.width, AppTokens.focusRingWidth);
    expect(side.strokeInset, -AppFocusRing.gap);
    expect(side.strokeOutset, AppFocusRing.gap + AppTokens.focusRingWidth);
    expect(
      ring(tester).color,
      Theme.of(tester.element(find.text('שמור'))).colorScheme.primary,
    );
  });

  testWidgets('עכבר: פוקוס בלי הקשה (autofocus אחרי לחיצה) בלי טבעת', (
    tester,
  ) async {
    useHighlight(FocusHighlightStrategy.alwaysTraditional);
    await pumpButtons(tester);
    final mouse = await tester.startGesture(
      const Offset(5, 5),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.up();
    saveNode.requestFocus();
    await tester.pumpAndSettle();
    expect(saveNode.hasPrimaryFocus, isTrue);
    expect(sideOf(tester, 'שמור'), BorderSide.none);
  });

  testWidgets('עכבר אחרי מקלדת: הפוקוס הבא כבר בלי טבעת', (tester) async {
    useHighlight(FocusHighlightStrategy.alwaysTraditional);
    await pumpButtons(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(sideOf(tester, 'שמור'), ring(tester));

    final mouse = await tester.startGesture(
      const Offset(5, 5),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.up();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    saveNode.requestFocus();
    await tester.pumpAndSettle();
    expect(sideOf(tester, 'שמור'), BorderSide.none);
  });

  group('רק הקשה אמיתית נחשבת למקלדת (R6-7)', () {
    /// לחיצת עכבר (אין טבעת), אחריה [keys], ואז פוקוס על "שמור".
    Future<BorderSide> sideAfter(
      WidgetTester tester,
      Future<void> Function() keys,
    ) async {
      useHighlight(FocusHighlightStrategy.alwaysTraditional);
      await pumpButtons(tester);
      final mouse = await tester.startGesture(
        const Offset(5, 5),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.up();
      await keys();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      saveNode.requestFocus();
      await tester.pumpAndSettle();
      expect(saveNode.hasPrimaryFocus, isTrue);
      return sideOf(tester, 'שמור');
    }

    testWidgets('מקש שינוי לבדו (Ctrl, Alt, Shift): בלי טבעת', (tester) async {
      final side = await sideAfter(tester, () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.shiftRight);
      });
      expect(side, BorderSide.none);
    });

    testWidgets('קיצור עם Ctrl (כמו פתיחת דיאלוג בקיצור): בלי טבעת', (
      tester,
    ) async {
      final side = await sideAfter(tester, () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });
      expect(side, BorderSide.none);
    });

    testWidgets('הקשה מסונתזת (חזרה לחלון עם Alt+Tab): בלי טבעת', (
      tester,
    ) async {
      final side = await sideAfter(tester, () async {
        // מה שהמנוע שולח למקש שנלחץ בזמן שהחלון לא היה בפוקוס.
        for (final type in [ui.KeyEventType.down, ui.KeyEventType.up]) {
          tester.binding.platformDispatcher.onKeyData!(
            ui.KeyData(
              type: type,
              physical: PhysicalKeyboardKey.keyA.usbHidUsage,
              logical: LogicalKeyboardKey.keyA.keyId,
              character: null,
              timeStamp: Duration.zero,
              synthesized: true,
            ),
          );
        }
      });
      expect(side, BorderSide.none);
    });

    testWidgets('Shift+Tab נחשב למקלדת', (tester) async {
      final side = await sideAfter(tester, () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });
      expect(side, ring(tester));
    });

    testWidgets('חץ נחשב למקלדת', (tester) async {
      final side = await sideAfter(tester, () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      });
      expect(side, ring(tester));
    });
  });

  group('רק Tab וחצים מדליקים את הטבעת (סקירת 4.11)', () {
    /// לחיצת עכבר (אין טבעת), אחריה [keys], ואז פוקוס על "שמור".
    Future<BorderSide> sideAfter(
      WidgetTester tester,
      Future<void> Function() keys,
    ) async {
      useHighlight(FocusHighlightStrategy.alwaysTraditional);
      await pumpButtons(tester);
      final mouse = await tester.startGesture(
        const Offset(5, 5),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.up();
      await keys();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      saveNode.requestFocus();
      await tester.pumpAndSettle();
      expect(saveNode.hasPrimaryFocus, isTrue);
      return sideOf(tester, 'שמור');
    }

    testWidgets('Delete, ‏Enter ואות (למשל דיאלוג שנפתח במקלדת): בלי טבעת', (
      tester,
    ) async {
      final side = await sideAfter(tester, () async {
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      });
      expect(side, BorderSide.none);
    });

    testWidgets('Ctrl+Tab (החלפת כרטיסייה): בלי טבעת', (tester) async {
      final side = await sideAfter(tester, () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      });
      expect(side, BorderSide.none);
    });

    testWidgets('חץ שמאלה: טבעת', (tester) async {
      final side = await sideAfter(
        tester,
        () => tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft),
      );
      expect(side, ring(tester));
    });

    testWidgets('לחיצה במקום ריק מכבה טבעת שכבר מוצגת, והפוקוס נשאר', (
      tester,
    ) async {
      useHighlight(FocusHighlightStrategy.alwaysTraditional);
      await pumpButtons(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(sideOf(tester, 'שמור'), ring(tester));

      final mouse = await tester.startGesture(
        const Offset(5, 5),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.up();
      await tester.pumpAndSettle();
      expect(saveNode.hasPrimaryFocus, isTrue);
      expect(sideOf(tester, 'שמור'), BorderSide.none);

      // וחץ מחזיר אותה, על הכפתור שהפוקוס עבר אליו.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      final ringed = labels.where((l) => sideOf(tester, l) == ring(tester));
      expect(ringed, hasLength(1));
    });
  });

  testWidgets('מגע: בלי טבעת, גם אחרי הקשה', (tester) async {
    await pumpButtons(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    useHighlight(FocusHighlightStrategy.alwaysTouch);
    final touch = await tester.startGesture(const Offset(5, 5));
    await touch.up();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    saveNode.requestFocus();
    await tester.pumpAndSettle();
    expect(saveNode.hasPrimaryFocus, isTrue);
    expect(sideOf(tester, 'שמור'), BorderSide.none);
  });

  testWidgets('כפתור מושבת לא מקבל טבעת', (tester) async {
    await pumpInApp(
      tester,
      const Center(
        child: ActionButton.recommended(text: 'שמור', onPressed: null),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(sideOf(tester, 'שמור'), BorderSide.none);
  });
}
