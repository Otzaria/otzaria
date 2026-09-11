/// חלונית ההגדרות של "תיקון קוראים".
library;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// גופני אוצריא המוצעים בשני הטורים.
const List<AppMenuEntry<String>> _kOtzariaFontEntries = [
  AppMenuEntry(value: 'System:FrankRuhlCLM', label: 'פרנק רוהל'),
  AppMenuEntry(value: 'System:TaameyDavidCLM', label: 'טעמי דוד'),
  AppMenuEntry(value: 'System:NotoSerifHebrew', label: 'Noto Serif Hebrew'),
  AppMenuEntry(value: 'System:Rubik', label: 'רוביק'),
  AppMenuEntry(value: 'System:KeterYG', label: 'כתר YG'),
];

/// גופני גוטמן אינם מוטמעים; כשאינם מותקנים התווית אומרת זאת, והבחירה בהם
/// נופלת לגופן החלופי.
String _guttmanLabel(String label, bool available) =>
    available ? label : '$label — אינו מותקן';

List<AppMenuEntry<String>> tikkunStamFontEntries() => [
  AppMenuEntry(
    value: 'Klasi',
    label: _guttmanLabel('קלאסי', TikkunStamFonts.stamAvailable),
  ),
  const AppMenuEntry(value: 'Ashkenazi', label: 'אשכנזי (בית יוסף)'),
  const AppMenuEntry(value: 'Sefardi', label: 'ספרדי (וועליש)'),
  ..._kOtzariaFontEntries,
];

/// גופני הסת"ם המוטמעים אינם מוצעים כאן: אין בהם מִתאר לניקוד ולטעמים.
List<AppMenuEntry<String>> tikkunNikudFontEntries() => [
  AppMenuEntry(
    value: 'Standard',
    label: _guttmanLabel('סטנדרטי', TikkunStamFonts.nikudAvailable),
  ),
  ..._kOtzariaFontEntries,
];

const String kTikkunDisclaimer =
    'הבהרה: החישובים, החלוקה לעמודים והמרווחים בין המילים מבוצעים על-ידי '
    'אלגוריתם אוטומטי, ואינם בהכרח תואמים את כללי הסת"ם המדויקים או את חלוקת '
    'הספרים המסורתית. בכל ספק יש להיוועץ בסופר סת"ם.';

/// תוכן חלונית ההגדרות. הגלילה והכותרת מגיעות מהמעטפת (ContextOverlayPanel).
class TikkunSettingsPanel extends StatelessWidget {
  final TikkunSettings settings;
  final ValueChanged<TikkunSettings> onChanged;

  const TikkunSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsCard(
          title: 'תצוגה',
          children: [
            SettingsActionTile.dropdownTile<String>(
              icon: FluentIcons.text_font_24_regular,
              title: 'גופן סת"ם',
              value: settings.stamFont,
              entries: tikkunStamFontEntries(),
              onSelected: (value) =>
                  _emit(settings.copyWith(stamFont: value ?? 'Klasi')),
            ),
            SettingsActionTile.dropdownTile<String>(
              icon: FluentIcons.text_font_24_regular,
              title: 'גופן ניקוד',
              value: settings.nikudFont,
              entries: tikkunNikudFontEntries(),
              onSelected: (value) =>
                  _emit(settings.copyWith(nikudFont: value ?? 'Standard')),
            ),
            _SliderTile(
              icon: FluentIcons.line_horizontal_3_24_regular,
              title: 'מרווח בין שורות',
              value: settings.lineSpacing,
              min: 0.5,
              max: 2.4,
              divisions: 19,
              valueLabel: settings.lineSpacing.toStringAsFixed(1),
              onChanged: (value) => _emit(
                settings.copyWith(
                  lineSpacing: (value * 10).roundToDouble() / 10,
                ),
              ),
            ),
            SettingsActionTile.switchTile(
              icon: FluentIcons.eye_24_regular,
              title: 'הצגת טור הסת"ם',
              subtitle: settings.hideStam
                  ? 'הטור מוסתר — מצב קריאה'
                  : 'הטור מוצג',
              value: !settings.hideStam,
              onChanged: (value) => _emit(settings.copyWith(hideStam: !value)),
            ),
            SettingsActionTile.switchTile(
              icon: FluentIcons.eye_24_regular,
              title: 'הצגת טור המנוקד',
              subtitle: settings.hideNikud
                  ? 'הטור מוסתר — מצב מבחן לקורא'
                  : 'הטור מוצג',
              value: !settings.hideNikud,
              onChanged: (value) => _emit(settings.copyWith(hideNikud: !value)),
            ),
            SettingsActionTile.segmentedTile<bool>(
              icon: FluentIcons.arrow_swap_24_regular,
              title: 'סדר הטורים',
              options: const [
                SegmentOption(value: false, label: 'סת"ם בימין'),
                SegmentOption(value: true, label: 'ניקוד בימין'),
              ],
              currentValue: settings.swapColumns,
              onChanged: (value) =>
                  _emit(settings.copyWith(swapColumns: value)),
            ),
            SettingsActionTile.switchTile(
              icon: FluentIcons.line_horizontal_1_24_regular,
              title: 'קווי הפרדה בין השורות',
              subtitle: settings.hideRowBorders
                  ? 'הקווים לא יוצגו'
                  : 'הקווים יוצגו',
              value: !settings.hideRowBorders,
              onChanged: (value) =>
                  _emit(settings.copyWith(hideRowBorders: !value)),
            ),
            if (settings.isSingleColumn)
              SettingsActionTile.switchTile(
                icon: FluentIcons.align_center_horizontal_24_regular,
                title: 'מרכוז הטור המוצג',
                subtitle: settings.centerSingleColumn
                    ? 'הטור ממורכז ותופס את רוחב העמוד'
                    : 'הטור נשאר במקומו',
                value: settings.centerSingleColumn,
                onChanged: (value) =>
                    _emit(settings.copyWith(centerSingleColumn: value)),
              ),
          ],
        ),
        kSettingsCardSpacing,
        SettingsCard(
          title: 'תוכן ומנהגים',
          children: [
            SettingsActionTile.segmentedTile<String>(
              icon: FluentIcons.book_open_24_regular,
              title: 'פתיחה בהפעלה',
              options: const [
                SegmentOption(value: 'parasha', label: 'פרשת השבוע'),
                SegmentOption(value: 'lastPosition', label: 'מיקום אחרון'),
              ],
              currentValue: settings.startupMode,
              onChanged: (value) =>
                  _emit(settings.copyWith(startupMode: value)),
            ),
            SettingsActionTile.segmentedTile<String>(
              icon: FluentIcons.book_24_regular,
              title: 'נוסח',
              options: const [
                SegmentOption(value: 'ashkenaz', label: 'אשכנז'),
                SegmentOption(value: 'sephard', label: 'ספרדי'),
              ],
              currentValue: settings.nusach,
              onChanged: (value) => _emit(settings.copyWith(nusach: value)),
            ),
            SettingsActionTile.segmentedTile<String>(
              icon: FluentIcons.globe_24_regular,
              title: 'מנהג לקריאות חגים ומועדים',
              options: const [
                SegmentOption(value: 'israel', label: 'ארץ ישראל'),
                SegmentOption(value: 'diaspora', label: 'חוץ לארץ'),
              ],
              currentValue: settings.nusachLand,
              onChanged: (value) => _emit(settings.copyWith(nusachLand: value)),
            ),
            SettingsActionTile.segmentedTile<TikkunDecalogueTaam>(
              icon: FluentIcons.text_font_info_24_regular,
              title: 'טעמי עשרת הדברות',
              subtitle: switch (settings.decalogueTaam) {
                TikkunDecalogueTaam.merged =>
                  'שתי מערכות הטעמים על אותן אותיות',
                TikkunDecalogueTaam.elyon => 'הטעמים שקוראים בהם בציבור',
                TikkunDecalogueTaam.tachton => 'הטעמים שקוראים בהם ביחיד',
              },
              options: const [
                SegmentOption(
                  value: TikkunDecalogueTaam.merged,
                  label: 'משולב',
                ),
                SegmentOption(
                  value: TikkunDecalogueTaam.elyon,
                  label: 'טעם עליון',
                ),
                SegmentOption(
                  value: TikkunDecalogueTaam.tachton,
                  label: 'טעם תחתון',
                ),
              ],
              currentValue: settings.decalogueTaam,
              onChanged: (value) =>
                  _emit(settings.copyWith(decalogueTaam: value)),
            ),
            SettingsActionTile.switchTile(
              icon: FluentIcons.shield_24_regular,
              title: 'הסתרת שם השם',
              subtitle: settings.hideDivineName
                  ? 'י-ה-ו-ה יוצג כ-י-ק-ו-ק'
                  : 'שם השם יוצג ככתבו',
              value: settings.hideDivineName,
              onChanged: (value) =>
                  _emit(settings.copyWith(hideDivineName: value)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                kTikkunDisclaimer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _emit(TikkunSettings updated) => onChanged(updated);
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Row(
        children: [
          Expanded(child: Text(title)),
          Text(valueLabel, style: theme.textTheme.bodySmall),
        ],
      ),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: valueLabel,
        onChanged: onChanged,
      ),
    );
  }
}
