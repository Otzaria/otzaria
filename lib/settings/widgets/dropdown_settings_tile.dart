import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'settings_tile_helpers.dart';

/// שורת הגדרה עם תפריט נפתח (dropdown) — מקבילה ל-[SegmentedSettingsTile].
///
/// Layout רספונסיבי:
/// • רחב (≥ [LayoutBreakpoints.compact]): Row — מידע משמאל, dropdown מימין.
/// • צר: Column — מידע למעלה, dropdown ברוחב מלא למטה.
///
/// דוגמה:
/// ```dart
/// DropdownSettingsTile<MyEnum>(
///   icon: FluentIcons.calendar_24_regular,
///   title: 'בחירת ערך',
///   subtitle: 'תיאור הערך הנוכחי',
///   value: currentValue,
///   entries: const [
///     AppMenuEntry(value: MyEnum.a, label: 'אפשרות א'),
///     AppMenuEntry(value: MyEnum.b, label: 'אפשרות ב'),
///   ],
///   onSelected: (v) { if (v != null) setState(() => currentValue = v); },
/// )
/// ```
class DropdownSettingsTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final T? value;
  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T?> onSelected;
  final bool enableSearch;
  final double minFieldWidth;
  final double maxFieldWidth;

  const DropdownSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.enableSearch = false,
    this.minFieldWidth = 160,
    this.maxFieldWidth = 320,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < LayoutBreakpoints.compact;
          final fieldWidth = isCompact
              ? constraints.maxWidth
              : constraints.maxWidth.clamp(minFieldWidth, maxFieldWidth);

          final field = SizedBox(
            width: fieldWidth,
            child: AppDropdownField<T>(
              value: value,
              enableSearch: enableSearch,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              entries: entries,
              onSelected: onSelected,
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsTileInfo(icon: icon, title: title, subtitle: subtitle),
                const SizedBox(height: 12),
                field,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SettingsTileInfo(
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Align(alignment: Alignment.centerLeft, child: field),
              ),
            ],
          );
        },
      ),
    );
  }
}
