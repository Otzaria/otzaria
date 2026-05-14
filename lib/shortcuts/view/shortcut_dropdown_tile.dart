import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/shortcuts/view/custom_shortcut_dialog.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// שדה בחירת קיצור דרך שמסנן קיצורים שכבר נמצאים בשימוש.
class ShortcutDropDownTile extends StatefulWidget {
  final String settingKey;
  final String title;
  final String? subtitle;
  final String selected;
  final Widget? leading;
  final Map<String, String> allShortcuts;

  const ShortcutDropDownTile({
    super.key,
    required this.settingKey,
    required this.title,
    this.subtitle,
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
    // האזנה לשינויים בקיצורים — מבטיחה שה-dropdown יציג את הערך החדש
    // מיד לאחר עדכון, ולא רק לאחר מעבר למסך אחר וחזרה.
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) =>
          previous.shortcuts != current.shortcuts,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    // Get current value for this setting
    final currentValue =
        ShortcutValidator.getShortcutValue(widget.settingKey) ?? widget.selected;

    // Get all shortcuts that are in use by OTHER settings
    final usedShortcuts = <String>{};
    for (final key in ShortcutValidator.shortcutKeys) {
      if (key != widget.settingKey &&
          !ShortcutValidator.canShareShortcut(widget.settingKey, key)) {
        // Don't include current setting
        final value = ShortcutValidator.getShortcutValue(key);
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;
          final field = SizedBox(
            width: isCompact ? double.infinity : 220,
            child: AppDropdownField<String>(
              key: ValueKey('${widget.settingKey}_$currentValue'),
              value: currentValue,
              entries: availableShortcuts.entries
                  .map(
                    (entry) => AppMenuEntry<String>(
                      value: entry.key,
                      label: entry.value,
                    ),
                  )
                  .toList(),
              onSelected: _handleSelection,
            ),
          );

          final titleSection = Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: kSettingsTitleStyle,
                        textDirection: TextDirection.rtl,
                      ),
                      if (widget.subtitle != null &&
                          widget.subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle!,
                          style: kSettingsSubtitleStyle,
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [titleSection]),
                const SizedBox(height: 12),
                field,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              titleSection,
              const SizedBox(width: 16),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: field,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleSelection(String? newValue) async {
    if (newValue == null || !mounted) return;

    final currentValue =
        ShortcutValidator.getShortcutValue(widget.settingKey) ?? widget.selected;
    final settingsBloc = context.read<SettingsBloc>();
    String? finalValue = newValue;

    if (newValue == '__custom__') {
      final customShortcut = await showDialog<String>(
        context: context,
        builder: (context) => CustomShortcutDialog(
          initialShortcut: currentValue,
        ),
      );

      if (!mounted) return;

      if (customShortcut != null && customShortcut.isNotEmpty) {
        finalValue = customShortcut;
      } else {
        finalValue = null;
      }
    }

    if (finalValue == null || !mounted) return;

    settingsBloc.add(UpdateShortcut(widget.settingKey, finalValue));

    final conflicts = ShortcutValidator.checkConflicts();
    if (conflicts.isNotEmpty && conflicts.containsKey(finalValue)) {
      final conflictingKeys = conflicts[finalValue]!;
      final conflictingNames = conflictingKeys
          .where((k) => k != widget.settingKey)
          .map((k) => ShortcutValidator.shortcutNames[k] ?? k)
          .join(', ');

      if (conflictingNames.isNotEmpty) {
        UiSnack.showWarning(
          'אזהרה: קיצור זה כבר בשימוש עבור: $conflictingNames',
          duration: const Duration(seconds: 3),
        );
      }
    }
  }
}
