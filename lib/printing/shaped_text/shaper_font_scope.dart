import 'dart:async';
import 'dart:isolate';

import 'package:opentype_shaper/opentype_shaper.dart';

Future<void>? _libraryLoad;

/// טוען את ה-DLL של ה-shaper ב-isolate צדדי, פעם אחת בכל תהליך. הטעינה הראשונה
/// נמשכת לפעמים שניות (סריקת אנטי-וירוס), ומה-isolate הראשי היא תוקעת את ה-UI.
Future<void> preloadShaperLibrary() => _libraryLoad ??=
    Isolate.run(_readAbiVersion)
    // שגיאה (ABI שונה) נזרקת שוב בקריאה הרגילה, עם ההודעה של החבילה.
    .then<void>((_) {}, onError: (Object _) {});

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
