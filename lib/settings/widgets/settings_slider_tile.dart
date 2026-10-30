import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// שורת הגדרה עם סליידר: אייקון, כותרת (ותיאור אופציונלי), הערך הנוכחי
/// בתגית בקצה השורה, והסליידר ברוחב מלא מתחת. מקור יחיד לכל הסליידרים במסך
/// ההגדרות, כדי שיראו אותו דבר עם תיאור ובלעדיו.
class SettingsSliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// הערך כפי שמוצג בתגית ובתווית הגרירה.
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const SettingsSliderTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RtlIcon(icon),
            const SizedBox(width: AppTokens.spaceMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.settingTitle),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppTextStyles.settingSubtitle.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.spaceSM),
            MetaChip(label: valueLabel),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}
