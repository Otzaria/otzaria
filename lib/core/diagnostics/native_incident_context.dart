import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// תמונת מצב קצרה לרשומת הקריסה או התקיעה של Windows.
abstract final class NativeIncidentContext {
  static bool _enabled = false;
  static int? _last;
  static final _publish = _lookup();

  /// נקרא אחרי חשיפת החלון. חיפוש סמל ה-FFI נדחה לצילום ההקשר.
  static void enable() => _enabled = !kIsWeb && Platform.isWindows;

  static void update(Map<String, Object?> context, bool semanticsEnabled) {
    if (!_enabled) return;
    final word = encode(context, semanticsEnabled);
    if (word == _last) return;
    _publish?.call(word);
    _last = word;
  }

  static void Function(int)? _lookup() {
    final executable = DynamicLibrary.executable();
    const name = 'OtzariaSetIncidentContext';
    if (!executable.providesSymbol(name)) return null;
    return executable.lookupFunction<Void Function(Uint32), void Function(int)>(
      name,
      isLeaf: true,
    );
  }

  /// שלושה שדות מתחום ערכים קבוע, ודגל נגישות. אין כאן מחרוזות משתמש.
  @visibleForTesting
  static int encode(Map<String, Object?> context, bool semanticsEnabled) {
    final screen = switch (context['screen']) {
      'library' => 1,
      'find' => 2,
      'reading' => 3,
      'search' => 4,
      'settings' => 5,
      _ => 0,
    };
    if (screen == 0) return 0;
    final tab = switch (context['currentTab']) {
      null => 0,
      'TextBookTab' => 1,
      'PdfBookTab' => 2,
      'CommentatorsTab' => 3,
      'PdfCommentatorsTab' => 4,
      'SearchingTab' => 5,
      'ToolTab' => 6,
      'CombinedTab' => 7,
      _ => 8,
    };
    final tabs = context['tabs'];
    final count = tabs is int ? tabs.clamp(0, 0xffff) : 0;
    return screen | (tab << 4) | (semanticsEnabled ? 1 << 8 : 0) | (count << 9);
  }
}
