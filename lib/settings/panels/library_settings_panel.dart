import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// פאנל הגדרות תצוגת ספרייה
class LibrarySettingsPanel extends StatefulWidget {
  /// ווידג'ט להצגת מיקום ספרי היברובוקס (מועבר מהטאב הראשי כדי לתמוך בבחירת תיקייה)
  final Widget? hebrewBooksPathWidget;

  /// בודק אם מסד הקטלוגים קיים. ניתן להזרקה לבדיקות; כברירת מחדל בודק את הקובץ.
  final Future<bool> Function()? catalogExistsChecker;

  const LibrarySettingsPanel({
    super.key,
    this.hebrewBooksPathWidget,
    this.catalogExistsChecker,
  });

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
      id: 'library.external.source_mode',
      title: 'מקורות אחרים לספרים',
      subtitle: 'הצגת ספרים מאוצר החכמה ו/או מהיברובוקס בספרייה',
      tab: SettingsTab.library,
      cardId: 'library.external',
      keywords: [
        'חיצוניים',
        'קטלוגים',
        'אוצר החכמה',
        'otzar',
        'hebrewbooks',
        'היברובוקס',
        'מופעל',
        'לא מופעל',
      ],
    ),
  ];

  @override
  State<LibrarySettingsPanel> createState() => _LibrarySettingsPanelState();
}

class _LibrarySettingsPanelState extends State<LibrarySettingsPanel> {
  /// null בזמן הבדיקה הראשונית; אחרת האם מסד הקטלוגים קיים במערכת.
  bool? _catalogExists;
  bool _isDownloadingCatalog = false;

  @override
  void initState() {
    super.initState();
    _refreshCatalogExists();
  }

  Future<bool> _checkCatalogExists() =>
      (widget.catalogExistsChecker ??
      ExternalCatalogRepository.instance.databaseExists)();

  Future<void> _refreshCatalogExists() async {
    final exists = await _checkCatalogExists();
    if (mounted) setState(() => _catalogExists = exists);
  }

  Future<void> _downloadCatalog() async {
    setState(() => _isDownloadingCatalog = true);
    await ExternalCatalogSettingsHelper.ensureCatalogDatabaseAvailable(context);
    if (!mounted) return;
    setState(() => _isDownloadingCatalog = false);
    await _refreshCatalogExists();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // הגדרות תצוגה
            SettingsCard(
              cardId: 'library.display',
              title: 'תצוגת ספרייה',
              children: [
                SettingsActionTile.segmentedTile<String>(
                  title: 'סוג תצוגה',
                  options: const [
                    SegmentOption(
                      value: 'grid',
                      label: 'רשת',
                      icon: FluentIcons.grid_24_regular,
                      subtitle: 'התיקיות והספרים יוצגו בתוך כרטיסים ברשת',
                    ),
                    SegmentOption(
                      value: 'list',
                      label: 'רשימה',
                      rtlIcon: FluentIcons.list_24_regular,
                      subtitle: 'התיקיות והספרים יוצגו ברשימה נפתחת (עץ מתרחב)',
                    ),
                  ],
                  currentValue: state.libraryViewMode,
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(
                      UpdateLibraryViewMode(value),
                    );
                  },
                ),
                SettingsActionTile.switchTile(
                  icon: FluentIcons.eye_24_regular,
                  title: 'הצג תצוגה מקדימה',
                  subtitle: state.libraryShowPreview
                      ? 'תצוגה מקדימה מוצגת'
                      : 'תצוגה מקדימה מוסתרת',
                  value: state.libraryShowPreview,
                  onChanged: (value) {
                    context.read<SettingsBloc>().add(
                      UpdateLibraryShowPreview(value),
                    );
                  },
                ),
              ],
            ),

            kSettingsCardSpacing,

            // ספרים נוספים (משלב מיקום היברובוקס וספרים חיצוניים)
            SettingsCard(
              cardId: 'library.external',
              title: 'ספריות חיצוניות',
              subtitle:
                  'ניתן לחפש ספר במסך ספריה או להציג ספרים מתיקיית ספרים של אוצר החכמה והיברובוקס\n'
                  'החיפוש בספריה מתבצע מתוך קטלוג, הגדרות מיקום והעדכונים לקטלוג מוגדרים דרך ספריית אוצריא',
              children: [
                // מיקום היברובוקס (יוצג ראשון במידה והועבר לו ווידג'ט - דסקטופ בלבד)
                ?widget.hebrewBooksPathWidget,

                // כשהקטלוג חסר מוצג כפתור הורדה במקום תפריט המקורות.
                if (_catalogExists == false)
                  _buildMissingCatalogTile()
                else if (_catalogExists == true)
                  _buildSourceModeTile(context, state),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildMissingCatalogTile() {
    return SettingsActionTile.text(
      icon: FluentIcons.cloud_arrow_down_24_regular,
      title: 'מקורות אחרים לספרים',
      subtitle:
          'הקטלוג של אוצר החכמה והיברובוקס חסר במערכת. יש להוריד אותו כדי להציג ולחפש ספרים ממקורות אלו.',
      actions: [
        ActionButton.recommended(
          text: 'הורד קטלוג',
          isLoading: _isDownloadingCatalog,
          onPressed: _downloadCatalog,
        ),
      ],
    );
  }

  Widget _buildSourceModeTile(BuildContext context, SettingsState state) {
    return SettingsActionTile.dropdownTile<String>(
      icon: FluentIcons.globe_24_regular,
      title: 'מקורות אחרים לספרים',
      value: _externalSourceMode(state),
      entries: const [
        AppMenuEntry(
          value: 'none',
          label: 'אל תציג',
          subtitle: 'ספרים חיצוניים לא יוצגו בתוצאות החיפוש במסך הספרייה',
        ),
        AppMenuEntry(
          value: 'all',
          label: 'הצג הכל',
          subtitle:
              'יוצגו ספרים מאוצר החכמה ומהיברובוקס בתוצאות החיפוש במסך הספרייה',
        ),
        AppMenuEntry(
          value: 'otzar',
          label: 'אוצר החכמה בלבד',
          subtitle: 'יוצגו ספרים מאוצר החכמה בתוצאות החיפוש במסך הספרייה',
        ),
        AppMenuEntry(
          value: 'hebrewbooks',
          label: 'היברובוקס בלבד',
          subtitle: 'יוצגו ספרים מהיברובוקס בתוצאות החיפוש במסך הספרייה',
        ),
      ],
      onSelected: (value) async {
        if (value != null) {
          await ExternalCatalogSettingsHelper.updateExternalSourceMode(
            context,
            value,
          );
        }
      },
    );
  }

  /// ערך התפריט הנוכחי לפי מצב הספרים החיצוניים.
  static String _externalSourceMode(SettingsState state) {
    if (!state.showExternalBooks) return 'none';
    if (state.showOtzarHachochma && state.showHebrewBooks) return 'all';
    if (state.showOtzarHachochma) return 'otzar';
    if (state.showHebrewBooks) return 'hebrewbooks';
    return 'none';
  }
}
