import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';

/// פאנל הגדרות ספרייה בסיסיות (תצוגה וספרים חיצוניים)
/// משמש גם בתוך הטאב המלא וגם בדיאלוג המהיר
class LibraryBasicSettingsPanel extends StatelessWidget {
  const LibraryBasicSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // הגדרות תצוגה
            SettingsCard(
              title: 'תצוגת ספרייה',
              children: [
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.list_24_regular),
                  title: const Text('תצוגת רשימה (עץ מתרחב)',
                      style: TextStyle(fontSize: 16)),
                  subtitle: Text(
                      state.libraryViewMode == 'list'
                          ? 'מוצגת תצוגת רשימה'
                          : 'מוצגת תצוגת רשת',
                      style: const TextStyle(fontSize: 13)),
                  value: state.libraryViewMode == 'list',
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(
                          UpdateLibraryViewMode(value ? 'list' : 'grid'),
                        );
                  },
                ),
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.eye_24_regular),
                  title: const Text('הצג תצוגה מקדימה',
                      style: TextStyle(fontSize: 16)),
                  subtitle: Text(
                      state.libraryShowPreview
                          ? 'תצוגה מקדימה מוצגת'
                          : 'תצוגה מקדימה מוסתרת',
                      style: const TextStyle(fontSize: 13)),
                  value: state.libraryShowPreview,
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(
                          UpdateLibraryShowPreview(value),
                        );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // הגדרות ספרים חיצוניים
            SettingsCard(
              title: 'ספרים חיצוניים',
              children: [
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.globe_24_regular),
                  title: const Text('האם להציג ספרים מאתרים חיצוניים?',
                      style: TextStyle(fontSize: 16)),
                  subtitle: Text(
                      state.showExternalBooks
                          ? 'יוצגו גם ספרים מאתרים חיצוניים'
                          : 'יוצגו רק ספרים מספריית אוצריא',
                      style: const TextStyle(fontSize: 13)),
                  value: state.showExternalBooks,
                  onChanged: (value) async {
                    await ExternalCatalogSettingsHelper.updateExternalBooks(
                      context,
                      value,
                    );
                  },
                ),
                if (state.showExternalBooks) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 32.0),
                    child: CheckboxListTile(
                      title: const Text('הצג ספרים מאוצר החכמה',
                          style: TextStyle(fontSize: 16)),
                      value: state.showOtzarHachochma,
                      onChanged: (value) async {
                        if (value != null) {
                          await ExternalCatalogSettingsHelper.updateOtzarBooks(
                            context,
                            value,
                          );
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 32.0),
                    child: CheckboxListTile(
                      title: const Text('הצג ספרים מהיברובוקס',
                          style: TextStyle(fontSize: 16)),
                      value: state.showHebrewBooks,
                      onChanged: (value) async {
                        if (value != null) {
                          await ExternalCatalogSettingsHelper.updateHebrewBooks(
                            context,
                            value,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}
