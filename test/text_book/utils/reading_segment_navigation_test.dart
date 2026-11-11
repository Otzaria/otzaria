import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/reading_toc.dart';

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
        positionsListener: positionsListener,
        segments: segments,
        lineIndex: 0,
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
    'scrollToSourceLine: ניווט חדש מבטל את הישן בלי תיקון שמחזיר אליו',
    (tester) async {
      final itemScrollController = ItemScrollController();
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
        positionsListener: positionsListener,
        segments: segments,
        lineIndex: 7,
        duration: const Duration(milliseconds: 250),
      );

      // ניווט חדש מחליף את הקודם גם כשהוא בוחר את אותו פריט ביישור אחר.
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
        closeTo(0.5, kAnchorLandingEpsilon),
        reason: 'ניווט שבוטל לא רשאי לתקן את המיקום שבחר הניווט החדש',
      );
    },
  );

  testWidgets(
    'scrollToSourceLine: רשימה שירדה מהעץ באמצע האנימציה לא זורקת',
    (tester) async {
      final itemScrollController = ItemScrollController();
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
        positionsListener: positionsListener,
        segments: segments,
        lineIndex: 0,
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

  testWidgets(
    'scrollToSourceLine: טעינת תוכן לפני היעד באמצע הגלילה — היעד נוחת',
    (tester) async {
      // issue #1973: טעינת רקע ממלאת פסקאות לפני היעד תוך כדי הגלילה אליו;
      // מספור הפריטים יציב, והיעד נמדד מול התוכן העדכני.
      final itemScrollController = ItemScrollController();
      final positionsListener = ItemPositionsListener.create();

      final lines = [
        '<h2>פרק א</h2>',
        'פסוק א בפרק א',
        'פסוק ב בפרק א',
        '<h2>פרק ב</h2>',
        'פסוק א בפרק ב',
        'פסוק ב בפרק ב',
        'פסוק ג בפרק ב',
        // פרק נוסף אחרי היעד, כדי שיהיה לאן לגלול כשמיישרים שורה בסוף פסקה.
        '<h2>פרק ג</h2>',
        'פסוק א בפרק ג',
      ];
      final partialFlags = [
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
      ];
      // [כותרת 0, פסקה 1..2, כותרת 3, פסקה 4..6, כותרת 7, פסקה 8]; בהתחלה
      // רק הפרק הראשון אינו טעון.
      final partial = buildReadingSegments(
        [
          for (var i = 0; i < lines.length; i++)
            partialFlags[i] ? lines[i] : '',
        ],
        continuous: true,
        loadedLineFlags: partialFlags,
        breakLines: readingBreakLines(headerToc(lines)),
      );
      final full = buildReadingSegments(lines, continuous: true);
      expect(full.length, partial.length);
      var segments = partial;
      late StateSetter setListState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setListState = setState;
                  return ScrollablePositionedList.builder(
                    itemScrollController: itemScrollController,
                    itemPositionsListener: positionsListener,
                    itemCount: segments.length,
                    // פריט גבוה מה-viewport כדי שדיוק תוך-סגמנטי אכן יגלול.
                    itemBuilder: (context, index) => SizedBox(
                      height: 600,
                      child: Text(segments[index].text),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const targetLine = 6;
      final scrollFuture = scrollToSourceLine(
        scrollController: itemScrollController,
        positionsListener: positionsListener,
        segments: partial,
        latestSegments: () => segments,
        lineIndex: targetLine,
        duration: const Duration(milliseconds: 250),
      );
      // באמצע האנימציה הפרק הראשון נטען.
      await tester.pump(const Duration(milliseconds: 60));
      setListState(() => segments = full);
      await tester.pumpAndSettle();
      await scrollFuture;

      expect(tester.takeException(), isNull);
      final targetIndex = segmentIndexForLine(full, targetLine);
      expect(targetIndex, 3);
      final position = positionsListener.itemPositions.value.singleWhere(
        (item) => item.index == targetIndex,
      );
      final fraction = lineFractionWithinSegment(full[targetIndex], targetLine);
      final targetEdge =
          position.itemLeadingEdge +
          fraction * (position.itemTrailingEdge - position.itemLeadingEdge);
      expect(
        targetEdge,
        closeTo(kReadingAnchorAlignment, kAnchorLandingEpsilon),
        reason: 'השורה חייבת לנחות על קו העוגן גם אחרי טעינת התוכן',
      );
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

  group('initialReadingAlignment', () {
    test('פתיחה בפריט הראשון מיישרת לקצה — אין תוכן מעל קו העוגן', () {
      expect(initialReadingAlignment(0), 0);
    });

    test('פתיחה בפריט אחר נשארת על קו העוגן', () {
      expect(initialReadingAlignment(1), kReadingAnchorAlignment);
      expect(initialReadingAlignment(120), kReadingAnchorAlignment);
    });
  });

  group('readingExtentEstimator', () {
    const plain = 'בראשית ברא אלהים את השמים ואת הארץ והארץ היתה תהו ובהו';
    const vocalized =
        'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ '
        'וְהָאָ֗רֶץ הָיְתָ֥ה תֹ֙הוּ֙ וָבֹ֔הוּ';

    test('אינו בונה פסקאות', () {
      final segments = buildReadingSegments(
        [for (var i = 0; i < 2000; i++) plain],
        continuous: true,
        breakLines: [for (var i = 0; i < 2000; i += 10) i],
      );
      final estimate = readingExtentEstimator(segments, 20);
      for (var i = 0; i < segments.length; i++) {
        estimate(i, 400);
      }
      expect(segments.debugBuiltCount, 0);
    });

    test('ניקוד, טעמים ותגיות אינם מגדילים את ההערכה', () {
      expect(visibleReadingCharCount(vocalized), plain.length);
      expect(visibleReadingCharCount('<b>$plain</b>'), plain.length);
      final lines = [
        for (var i = 0; i < 20; i++) plain,
        for (var i = 0; i < 20; i++) '<span>$vocalized</span>',
      ];
      final segments = buildReadingSegments(
        lines,
        continuous: true,
        breakLines: const [0, 20],
      );
      final estimate = readingExtentEstimator(segments, 20);
      expect(estimate(3, 400) / estimate(1, 400), closeTo(1, 0.05));
    });

    test('פריט שלא נטען מוערך לפי האורך הממוצע של הטעונים', () {
      final lines = [for (var i = 0; i < 30; i++) plain];
      final segments = buildReadingSegments(
        lines,
        continuous: true,
        breakLines: const [0, 10, 20],
        loadedLineFlags: [for (var i = 0; i < 30; i++) i < 20],
      );
      final estimate = readingExtentEstimator(segments, 20);
      expect(estimate(5, 400), estimate(1, 400));
    });
  });
}
