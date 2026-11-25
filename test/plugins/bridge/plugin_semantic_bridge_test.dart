import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/bridge/plugin_semantic_bridge.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

import '../../semantic_search/semantic_test_support.dart';

final _berakhot = TextBook(id: 7, title: 'ברכות');
final _byPath = {BookIdentity.indexedFilePath(_berakhot): _berakhot};

engine.SemanticNearestHit _hit(int segment) => engine.SemanticNearestHit(
  filePath: BookIdentity.indexedFilePath(_berakhot),
  id: BigInt.from(segment),
  title: 'ברכות',
  reference: 'ברכות ב.',
  segment: BigInt.from(segment),
  isPdf: false,
  matchedWindow: 0,
  score: 0.5,
  point: 0,
  pointScores: Float32List(0),
);

String _streamId(int id) => 'semantic_0123456789abcdef0123456789abcdef_$id';

Matcher _rpcError(String code) => throwsA(
  predicate((Object? error) => '$error'.contains(code), 'error with $code'),
);

void main() {
  late Directory root;
  late FakeBackend backend;
  late FakeConsentStore consent;
  late SemanticSearchRepository repository;
  late int indexGeneration;
  late bool catalogIsCurrent;
  late Set<void Function()> revocationListeners;
  late List<Map<String, dynamic>> events;

  PluginSemanticBridge bridge({Future<void>? bookGate}) => PluginSemanticBridge(
    books: (checkActive) async {
      await bookGate;
      checkActive();
      return (
        find: (Map<String, dynamic> _) => _berakhot,
        byIndexedPath: _byPath,
        officialPaths: _byPath.keys.toList(),
        isCurrent: () => catalogIsCurrent,
      );
    },
    onPermissionRevoked: (cancel) {
      revocationListeners.add(cancel);
      return () => revocationListeners.remove(cancel);
    },
    repository: () => repository,
  );

  Future<void> sink(String topic, Map<String, dynamic> payload) async {
    expect(topic, PluginSemanticBridge.streamEvent);
    events.add(payload);
  }

  Future<dynamic> nearest(
    PluginSemanticBridge bridge,
    String streamId, [
    Future<void> Function(String, Map<String, dynamic>)? deliver,
  ]) => bridge.handle('nearest', {
    '__streamId': streamId,
    'from': [
      {'text': 'אמר רבא'},
    ],
  }, eventSink: deliver ?? sink);

  List<String?> chunkTypes(String streamId) => [
    for (final event in events)
      if (event['streamId'] == streamId)
        (event['chunk'] as Map)['type'] as String?,
  ];

  setUp(() async {
    root = Directory.systemTemp.createTempSync('plugin_semantic_');
    installModelFiles(root);
    backend = FakeBackend()..vectors = installedV30;
    consent = FakeConsentStore();
    indexGeneration = 0;
    catalogIsCurrent = true;
    revocationListeners = {};
    repository = buildRepository(
      root: root,
      backend: backend,
      consent: consent,
      indexStamp: () async => '$indexGeneration',
    );
    events = [];
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('getStatus: ready, עם הדור והגבולות', () async {
    final status =
        await bridge().handle('getStatus', const {}, eventSink: null) as Map;
    expect(status['phase'], 'ready');
    expect(status['vectorsLibraryVersion'], 30);
    expect(status['generation'], 0);
    expect((status['limits'] as Map)['maxPoints'], 64);
  });

  test('בלי הסכמה רק getStatus עונה', () async {
    consent.set(SearchFeedbackConsent.declined);
    await pumpEventQueue();
    final plugin = bridge();

    final status =
        await plugin.handle('getStatus', const {}, eventSink: null) as Map;
    expect(status['phase'], 'consentRequired');
    await expectLater(
      nearest(plugin, _streamId(1)),
      _rpcError('error.unavailable'),
    );
    await expectLater(
      plugin.handle('countTokens', {
        'texts': ['א'],
      }, eventSink: null),
      _rpcError('error.unavailable'),
    );
    expect(backend.nearestInputs, isEmpty);
  });

  test('nearest מזרים progress, השורות ו-done', () async {
    backend.nearestResponse = emptyNearestResponse(hits: [_hit(3)]);

    final result = await nearest(bridge(), _streamId(1)) as Map;

    expect(result['completed'], isTrue);
    expect(chunkTypes(_streamId(1)), ['progress', 'hits', 'done']);
    final hits = (events[1]['chunk'] as Map)['hits'] as List;
    expect((hits.single as Map)['index'], 3);
    expect((hits.single as Map)['id'], 7);
    expect(backend.nearestInputs.single.facets, ['/']);
    expect(backend.nearestInputs.single.bookPaths, ['id:7']);
  });

  test('nearest חדש של אותו מופע מחליף את הקודם', () async {
    backend.searchGate = Completer<void>();
    final plugin = bridge();
    final first = nearest(plugin, _streamId(1));
    await pumpEventQueue();
    final second = nearest(plugin, _streamId(2));
    await pumpEventQueue();
    backend.searchGate!.complete();

    expect(await first, containsPair('cancelled', true));
    expect(await second, containsPair('completed', true));
    expect(chunkTypes(_streamId(1)), isNot(contains('done')));
  });

  test('מופע אחר, גם של אותו תוסף, אינו מחליף את הסריקה', () async {
    backend.searchGate = Completer<void>();
    final first = nearest(bridge(), _streamId(1));
    await pumpEventQueue();
    final second = nearest(bridge(), _streamId(2));
    await pumpEventQueue();
    backend.searchGate!.complete();

    expect(await first, containsPair('completed', true));
    expect(await second, containsPair('completed', true));
  });

  test('חיפוש של המשתמש מסיים את הסריקה ב-error.preempted', () async {
    backend.searchGate = Completer<void>();
    final scan = expectLater(
      nearest(bridge(), _streamId(1)),
      _rpcError('error.preempted'),
    );
    await pumpEventQueue();
    final search = repository.search(
      const SemanticSearchRequest(query: 'חסד', facets: ['/']),
    );
    await pumpEventQueue();
    backend.searchGate!.complete();

    await scan;
    expect(await search, isNotNull);
  });

  test('ביטול הזרם ו-release מבטלים את הסריקה במנוע', () async {
    backend.searchGate = Completer<void>();
    final plugin = bridge();
    final cancelled = nearest(plugin, _streamId(1));
    await pumpEventQueue();
    expect(
      plugin.handle('nearest', {
        '__cancelStreamId': _streamId(1),
      }, eventSink: sink),
      completion({'cancelled': true}),
    );
    await pumpEventQueue();
    final released = nearest(plugin, _streamId(2));
    await pumpEventQueue();
    plugin.release();
    backend.searchGate!.complete();

    expect(await cancelled, containsPair('cancelled', true));
    expect(await released, containsPair('cancelled', true));
    expect(backend.nearestHandles.every((h) => h.isCancelled), isTrue);
  });

  test('ביטול שמגיע לפני הזרם עוצר אותו כשהוא מתחיל', () async {
    final plugin = bridge();
    expect(
      await plugin.handle('nearest', {
        '__cancelStreamId': _streamId(1),
      }, eventSink: sink),
      {'cancelled': false},
    );
    expect(
      await nearest(plugin, _streamId(1)),
      containsPair('cancelled', true),
    );
    expect(backend.nearestInputs, isEmpty);
  });

  test('קלט שהמנוע דוחה חוזר כ-invalid_params', () async {
    backend.nearestFailure = const SemanticFailure(
      SemanticFailureKind.invalidInput,
      'vector width 3, set width 256',
    );
    await expectLater(
      nearest(bridge(), _streamId(1)),
      _rpcError('error.invalid_params'),
    );
  });

  test('קידוד קטע דורש רכיב מותקן ומותיר את ההורדה בידי האפליקציה', () async {
    final downloads = FakeDownloads();
    repository = buildRepository(
      root: root,
      backend: backend,
      consent: consent,
      download: downloads.call,
      modelReleases: kSemanticModelReleases,
    );
    final status =
        await bridge().handle('getStatus', const {}, eventSink: null) as Map;
    expect(status['phase'], 'ready');
    await expectLater(
      bridge().handle('nearest', {
        '__streamId': _streamId(1),
        'from': [
          {'text': 'א', 'as': 'passage'},
        ],
      }, eventSink: sink),
      _rpcError('error.unavailable'),
    );
    expect(downloads.urls, isEmpty);
    expect(backend.nearestInputs, isEmpty);
  });

  test('countTokens', () async {
    final counts =
        await bridge().handle('countTokens', {
              'texts': ['אב', 'אבגד'],
            }, eventSink: null)
            as Map;
    expect(counts['counts'], [4, 6]);
    expect(counts['queryMaxTokens'], 256);
    expect(counts['overheadTokens'], 2);
  });

  test('getCoveredBooks נשמר במטמון עד שהאינדקס משתנה', () async {
    backend.coveredBooksValue = SemanticCoveredBooksSummary(
      filePaths: [BookIdentity.indexedFilePath(_berakhot)],
      setKey: 'set',
    );
    final plugin = bridge();

    final first =
        await plugin.handle(
              'getCoveredBooks',
              const {},
              eventSink: null,
            )
            as Map;
    await plugin.handle('getCoveredBooks', const {}, eventSink: null);
    expect(backend.calls.where((call) => call == 'coveredBooks'), hasLength(1));
    expect((first['books'] as List).single['bookId'], 'ברכות');

    indexGeneration++;
    backend.coveredBooksValue = const SemanticCoveredBooksSummary(
      filePaths: [],
      setKey: 'set',
    );
    final second =
        await plugin.handle('getCoveredBooks', const {}, eventSink: null)
            as Map;
    expect(second['books'], isEmpty);
    expect(backend.calls.where((call) => call == 'coveredBooks'), hasLength(2));
  });

  test('סגירת דף עוצרת לפני שהספרייה נטענת', () async {
    final library = Completer<void>();
    final plugin = bridge(bookGate: library.future);
    final scan = nearest(plugin, _streamId(1));
    await pumpEventQueue();
    plugin.release();
    expect(await scan, containsPair('cancelled', true));
    library.complete();
    await pumpEventQueue();
    expect(backend.nearestInputs, isEmpty);
    expect(events, isEmpty);
  });

  test('חיפוש שכבר פעיל דוחה בקשה לפני טעינת הספרייה', () async {
    await repository.ensureOpen();
    await pumpEventQueue();
    backend.searchGate = Completer<void>();
    final search = repository.search(
      const SemanticSearchRequest(query: 'חסד', facets: ['/']),
    );
    await expectLater(
      nearest(bridge(), _streamId(1)),
      _rpcError('error.preempted'),
    );
    expect(backend.nearestInputs, isEmpty);
    backend.searchGate!.complete();
    await search;
  });

  for (final permission in [true, false]) {
    test(
      'ביטול ${permission ? 'הרשאה' : 'הסכמה'} בזמן שידור עוצר את הזרם',
      () async {
        backend.nearestResponse = emptyNearestResponse(hits: [_hit(3)]);
        final sent = Completer<void>();
        final releaseSink = Completer<void>();
        final scan = expectLater(
          nearest(bridge(), _streamId(1), (topic, payload) async {
            await sink(topic, payload);
            if ((payload['chunk'] as Map)['type'] == 'hits') {
              sent.complete();
              await releaseSink.future;
            }
          }),
          _rpcError(
            permission ? 'error.permission_denied' : 'error.unavailable',
          ),
        );
        await sent.future;
        if (permission) {
          for (final cancel in revocationListeners.toList()) {
            cancel();
          }
        } else {
          consent.set(SearchFeedbackConsent.declined);
        }
        await scan;
        releaseSink.complete();
        await pumpEventQueue();
        expect(chunkTypes(_streamId(1)), ['progress', 'hits']);
        expect(revocationListeners, isEmpty);
      },
    );
  }

  test('קטלוג שהוחלף בזמן הסריקה מבטל משלוח תוצאות', () async {
    await repository.ensureOpen();
    await pumpEventQueue();
    backend.searchGate = Completer<void>();
    final scan = expectLater(
      nearest(bridge(), _streamId(1)),
      _rpcError('error.unavailable'),
    );
    await pumpEventQueue();
    expect(backend.nearestInputs, hasLength(1));
    catalogIsCurrent = false;
    backend.searchGate!.complete();
    await scan;
    expect(chunkTypes(_streamId(1)), ['progress']);
  });

  test('חסם הזמן חל גם כשספרייה עדיין נטענת', () async {
    final previous = PluginSemanticBridge.maxDuration;
    PluginSemanticBridge.maxDuration = const Duration(milliseconds: 15);
    addTearDown(() => PluginSemanticBridge.maxDuration = previous);
    final library = Completer<void>();
    await expectLater(
      nearest(bridge(bookGate: library.future), _streamId(1)),
      throwsA(isA<TimeoutException>()),
    );
    library.complete();
    await pumpEventQueue();
    expect(backend.nearestInputs, isEmpty);
  });

  test('פעולה לא מוכרת', () async {
    await expectLater(
      bridge().handle('embed', const {}, eventSink: null),
      _rpcError('error.unknown_method'),
    );
  });
}
