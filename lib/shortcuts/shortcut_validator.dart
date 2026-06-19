import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// Validator for keyboard shortcuts to detect conflicts
class ShortcutValidator {
  static const String currentWindowSearchKey =
      'key-shortcut-search-current-window';
  static const String legacySearchInBookKey = 'key-shortcut-search-in-book';

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

  static const Map<String, List<String>> legacyShortcutAliases = {
    currentWindowSearchKey: [legacySearchInBookKey],
  };

  /// קיצורי "פתיחת כלי" אופציונליים (deep-link `otzaria://open/tool/<id>`).
  /// כל מפתח חייב להופיע גם ב-[shortcutKeys], [defaultShortcuts] (ריק), [shortcutNames].
  static const Map<String, String> openToolShortcutKeys = {
    'key-shortcut-open-tool-calendar': 'builtin.calendar',
    'key-shortcut-open-tool-shamor-zachor': 'builtin.shamor_zachor',
    'key-shortcut-open-tool-measurements': 'builtin.measurements',
    'key-shortcut-open-tool-notes': 'builtin.notes',
    'key-shortcut-open-tool-gematria': 'builtin.gematria',
    'key-shortcut-open-tool-aramaic-dictionary': 'builtin.aramaic_dictionary',
    'key-shortcut-open-tool-acronyms-dictionary': 'builtin.acronyms_dictionary',
  };

  /// List of all shortcut setting keys
  static const List<String> shortcutKeys = [
    'key-shortcut-open-library-browser',
    currentWindowSearchKey,
    'key-shortcut-open-find-ref',
    'key-shortcut-close-tab',
    'key-shortcut-close-all-tabs',
    'key-shortcut-restore-closed-tab',
    'key-shortcut-open-reading-screen',
    'key-shortcut-open-new-search',
    'key-shortcut-open-settings',
    'key-shortcut-open-more',
    'key-shortcut-open-bookmarks',
    'key-shortcut-open-history',
    'key-shortcut-add-bookmark',
    'key-shortcut-add-note',
    'key-shortcut-switch-workspace',
    'key-shortcut-print',
    'key-shortcut-toggle-pdf-view',
    'key-shortcut-calendar-toggle-times',
    'key-shortcut-calendar-toggle-events',
    'key-shortcut-calendar-today',
    'key-shortcut-calendar-create-event',
    'key-shortcut-calendar-toggle-view',
    'key-shortcut-shamor-zachor-cycle-filter',
    'key-shortcut-toggle-nav-pane',
    'key-shortcut-toggle-commentators-pane',
    'key-shortcut-open-commentators-tab',
    'key-shortcut-prev-segment',
    'key-shortcut-next-segment',
    'key-shortcut-prev-toc',
    'key-shortcut-next-toc',
    // פתיחת כלים — אופציונלי, ללא ברירת מחדל (ראה openToolShortcutKeys).
    'key-shortcut-open-tool-calendar',
    'key-shortcut-open-tool-shamor-zachor',
    'key-shortcut-open-tool-measurements',
    'key-shortcut-open-tool-notes',
    'key-shortcut-open-tool-gematria',
    'key-shortcut-open-tool-aramaic-dictionary',
    'key-shortcut-open-tool-acronyms-dictionary',
  ];

  /// Default values for shortcuts
  static const Map<String, String> defaultShortcuts = {
    'key-shortcut-open-library-browser': 'ctrl+l',
    currentWindowSearchKey: 'ctrl+f',
    'key-shortcut-open-find-ref': 'ctrl+o',
    'key-shortcut-close-tab': 'ctrl+w',
    'key-shortcut-close-all-tabs': 'ctrl+shift+w',
    'key-shortcut-restore-closed-tab': 'ctrl+shift+t',
    'key-shortcut-open-reading-screen': 'ctrl+r',
    'key-shortcut-open-new-search': 'ctrl+shift+f',
    'key-shortcut-open-settings': 'ctrl+comma',
    'key-shortcut-open-more': 'ctrl+m',
    'key-shortcut-open-bookmarks': 'ctrl+shift+b',
    'key-shortcut-open-history': 'ctrl+h',
    'key-shortcut-add-bookmark': 'ctrl+b',
    'key-shortcut-add-note': 'ctrl+n',
    'key-shortcut-switch-workspace': 'ctrl+k',
    'key-shortcut-print': 'ctrl+p',
    'key-shortcut-toggle-pdf-view': 'ctrl+shift+p',
    'key-shortcut-calendar-toggle-times': 'ctrl+t',
    'key-shortcut-calendar-toggle-events': 'ctrl+e',
    'key-shortcut-calendar-today': 'ctrl+d',
    'key-shortcut-calendar-create-event': 'ctrl+shift+n',
    'key-shortcut-calendar-toggle-view': 'ctrl+shift+e',
    'key-shortcut-shamor-zachor-cycle-filter': 'ctrl+s',
    'key-shortcut-toggle-nav-pane': 'ctrl+shift+l',
    'key-shortcut-toggle-commentators-pane': 'ctrl+shift+c',
    'key-shortcut-open-commentators-tab': '',
    'key-shortcut-prev-segment': 'alt+arrowup',
    'key-shortcut-next-segment': 'alt+arrowdown',
    'key-shortcut-prev-toc': 'alt+pageup',
    'key-shortcut-next-toc': 'alt+pagedown',
    'key-shortcut-open-tool-calendar': '',
    'key-shortcut-open-tool-shamor-zachor': '',
    'key-shortcut-open-tool-measurements': '',
    'key-shortcut-open-tool-notes': '',
    'key-shortcut-open-tool-gematria': '',
    'key-shortcut-open-tool-aramaic-dictionary': '',
    'key-shortcut-open-tool-acronyms-dictionary': '',
  };

  /// Shortcut names for display
  static const Map<String, String> shortcutNames = {
    'key-shortcut-open-library-browser': 'ספרייה',
    currentWindowSearchKey: 'חיפוש בספר הפתוח',
    'key-shortcut-open-find-ref': 'איתור',
    'key-shortcut-close-tab': 'סגור ספר נוכחי',
    'key-shortcut-close-all-tabs': 'סגור כל הספרים',
    'key-shortcut-restore-closed-tab': 'פתח כרטיסייה אחרונה שנסגרה',
    'key-shortcut-open-reading-screen': 'עיון',
    'key-shortcut-open-new-search': 'חיפוש חדש בכל הספרים',
    'key-shortcut-open-settings': 'הגדרות',
    'key-shortcut-open-more': 'כלים',
    'key-shortcut-open-bookmarks': 'סימניות',
    'key-shortcut-open-history': 'היסטוריה',
    'key-shortcut-add-bookmark': 'הוסף סימניה',
    'key-shortcut-add-note': 'הוספת הערה',
    'key-shortcut-switch-workspace': 'החלף שולחן עבודה',
    'key-shortcut-print': 'הדפסה',
    'key-shortcut-toggle-pdf-view': 'החלף מצב תצוגה (PDF/טקסט)',
    'key-shortcut-calendar-toggle-times': 'לוח שנה: פתיחה/סגירה זמני היום',
    'key-shortcut-calendar-toggle-events': 'לוח שנה: פתיחה/סגירה אירועים',
    'key-shortcut-calendar-today': 'לוח שנה: מעבר להיום',
    'key-shortcut-calendar-create-event': 'לוח שנה: יצירת אירוע',
    'key-shortcut-calendar-toggle-view': 'לוח שנה: מעבר בין תצוגות',
    'key-shortcut-shamor-zachor-cycle-filter': 'שמור וזכור: מעבר בין הסינונים',
    'key-shortcut-toggle-nav-pane': 'פתח/סגור חלונית ניווט',
    'key-shortcut-toggle-commentators-pane': 'פתח/סגור חלונית מפרשים',
    'key-shortcut-open-commentators-tab': 'פתח כרטיסיית מפרשים',
    'key-shortcut-prev-segment': 'הקטע הקודם',
    'key-shortcut-next-segment': 'הקטע הבא',
    'key-shortcut-prev-toc': 'הדף/פרק הקודם',
    'key-shortcut-next-toc': 'הדף/פרק הבא',
    'key-shortcut-open-tool-calendar': 'פתיחת לוח שנה',
    'key-shortcut-open-tool-shamor-zachor': 'פתיחת שמור וזכור',
    'key-shortcut-open-tool-measurements': 'פתיחת מדות ושיעורים',
    'key-shortcut-open-tool-notes': 'פתיחת הערות אישיות',
    'key-shortcut-open-tool-gematria': 'פתיחת גימטריה',
    'key-shortcut-open-tool-aramaic-dictionary': 'פתיחת מילון ארמי-עברי',
    'key-shortcut-open-tool-acronyms-dictionary': 'פתיחת ראשי תיבות',
  };

  /// Check for conflicts in current shortcuts
  /// Returns a map of conflicting shortcuts: {shortcut: [key1, key2, ...]}
  static Map<String, List<String>> checkConflicts() {
    final Map<String, List<String>> conflicts = {};
    final Map<String, List<String>> shortcutToKeys = {};

    for (final key in shortcutKeys) {
      final value = getShortcutValue(key) ?? '';
      if (value.isNotEmpty) {
        shortcutToKeys.putIfAbsent(value, () => []).add(key);
      }
    }

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
    final normalizedKey = canonicalSettingKey(settingKey);
    final directValue = Settings.getValue<String>(normalizedKey);
    if (directValue != null && directValue.isNotEmpty) {
      return directValue;
    }

    for (final legacyKey in legacyShortcutAliases[normalizedKey] ?? const []) {
      final legacyValue = Settings.getValue<String>(legacyKey);
      if (legacyValue != null && legacyValue.isNotEmpty) {
        return legacyValue;
      }
    }

    return defaultShortcuts[normalizedKey];
  }

  static bool canShareShortcut(String firstKey, String secondKey) {
    final normalizedFirst = canonicalSettingKey(firstKey);
    final normalizedSecond = canonicalSettingKey(secondKey);
    if (normalizedFirst == normalizedSecond) return true;

    for (final group in _compatibleShortcutGroups) {
      if (group.contains(normalizedFirst) && group.contains(normalizedSecond)) {
        return true;
      }
    }

    return false;
  }

  static String canonicalSettingKey(String settingKey) {
    if (settingKey == legacySearchInBookKey) {
      return currentWindowSearchKey;
    }
    return settingKey;
  }

  static Set<String> legacyKeysFor(String settingKey) {
    final normalizedKey = canonicalSettingKey(settingKey);
    return Set<String>.from(legacyShortcutAliases[normalizedKey] ?? const []);
  }

  static bool _isCompatibleGroup(Set<String> keys) {
    if (keys.length < 2) return false;

    final normalizedKeys = keys.map(canonicalSettingKey).toSet();
    for (final group in _compatibleShortcutGroups) {
      if (group.containsAll(normalizedKeys)) {
        return true;
      }
    }

    return false;
  }
}
