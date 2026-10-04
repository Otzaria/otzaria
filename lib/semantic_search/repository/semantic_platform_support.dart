import 'dart:ffi' show Abi;
import 'dart:io';

/// האם לחיפוש הסמנטי יש backend בפלטפורמה הזו.
///
/// Windows ו-Linux: כן. Android ו-iOS: לא. macOS: רק arm64 מגרסה 14, הדרישה
/// של ONNX Runtime הרשמי. [abi] ו-[macOsVersion] נועדו לבדיקות.
bool isSemanticSearchPlatformSupported({Abi? abi, String? macOsVersion}) {
  final current = abi ?? Abi.current();
  if (current == Abi.windowsX64 ||
      current == Abi.windowsArm64 ||
      current == Abi.linuxX64 ||
      current == Abi.linuxArm64) {
    return true;
  }
  if (current != Abi.macosArm64) return false;
  final version = macOsVersion ?? Platform.operatingSystemVersion;
  final major = int.tryParse(
    RegExp(r'\d+').firstMatch(version)?.group(0) ?? '',
  );
  return major != null && major >= 14;
}
