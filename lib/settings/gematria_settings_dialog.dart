import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

/// פונקציה גלובלית להצגת דיאלוג הגדרות גימטריה
/// ניתן לקרוא לה מכל מקום באפליקציה
Future<void> showGematriaSettingsDialog(BuildContext context) async {
  int maxResults = Settings.getValue<int>('key-gematria-max-results') ?? 100;
  bool filterDuplicates =
      Settings.getValue<bool>('key-gematria-filter-duplicates') ?? false;
  bool wholeVerseOnly =
      Settings.getValue<bool>('key-gematria-whole-verse-only') ?? false;
  bool torahOnly = Settings.getValue<bool>('key-gematria-torah-only') ?? false;
  bool useSmallGematria =
      Settings.getValue<bool>('key-gematria-use-small') ?? false;
  bool useFinalLetters =
      Settings.getValue<bool>('key-gematria-use-final-letters') ?? false;
  bool useWithKolel =
      Settings.getValue<bool>('key-gematria-use-with-kolel') ?? false;

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('הגדרות חיפוש גימטריה', textAlign: TextAlign.right),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: Text('מספר תוצאות מקסימלי:'),
              ),
              const SizedBox(height: 8),
              DropdownButton<int>(
                value: maxResults,
                isExpanded: true,
                items: [50, 100, 200, 500, 1000].map((value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text('$value'),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    maxResults = value;
                    Settings.setValue<int>('key-gematria-max-results', value);
                    setDialogState(() {});
                  }
                },
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('סינון תוצאות כפולות',
                    textAlign: TextAlign.right),
                value: filterDuplicates,
                onChanged: (value) {
                  filterDuplicates = value ?? false;
                  Settings.setValue<bool>(
                      'key-gematria-filter-duplicates', filterDuplicates);
                  setDialogState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('חיפוש פסוק שלם בלבד',
                    textAlign: TextAlign.right),
                value: wholeVerseOnly,
                onChanged: (value) {
                  wholeVerseOnly = value ?? false;
                  Settings.setValue<bool>(
                      'key-gematria-whole-verse-only', wholeVerseOnly);
                  setDialogState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title:
                    const Text('חיפוש בתורה בלבד', textAlign: TextAlign.right),
                value: torahOnly,
                onChanged: (value) {
                  torahOnly = value ?? false;
                  Settings.setValue<bool>('key-gematria-torah-only', torahOnly);
                  setDialogState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'שיטת חישוב גימטריה:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('גימטריה קטנה', textAlign: TextAlign.right),
                value: useSmallGematria,
                onChanged: (value) {
                  useSmallGematria = value ?? false;
                  if (useSmallGematria) {
                    useFinalLetters = false;
                    Settings.setValue<bool>(
                        'key-gematria-use-final-letters', false);
                  }
                  Settings.setValue<bool>(
                      'key-gematria-use-small', useSmallGematria);
                  setDialogState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('אותיות סופיות שונות',
                    textAlign: TextAlign.right),
                value: useFinalLetters,
                onChanged: (value) {
                  useFinalLetters = value ?? false;
                  if (useFinalLetters) {
                    useSmallGematria = false;
                    Settings.setValue<bool>('key-gematria-use-small', false);
                  }
                  Settings.setValue<bool>(
                      'key-gematria-use-final-letters', useFinalLetters);
                  setDialogState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('עם הכולל', textAlign: TextAlign.right),
                value: useWithKolel,
                onChanged: (value) {
                  useWithKolel = value ?? false;
                  Settings.setValue<bool>(
                      'key-gematria-use-with-kolel', useWithKolel);
                  setDialogState(() {});
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('סגור'),
          ),
        ],
      ),
    ),
  );
}
