import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/pdf_sheet_composer.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalModulePath = Pdfrx.pdfiumModulePath;
  late Directory directory;
  late File file;
  late Uint8List bytes;
  final sizes = [
    PdfPageFormat.a4,
    PdfPageFormat.a5,
    PdfPageFormat.a4.landscape,
  ];

  setUpAll(() async {
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    directory = await Directory.systemTemp.createTemp('print-source-');
    await pdfrxInitialize(tmpPath: directory.path);
    final pdf = pw.Document(compress: false, title: 'x' * (1024 * 1024 + 1));
    for (var i = 0; i < sizes.length; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: sizes[i],
          build: (_) => pw.Text('vector-page-${i + 1}'),
        ),
      );
    }
    bytes = await pdf.save();
    expect(bytes.length, greaterThan(1024 * 1024));
    file = await File('${directory.path}/mixed.pdf').writeAsBytes(bytes);
  });
  tearDownAll(() async {
    Pdfrx.pdfiumModulePath = originalModulePath;
    await directory.delete(recursive: true);
  });

  for (final fromFile in [true, false]) {
    test(
      'open/close/reopen preserves mixed sizes (${fromFile ? 'path' : 'bytes'})',
      () async {
        final source = fromFile
            ? PrintPdfSource.file(file.path)
            : PrintPdfSource.data(bytes);
        for (var repeat = 0; repeat < 4; repeat++) {
          final document = await source.open();
          try {
            expect(document.pages.length, sizes.length);
            for (var i = 0; i < sizes.length; i++) {
              final page = document.pages[i];
              expect(page.width, closeTo(sizes[i].width, 0.01));
              expect(page.height, closeTo(sizes[i].height, 0.01));
              expect(
                (await page.loadText())!.fullText,
                contains('vector-page-${i + 1}'),
              );
            }
          } finally {
            await document.dispose();
          }
        }
        final original = await source.readBytes();
        expect(original, orderedEquals(bytes));
        if (!fromFile) expect(identical(original, bytes), isTrue);
      },
    );

    test(
      'range/N-up output stays searchable (${fromFile ? 'path' : 'bytes'})',
      () async {
        final source = fromFile
            ? PrintPdfSource.file(file.path)
            : PrintPdfSource.data(bytes);
        final document = await source.open();
        late Uint8List output;
        try {
          output = await composePdfSheets(
            document,
            firstIndex: 1,
            lastIndex: 2,
            rows: 1,
            cols: 2,
            sheetWidth: PdfPageFormat.a4.width,
            sheetHeight: PdfPageFormat.a4.height,
          );
        } finally {
          await document.dispose();
        }
        final composed = await PrintPdfSource.data(output).open();
        try {
          expect(composed.pages.length, 1);
          final text = (await composed.pages.single.loadText())!.fullText;
          expect(text, contains('vector-page-2'));
          expect(text, contains('vector-page-3'));
          expect(text, isNot(contains('vector-page-1')));
        } finally {
          await composed.dispose();
        }
      },
    );
  }
}
