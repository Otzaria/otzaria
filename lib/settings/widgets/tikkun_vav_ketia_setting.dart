import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_vav_ketia.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

class TikkunVavKetiaSetting extends StatelessWidget {
  final TikkunVavKetia value;
  final ValueChanged<TikkunVavKetia> onChanged;

  /// הרשימה מתחת לכותרת ולתיאור, בכל רוחב — בחלונית צדדית שניתנת להרחבה.
  final bool stacked;

  const TikkunVavKetiaSetting({
    super.key,
    required this.value,
    required this.onChanged,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) =>
      SettingsActionTile.dropdownTile<TikkunVavKetia>(
        icon: OtzariaIcons.alef_1_24_filled,
        stacked: stacked,
        title: context.settingsText('וי״ו קטיעא'),
        subtitle: context.settingsText('בתיבת שלום; בגופני סת״ם, אשורית וכתר'),
        value: value,
        onSelected: (form) => onChanged(form ?? TikkunVavKetia.auto),
        entries: [
          AppMenuEntry(
            value: TikkunVavKetia.auto,
            label: context.settingsText('לפי המסורת'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.regular,
            label: context.settingsText('רגילה — ללא שינוי'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.small,
            label: context.settingsText('זעירא — כל האות קטנה'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.yod,
            label: context.settingsText('כעין יו״ד'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.short,
            label: context.settingsText('ראש רגיל ורגל מקוצרת'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.split,
            label: context.settingsText('הפסק ישר באמצע'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.splitDiagonal,
            label: context.settingsText('הפסק אלכסוני'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.splitHigh,
            label: context.settingsText('הפסק גבוה'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.shortTail,
            label: context.settingsText('רגל קצרה והמשך נפרד'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.smallTail,
            label: context.settingsText('זעירא והמשך נפרד'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.bridge,
            label: context.settingsText('קטיעה עם חיבור דק'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.bridgeDiagonal,
            label: context.settingsText('קטיעה אלכסונית עם חיבור דק'),
          ),
          AppMenuEntry(
            value: TikkunVavKetia.insetDiagonal,
            label: context.settingsText('חריץ אלכסוני פנימי'),
          ),
        ],
      );
}
