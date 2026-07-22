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
