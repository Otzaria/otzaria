import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';

import 'literal_pattern_test_helper.dart';

/// עוטף את [SectionSearchWorkerRuntime] עם [ReceivePort] שאוסף את
/// ההודעות היוצאות, ומאפשר להזרים בקשות אל ה־runtime ישירות בלי isolate.
class _RuntimeHarness {
  _RuntimeHarness() {
    _port = ReceivePort();
    _runtime = SectionSearchWorkerRuntime(
      _port.sendPort,
      cleanLine: (rawLine) {
        cleanedRawLines.add(rawLine);
        return cleanLineForSearch(rawLine);
      },
    );
    _port.listen(messages.add);
  }

  late final ReceivePort _port;
  late final SectionSearchWorkerRuntime _runtime;
  final List<dynamic> messages = [];
  final List<String> cleanedRawLines = [];

  Future<Map<String, dynamic>> search({
    required int requestId,
    int? contentId,
    List<String>? content,
    String query = 'אור',
    ({int start, int? end})? range,
  }) {
    deliver({
      'type': 'search',
      'requestId': requestId,
      'contentId': contentId,
      'content': ?content,
      'query': query,
      'patternSource': literalPatternSource(query),
      'rangeStart': range?.start,
      'rangeEnd': range?.end,
    });
    return waitForMessage(requestId: requestId);
  }

  void deliver(Map<String, dynamic> message) => _runtime.onMessage(message);

  void dispose() => _port.close();

  Future<Map<String, dynamic>> waitForMessage({
    required int requestId,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final raw in messages) {
        if (raw is Map && raw['requestId'] == requestId) {
          return Map<String, dynamic>.from(raw);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('לא התקבלה הודעה עבור requestId=$requestId בתוך $timeout');
  }
}

void main() {
  group('SectionSearchWorkerRuntime', () {
    test('מנקה רק את הטווח ומרחיב את המטמון בלי ניקוי חוזר', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);
      const content = [
        '<h1>ספר</h1>',
        '<h2>פרק א</h2>',
        '<b>אוֹר</b> ברכה אור',
        'ברכה שנייה',
        '<h2>פרק ב</h2>',
        'אור נוסף',
      ];
      const clean = 'אור ברכה אור';
      final first = await harness.search(
        requestId: 1,
        contentId: 1,
        content: content,
        range: (start: 2, end: 4),
      );
      expect(first, {
        'type': 'result',
        'requestId': 1,
        'results': [
          {
            'index': 2,
            'snippet': clean,
            'address': ' פרק א ',
            'query': 'אור',
            'matchOffset': 0,
            'lineLength': clean.length,
          },
        ],
        'truncated': false,
      });
      expect(harness.cleanedRawLines, content.sublist(2, 4));

      final repeated = await harness.search(
        requestId: 2,
        contentId: 1,
        query: 'ברכה',
        range: (start: 2, end: 4),
      );
      expect(repeated['results'] as List, hasLength(2));
      expect(harness.cleanedRawLines, content.sublist(2, 4));

      final extended = await harness.search(
        requestId: 3,
        contentId: 1,
        range: (start: 4, end: null),
      );
      expect((extended['results'] as List).single['address'], ' פרק ב ');
      expect(harness.cleanedRawLines, content.sublist(2));

      final full = await harness.search(requestId: 4, contentId: 1);
      expect(full['results'] as List, hasLength(2));
      expect(harness.cleanedRawLines, unorderedEquals(content));
      await harness.search(requestId: 5, contentId: 1, query: 'ברכה');
      expect(harness.cleanedRawLines, unorderedEquals(content));
    });

    test('שורות ריקות והערות פנימיות נשמרות לאחר ניקוי', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);
      const content = [
        '<h2>פרק</h2>',
        '<b>  </b>',
        '<sup class="footnote-marker">א</sup>'
            '<i class="footnote">אור נסתר</i>',
        'אוֹר<sup class="footnote-marker">ב</sup>'
            '<i class="footnote">אור נסתר</i>טוב',
      ];
      final first = await harness.search(
        requestId: 1,
        contentId: 1,
        content: content,
        range: (start: 1, end: null),
      );
      expect(first['results'] as List, hasLength(1));
      expect((first['results'] as List).single['snippet'], 'אור טוב');
      final second = await harness.search(
        requestId: 2,
        contentId: 1,
        query: 'נסתר',
        range: (start: 1, end: null),
      );
      expect(second['results'], isEmpty);
      expect(harness.cleanedRawLines, content.sublist(1));
    });

    test('חיפוש חוצה שורות מנקה את השכנה רק בתוך הטווח', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);
      const content = ['<h2>פרק</h2>', 'לפני אור', 'טוב אחרי', 'מחוץ לטווח'];
      final bounded = await harness.search(
        requestId: 1,
        contentId: 1,
        content: content,
        query: 'אור טוב',
        range: (start: 1, end: 2),
      );
      expect(bounded['results'], isEmpty);
      expect(harness.cleanedRawLines, [content[1]]);

      final crossing = await harness.search(
        requestId: 2,
        contentId: 1,
        query: 'אור טוב',
        range: (start: 1, end: 3),
      );
      expect(crossing['results'], [
        {
          'index': 1,
          'snippet': 'לפני אור\nטוב אחרי',
          'address': ' פרק ',
          'query': 'אור טוב',
          'matchOffset': content[1].indexOf('אור'),
          'lineLength': content[1].length,
          'continuesToNextLine': true,
        },
      ]);
      expect(harness.cleanedRawLines, content.sublist(1, 3));
    });

    test('טווח ריק אינו מנקה ושינוי גבול הסיום נשאר תחום לספר', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);
      const content = ['אור ראשון', 'אור שני'];
      final empty = await harness.search(
        requestId: 1,
        contentId: 1,
        content: content,
        range: (start: 1, end: 1),
      );
      expect(empty['results'], isEmpty);
      expect(harness.cleanedRawLines, isEmpty);
      final beyondEnd = await harness.search(
        requestId: 2,
        contentId: 1,
        range: (start: 8, end: 10),
      );
      expect(beyondEnd['results'], isEmpty);
      expect(harness.cleanedRawLines, isEmpty);
      final clamped = await harness.search(
        requestId: 3,
        contentId: 1,
        range: (start: 1, end: 10),
      );
      expect((clamped['results'] as List).single['index'], 1);
      expect(harness.cleanedRawLines, [content[1]]);
    });

    test('החלפת תוכן מפנה גם מטמון שנוקה רק בחלקו', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);
      const firstBook = ['<h2>ראשון</h2>', 'אור ראשון', 'אור נוסף'];
      const secondBook = ['<h2>שני</h2>', 'אור שני', 'שורה אחרת'];
      for (final (requestId, contentId, content, address) in [
        (1, 1, firstBook, ' ראשון '),
        (2, 2, secondBook, ' שני '),
        (3, 1, firstBook, ' ראשון '),
        (4, null, secondBook, ' שני '),
        (5, null, firstBook, ' ראשון '),
      ]) {
        final response = await harness.search(
          requestId: requestId,
          contentId: contentId,
          content: content,
          range: (start: 1, end: 2),
        );
        expect((response['results'] as List).single['snippet'], content[1]);
        expect((response['results'] as List).single['address'], address);
        expect(harness.cleanedRawLines, hasLength(requestId));
      }
    });

    test('ביטול סריקה משאיר רק שורות שכבר נוקו לשאילתה הבאה', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);
      final content = List.generate(300, (i) => 'שורה $i אור');
      await harness.search(
        requestId: 1,
        contentId: 1,
        content: content,
        range: (start: 0, end: 0),
      );
      expect(harness.cleanedRawLines, isEmpty);

      final superseded = harness.search(requestId: 2, contentId: 1);
      final latest = harness.search(
        requestId: 3,
        contentId: 1,
        query: 'שורה',
        range: (start: 128, end: 130),
      );
      expect((await superseded)['type'], 'canceled');
      expect((await latest)['results'] as List, hasLength(2));
      expect(harness.cleanedRawLines, content.sublist(0, 130));

      await harness.search(requestId: 4, contentId: 1);
      expect(harness.cleanedRawLines, content);
    });

    test('תקרת התוצאות עוצרת גם את ניקוי השורות שנותרו', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);
      final content = List.generate(1100, (i) => 'אור $i');
      final response = await harness.search(
        requestId: 1,
        contentId: 1,
        content: content,
      );
      expect(response['results'] as List, hasLength(1000));
      expect(response['truncated'], isTrue);
      expect(harness.cleanedRawLines, content.sublist(0, 1001));
    });

    test('משדר error עם requestId כשבקשה נכשלת', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);

      // content הוא int במקום List — יגרום ל־TypeError בתוך לולאת העיבוד.
      harness.deliver({
        'type': 'search',
        'requestId': 7,
        'content': 123,
        'query': 'בראשית',
        'patternSource': literalPatternSource('בראשית'),
      });

      final response = await harness.waitForMessage(requestId: 7);

      expect(response['type'], 'error');
      expect(response['requestId'], 7);
      expect(response['message'], isNotNull);
    });

    test('בקשה תקינה לאחר בקשה שנכשלת עדיין מעובדת', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);

      harness.deliver({
        'type': 'search',
        'requestId': 1,
        'content': 'not-a-list',
        'query': 'אברהם',
        'patternSource': literalPatternSource('אברהם'),
      });

      final errorResponse = await harness.waitForMessage(requestId: 1);
      expect(errorResponse['type'], 'error');
      expect(errorResponse['requestId'], 1);

      harness.deliver({
        'type': 'search',
        'requestId': 2,
        'content': <String>['בראשית ברא אלוהים', 'את השמים ואת הארץ'],
        'query': 'בראשית',
        'patternSource': literalPatternSource('בראשית'),
      });

      final okResponse = await harness.waitForMessage(requestId: 2);
      expect(okResponse['type'], 'result');
      expect(okResponse['requestId'], 2);
      final results = okResponse['results'] as List;
      expect(results, hasLength(1));
      expect((results.first as Map)['index'], 0);
    });

    test('עיבוד תקין מחזיר result עם requestId תואם', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);

      harness.deliver({
        'type': 'search',
        'requestId': 42,
        'content': <String>['אברהם הלך', 'יצחק גר בארץ', 'אברהם חזר'],
        'query': 'אברהם',
        'patternSource': literalPatternSource('אברהם'),
      });

      final response = await harness.waitForMessage(requestId: 42);
      expect(response['type'], 'result');
      expect(response['requestId'], 42);
      final results = response['results'] as List;
      expect(results, hasLength(2));
    });

    test('משתמש ב-cache לפי contentId כשנשלחת בקשה ללא content', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);

      // בקשה ראשונה כוללת content + contentId — בונה cache.
      harness.deliver({
        'type': 'search',
        'requestId': 1,
        'contentId': 1,
        'content': <String>['אברהם הלך', 'יצחק גר בארץ'],
        'query': 'אברהם',
        'patternSource': literalPatternSource('אברהם'),
      });
      final first = await harness.waitForMessage(requestId: 1);
      expect(first['type'], 'result');
      expect(first['results'] as List, hasLength(1));

      // בקשה שנייה לאותו contentId ללא content — חייבת להשתמש ב-cache
      // ובכל זאת להחזיר תוצאה נכונה לשאילתה החדשה.
      harness.deliver({
        'type': 'search',
        'requestId': 2,
        'contentId': 1,
        'query': 'יצחק',
        'patternSource': literalPatternSource('יצחק'),
      });
      final second = await harness.waitForMessage(requestId: 2);
      expect(second['type'], 'result');
      final results = second['results'] as List;
      expect(results, hasLength(1));
      expect((results.first as Map)['index'], 1);
    });

    test('מחליף את ה-cache כשמגיע contentId חדש עם תוכן חדש', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);

      harness.deliver({
        'type': 'search',
        'requestId': 1,
        'contentId': 1,
        'content': <String>['<h2>פרק א</h2>', 'אברהם'],
        'query': 'אברהם',
        'patternSource': literalPatternSource('אברהם'),
      });
      expect((await harness.waitForMessage(requestId: 1))['type'], 'result');

      // תוכן חדש (contentId=2) שאין בו 'אברהם' — מאמת invalidation.
      harness.deliver({
        'type': 'search',
        'requestId': 2,
        'contentId': 2,
        'content': <String>['יצחק', '<h2>פרק ב</h2>', 'יעקב'],
        'query': 'אברהם',
        'patternSource': literalPatternSource('אברהם'),
      });
      final afterSwap = await harness.waitForMessage(requestId: 2);
      expect(afterSwap['type'], 'result');
      expect(
        afterSwap['results'] as List,
        isEmpty,
        reason: 'ה-cache הוחלף — אין לחפש עוד בתוכן הישן',
      );

      // אותו contentId חדש ללא content — מגיע מה-cache החדש.
      harness.deliver({
        'type': 'search',
        'requestId': 3,
        'contentId': 2,
        'query': 'יעקב',
        'patternSource': literalPatternSource('יעקב'),
      });
      final reuse = await harness.waitForMessage(requestId: 3);
      expect(reuse['type'], 'result');
      expect(reuse['results'] as List, hasLength(1));
      // גם הכותרות שבונות את כתובת התוצאה הוחלפו יחד עם התוכן.
      expect(
        (((reuse['results'] as List).single as Map)['address'] as String)
            .trim(),
        'פרק ב',
      );
    });

    test('contentId לא מוכר ללא content מחזיר error', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);

      harness.deliver({
        'type': 'search',
        'requestId': 1,
        'contentId': 9,
        'query': 'אברהם',
        'patternSource': literalPatternSource('אברהם'),
      });
      final response = await harness.waitForMessage(requestId: 1);
      expect(response['type'], 'error');
      expect(response['requestId'], 1);
    });

    test('בניית cache נפסקת כשמגיע תוכן אחר באמצע ועדיין מעבדת אותו', () async {
      final harness = _RuntimeHarness();
      addTearDown(harness.dispose);

      // תוכן גדול מגודל ה-chunk (128) כדי שתהיה נקודת yield באמצע הבנייה,
      // שבה ה-worker מזהה שהגיעה בקשה לתוכן אחר ומפסיק.
      final bigOld = List<String>.generate(400, (i) => 'שורה $i אברהם');
      final newContent = <String>['יצחק בלבד'];

      // שתי בקשות ברצף סינכרוני: בניית התוכן הישן עוצרת ב-await הראשון,
      // ואז הבקשה לתוכן החדש נכנסת לתור לפני שהבנייה הישנה מסתיימת.
      harness.deliver({
        'type': 'search',
        'requestId': 1,
        'contentId': 1,
        'content': bigOld,
        'query': 'אברהם',
        'patternSource': literalPatternSource('אברהם'),
      });
      harness.deliver({
        'type': 'search',
        'requestId': 2,
        'contentId': 2,
        'content': newContent,
        'query': 'יצחק',
        'patternSource': literalPatternSource('יצחק'),
      });

      // הבקשה החדשה מעובדת נכון על התוכן החדש.
      final second = await harness.waitForMessage(requestId: 2);
      expect(second['type'], 'result');
      final results = second['results'] as List;
      expect(results, hasLength(1));
      expect((results.first as Map)['index'], 0);

      // הבקשה הישנה בוטלה (בבנייה או בחיפוש) ולא הניבה תוצאות.
      final first = await harness.waitForMessage(requestId: 1);
      expect(first['type'], 'canceled');
    });
  });
}
