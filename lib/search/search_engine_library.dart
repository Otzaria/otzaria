import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/utils/file/windows_library_preload.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// טעינת ספריית מנוע החיפוש הנייטיבית ואתחול [RustLib] ב-UI isolate.
abstract final class SearchEngineLibrary {
  static Future<void>? _loading;

  /// מאתחל את [RustLib] פעם אחת לתהליך; כל הקוראים חולקים אותו Future.
  static Future<void> ensureLoaded() => _loading ??= loadWith(
    preload: _preloadOnHelperIsolate,
    init: RustLib.init,
  );

  /// טוען את ה-DLL ב-isolate עזר ואז מאתחל; כשל בטעינה המוקדמת אינו סופי.
  @visibleForTesting
  static Future<void> loadWith({
    required Future<void> Function() preload,
    required Future<void> Function() init,
  }) async {
    try {
      await preload();
    } catch (_) {
      // init טוען בעצמו ומדווח על הכשל האמיתי.
    }
    await init();
  }

  static Future<void> _preloadOnHelperIsolate() async {
    if (!Platform.isWindows) return;
    await preloadOnHelperIsolate(
      '${RustLib.kDefaultExternalLibraryLoaderConfig.stem}.dll',
    );
  }

  /// FFI מאפשר ל-GC להמשיך בזמן טעינת ה-DLL; DynamicLibrary.open ברקע עדיין עוצר אותו.
  /// אחרי הטעינה כאן, RustLib.init רק מעלה את מונה ההפניות.
  @visibleForTesting
  static Future<void> preloadOnHelperIsolate(String path) => Isolate.run(() {
    if (!preloadWindowsLibrary(path)) {
      throw StateError('LoadLibraryW("$path") failed');
    }
  });
}
