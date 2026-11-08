import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

/// תמונה של 100×100 עם [dots] פיקסלים בצבע אחר.
Future<Uint8List> _png({int dots = 0, int width = 100}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), 100),
    Paint()..color = Colors.white,
  );
  for (var i = 0; i < dots; i++) {
    canvas.drawRect(
      Rect.fromLTWH(i.toDouble(), 0, 1, 1),
      Paint()..color = Colors.black,
    );
  }
  final image = await recorder.endRecording().toImage(width, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  testWidgets('הסובלנות היא 0.05% מהפיקסלים, וגודל אחר נכשל תמיד', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('otzaria_golden_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/g.png').writeAsBytesSync(await _png());
      final comparator = TolerantGoldenFileComparator(
        Uri.file('${dir.path}/x_test.dart'),
      );
      final golden = Uri.parse('g.png');

      expect(await comparator.compare(await _png(), golden), isTrue);
      // 5 מתוך 10,000 = 0.05%: בגבול.
      expect(await comparator.compare(await _png(dots: 5), golden), isTrue);
      // 6 מתוך 10,000 = 0.06%: מעל.
      await expectLater(
        comparator.compare(await _png(dots: 6), golden),
        throwsA(isA<FlutterError>()),
      );
      await expectLater(
        comparator.compare(await _png(width: 101), golden),
        throwsA(isA<FlutterError>()),
      );
    });
  });
}
