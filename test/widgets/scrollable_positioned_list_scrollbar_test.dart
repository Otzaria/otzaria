import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class _RecordingItemScrollController extends ItemScrollController {
  final List<int> jumps = <int>[];

  @override
  void jumpTo({required int index, double alignment = 0}) {
    jumps.add(index);
  }
}

void main() {
  testWidgets('פס הגלילה שומר רצועה נפרדת מהתוכן כשצריך לגלול', (tester) async {
    final listener = ItemPositionsListener.create();
    final controller = ItemScrollController();
    const contentKey = Key('scroll-content');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 10,
            child: Container(key: contentKey),
          ),
        ),
      ),
    );

    // מדמה תוכן שדורש גלילה — רק 2 פריטים מתוך 10 גלויים.
    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
          ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
        ];
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(contentKey)).dx, 12.0);
  });

  testWidgets('פס הגלילה מוסתר כשכל התוכן נראה במסך', (tester) async {
    final listener = ItemPositionsListener.create();
    final controller = ItemScrollController();
    const contentKey = Key('scroll-content');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 2,
            child: Container(key: contentKey),
          ),
        ),
      ),
    );

    // כל הפריטים גלויים בתוך המסך — אין מה לגלול, ולכן ה-12px צריכים להיעלם.
    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.4),
          ItemPosition(index: 1, itemLeadingEdge: 0.4, itemTrailingEdge: 0.8),
        ];
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(contentKey)).dx, 0.0);
  });

  testWidgets('הקלקה על תחתית המסילה מגיעה לסוף הספר גם כשמעט פריטים גלויים '
      '(מפרש פתוח מתחת)', (tester) async {
    // רגרסיה: כשמפרש פתוח מתחת ושני סגמנטים גלויים מתוך 100, חישוב היעד
    // מבוסס על thumb-height שמוקצב מינימום 0.05. לפני התיקון, גרירה לתחתית
    // עצרה ב-targetIndex = 95 (0.95 * 100) במקום maxScrollableIndex = 98,
    // ולכן הסגמנטים האחרונים היו בלתי-נגישים דרך הסקרולבר.
    final listener = ItemPositionsListener.create();
    final controller = _RecordingItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
          ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
        ];
    await tester.pump();

    final track = find.byType(GestureDetector);
    final trackBottomRight = tester.getBottomRight(track);
    final trackTopLeft = tester.getTopLeft(track);
    final tapPosition = Offset(
      (trackTopLeft.dx + trackBottomRight.dx) / 2,
      trackBottomRight.dy - 1,
    );

    await tester.tapAt(tapPosition);
    await tester.pump();

    expect(controller.jumps, isNotEmpty);
    // maxScrollableIndex = 100 - 2 = 98. שולחים tolerance של פריט אחד
    // למקרה של עיגול בגלל ש-thumb-height clamped (0.05 * 100 = 5 לעומת 2
    // הפריטים שבאמת גלויים).
    expect(controller.jumps.last, inInclusiveRange(97, 99));
  });

  testWidgets('עדכון maxScrollableIndex אחרי שינוי positions: '
      'הקלקה שנייה על אותו מיקום מגיעה ליעד מעודכן', (tester) async {
    // רגרסיה לחלק השני של התיקון: כשהמשתמש מתחיל גרירה כשיש 10 פריטים
    // גלויים (maxScrollableIndex=90) וקופץ לאזור עם רק 2 גלויים
    // (maxScrollableIndex=98), _maxScrollableIndex חייב להתעדכן כדי
    // שגרירה לתחתית באמת תגיע לסוף. הטסט בודק את אותו עיקרון דרך
    // שתי הקלקות עוקבות עם positions שונות בין הקלקה להקלקה.
    final listener = ItemPositionsListener.create();
    final positions =
        listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>;
    final controller = _RecordingItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    positions.value = List.generate(
      10,
      (i) => ItemPosition(
        index: i,
        itemLeadingEdge: i * 0.1,
        itemTrailingEdge: (i + 1) * 0.1,
      ),
    );
    await tester.pump();

    final track = find.byType(GestureDetector);
    final trackBottomRight = tester.getBottomRight(track);
    final trackTopLeft = tester.getTopLeft(track);
    final tapBottom = Offset(
      (trackTopLeft.dx + trackBottomRight.dx) / 2,
      trackBottomRight.dy - 1,
    );

    // הקלקה ראשונה — עם 10 פריטים גלויים, maxScrollableIndex=90.
    await tester.tapAt(tapBottom);
    await tester.pump();
    final firstJump = controller.jumps.last;
    expect(firstJump, lessThanOrEqualTo(91));

    // שינוי positions לאזור עם 2 גלויים בלבד (כמו אזור עם מפרש פתוח).
    positions.value = const [
      ItemPosition(index: 50, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
      ItemPosition(index: 51, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
    ];
    await tester.pump();

    // הקלקה שנייה על אותו מיקום — maxScrollableIndex חייב להיות מעודכן
    // ל-98, ולכן היעד צריך להיות גבוה משמעותית מ-90.
    await tester.tapAt(tapBottom);
    await tester.pump();

    expect(controller.jumps.last, greaterThanOrEqualTo(97));
  });

  testWidgets('גרירה שמתחילה על המסילה מחוץ לאגודל קופצת ליעד הנלחץ '
      '(לחיצה שזוהתה כגרירה)', (tester) async {
    // רגרסיה: כל מיקרו-תזוזה הופכת tap ל-drag, ואז onTapDown אינו נקרא.
    // לפני התיקון גרירה כזו רק הזיזה את האגודל ביחס למקומו הנוכחי במקום
    // לקפוץ ליעד שנבחר, ולכן "הטקסט לא נגלל לשם אלא נשאר באותו מקום".
    final listener = ItemPositionsListener.create();
    final controller = _RecordingItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    // האגודל קטן ונמצא בראש (פריטים 0-1 גלויים מתוך 100).
    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
          ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
        ];
    await tester.pump();

    final track = find.byType(GestureDetector);
    final trackTopLeft = tester.getTopLeft(track);
    final trackBottomRight = tester.getBottomRight(track);
    // מתחילים גרירה סמוך לתחתית המסילה — הרחק מהאגודל שבראש.
    final startNearBottom = Offset(
      (trackTopLeft.dx + trackBottomRight.dx) / 2,
      trackBottomRight.dy - 5,
    );

    final gesture = await tester.startGesture(startNearBottom);
    await tester.pump();
    // תזוזה מעבר ל-touch-slop כדי שתזוהה כגרירה ולא כ-tap.
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.jumps, isNotEmpty);
    // הקפיצה הראשונה (בתחילת הגרירה) חייבת להגיע לאזור התחתון של הספר,
    // ולא להישאר בראש (היכן שהאגודל היה).
    expect(controller.jumps.first, greaterThan(80));
  });

  testWidgets('לחיצה שמתחילה על האגודל עצמו אינה ממקמת אותו מחדש ומקפיצה', (
    tester,
  ) async {
    // רגרסיה: onTapDown נורה גם כשהמחווה הופכת מיד לגרירת האגודל. אם הוא
    // קופץ ללא תנאי, תפיסת האגודל ממרכזת אותו סביב הסמן ומקפיצה את הרשימה
    // עוד לפני שהגרירה היחסית מתחילה.
    final listener = ItemPositionsListener.create();
    final controller = _RecordingItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 10,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    // 2 מתוך 10 גלויים בראש → אגודל גדול (~20%) בראש המסילה.
    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
          ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
        ];
    await tester.pump();

    final track = find.byType(GestureDetector);
    final trackTopLeft = tester.getTopLeft(track);
    final trackBottomRight = tester.getBottomRight(track);
    final trackHeight = trackBottomRight.dy - trackTopLeft.dy;
    // נקודה בתוך האגודל (בראש, ~10% מגובה המסילה).
    final onThumb = Offset(
      (trackTopLeft.dx + trackBottomRight.dx) / 2,
      trackTopLeft.dy + trackHeight * 0.1,
    );

    await tester.tapAt(onThumb);
    await tester.pump();

    expect(controller.jumps, isEmpty);
  });

  testWidgets(
    'אחרי לחיצה וקפיצה ליעד, האגודל אינו "יורד" כשהפוזיציות מתעדכנות',
    (tester) async {
      // רגרסיה: המיפוי הקדים (מיקום→אינדקס) חילק ב-(1-thumbHeight) אך המיפוי
      // ההפוך (אינדקס→מיקום) לא הכפיל חזרה. לכן אחרי לחיצה שקפצה ליעד,
      // _updateScrollPosition דרס את מיקום האגודל לערך גבוה יותר, והאגודל
      // "ירד" ביחס למקום שנלחץ — בעוצמה שגדלה ככל שמתקדמים בספר.
      final listener = ItemPositionsListener.create();
      final positions =
          listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>;
      final controller = _RecordingItemScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollablePositionedListScrollbar(
              scrollController: controller,
              itemPositionsListener: listener,
              itemCount: 100,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // מצב התחלתי: ראש הספר (2 מתוך 100 גלויים) → אגודל בראש המסילה.
      positions.value = const [
        ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
        ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
      ];
      await tester.pump();

      final track = find.byType(GestureDetector);
      final trackTopLeft = tester.getTopLeft(track);
      final trackBottomRight = tester.getBottomRight(track);
      // לחיצה במרכז המסילה.
      final tapCenter = Offset(
        (trackTopLeft.dx + trackBottomRight.dx) / 2,
        (trackTopLeft.dy + trackBottomRight.dy) / 2,
      );

      await tester.tapAt(tapCenter);
      await tester.pump();

      // מיקום האגודל מיד אחרי הלחיצה (לפני שהפוזיציות מתעדכנות).
      final thumbTopAfterTap = tester
          .widget<Positioned>(find.byType(Positioned))
          .top!;
      final targetIndex = controller.jumps.last;

      // מדמים שהרשימה אכן קפצה ליעד: היעד נעשה הפריט הראשון הגלוי.
      positions.value = [
        ItemPosition(
          index: targetIndex,
          itemLeadingEdge: 0,
          itemTrailingEdge: 0.5,
        ),
        ItemPosition(
          index: targetIndex + 1,
          itemLeadingEdge: 0.5,
          itemTrailingEdge: 1.0,
        ),
      ];
      await tester.pump();

      final thumbTopAfterSettle = tester
          .widget<Positioned>(find.byType(Positioned))
          .top!;

      // האגודל חייב להישאר במקום שנלחץ — בלי "ירידה".
      expect(thumbTopAfterSettle, closeTo(thumbTopAfterTap, 2.0));
    },
  );

  testWidgets(
    'גובה האגודל יציב בין מצבי גלילה עם פריטים חלקיים, והמיקום מחליק',
    (tester) async {
      // ספירת פריטים שלמה מתחלפת 4↔5 כשפריט חלקי נכנס/יוצא ומקפיצה את הגובה;
      // הקצוות הרציפים מייצבים אותו, והמיקום משלב את החלק שנגלל מהפריט העליון.
      final listener = ItemPositionsListener.create();
      final positions =
          listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>;
      final controller = ItemScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollablePositionedListScrollbar(
              scrollController: controller,
              itemPositionsListener: listener,
              itemCount: 40,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // מצב A: 4 פריטים בגובה אחיד 0.25 שמרצפים את המסך בדיוק.
      positions.value = const [
        ItemPosition(index: 0, itemLeadingEdge: 0.0, itemTrailingEdge: 0.25),
        ItemPosition(index: 1, itemLeadingEdge: 0.25, itemTrailingEdge: 0.5),
        ItemPosition(index: 2, itemLeadingEdge: 0.5, itemTrailingEdge: 0.75),
        ItemPosition(index: 3, itemLeadingEdge: 0.75, itemTrailingEdge: 1.0),
      ];
      await tester.pump();
      final thumbA = tester.widget<Positioned>(find.byType(Positioned));
      final heightA = thumbA.height!;
      final topA = thumbA.top!;

      // מצב B: אותם פריטים נגללו ב-0.1 — כעת 5 פריטים חלקיים גלויים. ב-
      // visibleItems השלם זו קפיצה מ-4 ל-5 (גובה +25%); ברציף הגובה זהה.
      positions.value = const [
        ItemPosition(index: 0, itemLeadingEdge: -0.1, itemTrailingEdge: 0.15),
        ItemPosition(index: 1, itemLeadingEdge: 0.15, itemTrailingEdge: 0.4),
        ItemPosition(index: 2, itemLeadingEdge: 0.4, itemTrailingEdge: 0.65),
        ItemPosition(index: 3, itemLeadingEdge: 0.65, itemTrailingEdge: 0.9),
        ItemPosition(index: 4, itemLeadingEdge: 0.9, itemTrailingEdge: 1.15),
      ];
      await tester.pump();
      final thumbB = tester.widget<Positioned>(find.byType(Positioned));
      final heightB = thumbB.height!;
      final topB = thumbB.top!;

      // גובה יציב: ההפרש זניח (לפני התיקון היה ~25%).
      expect(heightB, closeTo(heightA, 1.0));
      // המיקום התקדם מעט כלפי מטה — מחליק, לא נשאר במקום.
      expect(topB, greaterThan(topA));
    },
  );

  testWidgets('גובה האגודל נשאר יציב כשגוללים לאזור עם סגמנטים בגובה שונה', (
    tester,
  ) async {
    // בקריאה רציפה הסגמנטים בגבהים שונים; ממוצע מקומי מתנודד בין אזורים.
    // הממוצע הגלובלי (על כל מה שנמדד) מחזיק את גובה האגודל יציב.
    final listener = ItemPositionsListener.create();
    final positions =
        listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>;
    final controller = ItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    // אזור גדול של סגמנטים קצרים (גובה 0.1) — נמדדים ומבססים את האומדן.
    positions.value = List.generate(
      90,
      (i) => ItemPosition(
        index: i,
        itemLeadingEdge: i * 0.1,
        itemTrailingEdge: (i + 1) * 0.1,
      ),
    );
    await tester.pump();
    final heightShort = tester
        .widget<Positioned>(find.byType(Positioned))
        .height!;

    // גלילה לאזור עם סגמנטים ארוכים פי 5 (גובה 0.5). הממוצע המקומי לבדו היה
    // מכווץ את האגודל פי ~5; הגלובלי מחזיק אותו כמעט קבוע.
    positions.value = const [
      ItemPosition(index: 90, itemLeadingEdge: 0.0, itemTrailingEdge: 0.5),
      ItemPosition(index: 91, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
    ];
    await tester.pump();
    final heightTall = tester
        .widget<Positioned>(find.byType(Positioned))
        .height!;

    // יציב: נשאר בטווח 30% מהגובה המקורי (לפני התיקון היה מתכווץ לחמישית).
    expect(heightTall, closeTo(heightShort, heightShort * 0.3));
  });

  testWidgets('שינוי layout (גובה פריט שנמדד) מאפס את מאגר הגבהים', (
    tester,
  ) async {
    // גובה פריט קבוע תחת גלילה; אם פריט שנמדד חוזר בגובה אחר — ה-layout השתנה
    // (גופן/viewport/מפרשים) והיחסים הישנים אינם תקפים, ולכן המאגר מתאפס.
    final listener = ItemPositionsListener.create();
    final positions =
        listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>;
    final controller = ItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    // צובר 50 פריטים בגובה 0.1.
    positions.value = List.generate(
      50,
      (i) => ItemPosition(
        index: i,
        itemLeadingEdge: i * 0.1,
        itemTrailingEdge: (i + 1) * 0.1,
      ),
    );
    await tester.pump();

    // אותם אינדקסים חוזרים בגובה 0.5 (שינוי layout) → איפוס, ממוצע לפי 0.5 בלבד.
    positions.value = const [
      ItemPosition(index: 0, itemLeadingEdge: 0.0, itemTrailingEdge: 0.5),
      ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
    ];
    await tester.pump();

    final thumbHeight = tester
        .widget<Positioned>(find.byType(Positioned))
        .height!;
    // אופס: avg=0.5 → 1/(0.5*100)=0.02→clamp 0.05 → 30px. בלי איפוס היה ~52px.
    expect(thumbHeight, closeTo(30.0, 5.0));
  });

  testWidgets('listener ישן לא מעדכן State אחרי החלפת widget ו-dispose', (
    tester,
  ) async {
    final firstListener = ItemPositionsListener.create();
    final secondListener = ItemPositionsListener.create();
    final controller = ItemScrollController();

    Widget build(ItemPositionsListener listener) {
      return MaterialApp(
        home: ScrollablePositionedListScrollbar(
          scrollController: controller,
          itemPositionsListener: listener,
          itemCount: 10,
          child: const SizedBox.expand(),
        ),
      );
    }

    await tester.pumpWidget(build(firstListener));
    await tester.pumpWidget(build(secondListener));

    (secondListener.itemPositions as ValueNotifier<Iterable<ItemPosition>>)
        .value = const [
      ItemPosition(index: 1, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
    ];

    await tester.pumpWidget(const SizedBox.shrink());

    (firstListener.itemPositions as ValueNotifier<Iterable<ItemPosition>>)
        .value = const [
      ItemPosition(index: 1, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
    ];

    expect(tester.takeException(), isNull);
  });

  testWidgets('ריחוף על המסילה מציג תווית יעד ומסתיר אותה ביציאה', (
    tester,
  ) async {
    final listener = ItemPositionsListener.create();
    final controller = ItemScrollController();
    final requestedIndices = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            labelForIndex: (index) {
              requestedIndices.add(index);
              return 'יעד $index';
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    // 2 מתוך 100 גלויים → יש מה לגלול והסרגל מוצג.
    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.02),
          ItemPosition(index: 1, itemLeadingEdge: 0.02, itemTrailingEdge: 0.04),
        ];
    await tester.pump();

    // הסרגל בקצה שמאל (LTR בבדיקה) ברוחב 12; מתחילים מחוץ לסרגל ומרחפים
    // פנימה כדי שייווצר אירוע hover אמיתי על ה-MouseRegion.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(400, 300));
    addTearDown(() => gesture.removePointer());
    await tester.pump();
    await gesture.moveTo(const Offset(6, 300));
    await tester.pump();

    expect(requestedIndices, isNotEmpty, reason: 'ריחוף צריך לבקש כתובת יעד');
    expect(find.textContaining('יעד'), findsOneWidget);

    // יציאה מהמסילה מסתירה את התווית.
    await gesture.moveTo(const Offset(400, 300));
    await tester.pump();
    expect(find.textContaining('יעד'), findsNothing);
  });

  testWidgets('הקלקה בודדת על המסילה אינה משאירה תווית תקועה (מסך מגע)', (
    tester,
  ) async {
    // רגרסיה: במסך מגע אין onExit שיסתיר את התווית. כשהקלקה בודדת הציגה
    // אותה, היא נשארה קפואה על התוכן גם אחרי שהאצבע עזבה.
    final listener = ItemPositionsListener.create();
    final controller = _RecordingItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            labelForIndex: (index) => 'יעד $index',
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.02),
          ItemPosition(index: 1, itemLeadingEdge: 0.02, itemTrailingEdge: 0.04),
        ];
    await tester.pump();

    final track = find.byType(GestureDetector);
    final trackTopLeft = tester.getTopLeft(track);
    final trackBottomRight = tester.getBottomRight(track);
    final tapCenter = Offset(
      (trackTopLeft.dx + trackBottomRight.dx) / 2,
      (trackTopLeft.dy + trackBottomRight.dy) / 2,
    );

    await tester.tapAt(tapCenter);
    await tester.pump();

    expect(
      find.textContaining('יעד'),
      findsNothing,
      reason: 'הקלקה בודדת לא אמורה להשאיר תווית תקועה',
    );
  });

  testWidgets('ביטול גרירה (הרשימה ניצחה ב-arena) מסתיר את תווית היעד', (
    tester,
  ) async {
    // רגרסיה: בלי onVerticalDragCancel, גרירה שנקטעה השאירה את התווית תקועה
    // בזמן שהתוכן ממשיך לגלול.
    final listener = ItemPositionsListener.create();
    final controller = _RecordingItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            labelForIndex: (index) => 'יעד $index',
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.02),
          ItemPosition(index: 1, itemLeadingEdge: 0.02, itemTrailingEdge: 0.04),
        ];
    await tester.pump();

    final track = find.byType(GestureDetector);
    final trackTopLeft = tester.getTopLeft(track);
    final trackBottomRight = tester.getBottomRight(track);
    final startNearBottom = Offset(
      (trackTopLeft.dx + trackBottomRight.dx) / 2,
      trackBottomRight.dy - 5,
    );

    final gesture = await tester.startGesture(startNearBottom);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(
      find.textContaining('יעד'),
      findsOneWidget,
      reason: 'בזמן גרירה התווית מוצגת',
    );

    await gesture.cancel();
    await tester.pump();
    expect(
      find.textContaining('יעד'),
      findsNothing,
      reason: 'ביטול גרירה חייב להסתיר את התווית',
    );
  });

  testWidgets('בלי labelForIndex אין תווית ואין קריסה בריחוף', (tester) async {
    final listener = ItemPositionsListener.create();
    final controller = ItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 100,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
        const [
          ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.02),
          ItemPosition(index: 1, itemLeadingEdge: 0.02, itemTrailingEdge: 0.04),
        ];
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(6, 300));
    addTearDown(() => gesture.removePointer());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('האגודל אינו קופץ למעלה בזמן גלילה למטה', (tester) async {
    // רגרסיה: ספירת הפריטים הגלויים שלמה ומתנדנדת ב-±1 בכל מעבר פריט
    // (7.5 פריטים במסך = 8 או 9). כשהיא שימשה כמכנה של מיקום האגודל, כל
    // תנודה הזיזה אותו למעלה בעוצמה שגדלה עם העומק בספר — 18% מהפריימים.
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final listener = ItemPositionsListener.create();
    final controller = ItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 60,
            child: ScrollablePositionedList.builder(
              itemScrollController: controller,
              itemPositionsListener: listener,
              itemCount: 60,
              // 120px לפריט מול מסך 900px = 7.5 פריטים, כלומר הספירה
              // מתחלפת בין 8 ל-9 בכל מעבר.
              itemBuilder: (context, i) =>
                  SizedBox(height: 120, child: Text('פריט $i')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final thumb = find.descendant(
      of: find.byType(ScrollablePositionedListScrollbar),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );
    expect(thumb, findsOneWidget);

    var previousTop = tester.getRect(thumb).top;
    var moved = false;
    // השגיאה גדלה ליניארית עם העומק, ולכן צריך לגלול מספיק עמוק כדי לתפוס
    // אותה — 60 פריימים בלבד עוברים מעליה.
    for (var i = 0; i < 250; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(300, 450),
          scrollDelta: const Offset(0, 12),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      final top = tester.getRect(thumb).top;
      if (top > previousTop) moved = true;
      expect(
        top,
        greaterThanOrEqualTo(previousTop - 0.01),
        reason: 'האגודל ירד מ-$previousTop ל-$top בזמן גלילה למטה (פריים $i)',
      );
      previousTop = top;
    }
    expect(moved, isTrue, reason: 'האגודל כלל לא זז — הטסט אינו בודק כלום');
  });

  group('ויסות קפיצות בזמן גרירה', () {
    /// גורר את האגודל מראש המסילה כלפי מטה ב-[steps] שלבים.
    Future<_RecordingItemScrollController> dragThumb(
      WidgetTester tester, {
      required int steps,
      required double stepDy,
      bool release = true,
    }) async {
      final listener = ItemPositionsListener.create();
      final controller = _RecordingItemScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollablePositionedListScrollbar(
              scrollController: controller,
              itemPositionsListener: listener,
              itemCount: 1000,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
          const [
            ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
            ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
          ];
      await tester.pump();

      final track = find.byType(GestureDetector);
      final topLeft = tester.getTopLeft(track);
      final bottomRight = tester.getBottomRight(track);
      // תופסים את האגודל עצמו — הוא בראש המסילה.
      final gesture = await tester.startGesture(
        Offset((topLeft.dx + bottomRight.dx) / 2, topLeft.dy + 2),
      );
      await tester.pump();
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(0, stepDy));
        await tester.pump();
      }
      if (release) {
        await gesture.up();
        await tester.pump();
      }
      return controller;
    }

    testWidgets('התזוזה הראשונה קופצת מיד, בלי להמתין לוויסות', (tester) async {
      final controller = await dragThumb(
        tester,
        steps: 1,
        stepDy: 40,
        release: false,
      );

      expect(
        controller.jumps,
        isNotEmpty,
        reason: 'המשוב הראשון בגרירה חייב להיות מיידי',
      );
    });

    testWidgets('קפיצות ביניים מווסתות — לא קופצים בכל תזוזה', (tester) async {
      final controller = await dragThumb(tester, steps: 25, stepDy: 8);

      // בלי ויסות כל אחת מ-25 התזוזות הייתה מייצרת קפיצה.
      expect(
        controller.jumps.length,
        lessThan(25),
        reason: 'הוויסות לא חסם דבר',
      );
    });

    testWidgets('השחרור נוחת בדיוק ביעד האחרון שכוונה אליו הגרירה', (
      tester,
    ) async {
      final controller = await dragThumb(tester, steps: 25, stepDy: 8);

      final track = find.byType(GestureDetector);
      final trackHeight = tester.getSize(track).height;
      final thumb = find.descendant(
        of: find.byType(ScrollablePositionedListScrollbar),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      );
      // היעד הצפוי נגזר ממיקום האגודל בפועל בתום הגרירה.
      final thumbTop = tester.getRect(thumb).top - tester.getRect(track).top;
      final thumbHeightFraction = tester.getRect(thumb).height / trackHeight;
      final ratio = (thumbTop / trackHeight) / (1.0 - thumbHeightFraction);
      final expected = (ratio * (1000 - 2)).round();

      expect(controller.jumps.last, closeTo(expected, 2));
    });

    testWidgets('חזרה ליעד שכבר בוצע מבטלת יעד ממתין', (tester) async {
      final listener = ItemPositionsListener.create();
      final controller = _RecordingItemScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollablePositionedListScrollbar(
              scrollController: controller,
              itemPositionsListener: listener,
              itemCount: 1000,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      (listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>).value =
          const [
            ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
            ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
          ];
      await tester.pump();

      final track = find.byType(GestureDetector);
      final topLeft = tester.getTopLeft(track);
      final bottomRight = tester.getBottomRight(track);
      final gesture = await tester.startGesture(
        Offset((topLeft.dx + bottomRight.dx) / 2, topLeft.dy + 2),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      final firstTarget = controller.jumps.single;

      await gesture.moveBy(const Offset(0, 100));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(controller.jumps.last, firstTarget);
    });
  });

  testWidgets('בסוף הרשימה האגודל נוגע בתחתית המסילה', (tester) async {
    // רגרסיה: מכנה נפרד למיקום האגודל (ממוצע גלובלי) במקום מכנה אחד לשני
    // הכיוונים ניתק את האגודל מהתוכן — בסוף הרשימה הוא נעצר כ-4.6% מעל
    // התחתית. ה-fixture בונה היסטוריה של פריטים כבדים כדי שהממוצע הגלובלי
    // ייבדל מהמקומי; בלי הבדל כזה השגיאה אינה מתבטאת בכלל.
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final listener = ItemPositionsListener.create();
    final positions =
        listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>;
    final controller = ItemScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: 120,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    // אזור כבד: 2 פריטים למסך.
    positions.value = const [
      ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
      ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
    ];
    await tester.pump();

    // המסך האחרון של הרשימה: 13 פריטים קלים, האחרון מסתיים בדיוק בתחתית.
    positions.value = List.generate(
      13,
      (i) => ItemPosition(
        index: 107 + i,
        itemLeadingEdge: i / 13,
        itemTrailingEdge: (i + 1) / 13,
      ),
    );
    await tester.pump();

    final track = find.byType(GestureDetector);
    final thumb = find.descendant(
      of: find.byType(ScrollablePositionedListScrollbar),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );

    expect(
      tester.getRect(thumb).bottom,
      closeTo(tester.getRect(track).bottom, 1.0),
      reason: 'בסוף הרשימה האגודל חייב להיות צמוד לתחתית המסילה',
    );
  });

  group('בתוך פאנל צד — המסילה לא מתחת לידית שינוי הגודל', () {
    /// פאנל צד פתוח וניתן לשינוי גודל (כמו חלונית המפרשים), עם רשימה גלילה
    /// שיש לה [ScrollablePositionedListScrollbar].
    Future<void> pumpPane(
      WidgetTester tester, {
      required AlignmentDirectional alignment,
    }) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final listener = ItemPositionsListener.create();
      final controller = ItemScrollController();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he', 'IL'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('he', 'IL')],
          home: Scaffold(
            body: AdaptiveSidePane(
              isOpen: true,
              alignment: alignment,
              isResizable: true,
              onPaneWidthChanged: (_) {},
              onClose: () {},
              mainContent: const SizedBox.expand(),
              paneContent: ScrollablePositionedListScrollbar(
                scrollController: controller,
                itemPositionsListener: listener,
                itemCount: 100,
                child: ScrollablePositionedList.builder(
                  itemScrollController: controller,
                  itemPositionsListener: listener,
                  itemCount: 100,
                  itemBuilder: (context, i) =>
                      SizedBox(height: 80, child: Text('שורה $i')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    void expectThumbGrabbable(WidgetTester tester) {
      final scrollbar = find.byType(ScrollablePositionedListScrollbar);
      final thumb = find.descendant(
        of: scrollbar,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      );
      expect(thumb, findsOneWidget, reason: 'האגודל חייב להיות מוצג');
      final handle = find.byType(ResizableDragHandle);
      expect(handle, findsOneWidget, reason: 'ידית שינוי הגודל חייבת להיות שם');

      final thumbRect = tester.getRect(thumb);
      final handleRect = tester.getRect(handle);
      // המשתמש מכוון למרכז האגודל; אם גם הוא בשטח המגע של הידית, הסמן הופך
      // לחץ שינוי גודל והגרירה משנה את רוחב החלונית במקום לגלול.
      expect(
        handleRect.contains(thumbRect.center),
        isFalse,
        reason:
            'שטח המגע של הידית ($handleRect) בולע את מרכז האגודל ($thumbRect)',
      );

      // המסילה נשארת בכיוון הקריאה, כמו כל שאר מחווני הגלילה בעברית.
      expect(
        thumbRect.center.dx,
        greaterThan(tester.getRect(scrollbar).center.dx),
        reason: 'המסילה עברה לשמאל — כיוון הפוך לשאר המחוונים באפליקציה',
      );
    }

    /// הקו הנראה של הידית חייב לשבת על דופן הפאנל. שטח המגע גולש החוצה ואינו
    /// ממורכז עליה, ולכן בלי הזזה מפורשת הקו מרחף לידה ונראה מנותק.
    void expectGripOnPaneEdge(
      WidgetTester tester, {
      required bool paneOnRight,
    }) {
      final paneRect = tester.getRect(
        find.byType(ScrollablePositionedListScrollbar),
      );
      final paneEdge = paneOnRight ? paneRect.left : paneRect.right;
      final grip = tester.getRect(
        find.descendant(
          of: find.byType(ResizableDragHandle),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        grip.center.dx,
        closeTo(paneEdge, 0.5),
        reason: 'הקו הנראה של הידית מרחף במרחק מדופן הפאנל ($paneEdge)',
      );
    }

    testWidgets('פאנל בצד שמאל (חלונית המפרשים)', (tester) async {
      // רגרסיה: הגדלת שטח המגע של הידית (8px→24px, cc5ee27ae) הכפילה את
      // כניסתה לתוך הפאנל מ-4px ל-12px — בדיוק רוחב מסילת הגלילה שיושבת שם.
      await pumpPane(tester, alignment: AlignmentDirectional.centerStart);
      expectThumbGrabbable(tester);
      expectGripOnPaneEdge(tester, paneOnRight: false);
    });

    testWidgets('פאנל בצד ימין', (tester) async {
      await pumpPane(tester, alignment: AlignmentDirectional.centerEnd);
      expectThumbGrabbable(tester);
      expectGripOnPaneEdge(tester, paneOnRight: true);
    });
  });

  group('פריט גבוה מהמסך (חלונית המפרשים)', () {
    /// רשימה של [itemCount] פריטים בגובה 4000px בתוך מסך 600px, עם סרגל
    /// שמקבל offsetController — בדיוק צורת חלונית המפרשים (פריט = מפרש שלם).
    Future<ItemPositionsListener> dragThumbToBottom(
      WidgetTester tester, {
      required int itemCount,
    }) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final listener = ItemPositionsListener.create();
      final controller = ItemScrollController();
      final offsetController = ScrollOffsetController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollablePositionedListScrollbar(
              scrollController: controller,
              offsetController: offsetController,
              itemPositionsListener: listener,
              itemCount: itemCount,
              child: ScrollablePositionedList.builder(
                itemScrollController: controller,
                itemPositionsListener: listener,
                scrollOffsetController: offsetController,
                itemCount: itemCount,
                itemBuilder: (context, i) =>
                    SizedBox(height: 4000, child: Text('פריט $i')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final thumb = find.descendant(
        of: find.byType(ScrollablePositionedListScrollbar),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      );
      final gesture = await tester.startGesture(tester.getRect(thumb).center);
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      return listener;
    }

    /// הקצה העליון של הפריט הראשון הגלוי, ביחידות viewport.
    ItemPosition firstVisible(ItemPositionsListener listener) =>
        listener.itemPositions.value.reduce(
          (a, b) => a.index <= b.index ? a : b,
        );

    testWidgets('מפרש בודד ארוך — גרירת האגודל גוללת עד סוף התוכן', (
      tester,
    ) async {
      // רגרסיה: הסרגל קפץ לאינדקס פריט שלם בלבד. עם מפרש אחד היעד היחיד היה
      // 0, ולכן גרירת האגודל לא הזיזה כלום והוא חזר לראש המסילה.
      final listener = await dragThumbToBottom(tester, itemCount: 1);

      // 4000px תוכן במסך 600px → גלילה מרבית 3400px = 5.667 viewports.
      expect(firstVisible(listener).index, 0);
      expect(firstVisible(listener).itemLeadingEdge, closeTo(-5.667, 0.1));
    });

    testWidgets('כמה מפרשים ארוכים — הגרירה מגיעה לסוף האחרון, לא לתחילתו', (
      tester,
    ) async {
      // רגרסיה: קפיצה לאינדקס נחתה בתחילת הפריט האחרון, ו-3400px האחרונים
      // (28% מהתוכן) היו בלתי-נגישים דרך הסרגל.
      final listener = await dragThumbToBottom(tester, itemCount: 3);

      expect(firstVisible(listener).index, 2);
      expect(firstVisible(listener).itemLeadingEdge, closeTo(-5.667, 0.1));
    });
  });

  testWidgets('האגודל אינו זז אחרי שהתוכן נוחת ביעד הגרירה', (tester) async {
    // רגרסיה: מיפוי המיקום והמיפוי ההפוך חייבים לחלוק מכנה. כשהופרדו, שחרור
    // הגרירה נחת עד 4.3% מהמסילה מתחת למקום שהמשתמש עזב — האגודל "ברח"
    // מהאצבע. ה-fixture מייצר הבדל בין הממוצע הגלובלי למקומי, אחרת שני
    // המכנים שווים במקרה והשגיאה אינה מתבטאת.
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final listener = ItemPositionsListener.create();
    final positions =
        listener.itemPositions as ValueNotifier<Iterable<ItemPosition>>;
    final controller = _RecordingItemScrollController();
    const itemCount = 120;
    const visibleAtTarget = 13;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollablePositionedListScrollbar(
            scrollController: controller,
            itemPositionsListener: listener,
            itemCount: itemCount,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    /// פוזיציות של מסך שמתחיל ב-[first] עם [visibleAtTarget] פריטים.
    List<ItemPosition> screenAt(int first) => List.generate(
      visibleAtTarget,
      (i) => ItemPosition(
        index: first + i,
        itemLeadingEdge: i / visibleAtTarget,
        itemTrailingEdge: (i + 1) / visibleAtTarget,
      ),
    );

    // היסטוריה כבדה (2 פריטים למסך) כדי שהממוצע הגלובלי ייבדל מהמקומי.
    positions.value = const [
      ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
      ItemPosition(index: 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
    ];
    await tester.pump();

    positions.value = screenAt(20);
    await tester.pump();

    final thumb = find.descendant(
      of: find.byType(ScrollablePositionedListScrollbar),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );

    // גרירת האגודל מטה. את המיקום מודדים ברגע השחרור, לפני שהתוכן זז.
    final gesture = await tester.startGesture(tester.getRect(thumb).center);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    final topAtRelease = tester.getRect(thumb).top;
    await gesture.up();
    await tester.pump();

    expect(controller.jumps, isNotEmpty);
    final landedIndex = controller.jumps.last;

    // הרשימה מרנדרת את היעד — בדיוק מה שקורה במסך אחרי jumpTo.
    positions.value = screenAt(landedIndex);
    await tester.pump();
    await tester.pump();

    // שני מקורות סטייה קיימים מלכתחילה: היעד מעוגל לאינדקס שלם (~2.6px כאן),
    // וגובה האגודל נאמד מחדש כשנמדדים פריטים נוספים (~3px). הרגרסיה שנשמרת
    // כאן גדולה מהם בסדר גודל — 22-34px.
    expect(
      tester.getRect(thumb).top,
      closeTo(topAtRelease, 8.0),
      reason: 'האגודל זז אחרי שהתוכן נחת — המיפוי קדימה וההפוך אינם מתאימים',
    );
  });
}
