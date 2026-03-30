import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// Validator for keyboard shortcuts to detect conflicts
class ShortcutValidator {
  static const Set<Set<String>> _compatibleShortcutGroups = {
    {
      'key-shortcut-add-note',
      'key-shortcut-calendar-toggle-events',
    },
    {
      'key-shortcut-calendar-toggle-times',
      'key-shortcut-shamor-zachor-cycle-filter',
    },
  };

  /// List of all shortcut setting keys
  static const List<String> shortcutKeys = [
    'key-shortcut-open-library-browser',
    'key-shortcut-search-current-window',
    'key-shortcut-open-find-ref',
    'key-shortcut-close-tab',
    'key-shortcut-close-all-tabs',
    'key-shortcut-open-reading-screen',
    'key-shortcut-open-new-search',
    'key-shortcut-open-settings',
    'key-shortcut-open-context-settings',
    'key-shortcut-open-more',
    'key-shortcut-open-bookmarks',
    'key-shortcut-open-history',
    'key-shortcut-switch-workspace',
    'key-shortcut-print',
    // Book view shortcuts
    // [EDITING DISABLED] 'key-shortcut-edit-section',
    'key-shortcut-add-bookmark',
    'key-shortcut-add-note',
    'key-shortcut-toggle-pdf-view',
    // Calendar shortcuts
    'key-shortcut-calendar-toggle-times',
    'key-shortcut-calendar-toggle-events',
    'key-shortcut-calendar-today',
    'key-shortcut-calendar-create-event',
    'key-shortcut-calendar-toggle-view',
    'key-shortcut-shamor-zachor-cycle-filter',
  ];

  /// Default values for shortcuts
  static const Map<String, String> defaultShortcuts = {
    'key-shortcut-open-library-browser': 'ctrl+l',
    'key-shortcut-search-current-window': 'ctrl+f',
    'key-shortcut-open-find-ref': 'ctrl+o',
    'key-shortcut-close-tab': 'ctrl+w',
    'key-shortcut-close-all-tabs': 'ctrl+shift+w',
    'key-shortcut-open-reading-screen': 'ctrl+r',
    'key-shortcut-open-new-search': 'ctrl+q',
    'key-shortcut-open-settings': 'ctrl+comma',
    'key-shortcut-open-context-settings': 'ctrl+shift+comma',
    'key-shortcut-open-more': 'ctrl+m',
    'key-shortcut-open-bookmarks': 'ctrl+shift+b',
    'key-shortcut-open-history': 'ctrl+h',
    // [EDITING DISABLED] 'key-shortcut-edit-section': 'ctrl+e',
    'key-shortcut-print': 'ctrl+p',
    'key-shortcut-add-bookmark': 'ctrl+b',
    'key-shortcut-add-note': 'ctrl+n',
    'key-shortcut-switch-workspace': 'ctrl+k',
    'key-shortcut-toggle-pdf-view': 'ctrl+shift+p',
    // Calendar shortcuts
    'key-shortcut-calendar-toggle-times': 'ctrl+e',
    'key-shortcut-calendar-toggle-events': 'ctrl+n',
    'key-shortcut-calendar-today': 'ctrl+d',
    'key-shortcut-calendar-create-event': 'ctrl+shift+n',
    'key-shortcut-calendar-toggle-view': 'ctrl+shift+e',
    'key-shortcut-shamor-zachor-cycle-filter': 'ctrl+e',
  };

  /// Shortcut names for display
  static const Map<String, String> shortcutNames = {
    'key-shortcut-open-library-browser': 'ספרייה',
    'key-shortcut-search-current-window': 'חיפוש בספר ובחלון הנוכחי',
    'key-shortcut-open-find-ref': 'איתור',
    'key-shortcut-close-tab': 'סגור ספר נוכחי',
    'key-shortcut-close-all-tabs': 'סגור כל הספרים',
    'key-shortcut-open-reading-screen': 'עיון',
    'key-shortcut-open-new-search': 'חלון חיפוש חדש',
    'key-shortcut-open-settings': 'הגדרות',
    'key-shortcut-open-context-settings': 'הגדרות חלון נוכחי',
    'key-shortcut-open-more': 'כלים',
    'key-shortcut-open-bookmarks': 'סימניות',
    'key-shortcut-open-history': 'היסטוריה',
    'key-shortcut-switch-workspace': 'החלף שולחן עבודה',
    'key-shortcut-print': 'הדפסה',
    // Book view shortcuts
    // [EDITING DISABLED] 'key-shortcut-edit-section': 'עריכת קטע',
    'key-shortcut-add-bookmark': 'הוסף סימניה',
    'key-shortcut-add-note': 'הוספת הערה',
    'key-shortcut-toggle-pdf-view': 'החלף מצב תצוגה (PDF/טקסט)',
    // Calendar shortcuts
    'key-shortcut-calendar-toggle-times': 'לוח שנה: פתיחה/סגירה זמני היום',
    'key-shortcut-calendar-toggle-events': 'לוח שנה: פתיחה/סגירה אירועים',
    'key-shortcut-calendar-today': 'לוח שנה: מעבר להיום',
    'key-shortcut-calendar-create-event': 'לוח שנה: יצירת אירוע',
    'key-shortcut-calendar-toggle-view': 'לוח שנה: מעבר בין תצוגות',
    'key-shortcut-shamor-zachor-cycle-filter':
        'שמור וזכור: מעבר בין הסינונים',
  };

  /// Check for conflicts in current shortcuts
  /// Returns a map of conflicting shortcuts: {shortcut: [key1, key2, ...]}
  static Map<String, List<String>> checkConflicts() {
    final Map<String, List<String>> conflicts = {};

    // Build a map of shortcut values to their keys
    final Map<String, List<String>> shortcutToKeys = {};

    for (final key in shortcutKeys) {
      final value = getShortcutValue(key) ?? '';
      if (value.isNotEmpty) {
        shortcutToKeys.putIfAbsent(value, () => []).add(key);
      }
    }

    // Find conflicts (shortcuts used by more than one action)
    for (final entry in shortcutToKeys.entries) {
      final conflictingKeys = entry.value;
      if (conflictingKeys.length > 1 &&
          !_isCompatibleGroup(conflictingKeys.toSet())) {
        conflicts[entry.key] = conflictingKeys;
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
    final value = getShortcutValue(settingKey);
    if (value == null || value.isEmpty) return false;

    final matchingKeys = <String>{};
    for (final key in shortcutKeys) {
      final keyValue = getShortcutValue(key) ?? '';
      if (keyValue == value) {
        matchingKeys.add(key);
      }
    }

    return matchingKeys.length > 1 && !_isCompatibleGroup(matchingKeys);
  }

  /// מחזיר את ערך הקיצור הנוכחי עבור [settingKey] או את ברירת המחדל שלו.
  static String? getShortcutValue(String settingKey) {
    return Settings.getValue<String>(settingKey) ?? defaultShortcuts[settingKey];
  }

  static bool canShareShortcut(String firstKey, String secondKey) {
    if (firstKey == secondKey) return true;

    for (final group in _compatibleShortcutGroups) {
      if (group.contains(firstKey) && group.contains(secondKey)) {
        return true;
      }
    }

    return false;
  }

  static bool _isCompatibleGroup(Set<String> keys) {
    for (final group in _compatibleShortcutGroups) {
      if (group.containsAll(keys)) {
        return true;
      }
    }

    return false;
  }
}
