import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// טאב הגדרות גימטריה.
class GematriaSettingsTab extends StatelessWidget {
  const GematriaSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsCard(
              title: 'חיפוש גימטריה',
              children: [
                ListTile(
                  leading: const Icon(FluentIcons.number_row_24_regular),
                  title: const Text(
                    'מספר תוצאות מקסימלי',
                    style: kSettingsTitleStyle,
                  ),
                  subtitle: const Text(
                    'כמות התוצאות המקסימלית להצגה',
                    style: kSettingsSubtitleStyle,
                  ),
                  trailing: SizedBox(
                    width: 120,
                    child: AppDropdownField<int>(
                      value: state.gematriaMaxResults,
                      entries: [50, 100, 200, 500, 1000]
                          .map(
                            (value) =>
                                AppMenuEntry(value: value, label: '$value'),
                          )
                          .toList(),
                      onSelected: (value) {
                        if (value == null) return;
                        context
                            .read<SettingsBloc>()
                            .add(UpdateGematriaMaxResults(value));
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
                  title: const Text(
                    'סינון תוצאות כפולות',
                    style: kSettingsTitleStyle,
                  ),
                  subtitle: Text(
                    state.gematriaFilterDuplicates
                        ? 'תוצאות זהות יוצגו פעם אחת בלבד'
                        : 'כל התוצאות יוצגו',
                    style: kSettingsSubtitleStyle,
                  ),
                  value: state.gematriaFilterDuplicates,
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(UpdateGematriaFilterDuplicates(value));
                  },
                ),
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.text_word_count_24_regular),
                  title: const Text(
                    'חיפוש פסוק שלם בלבד',
                    style: kSettingsTitleStyle,
                  ),
                  subtitle: Text(
                    state.gematriaWholeVerseOnly
                        ? 'חיפוש רק בפסוקים שלמים'
                        : 'חיפוש גם בחלקי פסוקים',
                    style: kSettingsSubtitleStyle,
                  ),
                  value: state.gematriaWholeVerseOnly,
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(UpdateGematriaWholeVerseOnly(value));
                  },
                ),
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.book_24_regular),
                  title: const Text(
                    'חיפוש בתורה בלבד',
                    style: kSettingsTitleStyle,
                  ),
                  subtitle: Text(
                    state.gematriaTorahOnly
                        ? 'חיפוש רק בחמישה חומשי תורה'
                        : 'חיפוש בכל הספרים',
                    style: kSettingsSubtitleStyle,
                  ),
                  value: state.gematriaTorahOnly,
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(UpdateGematriaTorahOnly(value));
                  },
                ),
              ],
            ),
            kSettingsCardSpacing,
            SettingsCard(
              title: 'שיטת חישוב גימטריה',
              children: [
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.number_symbol_24_regular),
                  title: const Text(
                    'גימטריה קטנה',
                    style: kSettingsTitleStyle,
                  ),
                  subtitle: const Text(
                    'כל אות מחושבת לפי ספרה אחת',
                    style: kSettingsSubtitleStyle,
                  ),
                  value: state.gematriaUseSmall,
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(UpdateGematriaUseSmall(value));
                  },
                ),
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.text_font_24_regular),
                  title: const Text(
                    'אותיות סופיות שונות',
                    style: kSettingsTitleStyle,
                  ),
                  subtitle: const Text(
                    'מנצפ"ך בערכים שונים',
                    style: kSettingsSubtitleStyle,
                  ),
                  value: state.gematriaUseFinalLetters,
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(UpdateGematriaUseFinalLetters(value));
                  },
                ),
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.add_circle_24_regular),
                  title: const Text(
                    'עם הכולל',
                    style: kSettingsTitleStyle,
                  ),
                  subtitle: const Text(
                    'הוספת מספר האותיות לסכום',
                    style: kSettingsSubtitleStyle,
                  ),
                  value: state.gematriaUseWithKolel,
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(UpdateGematriaUseWithKolel(value));
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
