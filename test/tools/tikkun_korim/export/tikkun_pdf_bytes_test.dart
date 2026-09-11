/// הרכבת ה-PDF הווקטורי: גופן Type0 מוטמע, טקסט אמיתי בכל דף, וקנה מידה
/// משותף לעמודים מקוריים.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_writer.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_vector_ops.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

String? _findNativeLibrary() {
  final name = Platform.isWindows
      ? 'opentype_shaper.dll'
      : Platform.isMacOS
      ? 'libopentype_shaper.dylib'
      : 'libopentype_shaper.so';
  for (final candidate in [
    'build/windows/x64/runner/Debug/$name',
    'C:/opentype_shaper/rust/target/release/$name',
    'C:/opentype_shaper/rust/target/debug/$name',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}

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

void main() {
  final libraryPath = _findNativeLibrary();
  final skip = libraryPath == null ? 'the native shaper is not built' : null;

  setUp(() => ShaperLibrary.path = libraryPath);

  test('המסמך מטמיע גופן Type0 ומכיל דף לכל עמוד שנאסף', () async {
    final writer = TikkunVectorPdfWriter(
      pageSize: TikkunExportPageSize.a4,
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
  }, skip: skip);

  test('גליף רווח נכתב בין מילים שכנות בשורה, ולא בין שורות', () async {
    Future<(int, String)> render(List<TikkunTextOp> texts) async {
      final writer = TikkunVectorPdfWriter(
        pageSize: TikkunExportPageSize.a4,
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
  }, skip: skip);

  test('קנה המידה: עמוד גבוה מהדף מוקטן, ובאיחוד כל העמודים מקבלים אותו', () {
    final writer = TikkunVectorPdfWriter(
      pageSize: TikkunExportPageSize.a4,
      loadFont: _loadTestFont,
    );
    const usableWidth = 595.28 - 2 * kTikkunExportMarginPt;
    const usableHeight = 841.89 - 2 * kTikkunExportMarginPt;

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
}
