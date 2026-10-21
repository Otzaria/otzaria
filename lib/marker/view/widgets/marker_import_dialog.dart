import 'package:flutter/material.dart';
import 'package:otzaria/marker/services/marker_transfer.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

typedef MarkerImportOptions = ({bool backupFirst, bool importPalette});

/// תצוגה מקדימה של ייבוא: כמה יתווספו, כמה כבר קיימים ומה לא יקושר.
/// מחזיר null בביטול.
Future<MarkerImportOptions?> showMarkerImportDialog(
  BuildContext context, {
  required MarkerImportPreview preview,
  required bool paletteIsDefault,
  bool fromLegacyPlugin = false,
}) async {
  var backupFirst = true;
  // פלטה שהמשתמש כבר עיצב לא תוחלף בלי שביקש.
  var importPalette = preview.palette != null && paletteIsDefault;
  final lines = [
    switch (preview.toAdd) {
      0 => 'אין סימונים חדשים לייבוא.',
      1 => 'יתווסף סימון אחד.',
      final count => 'יתווספו $count סימונים.',
    },
    if (preview.existing == 1) 'סימון אחד כבר קיים וידולג.',
    if (preview.existing > 1) '${preview.existing} כבר קיימים וידולגו.',
    if (preview.deletedSinceImport > 0)
      preview.deletedSinceImport == 1
          ? 'סימון אחד נמחק אחרי ייבוא קודם ולא יוחזר.'
          : '${preview.deletedSinceImport} נמחקו אחרי ייבוא קודם ולא יוחזרו.',
    if (preview.invalid == 1) 'רשומה פגומה אחת לא תיובא.',
    if (preview.invalid > 1) '${preview.invalid} רשומות פגומות לא ייובאו.',
    if (preview.renamedBooks == 1)
      'סימון אחד שייך לספר ששמו השתנה, ויקושר לשם החדש.',
    if (preview.renamedBooks > 1)
      '${preview.renamedBooks} סימונים שייכים לספרים ששמם השתנה, ויקושרו לשם החדש.',
    if (preview.unknownBooks == 1)
      'סימון אחד שייך לספר שאינו בספרייה. הוא יישמר ויוצג כשהספר יתווסף.',
    if (preview.unknownBooks > 1)
      '${preview.unknownBooks} סימונים שייכים לספרים שאינם בספרייה. הם יישמרו '
          'ויוצגו כשהספרים יתווספו.',
  ];
  // אין מה לייבא: הודעה עם כפתור אחד, בלי "ביטול" לצד "סגירה".
  if (preview.toAdd == 0) {
    await showSingleActionDialog(
      context: context,
      title: 'ייבוא סימונים',
      content: lines.join('\n'),
      confirmText: 'סגירה',
    );
    return null;
  }
  final confirmed = await showTwoActionsDialog(
    context: context,
    title: 'ייבוא סימונים',
    content: '',
    confirmText: 'ייבוא',
    customContent: StatefulBuilder(
      // גלילה: בחלון נמוך או בטלפון לרוחב השורות והתיבות אינן נכנסות.
      builder: (context, setState) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in lines) Text(line),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: backupFirst,
              onChanged: (value) => setState(() => backupFirst = value ?? true),
              title: const Text('גיבוי הסימונים הקיימים לפני הייבוא'),
            ),
            if (preview.palette != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: importPalette,
                onChanged: (value) =>
                    setState(() => importPalette = value ?? false),
                title: Text(
                  fromLegacyPlugin
                      ? 'החלפת הצבעים בצבעים של התוסף'
                      : 'החלפת הצבעים בצבעים מהקובץ',
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true) return null;
  return (backupFirst: backupFirst, importPalette: importPalette);
}
