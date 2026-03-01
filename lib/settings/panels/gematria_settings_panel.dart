import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/settings/settings_card.dart';

/// טאב הגדרות גימטריה
class GematriaSettingsTab extends StatefulWidget {
  const GematriaSettingsTab({super.key});

  @override
  State<GematriaSettingsTab> createState() => _GematriaSettingsTabState();
}

class _GematriaSettingsTabState extends State<GematriaSettingsTab> {
  late int maxResults;
  late bool filterDuplicates;
  late bool wholeVerseOnly;
  late bool torahOnly;
  late bool useSmallGematria;
  late bool useFinalLetters;
  late bool useWithKolel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    maxResults = Settings.getValue<int>('key-gematria-max-results') ?? 100;
    filterDuplicates =
        Settings.getValue<bool>('key-gematria-filter-duplicates') ?? false;
    wholeVerseOnly =
        Settings.getValue<bool>('key-gematria-whole-verse-only') ?? false;
    torahOnly = Settings.getValue<bool>('key-gematria-torah-only') ?? false;
    useSmallGematria =
        Settings.getValue<bool>('key-gematria-use-small') ?? false;
    useFinalLetters =
        Settings.getValue<bool>('key-gematria-use-final-letters') ?? false;
    useWithKolel =
        Settings.getValue<bool>('key-gematria-use-with-kolel') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // הגדרות חיפוש
          SettingsCard(
            title: 'חיפוש גימטריה',
            children: [
              ListTile(
                leading: const Icon(FluentIcons.number_row_24_regular),
                title: const Text('מספר תוצאות מקסימלי',
                    style: TextStyle(fontSize: 16)),
                trailing: DropdownButton<int>(
                  value: maxResults,
                  underline: const SizedBox(),
                  items: [50, 100, 200, 500, 1000].map((value) {
                    return DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => maxResults = value);
                      Settings.setValue<int>('key-gematria-max-results', value);
                    }
                  },
                ),
              ),
              const Divider(height: 1),
              CheckboxListTile(
                title: const Text('סינון תוצאות כפולות',
                    style: TextStyle(fontSize: 16)),
                value: filterDuplicates,
                onChanged: (value) {
                  setState(() => filterDuplicates = value ?? false);
                  Settings.setValue<bool>(
                      'key-gematria-filter-duplicates', filterDuplicates);
                },
              ),
              const Divider(height: 1),
              CheckboxListTile(
                title: const Text('חיפוש פסוק שלם בלבד',
                    style: TextStyle(fontSize: 16)),
                value: wholeVerseOnly,
                onChanged: (value) {
                  setState(() => wholeVerseOnly = value ?? false);
                  Settings.setValue<bool>(
                      'key-gematria-whole-verse-only', wholeVerseOnly);
                },
              ),
              const Divider(height: 1),
              CheckboxListTile(
                title: const Text('חיפוש בתורה בלבד',
                    style: TextStyle(fontSize: 16)),
                value: torahOnly,
                onChanged: (value) {
                  setState(() => torahOnly = value ?? false);
                  Settings.setValue<bool>('key-gematria-torah-only', torahOnly);
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // שיטת חישוב
          SettingsCard(
            title: 'שיטת חישוב גימטריה',
            children: [
              CheckboxListTile(
                title:
                    const Text('גימטריה קטנה', style: TextStyle(fontSize: 16)),
                subtitle: const Text('כל אות מחושבת לפי ספרה אחת',
                    style: TextStyle(fontSize: 13)),
                value: useSmallGematria,
                onChanged: (value) {
                  setState(() {
                    useSmallGematria = value ?? false;
                    if (useSmallGematria) {
                      useFinalLetters = false;
                      Settings.setValue<bool>(
                          'key-gematria-use-final-letters', false);
                    }
                  });
                  Settings.setValue<bool>(
                      'key-gematria-use-small', useSmallGematria);
                },
              ),
              const Divider(height: 1),
              CheckboxListTile(
                title: const Text('אותיות סופיות שונות',
                    style: TextStyle(fontSize: 16)),
                subtitle: const Text('מנצפ"ך בערכים שונים',
                    style: TextStyle(fontSize: 13)),
                value: useFinalLetters,
                onChanged: (value) {
                  setState(() {
                    useFinalLetters = value ?? false;
                    if (useFinalLetters) {
                      useSmallGematria = false;
                      Settings.setValue<bool>('key-gematria-use-small', false);
                    }
                  });
                  Settings.setValue<bool>(
                      'key-gematria-use-final-letters', useFinalLetters);
                },
              ),
              const Divider(height: 1),
              CheckboxListTile(
                title: const Text('עם הכולל', style: TextStyle(fontSize: 16)),
                subtitle: const Text('הוספת מספר האותיות לסכום',
                    style: TextStyle(fontSize: 13)),
                value: useWithKolel,
                onChanged: (value) {
                  setState(() => useWithKolel = value ?? false);
                  Settings.setValue<bool>(
                      'key-gematria-use-with-kolel', useWithKolel);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
