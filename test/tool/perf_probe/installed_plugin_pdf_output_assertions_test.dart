import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/installed_plugin_pdf_fixture.dart';
import '../../../integration_test/support/installed_plugin_pdf_output_assertions.dart';

Future<void> whileReaderFramePending(VoidCallback verify) async {
  final frame = Completer<void>();
  final pending = TestAsyncUtils.guard<void>(() => frame.future);
  try {
    verify();
  } finally {
    frame.complete();
    await pending;
  }
}

Uint8List rasterPixels(int width, int height) {
  final pixels = Uint8List(width * height * 4)
    ..fillRange(0, width * height * 4, 255);
  final dark = ((height - 40) * width + 40) * 4;
  pixels.setRange(dark, dark + 4, [0, 0, 0, 255]);
  return pixels;
}

void main() {
  testWidgets('native result checks complete while a reader frame is pending', (
    tester,
  ) async {
    final size = installedPdfPageSizes.first;
    await whileReaderFramePending(() {
      expectSync(
        () => expect(true, true),
        throwsA(
          isA<FlutterError>().having(
            (error) => error.message,
            'guard remains active',
            contains('Guarded function conflict'),
          ),
        ),
      );
      expectInstalledPdfRasterSupport(true);
      final proof = installedPdfRasterProof(
        size.width,
        size.height,
        rasterPixels(size.width, size.height),
        1,
      );
      expectSync(proof['contentPixelsVerified'], true);
      expectSync(proof['page'], 1);
    });
  });

  testWidgets(
    'invalid native results still fail while a reader frame is pending',
    (
      tester,
    ) async {
      final size = installedPdfPageSizes.first;
      final pixels = rasterPixels(size.width, size.height);
      await whileReaderFramePending(() {
        expectSync(
          () => expectInstalledPdfRasterSupport(false),
          throwsA(isA<TestFailure>()),
        );
        expectSync(
          () => installedPdfRasterProof(size.width + 1, size.height, pixels, 1),
          throwsA(isA<TestFailure>()),
        );
        pixels[(4 * size.width + 4) * 4] = 0;
        expectSync(
          () => installedPdfRasterProof(size.width, size.height, pixels, 1),
          throwsA(isA<TestFailure>()),
        );
      });
    },
  );
}
