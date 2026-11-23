import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../integration_test/support/perf_fixture.dart';
import '../../../tool/perf_probe/make_pdf_print_preview_fixtures.dart';
import '../../../tool/perf_probe/src/pdf_reader_case.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalModule = Pdfrx.pdfiumModulePath;
  setUpAll(() {
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
  });
  tearDownAll(() => Pdfrx.pdfiumModulePath = originalModule);
  late Directory temporary;
  setUp(
    () async =>
        temporary = await Directory.systemTemp.createTemp('pdf-case-fixture-'),
  );
  tearDown(() async {
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideDocumentsRootPath(null);
    await temporary.delete(recursive: true);
  });

  PerfPdfCase generated(int pages, {bool mixed = true}) =>
      PerfPdfCase.fromJson({
        'schemaVersion': 1,
        'source': {
          'kind': 'generated',
          'pageCount': pages,
          'mixedPageSizes': mixed,
        },
      }, baseDirectory: temporary.path);

  Future<PerfPdfCase> external(File file, {int expectedPages = 10}) async =>
      PerfPdfCase.fromJson({
        'schemaVersion': 1,
        'source': {
          'kind': 'external',
          'pageCount': expectedPages,
          'path': file.path,
          'sha256': (await sha256.bind(file.openRead()).first).toString(),
        },
      }, baseDirectory: temporary.path);

  Future<PdfDocument> open(PerfFixture fixture) async {
    await pdfrxInitialize(tmpPath: temporary.path);
    return PdfDocument.openFile(fixture.pdfPath, useProgressiveLoading: true);
  }

  for (final count in [10, 100, 1000, 10000]) {
    test(
      'generated $count-page case reaches its selected pages in PDFium',
      () async {
        final pdfCase = generated(count, mixed: count != 10);
        final fixture = PerfFixture(
          Directory(p.join(temporary.path, 'owned')),
          pdfReaderCase: pdfCase,
        );
        await fixture.prepare(preparationOnly: true);
        final document = await open(fixture);
        try {
          pdfCase.verifyPageCount(document.pages.length);
          final targets = pdfCase.navigationTargets;
          await document.reloadPages(
            pageNumbersToReload: [targets.forwardPage, targets.backwardPage],
          );
          for (final pageNumber in [
            targets.forwardPage,
            targets.backwardPage,
          ]) {
            final page = document.pages[pageNumber - 1];
            expect(page.isLoaded, isTrue);
            expect(
              (await page.loadText())!.fullText,
              contains('PDF preview fixture - page $pageNumber'),
            );
          }
          if (pdfCase.mixedPageSizes == false) {
            final page = document.pages[targets.forwardPage - 1];
            expect(page.width, closeTo(document.pages.first.width, 0.01));
            expect(page.height, closeTo(document.pages.first.height, 0.01));
          }
        } finally {
          await document.dispose();
        }
        final marker =
            jsonDecode(
                  await File(
                    p.join(fixture.root.path, '.otzaria-perf-fixture'),
                  ).readAsString(),
                )
                as Map;
        expect(marker['pdfSha256'], fixture.pdfSha256);
        expect(marker['pdfReaderCase'], pdfCase.toComparisonJson());
        await fixture.prepare(preparationOnly: false);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'external input is copied only in preparation and measured without its original',
    () async {
      final source = File(p.join(temporary.path, 'source.pdf'));
      await writePdfProbeFixture(
        source,
        pageCount: 10,
        mixed: true,
        scanned: true,
      );
      final originalBytes = await source.readAsBytes();
      final modified = await source.lastModified();
      final pdfCase = await external(source);
      final fixture = PerfFixture(
        Directory(p.join(temporary.path, 'owned')),
        pdfReaderCase: pdfCase,
      );
      await expectLater(
        fixture.prepare(preparationOnly: false),
        throwsStateError,
      );
      expect(await File(fixture.pdfPath).exists(), isFalse);
      await fixture.prepare(preparationOnly: true);
      expect(await File(fixture.pdfPath).readAsBytes(), originalBytes);
      expect(await source.readAsBytes(), originalBytes);
      expect(await source.lastModified(), modified);
      expect(fixture.pdfSha256, pdfCase.externalSha256);
      await source.rename(p.join(temporary.path, 'original-moved.pdf'));
      await fixture.prepare(preparationOnly: false);
      final document = await open(fixture);
      try {
        pdfCase.verifyPageCount(document.pages.length);
        await document.reloadPages(pageNumbersToReload: [10]);
        expect(
          (await document.pages.last.loadText())!.fullText,
          contains('page 10'),
        );
      } finally {
        await document.dispose();
      }
    },
  );

  test(
    'hash mismatch fails before creating corpus files or touching the original',
    () async {
      final source = File(p.join(temporary.path, 'source.pdf'));
      await writePdfProbeFixture(source, pageCount: 10);
      final pdfCase = await external(source);
      await source.writeAsString('source changed', mode: FileMode.append);
      final original = await source.readAsBytes();
      final fixture = PerfFixture(
        Directory(p.join(temporary.path, 'owned')),
        pdfReaderCase: pdfCase,
      );
      await expectLater(
        fixture.prepare(preparationOnly: true),
        throwsStateError,
      );
      expect(await fixture.root.list().isEmpty, isTrue);
      expect(await source.readAsBytes(), original);
    },
  );

  test(
    'the same PDF with different navigation is not accepted as the prepared case',
    () async {
      final fixture = PerfFixture(
        Directory(p.join(temporary.path, 'owned')),
        pdfReaderCase: generated(10),
      );
      await fixture.prepare(preparationOnly: true);
      final changedCase = PerfPdfCase.fromJson({
        ...fixture.pdfReaderCase.toJson(),
        'navigation': {'forwardPage': 9, 'backwardPage': 2},
      }, baseDirectory: temporary.path);
      await expectLater(
        PerfFixture(
          fixture.root,
          pdfReaderCase: changedCase,
        ).prepare(preparationOnly: false),
        throwsStateError,
      );
      await fixture.prepare(preparationOnly: false);
    },
  );

  test(
    'tampering with the owned copy fails and never writes through to the original',
    () async {
      final source = File(p.join(temporary.path, 'source.pdf'));
      await writePdfProbeFixture(source, pageCount: 10);
      final pdfCase = await external(source);
      final fixture = PerfFixture(
        Directory(p.join(temporary.path, 'owned')),
        pdfReaderCase: pdfCase,
      );
      await fixture.prepare(preparationOnly: true);
      await File(
        fixture.pdfPath,
      ).writeAsString('changed', mode: FileMode.append);
      await expectLater(
        fixture.prepare(preparationOnly: false),
        throwsStateError,
      );
      await pdfCase.verifyExternalSource();
    },
  );

  test(
    'an external page-count declaration is verified against the native document',
    () async {
      final source = File(p.join(temporary.path, 'source.pdf'));
      await writePdfProbeFixture(source, pageCount: 10);
      final pdfCase = await external(source, expectedPages: 100);
      final fixture = PerfFixture(
        Directory(p.join(temporary.path, 'owned')),
        pdfReaderCase: pdfCase,
      );
      await fixture.prepare(preparationOnly: true);
      final document = await open(fixture);
      try {
        expect(
          () => pdfCase.verifyPageCount(document.pages.length),
          throwsStateError,
        );
      } finally {
        await document.dispose();
      }
    },
  );

  test(
    'a warm fixture cannot replace its owned PDF with a symlink',
    () async {
      final source = File(p.join(temporary.path, 'source.pdf'));
      await writePdfProbeFixture(source, pageCount: 10);
      final pdfCase = await external(source);
      final fixture = PerfFixture(
        Directory(p.join(temporary.path, 'owned')),
        pdfReaderCase: pdfCase,
      );
      await fixture.prepare(preparationOnly: true);
      await File(fixture.pdfPath).delete();
      await Link(fixture.pdfPath).create(source.path);
      await expectLater(
        fixture.prepare(preparationOnly: false),
        throwsStateError,
      );
      await pdfCase.verifyExternalSource();
      await Link(fixture.pdfPath).delete();
      final pdfDirectory = File(fixture.pdfPath).parent;
      await pdfDirectory.delete();
      final elsewhere = await Directory(
        p.join(temporary.path, 'external-directory'),
      ).create();
      await source.copy(p.join(elsewhere.path, p.basename(fixture.pdfPath)));
      await Link(pdfDirectory.path).create(elsewhere.path);
      await expectLater(
        fixture.prepare(preparationOnly: false),
        throwsStateError,
      );
      await pdfCase.verifyExternalSource();
    },
    skip: Platform.isWindows
        ? 'Creating symlinks requires Windows developer mode.'
        : false,
  );
}
