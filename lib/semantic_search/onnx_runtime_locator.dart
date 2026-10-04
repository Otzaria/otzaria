import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;

/// מחזיר את הנתיב המוחלט של ONNX Runtime שמצורף לאפליקציה, או `null`.
///
/// הנתיב מועבר למנוע כ־`onnxRuntimePath`, ואז זה המקום היחיד שבו הוא מחפש:
/// - Windows: `<תיקיית ה־exe>\onnxruntime\onnxruntime.dll`
/// - Linux: `<תיקיית ה־exe>/onnxruntime/libonnxruntime.so`
/// - macOS: `<app>/Contents/Frameworks/libonnxruntime.dylib`
///
/// מחזיר `null` כשהקובץ חסר, ובפלטפורמה שאין לה גרסה רשמית מתאימה: Android,
/// iOS, ו־macOS שאינו arm64 (הגרסה של Microsoft ל־macOS היא arm64 בלבד).
/// בודק קיום קובץ בצורה סינכרונית, ולכן נקרא רק לפי דרישה ולא בעליית האפליקציה.
///
/// [executableDir] (נתיב מוחלט) ו־[abi] נועדו לבדיקות; ברירת המחדל היא התהליך הנוכחי.
String? bundledOnnxRuntimePath({String? executableDir, Abi? abi}) {
  final currentAbi = abi ?? Abi.current();
  final exeDir = executableDir ?? File(Platform.resolvedExecutable).parent.path;

  final String path;
  if (currentAbi == Abi.windowsX64 || currentAbi == Abi.windowsArm64) {
    path = p.windows.join(exeDir, 'onnxruntime', 'onnxruntime.dll');
  } else if (currentAbi == Abi.linuxX64 || currentAbi == Abi.linuxArm64) {
    path = p.posix.join(exeDir, 'onnxruntime', 'libonnxruntime.so');
  } else if (currentAbi == Abi.macosArm64) {
    // exeDir הוא Contents/MacOS בתוך ה־bundle.
    path = p.posix.join(
      p.posix.dirname(exeDir),
      'Frameworks',
      'libonnxruntime.dylib',
    );
  } else {
    return null;
  }

  return File(path).existsSync() ? path : null;
}
