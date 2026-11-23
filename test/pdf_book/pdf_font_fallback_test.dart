import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_font_fallback.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:pdf/widgets.dart' as pw;
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
    'גופן עברי שאינו מוטמע: גופן חלופי מחזיר חילוץ ורינדור של האותיות',
    (tester) async {
      await tester.runAsync(() async {
        await pdfrxFlutterInitialize();
        final path = '${tempDir.path}/non_embedded.pdf';
        File(path).writeAsBytesSync(
          _nonEmbeddedHebrewPdf('OtzariaTestHebrewFace'),
        );

        final plain = await PdfDocument.openFile(path);
        await _printNativeFontEnvironment();
        final plainText = (await plain.pages[0].loadStructuredText()).fullText;
        final plainRaster = await _renderHebrew(plain);
        await plain.dispose();
        expect(plainText, isNot(contains('שלום')));

        final fixed = await PdfFontFallback.openFile(path);
        final fixedText = (await fixed.pages[0].loadStructuredText()).fullText;
        final fixedRaster = await _renderHebrew(fixed);
        await fixed.dispose();
        // ignore: avoid_print
        print(
          'PDF_SINGLE_FONT_NATIVE ${jsonEncode({'plainText': plainText, 'plainRaster': plainRaster.diagnostics, 'fixedText': fixedText, 'fixedRaster': fixedRaster.diagnostics})}',
        );
        expect(fixedText, contains('שלום'));
        expect(fixedRaster.inkPixels, greaterThan(100));
      });
    },
  );

  testWidgets('מסמכים מקבילים משתפים רישום גופן וכולם נפתחים מחדש', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      const count = 10;
      const face = 'OtzariaSharedHebrewFace';
      final paths = [
        for (var i = 0; i < count; i++) '${tempDir.path}/shared-$i.pdf',
      ];
      final bytes = _nonEmbeddedHebrewPdf(face);
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
        expect(backend.registrationSources.single['kind'], 'data');
        expect(backend.registrationSources.single['resolvedFace'], 'Tinos');
        expect(
          backend.opened
              .take(count)
              .expand((doc) => doc.missingQueries)
              .any(
                (query) =>
                    query.face == face &&
                    query.charset == PdfFontCharset.ansi &&
                    query.isFixed,
              ),
          isTrue,
          reason: 'The real query must exercise the fixed-pitch ANSI fallback',
        );
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
            'raster': raster.diagnostics,
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
          'PDF_SHARED_FONT_NATIVE ${jsonEncode({'opens': backend.opened.length, 'registrations': backend.registrations, 'registrationSources': backend.registrationSources, 'reloads': backend.reloads, 'documents': observations})}',
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

  for (final memoryFirst in [true, false]) {
    testWidgets('PDF להדפסה משתתף בגילוי גופנים (memoryFirst=$memoryFirst)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await pdfrxFlutterInitialize();
        final font = pw.Font.ttf(
          await rootBundle.load(PdfFontFallback.bundledFallbackAsset),
        );
        final pdf = pw.Document()
          ..addPage(
            pw.Page(
              build: (_) => pw.Text(
                'שלום',
                textDirection: pw.TextDirection.rtl,
                style: pw.TextStyle(font: font, fontSize: 36),
              ),
            ),
          );
        final embeddedBytes = await pdf.save();
        final source = PrintPdfSource.data(embeddedBytes);
        const count = 10;
        final face = 'OtzariaMixedHebrewFace$memoryFirst';
        final paths = [
          for (var i = 0; i < count; i++)
            '${tempDir.path}/mixed-$memoryFirst-$i.pdf',
        ];
        for (final path in paths) {
          await File(path).writeAsBytes(_nonEmbeddedHebrewPdf(face));
        }
        final original = PdfrxEntryFunctions.instance;
        final backend = _ConcurrentFontBackend(original, count + 1);
        PdfrxEntryFunctions.instance = backend;
        try {
          late Future<PdfDocument> memory;
          if (memoryFirst) {
            memory = source.open();
            await backend.customReadStarted.future;
          }
          final files = [
            for (final path in paths) PdfFontFallback.openFile(path),
          ];
          if (!memoryFirst) memory = source.open();
          final documents = await Future.wait([...files, memory]);
          final embedded = documents.last;
          final observations = <Map<String, Object>>[];
          for (final document in documents) {
            final text =
                (await document.pages[0].loadStructuredText()).fullText;
            final raster = await _renderHebrew(document);
            observations.add({
              'memory': identical(document, embedded),
              'text': text,
              'inkPixels': raster.inkPixels,
              'raster': raster.diagnostics,
            });
          }
          // ignore: avoid_print
          print(
            'PDF_MIXED_FONT_NATIVE ${jsonEncode({
              'memoryFirst': memoryFirst,
              'opens': backend.opened.length,
              'customOpens': backend.customOpens,
              'registrations': backend.registrations,
              'registrationSources': backend.registrationSources,
              'reloads': backend.reloads,
              'discovery': [
                for (final doc in backend.opened.take(count + 1)) {'source': doc.sourceName, 'faces': doc.missingFaces},
              ],
              'documents': observations,
            })}',
          );
          expect(backend.registrations, 1);
          expect(backend.reloads, 1);
          expect(backend.opened, hasLength(count * 2 + 1));
          expect(backend.customOpens, 1);
          expect(backend.customMemoryLimit, embeddedBytes.length);
          expect(
            backend.opened.take(count + 1).contains(embedded),
            isTrue,
          );
          expect(
            backend.opened
                .take(count + 1)
                .where((doc) => !identical(doc, embedded))
                .every((doc) => doc.disposed),
            isTrue,
          );
          expect(
            observations.map((row) => row['text']),
            everyElement(contains('שלום')),
          );
          expect(
            observations.map((row) => row['inkPixels']),
            everyElement(greaterThan(100)),
          );
          expect(await source.readBytes(), same(embeddedBytes));
        } finally {
          for (final document in backend.opened) {
            if (!document.disposed) await document.dispose();
          }
          PdfrxEntryFunctions.instance = original;
        }
      });
    });
  }

  for (final acceptPassword in [true, false]) {
    testWidgets('הזנת סיסמה אינה חוסמת ספר אחר (accept=$acceptPassword)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await pdfrxFlutterInitialize();
        final lockedPath = '${tempDir.path}/password-$acceptPassword.pdf';
        // אותו PDF עברי, מוצפן באמצעות pypdf 6.21.4 עם סיסמת otzaria-test.
        final encoded = await File(
          'test/fixtures/pdf/password_hebrew.pdf.base64',
        ).readAsString();
        await File(lockedPath).writeAsBytes(
          base64Decode(encoded.replaceAll(RegExp(r'\s+'), '')),
        );
        final peerPath = '${tempDir.path}/password-peer-$acceptPassword.pdf';
        await File(peerPath).writeAsBytes(
          _nonEmbeddedHebrewPdf(
            acceptPassword
                ? 'OtzariaPasswordHebrewFace'
                : 'OtzariaPasswordCancelledPeer',
          ),
        );
        final original = PdfrxEntryFunctions.instance;
        final backend = _ConcurrentFontBackend(original, 1);
        PdfrxEntryFunctions.instance = backend;
        final password = Completer<String?>();
        final prompted = Completer<void>();
        var prompts = 0;
        final held = PdfFontFallback.openFile(
          lockedPath,
          passwordProvider: () {
            prompts++;
            if (!prompted.isCompleted) prompted.complete();
            return password.future;
          },
        ).then<Object>((doc) => doc, onError: (Object error) => error);
        Future<PdfDocument>? peer;
        try {
          await prompted.future.timeout(const Duration(seconds: 5));
          peer = PdfFontFallback.openFile(peerPath);
          final independent = await peer.timeout(const Duration(seconds: 5));
          expect(password.isCompleted, isFalse);
          expect(
            (await independent.pages[0].loadStructuredText()).fullText,
            contains('שלום'),
          );
          expect(
            (await _renderHebrew(independent)).inkPixels,
            greaterThan(100),
          );
          expect(backend.registrations, 1);
          expect(backend.reloads, 1);
          password.complete(acceptPassword ? 'otzaria-test' : null);
          final result = await held;
          if (acceptPassword) {
            expect(result, isA<PdfDocument>());
            final unlocked = result as PdfDocument;
            expect(unlocked.isEncrypted, isTrue);
            expect(
              (await unlocked.pages[0].loadStructuredText()).fullText,
              contains('שלום'),
            );
            expect((await _renderHebrew(unlocked)).inkPixels, greaterThan(100));
            expect(backend.opened, hasLength(3));
          } else {
            expect(result, isA<PdfPasswordException>());
            final afterCancel = await PdfFontFallback.openFile(peerPath);
            expect(
              (await afterCancel.pages[0].loadStructuredText()).fullText,
              contains('שלום'),
            );
            expect(backend.opened, hasLength(3));
          }
          expect(prompts, 1);
        } finally {
          if (!password.isCompleted) password.complete(null);
          await held;
          try {
            await peer;
          } catch (_) {}
          for (final document in backend.opened) {
            if (!document.disposed) await document.dispose();
          }
          PdfrxEntryFunctions.instance = original;
        }
      });
    });
  }

  testWidgets('רינדור של מסמך חי אינו מאבד גופן של פתיחות חדשות', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final font = pw.Font.ttf(
        await rootBundle.load(PdfFontFallback.bundledFallbackAsset),
      );
      final pdf = pw.Document()
        ..addPage(
          pw.Page(
            build: (_) => pw.Text(
              'שלום',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(font: font, fontSize: 36),
            ),
          ),
        );
      final existing = _ObservedFontDocument(
        await PrintPdfSource.data(await pdf.save()).open(),
      );
      const count = 10;
      var exercisedLiveDrainage = false;
      try {
        // תזמון ה־worker משתנה; כל ניסיון משתמש בשם גופן חדש ובודק את כל התוצאות.
        for (
          var attempt = 0;
          attempt < 8 && !exercisedLiveDrainage;
          attempt++
        ) {
          final face = 'OtzariaLiveRenderHebrewFace$attempt';
          final paths = [
            for (var i = 0; i < count; i++)
              '${tempDir.path}/live-render-$attempt-$i.pdf',
          ];
          for (final path in paths) {
            await File(path).writeAsBytes(_nonEmbeddedHebrewPdf(face));
          }
          final original = PdfrxEntryFunctions.instance;
          final backend = _ConcurrentFontBackend(original, count);
          PdfrxEntryFunctions.instance = backend;
          try {
            final opening = Future.wait([
              for (final path in paths) PdfFontFallback.openFile(path),
            ]);
            // ה־barrier עובר ב־worker אחרי טעינת הקבצים ולפני סיום גילוי העמודים.
            await Future<void>.value();
            await original.compute<int, int>((value) => value, 0);
            final rendering = () async {
              for (var frame = 0; frame < 4; frame++) {
                expect(
                  (await _renderHebrew(existing)).inkPixels,
                  greaterThan(100),
                );
                await Future<void>.delayed(Duration.zero);
              }
            }();
            await Future.wait<void>([opening.then((_) {}), rendering]);
            final documents = await opening;
            final observations = <Map<String, Object>>[];
            for (final document in documents) {
              final text =
                  (await document.pages[0].loadStructuredText()).fullText;
              final raster = await _renderHebrew(document);
              observations.add({
                'text': text,
                'inkPixels': raster.inkPixels,
                'raster': raster.diagnostics,
              });
            }
            exercisedLiveDrainage = existing.missingFaces.contains(face);
            // ignore: avoid_print
            print(
              'PDF_LIVE_RENDER_FONT_NATIVE ${jsonEncode({'attempt': attempt, 'exercisedLiveDrainage': exercisedLiveDrainage, 'liveDocumentFaces': existing.missingFaces, 'opens': backend.opened.length, 'registrations': backend.registrations, 'registrationSources': backend.registrationSources, 'reloads': backend.reloads, 'documents': observations})}',
            );
            expect(
              observations.map((row) => row['text']),
              everyElement(contains('שלום')),
            );
            expect(
              observations.map((row) => row['inkPixels']),
              everyElement(greaterThan(100)),
            );
            expect(backend.opened, hasLength(count * 2));
            expect(backend.registrations, 1);
            expect(backend.reloads, 1);
          } finally {
            for (final document in backend.opened) {
              if (!document.disposed) await document.dispose();
            }
            PdfrxEntryFunctions.instance = original;
          }
        }
        expect(
          exercisedLiveDrainage,
          isTrue,
          reason:
              'A live render must actually receive a missing-font query from a concurrent open',
        );
      } finally {
        await existing.dispose();
      }
    });
  });
}

Future<void> _printNativeFontEnvironment() async {
  final bundled = await rootBundle.load(PdfFontFallback.bundledFallbackAsset);
  final fontBytes = bundled.buffer.asUint8List(
    bundled.offsetInBytes,
    bundled.lengthInBytes,
  );
  final libraries = <Map<String, Object>>[];
  if (Platform.isLinux) {
    final paths = (await File('/proc/self/maps').readAsLines())
        .where((line) => line.contains('/libpdfium.so'))
        .map((line) => line.substring(line.indexOf('/')))
        .toSet();
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      libraries.add({
        'path': path,
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
    }
  }
  // ignore: avoid_print
  print(
    'PDF_FONT_NATIVE_ENV ${jsonEncode({'libraries': libraries, 'fontBytes': fontBytes.length, 'fontSha256': sha256.convert(fontBytes).toString(), 'explicitModulePath': Pdfrx.pdfiumModulePath, 'processGate': Pdfrx.useProcessWidePdfiumGate})}',
  );
}

Future<({Uint8List pixels, int inkPixels, Map<String, int> diagnostics})>
_renderHebrew(
  PdfDocument document,
) async {
  final image = await document.pages[0].render(
    backgroundColor: 0xffffffff,
  );
  if (image == null) throw StateError('PDFium did not render the Hebrew text');
  try {
    final pixels = Uint8List.fromList(image.pixels);
    var inkPixels = 0;
    var minRgb = 255;
    var maxAlpha = 0;
    var nonWhitePixels = 0;
    for (var i = 0; i < pixels.length; i += 4) {
      for (var channel = 0; channel < 3; channel++) {
        if (pixels[i + channel] < minRgb) minRgb = pixels[i + channel];
      }
      if (pixels[i + 3] > maxAlpha) maxAlpha = pixels[i + 3];
      if (pixels[i] != 255 || pixels[i + 1] != 255 || pixels[i + 2] != 255) {
        nonWhitePixels++;
      }
      final darkness =
          (765 - pixels[i] - pixels[i + 1] - pixels[i + 2]) * pixels[i + 3];
      if (darkness > 3 * 15 * 255) inkPixels++;
    }
    return (
      pixels: pixels,
      inkPixels: inkPixels,
      diagnostics: {
        'width': image.width,
        'height': image.height,
        'pixelBytes': pixels.length,
        'minRgb': minRgb,
        'maxAlpha': maxAlpha,
        'nonWhitePixels': nonWhitePixels,
        'inkPixels': inkPixels,
      },
    );
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
  final customReadStarted = Completer<void>();
  int customOpens = 0;
  int? customMemoryLimit;
  int registrations = 0;
  int reloads = 0;
  final registrationSources = <Map<String, Object?>>[];

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
  }) => _record(
    base.openFile(
      filePath,
      passwordProvider: passwordProvider,
      firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
      useProgressiveLoading: useProgressiveLoading,
    ),
  );

  @override
  Future<PdfDocument> openCustom({
    required FutureOr<int> Function(Uint8List buffer, int position, int size)
    read,
    required int fileSize,
    required String sourceName,
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) {
    customOpens++;
    customMemoryLimit = maxSizeToCacheOnMemory;
    return _record(
      base.openCustom(
        read: (buffer, position, size) {
          final result = read(buffer, position, size);
          if (!customReadStarted.isCompleted) customReadStarted.complete();
          return result;
        },
        fileSize: fileSize,
        sourceName: sourceName,
        passwordProvider: passwordProvider,
        firstAttemptByEmptyPassword: firstAttemptByEmptyPassword,
        useProgressiveLoading: useProgressiveLoading,
        maxSizeToCacheOnMemory: maxSizeToCacheOnMemory,
        onDispose: onDispose,
      ),
    );
  }

  Future<PdfDocument> _record(Future<PdfDocument> operation) async {
    try {
      final document = _ObservedFontDocument(await operation);
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
    registrationSources.add({
      'kind': 'data',
      'face': face,
      'resolvedFace': resolvedFace,
      'bytes': data.length,
      'sha256': sha256.convert(data).toString(),
    });
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
    registrationSources.add({
      'kind': 'file',
      'face': face,
      'resolvedFace': resolvedFace,
      'path': filePath,
    });
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
  _ObservedFontDocument(this.base) : super(sourceName: base.sourceName) {
    _observations = base.events.listen((event) {
      if (event is PdfDocumentMissingFontsEvent) {
        missingFaces.addAll(event.missingFonts.map((query) => query.face));
        missingQueries.addAll(event.missingFonts);
      }
    });
  }

  final PdfDocument base;
  final missingFaces = <String>[];
  final missingQueries = <PdfFontQuery>[];
  late final StreamSubscription<PdfDocumentEvent> _observations;
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
  Future<void> dispose() => closing ??= _dispose();

  Future<void> _dispose() async {
    await _observations.cancel();
    await base.dispose();
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
