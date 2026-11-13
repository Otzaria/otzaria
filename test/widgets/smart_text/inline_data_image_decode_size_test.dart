import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

/// כותרת PNG בלבד (חתימה + IHDR): די כדי לקבוע מידות, בלי פיקסלים.
Uint8List _pngHeader(int width, int height) {
  final bytes = ByteData(33);
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    bytes.setUint8(i, signature[i]);
  }
  bytes.setUint32(8, 13);
  bytes.setUint32(12, 0x49484452); // IHDR
  bytes.setUint32(16, width);
  bytes.setUint32(20, height);
  bytes.setUint8(24, 8);
  bytes.setUint8(25, 6);
  return bytes.buffer.asUint8List();
}

void main() {
  testWidgets('תמונת data: בשורת ספר מפוענחת ברוחב התצוגה ולא ברזולוציה '
      'המלאה (#5033)', (tester) async {
    final dataUri =
        'data:image/png;base64,${base64Encode(_pngHeader(2002, 2826))}';
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: SmartTextWidget(
                    text: '<img alt="" src="$dataUri">',
                    settings: const RenderSettings(fontSize: 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final dpr = tester.view.devicePixelRatio;
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, (400 * dpr).ceil());
    // הפריסה כמו תמונה מלאה שהוקטנה לרוחב: היחס נשמר.
    expect(
      tester.getSize(find.byType(Image)),
      const Size(400, 400 * 2826 / 2002),
    );
  });
}
