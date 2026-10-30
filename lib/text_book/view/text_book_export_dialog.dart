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
  final result = await showTwoActionsDialog(
    context: context,
    title: 'בחירת סוג קובץ',
    icon: FluentIcons.document_arrow_right_24_regular,
    headerBand: true,
    // מוצג דרך customContent, שמחליף את content.
    content: '',
    // רוחב קבוע: AlertDialog מודד רוחב פנימי, ו-segmentedTile בנוי על LayoutBuilder.
    customContent: StatefulBuilder(
      builder: (context, setDialogState) => SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'בחר פורמט לייצוא',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const _SectionLabel('שמות הקודש בקובץ הזה'),
            const SizedBox(height: 6),
            ListDialogCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsActionTile.dropdownTile<HolyNameDisplay>(
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
                    SettingsActionTile.segmentedTile<DivineNamesDisplay>(
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
          ],
        ),
      ),
    ),
    cancelText: 'טקסט',
    confirmText: 'Word',
    barrierDismissible: true,
  );

  if (result == null) return null;
  return (
    format: result ? TextBookExportFormat.word : TextBookExportFormat.text,
    holyName: holyName,
    divineNames: divineNames,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
