import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';

/// בודק את [RtlSelectionShortcuts]: Shift+חץ פועל תמיד על קצה ה-focus (לעולם
/// לא משחית את ה-anchor/תחילת המחרוזת), ובכיוון הנכון — בשורה אחת (דרך
/// priming) וברב-שורתי (דרך היפוך). שקוף ב-LTR.
void main() {
  late GlobalKey<SelectableRegionState> regionKey;
  late String? sel;

  // איפוס המצב הגלובלי בין בדיקות (באפליקציה הוא מתאפס כשעוברים אזור בחירה).
  setUp(() {
    rtlSelectionPriming = false;
    trackRtlSelection('');
  });

  Future<void> pumpRegion(
    WidgetTester tester, {
    required String text,
    required double width,
  }) async {
    regionKey = GlobalKey<SelectableRegionState>();
    sel = null;
    final focusNode = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: SizedBox(
                width: width,
                child: RtlSelectionShortcuts(
                  child: SelectableRegion(
                    key: regionKey,
                    focusNode: focusNode,
                    selectionControls: emptyTextSelectionControls,
                    // מתעלמים משינויי priming זמניים — מתעדים רק בחירה אמיתית.
                    onSelectionChanged: (v) {
                      if (!rtlSelectionPriming) sel = v?.plainText;
                    },
                    child: Text(
                      text,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focusNode.requestFocus();
    await tester.pump();
    regionKey.currentState!.selectAll();
    await tester.pump();
  }

  Future<void> shiftPress(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(k);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'שורה אחת: Shift+ימין מקצר מה-focus, Shift+שמאל מאריך (priming)',
    (tester) async {
      await pumpRegion(tester, text: 'אבגדהוז', width: 600);
      expect(sel, equals('אבגדהוז'));

      // Shift+ימין → מקצר מהקצה השמאלי (focus); ההתחלה (anchor) נשמרת.
      await shiftPress(tester, LogicalKeyboardKey.arrowRight);
      expect(
        sel,
        equals('אבגדהו'),
        reason: 'מקצר מה-focus, לא משחית מההתחלה — לא "$sel"',
      );

      // Shift+שמאל → מאריך בחזרה בקצה השמאלי (focus).
      await shiftPress(tester, LogicalKeyboardKey.arrowLeft);
      expect(sel, equals('אבגדהוז'), reason: 'Shift+שמאל מאריך ב-focus');
    },
  );

  testWidgets('שורה אחת מתעלמת מ-tracker גלובלי תקוע (אנטי-זיהום בין-אזורי)', (
    tester,
  ) async {
    // מדמים מצב גלובלי "תקוע" מאזור אחר: reversed=false.
    rtlSelectionPriming = false;
    trackRtlSelection('');
    trackRtlSelection('בג');
    trackRtlSelection('אבג'); // גדילה בהתחלה → reversed=false
    expect(rtlInferredReversed, isFalse);

    await pumpRegion(tester, text: 'אבגדה', width: 600);
    // לפי הגאומטריה המקומית (focus בצד שמאל), Shift+ימין מקצר מהסוף → "אבגד".
    // אילו היה משתמש ב-tracker הגלובלי התקוע, היה נועל את ה-anchor והתוצאה
    // הייתה שונה.
    await shiftPress(tester, LogicalKeyboardKey.arrowRight);
    expect(
      sel,
      equals('אבגד'),
      reason: 'שורה-אחת חייבת להשתמש בגאומטריה מקומית, לא ב-tracker הגלובלי',
    );
  });

  testWidgets('רב-שורתי: Shift+חץ אינו משחית את ההתחלה (anchor)', (
    tester,
  ) async {
    const text = 'אבגדה והוזח טיכלמ נסעפצ קרשת אבגדה והוזח טיכלמ נסעפצ קרשת';
    await pumpRegion(tester, text: text, width: 120);
    // ברב-שורתי ההיפוך פועל על ה-focus; הדרישה הקריטית: תחילת המחרוזת
    // (anchor) לעולם לא נחתכת (selectAll ממצה את שני הקצוות, ולכן בודקים רק
    // שאין השחתה מההתחלה).
    await shiftPress(tester, LogicalKeyboardKey.arrowLeft);
    expect(sel, isNotNull);
    expect(
      text.startsWith(sel!),
      isTrue,
      reason: 'תחילת הבחירה (anchor) חייבת להישמר — לא "$sel"',
    );
  });

  testWidgets('רב-שורתי מאפס כיוון גרירה מאזור קודם (אנטי-זיהום בין-אזורי)', (
    tester,
  ) async {
    // מצב גלובלי "תקוע" מאזור אחר: reversed=false.
    trackRtlSelection('');
    trackRtlSelection('בג');
    trackRtlSelection('אבג'); // גדל בהתחלה → reversed=false
    expect(rtlInferredReversed, isFalse);

    // אזור בחירה חדש (SelectableRegionState אחר). הבחירה הרב-שורתית הראשונה
    // בו אסור שתשתמש ב-reversed=false שנשאר מהאזור הקודם.
    const text = 'אבגדה והוזח טיכלמ נסעפצ קרשת אבגדה והוזח טיכלמ נסעפצ';
    await pumpRegion(tester, text: text, width: 120);
    await shiftPress(tester, LogicalKeyboardKey.arrowLeft);

    // ה-Action זיהה אזור חדש ואיפס את ה-tracker (ה-onSelectionChanged של
    // ה-harness אינו קורא ל-trackRtlSelection, ולכן הערך נשאר מאופס).
    expect(
      rtlInferredReversed,
      isNull,
      reason: 'מעבר אזור חייב לאפס כיוון גרירה ישן, לא לזהם בחירה רב-שורתית',
    );
  });

  testWidgets('אין יעד בחירה → לא בולע את המקש (משוחרר במעלה העץ)', (
    tester,
  ) async {
    var outerFired = false;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.arrowLeft,
                  shift: true,
                ): () =>
                    outerFired = true,
              },
              child: RtlSelectionShortcuts(
                child: Focus(
                  focusNode: focusNode,
                  autofocus: true,
                  child: const SizedBox(width: 50, height: 50),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    focusNode.requestFocus();
    await tester.pump();

    await shiftPress(tester, LogicalKeyboardKey.arrowLeft);
    expect(
      outerFired,
      isTrue,
      reason: 'בלי EditableText/SelectableRegion אסור לבלוע את Shift+חץ',
    );
  });

  testWidgets('יעד LTR מקונן ב-wrapper RTL → לא מוחל היפוך RTL', (
    tester,
  ) async {
    var outerFired = false;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.arrowLeft,
                  shift: true,
                ): () =>
                    outerFired = true,
              },
              child: RtlSelectionShortcuts(
                // אזור LTR מקונן בתוך wrapper RTL.
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableRegion(
                    focusNode: focusNode,
                    selectionControls: emptyTextSelectionControls,
                    child: const Text(
                      'hello world',
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focusNode.requestFocus();
    await tester.pump();

    await shiftPress(tester, LogicalKeyboardKey.arrowLeft);
    // ההכרעה לפי כיווניות היעד (LTR) → לא מוחלת לוגיקת RTL, והמקש משוחרר.
    expect(outerFired, isTrue, reason: 'יעד LTR אינו אמור לקבל לוגיקת RTL');
  });

  group('Ctrl+חץ בלי Shift — הזזת סמן מילה', () {
    Future<TextEditingController> pumpField(
      WidgetTester tester, {
      required String text,
      required int cursorAt,
    }) async {
      final controller = TextEditingController(text: text);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              // TextField גולמי בכוונה: RtlTextField בולע Ctrl+חץ בעצמו,
              // וכאן נבדק מסלול ה-fallback של RtlSelectionShortcuts ליעד קלט.
              child: RtlSelectionShortcuts(
                child: TextField(controller: controller, autofocus: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.selection = TextSelection.collapsed(offset: cursorAt);
      await tester.pump();
      return controller;
    }

    Future<void> ctrlPress(WidgetTester tester, LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+שמאל מזיז את הסמן קדימה (ויזואלית שמאלה) ב-RTL', (
      tester,
    ) async {
      final controller = await pumpField(
        tester,
        text: 'אבג דהו זחט',
        cursorAt: 0,
      );
      await ctrlPress(tester, LogicalKeyboardKey.arrowLeft);
      expect(controller.selection.isCollapsed, isTrue);
      expect(
        controller.selection.baseOffset,
        greaterThan(0),
        reason: 'Ctrl+שמאל ב-RTL חייב להתקדם במחרוזת, לא להישאר בהתחלה',
      );
    });

    testWidgets('Ctrl+ימין מזיז את הסמן אחורה (ויזואלית ימינה) ב-RTL', (
      tester,
    ) async {
      const text = 'אבג דהו זחט';
      final controller = await pumpField(
        tester,
        text: text,
        cursorAt: text.length,
      );
      await ctrlPress(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.selection.isCollapsed, isTrue);
      expect(
        controller.selection.baseOffset,
        lessThan(text.length),
        reason: 'Ctrl+ימין ב-RTL חייב לחזור אחורה במחרוזת, לא להישאר בסוף',
      );
    });

    testWidgets('SelectableRegion: Ctrl+ימין מקצר מילה מה-focus, שומר anchor', (
      tester,
    ) async {
      const text = 'אבג דהו זחט';
      await pumpRegion(tester, text: text, width: 600);
      await ctrlPress(tester, LogicalKeyboardKey.arrowRight);
      expect(sel, isNotNull);
      expect(
        sel,
        isNot(equals(text)),
        reason: 'Ctrl+ימין אמור לקצר את הבחירה ברמת מילה',
      );
      expect(
        text.startsWith(sel!),
        isTrue,
        reason: 'הקיצור חייב להיות מקצה ה-focus (הסוף), לא מה-anchor',
      );
    });
  });

  group('trackRtlSelection — הסקת כיוון הגרירה', () {
    setUp(() {
      // איפוס המצב הגלובלי בין בדיקות.
      rtlSelectionPriming = false;
      trackRtlSelection('');
    });

    test('גדילה בסוף המחרוזת → reversed=true (focus בסוף)', () {
      trackRtlSelection('אב');
      trackRtlSelection('אבג');
      trackRtlSelection('אבגד');
      expect(rtlInferredReversed, isTrue);
    });

    test('גדילה בתחילת המחרוזת → reversed=false (focus בהתחלה)', () {
      trackRtlSelection('גד');
      trackRtlSelection('בגד');
      trackRtlSelection('אבגד');
      expect(rtlInferredReversed, isFalse);
    });

    test('התכווצות מהסוף → reversed=true', () {
      trackRtlSelection('אבגד');
      trackRtlSelection('אבג');
      expect(rtlInferredReversed, isTrue);
    });

    test('התכווצות מההתחלה → reversed=false', () {
      trackRtlSelection('אבגד');
      trackRtlSelection('בגד');
      expect(rtlInferredReversed, isFalse);
    });

    test('בזמן priming המעקב מתעלם (שינוי זמני)', () {
      trackRtlSelection('אבג'); // last="אבג"
      trackRtlSelection('אבגד'); // reversed=true
      rtlSelectionPriming = true;
      trackRtlSelection('בגד'); // אמור להתעלם
      rtlSelectionPriming = false;
      expect(rtlInferredReversed, isTrue, reason: 'priming לא משנה את ההסקה');
    });
  });

  testWidgets('LTR: ה-widget שקוף ואינו מוסיף Shortcuts', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RtlSelectionShortcuts(child: SizedBox(width: 10, height: 10)),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(RtlSelectionShortcuts),
        matching: find.byType(Shortcuts),
      ),
      findsNothing,
    );
  });
}
