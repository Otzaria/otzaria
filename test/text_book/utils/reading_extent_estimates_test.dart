import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/text_book/utils/reading_extent_estimates.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/utils/reading_extent_worker_queue.dart';
import 'package:otzaria/text_book/view/widgets/reading_extent_estimation.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('סגירת ספר משחררת ספירה בתור ואינה מפעילה isolate מיותר', () async {
    final queue = ReadingExtentWorkerQueue();
    final running = Completer<int>();
    final first = queue.enqueue(() => running.future);
    await Future<void>.delayed(Duration.zero);
    final data = ReadingExtentEstimates.withWorkerQueue(
      _segments(List.filled(10000, 'טקסט של ספר שנסגר')),
      queue,
    );
    final refresh = data.refresh();
    data.dispose();
    expect((await refresh).ranges, isEmpty);
    expect(queue.debugStartedJobs, 1);
    running.complete(1);
    await first.result;
    await Future<void>.delayed(Duration.zero);
    expect(queue.debugStartedJobs, 1);
    expect(data.debugCountedLines, 0);
  });

  test('השבתה בזמן ספירה דוחה מנת חימום נוספת עד לחזרה', () async {
    final queue = _GatedWorkerQueue();
    final identity = Object();
    final data = ReadingExtentEstimates.withWorkerQueue(
      _segments(List.filled(10000, 'אב'), identity: identity, version: 1),
      queue,
    );
    addTearDown(data.dispose);
    var enabled = true;
    final refresh = data.refresh(shouldContinue: () => enabled);
    await queue.started.future;
    data.update(
      _segments(
        List.filled(10000, 'א' * 100),
        identity: identity,
        version: 2,
        changes: ContentLineChanges(
          fromVersion: 1,
          ranges: [(first: 0, last: 9999)],
        ),
      ),
    );
    enabled = false;
    queue.release.complete();
    expect((await refresh).full, isTrue);
    expect(queue.debugStartedJobs, 1);
    expect(data.debugCountedLines, 10000);
    expect(data.needsRefresh, isTrue);
    expect((await data.refresh(shouldContinue: () => enabled)).ranges, isEmpty);
    expect(queue.debugStartedJobs, 1);
    enabled = true;
    final resumed = await data.refresh(shouldContinue: () => enabled);
    expect(resumed.full, isFalse);
    expect(resumed.ranges, [(first: 0, last: 9999)]);
    expect(queue.debugStartedJobs, 2);
    expect(data.debugCountedLines, 20000);
    expect(data.needsRefresh, isFalse);
  });

  test('שחרור תוכן בטאב רקע אינו משנה את הערכות הגובה (issue #4173)', () async {
    final identity = Object();
    final content = [for (var i = 0; i < 3000; i++) 'א' * (1 + i % 7 * 90)];
    // ספר שחומם בחלקו: 2000 השורות הראשונות נספרו, השאר טרם נטענו.
    final data = ReadingExtentEstimates(
      _segments(
        content,
        identity: identity,
        version: 1,
        flags: [for (var i = 0; i < 3000; i++) i < 2000],
      ),
    );
    addTearDown(data.dispose);
    await data.refresh();
    // חימום הדרגתי משמר את הערכת השורות שטרם נטענו גם כשהממוצע השתנה.
    final warmed = List<String>.of(content)..fillRange(2000, 2700, 'א' * 1000);
    data.update(
      _segments(
        warmed,
        identity: identity,
        version: 2,
        flags: [for (var i = 0; i < 3000; i++) i < 2700],
        changes: ContentLineChanges(
          fromVersion: 1,
          ranges: [(first: 2000, last: 2699)],
        ),
      ),
    );
    expect((await data.refresh()).full, isFalse);
    const metrics = ReadingExtentMetrics(lineExtent: 20, charWidth: 8);
    final items = [100, 1000, 2500, 2800];
    final before = [for (final i in items) data.estimate(i, 400, metrics)];

    bool kept(int i) => (i - 1000).abs() <= 50;
    data.update(
      _segments(
        [for (var i = 0; i < 3000; i++) kept(i) ? warmed[i] : ''],
        identity: identity,
        version: 3,
        flags: [for (var i = 0; i < 3000; i++) kept(i)],
      ),
    );
    await data.refresh();
    expect([for (final i in items) data.estimate(i, 400, metrics)], before);
  });

  test('מסיר רק סימנים משולבים ומשאיר פיסוק עברי', () {
    expect(visibleReadingCharCount('אַ֑ב־ג׀ד׃ה׆ו'), 'אב־ג׀ד׃ה׆ו'.length);
    expect(visibleReadingCharCount('e\u0301'), 1);
    expect(visibleReadingCharCount('😀'), 1);
  });

  test('מפענח ישויות אחרי הסרת תגיות ומסתיר גוף הערות', () {
    expect(visibleReadingCharCount('&amp;&#x5BE;&#1472;&nbsp;&lt;b&gt;'), 7);
    expect(
      visibleReadingCharCount(
        'אב<sup class="footnote-marker">א</sup>'
        '<i class="footnote">${'גוף הערה ארוך ' * 1000}</i>גד',
      ),
      5,
    );
    expect(visibleReadingCharCount('<b>אב</b><span>גד</span>'), 4);
  });

  test('זהה לספירה ב-RegExp וב-runes על כל תו ועל צירופים אקראיים (perf)', () {
    // אורקל: המימוש הקודם.
    final tags = RegExp(r'<[^>]*>');
    final combining = RegExp(r'\p{M}', unicode: true);
    int oracle(String text) {
      var plain = notes.stripInlineNotes(text);
      if (plain.contains('<')) plain = plain.replaceAll(tags, '');
      if (plain.contains('&')) plain = html.parseFragment(plain).text ?? plain;
      var count = 0;
      for (final code in plain.runes) {
        if ((code >= 0x591 && code <= 0x5BD) ||
            code == 0x5BF ||
            code == 0x5C1 ||
            code == 0x5C2 ||
            code == 0x5C4 ||
            code == 0x5C5 ||
            code == 0x5C7) {
          continue;
        }
        if (code < 0x300 || (code >= 0x5D0 && code < 0x600)) {
          count++;
        } else if (!combining.hasMatch(String.fromCharCode(code))) {
          count++;
        }
      }
      return count;
    }

    final inputs = <String>[
      for (var c = 0; c <= 0xFFFF; c++) 'א<b>${String.fromCharCode(c)}</b>ב',
      for (final c in const [0x1F600, 0x1D167, 0xE0100, 0x10FFFF])
        'א${String.fromCharCode(c)}<b>ב',
    ];
    const pieces = [
      '<', '>', '<b>', '</b>', '<span class="x">', '<br>', '&amp;', '&lt;', //
      '&nbsp;', '&#x5BE;', '&#1472;', '&', ';', ' ', 'א', 'בְּ', 'רֵאשִׁ֖ית', //
      '־', '׀', '׃', '׆', '׈', 'é', '😀', '\uD83D', '\uDE00', //
      '<sup class="footnote-marker">1</sup><i class="footnote">הערה</i>', //
    ];
    final random = Random(7);
    for (var i = 0; i < 20000; i++) {
      inputs.add(
        [
          for (var j = random.nextInt(12); j > 0; j--)
            pieces[random.nextInt(pieces.length)],
        ].join(),
      );
    }
    for (final input in inputs) {
      expect(visibleReadingCharCount(input), oracle(input), reason: input);
    }
  });

  test('מידות השורות ורוחב העמודה משפיעים על ההערכה', () {
    final segments = _segments(['א' * 1000]);
    final full = readingExtentEstimator(
      segments,
      20,
      lineHeight: 1,
      verticalPadding: 0,
    );
    final narrow = readingExtentEstimator(
      segments,
      20,
      lineHeight: 2,
      contentWidthRatio: 0.5,
      verticalPadding: 0,
    );
    expect(narrow(0, 300), closeTo(full(0, 300) * 4, 40));
    expect(segments.debugBuiltCount, 0);
  });

  test('דלתאות רציפות ממוזגות ומעדכנות רק את שורותיהן', () async {
    final identity = Object();
    final content = List<String>.filled(20000, 'אבגד');
    var snapshot = _segments(content, identity: identity, version: 1);
    final data = ReadingExtentEstimates(snapshot);
    await data.refresh();
    expect(data.debugCountedLines, 20000);
    expect(data.debugStorageBytes, 80000);
    final firstContent = List<String>.of(content)..[7000] = 'א' * 1000;
    snapshot = _segments(
      firstContent,
      identity: identity,
      version: 2,
      changes: ContentLineChanges(
        fromVersion: 1,
        ranges: [(first: 7000, last: 7001)],
      ),
    );
    data.update(snapshot);
    final secondContent = List<String>.of(firstContent)..[7002] = 'א' * 2000;
    snapshot = _segments(
      secondContent,
      identity: identity,
      version: 3,
      changes: ContentLineChanges(
        fromVersion: 2,
        ranges: [(first: 7001, last: 7002)],
      ),
    );
    data.update(snapshot);
    final changed = await data.refresh();
    expect(changed.full, isFalse);
    expect(changed.ranges, [(first: 7000, last: 7002)]);
    expect(data.debugCountedLines, 20003);
    expect(data.debugStorageBytes, 80000);
    const metrics = ReadingExtentMetrics(lineExtent: 20, charWidth: 10);
    expect(data.estimate(7002, 100, metrics), 4004);
    expect(data.estimate(7000, 100, metrics), 2004);
    expect(snapshot.debugBuiltCount, 0);
  });

  test('טעינה תוך כדי ספירה ברקע אינה מאבדת דלתא', () async {
    final identity = Object();
    final original = _segments(
      List.filled(20000, 'אב'),
      identity: identity,
      version: 1,
    );
    final data = ReadingExtentEstimates(original);
    final refresh = data.refresh();
    final next = List<String>.of(original.content)..[18000] = 'א' * 3000;
    data.update(
      _segments(
        next,
        identity: identity,
        version: 2,
        changes: ContentLineChanges(
          fromVersion: 1,
          ranges: [(first: 18000, last: 18000)],
        ),
      ),
    );
    final result = await refresh;
    expect(result.full, isTrue);
    expect(data.debugCountedLines, 20001);
    expect(
      data.estimate(
        18000,
        100,
        const ReadingExtentMetrics(lineExtent: 20, charWidth: 10),
      ),
      6004,
    );
  });

  test('גרסה שדולגה וספר אחר מחייבים רענון מלא', () async {
    final identity = Object();
    final before = _segments(
      List.filled(20, 'אב'),
      identity: identity,
      version: 1,
    );
    final data = ReadingExtentEstimates(before);
    await data.refresh();
    final after = _segments(
      List.filled(20, 'אבגד'),
      identity: identity,
      version: 3,
      changes: ContentLineChanges(
        fromVersion: 2,
        ranges: [(first: 1, last: 1)],
      ),
    );
    expect(after.changedLinesSince(before), isNull);
    data.update(after);
    expect((await data.refresh()).full, isTrue);
    expect(data.debugCountedLines, 40);
    final other = _segments(
      ['', for (var i = 0; i < 19; i++) 'א' * 100],
      flags: [false, ...List.filled(19, true)],
      identity: Object(),
      version: 4,
      changes: ContentLineChanges(
        fromVersion: 3,
        ranges: [(first: 0, last: 0)],
      ),
    );
    expect(other.changedLinesSince(after), isNull);
    data.update(other);
    expect((await data.refresh()).full, isTrue);
    const metrics = ReadingExtentMetrics(lineExtent: 20, charWidth: 10);
    expect(data.estimate(0, 100, metrics), 204);
  });

  for (final textWidth in <double Function(double)?>[null, (w) => w / 2]) {
    testWidgets(
      'חימום מעדכן פריט רחוק בלי key חדש ובלי לבנותו${textWidth == null ? '' : ' (עם textWidth)'}',
      (tester) async {
        final identity = Object();
        final controller = ItemScrollController();
        final content = List<String>.filled(1000, '');
        content[0] = 'אבגד' * 30;
        var snapshot = _segments(
          content,
          flags: [true, ...List<bool>.filled(999, false)],
          identity: identity,
          version: 1,
        );
        late StateSetter rebuild;
        Object? latestKey;
        ItemExtentEstimator? latestEstimator;
        double? nativeWidth;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (_, setState) {
                rebuild = setState;
                return SizedBox(
                  width: 400,
                  height: 600,
                  child: ReadingExtentEstimation(
                    segments: snapshot,
                    controller: controller,
                    fontSize: 20,
                    textWidth: textWidth,
                    crossAxisPadding: 34,
                    builder: (estimator, key) {
                      latestKey = key;
                      latestEstimator = estimator;
                      return ScrollablePositionedList.builder(
                        itemCount: 1000,
                        itemScrollController: controller,
                        estimateExtent: (index, width) {
                          nativeWidth = width;
                          return estimator(index, width);
                        },
                        estimationKey: key,
                        padding: const EdgeInsets.symmetric(horizontal: 17),
                        itemBuilder: (_, index) =>
                            SizedBox(key: ValueKey(index), height: 100),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final key = latestKey;
        final before = controller.listController!.extentForIndex(500).$1;
        rebuild(() {
          final next = List<String>.of(content)..[500] = 'א' * 5000;
          final flags = List<bool>.of(snapshot.loadedLineFlags!)..[500] = true;
          snapshot = _segments(
            next,
            flags: flags,
            identity: identity,
            version: 2,
            changes: ContentLineChanges(
              fromVersion: 1,
              ranges: [(first: 500, last: 500)],
            ),
          );
        });
        await tester.pumpAndSettle();
        expect(latestKey, same(key));
        expect(
          controller.listController!.extentForIndex(500).$1,
          greaterThan(before * 10),
        );
        expect(
          controller.listController!.extentForIndex(500).$1,
          closeTo(latestEstimator!(500, nativeWidth!), 0.001),
        );
        expect(find.byKey(const ValueKey(500)), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'חימום בפריים האחרון של שינוי רוחב רציף ברשימה גדולה מוערך ברוחב החדש',
    (tester) async {
      const count = 5000;
      const target = 4000;
      const padding = EdgeInsets.symmetric(horizontal: 17);
      final identity = Object();
      final controller = ItemScrollController();
      final width = ValueNotifier(400.0);
      addTearDown(width.dispose);
      final content = List<String>.filled(count, '');
      var snapshot = _segments(
        content,
        flags: List<bool>.generate(count, (i) => i != target),
        identity: identity,
        version: 1,
      );
      late StateSetter rebuild;
      late ItemExtentEstimator latestEstimator;
      double? nativeWidth;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: ValueListenableBuilder(
                  valueListenable: width,
                  builder: (_, w, child) =>
                      SizedBox(width: w, height: 600, child: child),
                  child: ReadingExtentEstimation(
                    segments: snapshot,
                    controller: controller,
                    fontSize: 20,
                    crossAxisPadding: padding.horizontal,
                    builder: (estimator, key) {
                      latestEstimator = estimator;
                      return ScrollablePositionedList.builder(
                        itemCount: count,
                        itemScrollController: controller,
                        estimateExtent: (index, width) {
                          nativeWidth = width;
                          return estimator(index, width);
                        },
                        estimationKey: key,
                        padding: padding,
                        itemBuilder: (_, index) =>
                            SizedBox(key: ValueKey(index), height: 100),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var w = 380.0; w >= 200; w -= 20) {
        width.value = w;
        if (w == 200) {
          // הטעינה מגיעה בפריים האחרון, בזמן שהרשימה עוד דוחה את הרענון.
          rebuild(() {
            final next = List<String>.of(content)..[target] = 'א' * 3000;
            snapshot = _segments(
              next,
              flags: List<bool>.filled(count, true),
              identity: identity,
              version: 2,
              changes: ContentLineChanges(
                fromVersion: 1,
                ranges: [(first: target, last: target)],
              ),
            );
          });
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      final stats = controller.listController!.estimateRefreshStats!;
      expect(stats.deferredResizeCount, greaterThan(0));
      final newWidth = 200 - padding.horizontal;
      final oldWidth = 400 - padding.horizontal;
      expect(nativeWidth, newWidth);
      final expected = latestEstimator(target, newWidth);
      expect(expected, greaterThan(latestEstimator(target, oldWidth) * 1.5));
      expect(
        controller.listController!.extentForIndex(target).$1,
        closeTo(expected, 0.001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('רוחב הטקסט מחושב פעם אחת לכל רוחב ולא לכל פריט', (tester) async {
    final content = List<String>.generate(5000, (i) => 'אבגד' * (i % 40));
    var textWidthCalls = 0;
    var estimateCalls = 0;
    ItemExtentEstimator? latestEstimator;
    double? nativeWidth;
    final controller = ItemScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: ReadingExtentEstimation(
            segments: _segments(content),
            controller: controller,
            fontSize: 20,
            textWidth: (width) {
              textWidthCalls++;
              return width / 2;
            },
            builder: (estimator, key) {
              latestEstimator = estimator;
              return ScrollablePositionedList.builder(
                itemCount: content.length,
                itemScrollController: controller,
                estimateExtent: (index, width) {
                  estimateCalls++;
                  nativeWidth = width;
                  return estimator(index, width);
                },
                estimationKey: key,
                itemBuilder: (_, index) => const SizedBox(height: 100),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(estimateCalls, greaterThanOrEqualTo(content.length));
    expect(textWidthCalls, lessThanOrEqualTo(2));

    final settled = textWidthCalls;
    latestEstimator!(0, nativeWidth! - 50);
    expect(textWidthCalls, settled + 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('החלפת textWidth באותו רוחב מחליפה את ההערכה', (tester) async {
    final segments = _segments(['אבגד' * 100]);
    final controller = ItemScrollController();
    var half = false;
    var latestEstimate = 0.0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return ReadingExtentEstimation(
              segments: segments,
              controller: controller,
              fontSize: 20,
              textWidth: half ? (width) => width / 2 : (width) => width,
              builder: (estimate, key) {
                latestEstimate = estimate(0, 400);
                return const SizedBox();
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final full = latestEstimate;
    rebuild(() => half = true);
    await tester.pumpAndSettle();
    expect(latestEstimate, greaterThan(full * 1.5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('טאב מושבת דוחה ספירה וחוזר לרענון יחיד כשהוא פעיל', (
    tester,
  ) async {
    final segments = _segments(List.filled(100, 'א'));
    final keys = <Object>{};
    final controller = ItemScrollController();
    var enabled = false;
    var latestEstimate = 0.0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return TickerMode(
              enabled: enabled,
              child: ReadingExtentEstimation(
                segments: segments,
                controller: controller,
                fontSize: 20,
                builder: (estimate, key) {
                  keys.add(key);
                  latestEstimate = estimate(0, 100);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = latestEstimate;
    expect(keys, hasLength(1));
    rebuild(() => enabled = true);
    await tester.pumpAndSettle();
    expect(keys, hasLength(2));
    expect(latestEstimate, lessThan(before));
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(keys, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _GatedWorkerQueue extends ReadingExtentWorkerQueue {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  ReadingExtentWorkerJob<T> enqueue<T>(Future<T> Function() work) =>
      super.enqueue(() async {
        if (!started.isCompleted) {
          started.complete();
          await release.future;
        }
        return work();
      });
}

ReadingSegments _segments(
  List<String> content, {
  Object? identity,
  int version = 0,
  ContentLineChanges? changes,
  List<bool>? flags,
}) => ReadingSegments(
  layout: ReadingLayout.identity(content.length),
  content: content,
  loadedLineFlags: flags,
  readerIdentity: identity,
  contentVersion: version,
  contentChanges: changes,
);
