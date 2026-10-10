import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

/// רשימת הקיצורים הדינמיים של המשתמש. נשמרת כ-JSON תחת [settingsKey],
/// ומדווחת ל-[ShortcutValidator] כדי שזיהוי הקונפליקטים ומסך הקיצורים
/// יכירו בה כמו בכל קיצור אחר.
class DynamicShortcutRegistry extends ChangeNotifier {
  static const String settingsKey = 'key-dynamic-shortcuts';
  static const int maxShortcuts = 64;

  static final DynamicShortcutRegistry instance = DynamicShortcutRegistry._();
  DynamicShortcutRegistry._();

  @visibleForTesting
  DynamicShortcutRegistry.forTesting({this.persist = false}) : _loaded = true;

  /// false בבדיקות — בלי Settings.
  bool persist = true;
  bool _loaded = false;
  final List<DynamicShortcut> _shortcuts = [];

  List<DynamicShortcut> get shortcuts {
    _ensureLoaded();
    return List.unmodifiable(_shortcuts);
  }

  DynamicShortcut? byId(String id) {
    _ensureLoaded();
    for (final s in _shortcuts) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// מוסיף או מחליף (לפי id).
  void put(DynamicShortcut shortcut) {
    _ensureLoaded();
    final index = _shortcuts.indexWhere((s) => s.id == shortcut.id);
    if (index >= 0) {
      _shortcuts[index] = shortcut;
    } else {
      if (_shortcuts.length >= maxShortcuts) {
        throw StateError('too many dynamic shortcuts');
      }
      _shortcuts.add(shortcut);
    }
    _commit();
  }

  void remove(String id) {
    _ensureLoaded();
    _shortcuts.removeWhere((s) => s.id == id);
    _commit();
  }

  void clear() {
    _ensureLoaded();
    _shortcuts.clear();
    _commit();
  }

  /// מזהה חדש ייחודי.
  String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// טוען מ-JSON גולמי (לבדיקות ולגיבוי).
  void loadFromJson(String raw) {
    _parse(raw);
    notifyListeners();
  }

  void _parse(String raw) {
    _shortcuts.clear();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final s = DynamicShortcut.fromJson(Map<String, dynamic>.from(item));
            if (s != null) _shortcuts.add(s);
          }
        }
      } catch (_) {
        // JSON פגום — מתחילים מרשימה ריקה.
      }
    }
    _loaded = true;
    _syncValidator();
  }

  String toJsonString() => jsonEncode([for (final s in _shortcuts) s.toJson()]);

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    if (!persist) return;
    // בלי notifyListeners: הטעינה העצלה קורית בתוך build.
    _parse(Settings.getValue<String>(settingsKey) ?? '');
  }

  void _commit() {
    if (persist) {
      Settings.setValue(settingsKey, toJsonString());
    }
    _syncValidator();
    notifyListeners();
  }

  void _syncValidator() {
    ShortcutValidator.registerDynamicShortcuts({
      for (final s in _shortcuts)
        s.settingKey: (label: s.describe(), key: s.key),
    });
  }
}
