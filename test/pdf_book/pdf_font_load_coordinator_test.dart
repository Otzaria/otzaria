import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_load_coordinator.dart';
import 'package:pdfrx/pdfrx.dart';

PdfFontQuery query(
  String face, {
  int weight = 400,
  bool italic = false,
  PdfFontCharset charset = PdfFontCharset.hebrew,
  int pitchFamily = 0,
}) => PdfFontQuery(
  face: face,
  weight: weight,
  isItalic: italic,
  charset: charset,
  pitchFamily: pitchFamily,
);

PdfFontLoadResult loadedResult(Iterable<PdfFontQuery> queries) =>
    PdfFontLoadResult(
      loaded: [
        for (final font in queries)
          PdfLoadedFont(query: font, targetFace: font.face, length: 1),
      ],
      unresolved: const [],
      failed: const [],
      fontsReloaded: queries.isNotEmpty,
    );

Future<void> waitFor(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue);
}

void main() {
  test('empty requests do not prepare or load fonts', () async {
    final coordinator = PdfFontLoadCoordinator(
      load: (_) => throw StateError('No fonts were requested'),
    );
    expect(await coordinator.loadMissingFonts(const []), isFalse);
  });

  test(
    'duplicates and overlapping callers share only pending queries',
    () async {
      final calls = <List<PdfFontQuery>>[];
      final completions = <Completer<PdfFontLoadResult>>[];
      final coordinator = PdfFontLoadCoordinator(
        load: (fonts) {
          calls.add(fonts.toList());
          final completion = Completer<PdfFontLoadResult>();
          completions.add(completion);
          return completion.future;
        },
      );
      final first = coordinator.loadMissingFonts([
        query('A'),
        query('B'),
        query('A'),
      ]);
      final second = coordinator.loadMissingFonts([query('B'), query('C')]);
      final third = coordinator.loadMissingFonts([query('A')]);
      expect(calls.map((call) => call.map((font) => font.face).toList()), [
        ['A', 'B'],
        ['C'],
      ]);
      completions[1].complete(loadedResult(calls[1]));
      var secondFinished = false;
      unawaited(second.then((_) => secondFinished = true));
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);
      completions[0].complete(loadedResult(calls[0]));
      expect(await Future.wait([first, second, third]), [true, true, true]);
    },
  );

  test('a different font in a shared batch does not force a reopen', () async {
    final completion = Completer<PdfFontLoadResult>();
    final coordinator = PdfFontLoadCoordinator(load: (_) => completion.future);
    final first = coordinator.loadMissingFonts([query('A'), query('B')]);
    final second = coordinator.loadMissingFonts([query('B')]);
    completion.complete(loadedResult([query('A')]));
    expect(await first, isTrue);
    expect(await second, isFalse);
  });

  test('every query parameter participates in the pending identity', () async {
    final calls = <PdfFontQuery>[];
    final ready = Completer<void>();
    final coordinator = PdfFontLoadCoordinator(
      load: (fonts) async {
        calls.addAll(fonts);
        await ready.future;
        return loadedResult(fonts);
      },
    );
    final variants = [
      query('Shared'),
      query('Other'),
      query('Shared', weight: 700),
      query('Shared', italic: true),
      query('Shared', charset: PdfFontCharset.ansi),
      query('Shared', pitchFamily: 1),
    ];
    final results = [
      for (final font in variants) coordinator.loadMissingFonts([font]),
    ];
    expect(calls, variants);
    ready.complete();
    expect(await Future.wait(results), everyElement(isTrue));
  });

  test('completed results are not retained across font loads', () async {
    var calls = 0;
    final coordinator = PdfFontLoadCoordinator(
      load: (fonts) async {
        calls++;
        return loadedResult(fonts);
      },
    );
    expect(await coordinator.loadMissingFonts([query('A')]), isTrue);
    expect(await coordinator.loadMissingFonts([query('A')]), isTrue);
    expect(calls, 2);
  });

  test('unresolved and failed queries can be retried', () async {
    var calls = 0;
    final coordinator = PdfFontLoadCoordinator(
      load: (fonts) async {
        calls++;
        if (calls == 1) {
          return PdfFontLoadResult(
            loaded: const [],
            unresolved: [fonts.first],
            failed: [
              PdfFontLoadFailure(
                query: fonts.last,
                error: StateError('read failed'),
                stackTrace: StackTrace.current,
              ),
            ],
            fontsReloaded: false,
          );
        }
        return loadedResult(fonts);
      },
    );
    expect(
      await coordinator.loadMissingFonts([query('A'), query('B')]),
      isFalse,
    );
    expect(
      await coordinator.loadMissingFonts([query('A'), query('B')]),
      isTrue,
    );
    expect(calls, 2);
  });

  test(
    'a rejected batch reaches all callers and releases pending entries',
    () async {
      final failure = Completer<PdfFontLoadResult>();
      var calls = 0;
      final coordinator = PdfFontLoadCoordinator(
        load: (fonts) {
          calls++;
          return calls == 1
              ? failure.future
              : Future.value(loadedResult(fonts));
        },
      );
      final first = expectLater(
        coordinator.loadMissingFonts([query('A'), query('B')]),
        throwsStateError,
      );
      final second = expectLater(
        coordinator.loadMissingFonts([query('B')]),
        throwsStateError,
      );
      failure.completeError(StateError('refresh failed'));
      await Future.wait([first, second]);
      expect(await coordinator.loadMissingFonts([query('B')]), isTrue);
      expect(calls, 2);
    },
  );

  test('synchronous load failure does not poison a later request', () async {
    var calls = 0;
    final coordinator = PdfFontLoadCoordinator(
      load: (fonts) {
        if (++calls == 1) throw StateError('prepare failed');
        return Future.value(loadedResult(fonts));
      },
    );
    await expectLater(
      coordinator.loadMissingFonts([query('A')]),
      throwsStateError,
    );
    expect(await coordinator.loadMissingFonts([query('A')]), isTrue);
  });

  test(
    'invalid lazy input does not leave an incomplete pending font',
    () async {
      Iterable<PdfFontQuery> invalid() sync* {
        yield query('A');
        throw StateError('invalid input');
      }

      final coordinator = PdfFontLoadCoordinator(
        load: (fonts) async => loadedResult(fonts),
      );
      expect(() => coordinator.loadMissingFonts(invalid()), throwsStateError);
      expect(await coordinator.loadMissingFonts([query('A')]), isTrue);
    },
  );

  group('locked PdfFontManager work counts', () {
    late PdfrxEntryFunctions previousBackend;

    setUp(() => previousBackend = PdfrxEntryFunctions.instance);
    tearDown(() => PdfrxEntryFunctions.instance = previousBackend);

    for (final callers in [10, 100]) {
      test('$callers simultaneous documents load and register once', () async {
        Future<Map<String, Object>> run({required bool shared}) async {
          final backend = _Backend();
          PdfrxEntryFunctions.instance = backend;
          final resolver = _Resolver();
          final manager = PdfFontManager(resolvers: [resolver]);
          final coordinator = PdfFontLoadCoordinator(
            load: manager.loadMissingFonts,
          );
          final results = [
            for (var i = 0; i < callers; i++)
              shared
                  ? coordinator.loadMissingFonts([query('SharedHebrewFace')])
                  : manager
                        .loadMissingFonts([query('SharedHebrewFace')])
                        .then((result) => result.hasLoadedFonts),
          ];
          await waitFor(() => resolver.loads == (shared ? 1 : callers));
          resolver.ready.complete();
          expect(await Future.wait(results), everyElement(isTrue));
          return {
            'resolutions': resolver.resolutions,
            'loads': resolver.loads,
            'registrations': backend.registrations,
            'reloads': backend.reloads,
            'bytesRegistered': backend.bytesRegistered,
          };
        }

        final before = await run(shared: false);
        final after = await run(shared: true);
        for (final field in [
          'resolutions',
          'loads',
          'registrations',
          'reloads',
        ]) {
          expect(before[field], callers, reason: field);
          expect(after[field], 1, reason: field);
        }
        expect(before['bytesRegistered'], callers * _Resolver.payloadBytes);
        expect(after['bytesRegistered'], _Resolver.payloadBytes);
        // ignore: avoid_print
        print(
          'PDF_SHARED_FONT_LOADS ${jsonEncode({'callers': callers, 'evidence': 'operation counts; real manager, fake font bytes/backend', 'before': before, 'after': after})}',
        );
      });
    }

    test('all owners wait for backend refresh before reopening', () async {
      final reloadReady = Completer<void>();
      final backend = _Backend(reloadReady: reloadReady);
      PdfrxEntryFunctions.instance = backend;
      final resolver = _Resolver()..ready.complete();
      final manager = PdfFontManager(resolvers: [resolver]);
      final coordinator = PdfFontLoadCoordinator(
        load: manager.loadMissingFonts,
      );
      var reopened = 0;
      final results = [
        for (var i = 0; i < 10; i++)
          coordinator.loadMissingFonts([query('Shared')]).then((loaded) {
            if (loaded) reopened++;
            return loaded;
          }),
      ];
      await waitFor(() => backend.reloads == 1);
      expect(reopened, 0);
      reloadReady.complete();
      expect(await Future.wait(results), everyElement(isTrue));
      expect(reopened, 10);
    });

    test('a failed real-manager data load is retried', () async {
      final backend = _Backend();
      PdfrxEntryFunctions.instance = backend;
      final resolver = _Resolver(failFirstLoad: true)..ready.complete();
      final manager = PdfFontManager(resolvers: [resolver]);
      final coordinator = PdfFontLoadCoordinator(
        load: manager.loadMissingFonts,
      );
      expect(await coordinator.loadMissingFonts([query('Retry')]), isFalse);
      expect(backend.registrations, 0);
      expect(await coordinator.loadMissingFonts([query('Retry')]), isTrue);
      expect(resolver.loads, 2);
      expect(backend.registrations, 1);
      expect(backend.reloads, 1);
    });
  });
}

class _Resolver implements PdfFontResolver {
  _Resolver({this.failFirstLoad = false});

  static const payloadBytes = 1024 * 1024;
  final bool failFirstLoad;
  final ready = Completer<void>();
  int resolutions = 0;
  int loads = 0;

  @override
  PdfFontResolution resolve(PdfFontQuery query, PdfFontResolveContext context) {
    resolutions++;
    return PdfFontResolution(
      loadData: ({onProgress}) async {
        loads++;
        await ready.future;
        if (failFirstLoad && loads == 1) throw StateError('font data failed');
        return Uint8List(payloadBytes);
      },
    );
  }
}

class _Backend implements PdfrxEntryFunctions {
  _Backend({this.reloadReady});

  final Completer<void>? reloadReady;
  int registrations = 0;
  int bytesRegistered = 0;
  int reloads = 0;

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
    bytesRegistered += data.length;
  }

  @override
  Future<void> reloadFonts() async {
    reloads++;
    await reloadReady?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
