import 'dart:typed_data';

import 'package:zstandard/zstandard.dart';

/// בודק שהספרייה הנייטיבית של zstandard זמינה (dlopen), באותו דפוס כמו
/// [tryInitSearchEngine] ב-search_engine_test_init.dart: `flutter test` לא
/// עובר דרך ה-build הפלטפורמי שמקשר תוספים נייטיביים, כך שה-.so עלול
/// להיעדר; אז מדלגים על טסטים שתלויים בה במקום להיכשל.
Future<bool> tryZstandardAvailable() async {
  try {
    final packed = await Zstandard().compress(Uint8List(1), 1);
    return packed != null;
  } catch (_) {
    return false;
  }
}

const String zstandardSkipReason =
    'הספרייה הנייטיבית של zstandard לא נמצאה — build פלטפורמי דרוש';
