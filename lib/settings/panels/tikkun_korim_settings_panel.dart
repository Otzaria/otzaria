import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כרטיס "תיקון קוראים" בטאב הכלים — אותם מפתחות של הכרטיס "תוכן ומנהגים"
/// בחלונית ההגדרות של הכלי עצמו.
class TikkunKorimSettingsTab extends StatefulWidget {
  const TikkunKorimSettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'tools.tikkun_korim.startup_mode',
      title: 'פתיחה בהפעלה',
      subtitle: 'פרשת השבוע או המיקום האחרון',
      tab: SettingsTab.tools,
      cardId: 'tools.tikkun_korim',
      keywords: ['תיקון קוראים', 'פתיחה', 'פרשה', 'מיקום אחרון'],
    ),
    SettingsSearchEntry(
      id: 'tools.tikkun_korim.nusach',
      title: 'נוסח הפטרה',
      subtitle: 'אשכנז או ספרדי',
      tab: SettingsTab.tools,
      cardId: 'tools.tikkun_korim',
      keywords: ['תיקון קוראים', 'הפטרה', 'נוסח', 'אשכנז', 'ספרדי'],
    ),
    SettingsSearchEntry(
      id: 'tools.tikkun_korim.nusach_land',
      title: 'מנהג לקריאות חגים ומועדים',
      subtitle: 'ארץ ישראל או חוץ לארץ',
      tab: SettingsTab.tools,
      cardId: 'tools.tikkun_korim',
      keywords: ['תיקון קוראים', 'מנהג', 'ארץ ישראל', 'חוץ לארץ', 'חגים'],
    ),
    SettingsSearchEntry(
      id: 'tools.tikkun_korim.hide_divine_name',
      title: 'הסתרת שם השם',
      subtitle: 'שם השם יוצג בכינוי',
      tab: SettingsTab.tools,
      cardId: 'tools.tikkun_korim',
      keywords: ['תיקון קוראים', 'שם השם', 'הסתרה', 'מופעל', 'לא מופעל'],
    ),
  ];

  @override
  State<TikkunKorimSettingsTab> createState() => _TikkunKorimSettingsTabState();
}

class _TikkunKorimSettingsTabState extends State<TikkunKorimSettingsTab> {
  late String startupMode;
  late String nusach;
  late String nusachLand;
  late bool hideDivineName;

  @override
  void initState() {
    super.initState();
    const defaults = TikkunSettings();
    startupMode =
        Settings.getValue<String>(TikkunSettingsKeys.startupMode) ??
        defaults.startupMode;
    nusach =
        Settings.getValue<String>(TikkunSettingsKeys.nusach) ?? defaults.nusach;
    nusachLand =
        Settings.getValue<String>(TikkunSettingsKeys.nusachLand) ??
        defaults.nusachLand;
    hideDivineName =
        Settings.getValue<bool>(TikkunSettingsKeys.hideDivineName) ??
        defaults.hideDivineName;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          cardId: 'tools.tikkun_korim',
          title: context.settingsText('תיקון קוראים'),
          children: [
            SettingsActionTile.segmentedTile<String>(
              icon: FluentIcons.book_open_24_regular,
              title: context.settingsText('פתיחה בהפעלה'),
              options: [
                SegmentOption(
                  value: 'parasha',
                  label: context.settingsText('פרשת השבוע'),
                ),
                SegmentOption(
                  value: 'lastPosition',
                  label: context.settingsText('מיקום אחרון'),
                ),
              ],
              currentValue: startupMode,
              onChanged: (value) {
                setState(() => startupMode = value);
                Settings.setValue<String>(
                  TikkunSettingsKeys.startupMode,
                  value,
                );
              },
            ),
            SettingsActionTile.segmentedTile<String>(
              rtlIcon: FluentIcons.book_24_regular,
              title: context.settingsText('נוסח הפטרה'),
              options: [
                SegmentOption(
                  value: 'ashkenaz',
                  label: context.settingsText('אשכנז'),
                ),
                SegmentOption(
                  value: 'sephard',
                  label: context.settingsText('ספרדי'),
                ),
              ],
              currentValue: nusach,
              onChanged: (value) {
                setState(() => nusach = value);
                Settings.setValue<String>(TikkunSettingsKeys.nusach, value);
              },
            ),
            SettingsActionTile.segmentedTile<String>(
              icon: FluentIcons.globe_24_regular,
              title: context.settingsText('מנהג לקריאות חגים ומועדים'),
              options: [
                SegmentOption(
                  value: 'israel',
                  label: context.settingsText('ארץ ישראל'),
                ),
                SegmentOption(
                  value: 'diaspora',
                  label: context.settingsText('חוץ לארץ'),
                ),
              ],
              currentValue: nusachLand,
              onChanged: (value) {
                setState(() => nusachLand = value);
                Settings.setValue<String>(TikkunSettingsKeys.nusachLand, value);
              },
            ),
            SettingsActionTile.switchTile(
              icon: FluentIcons.shield_24_regular,
              title: context.settingsText('הסתרת שם השם'),
              subtitle: hideDivineName
                  ? context.settingsText('י-ה-ו-ה יוצג כ-י-ק-ו-ק')
                  : context.settingsText('שם השם יוצג ככתבו'),
              value: hideDivineName,
              onChanged: (value) {
                setState(() => hideDivineName = value);
                Settings.setValue<bool>(
                  TikkunSettingsKeys.hideDivineName,
                  value,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
