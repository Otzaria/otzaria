import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/perf_probe/prepare_pdf_case.dart';
import '../../../tool/perf_probe/src/pdf_reader_case.dart';
import '../../../tool/perf_probe/src/report.dart';
import 'report_test.dart' show phase, report;

Map<String, Object?> generated({
  Object? pages = 600,
  Map<String, Object?>? navigation,
}) => {
  'schemaVersion': 1,
  'source': {'kind': 'generated', 'pageCount': pages},
  'navigation': ?navigation,
};

PerfPdfCase parse(Object? value) =>
    PerfPdfCase.fromJson(value, baseDirectory: Directory.systemTemp.path);

void main() {
  test('default preserves the 600-page regular-reader workload', () async {
    final defaults = await PerfPdfCase.load('');
    expect(defaults.pageCount, 600);
    expect(defaults.mixedPageSizes, isTrue);
    expect(defaults.navigationTargets.toJson(), {
      'initialPage': 1,
      'forwardPage': 450,
      'backwardPage': 60,
      'zoomFactor': 2.0,
    });
    expect(defaults.navigationTargets.zoomPage, 60);
    expect(parse(generated()).toComparisonJson(), defaults.toComparisonJson());
    expect(parse(defaults.toJson()).toJson(), defaults.toJson());
  });

  for (final entry in {
    1: (1, 1),
    10: (7, 1),
    100: (75, 10),
    1000: (750, 100),
    10000: (7500, 1000),
  }.entries) {
    test('${entry.key} pages derive in-range targets', () {
      final pdfCase = parse(generated(pages: entry.key));
      final targets = pdfCase.navigationTargets;
      expect(targets.forwardPage, entry.value.$1);
      expect(targets.backwardPage, entry.value.$2);
      expect(targets.zoomPage, targets.backwardPage);
      for (final page in [
        targets.initialPage,
        targets.forwardPage,
        targets.backwardPage,
      ]) {
        expect(page, inInclusiveRange(1, pdfCase.pageCount));
      }
    });
  }

  test('explicit navigation and a late initial page are preserved', () {
    final pdfCase = parse(
      generated(
        pages: 10,
        navigation: {
          'initialPage': 8,
          'forwardPage': 10,
          'backwardPage': 3,
          'zoomFactor': 1.5,
        },
      ),
    );
    expect(pdfCase.navigationTargets.toJson(), {
      'initialPage': 8,
      'forwardPage': 10,
      'backwardPage': 3,
      'zoomFactor': 1.5,
    });
    expect(
      parse(
        generated(pages: 10, navigation: {'initialPage': 9}),
      ).navigationTargets.forwardPage,
      9,
    );
    expect(
      parse(
        generated(navigation: {'forwardPage': 2}),
      ).navigationTargets.backwardPage,
      2,
    );
  });

  for (final value in [null, false, '10', 10.0, 0, -1, 10001]) {
    test('invalid pageCount $value (${value.runtimeType}) is rejected', () {
      expect(() => parse(generated(pages: value)), throwsFormatException);
    });
  }
  for (final value in [
    null,
    false,
    '2',
    0,
    1,
    -2,
    16.1,
    double.nan,
    double.infinity,
  ]) {
    test('invalid zoomFactor $value (${value.runtimeType}) is rejected', () {
      expect(
        () => parse(generated(navigation: {'zoomFactor': value})),
        throwsFormatException,
      );
    });
  }
  for (final key in ['initialPage', 'forwardPage', 'backwardPage']) {
    for (final value in [null, true, '2', 2.0, 0, 11]) {
      test('invalid $key $value (${value.runtimeType}) is rejected', () {
        expect(
          () => parse(generated(pages: 10, navigation: {key: value})),
          throwsFormatException,
        );
      });
    }
  }
  test('misnamed directions and unknown configuration fields are rejected', () {
    for (final value in [
      {...generated(), 'schemaVersion': 1.0},
      {...generated(), 'schemaVersion': 2},
      {...generated(), 'extra': true},
      {...generated(), 'navigation': null},
      generated(navigation: {'zoom': 2}),
      generated(navigation: {'initialPage': 50, 'forwardPage': 20}),
      generated(navigation: {'forwardPage': 20, 'backwardPage': 30}),
      {
        'schemaVersion': 1,
        'source': {
          'kind': 'generated',
          'pageCount': 10,
          'mixedPageSizes': 'true',
        },
      },
      {
        'schemaVersion': 1,
        'source': {'kind': 'generated', 'pageCount': 10, 'path': 'ignored.pdf'},
      },
      {
        'schemaVersion': 1,
        'source': {'kind': 'unknown', 'pageCount': 10},
      },
    ]) {
      expect(() => parse(value), throwsFormatException, reason: '$value');
    }
  });

  Map<String, Object?> external(String path, String hash) => {
    'schemaVersion': 1,
    'source': {
      'kind': 'external',
      'pageCount': 10,
      'path': path,
      'sha256': hash,
    },
  };

  test(
    'external source requires an explicit SHA-256 and no invented sizes',
    () {
      for (final value in [
        external('', 'a' * 64),
        external('fixture.pdf', ''),
        external('fixture.pdf', 'z' * 64),
        external('fixture.pdf', 'a' * 63),
        {
          'schemaVersion': 1,
          'source': {
            'kind': 'external',
            'path': 'fixture.pdf',
            'sha256': 'a' * 64,
          },
        },
        {
          'schemaVersion': 1,
          'source': {
            'kind': 'external',
            'pageCount': 10,
            'path': 'fixture.pdf',
            'sha256': 'a' * 64,
            'mixedPageSizes': true,
          },
        },
      ]) {
        expect(() => parse(value), throwsFormatException);
      }
      final input = parse(external('fixture.pdf', 'A' * 64));
      expect(input.externalSha256, 'a' * 64);
      expect(
        input.sourcePath,
        p.join(Directory.systemTemp.path, 'fixture.pdf'),
      );
      expect(input.mixedPageSizes, isNull);
    },
  );

  test('reader count mismatch is an explicit failure', () {
    final input = parse(generated(pages: 100));
    input.verifyPageCount(100);
    expect(() => input.verifyPageCount(99), throwsStateError);
  });

  Map<String, dynamic> caseReport(PerfPdfCase pdfCase) => report(
    [phase(name: 'pdf.reader.open')],
    changes: {
      'settings': {'pdfReaderCase': pdfCase.toComparisonJson()},
    },
  );

  test('the existing comparator rejects changed input and navigation', () {
    final baseline = caseReport(parse(generated()));
    for (final pdfCase in [
      parse(generated(pages: 100)),
      parse({
        ...generated(),
        'source': {
          'kind': 'generated',
          'pageCount': 600,
          'mixedPageSizes': false,
        },
      }),
      parse(generated(navigation: {'initialPage': 2})),
      parse(generated(navigation: {'forwardPage': 499})),
      parse(generated(navigation: {'backwardPage': 99})),
      parse(generated(navigation: {'zoomFactor': 3})),
      parse(external('fixture.pdf', 'a' * 64)),
    ]) {
      final comparison = compareProbeReports(baseline, caseReport(pdfCase));
      expect(comparison['comparable'], isFalse);
      expect(comparison['reasons'], contains('metadata:settings'));
    }
    expect(
      compareProbeReports(
        caseReport(parse(external('one.pdf', 'a' * 64))),
        caseReport(parse(external('two.pdf', 'b' * 64))),
      )['comparable'],
      isFalse,
    );
  });

  test(
    'equal bytes/actions compare despite JSON order, numeric syntax and path',
    () {
      final first = parse(external('one.pdf', 'A' * 64));
      final second = parse({
        'navigation': {
          'zoomFactor': 2.0,
          'backwardPage': 1,
          'forwardPage': 7,
          'initialPage': 1,
        },
        ...external('elsewhere/two.pdf', 'a' * 64),
      });
      expect(first.toComparisonJson(), second.toComparisonJson());
      expect(
        compareProbeReports(
          caseReport(first),
          caseReport(second),
        )['comparable'],
        isTrue,
      );
    },
  );

  group('validated input snapshots', () {
    late Directory temporary;
    setUp(
      () async =>
          temporary = await Directory.systemTemp.createTemp('pdf-case-'),
    );
    tearDown(() async => temporary.delete(recursive: true));

    test(
      'snapshot resolves relative input, validates hash and leaves source unchanged',
      () async {
        const sourceName = 'מקור עם רווח.pdf';
        final source = File(p.join(temporary.path, sourceName));
        await source.writeAsString('%PDF-1.7\ninput bytes\n');
        final bytes = await source.readAsBytes();
        final modified = await source.lastModified();
        final config = File(p.join(temporary.path, 'תצורת מדידה.json'));
        await config.writeAsString(
          '\ufeff${jsonEncode(external(sourceName, sha256.convert(bytes).toString()))}',
        );
        final outputDirectory = await Directory(
          p.join(temporary.path, 'output'),
        ).create();
        final snapshot = File(p.join(outputDirectory.path, 'case.json'));
        await snapshotPerfPdfCase(config, snapshot);
        await config.delete();
        final stored = await PerfPdfCase.load(snapshot.path);
        expect(stored.sourcePath, source.path);
        expect(await source.readAsBytes(), bytes);
        expect(await source.lastModified(), modified);
        expect(
          await outputDirectory.list().length,
          1,
          reason: 'Only JSON is snapshotted before preparation.',
        );
        await expectLater(
          snapshotPerfPdfCase(snapshot, snapshot),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          (await PerfPdfCase.load(snapshot.path)).toJson(),
          stored.toJson(),
        );
      },
    );

    test(
      'bad hash fails without creating a snapshot or editing the input',
      () async {
        final source = File(p.join(temporary.path, 'input.pdf'));
        await source.writeAsString('unchanged');
        final config = File(p.join(temporary.path, 'case.json'));
        await config.writeAsString(jsonEncode(external('input.pdf', 'a' * 64)));
        final output = File(p.join(temporary.path, 'snapshot.json'));
        await expectLater(
          snapshotPerfPdfCase(config, output),
          throwsStateError,
        );
        expect(await output.exists(), isFalse);
        expect(await source.readAsString(), 'unchanged');
      },
    );

    test('oversized JSON fails before decoding', () async {
      final config = File(p.join(temporary.path, 'oversized.json'));
      await config.writeAsString(' ' * (64 * 1024 + 1));
      await expectLater(PerfPdfCase.load(config.path), throwsFormatException);
    });
  });
}
