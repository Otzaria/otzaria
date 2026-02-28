import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/bloc/settings_bloc.dart';
import 'package:otzaria/settings/bloc/settings_event.dart';
import 'package:otzaria/utils/shortcut_validator.dart';
import 'package:otzaria/widgets/custom_shortcut_dialog.dart';

/// Custom DropDownSettingsTile that filters out shortcuts already in use
class ShortcutDropDownTile extends StatefulWidget {
  final String settingKey;
  final String title;
  final String selected;
  final Widget? leading;
  final Map<String, String> allShortcuts;

  const ShortcutDropDownTile({
    super.key,
    required this.settingKey,
    required this.title,
    required this.selected,
    required this.allShortcuts,
    this.leading,
  });

  @override
  State<ShortcutDropDownTile> createState() => _ShortcutDropDownTileState();
}

class _ShortcutDropDownTileState extends State<ShortcutDropDownTile> {
  @override
  Widget build(BuildContext context) {
    // Get current value for this setting
    final currentValue =
        Settings.getValue<String>(widget.settingKey) ?? widget.selected;

    // Get all shortcuts that are in use by OTHER settings
    final usedShortcuts = <String>{};
    for (final key in ShortcutValidator.shortcutKeys) {
      if (key != widget.settingKey) {
        // Don't include current setting
        final value = Settings.getValue<String>(key) ??
            ShortcutValidator.defaultShortcuts[key];
        if (value != null && value.isNotEmpty) {
          usedShortcuts.add(value);
        }
      }
    }

    // Filter out shortcuts that are already in use
    final availableShortcuts = <String, String>{};

    // הוספת אופציה להתאמה אישית
    availableShortcuts['__custom__'] = 'התאמה אישית...';

    for (final entry in widget.allShortcuts.entries) {
      // Include if: it's the current value OR it's not used by others
      if (entry.key == currentValue || !usedShortcuts.contains(entry.key)) {
        availableShortcuts[entry.key] = entry.value;
      }
    }

    // If current value is not in available shortcuts (custom shortcut), add it
    if (!availableShortcuts.containsKey(currentValue) &&
        !widget.allShortcuts.containsKey(currentValue)) {
      availableShortcuts[currentValue] =
          currentValue.toUpperCase().replaceAll('+', ' + ');
    }

    return DropDownSettingsTile<String>(
      key: ValueKey('${widget.settingKey}_$currentValue'),
      settingKey: widget.settingKey,
      title: widget.title,
      selected: widget.selected,
      values: availableShortcuts,
      leading: widget.leading,
      onChange: (newValue) async {
        if (!mounted) return;

        final scaffoldMessenger = ScaffoldMessenger.of(context);
        final settingsBloc = context.read<SettingsBloc>();
        String? finalValue = newValue;

        // אם בחרו בהתאמה אישית, פתח את הדיאלוג
        if (newValue == '__custom__') {
          if (!mounted) return;

          final customShortcut = await showDialog<String>(
            context: context,
            builder: (context) => CustomShortcutDialog(
              initialShortcut: currentValue,
            ),
          );

          if (customShortcut != null && customShortcut.isNotEmpty) {
            // שמירת הקיצור המותאם אישית
            await Settings.setValue<String>(widget.settingKey, customShortcut);
            finalValue = customShortcut;
          } else {
            // המשתמש ביטל, אל תמשיך
            finalValue = null;
          }
        }

        if (finalValue == null || !mounted) return;

        // עדכון ה-BLoC
        settingsBloc.add(UpdateShortcut(widget.settingKey, finalValue));

        // בדיקת קונפליקטים
        final conflicts = ShortcutValidator.checkConflicts();
        if (conflicts.isNotEmpty && conflicts.containsKey(finalValue)) {
          final conflictingKeys = conflicts[finalValue]!;
          final conflictingNames = conflictingKeys
              .where((k) => k != widget.settingKey)
              .map((k) => ShortcutValidator.shortcutNames[k] ?? k)
              .join(', ');

          if (conflictingNames.isNotEmpty) {
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text(
                  'אזהרה: קיצור זה כבר בשימוש עבור: $conflictingNames',
                  textDirection: TextDirection.rtl,
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      },
    );
  }
}
