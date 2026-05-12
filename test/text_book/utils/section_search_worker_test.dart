import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';

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
      });

      final errorResponse = await harness.waitForMessage(requestId: 1);
      expect(errorResponse['type'], 'error');
      expect(errorResponse['requestId'], 1);

      harness.deliver({
        'type': 'search',
        'requestId': 2,
        'content': <String>['בראשית ברא אלוהים', 'את השמים ואת הארץ'],
        'query': 'בראשית',
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
      });

      final response = await harness.waitForMessage(requestId: 42);
      expect(response['type'], 'result');
      expect(response['requestId'], 42);
      final results = response['results'] as List;
      expect(results, hasLength(2));
    });
  });
}
