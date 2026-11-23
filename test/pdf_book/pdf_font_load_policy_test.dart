import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_load_coordinator.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_load_policy.dart';
import 'package:pdfrx/pdfrx.dart';

PdfFontQuery _query(
  String face, [
  PdfFontCharset charset = PdfFontCharset.ansi,
]) => PdfFontQuery(
  face: face,
  weight: 400,
  isItalic: false,
  charset: charset,
  pitchFamily: 1,
);

const _empty = PdfFontLoadResult(
  loaded: [],
  unresolved: [],
  failed: [],
  fontsReloaded: false,
);

void main() {
  late PdfrxEntryFunctions original;
  late _Backend backend;

  setUp(() {
    original = PdfrxEntryFunctions.instance;
    backend = _Backend();
    PdfrxEntryFunctions.instance = backend;
  });
  tearDown(() => PdfrxEntryFunctions.instance = original);

  PdfFontLoadPolicy policyFor(
    PdfFontManager hebrew, {
    PdfFontManager? platform,
  }) => PdfFontLoadPolicy(
    registerHebrew: (queries) =>
        hebrew.loadMissingFonts(queries, reloadFonts: false),
    registerPlatform: (queries) =>
        (platform ?? hebrew).loadMissingFonts(queries, reloadFonts: false),
    reload: backend.reloadFonts,
  );

  PdfFontLoadCoordinator coordinatorFor(PdfFontLoadPolicy policy) =>
      PdfFontLoadCoordinator(
        load: policy.loadMissingFonts,
        refreshPendingFonts: () async =>
            (await policy.loadMissingFonts(const [])).hasLoadedFonts,
      );

  for (final initial in ['empty', 'loaded', 'failed refresh']) {
    test('a finished $initial zone does not retain the font queue', () {
      late PdfFontLoadPolicy policy;
      var registrations = 0;
      var reloads = 0;
      var initialComplete = false;
      Object? initialFailure;
      final first = FakeAsync();
      first.run((_) {
        policy = PdfFontLoadPolicy(
          registerHebrew: (queries) async {
            registrations += queries.length;
            return PdfFontLoadResult(
              loaded: [
                for (final query in queries)
                  PdfLoadedFont(
                    query: query,
                    targetFace: query.face,
                    length: 8,
                  ),
              ],
              unresolved: const [],
              failed: const [],
              fontsReloaded: false,
            );
          },
          registerPlatform: (_) async => fail('Only ANSI queries are used'),
          reload: () async {
            reloads++;
            if (initial == 'failed refresh' && reloads == 1) {
              throw StateError('refresh failed');
            }
          },
        );
        policy
            .loadMissingFonts(initial == 'empty' ? const [] : [_query('First')])
            .then<void>(
              (_) => initialComplete = true,
              onError: (Object error, StackTrace stackTrace) {
                initialFailure = error;
                initialComplete = true;
              },
            );
      });
      first.flushMicrotasks();
      expect(initialComplete, isTrue);
      if (initial == 'failed refresh') {
        expect(initialFailure, isA<StateError>());
      } else {
        expect(initialFailure, isNull);
      }

      PdfFontLoadResult? result;
      final second = FakeAsync();
      second.run((_) {
        policy
            .loadMissingFonts([_query('Second')])
            .then((value) => result = value);
      });
      // הסביבה הראשונה הסתיימה; ממשיכים רק את תור האירועים של הבקשה החדשה.
      second.flushMicrotasks();
      expect(result, isNotNull);
      expect(
        result!.loaded.map((font) => font.query.face),
        initial == 'failed refresh' ? ['First', 'Second'] : ['Second'],
      );
      expect(result!.fontsReloaded, isTrue);
      expect(registrations, initial == 'empty' ? 1 : 2);
      expect(reloads, initial == 'empty' ? 1 : 2);
      expect(first.microtaskCount, 0);
    });
  }

  test(
    'ANSI, default and Hebrew keep the original fixed-pitch query',
    () async {
      final queries = [
        for (final charset in PdfFontCharset.values)
          _query('Missing ${charset.name}', charset),
      ];
      final hebrew = <PdfFontQuery>[];
      final platform = <PdfFontQuery>[];
      final policy = PdfFontLoadPolicy(
        registerHebrew: (queries) async {
          hebrew.addAll(queries);
          return _empty;
        },
        registerPlatform: (queries) async {
          platform.addAll(queries);
          return _empty;
        },
        reload: () async => fail('No new registration requires a refresh'),
      );
      await policy.loadMissingFonts(queries);
      const preferred = {
        PdfFontCharset.ansi,
        PdfFontCharset.default_,
        PdfFontCharset.hebrew,
      };
      expect(
        hebrew,
        queries.where((query) => preferred.contains(query.charset)),
      );
      expect(
        platform,
        queries.where((query) => !preferred.contains(query.charset)),
      );
      expect([...hebrew, ...platform].every((query) => query.isFixed), isTrue);
    },
  );

  test(
    'mixed scripts register sequentially and share one final refresh',
    () async {
      final firstReady = Completer<void>();
      final firstResolver = _Resolver(ready: firstReady);
      final secondResolver = _Resolver();
      final policy = policyFor(
        PdfFontManager(resolvers: [firstResolver]),
        platform: PdfFontManager(resolvers: [secondResolver]),
      );
      final first = _query('Hebrew');
      final second = _query('CJK', PdfFontCharset.shiftJis);
      final loading = policy.loadMissingFonts([first, second]);
      await _waitFor(() => firstResolver.loads == 1);
      expect(secondResolver.loads, 0);
      expect(backend.reloads, 0);
      firstReady.complete();
      final result = await loading;
      expect(result.loaded.map((font) => font.query), [first, second]);
      expect(result.fontsReloaded, isTrue);
      expect(backend.registrations, 2);
      expect(backend.reloads, 1);
    },
  );

  test('loaded fonts are not delivered before the shared refresh', () async {
    final ready = Completer<void>();
    backend.reloadReady = ready;
    final policy = policyFor(PdfFontManager(resolvers: [_Resolver()]));
    var delivered = false;
    final loading = policy.loadMissingFonts([_query('Wait')]).then((result) {
      delivered = true;
      return result;
    });
    await _waitFor(() => backend.reloads == 1);
    expect(delivered, isFalse);
    ready.complete();
    expect((await loading).hasLoadedFonts, isTrue);
  });

  test(
    'a second manager failure preserves the first successful registration',
    () async {
      final manager = PdfFontManager(resolvers: [_Resolver()]);
      final good = _query('Good');
      final bad = _query('Bad', PdfFontCharset.chineseBig5);
      final failure = StateError('platform preparation failed');
      final policy = PdfFontLoadPolicy(
        registerHebrew: (queries) =>
            manager.loadMissingFonts(queries, reloadFonts: false),
        registerPlatform: (_) => throw failure,
        reload: backend.reloadFonts,
      );
      final coordinator = coordinatorFor(policy);
      final opening = coordinator.beginOpening();
      expect(await coordinator.loadMissingFonts([good, bad]), isTrue);
      expect(
        await coordinator.completeOpening(opening, const []),
        isTrue,
      );
      expect(backend.registrations, 1);
      expect(backend.reloads, 1);
      final retried = await policy.loadMissingFonts([bad]);
      expect(retried.failed.single.query, same(bad));
      expect(retried.failed.single.error, same(failure));
      expect(retried.loaded, isEmpty);
      expect(backend.reloads, 1);
    },
  );

  test(
    'unresolved and per-query failures survive aggregation unchanged',
    () async {
      final missing = _query('Missing');
      final bad = _query('Bad', PdfFontCharset.arabic);
      final failure = PdfFontLoadFailure(
        query: bad,
        error: StateError('font file failed'),
        stackTrace: StackTrace.current,
      );
      final policy = PdfFontLoadPolicy(
        registerHebrew: (_) async => PdfFontLoadResult(
          loaded: const [],
          unresolved: [missing],
          failed: const [],
          fontsReloaded: false,
        ),
        registerPlatform: (_) async => PdfFontLoadResult(
          loaded: const [],
          unresolved: const [],
          failed: [failure],
          fontsReloaded: false,
        ),
        reload: backend.reloadFonts,
      );
      final result = await policy.loadMissingFonts([missing, bad]);
      expect(result.unresolved.single, same(missing));
      expect(result.failed.single, same(failure));
      expect(result.fontsReloaded, isFalse);
      expect(backend.reloads, 0);
    },
  );

  for (final emptyDiscovery in [false, true]) {
    test(
      'failed refresh retries registered faces (empty=$emptyDiscovery)',
      () async {
        backend.reloadFailures = 1;
        final resolver = _Resolver();
        final policy = policyFor(PdfFontManager(resolvers: [resolver]));
        final coordinator = coordinatorFor(policy);
        final font = _query('Retry');
        await expectLater(
          coordinator.loadMissingFonts([font]),
          throwsStateError,
        );
        expect(backend.registrations, 1);
        expect(backend.reloads, 1);
        if (emptyDiscovery) {
          expect(
            await coordinator.completeOpening(
              coordinator.beginOpening(),
              const [],
            ),
            isTrue,
          );
        } else {
          expect(await coordinator.loadMissingFonts([font]), isTrue);
        }
        expect(resolver.loads, 1);
        expect(backend.registrations, 1);
        expect(backend.reloads, 2);
        final empty = await policy.loadMissingFonts(const []);
        expect(empty.loaded, isEmpty);
        expect(empty.fontsReloaded, isFalse);
        expect(await coordinator.loadMissingFonts([font]), isFalse);
        expect(backend.reloads, 2);
      },
    );
  }

  test(
    'repeated refresh failure releases discovery and remains retryable',
    () async {
      backend.reloadFailures = 2;
      final policy = policyFor(PdfFontManager(resolvers: [_Resolver()]));
      final coordinator = coordinatorFor(policy);
      expect(
        await coordinator.completeOpening(
          coordinator.beginOpening(),
          [_query('Twice')],
        ),
        isFalse,
      );
      expect(backend.reloads, 2);
      expect(
        await coordinator.completeOpening(
          coordinator.beginOpening(),
          const [],
        ),
        isTrue,
      );
      expect(backend.registrations, 1);
      expect(backend.reloads, 3);
    },
  );

  test(
    'a new batch also refreshes registrations left by a failed batch',
    () async {
      backend.reloadFailures = 1;
      final policy = policyFor(PdfFontManager(resolvers: [_Resolver()]));
      final earlier = _query('Earlier');
      final later = _query('Later');
      await expectLater(policy.loadMissingFonts([earlier]), throwsStateError);
      final result = await policy.loadMissingFonts([later]);
      expect(result.loaded.map((font) => font.query), [earlier, later]);
      expect(backend.registrations, 2);
      expect(backend.reloads, 2);
      expect((await policy.loadMissingFonts(const [])).loaded, isEmpty);
      expect(backend.reloads, 2);
    },
  );

  test(
    'an empty flush does not join an unrelated active registration',
    () async {
      final ready = Completer<void>();
      backend.reloadReady = ready;
      final policy = policyFor(PdfFontManager(resolvers: [_Resolver()]));
      final later = policy.loadMissingFonts([_query('Later')]);
      await _waitFor(() => backend.reloads == 1);
      try {
        final empty = await policy
            .loadMissingFonts(const [])
            .timeout(const Duration(seconds: 1));
        expect(empty.loaded, isEmpty);
        expect(empty.fontsReloaded, isFalse);
        expect(ready.isCompleted, isFalse);
      } finally {
        ready.complete();
        await later;
      }
    },
  );

  test('failed refresh does not join a later stalled registration', () async {
    final firstRefresh = Completer<void>();
    final laterReady = Completer<void>();
    final laterResolver = _Resolver(ready: laterReady);
    final firstManager = PdfFontManager(resolvers: [_Resolver()]);
    final laterManager = PdfFontManager(resolvers: [laterResolver]);
    var reloads = 0;
    final policy = PdfFontLoadPolicy(
      registerHebrew: (queries) =>
          firstManager.loadMissingFonts(queries, reloadFonts: false),
      registerPlatform: (queries) =>
          laterManager.loadMissingFonts(queries, reloadFonts: false),
      reload: () async {
        if (++reloads == 1) await firstRefresh.future;
      },
    );
    final coordinator = coordinatorFor(policy);
    final opening = coordinator.beginOpening();
    final first = expectLater(
      coordinator.loadMissingFonts([_query('First')]),
      throwsStateError,
    );
    await _waitFor(() => reloads == 1);
    final completed = coordinator.completeOpening(opening, const []);
    await Future<void>.delayed(Duration.zero);
    final later = coordinator.loadMissingFonts([
      _query('Later', PdfFontCharset.shiftJis),
    ]);
    final laterOpening = coordinator.beginOpening();
    try {
      firstRefresh.completeError(StateError('first refresh failed'));
      await first;
      await _waitFor(() => laterResolver.loads == 1);
      expect(await completed.timeout(const Duration(seconds: 1)), isFalse);
      expect(laterReady.isCompleted, isFalse);
    } finally {
      laterReady.complete();
      expect(await later, isTrue);
    }
    expect(
      await coordinator.completeOpening(laterOpening, const []),
      isTrue,
    );
    expect(backend.registrations, 2);
    expect(reloads, 2);
    expect((await policy.loadMissingFonts(const [])).loaded, isEmpty);
  });

  test('all empty discoveries share an active recovery refresh', () async {
    backend.reloadFailures = 1;
    final policy = policyFor(PdfFontManager(resolvers: [_Resolver()]));
    final coordinator = coordinatorFor(policy);
    await expectLater(
      coordinator.loadMissingFonts([_query('Recovery')]),
      throwsStateError,
    );
    final ready = Completer<void>();
    backend.reloadReady = ready;
    final a = coordinator.beginOpening();
    final b = coordinator.beginOpening();
    var delivered = 0;
    final results = [
      for (final opening in [a, b])
        coordinator.completeOpening(opening, const []).then((changed) {
          delivered++;
          return changed;
        }),
    ];
    await _waitFor(() => backend.reloads == 2);
    expect(delivered, 0);
    ready.complete();
    expect(await Future.wait(results), [true, true]);
    expect(backend.registrations, 1);
    expect(backend.reloads, 2);
  });

  test('empty discovery does not prepare managers or refresh fonts', () async {
    final policy = PdfFontLoadPolicy(
      registerHebrew: (_) => throw StateError('unexpected Hebrew load'),
      registerPlatform: (_) => throw StateError('unexpected platform load'),
      reload: () async => fail('unexpected refresh'),
    );
    final result = await policy.loadMissingFonts(const []);
    expect(result.loaded, isEmpty);
    expect(result.unresolved, isEmpty);
    expect(result.failed, isEmpty);
    expect(result.fontsReloaded, isFalse);
  });
}

Future<void> _waitFor(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue);
}

class _Resolver implements PdfFontResolver {
  _Resolver({this.ready});

  final Completer<void>? ready;
  int loads = 0;

  @override
  PdfFontResolution resolve(
    PdfFontQuery query,
    PdfFontResolveContext context,
  ) => PdfFontResolution(
    loadData: ({onProgress}) async {
      loads++;
      await ready?.future;
      return Uint8List(8);
    },
  );
}

// המנהל אמיתי; הבדיקה מונה פעולות backend ונתוני גופן סינתטיים.
class _Backend implements PdfrxEntryFunctions {
  int registrations = 0;
  int reloads = 0;
  int reloadFailures = 0;
  Completer<void>? reloadReady;

  @override
  Future<void> configureFontEnvironment({
    String? fontCachePath,
    List<String> fontPaths = const [],
  }) async {}

  @override
  Future<void> addFontData({
    required String face,
    required Uint8List data,
    String? resolvedFace,
  }) async {
    registrations++;
  }

  @override
  Future<void> reloadFonts() async {
    reloads++;
    if (reloads <= reloadFailures) throw StateError('refresh failed');
    await reloadReady?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
