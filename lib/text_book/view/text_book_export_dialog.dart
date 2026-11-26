import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// סוג הקובץ של ייצוא ספר שלם.
enum TextBookExportFormat {
  word('docx'),
  text('txt');

  final String extension;
  const TextBookExportFormat(this.extension);
}

/// בחירות דיאלוג הייצוא — חלות על הקובץ הזה בלבד, לא על ההגדרות.
typedef TextBookExportChoice = ({
  TextBookExportFormat format,
  HolyNameDisplay holyName,
  DivineNamesDisplay divineNames,
});

/// דיאלוג הייצוא: סוג הקובץ, ושמות הקודש לקובץ הזה. ברירת המחדל מ-[profile]
/// (ערוץ הייצוא); null כשהדיאלוג נסגר בלי בחירה.
Future<TextBookExportChoice?> showTextBookExportDialog(
  BuildContext context, {
  required TextDisplayProfile profile,
  required bool hasDivineNames,
}) async {
  var holyName = profile.holyName;
  var divineNames = profile.divineNames;
  final format = await showChoiceDialog<TextBookExportFormat>(
    context: context,
    title: 'הגדרות ייצוא',
    icon: FluentIcons.document_arrow_right_24_regular,
    size: AppDialogSize.medium,
    // רוחב קבוע: SettingsSegmentedTile בנוי על LayoutBuilder.
    customContent: StatefulBuilder(
      builder: (context, setDialogState) => SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionLabel('שמות הקודש בקובץ הזה'),
            const SizedBox(height: 6),
            AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsDropdownTile<HolyNameDisplay>(
                    icon: OtzariaIcons.alef_lock_24_filled,
                    title: 'שם הוי"ה',
                    entries: const [
                      AppMenuEntry(value: HolyNameDisplay.asIs, label: 'ככתבו'),
                      AppMenuEntry(
                        value: HolyNameDisplay.kufKuf,
                        label: 'יקוק',
                      ),
                      AppMenuEntry(
                        value: HolyNameDisplay.daletDalet,
                        label: 'ידוד',
                      ),
                      AppMenuEntry(
                        value: HolyNameDisplay.hehApostrophe,
                        label: "ה'",
                      ),
                      AppMenuEntry(
                        value: HolyNameDisplay.doubleYod,
                        label: 'יי',
                      ),
                    ],
                    value: holyName,
                    onSelected: (v) {
                      if (v != null) setDialogState(() => holyName = v);
                    },
                  ),
                  if (hasDivineNames) ...[
                    Divider(
                      height: 1,
                      color: listDialogRowDivider(context).color,
                    ),
                    SettingsSegmentedTile<DivineNamesDisplay>(
                      icon: OtzariaIcons.alef_crown_24_filled,
                      title: 'שאר שמות הקודש',
                      options: const [
                        SegmentOption(
                          value: DivineNamesDisplay.asIs,
                          label: 'ככתבם',
                        ),
                        SegmentOption(
                          value: DivineNamesDisplay.substitute,
                          label: 'בכינוי',
                        ),
                      ],
                      currentValue: divineNames,
                      onChanged: (v) => setDialogState(() => divineNames = v),
                    ),
                  ],
                ],
              ),
            ),
            // כפתורי הפורמט (choices) שמתחת הם פעולת הייצוא.
            const SizedBox(height: 16),
            const AppSectionLabel('פורמט ייצוא'),
          ],
        ),
      ),
    ),
    choices: const [
      AppDialogChoice(value: TextBookExportFormat.text, label: 'טקסט'),
      AppDialogChoice(
        value: TextBookExportFormat.word,
        label: 'Word',
        recommended: true,
      ),
    ],
  );

  if (format == null) return null;
  return (
    format: format,
    holyName: holyName,
    divineNames: divineNames,
  );
}
