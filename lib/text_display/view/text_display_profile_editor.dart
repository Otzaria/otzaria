import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// עורך פרופיל תצוגה מלא — שורה לכל שדה. משמש את מסך ההגדרות ואת
/// הפופאפ בסרגל הספר, כדי שהמשתמש יראה את אותם פקדים בכל מקום.
class TextDisplayProfileEditor extends StatelessWidget {
  final TextDisplayProfile profile;
  final ValueChanged<TextDisplayProfile> onChanged;

  const TextDisplayProfileEditor({
    super.key,
    required this.profile,
    required this.onChanged,
  });

  /// השורות כרשימה — לשיבוץ ישיר בתוך [SettingsCard] (שמוסיף מפרידים).
  static List<Widget> tiles(
    BuildContext context, {
    required TextDisplayProfile profile,
    required ValueChanged<TextDisplayProfile> onChanged,
  }) {
    final t = context.settingsText;
    final showHide = [
      SegmentOption(value: MarkVisibility.show, label: t('הצג')),
      SegmentOption(value: MarkVisibility.hide, label: t('הסתר')),
    ];
    return [
      SettingsActionTile.segmentedTile<MarkVisibility>(
        icon: OtzariaIcons.alef_niqqud_24_filled,
        title: t('ניקוד'),
        options: showHide,
        currentValue: profile.nikud,
        onChanged: (v) => onChanged(profile.copyWith(nikud: v)),
      ),
      SettingsActionTile.segmentedTile<TeamimVisibility>(
        icon: OtzariaIcons.alef_niqqud_taamim_24_filled,
        title: t('טעמי המקרא'),
        options: [
          SegmentOption(value: TeamimVisibility.show, label: t('הצג')),
          SegmentOption(value: TeamimVisibility.hide, label: t('הסתר')),
          SegmentOption(
            value: TeamimVisibility.followNikud,
            label: t('כמו הניקוד'),
          ),
        ],
        currentValue: profile.teamim,
        onChanged: (v) => onChanged(profile.copyWith(teamim: v)),
      ),
      SettingsActionTile.segmentedTile<MarkVisibility>(
        icon: OtzariaIcons.alef_punctuation_24_filled,
        title: t('סימני פיסוק'),
        options: showHide,
        currentValue: profile.punctuation,
        onChanged: (v) => onChanged(profile.copyWith(punctuation: v)),
      ),
      SettingsActionTile.dropdownTile<HolyNameDisplay>(
        icon: OtzariaIcons.alef_lock_24_filled,
        title: t('שם הוי"ה'),
        entries: [
          AppMenuEntry(value: HolyNameDisplay.asIs, label: t('ככתבו')),
          AppMenuEntry(value: HolyNameDisplay.kufKuf, label: t('יקוק')),
          AppMenuEntry(value: HolyNameDisplay.hehApostrophe, label: t("ה'")),
          AppMenuEntry(value: HolyNameDisplay.doubleYod, label: t('יי')),
        ],
        value: profile.holyName,
        onSelected: (v) {
          if (v != null) onChanged(profile.copyWith(holyName: v));
        },
      ),
      SettingsActionTile.segmentedTile<DivineNamesDisplay>(
        icon: OtzariaIcons.alef_crown_24_filled,
        title: t('שאר שמות הקודש'),
        subtitle: t('אלהים, שדי, צבאות ועוד — בספרים שבהם השמות מסומנים'),
        options: [
          SegmentOption(value: DivineNamesDisplay.asIs, label: t('ככתבם')),
          SegmentOption(
            value: DivineNamesDisplay.substitute,
            label: t('בכינוי'),
          ),
        ],
        currentValue: profile.divineNames,
        onChanged: (v) => onChanged(profile.copyWith(divineNames: v)),
      ),
      SettingsActionTile.segmentedTile<MarkVisibility>(
        icon: OtzariaIcons.alef_1_24_filled,
        title: t('ציוני המפרשים'),
        subtitle: t('אותיות הציון שבטקסט, למשל (א)'),
        options: showHide,
        currentValue: profile.anchorMarkers,
        onChanged: (v) => onChanged(profile.copyWith(anchorMarkers: v)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: tiles(
        context,
        profile: profile,
        onChanged: onChanged,
      ),
    );
  }
}
