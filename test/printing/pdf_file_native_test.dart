import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/pdf_file_stream.dart';
import 'package:otzaria/printing/print_pdf_file_cache.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalModulePath = Pdfrx.pdfiumModulePath;
  late Directory directory;
  late Uint8List fontBytes;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pdf-file-native-test-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    await pdfrxInitialize(tmpPath: directory.path);
    fontBytes = await File('fonts/Tinos-Regular.ttf').readAsBytes();
  });
  tearDownAll(() async {
    Pdfrx.pdfiumModulePath = originalModulePath;
    await directory.delete(recursive: true);
  });

  test(
    'a leased file preserves native Hebrew, layout, pixels and source lifetime',
    () async {
      final cache = PrintPdfFileCache(temporaryDirectory: directory);
      final formats = [PdfPageFormat.a4, PdfPageFormat.a5.landscape];
      final pdf = _document(fontBytes, formats);
      PrintPdfFileLease? lease;
      PdfDocument? fromFile;
      PdfDocument? fromBytes;
      Future<void>? closing;
      try {
        lease = await cache.acquire(
          'hebrew',
          (path) => writePdfDocumentToFile(pdf, path),
        );
        final path = lease.path;
        final saved = await _document(fontBytes, formats).save();
        fromFile = await lease.source.open();
        fromBytes = await PrintPdfSource.data(saved).open();
        cache.invalidate();
        var closed = false;
        closing = cache.dispose().then((_) => closed = true);
        expect(closed, isFalse);
        expect(await File(path).exists(), isTrue);
        expect(fromFile.pages.length, formats.length);
        for (var index = 0; index < formats.length; index++) {
          final filePage = fromFile.pages[index];
          final memoryPage = fromBytes.pages[index];
          expect(filePage.width, closeTo(formats[index].width, 0.01));
          expect(filePage.height, closeTo(formats[index].height, 0.01));
          final text = (await filePage.loadText())!.fullText;
          expect(text, contains('שלום'));
          expect(text, (await memoryPage.loadText())!.fullText);
          final fileImage = await filePage.render(
            width: 300,
            height: 400,
            fullWidth: 300,
            fullHeight: 400,
            backgroundColor: 0xffffffff,
          );
          final memoryImage = await memoryPage.render(
            width: 300,
            height: 400,
            fullWidth: 300,
            fullHeight: 400,
            backgroundColor: 0xffffffff,
          );
          try {
            expect(fileImage, isNotNull);
            expect(memoryImage, isNotNull);
            expect(fileImage!.pixels, orderedEquals(memoryImage!.pixels));
            var ink = 0;
            for (var i = 0; i < fileImage.pixels.length; i += 4) {
              if (fileImage.pixels[i] < 200 &&
                  fileImage.pixels[i + 1] < 200 &&
                  fileImage.pixels[i + 2] < 200 &&
                  fileImage.pixels[i + 3] > 128) {
                ink++;
              }
            }
            expect(ink, greaterThan(100));
          } finally {
            fileImage?.dispose();
            memoryImage?.dispose();
          }
        }
        await fromFile.dispose();
        fromFile = null;
        await fromBytes.dispose();
        fromBytes = null;
        await lease.dispose();
        await closing;
        expect(closed, isTrue);
        expect(await File(path).parent.exists(), isFalse);
      } finally {
        try {
          await fromFile?.dispose();
        } finally {
          try {
            await fromBytes?.dispose();
          } finally {
            try {
              await lease?.dispose();
            } finally {
              await (closing ?? cache.dispose());
            }
          }
        }
      }
    },
  );
}

pw.Document _document(Uint8List fontBytes, List<PdfPageFormat> formats) {
  final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
  final document = pw.Document(compress: false);
  for (final format in formats) {
    document.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Center(
          child: pw.Text(
            'שלום',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: font, fontSize: 32),
          ),
        ),
      ),
    );
  }
  return document;
}
