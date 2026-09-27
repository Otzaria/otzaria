import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SwitchSettingsTile;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_build_service.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:otzaria/external_catalog/responsa/responsa_paths.dart';
import 'package:otzaria/external_catalog/responsa/responsa_service.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/view/responsa_build_progress_view.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
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

  /// טוען את מצב קטלוג פרויקט השו"ת. ניתן להזרקה לבדיקות.
  final Future<ResponsaCatalogInfo> Function()? responsaInfoLoader;

  /// טוען את מצב ההתקנה של פרויקט השו"ת. ניתן להזרקה לבדיקות.
  final Future<ResponsaStatus> Function()? responsaStatusLoader;

  /// מפעיל את בניית קטלוג בר אילן. ניתן להזרקה לבדיקות — הבנייה
  /// האמיתית סורקת מיליון רשומות מול מופע חי של התוכנה.
  final Future<void> Function()? responsaCatalogBuilder;

  const LibrarySettingsPanel({
    super.key,
    this.hebrewBooksPathWidget,
    this.catalogExistsChecker,
    this.responsaInfoLoader,
    this.responsaStatusLoader,
    this.responsaCatalogBuilder,
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
      id: 'library.external.local_hebrewbooks',
      title: 'הצג ספרי היברובוקס שברשותך',
      subtitle: 'ספרים מתיקיית היברובוקס יופיעו באיתור הספר',
      tab: SettingsTab.library,
      cardId: 'library.external',
      keywords: [
        'היברובוקס',
        'hebrewbooks',
        'מקומי',
        'תיקייה',
        'מופעל',
        'לא מופעל',
      ],
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
    SettingsSearchEntry(
      id: 'library.responsa.show',
      title: 'הצג ופתח ספרי בר אילן',
      subtitle:
          'ספרים מפרויקט השו"ת (בר אילן) יופיעו באיתור הספר וייפתחו בתוכנה',
      tab: SettingsTab.library,
      cardId: 'library.responsa',
      keywords: [
        'פרויקט השו"ת',
        'בר אילן',
        'בר-אילן',
        'responsa',
        'שו"ת',
        'מופעל',
        'לא מופעל',
      ],
    ),
    SettingsSearchEntry(
      id: 'library.responsa.build',
      title: 'רענון קטלוג בר אילן',
      subtitle: 'סריקת קטלוג התוכנה המותקנת כדי לאתר ולפתוח ספרים',
      tab: SettingsTab.library,
      cardId: 'library.responsa',
      keywords: [
        'פרויקט השו"ת',
        'בר אילן',
        'בר-אילן',
        'קטלוג',
        'בנייה',
        'רענון',
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

  /// null בזמן הבדיקה; אחרת מצב הקטלוג המקומי של פרויקט השו"ת.
  ResponsaCatalogInfo? _responsaInfo;

  /// null בזמן הבדיקה; אחרת האם פרויקט השו"ת מותקן ובאיזו מהדורה.
  ResponsaStatus? _responsaStatus;

  final ResponsaCatalogBuildService _responsaBuild =
      ResponsaCatalogBuildService();
  ResponsaBuildProgress? _responsaBuildProgress;

  @override
  void initState() {
    super.initState();
    _refreshCatalogExists();
    _refreshResponsaInfo();
  }

  /// קורא את מצב הקטלוג ואת מצב ההתקנה.
  ///
  /// שתי הקריאות מוגנות בנפרד. הן סורקות רישום, כוננים וחלונות, וכשל
  /// באחת מהן השאיר את **שתיהן** `null` — ואז הכרטיס של בר אילן פשוט
  /// אינו מוצג, בלי שגיאה ובלי דרך למשתמש לדעת שהתכונה קיימת.
  Future<void> _refreshResponsaInfo() async {
    ResponsaCatalogInfo info;
    try {
      info =
          await (widget.responsaInfoLoader ??
              ResponsaCatalogRepository.instance.info)();
    } catch (error) {
      debugPrint('LibrarySettingsPanel: responsa info failed: $error');
      info = ResponsaCatalogInfo.missing;
    }
    ResponsaStatus status;
    try {
      status =
          await (widget.responsaStatusLoader ??
              ResponsaService.instance.controller.status)();
    } catch (error) {
      debugPrint('LibrarySettingsPanel: responsa status failed: $error');
      status = ResponsaStatus.notInstalled;
    }
    if (mounted) {
      setState(() {
        _responsaInfo = info;
        _responsaStatus = status;
      });
    }
  }

  /// האם הקטלוג שעל הדיסק נבנה מהתקנה שאינה על המחשב הזה.
  ///
  /// הקטלוג יושב בתיקיית הספרייה, ולכן הוא נודד איתה בין מחשבים — ראה
  /// `ResponsaPaths`. קטלוג נודד נראה תקין לחלוטין ורק הפתיחה נכשלת,
  /// ולכן הוא מוצג כאן כבקשת רענון ולא כשגיאה בזמן פתיחה.
  bool get _responsaCatalogIsForeign {
    final info = _responsaInfo;
    if (info == null || !info.isUsable) return false;
    final installations = _responsaStatus?.installations ?? const [];
    return !info.describesAnyOf(
      installations.map((installation) => installation.installPath),
    );
  }

  /// בניית הקטלוג — סריקה חיה של עץ הקטלוג בתוכנה.
  ///
  /// ארוכה מטבעה (כ-1.25 מיליון רשומות, כמה דקות), ולכן היא מדווחת
  /// התקדמות וניתנת לביטול.
  Future<void> _buildResponsaCatalog() async {
    if (widget.responsaCatalogBuilder case final injected?) {
      await injected();
      if (mounted) await _refreshResponsaInfo();
      return;
    }
    final target = ResponsaPaths.catalogPath;
    if (target == null) return;
    setState(() {
      _responsaBuildProgress = const ResponsaBuildProgress(
        stage: ResponsaBuildStage.starting,
      );
    });
    await for (final progress in _responsaBuild.build(targetPath: target)) {
      if (!mounted) return;
      setState(() => _responsaBuildProgress = progress);
    }
    if (!mounted) return;
    final finished = _responsaBuildProgress;
    if (finished?.stage == ResponsaBuildStage.done) {
      DataRepository.instance.invalidateExternalBooksCache();
      UiSnack.show(SettingsMessages.responsaCatalogBuilt(finished!.books));
    } else if (finished?.error case final error?) {
      UiSnack.showError(error);
    }
    setState(() => _responsaBuildProgress = null);
    await _refreshResponsaInfo();
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
              title: context.settingsText('תצוגת ספרייה'),
              children: [
                SettingsActionTile.segmentedTile<String>(
                  title: context.settingsText('סוג תצוגה'),
                  options: [
                    SegmentOption(
                      value: 'grid',
                      label: context.settingsText('רשת'),
                      icon: FluentIcons.grid_24_regular,
                      subtitle: context.settingsText(
                        'התיקיות והספרים יוצגו בתוך כרטיסים ברשת',
                      ),
                    ),
                    SegmentOption(
                      value: 'list',
                      label: context.settingsText('רשימה'),
                      rtlIcon: OtzariaIcons.list_24_regular,
                      subtitle: context.settingsText(
                        'התיקיות והספרים יוצגו ברשימה נפתחת (עץ מתרחב)',
                      ),
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
                  title: context.settingsText('הצג תצוגה מקדימה'),
                  subtitle: context.settingsText(
                    state.libraryShowPreview
                        ? 'תצוגה מקדימה מוצגת'
                        : 'תצוגה מקדימה מוסתרת',
                  ),
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
              title: context.settingsText('ספריות חיצוניות'),
              subtitle: context.settingsText(
                'ניתן לחפש ספר במסך ספרייה או להציג ספרים מתיקיית ספרים של אוצר החכמה והיברובוקס',
              ),
              children: [
                // מיקום היברובוקס (יוצג ראשון במידה והועבר לו ווידג'ט - דסקטופ בלבד)
                ?widget.hebrewBooksPathWidget,

                // כשהקטלוג חסר מוצג כפתור הורדה במקום תפריט המקורות.
                if (_catalogExists == false)
                  _buildMissingCatalogTile(context)
                else if (_catalogExists == true) ...[
                  _buildSourceModeTile(context, state),
                  // כשהקטלוג עצמו מוצג הספרים המקומיים כלולים בו ממילא.
                  if (_hasHebrewBooksPath &&
                      !(state.showExternalBooks && state.showHebrewBooks))
                    _buildLocalHebrewBooksTile(context, state),
                ],
              ],
            ),

            if (_responsaStatus?.installed ?? false) ...[
              kSettingsCardSpacing,
              _buildResponsaCard(context, state),
            ],
          ],
        );
      },
    );
  }

  /// כרטיס פרויקט השו"ת (בר אילן). מוצג כשהתוכנה מותקנת במחשב.
  ///
  /// **מתג אחד.** חיפוש ופתיחה אינם שתי יכולות נפרדות מבחינת המשתמש:
  /// ספר שנמצא בחיפוש ואי אפשר לפתוח אותו הוא תוצאה חסרת ערך. המתג
  /// מדליק את שניהם, ובהדלקה הראשונה גם בונה את הקטלוג.
  ///
  /// הקטלוג נבנה מההתקנה של המשתמש ולכן חייב להיבנות אצלו; אין קובץ
  /// קטלוג שאפשר להוריד, כי תוכן המאגר משתנה בין מהדורות.
  Widget _buildResponsaCard(BuildContext context, SettingsState state) {
    final info = _responsaInfo;
    final version = info?.sourceVersion ?? _responsaStatus?.version;
    final hasCatalog = info?.isUsable ?? false;
    final enabled = state.showResponsaInLibrary;
    final progress = _responsaBuildProgress;
    return SettingsCard(
      cardId: 'library.responsa',
      title: context.settingsText('פרויקט השו"ת (בר אילן)'),
      subtitle: context.settingsText(
        'חיפוש ספרים ומחברים מבר אילן ופתיחתם בתוכנה',
      ),
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.library_24_regular,
          title: context.settingsText('הצג ופתח ספרי בר אילן'),
          subtitle: progress != null
              ? _progressText(context, progress)
              : context.settingsText(
                  // מספר המהדורה נכנס למשפט רק כשהוא ידוע. הוא נקרא מכותרת
                  // החלון או משם התיקייה, ואין ערובה לקיומו — "מהדורה 0" הוא
                  // ערך שקרי, ו"מהדורה" בלי מספר הוא משפט שבור.
                  switch ((hasCatalog, enabled, version)) {
                    (true, _, final int _) =>
                      'נמצאו {count} ספרים במהדורה {version}. לחיצה על ספר '
                          'תפתח אותו בבר אילן.',
                    (true, _, null) =>
                      'נמצאו {count} ספרים. לחיצה על ספר תפתח אותו בבר אילן.',
                    (false, true, _) => 'הקטלוג טרם נבנה — יש לרענן אותו למטה.',
                    (false, false, _) =>
                      'בהדלקה הראשונה ייבנה קטלוג מההתקנה שבמחשב. הסריקה '
                          'אורכת מספר דקות, ובר אילן ייפתח לשם כך אם אינו פתוח.',
                  },
                  args: {
                    'count': info?.bookCount ?? 0,
                    'version': version ?? 0,
                  },
                ),
          value: enabled,
          onChanged: progress != null
              ? null
              : (value) => _toggleResponsa(context, state, value),
        ),
        if (enabled) _buildResponsaRebuildTile(context, hasCatalog),
        if (progress != null)
          ResponsaBuildProgressView(
            progress: progress,
            expectedNodes: _expectedNodes,
          ),
      ],
    );
  }

  /// בנייה ורענון של הקטלוג.
  ///
  /// חוליה אחת לשני המצבים: הפעולה זהה, ורק הניסוח משתנה לפי קיום
  /// הקטלוג ולפי היותו ישן.
  Widget _buildResponsaRebuildTile(BuildContext context, bool hasCatalog) {
    final progress = _responsaBuildProgress;
    final outdated = _responsaInfo?.isOutdated ?? false;
    final foreign = _responsaCatalogIsForeign;
    return SettingsActionTile.text(
      icon: FluentIcons.arrow_sync_24_regular,
      title: context.settingsText(
        hasCatalog ? 'רענון קטלוג בר אילן' : 'בניית קטלוג בר אילן',
      ),
      subtitle: progress != null
          ? _progressText(context, progress)
          : context.settingsText(
              switch ((hasCatalog, outdated || foreign)) {
                (_, true) when foreign =>
                  'הקטלוג נבנה מהתקנה אחרת של בר אילן — ככל הנראה במחשב אחר, '
                      'והוא עבר לכאן יחד עם תיקיית הספרייה. הספרים שבו אינם '
                      'בהכרח אלה שבמאגר שבמחשב הזה, ויש לרענן אותו.',
                (_, true) =>
                  'הקטלוג נבנה בגרסה ישנה של אוצריא. רענון יעדכן את שמות '
                      'הספרים והמחברים, את פרטי המהדורה ואת אופן הפתיחה.',
                (true, false) => 'יש לרענן אחרי התקנת מהדורה אחרת של בר אילן',
                (false, false) =>
                  'הבנייה סורקת את קטלוג התוכנה ואורכת מספר דקות; '
                      'בר אילן ייפתח לשם כך אם אינו פתוח.',
              },
            ),
      actions: [
        if (progress == null)
          if (hasCatalog && !outdated && !foreign)
            ActionButton.neutral(
              text: context.settingsText('רענן'),
              onPressed: _buildResponsaCatalog,
            )
          else
            ActionButton.recommended(
              text: context.settingsText(hasCatalog ? 'רענן' : 'בנה קטלוג'),
              onPressed: _buildResponsaCatalog,
            )
        else
          ActionButton.neutral(
            text: context.settingsText('ביטול'),
            onPressed: _responsaBuild.cancel,
          ),
      ],
    );
  }

  /// מספר הצמתים בבנייה הקודמת — רק כשהקטלוג נבנה מההתקנה שבמחשב.
  /// קטלוג שהגיע ממחשב אחר מתאר עץ אחר, ומכנה ממנו הוא ניחוש.
  int? get _expectedNodes =>
      _responsaCatalogIsForeign ? null : _responsaInfo?.nodeCount;

  String _progressText(BuildContext context, ResponsaBuildProgress progress) {
    final headline = ResponsaBuildStatus.of(
      progress,
      expectedNodes: _expectedNodes,
    ).headline;
    return context.settingsText(headline.template, args: headline.args);
  }

  /// מדליק או מכבה את בר אילן, ובהדלקה הראשונה גם בונה את הקטלוג.
  ///
  /// הבנייה אינה רצה בעליית אוצריא ואינה רצה מאליה: היא מתחילה כאן,
  /// אחרי שהמשתמש ביקש במפורש — זו סריקה של מיליון רשומות שמצריכה
  /// מופע פתוח של התוכנה.
  void _toggleResponsa(
    BuildContext context,
    SettingsState state,
    bool enabled,
  ) {
    final providers = {...state.enabledExternalProviders};
    if (enabled) {
      providers.add(ExternalProviderRegistry.responsa.id);
    } else {
      providers.remove(ExternalProviderRegistry.responsa.id);
    }
    context.read<SettingsBloc>().add(
      UpdateEnabledExternalProviders(providers),
    );
    if (enabled &&
        !(_responsaInfo?.isUsable ?? false) &&
        _responsaBuildProgress == null) {
      _buildResponsaCatalog();
    }
  }

  Widget _buildMissingCatalogTile(BuildContext context) {
    return SettingsActionTile.text(
      icon: FluentIcons.cloud_arrow_down_24_regular,
      title: context.settingsText('מקורות אחרים לספרים'),
      subtitle: context.settingsText(
        'הקטלוג של אוצר החכמה והיברובוקס חסר במערכת. יש להוריד אותו כדי להציג ולחפש ספרים ממקורות אלו.',
      ),
      actions: [
        ActionButton.recommended(
          text: context.settingsText('הורד קטלוג'),
          isLoading: _isDownloadingCatalog,
          onPressed: _downloadCatalog,
        ),
      ],
    );
  }

  /// האם הוגדרה תיקיית ספרי היברובוקס מקומיים.
  bool get _hasHebrewBooksPath {
    if (!Settings.isInitialized) return false;
    final path = Settings.getValue<String>(
      SettingsRepository.keyHebrewBooksPath,
    );
    return path != null && path.isNotEmpty;
  }

  /// מתג הצגת ספרי היברובוקס שכבר ירדו למחשב (issue #1143) — מיועד למי
  /// שהגדיר את התיקייה עבור תוסף ואינו רוצה אותם באיתור הספר.
  Widget _buildLocalHebrewBooksTile(BuildContext context, SettingsState state) {
    return SettingsActionTile.switchTile(
      icon: FluentIcons.document_folder_24_regular,
      title: context.settingsText('הצג ספרי היברובוקס שברשותך'),
      subtitle: context.settingsText(
        state.showLocalHebrewBooks
            ? 'ספרים מתיקיית היברובוקס יוצגו בתוצאות איתור הספר'
            : 'ספרים מתיקיית היברובוקס לא יוצגו בתוצאות איתור הספר',
      ),
      value: state.showLocalHebrewBooks,
      onChanged: (value) {
        context.read<SettingsBloc>().add(UpdateShowLocalHebrewBooks(value));
      },
    );
  }

  Widget _buildSourceModeTile(BuildContext context, SettingsState state) {
    return SettingsActionTile.dropdownTile<String>(
      icon: FluentIcons.globe_24_regular,
      title: context.settingsText('מקורות אחרים לספרים'),
      value: _externalSourceMode(state),
      entries: [
        AppMenuEntry(
          value: 'none',
          label: context.settingsText('אל תציג'),
          subtitle: context.settingsText(
            'ספרים חיצוניים לא יוצגו בתוצאות החיפוש במסך הספרייה',
          ),
        ),
        AppMenuEntry(
          value: 'all',
          label: context.settingsText('הצג הכל'),
          subtitle: context.settingsText(
            'יוצגו ספרים מאוצר החכמה ומהיברובוקס בתוצאות החיפוש במסך הספרייה',
          ),
        ),
        AppMenuEntry(
          value: 'otzar',
          label: context.settingsText('אוצר החכמה בלבד'),
          subtitle: context.settingsText(
            'יוצגו ספרים מאוצר החכמה בתוצאות החיפוש במסך הספרייה',
          ),
        ),
        AppMenuEntry(
          value: 'hebrewbooks',
          label: context.settingsText('היברובוקס בלבד'),
          subtitle: context.settingsText(
            'יוצגו ספרים מהיברובוקס בתוצאות החיפוש במסך הספרייה',
          ),
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
