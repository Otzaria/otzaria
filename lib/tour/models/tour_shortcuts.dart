// לתחזוקת הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tour/models/tour_step.dart';

/// תוויות הניווט עם מפתח ההגדרה של הקיצור של כל אחת. התוויות זהות לאלו
/// שבסרגל הניווט, כדי שהתרגום יהיה אחד.
const List<(String label, String settingKey, String fallback)>
_navigationShortcuts = [
  ('ספרייה', 'key-shortcut-open-library-browser', 'ctrl+l'),
  ('איתור', 'key-shortcut-open-find-ref', 'ctrl+o'),
  ('עיון', 'key-shortcut-open-reading-screen', 'ctrl+r'),
  ('חיפוש', 'key-shortcut-open-new-search', 'ctrl+shift+f'),
  ('כלים', 'key-shortcut-open-more', 'ctrl+m'),
  ('הגדרות', 'key-shortcut-open-settings', 'ctrl+comma'),
];

const Map<TourShortcutHint, (String settingKey, String fallback)>
_singleShortcuts = {
  TourShortcutHint.findRef: ('key-shortcut-open-find-ref', 'ctrl+o'),
  TourShortcutHint.reading: ('key-shortcut-open-reading-screen', 'ctrl+r'),
  TourShortcutHint.search: ('key-shortcut-open-new-search', 'ctrl+shift+f'),
  TourShortcutHint.tools: ('key-shortcut-open-more', 'ctrl+m'),
  TourShortcutHint.settings: ('key-shortcut-open-settings', 'ctrl+comma'),
};

/// הטקסט שממלא את `{shortcut}` בגוף שלב הסיור, או `null` כשאין קיצור.
///
/// [context] - דרוש לתרגום תוויות הניווט לשפת ההגדרות.
String? tourShortcutText(BuildContext context, TourShortcutHint hint) {
  if (hint == TourShortcutHint.none) return null;
  if (hint == TourShortcutHint.mainNavigation) {
    return _navigationShortcuts
        .map(
          (entry) =>
              '${context.settingsText(entry.$1)} '
              '${_read(entry.$2, entry.$3)}',
        )
        .join(' · ');
  }
  final single = _singleShortcuts[hint]!;
  return _read(single.$1, single.$2);
}

String _read(String key, String defaultValue) =>
    _format(Settings.getValue<String>(key) ?? defaultValue);

String _format(String shortcut) => shortcut
    .split('+')
    .map((part) {
      if (part == 'ctrl') return 'Ctrl';
      if (part == 'shift') return 'Shift';
      if (part == 'alt') return 'Alt';
      if (part == 'comma') return ',';
      if (part == 'tab') return 'Tab';
      return part.isEmpty ? part : part[0].toUpperCase() + part.substring(1);
    })
    .join('+');
