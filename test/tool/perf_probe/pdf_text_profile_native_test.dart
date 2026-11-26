import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
// Same public engine API and native backend as the AOT component probe.
// ignore: depend_on_referenced_packages
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

import '../../../tool/perf_probe/pdf_text_fixture.dart';
import '../../../tool/perf_probe/run_pdf_text_profile.dart';
import '../../../tool/perf_probe/src/pdf_text_profile.dart';

void main() {
  late Directory directory;
  late File input;
  late Map<String, Object?> corpus;
  final previousFlags = (
    Pdfrx.normalizeHebrewText,
    Pdfrx.decodeLegacyHebrewText,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pdf-text-native-');
    final module = Platform.environment['OTZARIA_PDF_TEXT_PDFIUM'];
    if (module != null) {
      final expected = Platform.environment['OTZARIA_PDF_TEXT_PDFIUM_SHA256'];
      expect(expected, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        (await sha256.bind(File(module).openRead()).single).toString(),
        expected,
      );
      Pdfrx.pdfiumModulePath = module;
    }
    Pdfrx.normalizeHebrewText = true;
    Pdfrx.decodeLegacyHebrewText = true;
    await pdfrxInitialize(tmpPath: directory.path);
    input = File('${directory.path}/corpus.pdf');
    corpus = await writePdfTextFixture(
      input,
      fontFile: File('fonts/Tinos-Regular.ttf'),
    );
  });
  tearDownAll(() async {
    Pdfrx.normalizeHebrewText = previousFlags.$1;
    Pdfrx.decodeLegacyHebrewText = previousFlags.$2;
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
    await directory.delete(recursive: true);
  });

  test(
    'the embedded corpus is deterministic and renders Hebrew bodies',
    () async {
      final same = await writePdfTextFixture(
        File('${directory.path}/same.pdf'),
        fontFile: File('fonts/Tinos-Regular.ttf'),
      );
      expect(same, corpus);
      expect(
        corpus['sha256'],
        '3f148e978f8bdb29f499a9dc229d05708bf0e7c895ee9f4469300f3f8ce8cfb4',
      );
      final document = await PdfDocument.openFile(input.path);
      try {
        final validation = await validatePdfTextFixture(document);
        expect(validation['status'], 'passed');
        final pages = validation['pages'] as List<Map<String, Object?>>;
        expect(pages.length, 32);
        expect(pages.where((p) => p.containsKey('raster')).length, 8);
        expect(pages.where((p) => p['niqqudMarks'] == 60).length, 4);
        expect(validation['pointedTextObservation'], {
          'kind': 'pdfium-inserted-spaces',
          'pages': [2, 10, 18, 26],
          'extractedLine': pdfTextPointedExtractedLine,
          'niqqudMarksPerPage': 60,
          'queryId': 'niqqud_tolerant',
          'matchesPerPage': 0,
        });
      } finally {
        await document.dispose();
      }
    },
  );

  test('legacy control requires the app normalization policy', () async {
    final document = await PdfDocument.openFile(input.path);
    try {
      Pdfrx.decodeLegacyHebrewText = false;
      final legacy = await document.pages[7].loadStructuredText();
      expect(legacy.fullText.contains('שלום'), isFalse);
      expect(legacy.fullText, contains('íìåò íåìù'));
      Pdfrx.decodeLegacyHebrewText = true;
      final decoded = await document.pages[7].loadStructuredText();
      expect('שלום'.allMatches(decoded.fullText).length, 12);
      expect('עולם'.allMatches(decoded.fullText).length, 12);
    } finally {
      Pdfrx.decodeLegacyHebrewText = true;
      await document.dispose();
    }
  });

  test(
    'native pipeline and both LRU sweeps keep text and geometry parity',
    () async {
      final document = await PdfDocument.openFile(input.path);
      try {
        final rows = <Map<String, Object?>>[];
        final profile = await runPdfTextProfile(
          document: document,
          queries: pdfTextFixtureQueries,
          warmup: 0,
          repetitions: 1,
          onObservation: rows.add,
        );
        validatePdfTextCorpusResults(profile);
        expect(rows.length, 96);
        expect(rows.every((row) => row['parity'] == true), isTrue);
        for (final phase in ['pipeline', 'cacheFirst', 'cacheRepeat']) {
          final samples = rows.where((row) => row['phase'] == phase).toList();
          expect(samples.length, 32);
          expect(samples.every((row) => row['rawLoadCalls'] == 1), isTrue);
        }
        final changed = jsonDecode(jsonEncode(profile)) as Map<String, Object?>;
        for (final row in changed['observations'] as List) {
          for (final query in row['queries'] as List) {
            query['matches'] = 0;
            query['rects'] = 0;
          }
        }
        expect(() => validatePdfTextCorpusResults(changed), throwsStateError);
      } finally {
        await document.dispose();
      }
    },
  );
}
