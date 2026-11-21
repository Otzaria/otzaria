import 'dart:async';
import 'dart:isolate';

import 'package:opentype_shaper/opentype_shaper.dart';

Future<void>? _libraryLoad;

/// מחמם את הספרייה באיזולט צדדי ומשתף את הטעינה בין קוראי האיזולט הנוכחי.
Future<void> preloadShaperLibrary() => _libraryLoad ??= _loadShaperLibrary();

Future<void> _loadShaperLibrary() async {
  try {
    await Future<int>.sync(() => Isolate.run(_readAbiVersion));
  } catch (_) {
    _libraryLoad = null;
    rethrow;
  }
}

int _readAbiVersion() => ShaperLibrary.abiVersion;

/// משאיר את שני הגופנים חיים עד לסיום הפעולה, ומשחרר גם יצירה חלקית.
Future<T> withShaperFontPair<T>({
  required ShaperFont Function() createPrimary,
  required ShaperFont Function() createFallback,
  required FutureOr<T> Function(ShaperFont primary, ShaperFont fallback) action,
}) async {
  final primary = createPrimary();
  try {
    final fallback = createFallback();
    try {
      return await action(primary, fallback);
    } finally {
      fallback.dispose();
    }
  } finally {
    primary.dispose();
  }
}
