import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_library.dart';

import '../support/search_engine_test_init.dart';

typedef _GetModuleHandleNative = IntPtr Function(Pointer<Utf16>);
typedef _GetModuleHandle = int Function(Pointer<Utf16>);

bool _isModuleLoaded(String path) {
  final getModuleHandle = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<_GetModuleHandleNative, _GetModuleHandle>(
        'GetModuleHandleW',
      );
  final native = path.toNativeUtf16();
  try {
    return getModuleHandle(native) != 0;
  } finally {
    malloc.free(native);
  }
}

void main() {
  group('loadWith', () {
    test('מאתחל רק אחרי שהטעינה המוקדמת הסתיימה', () async {
      final calls = <String>[];
      await SearchEngineLibrary.loadWith(
        preload: () async {
          await Future<void>.delayed(Duration.zero);
          calls.add('preload');
        },
        init: () async => calls.add('init'),
      );
      expect(calls, ['preload', 'init']);
    });

    test('כשל בטעינה המוקדמת אינו מונע אתחול', () async {
      var initialized = false;
      await SearchEngineLibrary.loadWith(
        preload: () async => throw ArgumentError('not found'),
        init: () async => initialized = true,
      );
      expect(initialized, isTrue);
    });

    test('כשל באתחול מגיע לממתין', () async {
      final failure = StateError('content hash mismatch');
      await expectLater(
        SearchEngineLibrary.loadWith(
          preload: () async {},
          init: () async => throw failure,
        ),
        throwsA(same(failure)),
      );
    });
  });

  test(
    'ה-DLL שנטען ב-isolate עזר נשאר טעון בתהליך אחרי שה-isolate יצא',
    () async {
      final source = searchEngineLoadedLibraryPath!;
      final temp = Directory.systemTemp.createTempSync('otzaria_preload_');
      addTearDown(() {
        try {
          temp.deleteSync(recursive: true);
        } on FileSystemException {
          // ה-DLL טעון עד סוף התהליך.
        }
      });
      // שם ייחודי: מבטיח שאיש בתהליך לא טען את הקובץ לפני הבדיקה.
      final copy = File(source).copySync('${temp.path}\\preload_probe.dll');
      expect(_isModuleLoaded(copy.path), isFalse);

      await SearchEngineLibrary.preloadOnHelperIsolate(copy.path);

      expect(_isModuleLoaded(copy.path), isTrue);
    },
    skip: !Platform.isWindows
        ? 'GetModuleHandleW קיים רק ב-Windows'
        : searchEngineLoadedLibraryPath == null
        ? searchEngineSkipReason
        : false,
  );
}
