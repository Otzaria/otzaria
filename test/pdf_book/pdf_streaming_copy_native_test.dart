import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_text_selection_actions.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../test_helpers/pdf_document_dispose.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalModulePath = Pdfrx.pdfiumModulePath;
  final originalCacheDirectory = Pdfrx.cacheDirectoryPath;
  late Directory cacheDirectory;
  final clipboard = <String>[];

  setUp(() {
    cacheDirectory = Directory.systemTemp.createTempSync('pdf-streaming-copy-');
    Pdfrx.cacheDirectoryPath = cacheDirectory.path;
    final module = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$module',
    ).absolute.path;
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    Pdfrx.cacheDirectoryPath = originalCacheDirectory;
    cacheDirectory.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    '1001-page native Copy keeps geometry bounded and preserves text',
    (
      tester,
    ) async {
      const pageCount = 1001;
      final bytes = _largePdf(pageCount);
      final document = (await tester.runAsync(() async {
        await pdfrxFlutterInitialize();
        return PdfDocument.openData(bytes);
      }))!;
      try {
        final controller = await _show(tester, document);
        final actions = PdfTextSelectionActions(
          controller,
          isActive: () => true,
        );
        expect(
          await tester.runAsync(actions.selectAll),
          PdfTextActionResult.none,
        );
        final selection = controller.textSelectionDelegate;
        final range = selection.textSelectionPointRange!;
        expect(range.start.text.pageNumber, 1);
        expect(range.end.text.pageNumber, pageCount);
        final cache = PdfPageTextCache.forDocument(document);
        final before = _cacheCounters(cache);

        expect(
          await tester.runAsync(() => actions.copy(keepSelection: true)),
          PdfTextActionResult.copied,
        );
        expect(clipboard, hasLength(1));
        expect(selection.textSelectionPointRange!.start, range.start);
        expect(selection.textSelectionPointRange!.end, range.end);
        final after = _cacheCounters(cache);
        expect(cache.length, lessThanOrEqualTo(cache.maximumPages));
        expect(cache.estimatedBytes, lessThanOrEqualTo(cache.maximumBytes));
        expect(clipboard.single, contains('Page 1 line 0'));
        expect(clipboard.single, contains('Page 1001 line 4'));

        final reference = await tester.runAsync(selection.getSelectedText);
        expect(clipboard.single, reference);
        debugPrint(
          'PDF_STREAMING_COPY ${jsonEncode({
            'pages': pageCount,
            'fixtureBytes': bytes.length,
            'fixtureSha256': sha256.convert(bytes).toString(),
            'outputCharacters': clipboard.single.length,
            'before': before,
            'afterApplicationCopy': after,
            'afterLibraryReferenceRead': _cacheCounters(cache),
            'scope': 'Dart text-cache counters; not native allocations or RSS',
          })}',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(
          const PdfViewerBehaviorControlParams().trailingPageLoadingDelay,
        );
        await disposePdfDocument(tester, document);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native backward Hebrew selection matches library text across a blank page',
    (
      tester,
    ) async {
      final document = (await tester.runAsync(() async {
        await pdfrxFlutterInitialize();
        final font = pw.Font.ttf(
          File(
            'fonts/FrankRuehlCLM-Medium.ttf',
          ).readAsBytesSync().buffer.asByteData(),
        );
        final pdf = pw.Document();
        for (final content in [
          'התחלה שָׁלוֹם שלום ABC 123',
          '',
          'סוף שלום  XYZ 456',
        ]) {
          pdf.addPage(
            pw.Page(
              build: (_) => content.isEmpty
                  ? pw.SizedBox()
                  : pw.Text(
                      content,
                      style: pw.TextStyle(font: font),
                      textDirection: pw.TextDirection.rtl,
                    ),
            ),
          );
        }
        return PdfDocument.openData(await pdf.save());
      }))!;
      try {
        final controller = await _show(tester, document);
        final first = (await tester.runAsync(
          document.pages.first.loadStructuredText,
        ))!;
        final last = (await tester.runAsync(
          document.pages.last.loadStructuredText,
        ))!;
        final selection = controller.textSelectionDelegate;
        final range = PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(last, last.charRects.length - 3),
          PdfTextSelectionPoint(first, 2),
        );
        await selection.setTextSelectionPointRange(range);
        final reference = await tester.runAsync(selection.getSelectedText);
        final actions = PdfTextSelectionActions(
          controller,
          isActive: () => true,
        );
        expect(
          await tester.runAsync(() => actions.copy(keepSelection: true)),
          PdfTextActionResult.copied,
        );
        expect(clipboard.single, reference);
        expect(clipboard.single, contains('שלום'));
        expect(clipboard.single, contains('ABC'));
        expect(selection.textSelectionPointRange!.start, range.start);
        expect(selection.textSelectionPointRange!.end, range.end);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(
          const PdfViewerBehaviorControlParams().trailingPageLoadingDelay,
        );
        await disposePdfDocument(tester, document);
      }
    },
  );
}

Future<PdfViewerController> _show(
  WidgetTester tester,
  PdfDocument document,
) async {
  final controller = PdfViewerController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
          params: PdfViewerParams(
            textSelectionParams: PdfTextSelectionParams(
              showContextMenuAutomatically: false,
            ),
          ),
        ),
      ),
    ),
  );
  final clock = Stopwatch()..start();
  while (!controller.isReady ||
      controller.visibleRenderState.value != PdfVisibleRenderState.ready) {
    if (clock.elapsed > const Duration(seconds: 30)) {
      fail('The native PDF viewer did not become ready');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  return controller;
}

Map<String, int> _cacheCounters(PdfPageTextCache cache) => {
  'pages': cache.length,
  'estimatedBytes': cache.estimatedBytes,
};

Uint8List _largePdf(int count) {
  final ids = [for (var i = 0; i < count; i++) 4 + i * 2];
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count $count /Kids [${ids.map((id) => '$id 0 R').join(' ')}] >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (var i = 0; i < count; i++) {
    final content = StringBuffer();
    for (var line = 0; line < 5; line++) {
      content.writeln(
        'BT /F1 10 Tf 20 ${780 - line * 20} Td '
        '(Page ${i + 1} line $line: ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789) Tj ET',
      );
    }
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents ${ids[i] + 1} 0 R >>',
    );
    objects.add('<< /Length ${content.length} >>\nstream\n${content}endstream');
  }
  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = output.length;
  output.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(output.toString()));
}
