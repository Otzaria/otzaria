/// הרכבת ה-PDF הווקטורי: גופן Type0 מוטמע, טקסט אמיתי בכל דף, וקנה מידה
/// משותף לעמודים מקוריים.
library;

// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:opentype_shaper/src/bindings.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_writer.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_vector_ops.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_vav_ketia.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

/// גופן חופשי שמוטמע בתוכנה — גופני גוטמן קנייניים ואינם בשימוש כאן.
const String _fontPath = 'fonts/tikkun_korim/Ashkenazi-Stam.ttf';

Future<Uint8List?> _loadTestFont(String family, {required bool bold}) async {
  if (bold) return null;
  return File(_fontPath).readAsBytes();
}

TikkunTextOp _text(
  String text, {
  double left = 100,
  double width = 60,
  double baseline = 50,
}) => TikkunTextOp(
  text: text,
  style: const TextStyle(fontFamily: 'AshkenaziStam', fontSize: 25),
  left: left,
  width: width,
  baseline: baseline,
  rtl: true,
);

/// זרמי המסמך, מנופחים חזרה — package:pdf דוחס אותם כברירת מחדל, ולכן זרם
/// התוכן וטבלת ה-ToUnicode אינם קריאים בבייטים עצמם.
List<String> _inflatedStreams(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final streams = <String>[];
  var cursor = 0;
  while (true) {
    final start = text.indexOf('stream', cursor);
    if (start < 0) break;
    final end = text.indexOf('endstream', start);
    if (end < 0) break;
    var from = start + 'stream'.length;
    while (from < end && (bytes[from] == 13 || bytes[from] == 10)) {
      from++;
    }
    try {
      streams.add(
        latin1.decode(
          ZLibCodec().decode(bytes.sublist(from, end)),
          allowInvalid: true,
        ),
      );
    } on FormatException {
      // זרם שאינו דחוס בזליב — אין ממנו צורך כאן.
    }
    cursor = end + 'endstream'.length;
  }
  return streams;
}

/// Number of native registry references left after the Dart owners dispose.
/// A nonzero result means the font's native entry was still allocated.
int _drainUnexpectedNativeReferences(int handle) {
  for (var count = 0; count < 32; count++) {
    final status = ShaperBindings.instance.releaseFont(handle);
    if (status == ShaperStatus.unknownHandle) return count;
    expect(status, ShaperStatus.ok);
  }
  throw StateError('Native font reference count exceeded 32');
}

TikkunVectorPage _ownershipPage() => TikkunVectorPage(
  texts: [_text('בְּרֵאשִׁית')],
  rects: const [],
  width: 400,
  height: 200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final cff in [false, true]) {
    for (final form in TikkunVavKetia.values.where(
      (f) => f.codePoint != null,
    )) {
      test(
        'PDF ${cff ? 'CFF' : 'TTF'}/${form.id} מעתיק וי״ו עברית ולא קוד פרטי',
        () async {
          final bytes = cff
              ? (await rootBundle.load(
                  'packages/otzaria_ashurit/OtzariaAshuritNikud-Regular.otf',
                )).buffer.asUint8List()
              : await File(_fontPath).readAsBytes();
          final writer = TikkunVectorPdfWriter(
            pageFormat: PdfPageFormat.a4,
            loadFont: (_, {required bool bold}) async => bytes,
            fallbackFamilies: const [],
          );
          final shown = 'שלום'.replaceFirst(
            'ו',
            String.fromCharCode(form.codePoint!),
          );
          final pdf = await writer.write([
            TikkunVectorPage(
              texts: [_text(shown)],
              rects: const [],
              width: 400,
              height: 200,
            ),
          ], unifyScale: false);
          final cmap = _inflatedStreams(
            pdf,
          ).where((s) => s.contains('beginbfchar')).join();
          expect(cmap, contains('<05D5>'));
          expect(
            cmap,
            isNot(contains(form.codePoint!.toRadixString(16).toUpperCase())),
          );
        },
      );
    }
  }
  test('המסמך מטמיע גופן Type0 ומכיל דף לכל עמוד שנאסף', () async {
    final writer = TikkunVectorPdfWriter(
      pageFormat: PdfPageFormat.a4,
      loadFont: _loadTestFont,
      fallbackFamilies: const [],
    );
    final page = TikkunVectorPage(
      texts: [_text('בְּרֵאשִׁית'), _text('בָּרָא', baseline: 100)],
      rects: const [
        TikkunRectOp(Rect.fromLTWH(0, 120, 1250, 1), Color(0xFF888888)),
      ],
      width: 1250,
      height: 200,
    );
    final bytes = await writer.write([page, page], unifyScale: false);
    final text = latin1.decode(bytes, allowInvalid: true);

    expect(text, startsWith('%PDF-'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
    expect(text, contains('/Subtype/Type0'));
    expect(text, contains('/CIDFontType2'));
    expect(text, contains('/FontFile2'));
    expect(text, contains('/ToUnicode'));
    // אין תמונות — הטקסט וקטורי.
    expect(text, isNot(contains('/Subtype/Image')));
  });

  test('גליף רווח נכתב בין מילים שכנות בשורה, ולא בין שורות', () async {
    Future<(int, String)> render(List<TikkunTextOp> texts) async {
      final writer = TikkunVectorPdfWriter(
        pageFormat: PdfPageFormat.a4,
        loadFont: _loadTestFont,
        fallbackFamilies: const [],
      );
      final bytes = await writer.write([
        TikkunVectorPage(
          texts: texts,
          rects: const [],
          width: 400,
          height: 200,
        ),
      ], unifyScale: false);
      final streams = _inflatedStreams(bytes);
      return (
        RegExp(
          r'\bTd\b',
        ).allMatches(streams.firstWhere((s) => s.contains('TJ'))).length,
        streams.firstWhere((s) => s.contains('beginbfchar')),
      );
    }

    final first = _text('ברא', left: 200);
    // אותן מילים בשורות נפרדות — בסיס ההשוואה, בלי רווח.
    final (apartCount, apartCmap) = await render([
      first,
      _text('אלהים', left: 100, baseline: 100),
    ]);
    final (sameLineCount, sameLineCmap) = await render([
      first,
      _text('אלהים', left: 100),
    ]);
    // תיבות נוגעות: פיצול כיוון בתוך מילה אחת, לא גבול מילה.
    final (touchingCount, _) = await render([
      first,
      _text('אלהים', left: 160, width: 40),
    ]);

    expect(sameLineCount, apartCount + 1);
    expect(touchingCount, apartCount);
    expect(sameLineCmap, contains('<0020>'));
    expect(apartCmap, isNot(contains('<0020>')));
  });

  test('קנה המידה: עמוד גבוה מהדף מוקטן, ובאיחוד כל העמודים מקבלים אותו', () {
    final writer = TikkunVectorPdfWriter(
      pageFormat: PdfPageFormat.a4,
      loadFont: _loadTestFont,
    );
    final usableWidth = PdfPageFormat.a4.width - 2 * kTikkunExportMarginPt;
    final usableHeight = PdfPageFormat.a4.height - 2 * kTikkunExportMarginPt;

    final wide = TikkunVectorPage(
      texts: const [],
      rects: const [],
      width: 1250,
      height: 500,
    );
    final tall = TikkunVectorPage(
      texts: const [],
      rects: const [],
      width: 1250,
      height: 3000,
    );
    expect(writer.scaleFor(wide), closeTo(usableWidth / 1250, 1e-9));
    expect(writer.scaleFor(tall), closeTo(usableHeight / 3000, 1e-9));
    expect(writer.scaleFor(tall), lessThan(writer.scaleFor(wide)));
  });

  test('ביטול לפני תחילת העבודה נכשל ב-TikkunExportCancelled', () async {
    final exporter = TikkunPdfExporter(
      settings: const TikkunSettings(),
      options: const TikkunExportOptions(),
    )..cancel();

    expect(exporter.isCancelled, isTrue);
    await expectLater(
      exporter.export(const []),
      throwsA(isA<TikkunExportCancelled>()),
    );
  });

  test('ביטול בזמן כתיבת עמוד מפסיק לפני המשך הציור', () async {
    var cancelled = false;
    final writer = TikkunVectorPdfWriter(
      pageFormat: PdfPageFormat.a4,
      loadFont: (family, {required bold}) async {
        cancelled = true;
        return _loadTestFont(family, bold: bold);
      },
      fallbackFamilies: const [],
    );
    final page = TikkunVectorPage(
      texts: [_text('בְּרֵאשִׁית')],
      rects: const [],
      width: 400,
      height: 200,
    );

    await expectLater(
      writer.write(
        [page],
        unifyScale: false,
        throwIfCancelled: () {
          if (cancelled) throw const TikkunExportCancelled();
        },
      ),
      throwsA(isA<TikkunExportCancelled>()),
    );
  });

  test('failed PdfShapedFont construction rolls back the native owner', () async {
    final fontBytes = File(_fontPath).readAsBytesSync();
    final anchor = ShaperFont.register(fontBytes);
    final handle = anchor.handle;
    final failure = StateError('injected PDF font construction failure');
    var builderCalls = 0;
    try {
      final writer = TikkunVectorPdfWriter(
        pageFormat: PdfPageFormat.a4,
        loadFont: (_, {required bool bold}) async => fontBytes,
        fallbackFamilies: const [],
        buildPdfFont: (document, shaper, bytes) {
          builderCalls++;
          expect(shaper.handle, handle);
          expect(bytes, same(fontBytes));
          throw failure;
        },
      );

      await expectLater(
        writer.write([_ownershipPage()], unifyScale: false),
        throwsA(same(failure)),
      );
      expect(builderCalls, 1);
      expect(anchor.shape('בדיקה').glyphCount, greaterThan(0));
    } finally {
      anchor.dispose();
    }
    expect(_drainUnexpectedNativeReferences(handle), 0);
  });

  test('failed second PDF font rolls back while first font is cached', () async {
    final fontBytes = File(_fontPath).readAsBytesSync();
    final anchor = ShaperFont.register(fontBytes);
    final handle = anchor.handle;
    final failure = StateError('second PDF font construction failed');
    var builderCalls = 0;
    try {
      final writer = TikkunVectorPdfWriter(
        pageFormat: PdfPageFormat.a4,
        loadFont: (_, {required bool bold}) async => fontBytes,
        fallbackFamilies: const [],
        buildPdfFont: (document, shaper, bytes) {
          builderCalls++;
          expect(shaper.handle, handle);
          if (builderCalls == 2) throw failure;
          return PdfShapedFont(
            document,
            shaper: shaper,
            fontBytes: bytes,
            textForExtraction: restoreTikkunVavKetiaText,
          );
        },
      );
      final page = TikkunVectorPage(
        texts: [
          _text('בְּרֵאשִׁית'),
          TikkunTextOp(
            text: 'בָּרָא',
            style: const TextStyle(fontFamily: 'second-family', fontSize: 25),
            left: 170,
            width: 60,
            baseline: 50,
            rtl: true,
          ),
        ],
        rects: const [],
        width: 400,
        height: 200,
      );

      await expectLater(
        writer.write([page], unifyScale: false),
        throwsA(same(failure)),
      );
      expect(builderCalls, 2);
      expect(anchor.shape('בדיקה').glyphCount, greaterThan(0));
    } finally {
      anchor.dispose();
    }
    expect(_drainUnexpectedNativeReferences(handle), 0);
  });

  test('native owner survives suspended save and is freed after save throws', () async {
    final fontBytes = File(_fontPath).readAsBytesSync();
    final anchor = ShaperFont.register(fontBytes);
    final handle = anchor.handle;
    final enteredSave = Completer<void>();
    final finishSave = Completer<void>();
    final failure = StateError('injected asynchronous pdf.save failure');
    final writer = TikkunVectorPdfWriter(
      pageFormat: PdfPageFormat.a4,
      loadFont: (_, {required bool bold}) async => fontBytes,
      fallbackFamilies: const [],
      savePdf: (_) async {
        enteredSave.complete();
        await finishSave.future;
        throw failure;
      },
    );

    final pending = writer.write([_ownershipPage()], unifyScale: false);
    try {
      await enteredSave.future.timeout(const Duration(seconds: 15));
      // Drop the independent reference. The writer must now be the only owner
      // keeping the native allocation available during the pending save.
      anchor.dispose();
      final borrowed = ShaperFont.attach(handle);
      try {
        expect(borrowed.shape('בדיקה').glyphCount, greaterThan(0));
      } finally {
        borrowed.dispose();
      }
      finishSave.complete();
      await expectLater(pending, throwsA(same(failure)));
    } finally {
      if (!finishSave.isCompleted) finishSave.complete();
      anchor.dispose();
    }
    expect(_drainUnexpectedNativeReferences(handle), 0);
  });

  test('cancellation after font loading releases every native reference', () async {
    final fontBytes = File(_fontPath).readAsBytesSync();
    final anchor = ShaperFont.register(fontBytes);
    final handle = anchor.handle;
    var registered = false;
    try {
      final writer = TikkunVectorPdfWriter(
        pageFormat: PdfPageFormat.a4,
        loadFont: (_, {required bool bold}) async {
          registered = true;
          return fontBytes;
        },
        fallbackFamilies: const [],
      );
      await expectLater(
        writer.write(
          [_ownershipPage()],
          unifyScale: false,
          throwIfCancelled: () {
            if (registered) throw const TikkunExportCancelled();
          },
        ),
        throwsA(isA<TikkunExportCancelled>()),
      );
      expect(registered, isTrue);
      expect(anchor.shape('בדיקה').glyphCount, greaterThan(0));
    } finally {
      anchor.dispose();
    }
    expect(_drainUnexpectedNativeReferences(handle), 0);
  });

  test('repeated successful PDF exports leave no native font allocation', () async {
    final fontBytes = File(_fontPath).readAsBytesSync();
    for (var cycle = 0; cycle < 8; cycle++) {
      final anchor = ShaperFont.register(fontBytes);
      final handle = anchor.handle;
      var loaded = 0;
      try {
        final writer = TikkunVectorPdfWriter(
          pageFormat: PdfPageFormat.a4,
          loadFont: (_, {required bool bold}) async {
            loaded++;
            return fontBytes;
          },
          fallbackFamilies: const [],
        );
        final pdf = await writer.write(
          [_ownershipPage()],
          unifyScale: false,
        );
        expect(latin1.decode(pdf, allowInvalid: true), startsWith('%PDF-'));
        expect(loaded, 1, reason: 'registration cycle $cycle');
      } finally {
        anchor.dispose();
      }
      expect(
        _drainUnexpectedNativeReferences(handle),
        0,
        reason: 'native registry leak after cycle $cycle',
      );
    }
  });
}
