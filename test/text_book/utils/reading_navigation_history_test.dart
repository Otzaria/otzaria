import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/view/widgets/reader_back_button.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/reading_toc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const initial = ReadingAnchor(
    line: 5,
    intraLineFraction: 0.6,
    alignment: 0.2,
  );

  test('חזרה מנווטת לנקודה הקודמת בתוך השורה בלי לרשום את עצמה', () async {
    final lines = LineScrollController(initialAnchor: initial);
    addTearDown(lines.dispose);
    await lines.scrollToLine(20, intraLineFraction: 0.7, alignment: 0.3);
    await lines.jumpToLine(40);
    await lines.goBack();
    expect(
      lines.captureAnchor(),
      const ReadingAnchor(
        line: 20,
        intraLineFraction: 0.7,
        alignment: 0.3,
      ),
    );
    await lines.goBack();
    expect(lines.captureAnchor(), initial);
    expect(lines.canGoBack.value, isFalse);
  });

  test('גלילה שוטפת אינה מייצרת היסטוריה; גרירת מסילה לוכדת פעם אחת', () async {
    final lines = LineScrollController();
    addTearDown(lines.dispose);
    lines.reportExternalLine(10);
    lines.reportExternalLine(20);
    expect(lines.canGoBack.value, isFalse);
    lines.beginUserNavigation();
    lines.reportExternalLine(200);
    await lines.goBack();
    expect(lines.captureAnchor()!.line, 20);
    expect(lines.canGoBack.value, isFalse);
  });

  test('היסטוריה ממושכת נשארת מוגבלת', () async {
    final lines = LineScrollController(initialAnchor: initial);
    addTearDown(lines.dispose);
    for (var line = 6; line <= 1000; line++) {
      await lines.jumpToLine(line);
    }
    var count = 0;
    while (lines.canGoBack.value) {
      await lines.goBack();
      count++;
    }
    expect(count, 50);
    expect(lines.captureAnchor()!.line, 950);
  });

  testWidgets('ניתוק הקורא שומר את גובה העוגן שנמדד לפניו', (tester) async {
    final lines = LineScrollController();
    final segments = buildReadingSegments(
      List.generate(100, (i) => 'שורה $i'),
      continuous: false,
    );
    final binding = ReadingViewportBinding(
      segments: () => segments,
      viewportExtent: () => 600,
    );
    lines.attach(binding);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: ScrollablePositionedList.builder(
          itemScrollController: lines.itemController,
          itemPositionsListener: lines.positionsListener,
          initialScrollIndex: 20,
          initialAlignment: 0.2,
          itemCount: 100,
          itemBuilder: (_, index) =>
              SizedBox(height: 80, child: Text('$index')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final measured = lines.captureAnchor();
    expect(measured, isNotNull);
    lines.detach(binding);
    expect(lines.captureAnchor(), measured);
    await tester.pumpWidget(const SizedBox());
    lines.dispose();
  });

  for (final startsOutsideReader in [false, true]) {
    testWidgets('החזקת PageDown אחרי קישור היא נקודת חזרה אחת '
        '${startsOutsideReader ? '(התחילה מחוץ לקורא)' : ''} (issue #3909)', (
      tester,
    ) async {
      final lines = LineScrollController();
      final segments = buildReadingSegments(
        List.generate(400, (i) => 'שורה $i'),
        continuous: false,
      );
      lines.attach(
        ReadingViewportBinding(
          segments: () => segments,
          viewportExtent: () => 600,
        ),
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      // החיבור של התצוגה הרגילה (CombinedView).
      await tester.pumpWidget(
        MaterialApp(
          home: ProgressiveScroll(
            scrollController: lines.itemController,
            focusNode: focus,
            onNavigationStart: lines.beginUserNavigation,
            child: ScrollablePositionedList.builder(
              itemScrollController: lines.itemController,
              itemPositionsListener: lines.positionsListener,
              itemCount: 400,
              itemBuilder: (_, index) =>
                  SizedBox(height: 80, child: Text('$index')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final beforeLink = lines.captureAnchor()!.line;
      // כך מנווט קישור בתוך הספר.
      final link = lines.scrollToLine(200);
      await tester.pumpAndSettle();
      await link;
      if (startsOutsideReader) {
        unawaited(
          showDialog<void>(
            context: tester.element(find.byType(ProgressiveScroll).first),
            builder: (_) =>
                const AlertDialog(content: TextField(autofocus: true)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
        Navigator.of(tester.element(find.byType(TextField))).pop();
        await tester.pumpAndSettle();
      }
      focus.requestFocus();
      await tester.pump();

      // חזרת מקלדת של Windows: כ-30 בשנייה, שני פריימים בין חזרה לחזרה.
      if (!startsOutsideReader) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
      }
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 17));
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(lines.captureAnchor()!.line, greaterThan(200));

      Future<int> back() async {
        final navigation = lines.goBack();
        await tester.pumpAndSettle();
        await navigation;
        return lines.captureAnchor()!.line;
      }

      expect(await back(), 200);
      expect(await back(), beforeLink);
      expect(lines.canGoBack.value, isFalse);
      await tester.pumpWidget(const SizedBox());
      lines.dispose();
    });
  }

  testWidgets('כפתור חזרה מופעל אחרי ניווט ומשחזר את העוגן', (tester) async {
    final lines = LineScrollController(initialAnchor: initial);
    addTearDown(lines.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ReaderBackButton(lines: lines),
        ),
      ),
    );
    expect(tester.widget<BarButton>(find.byType(BarButton)).onPressed, isNull);
    await lines.jumpToLine(500);
    await tester.pump();
    expect(
      tester.widget<BarButton>(find.byType(BarButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byType(BarButton));
    await tester.pump();
    expect(lines.captureAnchor(), initial);
    expect(tester.widget<BarButton>(find.byType(BarButton)).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
