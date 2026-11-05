import 'dart:async';

import 'package:opentype_shaper/opentype_shaper.dart';

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
