import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/onnx_runtime_locator.dart';

void main() {
  late Directory root;
  // קווים נטויים קדימה: תקפים גם ב-Windows, ונדרשים לפירוק נתיב posix בבדיקות macOS.
  late String rootPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ort_locator_');
    rootPath = root.path.replaceAll(r'\', '/');
  });

  tearDown(() => root.deleteSync(recursive: true));

  void touch(String relative) {
    File('$rootPath/$relative').createSync(recursive: true);
  }

  test('returns null when the runtime is not bundled', () {
    expect(
      bundledOnnxRuntimePath(executableDir: rootPath, abi: Abi.windowsX64),
      isNull,
    );
  });

  test('finds onnxruntime.dll in its own folder on Windows', () {
    touch('onnxruntime/onnxruntime.dll');
    for (final abi in [Abi.windowsX64, Abi.windowsArm64]) {
      final path = bundledOnnxRuntimePath(executableDir: rootPath, abi: abi);
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(path, endsWith(r'onnxruntime\onnxruntime.dll'));
    }
  });

  test('does not pick up a runtime placed beside the executable', () {
    touch('onnxruntime.dll');
    expect(
      bundledOnnxRuntimePath(executableDir: rootPath, abi: Abi.windowsX64),
      isNull,
    );
  });

  test('finds libonnxruntime.so in its own folder on Linux', () {
    touch('onnxruntime/libonnxruntime.so');
    for (final abi in [Abi.linuxX64, Abi.linuxArm64]) {
      expect(
        bundledOnnxRuntimePath(executableDir: rootPath, abi: abi),
        '$rootPath/onnxruntime/libonnxruntime.so',
      );
    }
  });

  test('finds the dylib in Contents/Frameworks on macOS arm64 only', () {
    touch('Contents/Frameworks/libonnxruntime.dylib');
    final exeDir = '$rootPath/Contents/MacOS';
    expect(
      bundledOnnxRuntimePath(executableDir: exeDir, abi: Abi.macosArm64),
      '$rootPath/Contents/Frameworks/libonnxruntime.dylib',
    );
    expect(
      bundledOnnxRuntimePath(executableDir: exeDir, abi: Abi.macosX64),
      isNull,
    );
  });

  test('returns null on mobile', () {
    touch('onnxruntime/libonnxruntime.so');
    for (final abi in [Abi.androidArm64, Abi.iosArm64]) {
      expect(bundledOnnxRuntimePath(executableDir: rootPath, abi: abi), isNull);
    }
  });
}
