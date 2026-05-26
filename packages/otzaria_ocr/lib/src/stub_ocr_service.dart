import 'dart:typed_data';

import 'api/ocr_models.dart';
import 'api/ocr_service.dart';

/// מימוש stub - מוחזר תמיד כשאין override פרטי.
/// כל הפעולות מחזירות "לא נתמך".
class StubOcrService implements OcrService {
  const StubOcrService();

  @override
  Future<OcrAvailability> getAvailability() async =>
      OcrAvailability.unsupportedPlatform;

  @override
  Future<void> installModels({
    void Function(OcrInstallProgress progress)? onProgress,
  }) async {
    throw const OcrUnsupportedPlatformException();
  }

  @override
  Future<OcrResult> recognizeImage(Uint8List imageBytes) async {
    throw const OcrUnsupportedPlatformException();
  }

  @override
  Future<void> dispose() async {}
}

OcrService createOcrService() => const StubOcrService();
