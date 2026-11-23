import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_page_highlights.dart';
import 'package:otzaria/pdf_book/utils/result_lines_highlight_pattern.dart';
import 'package:pdfrx/pdfrx.dart';

PdfPageText _text(int page, [String content = 'שלום עולם']) => PdfPageText(
  pageNumber: page,
  fullText: content,
  charRects: [
    for (var i = 0; i < content.length; i++)
      PdfRect(i * 10.0, 100, (i + 1) * 10.0, 90),
  ],
  fragments: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('רק עמוד נדרש נטען, ו-20 בקשות לאותו עמוד חולקות חילוץ', () async {
    final loaded = <int>[];
    final gate = Completer<PdfPageText?>();
    final cache = PdfPageHighlights(
      loadText: (page) {
        loaded.add(page);
        return gate.future;
      },
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    cache.setPattern(RegExp('שלום'));
    expect(loaded, isEmpty);
    final requests = List.generate(20, (_) => cache.ensurePage(9999));
    await pumpEventQueue();
    expect(loaded, [9999]);
    gate.complete(_text(9999));
    final matches = await Future.wait(requests);
    expect(matches.every((m) => identical(m, matches.first)), isTrue);
    expect(matches.first!.single.text, 'שלום');
    expect(identical(await cache.ensurePage(9999), matches.first), isTrue);
    expect(loaded, [9999]);
  });

  test('רק חילוץ אחד פעיל גם כשעמודים רבים ממתינים', () async {
    var active = 0;
    var peak = 0;
    final cache = PdfPageHighlights(
      loadText: (page) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(Duration.zero);
        active--;
        return _text(page);
      },
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    cache.setPattern('שלום');
    await Future.wait([
      for (var page = 1; page <= 20; page++) cache.ensurePage(page),
    ]);
    expect(peak, 1);
  });

  test('שאילתה חדשה משחררת ממתינים מיד ומשליכה תוצאה ישנה', () async {
    final gate = Completer<PdfPageText?>();
    var loads = 0;
    var notifications = 0;
    final cache = PdfPageHighlights(
      loadText: (page) =>
          ++loads == 1 ? gate.future : Future.value(_text(page)),
      onChanged: () => notifications++,
    );
    addTearDown(cache.dispose);
    cache.setPattern('שלום');
    final abandoned = cache.ensurePage(1);
    await pumpEventQueue();
    cache.setPattern('עולם');
    expect(await abandoned, isNull);
    final current = cache.ensurePage(1);
    gate.complete(_text(1));
    expect((await current)!.single.text, 'עולם');
    expect(notifications, 1);
    expect(loads, 2);
  });

  test('הסתרה מבטלת תור, ואינה מפרסמת תוצאה מאוחרת', () async {
    final gate = Completer<PdfPageText?>();
    final loaded = <int>[];
    var notifications = 0;
    final cache = PdfPageHighlights(
      loadText: (page) {
        loaded.add(page);
        return loaded.length == 1 ? gate.future : Future.value(_text(page));
      },
      onChanged: () => notifications++,
    );
    addTearDown(cache.dispose);
    cache.setPattern('שלום');
    final running = cache.ensurePage(1);
    final queued = cache.ensurePage(2);
    await pumpEventQueue();
    cache.setActive(false);
    expect(await running, isNull);
    expect(await queued, isNull);
    gate.complete(_text(1));
    await pumpEventQueue();
    expect(loaded, [1]);
    expect(notifications, 0);
    expect(await cache.ensurePage(3), isNull);
    cache.setActive(true);
    expect((await cache.ensurePage(2))!.single.pageNumber, 2);
    expect(loaded, [1, 2]);
  });

  test('dispose מסיים המתנות בלי לחכות לחילוץ שאינו ניתן לביטול', () async {
    final gate = Completer<PdfPageText?>();
    var notifications = 0;
    final cache = PdfPageHighlights(
      loadText: (_) => gate.future,
      onChanged: () => notifications++,
    );
    cache.setPattern('שלום');
    final request = cache.ensurePage(1);
    await pumpEventQueue();
    cache.dispose();
    expect(await request, isNull);
    gate.complete(_text(1));
    await pumpEventQueue();
    expect(cache.cachedPageCount, 0);
    expect(notifications, 0);
  });

  test('מטמון ההיסטוריה מוגבל, אך עמודים נראים אינם מפנים זה את זה', () async {
    var loads = 0;
    final cache = PdfPageHighlights(
      loadText: (page) async {
        loads++;
        return _text(page);
      },
      onChanged: () {},
      maxCachedPages: 3,
    );
    addTearDown(cache.dispose);
    cache.setPattern('שלום');
    for (var page = 1; page <= 20; page++) {
      await cache.ensurePage(page, forNavigation: true);
    }
    expect(cache.cachedPageCount, 3);
    cache.setVisiblePages({1, 2, 3, 4, 5});
    for (var page = 1; page <= 5; page++) {
      await cache.ensurePage(page, forNavigation: true);
    }
    final before = loads;
    for (var page = 1; page <= 5; page++) {
      expect(await cache.ensurePage(page), isNotNull);
    }
    expect(loads, before);
    expect(cache.cachedPageCount, 5);
    cache.setVisiblePages({5});
    expect(cache.cachedPageCount, 3);
    cache.clear();
    expect(cache.cachedPageCount, 0);
  });

  test('עמוד שנעלם מהתצוגה אינו מתחיל חילוץ אחרי שינוי תצוגה', () async {
    final loaded = <int>[];
    final cache = PdfPageHighlights(
      loadText: (page) async {
        loaded.add(page);
        return _text(page);
      },
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    cache.setPattern('שלום');
    final obsolete = cache.ensurePage(1);
    final visible = cache.ensurePage(100);
    cache.setVisiblePages({100});
    expect(await obsolete, isNull);
    expect((await visible)!.single.pageNumber, 100);
    expect(loaded, [100]);
  });

  test('כשל חילוץ אינו יוצר לולאת paint וניווט מפורש יכול לנסות שוב', () async {
    var loads = 0;
    final cache = PdfPageHighlights(
      loadText: (page) async {
        if (++loads == 1) throw StateError('injected failure');
        return _text(page);
      },
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    cache.setPattern('שלום');
    cache.setVisiblePages({1});
    expect(await cache.ensurePage(1), isNull);
    expect(cache.error, isA<StateError>());
    for (var i = 0; i < 20; i++) {
      expect(await cache.ensurePage(1), isNull);
    }
    expect(loads, 1);
    expect(await cache.ensurePage(1, forNavigation: true), isNotEmpty);
    expect(loads, 2);
  });

  test('Pattern מותאם שומר משמעות של שורות, סדר וגבולות גיאומטריים', () async {
    final pattern = ResultLinesHighlightPattern.build(
      ['שלום', 'עולם'],
      [
        {0, 1},
      ],
    )!;
    const content = 'שלום לבד\nשלום עולם\nעולם לבד';
    final cache = PdfPageHighlights(
      loadText: (page) async => _text(page, content),
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    cache.setPattern(pattern);
    final matches = (await cache.ensurePage(5))!;
    expect(matches.map((m) => m.text), ['שלום', 'עולם']);
    expect(matches.map((m) => m.start), [9, 14]);
    expect(
      matches.every((m) => m.pageNumber == 5 && m.rects.isNotEmpty),
      isTrue,
    );
  });
}
