import 'dart:typed_data';

import 'api/ocr_models.dart';
import 'api/ocr_service.dart';

/// מימוש stub - מוחזר תמיד כשאין override פרטי.
/// `getAvailability` מחזירה `unsupportedPlatform` ו-`recognizeImage` זורקת.
class StubOcrService implements OcrService {
  const StubOcrService();

  @override
  Future<OcrAvailability> getAvailability() async =>
      OcrAvailability.unsupportedPlatform;

  @override
  Future<OcrResult> recognizeImage(Uint8List imageBytes) async {
    throw const OcrUnsupportedPlatformException();
  }

  @override
  Future<void> dispose() async {}
}

OcrService createOcrService() => const StubOcrService();
