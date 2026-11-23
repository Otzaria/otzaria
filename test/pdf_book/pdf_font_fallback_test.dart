import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_fallback.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF עם טקסט עברי גלוי בגופן TrueType שאינו מוטמע — כמו מסכתות הבבלי
/// (ABBYY) וקובצי PDF אישיים רבים.
List<int> _nonEmbeddedHebrewPdf(String fontName) {
  final letters = [for (var i = 0; i < 27; i++) 0x05D0 + i];
  final diffs = letters
      .map((u) => '/uni${u.toRadixString(16).toUpperCase().padLeft(4, '0')}')
      .join(' ');
  final word = 'שלום';
  final codes = word.runes.map((r) => letters.indexOf(r) + 1);
  final content = StringBuffer('BT /F1 36 Tf\n');
  var x = 400.0;
  for (final code in codes) {
    x -= 20;
    content.write(
      '1 0 0 1 $x 700 Tm (\\${code.toRadixString(8).padLeft(3, '0')}) Tj\n',
    );
  }
  content.write('ET');

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /TrueType /BaseFont /$fontName /FirstChar 0 '
        '/LastChar 255 /Widths [${List.filled(256, '500').join(' ')}] '
        '/Encoding << /Type /Encoding /BaseEncoding /WinAnsiEncoding '
        '/Differences [1 $diffs] >> /FontDescriptor 6 0 R >>',
    '<< /Type /FontDescriptor /FontName /$fontName /Flags 32 '
        '/FontBBox [0 -250 1000 850] /ItalicAngle 0 /Ascent 750 '
        '/Descent -250 /CapHeight 700 /StemV 80 >>',
  ];

  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return latin1.encode(out.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria-pdf-font-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => switch (call.method) {
            'getTemporaryDirectory' => tempDir.path,
            _ => null,
          },
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('familyFromPdfFace מסיר קידומת subset וסיומת סגנון', () {
    expect(PdfFontFallback.familyFromPdfFace('David'), 'David');
    expect(PdfFontFallback.familyFromPdfFace('David-Bold'), 'David');
    expect(
      PdfFontFallback.familyFromPdfFace('ABCDEF+Narkisim,Bold'),
      'Narkisim',
    );
  });

  testWidgets(
    'גופן עברי שאינו מוטמע: בלי גופן חלופי האותיות נעלמות, ואיתו הן נחלצות',
    (tester) async {
      await tester.runAsync(() async {
        await pdfrxFlutterInitialize();
        final path = '${tempDir.path}/non_embedded.pdf';
        File(path).writeAsBytesSync(
          _nonEmbeddedHebrewPdf('OtzariaTestHebrewFace'),
        );

        final plain = await PdfDocument.openFile(path);
        final plainText = (await plain.pages[0].loadStructuredText()).fullText;
        await plain.dispose();
        expect(plainText, isNot(contains('שלום')));

        final fixed = await PdfFontFallback.openFile(path);
        final fixedText = (await fixed.pages[0].loadStructuredText()).fullText;
        await fixed.dispose();
        expect(fixedText, contains('שלום'));
      });
    },
  );

  testWidgets('מסמכים מקבילים משתפים רישום גופן וכולם נפתחים מחדש', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      const count = 10;
      final paths = [
        for (var i = 0; i < count; i++) '${tempDir.path}/shared-$i.pdf',
      ];
      final bytes = _nonEmbeddedHebrewPdf('OtzariaSharedHebrewFace');
      for (final path in paths) {
        await File(path).writeAsBytes(bytes);
      }
      final original = PdfrxEntryFunctions.instance;
      final backend = _ConcurrentFontBackend(original, count);
      PdfrxEntryFunctions.instance = backend;
      try {
        final documents = await Future.wait([
          for (final path in paths) PdfFontFallback.openFile(path),
        ]);
        expect(backend.registrations, 1);
        expect(backend.reloads, 1);
        final originals = backend.opened.take(count).toSet();
        final reopened = documents.where((doc) => !originals.contains(doc));
        expect(reopened, isNotEmpty);
        final reference = await _renderHebrew(reopened.first);
        final observations = <Map<String, Object>>[];
        for (final document in documents) {
          final text = (await document.pages[0].loadStructuredText()).fullText;
          final raster = await _renderHebrew(document);
          observations.add({
            'text': text,
            'inkPixels': raster.inkPixels,
            'reopened': !originals.contains(document),
            'matchesReopenedRaster':
                raster.pixels.length == reference.pixels.length &&
                Iterable.generate(raster.pixels.length).every(
                  (index) => raster.pixels[index] == reference.pixels[index],
                ),
          });
        }
        // ignore: avoid_print
        print(
          'PDF_SHARED_FONT_NATIVE ${jsonEncode({'opens': backend.opened.length, 'registrations': backend.registrations, 'reloads': backend.reloads, 'documents': observations})}',
        );
        expect(
          observations.map((row) => row['text']),
          everyElement(contains('שלום')),
        );
        expect(
          observations.map((row) => row['inkPixels']),
          everyElement(greaterThan(100)),
        );
        expect(
          observations.map((row) => row['matchesReopenedRaster']),
          everyElement(isTrue),
        );
        expect(backend.opened.length, count * 2);
        expect(backend.opened.take(count).every((doc) => doc.disposed), isTrue);
        expect(
          backend.opened.skip(count).every((doc) => !doc.disposed),
          isTrue,
        );
        expect(documents.toSet(), hasLength(count));
      } finally {
        for (final document in backend.opened) {
          if (!document.disposed) await document.dispose();
        }
        PdfrxEntryFunctions.instance = original;
      }
    });
  });
}

Future<({Uint8List pixels, int inkPixels})> _renderHebrew(
  PdfDocument document,
) async {
  final image = await document.pages[0].render(
    x: 300,
    y: 95,
    width: 140,
    height: 80,
    backgroundColor: 0xffffffff,
  );
  if (image == null) throw StateError('PDFium did not render the Hebrew text');
  try {
    final pixels = Uint8List.fromList(image.pixels);
    var inkPixels = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      final darkness =
          (765 - pixels[i] - pixels[i + 1] - pixels[i + 2]) * pixels[i + 3];
      if (darkness > 3 * 15 * 255) inkPixels++;
    }
    return (pixels: pixels, inkPixels: inkPixels);
  } finally {
    image.dispose();
  }
}

class _ConcurrentFontBackend implements PdfrxEntryFunctions {
  _ConcurrentFontBackend(this.base, this.initialDocuments);

  final PdfrxEntryFunctions base;
  final int initialDocuments;
  final opened = <_ObservedFontDocument>[];
  final _openedInitial = Completer<void>();
  int registrations = 0;
  int reloads = 0;

  @override
  PdfrxBackendType get backendType => base.backendType;

  @override
  Future<void> init() => base.init();

  @override
  Future<T> suspendPdfiumWorkerDuringAction<T>(FutureOr<T> Function() action) =>
      base.suspendPdfiumWorkerDuringAction(action);

  @override
  Future<R> compute<M, R>(FutureOr<R> Function(M) callback, M message) =>
      base.compute(callback, message);

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async {
    try {
      final document = _ObservedFontDocument(
        await base.openFile(
          filePath,
          passwordProvider: passwordProvider,
          firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
          useProgressiveLoading: useProgressiveLoading,
        ),
      );
      opened.add(document);
      if (opened.length == initialDocuments && !_openedInitial.isCompleted) {
        _openedInitial.complete();
      }
      await _openedInitial.future;
      return document;
    } catch (_) {
      if (!_openedInitial.isCompleted) _openedInitial.complete();
      rethrow;
    }
  }

  @override
  Future<void> configureFontEnvironment({
    String? fontCachePath,
    List<String> fontPaths = const [],
  }) => base.configureFontEnvironment(
    fontCachePath: fontCachePath,
    fontPaths: fontPaths,
  );

  @override
  Future<void> addFontData({
    required String face,
    required Uint8List data,
    String? resolvedFace,
  }) async {
    registrations++;
    // כל המסמכים המקוריים מספיקים לדווח על הגופן לפני הרישום הראשון.
    await Future<void>.delayed(Duration.zero);
    await base.addFontData(face: face, data: data, resolvedFace: resolvedFace);
  }

  @override
  Future<void> addFontFile({
    required String face,
    required String filePath,
    String? resolvedFace,
  }) async {
    registrations++;
    await Future<void>.delayed(Duration.zero);
    await base.addFontFile(
      face: face,
      filePath: filePath,
      resolvedFace: resolvedFace,
    );
  }

  @override
  Future<void> reloadFonts() async {
    reloads++;
    await base.reloadFonts();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedFontDocument extends PdfDocument {
  _ObservedFontDocument(this.base) : super(sourceName: base.sourceName);

  final PdfDocument base;
  bool disposed = false;
  Future<void>? closing;

  @override
  List<PdfPage> get pages => base.pages;

  @override
  Stream<PdfDocumentEvent> get events => base.events;

  @override
  PdfPermissions? get permissions => base.permissions;

  @override
  bool get isEncrypted => base.isEncrypted;

  @override
  Future<void> dispose() => closing ??= base.dispose().then((_) {
    disposed = true;
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
