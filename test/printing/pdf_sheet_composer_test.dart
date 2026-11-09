import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/pdf_sheet_composer.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

Future<Uint8List> _numberedPdf(int count) {
  final doc = pw.Document();
  for (var i = 1; i <= count; i++) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(child: pw.Text('page$i')),
      ),
    );
  }
  return doc.save();
}

/// Left edge of `needle` on the page, from the text layer.
Future<double?> _leftOf(PdfPage page, String needle) async {
  final text = await page.loadStructuredText();
  final at = text.fullText.indexOf(needle);
  return at < 0 ? null : text.charRects[at].left;
}

void main() {
  group('sheetSlotOrder', () {
    test('הראשון מימין בכל שורה, ומקום ריק נשמר רק לפני עמוד', () {
      expect(
        sheetSlotOrder(firstIndex: 0, lastIndex: 4, rows: 1, cols: 2),
        [1, 0, 3, 2, null, 4],
      );
      expect(
        sheetSlotOrder(firstIndex: 0, lastIndex: 2, rows: 2, cols: 2),
        [1, 0, null, 2],
      );
    });

    test('משמאל לימין אין צורך במקומות ריקים בסוף', () {
      expect(
        sheetSlotOrder(
          firstIndex: 0,
          lastIndex: 4,
          rows: 1,
          cols: 2,
          rightToLeft: false,
        ),
        [0, 1, 2, 3, 4],
      );
    });

    test('תא יחיד הוא טווח העמודים עצמו', () {
      expect(
        sheetSlotOrder(firstIndex: 2, lastIndex: 4, rows: 1, cols: 1),
        [2, 3, 4],
      );
    });
  });

  group('composePdfSheets', () {
    final originalModulePath = Pdfrx.pdfiumModulePath;
    setUpAll(() async {
      final moduleName = Platform.isWindows
          ? 'pdfium.dll'
          : Platform.isMacOS
          ? 'libpdfium.dylib'
          : 'libpdfium.so';
      Pdfrx.pdfiumModulePath = File(
        'build/native_assets/${Platform.operatingSystem}/$moduleName',
      ).absolute.path;
      // Skips the path_provider lookup, which a plain test has no plugin for.
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
      await pdfrxFlutterInitialize();
    });

    tearDownAll(() => Pdfrx.pdfiumModulePath = originalModulePath);

    test('שני עמודים בגיליון נשארים טקסט, הראשון מימין', () async {
      final source = await PdfDocument.openData(await _numberedPdf(5));
      addTearDown(source.dispose);
      final sheet = PdfPageFormat.a4.landscape;

      final bytes = await composePdfSheets(
        source,
        firstIndex: 0,
        lastIndex: 4,
        rows: 1,
        cols: 2,
        sheetWidth: sheet.width,
        sheetHeight: sheet.height,
      );
      final output = await PdfDocument.openData(bytes);
      addTearDown(output.dispose);

      expect(output.pages, hasLength(3));
      expect(output.pages.first.width, closeTo(sheet.width, 0.5));
      expect(output.pages.first.height, closeTo(sheet.height, 0.5));

      // The text survives as text: a raster sheet would have none.
      final first = await _leftOf(output.pages[0], 'page1');
      final second = await _leftOf(output.pages[0], 'page2');
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!, greaterThan(second!));

      // The odd last page keeps the right-hand cell.
      final last = await _leftOf(output.pages[2], 'page5');
      expect(last, greaterThan(sheet.width / 2));
    });

    test(
      'סדר התוכן בגיליון הוא סדר הקריאה: עליון ימין, עליון שמאל, תחתון ימין, תחתון שמאל',
      () async {
        final source = await PdfDocument.openData(await _numberedPdf(4));
        addTearDown(source.dispose);

        final bytes = await composePdfSheets(
          source,
          firstIndex: 0,
          lastIndex: 3,
          rows: 2,
          cols: 2,
          sheetWidth: PdfPageFormat.a4.width,
          sheetHeight: PdfPageFormat.a4.height,
        );
        final output = await PdfDocument.openData(bytes);
        addTearDown(output.dispose);

        // Selection and extraction follow the order objects are drawn in.
        final cells = await output.useNativeDocumentHandle(
          (handle) => _cellsInDrawOrder(handle, PdfPageFormat.a4),
        );
        expect(cells, ['top-right', 'top-left', 'bottom-right', 'bottom-left']);
      },
    );

    for (final (name, sheet) in [
      ('Legal', PdfPageFormat.legal),
      ('A3', PdfPageFormat.a3),
    ]) {
      test('גיליון $name: שני עמודי A4 בגודל הגיליון', () async {
        final source = await PdfDocument.openData(await _numberedPdf(4));
        addTearDown(source.dispose);

        final bytes = await composePdfSheets(
          source,
          firstIndex: 0,
          lastIndex: 3,
          rows: 2,
          cols: 1,
          sheetWidth: sheet.width,
          sheetHeight: sheet.height,
        );
        final output = await PdfDocument.openData(bytes);
        addTearDown(output.dispose);

        expect(output.pages, hasLength(2));
        expect(output.pages.first.width, closeTo(sheet.width, 0.5));
        expect(output.pages.first.height, closeTo(sheet.height, 0.5));
        final text = await output.pages[1].loadStructuredText();
        expect(text.fullText, contains('page3'));
        expect(text.fullText, contains('page4'));
      });
    }

    test('טווח עמודים בלי גיליון מרובה מעתיק את העמודים כמות שהם', () async {
      final source = await PdfDocument.openData(await _numberedPdf(5));
      addTearDown(source.dispose);

      final bytes = await composePdfSheets(
        source,
        firstIndex: 1,
        lastIndex: 3,
        rows: 1,
        cols: 1,
        sheetWidth: PdfPageFormat.a4.width,
        sheetHeight: PdfPageFormat.a4.height,
      );
      final output = await PdfDocument.openData(bytes);
      addTearDown(output.dispose);

      expect(output.pages, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final text = await output.pages[i].loadStructuredText();
        expect(text.fullText, contains('page${i + 2}'));
      }
    });
  });
}

/// Where each object on the first sheet sits, in the order it is drawn.
List<String> _cellsInDrawOrder(int handle, PdfPageFormat sheet) {
  final pdfium = pdfium_bindings.getPdfium(modulePath: Pdfrx.pdfiumModulePath);
  final page = pdfium.FPDF_LoadPage(
    pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle),
    0,
  );
  try {
    return using((arena) {
      final left = arena<Float>();
      final bottom = arena<Float>();
      final right = arena<Float>();
      final top = arena<Float>();
      return [
        for (var i = 0; i < pdfium.FPDFPage_CountObjects(page); i++)
          if (pdfium.FPDFPageObj_GetBounds(
                pdfium.FPDFPage_GetObject(page, i),
                left,
                bottom,
                right,
                top,
              ) !=
              0)
            '${(bottom.value + top.value) / 2 > sheet.height / 2 ? 'top' : 'bottom'}-'
                '${(left.value + right.value) / 2 > sheet.width / 2 ? 'right' : 'left'}',
      ];
    });
  } finally {
    pdfium.FPDF_ClosePage(page);
  }
}
