import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';

import 'literal_pattern_test_helper.dart';

/// עוטף את [SectionSearchWorkerRuntime] עם [ReceivePort] שאוסף את
/// ההודעות היוצאות, ומאפשר להזרים בקשות אל ה־runtime ישירות בלי isolate.
class _RuntimeHarness {
  _RuntimeHarness() {
    _port = ReceivePort();
    _runtime = SectionSearchWorkerRuntime(_port.sendPort);
    _port.listen(messages.add);
  }

  late final ReceivePort _port;
  late final SectionSearchWorkerRuntime _runtime;
  final List<dynamic> messages = [];

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
        'content': <String>['אברהם'],
        'query': 'אברהם',
        'patternSource': literalPatternSource('אברהם'),
      });
      expect((await harness.waitForMessage(requestId: 1))['type'], 'result');

      // תוכן חדש (contentId=2) שאין בו 'אברהם' — מאמת invalidation.
      harness.deliver({
        'type': 'search',
        'requestId': 2,
        'contentId': 2,
        'content': <String>['יצחק', 'יעקב'],
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
