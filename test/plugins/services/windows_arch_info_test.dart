import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/windows_arch_info.dart';

void main() {
  group('WindowsArchInfo.resolveEmulatedOnArm', () {
    test('x64 process on ARM64 machine is detected as emulated', () {
      expect(
        WindowsArchInfo.resolveEmulatedOnArm({
          'PROCESSOR_ARCHITECTURE': 'AMD64',
          'PROCESSOR_ARCHITEW6432': 'ARM64',
        }),
        isTrue,
      );
    });

    test('native x64 machine is not emulated', () {
      expect(
        WindowsArchInfo.resolveEmulatedOnArm({
          'PROCESSOR_ARCHITECTURE': 'AMD64',
        }),
        isFalse,
      );
    });

    test('native ARM64 process is not emulated', () {
      expect(
        WindowsArchInfo.resolveEmulatedOnArm({
          'PROCESSOR_ARCHITECTURE': 'ARM64',
          'PROCESSOR_ARCHITEW6432': 'ARM64',
        }),
        isFalse,
      );
    });

    test('x86 process on x64 machine is not reported as ARM', () {
      expect(
        WindowsArchInfo.resolveEmulatedOnArm({
          'PROCESSOR_ARCHITECTURE': 'x86',
          'PROCESSOR_ARCHITEW6432': 'AMD64',
        }),
        isFalse,
      );
    });

    test('lowercase values are handled', () {
      expect(
        WindowsArchInfo.resolveEmulatedOnArm({
          'PROCESSOR_ARCHITECTURE': 'amd64',
          'PROCESSOR_ARCHITEW6432': 'arm64',
        }),
        isTrue,
      );
    });
  });

  group('WindowsArchInfo.resolveWindowsOnArm', () {
    test('native ARM64 process is on ARM', () {
      expect(
        WindowsArchInfo.resolveWindowsOnArm({
          'PROCESSOR_ARCHITECTURE': 'ARM64',
        }),
        isTrue,
      );
    });

    test('emulated x64 process on ARM64 machine is on ARM', () {
      expect(
        WindowsArchInfo.resolveWindowsOnArm({
          'PROCESSOR_ARCHITECTURE': 'AMD64',
          'PROCESSOR_ARCHITEW6432': 'ARM64',
        }),
        isTrue,
      );
    });

    test('native x64 machine is not on ARM', () {
      expect(
        WindowsArchInfo.resolveWindowsOnArm({
          'PROCESSOR_ARCHITECTURE': 'AMD64',
        }),
        isFalse,
      );
    });
  });
}
