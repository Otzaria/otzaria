import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// פאנל הגדרות תצוגת ספרייה
class LibrarySettingsPanel extends StatelessWidget {
  /// ווידג'ט להצגת מיקום ספרי היברובוקס (מועבר מהטאב הראשי כדי לתמוך בבחירת תיקייה)
  final Widget? hebrewBooksPathWidget;

  const LibrarySettingsPanel({super.key, this.hebrewBooksPathWidget});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'library.display.view_type',
      title: 'סוג תצוגה',
      subtitle: 'תצוגת רשת או רשימה לספרי הקטגוריה',
      tab: SettingsTab.library,
      cardId: 'library.display',
      keywords: ['רשת', 'רשימה', 'תצוגה', 'גריד'],
    ),
    SettingsSearchEntry(
      id: 'library.display.preview',
      title: 'הצג תצוגה מקדימה',
      subtitle: 'תצוגה מקדימה של תוכן ספרים',
      tab: SettingsTab.library,
      cardId: 'library.display',
      keywords: ['תצוגה מקדימה', 'preview', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'library.external.show',
      title: 'הצגת ספרים מאתרים חיצוניים',
      subtitle: 'הצגת קטלוגים חיצוניים בתצוגת הספרייה',
      tab: SettingsTab.library,
      cardId: 'library.display',
      keywords: ['חיצוניים', 'קטלוגים', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'library.external.otzar',
      title: 'הצג ספרים מאוצר החכמה',
      subtitle: 'ספרים מאתר אוצר החכמה',
      tab: SettingsTab.library,
      cardId: 'library.display',
      keywords: ['אוצר החכמה', 'otzar', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'library.external.hebrewbooks',
      title: 'הצג ספרים מהיברובוקס',
      subtitle: 'ספרים מאתר HebrewBooks',
      tab: SettingsTab.library,
      cardId: 'library.display',
      keywords: ['hebrewbooks', 'היברובוקס', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'library.external.auto_sync',
      title: 'סנכרון קטלוגים אוטומטי',
      subtitle: 'עדכן קטלוגים חיצוניים אוטומטית',
      tab: SettingsTab.library,
      cardId: 'library.display',
      keywords: ['סנכרון', 'קטלוגים', 'אוטומטי', 'מופעל', 'לא מופעל'],
    ),
  ];

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
                SegmentedSettingsTile<String>(
                  icon: FluentIcons.grid_24_regular,
                  title: 'סוג תצוגה',
                  subtitle: state.libraryViewMode == 'list'
                      ? 'תצוגת רשימה (עץ מתרחב)'
                      : 'תצוגת רשת',
                  options: const [
                    SegmentOption(
                      value: 'grid',
                      label: 'רשת',
                      icon: FluentIcons.grid_24_regular,
                    ),
                    SegmentOption(
                      value: 'list',
                      label: 'רשימה',
                      icon: FluentIcons.list_24_regular,
                    ),
                  ],
                  currentValue: state.libraryViewMode,
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(UpdateLibraryViewMode(value));
                  },
                ),
                SwitchSettingsTile.text(
                  icon: FluentIcons.eye_24_regular,
                  title: 'הצג תצוגה מקדימה',
                  subtitle: state.libraryShowPreview
                      ? 'תצוגה מקדימה מוצגת'
                      : 'תצוגה מקדימה מוסתרת',
                  value: state.libraryShowPreview,
                  onChanged: (value) {
                    context
                        .read<SettingsBloc>()
                        .add(UpdateLibraryShowPreview(value));
                  },
                ),
              ],
            ),

            kSettingsCardSpacing,

            // ספרים נוספים (משלב מיקום היברובוקס וספרים חיצוניים)
            SettingsCard(
              title: 'ספרים נוספים',
              children: [
                // מיקום היברובוקס (יוצג ראשון במידה והועבר לו ווידג'ט - דסקטופ בלבד)
                if (hebrewBooksPathWidget != null) hebrewBooksPathWidget!,

                SwitchSettingsTile.text(
                  icon: FluentIcons.globe_24_regular,
                  title: 'הצגת ספרים מאתרים חיצוניים',
                  subtitle: state.showExternalBooks
                      ? 'יוצגו גם ספרים מאתרים חיצוניים'
                      : 'יוצגו רק ספרים מספריית אוצריא',
                  value: state.showExternalBooks,
                  onChanged: (value) async {
                    await ExternalCatalogSettingsHelper.updateExternalBooks(
                      context,
                      value,
                    );
                  },
                ),
                if (state.showExternalBooks) ...[
                  SwitchSettingsTile.text(
                    icon: FluentIcons.library_24_regular,
                    title: 'הצג ספרים מאוצר החכמה',
                    subtitle: 'ספרים מאתר אוצר החכמה',
                    value: state.showOtzarHachochma,
                    onChanged: (value) async {
                      await ExternalCatalogSettingsHelper.updateOtzarBooks(
                        context,
                        value,
                      );
                    },
                  ),
                  SwitchSettingsTile.text(
                    icon: FluentIcons.book_open_24_regular,
                    title: 'הצג ספרים מהיברובוקס',
                    subtitle: 'ספרים מאתר HebrewBooks',
                    value: state.showHebrewBooks,
                    onChanged: (value) async {
                      await ExternalCatalogSettingsHelper.updateHebrewBooks(
                        context,
                        value,
                      );
                    },
                  ),
                  SwitchSettingsTile.text(
                    icon: FluentIcons.arrow_sync_24_regular,
                    title: 'סנכרון קטלוגים אוטומטי',
                    subtitle: 'עדכן קטלוגים חיצוניים אוטומטית',
                    value: state.autoSyncCatalogs,
                    onChanged: (value) {
                      context
                          .read<SettingsBloc>()
                          .add(UpdateAutoSyncCatalogs(value));
                    },
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
