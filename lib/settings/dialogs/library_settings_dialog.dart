import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/dialogs.dart';

/// פונקציה גלובלית להצגת דיאלוג הגדרות ספרייה
/// ניתן לקרוא לה מכל מקום באפליקציה
void showLibrarySettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, currentSettingsState) {
        return GenericSettingsDialog(
          title: 'הגדרות ספרייה',
          width: 500,
          items: [
            // תצוגת רשת/רשימה
            SwitchSettingsItem(
              title: 'תצוגת רשימה (עץ מתרחב)',
              subtitle: currentSettingsState.libraryViewMode == 'list'
                  ? 'מוצגת תצוגת רשימה'
                  : 'מוצגת תצוגת רשת',
              value: currentSettingsState.libraryViewMode == 'list',
              onChanged: (value) {
                context.read<SettingsBloc>().add(
                      UpdateLibraryViewMode(value ? 'list' : 'grid'),
                    );
              },
            ),
            // תצוגה מקדימה
            SwitchSettingsItem(
              title: 'הצג תצוגה מקדימה',
              subtitle: currentSettingsState.libraryShowPreview
                  ? 'תצוגה מקדימה מוצגת'
                  : 'תצוגה מקדימה מוסתרת',
              value: currentSettingsState.libraryShowPreview,
              onChanged: (value) {
                context.read<SettingsBloc>().add(
                      UpdateLibraryShowPreview(value),
                    );
              },
            ),
            // ספרים חיצוניים
            SwitchSettingsItem(
              title: 'האם להציג ספרים מאתרים חיצוניים?',
              subtitle: currentSettingsState.showExternalBooks
                  ? 'יוצגו גם ספרים מאתרים חיצוניים'
                  : 'יוצגו רק ספרים מספריית אוצריא',
              value: currentSettingsState.showExternalBooks,
              onChanged: (value) {
                context
                    .read<SettingsBloc>()
                    .add(UpdateShowExternalBooks(value));
                context.read<SettingsBloc>().add(UpdateShowHebrewBooks(value));
                context
                    .read<SettingsBloc>()
                    .add(UpdateShowOtzarHachochma(value));
              },
              dependentItems: currentSettingsState.showExternalBooks
                  ? [
                      CheckboxSettingsItem(
                        title: 'הצג ספרים מאוצר החכמה',
                        value: currentSettingsState.showOtzarHachochma,
                        onChanged: (bool? value) {
                          if (value != null) {
                            context.read<SettingsBloc>().add(
                                  UpdateShowOtzarHachochma(value),
                                );
                          }
                        },
                      ),
                      CheckboxSettingsItem(
                        title: 'הצג ספרים מהיברובוקס',
                        value: currentSettingsState.showHebrewBooks,
                        onChanged: (bool? value) {
                          if (value != null) {
                            context.read<SettingsBloc>().add(
                                  UpdateShowHebrewBooks(value),
                                );
                          }
                        },
                      ),
                    ]
                  : null,
            ),
          ],
        );
      },
    ),
  );
}
