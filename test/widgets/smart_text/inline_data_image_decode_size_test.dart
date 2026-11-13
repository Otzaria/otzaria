import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/display_sized_memory_image.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

/// PNG תקין באפור אחיד; דחיסה הופכת אותו לקטן גם במידות של סריקת עמוד.
Uint8List _png(int width, int height) {
  int crc(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final byte in data) {
      c ^= byte;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
    }
    return c ^ 0xFFFFFFFF;
  }

  List<int> u32(int v) => [
    v >> 24 & 0xFF,
    v >> 16 & 0xFF,
    v >> 8 & 0xFF,
    v & 0xFF,
  ];
  List<int> chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    return [...u32(data.length), ...body, ...u32(crc(body))];
  }

  final raw = Uint8List((width + 1) * height);
  for (var row = 0; row < height; row++) {
    raw.fillRange(row * (width + 1) + 1, (row + 1) * (width + 1), 0x80);
  }
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ...chunk('IHDR', [...u32(width), ...u32(height), 8, 0, 0, 0, 0]),
    ...chunk('IDAT', ZLibEncoder().convert(raw)),
    ...chunk('IEND', const []),
  ]);
}

/// JPEG עם Exif: המידות לא נקראות, והתמונה עוברת במסלול הרגיל של fwfh.
Uint8List _exifJpegHeader() => Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0, 0, //
  0xFF, 0xC0, 0x00, 0x11, 0x08, 0x01, 0xE0, 0x02, 0x80, 0x03, 0, 0, 0, 0,
]);

Future<void> _pumpLine(
  WidgetTester tester,
  Uint8List bytes, {
  double width = 400,
  String mime = 'image/png',
}) => tester.pumpWidget(
  MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: width,
              child: SmartTextWidget(
                text: '<img src="data:$mime;base64,${base64Encode(bytes)}">',
                settings: const RenderSettings(fontSize: 20),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// רוחב הפענוח הצפוי: רוחב התצוגה הפיזי, מעוגל למעלה למדרגות של 256.
int _stepped(double physicalWidth) =>
    math.min(2002, (physicalWidth.ceil() / 256).ceil() * 256);

ImageProvider _provider(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).image;

void main() {
  final scan = _png(2002, 2826);

  testWidgets('תמונת data: בשורת ספר מפוענחת ברוחב התצוגה ולא ברזולוציה '
      'המלאה', (tester) async {
    await _pumpLine(tester, scan);
    await tester.pump();

    final dpr = tester.view.devicePixelRatio;
    final provider = _provider(tester);
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).width, _stepped(400 * dpr));
    // הפריסה כמו תמונה מלאה שהוקטנה לרוחב: היחס נשמר.
    expect(
      tester.getSize(find.byType(Image)),
      const Size(400, 400 * 2826 / 2002),
    );
  });

  testWidgets('הגדלת רוחב קטנה אינה מפענחת שוב; מעבר מדרגה כן', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpLine(tester, scan);
    await tester.pump();
    final first = _provider(tester);
    expect((first as ResizeImage).width, 512);

    await _pumpLine(tester, scan, width: 410);
    await tester.pump();
    expect(identical(_provider(tester), first), isTrue);

    await _pumpLine(tester, scan, width: 600);
    await tester.pump();
    expect((_provider(tester) as ResizeImage).width, 768);
  });

  testWidgets('שינוי devicePixelRatio בלי שינוי פריסה מפענח ברוחב החדש', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpLine(tester, scan);
    await tester.pump();
    expect((_provider(tester) as ResizeImage).width, 512);

    tester.view.devicePixelRatio = 2;
    await tester.pump();
    await tester.pump();
    expect((_provider(tester) as ResizeImage).width, 1024);
  });

  testWidgets('תמונה פגומה עם כותרת תקינה מציגה את סימן השגיאה בגודלו', (
    tester,
  ) async {
    await _pumpLine(
      tester,
      Uint8List.fromList([...scan.take(33), ...List.filled(64, 7)]),
    );
    await tester.pump();
    for (var i = 0; i < 5 && find.text('❌').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();
    }

    expect(find.text('❌'), findsOneWidget);
    expect(tester.getSize(find.text('❌')).height, lessThan(100));
  });

  testWidgets('החלפת התמונה באותו State מאפסת שגיאה קודמת', (tester) async {
    Future<void> pumpImage(Uint8List bytes) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            child: DisplaySizedMemoryImage(
              bytes: bytes,
              pixelWidth: 2002,
              pixelHeight: 2826,
              errorBuilder: (_, _, _) => const Text('❌'),
            ),
          ),
        ),
      ),
    );

    await pumpImage(
      Uint8List.fromList([...scan.take(33), ...List.filled(64, 7)]),
    );
    await tester.pump();
    for (var i = 0; i < 5 && find.text('❌').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();
    }
    expect(find.text('❌'), findsOneWidget);

    await pumpImage(scan);
    await tester.pump();
    expect(find.text('❌'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('JPEG עם Exif ממשיך במסלול הרגיל, ברזולוציה מלאה', (
    tester,
  ) async {
    await _pumpLine(tester, _exifJpegHeader(), mime: 'image/jpeg');
    await tester.pump();
    expect(_provider(tester), isA<MemoryImage>());
  });
}
