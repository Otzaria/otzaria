import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';

/// פאנל הגדרות תצוגת ספרייה
class LibrarySettingsPanel extends StatelessWidget {
  /// ווידג'ט להצגת מיקום ספרי היברובוקס (מועבר מהטאב הראשי כדי לתמוך בבחירת תיקייה)
  final Widget? hebrewBooksPathWidget;

  const LibrarySettingsPanel({super.key, this.hebrewBooksPathWidget});

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
                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.eye_24_regular),
                  title: const Text('הצג תצוגה מקדימה',
                      style: kSettingsTitleStyle),
                  subtitle: Text(
                    state.libraryShowPreview
                        ? 'תצוגה מקדימה מוצגת'
                        : 'תצוגה מקדימה מוסתרת',
                    style: kSettingsSubtitleStyle,
                  ),
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

                SwitchSettingsTile(
                  leading: const Icon(FluentIcons.globe_24_regular),
                  title: const Text('הצגת ספרים מאתרים חיצוניים',
                      style: kSettingsTitleStyle),
                  subtitle: Text(
                    state.showExternalBooks
                        ? 'יוצגו גם ספרים מאתרים חיצוניים'
                        : 'יוצגו רק ספרים מספריית אוצריא',
                    style: kSettingsSubtitleStyle,
                  ),
                  value: state.showExternalBooks,
                  onChanged: (value) async {
                    await ExternalCatalogSettingsHelper.updateExternalBooks(
                      context,
                      value,
                    );
                  },
                ),
                if (state.showExternalBooks) ...[
                  SwitchSettingsTile(
                    leading: const Icon(FluentIcons.library_24_regular),
                    title: const Text('הצג ספרים מאוצר החכמה',
                        style: kSettingsTitleStyle),
                    subtitle: const Text('ספרים מאתר אוצר החכמה',
                        style: kSettingsSubtitleStyle),
                    value: state.showOtzarHachochma,
                    onChanged: (value) async {
                      await ExternalCatalogSettingsHelper.updateOtzarBooks(
                        context,
                        value,
                      );
                    },
                  ),
                  SwitchSettingsTile(
                    leading: const Icon(FluentIcons.book_open_24_regular),
                    title: const Text('הצג ספרים מהיברובוקס',
                        style: kSettingsTitleStyle),
                    subtitle: const Text('ספרים מאתר HebrewBooks',
                        style: kSettingsSubtitleStyle),
                    value: state.showHebrewBooks,
                    onChanged: (value) async {
                      await ExternalCatalogSettingsHelper.updateHebrewBooks(
                        context,
                        value,
                      );
                    },
                  ),
                  const _CatalogSyncTile(),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

/// ווידג'ט לסנכרון קטלוגים חיצוניים
class _CatalogSyncTile extends StatefulWidget {
  const _CatalogSyncTile();

  @override
  State<_CatalogSyncTile> createState() => _CatalogSyncTileState();
}

class _CatalogSyncTileState extends State<_CatalogSyncTile> {
  bool _isSyncing = false;
  String _message = 'סנכרן קטלוגים';

  Future<void> _syncCatalogs() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _message = 'מסנכרן...';
    });

    late String finalMessage;
    try {
      final repository = ExternalCatalogRepository.instance;

      if (!await repository.databaseExists()) {
        finalMessage = 'אין קטלוגים להצגה';
      } else {
        final updated = await repository.updateDatabaseIfNeeded();
        if (updated) {
          DataRepository.instance.invalidateExternalBooksCache();
          finalMessage = 'הקטלוגים עודכנו בהצלחה';
        } else {
          finalMessage = 'הקטלוגים מעודכנים';
        }
      }
    } catch (e) {
      finalMessage = 'שגיאה: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _message = finalMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(FluentIcons.arrow_sync_24_regular),
      title: const Text('סנכרון קטלוגים', style: kSettingsTitleStyle),
      subtitle: Text(_message, style: kSettingsSubtitleStyle),
      hoverColor: Colors.transparent,
      trailing: _isSyncing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : RecommendedActionButton(
              text: 'סנכרן',
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: () {
                _syncCatalogs();
              },
            ),
    );
  }
}
