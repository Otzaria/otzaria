import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
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

  testWidgets(
      'הקלקה על תחתית המסילה מגיעה לסוף הספר גם כשמעט פריטים גלויים '
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

  testWidgets(
      'עדכון maxScrollableIndex אחרי שינוי positions: '
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

  testWidgets(
      'גרירה שמתחילה על המסילה מחוץ לאגודל קופצת ליעד הנלחץ '
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

  testWidgets('לחיצה שמתחילה על האגודל עצמו אינה ממקמת אותו מחדש ומקפיצה',
      (tester) async {
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

  testWidgets('אחרי לחיצה וקפיצה ליעד, האגודל אינו "יורד" כשהפוזיציות מתעדכנות',
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
    final thumbTopAfterTap =
        tester.widget<Positioned>(find.byType(Positioned)).top!;
    final targetIndex = controller.jumps.last;

    // מדמים שהרשימה אכן קפצה ליעד: היעד נעשה הפריט הראשון הגלוי.
    positions.value = [
      ItemPosition(
          index: targetIndex, itemLeadingEdge: 0, itemTrailingEdge: 0.5),
      ItemPosition(
          index: targetIndex + 1, itemLeadingEdge: 0.5, itemTrailingEdge: 1.0),
    ];
    await tester.pump();

    final thumbTopAfterSettle =
        tester.widget<Positioned>(find.byType(Positioned)).top!;

    // האגודל חייב להישאר במקום שנלחץ — בלי "ירידה".
    expect(thumbTopAfterSettle, closeTo(thumbTopAfterTap, 2.0));
  });

  testWidgets('listener ישן לא מעדכן State אחרי החלפת widget ו-dispose',
      (tester) async {
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

  testWidgets('ריחוף על המסילה מציג תווית יעד ומסתיר אותה ביציאה',
      (tester) async {
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

  testWidgets('הקלקה בודדת על המסילה אינה משאירה תווית תקועה (מסך מגע)',
      (tester) async {
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

    expect(find.textContaining('יעד'), findsNothing,
        reason: 'הקלקה בודדת לא אמורה להשאיר תווית תקועה');
  });

  testWidgets('ביטול גרירה (הרשימה ניצחה ב-arena) מסתיר את תווית היעד',
      (tester) async {
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
    expect(find.textContaining('יעד'), findsOneWidget,
        reason: 'בזמן גרירה התווית מוצגת');

    await gesture.cancel();
    await tester.pump();
    expect(find.textContaining('יעד'), findsNothing,
        reason: 'ביטול גרירה חייב להסתיר את התווית');
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
}
