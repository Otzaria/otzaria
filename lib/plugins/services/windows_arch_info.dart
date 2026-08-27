import 'dart:io';

import 'package:flutter/foundation.dart';

/// זיהוי ארכיטקטורת Windows on ARM — הן ריצה נייטיבית והן אמולציית x64.
///
/// באמולציה WebView2 מסרב ליצור controller במסלול הקומפוזיציה שבו התוספים
/// משתמשים, וכל תוסף עולה ריק. הזיהוי מאפשר להסביר זאת למשתמש, ומשמש גם
/// את מנגנון העדכון לבחירת המתקין המתאים למעבד.
class WindowsArchInfo {
  /// overrides לבדיקות בלבד. העבר `null` לאיפוס.
  static bool? _emulatedOverride;
  static bool? _onArmOverride;

  @visibleForTesting
  static void debugOverrideEmulatedOnArm(bool? value) {
    _emulatedOverride = value;
  }

  @visibleForTesting
  static void debugOverrideWindowsOnArm(bool? value) {
    _onArmOverride = value;
  }

  /// `true` כשהתהליך הנוכחי הוא x64 אך המעבד עצמו ARM64.
  ///
  /// תחת אמולציה Windows מותיר ב-PROCESSOR_ARCHITECTURE את הארכיטקטורה של
  /// התהליך (AMD64) ומוסיף ב-PROCESSOR_ARCHITEW6432 את זו של המעבד (ARM64).
  static bool get isEmulatedOnArm {
    if (_emulatedOverride != null) return _emulatedOverride!;
    if (!Platform.isWindows) return false;
    return resolveEmulatedOnArm(Platform.environment);
  }

  /// `true` על כל מחשב ARM — בין אם התהליך נייטיבי ובין אם מאומל.
  /// זה הקריטריון לבחירת מתקין העדכון: המעבד קובע, לא התהליך הנוכחי.
  static bool get isWindowsOnArm {
    if (_onArmOverride != null) return _onArmOverride!;
    if (!Platform.isWindows) return false;
    return resolveWindowsOnArm(Platform.environment);
  }

  @visibleForTesting
  static bool resolveEmulatedOnArm(Map<String, String> environment) {
    final native = environment['PROCESSOR_ARCHITEW6432']?.toUpperCase();
    if (native == null || native.isEmpty) return false;
    final process = environment['PROCESSOR_ARCHITECTURE']?.toUpperCase();
    return native.startsWith('ARM') &&
        process != null &&
        !process.startsWith('ARM');
  }

  @visibleForTesting
  static bool resolveWindowsOnArm(Map<String, String> environment) {
    final process = environment['PROCESSOR_ARCHITECTURE']?.toUpperCase();
    if (process != null && process.startsWith('ARM')) return true;
    return resolveEmulatedOnArm(environment);
  }
}
