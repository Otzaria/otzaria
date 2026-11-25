import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'installed_plugin_pdf_fixture.dart';

/// תוצאות native נבדקות גם כשהפריים המקביל של הקורא עוד ממתין.
void expectInstalledPdfRasterSupport(bool canRaster) {
  expectSync(canRaster, true);
}

Map<String, Object?> installedPdfRasterProof(
  int width,
  int height,
  Uint8List pixels,
  int page,
) {
  final size = installedPdfPageSizes[page - 1];
  expectSync((width, height), (size.width, size.height));
  expectSync(pixels, hasLength(width * height * 4));
  final dark = ((height - 40) * width + 40) * 4;
  final light = (4 * width + 4) * 4;
  expectSync(pixels.sublist(dark, dark + 4), [0, 0, 0, 255]);
  expectSync(pixels.sublist(light, light + 4), [255, 255, 255, 255]);
  return {
    'page': page,
    'width': width,
    'height': height,
    'pixelSha256': sha256.convert(pixels).toString(),
    'contentPixelsVerified': true,
  };
}
