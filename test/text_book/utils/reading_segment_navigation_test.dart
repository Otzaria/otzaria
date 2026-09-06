import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  group('isRemnantAbovePositionAnchor', () {
    test('קטע שנגמר בקו העוגן ומתחיל מעליו - שייר', () {
      expect(isRemnantAbovePositionAnchor(-0.2, 0.05), isTrue);
      expect(isRemnantAbovePositionAnchor(0.0, 0.055), isTrue);
      // שייר קצר שנגמר בדיוק בעוגן - עדיין שייר, לא יעד.
      expect(isRemnantAbovePositionAnchor(0.04, 0.05), isTrue);
    });

    test('קטע קצר שמתחיל בקו העוגן (בגבול הרעש) הוא יעד הניווט, לא שייר', () {
      // פסוק קצר בפתיחת פרשה: רוחבו קטן מהסבילות אך הוא מתחיל בעוגן עצמו.
      expect(isRemnantAbovePositionAnchor(0.0499, 0.0677), isFalse);
      expect(isRemnantAbovePositionAnchor(0.05, 0.065), isFalse);
    });

    test('קטע עם נוכחות משמעותית מתחת לעוגן אינו שייר', () {
      expect(isRemnantAbovePositionAnchor(-0.1, 0.3), isFalse);
    });
  });

  testWidgets(
    'scrollToSourceLine: duration zero + סגמנט גלוי + fraction>0 לא קורס',
    (tester) async {
      final itemScrollController = ItemScrollController();
      final scrollOffsetController = ScrollOffsetController();
      final positionsListener = ItemPositionsListener.create();

      final lines = List.generate(20, (i) => 'שורה מספר $i');
      final segments = buildReadingSegments(lines, continuous: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ScrollablePositionedList.builder(
                itemScrollController: itemScrollController,
                scrollOffsetController: scrollOffsetController,
                itemPositionsListener: positionsListener,
                itemCount: lines.length,
                // פריט גבוה מה-viewport כדי שדיוק תוך-סגמנטי אכן יגלול.
                itemBuilder: (context, index) =>
                    SizedBox(height: 600, child: Text(lines[index])),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // המסלול שעלול היה לזרוק assert(duration > Duration.zero):
      // animateScroll עם Duration.zero כשהסגמנט גלוי ו-fraction>0.
      // הרצה במקביל ל-pump כדי שאנימציית הדיוק תושלם.
      final scrollFuture = scrollToSourceLine(
        scrollController: itemScrollController,
        scrollOffsetController: scrollOffsetController,
        positionsListener: positionsListener,
        segments: segments,
        lineIndex: 0,
        viewportExtent: 400,
        duration: Duration.zero,
        intraLineFraction: 0.5,
      );
      await tester.pumpAndSettle();
      await scrollFuture;

      expect(tester.takeException(), isNull);
      final position = positionsListener.itemPositions.value.singleWhere(
        (item) => item.index == 0,
      );
      final targetEdge =
          position.itemLeadingEdge +
          0.5 * (position.itemTrailingEdge - position.itemLeadingEdge);
      expect(
        targetEdge,
        closeTo(kReadingAnchorAlignment, kAnchorLandingEpsilon),
        reason: 'היעד בתוך הסגמנט חייב לנחות על קו העוגן',
      );
    },
  );

  testWidgets(
    'scrollToSourceLine: יעד כותרת (ללא דיוק תוך-שורתי) מתוקן לעוגן גם כשהגלילה הופרעה',
    (tester) async {
      final itemScrollController = ItemScrollController();
      final scrollOffsetController = ScrollOffsetController();
      final positionsListener = ItemPositionsListener.create();

      final lines = List.generate(30, (i) => 'שורה מספר $i');
      final segments = buildReadingSegments(lines, continuous: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ScrollablePositionedList.builder(
                itemScrollController: itemScrollController,
                scrollOffsetController: scrollOffsetController,
                itemPositionsListener: positionsListener,
                itemCount: lines.length,
                itemBuilder: (context, index) =>
                    SizedBox(height: 100, child: Text(lines[index])),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFuture = scrollToSourceLine(
        scrollController: itemScrollController,
        scrollOffsetController: scrollOffsetController,
        positionsListener: positionsListener,
        segments: segments,
        lineIndex: 7,
        viewportExtent: 400,
        duration: const Duration(milliseconds: 250),
      );

      // הפרעה באמצע האנימציה (מדמה reanchor/רה-פריסה מטעינה הדרגתית):
      // היעד נשאר גלוי אך רחוק מקו העוגן.
      await tester.pump(const Duration(milliseconds: 100));
      itemScrollController.jumpTo(index: 7, alignment: 0.5);

      await tester.pumpAndSettle();
      await scrollFuture;

      expect(tester.takeException(), isNull);
      final position = positionsListener.itemPositions.value.singleWhere(
        (item) => item.index == 7,
      );
      expect(
        position.itemLeadingEdge,
        closeTo(kReadingAnchorAlignment, kAnchorLandingEpsilon),
        reason: 'ניווט מכותרות חייב להתאושש מהפרעה ולנחות על קו העוגן',
      );
    },
  );

  testWidgets(
    'scrollToSourceLine: רשימה שירדה מהעץ באמצע האנימציה לא זורקת',
    (tester) async {
      final itemScrollController = ItemScrollController();
      final scrollOffsetController = ScrollOffsetController();
      final positionsListener = ItemPositionsListener.create();

      final lines = List.generate(20, (i) => 'שורה מספר $i');
      final segments = buildReadingSegments(lines, continuous: false);

      Widget app({required bool withList}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: withList
                ? ScrollablePositionedList.builder(
                    itemScrollController: itemScrollController,
                    scrollOffsetController: scrollOffsetController,
                    itemPositionsListener: positionsListener,
                    itemCount: lines.length,
                    // פריט גבוה מה-viewport: היעד גלוי, ולכן הגלילה עוברת
                    // ב-animateScroll ולא בקפיצה שנוחתת מיד על העוגן.
                    itemBuilder: (context, index) =>
                        SizedBox(height: 600, child: Text(lines[index])),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      );

      await tester.pumpWidget(app(withList: true));
      await tester.pumpAndSettle();

      final scrollFuture = scrollToSourceLine(
        scrollController: itemScrollController,
        scrollOffsetController: scrollOffsetController,
        positionsListener: positionsListener,
        segments: segments,
        lineIndex: 0,
        viewportExtent: 400,
        duration: const Duration(milliseconds: 250),
        intraLineFraction: 0.5,
      );

      // הפריים הראשון מתניע את האנימציה; השני מקדם אותה לאמצע.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // הכרטיסיה נסגרה / עברה לחלון אחר באמצע האנימציה.
      await tester.pumpWidget(app(withList: false));
      await tester.pumpAndSettle();

      expect(itemScrollController.isAttached, isFalse);
      expect(
        positionsListener.itemPositions.value,
        isNotEmpty,
        reason:
            'המדידה האחרונה נשארת אחרי הניתוק — ולכן היא אינה עדות לרשימה חיה',
      );
      await expectLater(scrollFuture, completes);
      expect(tester.takeException(), isNull);
    },
  );

  group('closePaneAfterNavigation', () {
    test('לא סוגר את החלונית לפני שהגלילה הסתיימה', () async {
      final navigation = Completer<void>();
      var closed = false;

      final future = closePaneAfterNavigation(
        navigation: navigation.future,
        closePane: () => closed = true,
      );

      // מתן הזדמנות ל-microtasks לרוץ — הסגירה עדיין אסורה.
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);

      navigation.complete();
      await future;
      expect(closed, isTrue);
    });

    test('סוגר את החלונית גם כשהגלילה נכשלה', () async {
      final navigation = Completer<void>();
      var closed = false;

      final future = closePaneAfterNavigation(
        navigation: navigation.future,
        closePane: () => closed = true,
      );

      navigation.completeError(StateError('scroll failed'));
      await expectLater(future, throwsStateError);
      expect(closed, isTrue);
    });
  });
}
