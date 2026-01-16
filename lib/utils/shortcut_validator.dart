import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// Validator for keyboard shortcuts to detect conflicts
class ShortcutValidator {
  /// List of all shortcut setting keys
  static const List<String> shortcutKeys = [
    'key-shortcut-open-library-browser',
    'key-shortcut-open-find-ref',
    'key-shortcut-close-tab',
    'key-shortcut-close-all-tabs',
    'key-shortcut-open-reading-screen',
    'key-shortcut-open-new-search',
    'key-shortcut-open-settings',
    'key-shortcut-open-more',
    'key-shortcut-open-bookmarks',
    'key-shortcut-open-history',
    'key-shortcut-search-in-book',
    'key-shortcut-edit-section',
    'key-shortcut-print',
    'key-shortcut-add-bookmark',
    'key-shortcut-add-note',
    'key-shortcut-switch-workspace',
    'key-shortcut-toggle-pdf-view',
  ];

  /// Default values for shortcuts
  static const Map<String, String> defaultShortcuts = {
    'key-shortcut-open-library-browser': 'ctrl+l',
    'key-shortcut-open-find-ref': 'ctrl+o',
    'key-shortcut-close-tab': 'ctrl+w',
    'key-shortcut-close-all-tabs': 'ctrl+shift+w',
    'key-shortcut-open-reading-screen': 'ctrl+r',
    'key-shortcut-open-new-search': 'ctrl+q',
    'key-shortcut-open-settings': 'ctrl+comma',
    'key-shortcut-open-more': 'ctrl+m',
    'key-shortcut-open-bookmarks': 'ctrl+shift+b',
    'key-shortcut-open-history': 'ctrl+h',
    'key-shortcut-search-in-book': 'ctrl+f',
    'key-shortcut-edit-section': 'ctrl+e',
    'key-shortcut-print': 'ctrl+p',
    'key-shortcut-add-bookmark': 'ctrl+b',
    'key-shortcut-add-note': 'ctrl+n',
    'key-shortcut-switch-workspace': 'ctrl+k',
    'key-shortcut-toggle-pdf-view': 'ctrl+shift+p',
  };

  /// Shortcut names for display
  static const Map<String, String> shortcutNames = {
    'key-shortcut-open-library-browser': 'ספרייה',
    'key-shortcut-open-find-ref': 'איתור',
    'key-shortcut-close-tab': 'סגור ספר נוכחי',
    'key-shortcut-close-all-tabs': 'סגור כל הספרים',
    'key-shortcut-open-reading-screen': 'עיון',
    'key-shortcut-open-new-search': 'חלון חיפוש חדש',
    'key-shortcut-open-settings': 'הגדרות',
    'key-shortcut-open-more': 'כלים',
    'key-shortcut-open-bookmarks': 'סימניות',
    'key-shortcut-open-history': 'היסטוריה',
    'key-shortcut-search-in-book': 'חיפוש בספר',
    'key-shortcut-edit-section': 'עריכת קטע',
    'key-shortcut-print': 'הדפסה',
    'key-shortcut-add-bookmark': 'הוספת סימניה',
    'key-shortcut-add-note': 'הוספת הערה',
    'key-shortcut-switch-workspace': 'החלף שולחן עבודה',
    'key-shortcut-toggle-pdf-view': 'החלף מצב תצוגה (PDF/טקסט)',
  };

  /// Check for conflicts in current shortcuts
  /// Returns a map of conflicting shortcuts: {shortcut: [key1, key2, ...]}
  static Map<String, List<String>> checkConflicts() {
    final Map<String, List<String>> conflicts = {};

    // Build a map of shortcut values to their keys
    final Map<String, List<String>> shortcutToKeys = {};

    for (final key in shortcutKeys) {
      final value =
          Settings.getValue<String>(key) ?? defaultShortcuts[key] ?? '';
      if (value.isNotEmpty) {
        shortcutToKeys.putIfAbsent(value, () => []).add(key);
      }
    }

    // Find conflicts (shortcuts used by more than one action)
    for (final entry in shortcutToKeys.entries) {
      if (entry.value.length > 1) {
        conflicts[entry.key] = entry.value;
      }
    }

    return conflicts;
  }

  /// Get a human-readable description of conflicts
  static String getConflictsDescription() {
    final conflicts = checkConflicts();

    if (conflicts.isEmpty) {
      return 'אין קונפליקטים בקיצורי המקשים';
    }

    final buffer = StringBuffer('נמצאו קונפליקטים בקיצורי המקשים:\n\n');

    for (final entry in conflicts.entries) {
      final shortcut = entry.key;
      final keys = entry.value;

      buffer.writeln('$shortcut משמש עבור:');
      for (final key in keys) {
        final name = shortcutNames[key] ?? key;
        buffer.writeln('  • $name');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Check if a specific shortcut has conflicts
  static bool hasConflict(String settingKey) {
    final value =
        Settings.getValue<String>(settingKey) ?? defaultShortcuts[settingKey];
    if (value == null || value.isEmpty) return false;

    int count = 0;
    for (final key in shortcutKeys) {
      final keyValue =
          Settings.getValue<String>(key) ?? defaultShortcuts[key] ?? '';
      if (keyValue == value) {
        count++;
        if (count > 1) return true;
      }
    }

    return false;
  }
}
