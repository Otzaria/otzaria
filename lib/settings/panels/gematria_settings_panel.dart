import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// טאב הגדרות גימטריה
class GematriaSettingsTab extends StatefulWidget {
  const GematriaSettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'tools.gematria.method',
      title: 'שיטת חישוב גימטריה',
      subtitle: 'שיטת חישוב המשמשת בכלי הגימטריה',
      tab: SettingsTab.tools,
      cardId: 'tools.gematria',
      keywords: ['גימטריה', 'חישוב'],
    ),
  ];

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsAnchor(
          cardId: 'tools.gematria',
          child: SettingsCard(
          title: 'חיפוש גימטריה',
          children: [
            ListTile(
              leading: const Icon(FluentIcons.number_row_24_regular),
              title:
                  const Text('מספר תוצאות מקסימלי', style: kSettingsTitleStyle),
              subtitle: const Text('כמות התוצאות המקסימלית להצגה',
                  style: kSettingsSubtitleStyle),
              trailing: SizedBox(
                width: 120,
                child: AppDropdownField<int>(
                  value: maxResults,
                  entries: [50, 100, 200, 500, 1000]
                      .map(
                        (value) =>
                            AppMenuEntry(value: value, label: '$value'),
                      )
                      .toList(),
                  onSelected: (value) {
                    if (value != null) {
                      setState(() => maxResults = value);
                      Settings.setValue<int>(
                          'key-gematria-max-results', value);
                    }
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ),
            SwitchSettingsTile(
              leading: const Icon(FluentIcons.filter_24_regular),
              title:
                  const Text('סינון תוצאות כפולות', style: kSettingsTitleStyle),
              subtitle: Text(
                filterDuplicates
                    ? 'תוצאות זהות יוצגו פעם אחת בלבד'
                    : 'כל התוצאות יוצגו',
                style: kSettingsSubtitleStyle,
              ),
              value: filterDuplicates,
              onChanged: (value) {
                setState(() => filterDuplicates = value);
                Settings.setValue<bool>(
                    'key-gematria-filter-duplicates', filterDuplicates);
              },
            ),
            SwitchSettingsTile(
              leading: const Icon(FluentIcons.text_word_count_24_regular),
              title:
                  const Text('חיפוש פסוק שלם בלבד', style: kSettingsTitleStyle),
              subtitle: Text(
                wholeVerseOnly
                    ? 'חיפוש רק בפסוקים שלמים'
                    : 'חיפוש גם בחלקי פסוקים',
                style: kSettingsSubtitleStyle,
              ),
              value: wholeVerseOnly,
              onChanged: (value) {
                setState(() => wholeVerseOnly = value);
                Settings.setValue<bool>(
                    'key-gematria-whole-verse-only', wholeVerseOnly);
              },
            ),
            SwitchSettingsTile(
              leading: const Icon(FluentIcons.book_24_regular),
              title: const Text('חיפוש בתורה בלבד', style: kSettingsTitleStyle),
              subtitle: Text(
                torahOnly ? 'חיפוש רק בחמישה חומשי תורה' : 'חיפוש בכל הספרים',
                style: kSettingsSubtitleStyle,
              ),
              value: torahOnly,
              onChanged: (value) {
                setState(() => torahOnly = value);
                Settings.setValue<bool>('key-gematria-torah-only', torahOnly);
              },
            ),
          ],
          ),
        ),
        kSettingsCardSpacing,
        SettingsCard(
          title: 'שיטת חישוב גימטריה',
          children: [
            SwitchSettingsTile(
              leading: const Icon(FluentIcons.number_symbol_24_regular),
              title: const Text('גימטריה קטנה', style: kSettingsTitleStyle),
              subtitle: const Text('כל אות מחושבת לפי ספרה אחת',
                  style: kSettingsSubtitleStyle),
              value: useSmallGematria,
              onChanged: (value) {
                setState(() {
                  useSmallGematria = value;
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
            SwitchSettingsTile(
              leading: const Icon(FluentIcons.text_font_24_regular),
              title:
                  const Text('אותיות סופיות שונות', style: kSettingsTitleStyle),
              subtitle: const Text('מנצפ"ך בערכים שונים',
                  style: kSettingsSubtitleStyle),
              value: useFinalLetters,
              onChanged: (value) {
                setState(() {
                  useFinalLetters = value;
                  if (useFinalLetters) {
                    useSmallGematria = false;
                    Settings.setValue<bool>('key-gematria-use-small', false);
                  }
                });
                Settings.setValue<bool>(
                    'key-gematria-use-final-letters', useFinalLetters);
              },
            ),
            SwitchSettingsTile(
              leading: const Icon(FluentIcons.add_circle_24_regular),
              title: const Text('עם הכולל', style: kSettingsTitleStyle),
              subtitle: const Text('הוספת מספר האותיות לסכום',
                  style: kSettingsSubtitleStyle),
              value: useWithKolel,
              onChanged: (value) {
                setState(() => useWithKolel = value);
                Settings.setValue<bool>(
                    'key-gematria-use-with-kolel', useWithKolel);
              },
            ),
          ],
        ),
      ],
    );
  }
}
