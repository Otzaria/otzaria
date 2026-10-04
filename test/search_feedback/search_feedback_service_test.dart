import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_identity.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
import 'package:pinenacl/ed25519.dart' as ed;

import 'search_feedback_test_support.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.duration);

  final Duration duration;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

typedef _Handler = http.Response Function(http.Request request);

void main() {
  late Directory dir;
  late MemoryConsentPersistence consent;
  late List<http.Request> requests;
  late List<_FakeTimer> timers;
  late _Handler eventsHandler;
  late _Handler registerHandler;
  late DateTime now;
  late bool online;
  late bool buildAllowsSending;

  http.Response json(int status, Object body, {Map<String, String>? headers}) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json', ...?headers},
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sf_service');
    consent = MemoryConsentPersistence();
    requests = [];
    timers = [];
    now = kStart.add(const Duration(seconds: 5));
    online = true;
    buildAllowsSending = true;
    registerHandler = (request) {
      final body = jsonDecode(request.body) as Map;
      final keyId = SearchFeedbackIdentity.keyIdOf(
        base64.decode(body['publicKey'] as String),
      );
      return json(200, {'keyId': keyId, 'status': 'active'});
    };
    eventsHandler = (request) => json(200, {'accepted': 1, 'duplicates': 0});
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  SearchFeedbackService makeService() => SearchFeedbackService(
    client: MockClient((request) async {
      requests.add(request);
      return request.url.path.endsWith('/register')
          ? registerHandler(request)
          : eventsHandler(request);
    }),
    baseUrl: Uri.parse('https://example.test'),
    clock: () => now,
    storageDirectory: () async => dir,
    consentPersistence: consent,
    sendingAllowed: () => online,
    buildAllowsSending: buildAllowsSending,
    appVersion: () => '1.2.3+456',
    platform: () => 'windows',
    osVersion: () => '10.0.26200',
    locale: () => 'he',
    timerFactory: (duration, callback) {
      final timer = _FakeTimer(duration);
      timers.add(timer);
      return timer;
    },
  );

  Future<SearchFeedbackService> grantedService() async {
    final service = makeService();
    await service.grant();
    await service.flush();
    return service;
  }

  Future<void> recordOne(SearchFeedbackService service) async {
    service.recordSearch(searchContext());
    await service.settle();
  }

  List<http.Request> eventRequests() =>
      requests.where((r) => r.url.path.endsWith('/events')).toList();

  File keyFile() => File('${dir.path}/${SearchFeedbackIdentityStore.fileName}');

  bool hasQueueFiles() =>
      dir.existsSync() && dir.listSync().any((e) => e.path.endsWith('.jsonl'));

  group('consent', () {
    test('without consent nothing is queued or sent', () async {
      final service = makeService();
      expect(service.consent, SearchFeedbackConsent.unknown);
      expect(service.isCollecting, isFalse);
      await recordOne(service);
      service.recordOpen(
        searchContext(),
        result(),
        SearchFeedbackOpenVia.click,
      );
      await service.settle();
      await service.flush();
      expect(service.queue.isEmpty, isTrue);
      expect(hasQueueFiles(), isFalse);
      expect(requests, isEmpty);
    });

    test('a grant for an older consent version reads as unknown', () {
      consent
        ..state = 'granted'
        ..version = kSearchFeedbackConsentVersion - 1;
      expect(makeService().consent, SearchFeedbackConsent.unknown);
      consent.version = kSearchFeedbackConsentVersion;
      expect(makeService().consent, SearchFeedbackConsent.granted);
    });

    test('changes stream reports grant and revoke', () async {
      final service = makeService();
      final seen = <SearchFeedbackConsent>[];
      final sub = service.changes.listen(seen.add);
      await service.grant();
      await service.revoke();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [
        SearchFeedbackConsent.granted,
        SearchFeedbackConsent.declined,
      ]);
    });

    test('revoke deletes the queue files and the installation key', () async {
      final service = await grantedService();
      online = false;
      await recordOne(service);
      online = true;
      await service.flush();
      expect(keyFile().existsSync(), isTrue);
      online = false;
      await recordOne(service);
      expect(hasQueueFiles(), isTrue);

      await service.revoke();
      expect(service.consent, SearchFeedbackConsent.declined);
      expect(hasQueueFiles(), isFalse);
      expect(keyFile().existsSync(), isFalse);
      await recordOne(service);
      expect(service.queue.isEmpty, isTrue);
    });
  });

  group('recording', () {
    test('user-book open returns an id but queues nothing', () async {
      final service = await grantedService();
      final openId = service.recordOpen(
        searchContext(),
        result(isUserBook: true),
        SearchFeedbackOpenVia.click,
      );
      await service.settle();
      expect(openId, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(service.queue.isEmpty, isTrue);
    });

    test('recording schedules a debounced flush', () async {
      final service = await grantedService();
      await recordOne(service);
      expect(
        timers.where((t) => t.duration == service.flushDebounce && t.isActive),
        isNotEmpty,
      );
    });
  });

  group('sending', () {
    test('registers once, then posts a signed batch', () async {
      final service = await grantedService();
      await recordOne(service);
      service.recordResultsShown(searchContext(), 0, [result()]);
      await service.settle();
      await service.flush();

      expect(requests.first.url.path, '/api/search-feedback/register');
      final register = requests.first;
      expect(register.headers.containsKey('X-Otzaria-Key-Id'), isFalse);
      final registerBody = jsonDecode(register.body) as Map;
      expect(registerBody['createdAt'], '2026-10-02T10:00:05.000Z');
      expect(registerBody['platform'], 'windows');

      final events = eventRequests().single;
      expect(events.headers['Content-Type'], 'application/json; charset=utf-8');
      expect(events.headers['User-Agent'], 'otzaria-search-feedback/1.2.3+456');
      final publicKey = base64.decode(registerBody['publicKey'] as String);
      expect(
        events.headers['X-Otzaria-Key-Id'],
        SearchFeedbackIdentity.keyIdOf(publicKey),
      );
      final verified = ed.VerifyKey(Uint8List.fromList(publicKey)).verify(
        signature: ed.Signature(
          base64.decode(events.headers['X-Otzaria-Signature']!),
        ),
        message: events.bodyBytes,
      );
      expect(verified, isTrue);
      expect(events.bodyBytes.every((b) => b < 0x80), isTrue);

      final body = jsonDecode(events.body) as Map;
      expect(body['schema'], 1);
      expect(body['sentAt'], '2026-10-02T10:00:05.000Z');
      expect((body['events'] as List).map((e) => (e as Map)['type']), [
        'search',
        'results_shown',
      ]);
      final context = body['context'] as Map;
      expect(context['osVersion'], '10.0.26200');
      expect((context['engine'] as Map)['modelFamilyId'], 'family@abc');
      expect(jsonEncode(body), isNot(contains(dir.path.replaceAll(r'\', '/'))));
      expect(service.queue.isEmpty, isTrue);

      await recordOne(service);
      await service.flush();
      expect(
        requests.where((r) => r.url.path.endsWith('/register')),
        hasLength(1),
        reason: 'registered state is cached in the key file',
      );
    });

    test('offline mode keeps queueing and sends nothing', () async {
      final service = await grantedService();
      online = false;
      await recordOne(service);
      await service.flush();
      expect(requests, isEmpty);
      expect(service.queue.eventCount, 1);
      expect(timers.where((t) => t.isActive), isNotEmpty);

      online = true;
      await service.flush();
      expect(eventRequests(), hasLength(1));
      expect(service.queue.isEmpty, isTrue);
    });

    test('unknown_key re-registers and retries once', () async {
      final service = await grantedService();
      var calls = 0;
      eventsHandler = (request) => calls++ == 0
          ? json(401, {'error': 'unknown_key'})
          : json(200, {'accepted': 1, 'duplicates': 0});
      await recordOne(service);
      await service.flush();
      expect(
        requests.map((r) => r.url.path.split('/').last),
        ['register', 'events', 'register', 'events'],
      );
      expect(service.queue.isEmpty, isTrue);
    });

    test(
      'key_blocked purges, stops collecting, and survives restart',
      () async {
        final service = await grantedService();
        eventsHandler = (request) => json(403, {'error': 'key_blocked'});
        await recordOne(service);
        await service.flush();
        expect(service.isCollecting, isFalse);
        expect(hasQueueFiles(), isFalse);

        final restarted = makeService();
        await restarted.flush();
        expect(restarted.isCollecting, isFalse);
        await recordOne(restarted);
        expect(restarted.queue.isEmpty, isTrue);

        await restarted.grant();
        expect(
          restarted.isCollecting,
          isTrue,
          reason: 'regrant resets the key',
        );
      },
    );

    test('403 without a protocol error code does not block the key', () async {
      final service = await grantedService();
      eventsHandler = (request) => http.Response('<html>blocked</html>', 403);
      await recordOne(service);
      await service.flush();
      expect(service.isCollecting, isTrue);
      expect(service.queue.eventCount, 1);
    });

    test('rate_limited honors Retry-After', () async {
      final service = await grantedService();
      eventsHandler = (request) => json(
        429,
        {'error': 'rate_limited'},
        headers: {'retry-after': '120'},
      );
      await recordOne(service);
      await service.flush();
      expect(service.backoffUntil, now.add(const Duration(seconds: 120)));
      expect(timers.last.duration, const Duration(seconds: 120));

      final before = requests.length;
      await service.flush();
      expect(requests.length, before, reason: 'still backing off');
      now = now.add(const Duration(seconds: 121));
      eventsHandler = (request) => json(200, {'accepted': 1, 'duplicates': 0});
      await service.flush();
      expect(service.queue.isEmpty, isTrue);
    });

    test('shabbat 503 retries later and keeps the batch', () async {
      final service = await grantedService();
      eventsHandler = (request) => json(503, {'error': 'shabbat'});
      await recordOne(service);
      await service.flush();
      expect(service.queue.eventCount, 1);
      expect(service.backoffUntil, isNotNull);
    });

    test('5xx and network errors back off exponentially', () async {
      final service = await grantedService();
      eventsHandler = (request) => http.Response('oops', 502);
      await recordOne(service);
      await service.flush();
      final first = service.backoffUntil!.difference(now);
      now = service.backoffUntil!;
      eventsHandler = (request) => throw http.ClientException('socket');
      await service.flush();
      final second = service.backoffUntil!.difference(now);
      expect(second, first * 2);
      expect(service.queue.eventCount, 1);
    });

    for (final (status, code) in [
      (400, 'invalid_json'),
      (401, 'bad_signature'),
      (422, 'invalid_payload'),
    ]) {
      test('$code drops the batch', () async {
        final service = await grantedService();
        eventsHandler = (request) => json(status, {'error': code});
        await recordOne(service);
        await service.flush();
        expect(service.queue.isEmpty, isTrue);
        expect(service.backoffUntil, isNull);
      });
    }

    test('too_large splits the batch and sends the halves', () async {
      final service = await grantedService();
      var calls = 0;
      eventsHandler = (request) => calls++ == 0
          ? json(413, {'error': 'too_large'})
          : json(200, {'accepted': 1, 'duplicates': 0});
      online = false;
      for (var i = 0; i < 4; i++) {
        await recordOne(service);
      }
      online = true;
      await service.flush();
      expect(service.queue.eventCount, 4);
      await service.flush();
      expect(service.queue.isEmpty, isTrue);
      final sizes = eventRequests()
          .map((r) => ((jsonDecode(r.body) as Map)['events'] as List).length)
          .toList();
      expect(sizes, [4, 2, 2]);
    });

    test('a filter page answering repeatedly drops the batch', () async {
      final service = await grantedService();
      eventsHandler = (request) => http.Response('<html>418</html>', 418);
      await recordOne(service);
      for (var i = 0; i < SearchFeedbackService.maxUnrecognizedStrikes; i++) {
        now = service.backoffUntil ?? now;
        await service.flush();
      }
      expect(service.queue.isEmpty, isTrue);
    });
  });

  group('round 2', () {
    test('debug builds queue locally but never send', () async {
      buildAllowsSending = false;
      final service = await grantedService();
      await recordOne(service);
      await service.flush();
      expect(service.queue.eventCount, 1);
      expect(requests, isEmpty);
      expect(keyFile().existsSync(), isFalse, reason: 'no identity created');
    });

    test('debug gate and base URL override', () {
      expect(
        SearchFeedbackService.buildAllowsSendingFor(
          debugMode: true,
          sendInDebug: false,
        ),
        isFalse,
      );
      expect(
        SearchFeedbackService.buildAllowsSendingFor(
          debugMode: true,
          sendInDebug: true,
        ),
        isTrue,
      );
      expect(
        SearchFeedbackService.buildAllowsSendingFor(
          debugMode: false,
          sendInDebug: false,
        ),
        isTrue,
      );
      expect(
        SearchFeedbackService.resolveBaseUrl('http://localhost:8787'),
        Uri.parse('http://localhost:8787'),
      );
      expect(
        SearchFeedbackService.resolveBaseUrl(''),
        SearchFeedbackService.defaultBaseUrl,
      );
      expect(
        SearchFeedbackService.resolveBaseUrl('ftp://x'),
        SearchFeedbackService.defaultBaseUrl,
      );
    });

    test('200 with rejected events still deletes the batch', () async {
      final service = await grantedService();
      eventsHandler = (request) => json(200, {
        'accepted': 0,
        'duplicates': 0,
        'rejected': 1,
        'rejectedSamples': [
          {'index': 0, 'field': 'query'},
        ],
      });
      await recordOne(service);
      await service.flush();
      expect(service.queue.isEmpty, isTrue);
    });

    test('events older than 29 days are pruned before sending', () async {
      final service = await grantedService();
      online = false;
      service.recordSearch(searchContext(id: 'session_old_aaaa'));
      await service.settle();
      now = now.add(const Duration(days: 20));
      service.recordSearch(searchContext(id: 'session_new_bbbb'));
      await service.settle();
      now = now.add(const Duration(days: 10));
      online = true;
      await service.flush();
      final sent = eventRequests().single;
      final events = (jsonDecode(sent.body) as Map)['events'] as List;
      expect(events.map((e) => (e as Map)['searchSessionId']), [
        'session_new_bbbb',
      ]);
      expect(service.queue.isEmpty, isTrue);
    });

    test('a batch made only of stale events is removed unsent', () async {
      final service = await grantedService();
      online = false;
      await recordOne(service);
      now = now.add(const Duration(days: 30));
      online = true;
      await service.flush();
      expect(eventRequests(), isEmpty);
      expect(service.queue.isEmpty, isTrue);
    });

    Future<void> failRepeatedly(
      SearchFeedbackService service,
      int times,
      Duration spacing,
    ) async {
      for (var i = 0; i < times; i++) {
        now = (service.backoffUntil ?? now).add(spacing);
        await service.flush();
      }
    }

    test('repeated 5xx drops a batch only after 5 strikes and 24h', () async {
      final service = await grantedService();
      eventsHandler = (request) => http.Response('boom', 500);
      await recordOne(service);
      await failRepeatedly(service, 6, Duration.zero);
      expect(
        service.queue.eventCount,
        1,
        reason: 'many 5xx within a short time are kept',
      );
      await failRepeatedly(service, 1, const Duration(hours: 24));
      expect(service.queue.isEmpty, isTrue);
    });

    test('5xx strikes survive a restart', () async {
      final first = await grantedService();
      eventsHandler = (request) => json(500, {'error': 'internal'});
      await recordOne(first);
      await failRepeatedly(first, 4, Duration.zero);

      final restarted = makeService();
      now = now.add(const Duration(hours: 25));
      await restarted.flush();
      expect(restarted.queue.isEmpty, isTrue);
    });

    test('Shabbat/disabled 503 never drops a batch', () async {
      final service = await grantedService();
      eventsHandler = (request) => json(503, {'error': 'shabbat'});
      await recordOne(service);
      await failRepeatedly(service, 10, const Duration(hours: 12));
      eventsHandler = (request) => json(503, {'error': 'disabled'});
      await failRepeatedly(service, 10, const Duration(hours: 12));
      expect(service.queue.eventCount, 1);
    });
  });
}
