import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/pdf_export_cancellation.dart';
import 'package:otzaria/printing/pdf_sheet_composer.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

Future<Uint8List> _sourcePdf() async {
  final fontBytes = await File('fonts/Tinos-Regular.ttf').readAsBytes();
  final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
  final document = pw.Document();
  for (var index = 1; index <= 5; index++) {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                'page$index',
                style: pw.TextStyle(font: font, fontSize: 28),
              ),
              pw.Text(
                'שלום',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: font, fontSize: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
  return document.save();
}

Future<({String digest, int ink})> _raster(PdfPage page) async {
  final image = await page.render(
    fullWidth: page.width,
    fullHeight: page.height,
    backgroundColor: 0xffffffff,
  );
  if (image == null) throw StateError('PDFium returned no raster.');
  try {
    final pixels = image.pixels;
    var ink = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      if ((765 - pixels[i] - pixels[i + 1] - pixels[i + 2]) * pixels[i + 3] >
          3 * 15 * 255) {
        ink++;
      }
    }
    return (digest: sha256.convert(pixels).toString(), ink: ink);
  } finally {
    image.dispose();
  }
}

// Distinct uncompressed image objects keep native serialization larger than a disk block.
void _writeLargeImagePdf(File file) {
  const width = 2048, height = 1536, pages = 4;
  const imageBytes = width * height * 3;
  final random = Random(5538);
  final chunk = Uint8List.fromList([
    for (var i = 0; i < 65536; i++) random.nextInt(256),
  ]);
  final output = file.openSync(mode: FileMode.write);
  final offsets = <int>[];
  void text(String value) => output.writeFromSync(latin1.encode(value));
  void object(int number, String value) {
    offsets.add(output.positionSync());
    text('$number 0 obj\n$value\nendobj\n');
  }

  try {
    text('%PDF-1.4\n');
    object(1, '<< /Type /Catalog /Pages 2 0 R >>');
    object(
      2,
      '<< /Type /Pages /Count $pages /Kids [${[for (var i = 0; i < pages; i++) '${3 + i * 3} 0 R'].join(' ')}] >>',
    );
    for (var index = 0; index < pages; index++) {
      final page = 3 + index * 3;
      object(
        page,
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents ${page + 1} 0 R /Resources << /XObject << /Image ${page + 2} 0 R >> >> >>',
      );
      const content = 'q 595 0 0 842 0 0 cm /Image Do Q';
      object(
        page + 1,
        '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      );
      offsets.add(output.positionSync());
      text(
        '${page + 2} 0 obj\n<< /Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length $imageBytes >>\nstream\n',
      );
      chunk[0] = index;
      for (var written = 0; written < imageBytes; written += chunk.length) {
        output.writeFromSync(chunk, 0, min(chunk.length, imageBytes - written));
      }
      text('\nendstream\nendobj\n');
    }
    final xref = output.positionSync();
    text('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
    for (final offset in offsets) {
      text('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    text(
      'trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
    );
  } finally {
    output.closeSync();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File sourceFile;
  final originalModulePath = Pdfrx.pdfiumModulePath;
  final originalCachePath = Pdfrx.cacheDirectoryPath;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pdf-sheet-file-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    Pdfrx.cacheDirectoryPath = directory.path;
    await pdfrxFlutterInitialize();
    sourceFile = File('${directory.path}/source.pdf');
    await sourceFile.writeAsBytes(await _sourcePdf());
  });

  tearDownAll(() async {
    Pdfrx.pdfiumModulePath = originalModulePath;
    Pdfrx.cacheDirectoryPath = originalCachePath;
    await directory.delete(recursive: true);
  });

  for (final (name, rows, cols, first, last, rtl) in [
    ('range', 1, 1, 1, 3, true),
    ('two-rtl', 1, 2, 0, 4, true),
    ('four-rtl', 2, 2, 0, 4, true),
    ('two-ltr', 1, 2, 0, 4, false),
  ]) {
    test('קובץ $name שומר טקסט עברי, סדר ורסטר כמו ממשק bytes', () async {
      final source = await PdfDocument.openFile(sourceFile.path);
      final target = File('${directory.path}/$name.pdf');
      PdfDocument? fromBytes;
      PdfDocument? fromFile;
      try {
        final bytes = await composePdfSheets(
          source,
          firstIndex: first,
          lastIndex: last,
          rows: rows,
          cols: cols,
          sheetWidth: PdfPageFormat.a4.width,
          sheetHeight: PdfPageFormat.a4.height,
          rightToLeft: rtl,
        );
        await target.create(exclusive: true);
        final length = await composePdfSheetsToFile(
          source,
          outputPath: target.path,
          firstIndex: first,
          lastIndex: last,
          rows: rows,
          cols: cols,
          sheetWidth: PdfPageFormat.a4.width,
          sheetHeight: PdfPageFormat.a4.height,
          rightToLeft: rtl,
        );
        expect(length, await target.length());
        expect(length, greaterThan(100));
        fromBytes = await PdfDocument.openData(bytes);
        fromFile = await PdfDocument.openFile(target.path);
        expect(
          fromFile.pages.length,
          ((last - first + 1) / (rows * cols)).ceil(),
        );
        expect(fromFile.pages.length, fromBytes.pages.length);
        for (var i = 0; i < fromFile.pages.length; i++) {
          final actual = fromFile.pages[i];
          final expected = fromBytes.pages[i];
          expect(actual.width, expected.width);
          expect(actual.height, expected.height);
          final text = (await actual.loadStructuredText()).fullText;
          expect(text, (await expected.loadStructuredText()).fullText);
          expect(text, contains('שלום'));
          final actualRaster = await _raster(actual);
          final expectedRaster = await _raster(expected);
          expect(actualRaster.ink, greaterThan(100));
          expect(actualRaster, expectedRaster);
        }
        // The caller still owns an open, usable input document after both exports.
        expect(
          (await source.pages.first.loadStructuredText()).fullText,
          contains('page1'),
        );
      } finally {
        await fromFile?.dispose();
        await fromBytes?.dispose();
        await source.dispose();
      }
      await target.delete();
    });
  }

  Future<int> write(
    PdfDocument source,
    String path, {
    PdfExportCancellationToken? token,
  }) => composePdfSheetsToFile(
    source,
    outputPath: path,
    firstIndex: 0,
    lastIndex: 4,
    rows: 1,
    cols: 2,
    sheetWidth: PdfPageFormat.a4.width,
    sheetHeight: PdfPageFormat.a4.height,
    cancellationToken: token,
  );

  test('ביטול מראש אינו משנה את קובץ הביניים או סוגר את המקור', () async {
    final source = await PdfDocument.openFile(sourceFile.path);
    final target = File('${directory.path}/cancelled.pdf');
    await target.writeAsString('reserved');
    final token = PdfExportCancellationToken()..cancel();
    try {
      await expectLater(
        write(source, target.path, token: token),
        throwsA(isA<PdfExportCancelledException>()),
      );
      expect(await target.readAsString(), 'reserved');
      expect(
        (await source.pages.first.loadStructuredText()).fullText,
        contains('page1'),
      );
    } finally {
      token.dispose();
      await source.dispose();
    }
  });

  test('dispose בזמן המתנה ל-worker משאיר את הדגל חי עד סיומו', () async {
    final source = await PdfDocument.openFile(sourceFile.path);
    final original = PdfrxEntryFunctions.instance;
    final gated = _GatedCompute(original);
    final token = PdfExportCancellationToken();
    final path = '${directory.path}/queued-cancel.pdf';
    Future<void>? checked;
    PdfrxEntryFunctions.instance = gated;
    try {
      checked = expectLater(
        write(source, path, token: token),
        throwsA(isA<PdfExportCancelledException>()),
      );
      await Future.any([gated.started.future, checked])
          .timeout(const Duration(seconds: 5));
      token.dispose();
      gated.release.complete();
      await checked;
      expect(await File(path).exists(), isFalse);
    } finally {
      token.dispose();
      if (!gated.release.isCompleted) gated.release.complete();
      try {
        await checked;
      } finally {
        PdfrxEntryFunctions.instance = original;
        await source.dispose();
      }
    }
  });

  test('כשל פתיחת יעד אינו מדליף מסמך, והייצוא הבא מצליח', () async {
    final source = await PdfDocument.openFile(sourceFile.path);
    try {
      await expectLater(
        write(source, directory.path),
        throwsA(isA<FileSystemException>()),
      );
      final target = File('${directory.path}/after-open-failure.pdf');
      expect(await write(source, target.path), await target.length());
      final opened = await PdfDocument.openFile(target.path);
      try {
        expect(opened.pages, hasLength(3));
      } finally {
        await opened.dispose();
      }
      await target.delete();
    } finally {
      await source.dispose();
    }
  });

  test('ביטול אחרי תחילת כתיבה native סוגר פלט חלקי בלי לשחרר דגל מוקדם', () async {
    final input = File('${directory.path}/large-input.pdf');
    _writeLargeImagePdf(input);
    final source = await PdfDocument.openFile(input.path);
    Future<int> export(String path, PdfExportCancellationToken? token) =>
        composePdfSheetsToFile(
          source,
          outputPath: path,
          firstIndex: 0,
          lastIndex: 3,
          rows: 2,
          cols: 2,
          sheetWidth: 595,
          sheetHeight: 842,
          cancellationToken: token,
        );

    try {
      final complete = File('${directory.path}/large-complete.pdf');
      final fullLength = await export(complete.path, null);
      expect(fullLength, greaterThan(32 * 1024 * 1024));
      expect(fullLength, await complete.length());
      final completeDocument = await PdfDocument.openFile(complete.path);
      try {
        expect(completeDocument.pages, hasLength(1));
      } finally {
        await completeDocument.dispose();
      }
      await complete.delete();

      var observedCancellation = false;
      for (var attempt = 0; attempt < 3 && !observedCancellation; attempt++) {
        final target = File('${directory.path}/large-partial-$attempt.pdf');
        final token = PdfExportCancellationToken();
        var completed = false;
        final writing = export(target.path, token).then<Object>(
          (length) {
            completed = true;
            return length;
          },
          onError: (Object error) {
            completed = true;
            return error;
          },
        );
        try {
          var seen = 0;
          final deadline = Stopwatch()..start();
          while (!completed && seen == 0) {
            if (await target.exists()) seen = await target.length();
            if (deadline.elapsed > const Duration(seconds: 10)) {
              fail('Native export did not start writing within the deadline.');
            }
            if (seen == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          }
          token.dispose();
          final result = await writing;
          final written = await target.length();
          if (result is PdfExportCancelledException) {
            observedCancellation = seen > 0 && written < fullLength;
          } else {
            expect(result, fullLength);
            expect(written, fullLength);
          }
          stdout.writeln(
            'PDF_SHEET_FILE_CANCEL ${jsonEncode({'attempt': attempt, 'observedBytesBeforeCancel': seen, 'writtenBytes': written, 'fullOutputBytes': fullLength, 'cancelledDuringWrite': observedCancellation})}',
          );
        } finally {
          token.dispose();
          await writing;
          if (await target.exists()) await target.delete();
        }
      }
      expect(
        observedCancellation,
        isTrue,
        reason: 'The test must observe a real partial native write before cancellation.',
      );
      final image = await source.pages.first.render(
        width: 64,
        height: 64,
        fullWidth: 64,
        fullHeight: 64,
      );
      expect(image, isNotNull);
      image?.dispose();
    } finally {
      await source.dispose();
      await input.delete();
    }
  });

  if (Platform.isLinux) {
    test('כשל כתיבה native מוחזר מ-WriteBlock והייצוא הבא מצליח', () async {
      final source = await PdfDocument.openFile(sourceFile.path);
      try {
        await expectLater(
          write(source, '/dev/full'),
          throwsA(isA<FileSystemException>()),
        );
        final target = File('${directory.path}/after-write-failure.pdf');
        expect(await write(source, target.path), await target.length());
        await target.delete();
      } finally {
        await source.dispose();
      }
    });
  }
}

class _GatedCompute implements PdfrxEntryFunctions {
  _GatedCompute(this.original);
  final PdfrxEntryFunctions original;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<T> suspendPdfiumWorkerDuringAction<T>(FutureOr<T> Function() action) =>
      original.suspendPdfiumWorkerDuringAction(action);

  @override
  Future<R> compute<M, R>(FutureOr<R> Function(M) callback, M message) async {
    started.complete();
    await release.future;
    return original.compute(callback, message);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
