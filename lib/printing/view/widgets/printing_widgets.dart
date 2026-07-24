import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/controls/custom_switch.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// סרגל עליון של דיאלוג ההדפסה — כותרת ממורכזת עם פקדי [leading] בתחילת הסרגל.
class PrintingAppBar extends StatelessWidget {
  final String title;

  /// פקדים בתחילת הסרגל (ימין ב-RTL) — למשל ניווט ובורר עמוד. הכותרת ממורכזת.
  final Widget? leading;

  const PrintingAppBar({
    super.key,
    required this.title,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: NavigationToolbar(
          leading: leading,
          middle: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          centerMiddle: true,
        ),
      ),
    );
  }
}

/// ריפוד אחיד לשורה בכרטיס — מוגדר בתוך כל שורה (ולא על הכרטיס), כדי שהריחוף
/// של שורות אינטראקטיביות (מתגים) ימלא את כל רוחב הכרטיס כמו במסך ההגדרות.
const EdgeInsets kPrintingRowPadding = EdgeInsets.symmetric(
  horizontal: 16,
  vertical: 12,
);

/// כרטיס הגדרות עם כותרת ואייקון מחוץ לכרטיס (בסגנון [SettingsCard]),
/// ו-[children] בתוך [AppCard.section] — מפריד אוטומטית בין השורות.
class PrintingSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const PrintingSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: SettingsCard.titleStyleOf(context)),
            ],
          ),
        ),
        AppCard.section(children: children),
      ],
    );
  }
}

/// שורת הגדרה עם מחוון (Slider) ותצוגת הערך הנוכחי.
class PrintingSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const PrintingSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayValue,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: kPrintingRowPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: Text(
                  displayValue,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

/// שורת הגדרה עם תווית קבועת-רוחב מימין ותוכן (למשל דרופדאון) מתרחב לצידה.
class PrintingDropdownRow extends StatelessWidget {
  final String label;
  final Widget child;

  const PrintingDropdownRow({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: kPrintingRowPadding,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// שורת מתג קומפקטית עם ריחוף על כל רוחב הכרטיס (לחיצה על כל השורה מחליפה).
class PrintingSwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const PrintingSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 2, bottom: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                ),
              ),
            ),
            ExcludeFocus(
              child: CustomSwitch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

/// דרופדאון "כיוון" (לאורך/לרוחב) עם ההתוויות הקבועות של מסך ההדפסה.
class PrintingOrientationDropdownRow extends StatelessWidget {
  final pw.PageOrientation value;
  final ValueChanged<pw.PageOrientation> onChanged;

  const PrintingOrientationDropdownRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PrintingDropdownRow(
      label: 'כיוון',
      child: AppDropdownField<pw.PageOrientation>(
        value: value,
        entries: const [
          AppMenuEntry(
            value: pw.PageOrientation.portrait,
            label: 'לאורך',
          ),
          AppMenuEntry(
            value: pw.PageOrientation.landscape,
            label: 'לרוחב',
          ),
        ],
        onSelected: (pw.PageOrientation? value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

/// דרופדאון "עמודים בגליון" (1/2/4) עם ההתוויות הקבועות של מסך ההדפסה.
class PrintingPagesPerSheetDropdownRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const PrintingPagesPerSheetDropdownRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PrintingDropdownRow(
      label: 'עמודים בגליון',
      child: AppDropdownField<int>(
        value: value,
        entries: const [
          AppMenuEntry(value: 1, label: '1 (רגיל)'),
          AppMenuEntry(value: 2, label: '2 (יישור לימין)'),
          AppMenuEntry(value: 4, label: '4 (יישור לימין)'),
        ],
        onSelected: (int? value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}
