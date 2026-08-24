import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
// dart:io מגדיר Link משלו (קישור בקובץ־מערכת) שמתנגש ב-Link של הקישורים.
import 'dart:io' hide Link;
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/core/connectivity_status_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_search_api.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchStreamUpdate;
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/plugins/services/plugin_in_book_search_service.dart';
import 'package:otzaria/plugins/services/plugin_reader_actions.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/plugins/database/plugin_database_service.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';
import 'package:otzaria/plugins/services/plugin_store_link_parser.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_settings_access_policy.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_service.dart';
import 'package:otzaria/plugins/services/plugin_path_safety.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/declarative/services/declarative_library_book_access.dart';
import 'package:otzaria/plugins/services/plugin_section_text_map_service.dart';
import 'package:otzaria/plugins/services/plugin_text_occurrence_service.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

// ===================================================================
// Helper: build the main colorScheme roles + typography from Flutter theme
// ===================================================================
Map<String, dynamic> buildThemePayload(BuildContext context) {
  final theme = Theme.of(context);
  return buildThemePayloadFromScheme(
    theme.colorScheme,
    isDark: theme.brightness == Brightness.dark,
  );
}

/// בונה את ה-payload מ-[ColorScheme] מפורש במקום מ-`Theme.of(context)`.
/// נצרך כשמדווחים על שינוי theme בזמן אמת: ה-`MaterialApp` מתעדכן רק ב-frame
/// הבא, כך ש-`Theme.of(context)` עדיין מחזיר את הצבעים הישנים. בנייה מ-scheme
/// שמחושב ישירות מההגדרות מבטיחה שהתוסף יקבל את הצבעים הנכונים.
Map<String, dynamic> buildThemePayloadFromScheme(
  ColorScheme cs, {
  required bool isDark,
}) {
  String hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  final fontFamily =
      Settings.getValue<String>(SettingsRepository.keyFontFamily) ??
      'Frank Ruhl Libre';
  final commentatorsFontFamily =
      Settings.getValue<String>(SettingsRepository.keyCommentatorsFontFamily) ??
      'Shofar';
  final fontSize =
      Settings.getValue<double>(SettingsRepository.keyFontSize) ?? 25.0;
  final commentatorsFontSize =
      Settings.getValue<double>(SettingsRepository.keyCommentatorsFontSize) ??
      22.0;
  final lineHeight =
      Settings.getValue<double>(SettingsRepository.keyLineHeight) ?? 1.5;

  return {
    'mode': isDark ? 'dark' : 'light',
    'colorScheme': {
      'primary': hex(cs.primary),
      'onPrimary': hex(cs.onPrimary),
      'primaryContainer': hex(cs.primaryContainer),
      'onPrimaryContainer': hex(cs.onPrimaryContainer),
      'secondary': hex(cs.secondary),
      'onSecondary': hex(cs.onSecondary),
      'secondaryContainer': hex(cs.secondaryContainer),
      'onSecondaryContainer': hex(cs.onSecondaryContainer),
      'tertiary': hex(cs.tertiary),
      'onTertiary': hex(cs.onTertiary),
      'tertiaryContainer': hex(cs.tertiaryContainer),
      'onTertiaryContainer': hex(cs.onTertiaryContainer),
      'surface': hex(cs.surface),
      'onSurface': hex(cs.onSurface),
      'onSurfaceVariant': hex(cs.onSurfaceVariant),
      'surfaceContainerLowest': hex(cs.surfaceContainerLowest),
      'surfaceContainerLow': hex(cs.surfaceContainerLow),
      'surfaceContainer': hex(cs.surfaceContainer),
      'surfaceContainerHigh': hex(cs.surfaceContainerHigh),
      'surfaceContainerHighest': hex(cs.surfaceContainerHighest),
      'error': hex(cs.error),
      'onError': hex(cs.onError),
      'errorContainer': hex(cs.errorContainer),
      'onErrorContainer': hex(cs.onErrorContainer),
      'outline': hex(cs.outline),
      'outlineVariant': hex(cs.outlineVariant),
      'inverseSurface': hex(cs.inverseSurface),
      'onInverseSurface': hex(cs.onInverseSurface),
      'inversePrimary': hex(cs.inversePrimary),
      'shadow': hex(cs.shadow),
      'scrim': hex(cs.scrim),
      'surfaceTint': hex(cs.surfaceTint),
    },
    'typography': {
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'commentatorsFontFamily': commentatorsFontFamily,
      'commentatorsFontSize': commentatorsFontSize,
    },
  };
}

// ===================================================================
// Helper: build CSS @font-face block with bundled fonts as data: URLs
// so the plugin WebView can resolve names like 'FrankRuhlCLM'.
// בלי זה — שמות הגופנים שאוצריא שולחת לתוסף מצביעים על font assets
// של Flutter שאינם זמינים ל-WebView, וב-macOS ה-fallback של המערכת
// לעברית נראה כגופן דקורטיבי (ראה תקלת תצוגת תוספים ב-macOS).
// ===================================================================
final Map<String, String> _fontFaceCache = {};

Future<String> _loadFontFaceCss(String fontFamily) async {
  if (fontFamily.isEmpty) return '';
  final cached = _fontFaceCache[fontFamily];
  if (cached != null) return cached;
  final assetPath = AppFonts.fontPaths[fontFamily];
  if (assetPath == null) return '';
  try {
    final bytes = await rootBundle.load(assetPath);
    final b64 = base64Encode(bytes.buffer.asUint8List());
    final css =
        "@font-face{font-family:'$fontFamily';src:url(data:font/ttf;base64,$b64) format('truetype');font-display:block;}";
    _fontFaceCache[fontFamily] = css;
    return css;
  } catch (_) {
    return '';
  }
}

/// בונה בלוק CSS עם `@font-face` עבור הגופנים המובנים שנבחרו בהגדרות,
/// כך שתוספים שמשתמשים בשמות הגופנים שמגיעים ב-theme יוכלו להציגם.
Future<String> buildPluginFontFaceCss() async {
  final fontFamily =
      Settings.getValue<String>(SettingsRepository.keyFontFamily) ??
      AppFonts.defaultFont;
  final commentatorsFontFamily =
      Settings.getValue<String>(SettingsRepository.keyCommentatorsFontFamily) ??
      AppFonts.defaultCommentatorsFont;
  final families = <String>{fontFamily, commentatorsFontFamily};
  final parts = <String>[];
  for (final family in families) {
    final css = await _loadFontFaceCss(family);
    if (css.isNotEmpty) parts.add(css);
  }
  return parts.join('\n');
}

/// שורת ערך AltToc עם ה-lineIndex שלה (או null לכותרת-אב ללא שורה), לבניית
/// העץ וחישוב ה-index ב-`getBookAltToc`.
typedef AltTocEntryRow = ({
  int id,
  int? parentId,
  int level,
  int? lineIndex,
  String text,
});

class PluginBridgeDependencies {
  final HistoryBloc historyBloc;
  final TabsBloc tabsBloc;
  final NavigationBloc navigationBloc;
  final CalendarCubit calendarCubit;
  final WorkspaceBloc workspaceBloc;
  final SearchRepository searchRepository;
  final PersonalNotesRepository personalNotesRepository;
  final BookOpenCoordinator bookOpenCoordinator;
  final Map<String, dynamic> Function() themePayloadBuilder;
  final Future<bool> Function({required String title, required String content})
  showConfirmDialog;
  final Future<bool> Function({
    required String title,
    required String content,
    required String subtitle,
  })
  showWarningDialog;
  final void Function(
    String downloadUrl, {
    PluginInstallReportContext? reportContext,
  })?
  requestPluginInstall;

  /// פותח דיאלוג בחירת תיקייה ומחזיר את הנתיב שנבחר, או `null` אם המשתמש
  /// ביטל. אופציונלי — אם לא סופק, האדפטר משתמש ב-[FilePicker.getDirectoryPath].
  /// קיים בעיקר כדי לאפשר הזרקה בבדיקות (בחירת תיקייה אמיתית אינה זמינה בהן).
  final Future<String?> Function({String? title})? pickFolder;

  /// פותח דיאלוג בחירת קובץ ומחזיר את הנתיב שנבחר, או `null` אם המשתמש ביטל.
  /// אופציונלי — אם לא סופק, האדפטר משתמש ב-[FilePicker.pickFiles].
  /// קיים בעיקר כדי לאפשר הזרקה בבדיקות (בחירת קובץ אמיתית אינה זמינה בהן).
  final Future<String?> Function({
    List<String>? allowedExtensions,
    String? title,
  })?
  pickFile;

  /// פותח דיאלוג „שמור בשם” ומחזיר את הנתיב שנבחר, או `null` אם המשתמש ביטל.
  /// **אינו כותב** את הקובץ — הכתיבה נעשית באדפטר. אופציונלי; אם לא
  /// סופק, האדפטר משתמש ב-[FilePicker.saveFile]. קיים כדי לאפשר הזרקה בבדיקות.
  final Future<String?> Function({
    required String suggestedName,
    List<String>? allowedExtensions,
    String? title,
  })?
  pickSaveLocation;

  /// פותר הפניה חופשית (שם ספר + ref, למשל "תלמוד ירושלמי עירובין פ\"ו ה\"ז")
  /// למיקום, דרך מנוע `find_ref` המודע-להקשר. מחזיר התאמות עם מיקום ה-index.
  /// אופציונלי — אם לא סופק, `openBookAtRef` נופל להתאמת TOC מקומית בלבד.
  final Future<List<({String title, int index, bool isPdf})>> Function(
    String reference,
  )?
  resolveReference;

  /// פותר הפניה לרמת שורה (פסוק/סעיף) דרך ה-heRef הפר-שורתי — מדויק מתחת
  /// לרזולוציית ה-TOC. אופציונלי — אם לא סופק או שאין התאמה, `openBookAtRef`
  /// ממשיך במסלולי ה-TOC הקיימים.
  final Future<int?> Function(TextBook book, String ref)? resolveRefToLine;

  /// מחזיר את מבני ה-AltToc של ספר לפי כותרתו. אופציונלי — אם לא סופק,
  /// האדפטר משתמש ב-[DatabaseLibraryProvider.instance]. קיים בעיקר להזרקה
  /// בבדיקות (ה-DB אינו זמין בהן).
  final Future<List<AltTocStructure>> Function(String bookTitle)?
  altStructuresProvider;

  /// מחזיר את ערכי מבנה ה-AltToc עם ה-lineIndex, לבניית העץ. אופציונלי —
  /// אם לא סופק, האדפטר משתמש ב-[DatabaseLibraryProvider.instance].
  final Future<List<AltTocEntryRow>> Function(int structureId)?
  altTocEntriesProvider;

  /// מקור הקישורים והמפרשים ל-`library.getLinks` / `library.getCommentators`.
  /// אופציונלי — ברירת המחדל היא [TextBookRepository] מעל מערכת הקבצים.
  final TextBookRepository? textBookRepository;

  /// סיכום יעדי הקישורים של ספר (`library.getLinkTargetsSummary`). אופציונלי —
  /// ברירת המחדל היא [DatabaseLibraryProvider.instance].
  final Future<({List<LinkTargetSummary> targets, int maxSourceLine})?>
  Function(String title, int categoryId)?
  linkTargetsSummaryProvider;

  /// טוען את תוכן הקישור (`library.getLinkContent`). אופציונלי — ברירת המחדל
  /// היא [Link.content] עם המטמון שלו.
  final Future<String> Function(Link link)? linkContentLoader;

  /// מקור-האמת של הסימניות (`bookmarks.*`). ה-bloc מחזיק את הרשימה בזיכרון
  /// וכותב לדיסק, ולכן כתיבה ישירה למחסן הייתה נדרסת. null = ה-API אינו זמין.
  final BookmarkBloc? bookmarkBloc;

  /// `plugin.backgroundDone` — התוסף מכריז שסיים את עבודת הרקע. מחווט רק
  /// במופע הרקע (PluginBackgroundHost); בדף התוסף נשאר null, כך שקריאה
  /// משם היא no-op בטוח. מחזיר אם הכיבוי אכן תוזמן.
  final bool Function()? onBackgroundInstanceDone;

  /// שולח אירוע ממוקד לתוסף (לחיצה על הודעת snack) — עם [instanceId]
  /// האירוע חוזר למופע שהציג את ההודעה. אופציונלי — ברירת המחדל היא
  /// [PluginRuntimeDispatcher.dispatchEventToPlugin]; קיים להזרקה בבדיקות.
  final Future<void> Function(
    String pluginId,
    String topic,
    Map<String, dynamic> payload, {
    String? instanceId,
  })?
  dispatchEventToPlugin;

  const PluginBridgeDependencies({
    required this.historyBloc,
    required this.tabsBloc,
    required this.navigationBloc,
    required this.calendarCubit,
    required this.workspaceBloc,
    required this.searchRepository,
    required this.personalNotesRepository,
    required this.bookOpenCoordinator,
    required this.themePayloadBuilder,
    required this.showConfirmDialog,
    required this.showWarningDialog,
    this.requestPluginInstall,
    this.pickFolder,
    this.pickFile,
    this.pickSaveLocation,
    this.resolveReference,
    this.resolveRefToLine,
    this.altStructuresProvider,
    this.altTocEntriesProvider,
    this.textBookRepository,
    this.linkTargetsSummaryProvider,
    this.linkContentLoader,
    this.bookmarkBloc,
    this.onBackgroundInstanceDone,
    this.dispatchEventToPlugin,
  });
}

/// חלון השורות המרבי לקריאת `library.getLinks` אחת, ותקרת הרשומות בתשובה.
const int _pluginLinksMaxWindowLines = 200;
const int _pluginLinksMaxRecords = 2000;

/// מספר הפריטים המרבי בקריאת `library.getLinkContent` אחת.
const int _pluginLinkContentMaxItems = 25;

typedef PluginRpcEventSink =
    Future<void> Function(
      String topic,
      Map<String, dynamic> payload,
    );

class _PluginNetworkRequest {
  final Uri uri;
  final String method;
  final Map<String, String>? headers;
  final String? body;
  final Duration timeout;

  const _PluginNetworkRequest({
    required this.uri,
    required this.method,
    required this.headers,
    required this.body,
    required this.timeout,
  });
}

// ===================================================================
// Bridge Adapter - strict 1:1 with plugin_system_plan.md
// ===================================================================
class PluginBridgeAdapter {
  final InstalledPlugin plugin;

  /// מזהה מופע הריצה שה-adapter משרת (טאב או 'background') — רישומי ה-UI
  /// וההדגשות ממופתחים לפיו, וניקויים ב-dispose מסיר רק אותם.
  final String instanceId;
  final PluginRegistryRepository _pluginRepo;
  final PluginBridgeDependencies _dependencies;
  final NotificationService _notificationService;
  final PluginDatabaseService _databaseService;
  final PluginHighlightRegistry _highlightRegistry;

  PluginBridgeAdapter(
    this.plugin, {
    required this._dependencies,
    this.instanceId = PluginInstanceIds.defaultForeground,
    PluginRegistryRepository? pluginRepository,
    NotificationService? notificationService,
    PluginDatabaseService? databaseService,
    this._networkFetchService,
    this._fileDownloadService,
    PluginFsService? fsService,
    PluginShortcutService? shortcutService,
    PluginFileServer? fileServer,
    PluginHighlightRegistry? highlightRegistry,
    PluginReportService? reportService,
  }) : _pluginRepo = pluginRepository ?? PluginRegistryRepository(),
       _pluginReportService = reportService,
       _notificationService = notificationService ?? NotificationService(),
       _databaseService = databaseService ?? PluginDatabaseService(),
       _highlightRegistry =
           highlightRegistry ?? PluginHighlightRegistry.instance,
       _pluginFsService = fsService,
       _pluginShortcutService = shortcutService,
       _fileServer = fileServer ?? PluginFileServer.instance;

  // שרת הקבצים הפנימי שמגיש קבצים אישיים ל-WebView (מופע יחיד לכל האפליקציה
  // כברירת מחדל; ניתן להזרקה לבדיקות).
  final PluginFileServer _fileServer;

  // שירות הורדת קבצים — מופע יחיד לכל adapter, נוצר עם השימוש הראשון
  // ומשוחרר ב-dispose (אחרת כל הורדה תדליף client ורישום ב-registry).
  PluginFileDownloadService? _fileDownloadService;
  PluginFileDownloadService get _downloadService =>
      _fileDownloadService ??= PluginFileDownloadService();

  // שירות פעולות קבצים (fs.extractZip/deleteFile) — מופע יחיד לכל adapter,
  // נוצר עם השימוש הראשון. אינו מחזיק משאבים ולכן אינו דורש שחרור ב-dispose.
  PluginFsService? _pluginFsService;
  PluginFsService get _fsService => _pluginFsService ??= PluginFsService();

  // שירות שליחת דיווחי משתמש על התוסף (feedback.report) — מופע יחיד לכל
  // adapter, נוצר עם השימוש הראשון.
  PluginReportService? _pluginReportService;
  PluginReportService get _reportService =>
      _pluginReportService ??= PluginReportService();

  // שירות יצירת קיצורי דרך (shortcut.create) — מופע יחיד לכל adapter.
  PluginShortcutService? _pluginShortcutService;
  PluginShortcutService get _shortcutService =>
      _pluginShortcutService ??= const PluginShortcutService();

  /// תיקיות שהמשתמש בחר במפורש דרך `ui.pickFolder` עבור התוסף בריצה זו.
  ///
  /// **גבול האבטחה לכתיבה/מחיקה בדיסק:** פעולות `fs.extractZip`,
  /// `fs.deleteFile` ו-`network.download` עם `destPath` מותרות אך ורק על
  /// נתיבים בתוך אחת מהתיקיות הללו. כך גישת התוסף לדיסק נובעת מהסכמה מפורשת
  /// של המשתמש בדיאלוג בחירת התיקייה — ולא מהרשאת manifest. הקבוצה מאופסת עם
  /// `dispose` (טעינה/השבתה מחדש של התוסף).
  final Set<String> _grantedFolders = <String>{};

  // שירות בקשות HTTP — מופע יחיד לכל adapter; ניתן להזרקה
  // לבדיקות, נוצר עם השימוש הראשון אם לא הוזרק, ומשוחרר ב-dispose.
  PluginNetworkFetchService? _networkFetchService;
  PluginNetworkFetchService get _fetchService =>
      _networkFetchService ??= PluginNetworkFetchService();

  // bookId → טקסט מלא של הספר (מטמון LRU קצר, per adapter instance) עבור
  // getBookContent. ראה _loadBookRawText.
  final Map<PluginBookIdentityKey, String> _bookContentCache = {};
  static const int _bookContentCacheMaxEntries = 4;

  Library? _bookIndexLibrary;
  Map<int, List<Book>> _booksById = const {};
  Map<String, List<Book>> _booksByTitle = const {};
  Map<String, Book> _booksByUid = const {};
  Map<String, Book> _booksByIndexedPath = const {};
  final Map<String, Future<void> Function()> _activeSearchStreams = {};
  final Set<String> _pendingSearchCancellations = {};
  final Map<String, Future<void> Function()> _activeNetworkFetchStreams = {};
  final Set<String> _pendingNetworkFetchCancellations = {};

  static const _searchStreamEvent = '__otzaria.search.query.chunk';
  static const _networkFetchStreamEvent = '__otzaria.network.fetchStream.chunk';
  static const _streamIdKey = '__streamId';
  static const _cancelStreamIdKey = '__cancelStreamId';
  static const _maxConcurrentSearchStreams = 4;
  static const _maxConcurrentNetworkFetchStreams = 4;
  static const _maxNetworkFetchChunkCodeUnits = 32 * 1024;
  static const _maxSearchDuration = Duration(minutes: 2);
  static const _searchIdleTimeout = Duration(seconds: 30);
  static final _streamIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static bool isSearchCancellationPayload(Map<String, dynamic> args) {
    if (args.length != 1) return false;
    final streamId = args[_cancelStreamIdKey];
    return streamId is String && _streamIdPattern.hasMatch(streamId);
  }

  static bool isNetworkFetchCancellationPayload(Map<String, dynamic> args) {
    if (args.length != 1) return false;
    final streamId = args[_cancelStreamIdKey];
    return streamId is String && _streamIdPattern.hasMatch(streamId);
  }

  void dispose() {
    // מסיר רק את תרומות המופע הזה — מופע אחר של אותו תוסף ממשיך לתפקד,
    // וה-dedup בציור חושף את העותקים שלו.
    final key = (pluginId: plugin.pluginId, instanceId: instanceId);
    ContextMenuRegistry.instance.removeInstance(key);
    PluginToolbarRegistry.instance.removeInstance(key);
    _highlightRegistry.removeInstance(key);
    for (final cancel in _activeSearchStreams.values) {
      unawaited(cancel());
    }
    _activeSearchStreams.clear();
    _pendingSearchCancellations.clear();
    for (final cancel in _activeNetworkFetchStreams.values) {
      unawaited(cancel());
    }
    _activeNetworkFetchStreams.clear();
    _pendingNetworkFetchCancellations.clear();
    _networkFetchService?.dispose();
    _fileDownloadService?.dispose();
    _bookIndexLibrary = null;
    _booksById = const {};
    _booksByTitle = const {};
    _booksByUid = const {};
    _booksByIndexedPath = const {};
  }

  /// טוען את הטקסט המלא של ספר עבור `getBookContent`, עם מטמון LRU קצר
  /// (per adapter instance).
  ///
  /// `getBookContent` מחזירה מקטע באמצעות `substring`, והתוסף טוען ספר מלא
  /// ב-chunks של 5000 תווים — כך שטעינה אחת מחייבת עשרות קריאות RPC רצופות.
  /// בלי מטמון כל קריאה טוענת מחדש את כל הספר מה-DB (O(n²)), בזבוז שמתחדד
  /// כשתוסף מבצע polling/prefetch אגרסיבי. המטמון מצמצם זאת ל-O(n) לספר
  /// ומנטרל את עלות ה-IO החוזרת.
  ///
  /// המטמון מוגבל ל-[_bookContentCacheMaxEntries] ספרים ומתאפס עם dispose של
  /// ה-adapter (טעינה/השבתה מחדש של התוסף). לכן ייתכן חלון קצר של תוכן
  /// לא-מעודכן אם המשתמש עורך ספר בזמן שתוסף קורא אותו — מקרה קצה נדיר
  /// בנתיב קריאה-בלבד.
  Future<String> _loadBookRawText(Book book) async {
    final key = PluginBookIdentity.keyOf(book);
    final cached = _bookContentCache.remove(key);
    if (cached != null) {
      _bookContentCache[key] = cached; // רענון מיקום ב-LRU
      return cached;
    }
    // איתור ה-TextBook מהקטלוג כדי לקבל categoryId/fileType נכונים מה-metadata.
    // בלי זה, השכבה התחתונה מקבעת fileType='txt' ונכשלת לגבי ספרים בפורמט אחר
    // אצל משתמשים שאין להם קבצי טקסט נפרדים בדיסק (רק seforim.db).
    final String rawText;
    if (book is TextBook) {
      rawText = await TextBookRepository(
        fileSystem: FileSystemData.instance,
      ).getBookContent(book);
    } else {
      rawText = await DataRepository.instance.getBookText(book.title);
    }
    _bookContentCache[key] = rawText;
    if (_bookContentCache.length > _bookContentCacheMaxEntries) {
      _bookContentCache.remove(_bookContentCache.keys.first);
    }
    return rawText;
  }

  Future<dynamic> execute(
    String domain,
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    switch (domain) {
      case 'app':
        return await _handleApp(action, args);
      case 'library':
        return await _handleLibrary(action, args);
      case 'search':
        return await _handleSearch(action, args, eventSink: eventSink);
      case 'reader':
        return await _handleReader(action, args);
      case 'navigation':
        return await _handleNavigation(action, args);
      case 'notes':
        return await _handleNotes(action, args);
      case 'ui':
        return await _handleUi(action, args);
      case 'storage':
        return await _handleStorage(action, args);
      case 'settings':
        return await _handleSettings(action, args);
      case 'calendar':
        return await _handleCalendar(action, args);
      case 'publishedData':
        return await _handlePublishedData(action, args);
      case 'feedback':
        return await _handleFeedback(action, args);
      case 'history':
        return await _handleHistory(action, args);
      case 'bookmarks':
        return await _handleBookmarks(action, args);
      case 'tools':
        return await _handleTools(action, args);
      case 'notifications':
        return await _handleNotifications(action, args);
      case 'database':
        return _handleDatabase(action, args);
      case 'network':
        return await _handleNetwork(action, args, eventSink: eventSink);
      case 'fs':
        return await _handleFs(action, args);
      case 'shortcut':
        return await _handleShortcut(action, args);
      case 'plugin':
        return await _handlePlugin(action, args);
      default:
        throw Exception("error.unknown_method: Unknown domain: $domain");
    }
  }

  // ----------------------------------------------------------------
  // app.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleApp(String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'getInfo':
        final packageInfo = await PackageInfo.fromPlatform();
        return {
          'version': packageInfo.version,
          'buildNumber': packageInfo.buildNumber,
          'platform': Platform.operatingSystem,
        };
      case 'getTheme':
        return _dependencies.themePayloadBuilder();
      case 'getLocale':
        // שפת הממשק שבחר המשתמש (או שפת המערכת בזיהוי אוטומטי) — לתוספים
        // רב-לשוניים. 'language' הוא קוד השפה ('he'/'en'); 'locale' נשמר
        // בצורתו הישנה (he-IL) לתאימות.
        return pluginLocalePayload(
          code: Settings.getValue<String>(
            SettingsRepository.keySettingsLanguage,
          ),
        );
      case 'getUserEmail':
        final email =
            Settings.getValue<String>(
              SettingsRepository.keyErrorReportSenderEmail,
            ) ??
            '';
        return {'email': email.trim()};
      case 'openUrl':
        final url = args['url'] as String?;
        if (url == null || url.isEmpty) {
          throw Exception('error.invalid_params: url required');
        }
        final uri = Uri.tryParse(url);
        if (uri == null) {
          throw Exception('error.invalid_params: invalid URL');
        }
        // רק http/https — חוסם file://, javascript:, ומטפלי-פרוטוקול מותקנים
        // (otzaria:// וכו') שהיו מאפשרים לתוסף להריץ פעולות מחוץ לדפדפן.
        if (uri.scheme != 'http' && uri.scheme != 'https') {
          throw Exception('error.forbidden: only http/https URLs are allowed');
        }
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          throw Exception('error.internal: failed to open URL');
        }
        return true;
      case 'getConnectivity':
        final forceRefresh = args['forceRefresh'];
        if (forceRefresh != null && forceRefresh is! bool) {
          throw Exception('error.invalid_params: forceRefresh must be boolean');
        }
        return (await ConnectivityStatusService.instance.snapshot(
          forceRefresh: forceRefresh as bool? ?? false,
        )).toJson();
      case 'getGrantedPermissions':
        return {'permissions': await _getGrantedPermissions()};
      default:
        throw Exception("error.unknown_method: Unknown action in app: $action");
    }
  }

  // ----------------------------------------------------------------
  // library.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleLibrary(
    String action,
    Map<String, dynamic> args,
  ) async {
    final library = await DataRepository.instance.library;
    switch (action) {
      case 'findBooks':
        final query = args['query']?.toString() ?? '';
        final limit = args['limit'] as int? ?? 20;
        // query ריק = עיון בכל הספרים (תאימות לאחור). אחרת מנוע החיפוש המדורג
        // של הספרייה — מחזיר ספר בסיסי/התאמה טובה לפני פירושים, כך שתוסף
        // שלוקח את התוצאה הראשונה יקבל את הספר הנכון (ולא פירוש על
        // "ירושלמי עירובין").
        final List<dynamic> matched = query.trim().isEmpty
            ? library.getAllBooks()
            : await DataRepository.instance.findBooks(query, null);
        return matched
            .take(limit)
            // spec: returns [{id, type, bookId, title, author?, topics?}]
            .map(
              (b) => {
                ...PluginBookIdentity.toJsonWithUid(b as Book),
                'title': b.title,
              },
            )
            .toList();
      case 'getBookMetadata':
        // spec: accepts id, bookId (= title in otzaria), type — all optional,
        // all supplied fields must match the same book.
        {
          final bookId = (args['bookId'] ?? args['title']) as String?;
          if (PluginBookIdentity.parseId(args['id']) == null &&
              bookId == null &&
              (args['bookUid'] as String?)?.trim().isNotEmpty != true) {
            throw Exception(
              'error.invalid_params: id, bookUid or bookId required',
            );
          }
          final book = _findPluginBook(library, args);
          if (book == null) return null;
          return {
            ...PluginBookIdentity.toJsonWithUid(book),
            'title': book.title,
            'topics': book.topics,
            'categoryPath': FacetHelper.resolveCategoryPath(book),
          };
        }
      case 'resolveBooks':
        {
          final rawItems = args['items'];
          if (rawItems is! List || rawItems.length > 100) {
            throw Exception(
              'error.invalid_params: items must be an array with at most 100 entries',
            );
          }
          final identities = <Map<String, dynamic>>[];
          for (final item in rawItems) {
            if (item is! Map) {
              throw Exception(
                'error.invalid_params: items entries must be objects',
              );
            }
            identities.add(Map<String, dynamic>.from(item));
          }
          final access = DeclarativeLibraryBookAccess.otzaria(
            _dependencies.bookOpenCoordinator,
          );
          final books = await access.findUniqueBooks(identities);
          return [
            for (final book in books)
              if (book == null)
                null
              else
                {
                  ...PluginBookIdentity.toJsonWithUid(book),
                  'title': book.title,
                  'categoryPath': FacetHelper.resolveCategoryPath(book),
                },
          ];
        }
      case 'resolveCategoryPaths':
        {
          // spec: resolveCategoryPaths({ ids }) — נתיב הקטגוריה בעץ הספרייה
          // לכל מזהה ספר, מיושר לסדר הקלט (null למזהה לא מוכר). מסלול bulk:
          // ספק תוצאות חיצוני מסווג אינדקס שלם (עד תקרת האינדקס של מדור
          // החיפוש) בקריאה אחת, במקום קריאת resolveBooks לכל 100 מזהים.
          final rawIds = args['ids'];
          if (rawIds is! List || rawIds.length > 20000) {
            throw Exception(
              'error.invalid_params: ids must be an array with at most 20000 entries',
            );
          }
          final bookById = <int, Book>{
            for (final book in library.getAllBooks())
              if (book.id != null) book.id!: book,
          };
          return [
            for (final raw in rawIds)
              if (raw is int && bookById[raw] != null)
                FacetHelper.resolveCategoryPath(bookById[raw]!)
              else
                null,
          ];
        }
      case 'listRecentBooks':
        final historyState = _dependencies.historyBloc.state;
        if (historyState is! HistoryLoaded) return [];
        return historyState.history
            .where((b) => !b.isSearch)
            .take(20)
            .map(
              (b) => {
                ...PluginBookIdentity.toJsonWithUid(b.book),
                'title': b.book.title,
                'ref': b.ref,
              },
            )
            .toList();
      case 'getBookContent':
        final book = _findPluginBook(library, args);
        final bookId = (args['bookId'] ?? args['title']) as String?;
        if (book == null && bookId == null) {
          throw Exception('error.not_found: book not found');
        }
        final rawText = book == null
            ? await DataRepository.instance.getBookText(bookId!)
            : await _loadBookRawText(book);
        final limit = args['limit'] as int? ?? 1000;
        final offset = args['offset'] as int? ?? 0;
        final section = args['section'] as String?;
        int startIndex = offset;
        if (section != null && section.isNotEmpty) {
          final idx = rawText.indexOf(section);
          // ה-offset נספר יחסית למיקום ה-section, לא לתחילת הטקסט
          if (idx >= 0) startIndex = idx + offset;
        }
        final clampedLimit = limit > 5000 ? 5000 : limit;
        final end = (startIndex + clampedLimit).clamp(0, rawText.length);
        return rawText.substring(startIndex.clamp(0, rawText.length), end);
      case 'getBookToc':
        final book = _findPluginBook(library, args);
        if (book is TextBook) {
          final toc = flattenToc(await book.tableOfContents);
          return toc
              .map((e) => {'text': e.text, 'index': e.index, 'level': e.level})
              .toList();
        }
        return [];
      case 'listBookAltStructures':
        {
          final bookId = args['bookId'] ?? args['title'];
          if (bookId is! String || bookId.isEmpty) {
            throw Exception('error.invalid_params: bookId required');
          }
          final structures = await _loadAltStructures(bookId);
          // ה-id הפנימי של ה-DB אינו יציב בין גרסאות ספרייה — לא נחשף לתוסף.
          return structures
              .map(
                (s) => {'key': s.key, 'title': s.title, 'heTitle': s.heTitle},
              )
              .toList();
        }
      case 'getBookAltToc':
        {
          final bookId = args['bookId'] ?? args['title'];
          if (bookId is! String || bookId.isEmpty) {
            throw Exception('error.invalid_params: bookId required');
          }
          final rawKey = args['structureKey'];
          if (rawKey != null && (rawKey is! String || rawKey.isEmpty)) {
            throw Exception(
              'error.invalid_params: structureKey must be a string',
            );
          }
          final structureKey = rawKey as String?;
          final structures = await _loadAltStructures(bookId);
          if (structures.isEmpty) {
            // ספר בלי AltToc (או ספר אישי/קובץ). key שלא קיים → שגיאה.
            if (structureKey != null) {
              throw Exception(
                'error.not_found: structureKey "$structureKey" not found',
              );
            }
            return [];
          }
          AltTocStructure selected;
          if (structureKey == null) {
            selected = structures.first;
          } else {
            final match = structures
                .where((s) => s.key == structureKey)
                .toList();
            if (match.isEmpty) {
              throw Exception(
                'error.not_found: structureKey "$structureKey" not found',
              );
            }
            selected = match.first;
          }
          final entries = await _loadAltTocEntries(selected.id);
          return _flattenAltToc(entries);
        }
      case 'getTree':
        // spec: getTree({ path?, includeBooks? }) -> מבנה עץ הספרייה המלא
        // path אופציונלי: מצמצם את העץ לתת-קטגוריה לפי הנתיב שלה (כמו '/תנך/ראשונים').
        //   ברירת מחדל: כל הספרייה.
        // includeBooks אופציונלי (ברירת מחדל true): האם לכלול את רשימות הספרים.
        final path = args['path']?.toString();
        final includeBooks = args['includeBooks'] as bool? ?? true;
        final root = (path == null || path.isEmpty || path == '/')
            ? library
            : _findCategoryByPath(library, path);
        if (root == null) return null;
        return _categoryToTree(root, includeBooks: includeBooks);
      case 'getCommentators':
        return await _getCommentators(library, args);
      case 'getLinks':
        return await _getLinks(library, args);
      case 'getLinkTargetsSummary':
        return await _getLinkTargetsSummary(library, args);
      case 'getLinkContent':
        return await _getLinkContent(args);
      default:
        throw Exception(
          'error.unknown_method: Unknown action in library: $action',
        );
    }
  }

  // ----------------------------------------------------------------
  // library.* — מפרשים וקישורים
  // ----------------------------------------------------------------

  TextBookRepository get _linksRepository =>
      _dependencies.textBookRepository ??
      TextBookRepository(fileSystem: FileSystemData.instance);

  /// מאתר את ספר הטקסט של קריאות הקישורים. `bookId` (=כותרת) עם `categoryId`
  /// אופציונלי שמכריע בין ספרים שווי-שם; אחרת נופל לזיהוי הרגיל לפי `id`.
  TextBook? _findLinksTextBook(Library library, Map<String, dynamic> args) {
    _ensureBookIndex(library);
    final bookUid = (args['bookUid'] as String?)?.trim();
    if (bookUid != null && bookUid.isNotEmpty) {
      final byUid = _booksByUid[bookUid];
      if (byUid is TextBook) return byUid;
    }
    final bookId = (args['bookId'] ?? args['title']) as String?;
    if (PluginBookIdentity.parseId(args['id']) == null && bookId != null) {
      final categoryId = args['categoryId'] as int?;
      return (_booksByTitle[bookId] ?? const <Book>[])
          .whereType<TextBook>()
          .where((b) => categoryId == null || b.categoryId == categoryId)
          .firstOrNull;
    }
    final book = _findPluginBook(library, args);
    return book is TextBook ? book : null;
  }

  /// קורא מספר שורה מה-wire (0-based) ומאמת שהוא שלם אי-שלילי.
  int _requireWireLine(dynamic raw, String name) {
    if (raw is! int || raw < 0) {
      throw Exception(
        'error.invalid_params: $name must be a non-negative integer',
      );
    }
    return raw;
  }

  List<String>? _optionalStringList(dynamic raw, String name) {
    if (raw == null) return null;
    if (raw is! List) {
      throw Exception('error.invalid_params: $name must be an array');
    }
    final values = <String>[];
    for (final item in raw) {
      if (item is! String || item.trim().isEmpty) {
        throw Exception('error.invalid_params: $name entries must be strings');
      }
      values.add(item.trim());
    }
    return values;
  }

  Future<dynamic> _getCommentators(
    Library library,
    Map<String, dynamic> args,
  ) async {
    final rawStart = args['startLine'];
    final rawEnd = args['endLine'];
    if ((rawStart == null) != (rawEnd == null)) {
      throw Exception(
        'error.invalid_params: startLine and endLine must be given together',
      );
    }
    final book = _findLinksTextBook(library, args);
    if (book == null) throw Exception('error.not_found: book not found');

    final List<CommentatorInfo> commentators;
    Set<String> rare = const {};
    if (rawStart != null) {
      final startLine = _requireWireLine(rawStart, 'startLine');
      final endLine = _requireWireLine(rawEnd, 'endLine');
      if (endLine < startLine) {
        throw Exception('error.invalid_params: endLine must be >= startLine');
      }
      commentators = await _linksRepository.getCommentatorsInLineRange(
        book,
        startLine: startLine,
        endLine: endLine,
      );
    } else {
      final detailed = await _linksRepository.getCommentatorsDetailed(book);
      commentators = detailed.commentators;
      rare = detailed.rare;
    }

    if (args['grouped'] as bool? ?? false) {
      final titles = [for (final c in commentators) c.title];
      final eras = await splitByEra(titles);
      return {
        'groups': _commentatorGroupsToJson(
          buildCommentatorGroups(eras, titles),
        ),
      };
    }

    return {
      'commentators': [
        for (final c in commentators)
          {
            'title': c.title,
            if (c.author != null && c.author!.isNotEmpty) 'author': c.author,
            'linkCount': c.linkCount,
            'isRare': rare.contains(c.title),
          },
      ],
    };
  }

  List<Map<String, dynamic>> _commentatorGroupsToJson(
    List<CommentatorGroup> groups,
  ) => [
    for (final group in groups)
      if (group.commentators.isNotEmpty)
        {'title': group.title, 'commentators': group.commentators},
  ];

  Future<dynamic> _getLinks(Library library, Map<String, dynamic> args) async {
    final startLine = _requireWireLine(args['startLine'], 'startLine');
    final endLine = _requireWireLine(args['endLine'], 'endLine');
    if (endLine < startLine) {
      throw Exception('error.invalid_params: endLine must be >= startLine');
    }
    if (endLine - startLine + 1 > _pluginLinksMaxWindowLines) {
      throw Exception(
        'error.invalid_params: line window must not exceed '
        '$_pluginLinksMaxWindowLines lines',
      );
    }
    final targetTitles = _optionalStringList(
      args['targetTitles'],
      'targetTitles',
    );
    final connectionTypes = _optionalStringList(
      args['connectionTypes'],
      'connectionTypes',
    );
    final includeAnchors = args['includeAnchors'] as bool? ?? false;

    final book = _findLinksTextBook(library, args);
    if (book == null) throw Exception('error.not_found: book not found');

    final links = await _linksRepository.getBookLinksInRange(
      book,
      startIndex: startLine,
      endIndex: endLine,
      targetBookTitles: targetTitles,
    );

    final titlesFilter = targetTitles?.toSet();
    final typesFilter = connectionTypes?.map(LinkTypes.normalize).toSet();
    final records = <Map<String, dynamic>>[];
    var truncated = false;
    for (final link in links) {
      final targetTitle = getTitleFromPath(link.path2);
      if (titlesFilter != null && !titlesFilter.contains(targetTitle)) continue;
      if (typesFilter != null &&
          !typesFilter.contains(LinkTypes.normalize(link.connectionType)) &&
          !typesFilter.contains(LinkTypes.canonicalType(link.connectionType))) {
        continue;
      }
      if (records.length >= _pluginLinksMaxRecords) {
        truncated = true;
        break;
      }
      // index1/index2 הם 1-based במודל; ה-wire כולו 0-based — זו נקודת ההמרה.
      records.add({
        'sourceLine': link.index1 - 1,
        'targetTitle': targetTitle,
        'targetLine': link.index2 - 1,
        'targetLineEnd': link.index2End == null ? null : link.index2End! - 1,
        'targetHeRef': link.heRef,
        'connectionType': link.connectionType,
        'isCommentary': LinkTypes.isDependentTextLink(link.connectionType),
        'targetIsUserBook': link.targetIsUserBook,
        'targetCategoryId': link.targetCategoryId,
        if (includeAnchors) ...?_linkAnchorJson(link),
      });
    }
    return {'links': records, 'truncated': truncated};
  }

  Map<String, dynamic>? _linkAnchorJson(Link link) {
    final span = link.anchorSpans.firstOrNull;
    final start = span?.start ?? link.anchorStart;
    if (start == null) return null;
    return {
      'anchor': {
        'start': start,
        'end': span?.end ?? link.anchorEnd,
        'label': span?.label ?? link.anchorLabel,
      },
    };
  }

  Future<dynamic> _getLinkTargetsSummary(
    Library library,
    Map<String, dynamic> args,
  ) async {
    final book = _findLinksTextBook(library, args);
    if (book?.categoryId == null) {
      throw Exception('error.not_found: book not found');
    }
    final provider =
        _dependencies.linkTargetsSummaryProvider ??
        DatabaseLibraryProvider.instance.getBookLinkTargetsSummary;
    final summary = await provider(book!.title, book.categoryId!);
    if (summary == null) {
      throw Exception('error.internal: link targets summary unavailable');
    }
    return {
      'targets': [
        for (final target in summary.targets)
          {
            'targetTitle': target.targetTitle,
            'connectionType': target.connectionType,
            'linkCount': target.linkCount,
          },
      ],
      // maxSourceLine מגיע 1-based מהמסד; ‎-1‎ = לספר אין קישורים כלל.
      'maxSourceLine': summary.maxSourceLine - 1,
    };
  }

  Future<dynamic> _getLinkContent(Map<String, dynamic> args) async {
    final rawItems = args['links'];
    if (rawItems is! List ||
        rawItems.isEmpty ||
        rawItems.length > _pluginLinkContentMaxItems) {
      throw Exception(
        'error.invalid_params: links must be an array with at most '
        '$_pluginLinkContentMaxItems entries',
      );
    }
    final loader = _dependencies.linkContentLoader;
    final items = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      if (raw is! Map) {
        throw Exception('error.invalid_params: links entries must be objects');
      }
      final targetTitle = raw['targetTitle'];
      final targetLine = raw['targetLine'];
      if (targetTitle is! String || targetTitle.isEmpty || targetLine is! int) {
        throw Exception(
          'error.invalid_params: targetTitle and targetLine are required',
        );
      }
      final targetLineEnd = raw['targetLineEnd'];
      final link = Link(
        heRef: targetTitle,
        index1: 1,
        path2: targetTitle,
        index2: targetLine + 1,
        index2End: targetLineEnd is int ? targetLineEnd + 1 : null,
        connectionType: LinkTypes.commentary,
        targetCategoryId: raw['targetCategoryId'] as int?,
        targetIsUserBook: raw['targetIsUserBook'] as bool? ?? false,
      );
      try {
        items.add({'content': await (loader?.call(link) ?? link.content)});
      } catch (_) {
        items.add(const {'error': 'not_found'});
      }
    }
    return {'items': items};
  }

  /// טוען את מבני ה-AltToc של ספר (דרך התלות המוזרקת או ה-DB).
  Future<List<AltTocStructure>> _loadAltStructures(String bookId) {
    final provider =
        _dependencies.altStructuresProvider ??
        DatabaseLibraryProvider.instance.getAlternativeStructuresForBook;
    return provider(bookId);
  }

  /// טוען את ערכי מבנה ה-AltToc עם ה-lineIndex (דרך התלות המוזרקת או ה-DB).
  Future<List<AltTocEntryRow>> _loadAltTocEntries(int structureId) {
    final provider =
        _dependencies.altTocEntriesProvider ??
        DatabaseLibraryProvider.instance.getAltTocEntriesWithLineIndex;
    return provider(structureId);
  }

  /// מסדר את ערכי ה-AltToc בסדר מסמך (depth-first) למערך שטוח זהה במבנה
  /// ל-`getBookToc`: `[{text, index, level}]`.
  ///
  /// ל-index של ערך ללא שורה (בעיקר כותרות-אב) נלקח ה-lineIndex של הצאצא
  /// הראשון (depth-first) שיש לו שורה. ערך שאין לו ולאף צאצא שורה — מושמט.
  List<Map<String, dynamic>> _flattenAltToc(List<AltTocEntryRow> entries) {
    final childrenByParent = <int?, List<AltTocEntryRow>>{};
    for (final e in entries) {
      childrenByParent.putIfAbsent(e.parentId, () => []).add(e);
    }

    int? firstDescendantLine(AltTocEntryRow node) {
      if (node.lineIndex != null) return node.lineIndex;
      for (final child in childrenByParent[node.id] ?? const []) {
        final found = firstDescendantLine(child);
        if (found != null) return found;
      }
      return null;
    }

    final result = <Map<String, dynamic>>[];
    void visit(AltTocEntryRow node) {
      final index = node.lineIndex ?? firstDescendantLine(node);
      if (index != null) {
        result.add({'text': node.text, 'index': index, 'level': node.level});
      }
      for (final child in childrenByParent[node.id] ?? const []) {
        visit(child);
      }
    }

    for (final root in childrenByParent[null] ?? const []) {
      visit(root);
    }
    return result;
  }

  /// בונה ייצוג JSON רקורסיבי של קטגוריה כולל תתי-קטגוריות וספרים.
  ///
  /// [includeBooks] קובע האם לכלול את רשימת הספרים בכל קטגוריה.
  Map<String, dynamic> _categoryToTree(
    Category category, {
    required bool includeBooks,
  }) {
    final node = <String, dynamic>{
      'title': category.title,
      'path': category.path,
      'categories': category.subCategories
          .map((c) => _categoryToTree(c, includeBooks: includeBooks))
          .toList(),
    };
    if (includeBooks) {
      node['books'] = category.books.map(_bookToTreeEntry).toList();
    }
    return node;
  }

  /// ממפה ספר לרשומה בעץ: id, type, bookId (= title באוצריא), title, author?, topics?.
  Map<String, dynamic> _bookToTreeEntry(Book book) {
    final entry = <String, dynamic>{
      ...PluginBookIdentity.toJsonWithUid(book),
      'title': book.title,
    };
    if (book.author != null && book.author!.isNotEmpty) {
      entry['author'] = book.author;
    }
    if (book.topics.isNotEmpty) {
      entry['topics'] = book.topics;
    }
    return entry;
  }

  // ----------------------------------------------------------------
  // Book identity helpers (Plugin SDK)
  // ----------------------------------------------------------------

  /// מחזיר את סוג הספר כמחרוזת עבור ה-Plugin SDK.
  Book? _findPluginBook(Library library, Map<String, dynamic> args) {
    _ensureBookIndex(library);
    // `bookUid` הוא מזהה יציב וחד-משמעי — אם סופק, פותר ישירות בלי ניחוש.
    final bookUid = (args['bookUid'] as String?)?.trim();
    if (bookUid != null && bookUid.isNotEmpty) {
      final byUid = _booksByUid[bookUid];
      if (byUid != null) return byUid;
    }
    final id = PluginBookIdentity.parseId(args['id']);
    final bookId = (args['bookId'] ?? args['title']) as String?;
    final type = args['type'] as String?;
    final source = args['source'] as String?;
    if (id == null && bookId == null) return null;
    final candidates = id != null
        ? (_booksById[id] ?? const <Book>[])
        : (_booksByTitle[bookId] ?? const <Book>[]);
    final found = candidates
        .where(
          (book) => PluginBookIdentity.matches(
            book,
            id: id,
            bookId: bookId,
            type: type,
            source: source,
          ),
        )
        .toList();
    if (found.isEmpty) return null;
    if ((id != null || type != null || source != null) && found.length != 1) {
      return null;
    }
    return found.first;
  }

  void _ensureBookIndex(Library library) {
    if (identical(_bookIndexLibrary, library)) return;
    final byId = <int, List<Book>>{};
    final byTitle = <String, List<Book>>{};
    final byUid = <String, Book>{};
    for (final book in library.getAllBooks()) {
      if (book.id case final int id) {
        (byId[id] ??= []).add(book);
      }
      (byTitle[book.title] ??= []).add(book);
      byUid[PluginBookIdentity.uidOf(book)] = book;
    }
    _bookIndexLibrary = library;
    _booksById = byId;
    _booksByTitle = byTitle;
    _booksByUid = byUid;
    _booksByIndexedPath = PluginSearchApi.booksByIndexedFilePath(library);
  }

  // ----------------------------------------------------------------

  /// מאתר תת-קטגוריה לפי נתיב מלא (למשל '/תנך/ראשונים'), או null אם לא נמצאה.
  Category? _findCategoryByPath(Library library, String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    Category current = library;
    for (final segment in segments) {
      final next = current.subCategories
          .where((c) => c.title == segment)
          .firstOrNull;
      if (next == null) return null;
      current = next;
    }
    return current;
  }

  // ----------------------------------------------------------------
  // search.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleSearch(
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    switch (action) {
      case 'fullText':
        final query = args['query'] as String?;
        final limit = args['limit'] as int? ?? 50;
        if (query == null || query.isEmpty) return [];
        final results = await _dependencies.searchRepository.searchTexts(
          query,
          [],
          limit,
        );
        return results
            .map(
              (r) => {
                'type': r.isPdf ? 'pdf' : 'text',
                'book': r.title,
                'text': r.text,
                'index': r.segment.toInt(),
              },
            )
            .toList();
      case 'getOptions':
        return PluginSearchApi.describeOptions();
      case 'query':
        if (args[_cancelStreamIdKey] case final String streamId) {
          return _cancelPluginSearch(streamId);
        }
        return await _runPluginSearch(args, eventSink: eventSink);
      default:
        throw Exception(
          "error.unknown_method: Unknown action in search: $action",
        );
    }
  }

  /// מזרים את `search.query` באותו מסלול chunks של מסך החיפוש.
  Future<Map<String, dynamic>> _runPluginSearch(
    Map<String, dynamic> args, {
    required PluginRpcEventSink? eventSink,
  }) async {
    final streamId = args[_streamIdKey];
    if (streamId is! String || !_streamIdPattern.hasMatch(streamId)) {
      throw Exception('error.invalid_params: invalid internal stream id');
    }
    if (eventSink == null) {
      throw Exception('error.internal: search stream transport unavailable');
    }
    if (_pendingSearchCancellations.remove(streamId)) {
      return {'completed': false, 'cancelled': true};
    }
    if (_activeSearchStreams.containsKey(streamId)) {
      throw Exception('error.invalid_params: duplicate search stream id');
    }
    if (_activeSearchStreams.length >= _maxConcurrentSearchStreams) {
      throw Exception('error.rate_limited: too many active search streams');
    }

    final publicArgs = Map<String, dynamic>.of(args)..remove(_streamIdKey);
    final request = PluginSearchRequest.fromArgs(publicArgs)
      ..validateAgainstQuery();
    final library = await DataRepository.instance.library;
    final facets = PluginSearchApi.resolveFacets(
      publicArgs,
      findBook: (identity) => _findPluginBook(library, identity),
    );
    final stream = _dependencies.searchRepository.searchTextsStreamWithCounts(
      request.sanitizedQuery,
      facets,
      request.limit,
      offset: request.offset,
      chunkSize: 50,
      order: request.order,
      searchMode: request.searchMode,
      distance: request.distance,
      negativeQuery: request.sanitizedNegativeQuery,
      negativeDistance: request.negativeDistance,
      scope: request.proximityScope,
      negativeScope: request.negativeProximityScope,
      customSpacing: request.effectiveCustomSpacing,
      negativeCustomSpacing: request.effectiveNegativeCustomSpacing,
      alternativeWords: request.effectiveAlternativeWords,
      negativeAlternativeWords: request.effectiveNegativeAlternativeWords,
      searchOptions: request.effectiveSearchOptions,
      negativeSearchOptions: request.effectiveNegativeSearchOptions,
      grouping: request.grouping,
      wordMatchMode: request.wordMatchMode,
      wordMatchCount: request.wordMatchCount,
    );
    final iterator = StreamIterator<SearchStreamUpdate>(stream);
    var cancelled = false;
    var expired = false;
    Future<void> cancel() async {
      cancelled = true;
      await iterator.cancel();
    }

    if (_pendingSearchCancellations.remove(streamId)) {
      await iterator.cancel();
      return {'completed': false, 'cancelled': true};
    }
    _activeSearchStreams[streamId] = cancel;
    final deadline = Timer(_maxSearchDuration, () {
      expired = true;
      unawaited(cancel());
    });
    var sequence = 0;
    int? totalCount;
    int? groupCount;
    var truncated = false;
    try {
      while (await iterator.moveNext().timeout(_searchIdleTimeout)) {
        final update = iterator.current;
        if (update.totalCount != null) {
          totalCount = update.totalCount;
          groupCount = update.groupCount;
          truncated = update.truncated;
        }
        if (update.results.isNotEmpty || update.bookCounts != null) {
          _ensureBookIndex(library);
        }
        final booksByPath = _booksByIndexedPath;
        await eventSink(_searchStreamEvent, {
          'streamId': streamId,
          'chunk': {
            'sequence': sequence++,
            'results': [
              for (final result in update.results)
                PluginSearchApi.resultToJson(
                  result,
                  booksByPath[result.filePath],
                  booksByPath: booksByPath,
                ),
            ],
            'total': totalCount,
            'groupCount': groupCount,
            'truncated': truncated,
            'limit': request.limit,
            'offset': request.offset,
            'facets': facets,
            if (request.includeBookCounts && update.bookCounts != null)
              'bookCounts': [
                for (final entry in update.bookCounts!.entries)
                  if (booksByPath[entry.key] case final Book book)
                    {
                      ...PluginBookIdentity.toJsonWithUid(book),
                      'title': book.title,
                      'count': entry.value,
                    },
              ],
          },
        });
      }
      if (expired) throw TimeoutException('Search stream timed out');
      return {
        'completed': !cancelled,
        'cancelled': cancelled,
        'chunks': sequence,
      };
    } finally {
      deadline.cancel();
      _activeSearchStreams.remove(streamId);
      await iterator.cancel();
    }
  }

  Map<String, dynamic> _cancelPluginSearch(String streamId) {
    if (!_streamIdPattern.hasMatch(streamId)) {
      throw Exception('error.invalid_params: invalid internal stream id');
    }
    final cancel = _activeSearchStreams[streamId];
    if (cancel == null) {
      if (_pendingSearchCancellations.length < 16) {
        _pendingSearchCancellations.add(streamId);
      }
      return {'cancelled': false};
    }
    unawaited(cancel());
    return {'cancelled': true};
  }

  // ----------------------------------------------------------------
  // reader.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleReader(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'openBook':
        // spec: openBook({ id?, bookId?, type?, index?, searchQuery?,
        //   navigateToPositionIfReused?, matchPages?, matchedTerms? })
        // also accepts legacy 'title' for back-compat; all supplied identity fields must match.
        {
          final bookId = (args['bookId'] ?? args['title']) as String?;
          final index = (args['index'] as num?)?.toInt() ?? 0;
          final searchQuery = args['searchQuery'] as String? ?? '';
          final navigateToPositionIfReused =
              args['navigateToPositionIfReused'] as bool? ?? false;
          final openInSidePane = args['openInSidePane'] as bool? ?? false;
          final externalMatches = _parseExternalMatches(args, searchQuery);
          if (PluginBookIdentity.parseId(args['id']) == null &&
              bookId == null &&
              args['external'] == null &&
              (args['bookUid'] as String?)?.trim().isNotEmpty != true) {
            throw Exception(
              'error.invalid_params: id, bookUid or bookId required',
            );
          }
          if (args['external'] != null) {
            final access = DeclarativeLibraryBookAccess.otzaria(
              _dependencies.bookOpenCoordinator,
            );
            return access.openUnique(
              _identityFields(args),
              index: index,
              searchQuery: searchQuery,
              navigateToPositionIfReused: navigateToPositionIfReused,
              inSidePane: openInSidePane,
              externalMatches: externalMatches,
            );
          }
          final book = _findPluginBook(
            await DataRepository.instance.library,
            args,
          );
          if (book == null) return false;
          _dependencies.bookOpenCoordinator.openBook(
            book,
            index,
            searchQuery,
            ignoreHistory: true,
            requiresStableLayout: book is PdfBook,
            navigateToPositionIfReused: navigateToPositionIfReused,
            inSidePane: openInSidePane,
            externalMatches: externalMatches,
          );
          return true;
        }
      case 'registerInBookSearchProvider':
        // spec: registerInBookSearchProvider({ provider })
        // רושם את התוסף כספק חיפוש-בתוך-ספר לספרים חיצוניים של provider.
        {
          final provider = args['provider'];
          if (provider is! String || provider.isEmpty) {
            throw Exception('error.invalid_params: provider required');
          }
          try {
            PluginInBookSearchService.instance.register(
              provider,
              plugin.pluginId,
            );
          } on StateError {
            throw Exception(
              'error.conflict: provider is owned by another plugin',
            );
          }
          return true;
        }
      case 'respondInBookSearch':
        // spec: respondInBookSearch({ requestId, pages?, matchedTerms?, query?, error? })
        // תשובת הספק לאירוע reader.inBookSearch.requested.
        {
          final requestId = args['requestId'];
          if (requestId is! String || requestId.isEmpty) {
            throw Exception('error.invalid_params: requestId required');
          }
          final accepted = PluginInBookSearchService.instance.respond(
            plugin.pluginId,
            requestId,
            pages: (args['pages'] as List? ?? const [])
                .whereType<num>()
                .map((page) => page.toInt())
                .where((page) => page > 0)
                .toList(),
            matchedTerms: (args['matchedTerms'] as List? ?? const [])
                .whereType<String>()
                .toList(),
            query: args['query'] as String? ?? '',
            error: args['error'] as String?,
            instanceId: instanceId,
          );
          if (!accepted) {
            throw Exception(
              'error.not_found: request does not belong to this plugin',
            );
          }
          return true;
        }
      case 'openSearchTab':
        // spec: openSearchTab({ query, autoSearch?, selectItems?, settings? })
        // פותח כרטיסיית חיפוש מובנית עם השאילתה; selectItems מסמן שורות
        // דיאלוג של התוסף הקורא (מפתחי הבחירה נגזרים מ-pluginId שלו בלבד).
        // autoSearch: false פותח את הטאב עם השאילתה בשדה מבלי להריץ חיפוש
        // (ברירת המחדל true — הרצה אוטומטית). settings מקבל את הגדרות
        // החיפוש (מצב, מרחק, מדיניות התאמה ואפשרויות מילה) בדיוק כמו
        // search.query — ראה PluginOpenSearchTabSettings.
        {
          final query = (args['query'] as String? ?? '').trim();
          if (query.isEmpty || query.length > 500) {
            throw Exception('error.invalid_params: query required');
          }
          final autoSearch = args['autoSearch'] as bool? ?? true;
          final selectItems = (args['selectItems'] as List? ?? const [])
              .whereType<String>()
              .where(
                (id) => RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(id),
              )
              .take(4)
              .toList();
          final settings = PluginOpenSearchTabSettings.parse(
            args['settings'],
            query: query,
          );
          return openPluginSearchTab(
            coordinator: _dependencies.bookOpenCoordinator,
            query: query,
            autoSearch: autoSearch,
            settings: settings,
            pluginSearchSelections: {
              for (final itemId in selectItems)
                '${plugin.pluginId}/$itemId': true,
            },
          );
        }
      case 'registerExternalSearchProvider':
        // spec: registerExternalSearchProvider({ provider })
        // רושם את התוסף כספק תוצאות חיצוני למסך החיפוש המובנה.
        {
          final provider = args['provider'];
          if (provider is! String || provider.isEmpty) {
            throw Exception('error.invalid_params: provider required');
          }
          try {
            PluginExternalSearchService.instance.register(
              provider,
              plugin.pluginId,
            );
          } on StateError {
            throw Exception(
              'error.conflict: provider is owned by another plugin',
            );
          }
          return true;
        }
      case 'respondExternalSearch':
        // spec: respondExternalSearch({ requestId, results?, totalBooks?,
        //   totalHits?, hasMore?, done?, index?, error? })
        // תשובת הספק לאירוע search.external.requested; הניקוי נעשה בשירות.
        // done: false — עדכון חלקי תוך כדי הזרמה; הבקשה נשארת פתוחה.
        {
          final requestId = args['requestId'];
          if (requestId is! String || requestId.isEmpty) {
            throw Exception('error.invalid_params: requestId required');
          }
          final accepted = PluginExternalSearchService.instance.respond(
            plugin.pluginId,
            requestId,
            results: args['results'] as List? ?? const [],
            totalBooks: (args['totalBooks'] as num?)?.toInt() ?? 0,
            totalHits: (args['totalHits'] as num?)?.toInt() ?? 0,
            hasMore: args['hasMore'] == true,
            done: args['done'] != false,
            index: args['index'] as List?,
            error: args['error'] as String?,
            instanceId: instanceId,
          );
          if (!accepted) {
            throw Exception(
              'error.not_found: request does not belong to this plugin',
            );
          }
          return true;
        }
      case 'openBookAtRef':
        // spec: openBookAtRef({ id?, bookId?, type?, ref, index?, highlight? })
        {
          final bookId = (args['bookId'] ?? args['title']) as String?;
          final ref = args['ref'] as String?;
          int index = (args['index'] as num?)?.toInt() ?? 0;
          final highlight = args['highlight'] as bool? ?? false;
          if (PluginBookIdentity.parseId(args['id']) == null &&
              bookId == null &&
              (args['bookUid'] as String?)?.trim().isNotEmpty != true) {
            throw Exception(
              'error.invalid_params: id, bookUid or bookId required',
            );
          }
          final book = _findPluginBook(
            await DataRepository.instance.library,
            args,
          );
          if (book == null) return false;
          final resolvedBookId = book.title;
          var refFound = false;
          if (ref != null && ref.isNotEmpty && book is TextBook) {
            // רזולוציה לרמת שורה (פסוק/סעיף) דרך heRef — מדויקת מתחת ל-TOC,
            // ולכן נבדקת ראשונה.
            final resolveLine = _dependencies.resolveRefToLine;
            if (resolveLine != null) {
              try {
                final lineIndex = await resolveLine(book, ref);
                if (lineIndex != null) {
                  _dependencies.bookOpenCoordinator.openBook(
                    book,
                    lineIndex,
                    '',
                    ignoreHistory: true,
                    markSection: highlight,
                  );
                  return true;
                }
              } catch (_) {}
            }
            // מנוע find_ref — מודע-הקשר, מפענח הפניות מובנות
            // (פרק/הלכה/סימן) שתלויות בסוג הספר. ההפניה כוללת את שם הספר.
            final resolve = _dependencies.resolveReference;
            if (resolve != null) {
              try {
                final hits = await resolve('$resolvedBookId $ref');
                final hit = hits
                    .where((h) => h.title == resolvedBookId && !h.isPdf)
                    .firstOrNull;
                if (hit != null) {
                  index = hit.index;
                  refFound = true;
                }
              } catch (_) {}
            }
            // fallback: התאמת TOC מקומית (flatten + נרמול) — בעיקר לבבלי
            if (!refFound) {
              try {
                final toc = flattenToc(await book.tableOfContents);
                final entry = toc.cast<dynamic>().firstWhere(
                  (e) =>
                      e?.text != null &&
                      tocTextMatchesRef(e.text.toString(), ref),
                  orElse: () => null,
                );
                if (entry != null) {
                  index = (entry.index as num).toInt();
                  refFound = true;
                }
              } catch (_) {}
            }
          }
          // חיפוש רק כ-fallback: אם מצאנו את הכותרת וקפצנו אליה,
          // אין טעם להשאיר אותה גם בתיבת החיפוש.
          _dependencies.bookOpenCoordinator.openBook(
            book,
            index,
            refFound ? '' : (ref ?? ''),
            ignoreHistory: true,
            markSection: highlight && refFound,
            requiresStableLayout: book is PdfBook,
          );
          return true;
        }
      case 'getCurrentState':
        final tabsState = _dependencies.tabsBloc.state;
        final tabs = tabsState.tabs.where((tab) => tab is! ToolTab).toList();
        final panes = tabs.map(_paneForPlugins).toList();
        // Use the same resolver as getCurrentRef for consistent currentRef values
        final snapshots = await Future.wait(panes.map(resolveReaderLocation));
        final openTabs = List.generate(tabs.length, (i) {
          final t = panes[i];
          // טאב שאינו ספר (חיפוש) — id/type = null
          final tabBook = t is TextBookTab
              ? t.book
              : (t is PdfBookTab ? t.book : null);
          return {
            'id': tabBook?.id,
            'type': tabBook != null ? PluginBookIdentity.typeOf(tabBook) : null,
            'source': tabBook != null
                ? PluginBookIdentity.sourceOf(tabBook)
                : null,
            'bookId': t.title,
            'bookUid': tabBook != null
                ? PluginBookIdentity.uidOf(tabBook)
                : null,
            'book': t.title,
            'index': t is TextBookTab
                ? t.index
                : (t is PdfBookTab ? t.pageNumber : 0),
            'currentRef': snapshots[i]?.currentRef,
          };
        });
        final currentPane = tabsState.readingPane;
        if (currentPane == null) {
          return {
            'currentBook': null,
            'currentBookId': null,
            'bookUid': null,
            'currentId': null,
            'currentType': null,
            'currentSource': null,
            'currentIndex': 0,
            'currentRef': null,
            'openTabs': openTabs,
          };
        }
        final currentSnapshot = await resolveReaderLocation(currentPane);
        final currentPaneBook = currentPane is TextBookTab
            ? currentPane.book
            : (currentPane is PdfBookTab ? currentPane.book : null);
        return {
          'currentBook': currentPane.title,
          'currentBookId': currentPane.title,
          'bookUid': currentPaneBook != null
              ? PluginBookIdentity.uidOf(currentPaneBook)
              : null,
          'currentId': currentPaneBook?.id,
          'currentType': currentPaneBook != null
              ? PluginBookIdentity.typeOf(currentPaneBook)
              : null,
          'currentSource': currentPaneBook != null
              ? PluginBookIdentity.sourceOf(currentPaneBook)
              : null,
          'currentIndex': currentPane is TextBookTab
              ? currentPane.index
              : (currentPane is PdfBookTab ? currentPane.pageNumber : 0),
          'currentRef': currentSnapshot?.currentRef,
          'openTabs': openTabs,
        };
      case 'getCurrentRef':
        final snapshot = await resolveReaderLocation(
          _dependencies.tabsBloc.state.readingPane,
        );
        if (snapshot == null) {
          return {
            'currentBook': null,
            'currentBookId': null,
            'bookUid': null,
            'currentId': null,
            'currentType': null,
            'currentSource': null,
            'currentIndex': 0,
            'currentRef': null,
          };
        }
        return snapshot.toJson();
      case 'getActiveCommentators':
        return _getActiveCommentators();
      case 'setActiveCommentators':
        // spec: setActiveCommentators({ add?, remove? })
        return _setActiveCommentators(args);
      case 'getHighlightCapabilities':
        // spec: getHighlightCapabilities() -> { surface, highlights,
        //   selection, contextMenu }
        return _getHighlightCapabilities();
      case 'scrollToSection':
        // spec: scrollToSection({ sectionIndex, highlight? })
        // גולל את הספר הפתוח, בלי לפתוח אותו מחדש וללא הדגשה נדרשת.
        {
          final sectionIndex = args['sectionIndex'];
          if (sectionIndex is! int || sectionIndex < 0) {
            throw Exception(
              'error.invalid_params: sectionIndex must be a non-negative integer',
            );
          }
          return PluginReaderScrollService(
            _dependencies.tabsBloc,
          ).scrollToSection(
            sectionIndex,
            highlight: args['highlight'] == true,
          );
        }
      case 'getSelection':
        final currentPane = _dependencies.tabsBloc.state.readingPane;
        final snapshot = await resolveReaderLocation(currentPane);
        return _buildCurrentSelection(currentPane, snapshot?.currentRef);
      case 'findTextOccurrences':
        return _findTextOccurrences(args);
      case 'getSectionTextMap':
        return _getSectionTextMap(args);
      case 'addContextMenuItem':
        ContextMenuRegistry.instance.registerPayload(
          plugin.pluginId,
          args,
          instanceId: instanceId,
        );
        await _trackWhenStorageKeys(args);
        return true;
      case 'removeContextMenuItem':
        final id = args['id'] as String?;
        if (id == null) throw Exception('error.invalid_params: id required');
        ContextMenuRegistry.instance.remove(
          plugin.pluginId,
          id,
          instanceId: instanceId,
        );
        return true;
      case 'updateContextMenuItem':
        final id = args['id'];
        final patch = args['patch'];
        if (id is! String || patch is! Map) {
          throw const PluginContextMenuException(
            'error.invalid_params',
            'id and patch are required',
          );
        }
        ContextMenuRegistry.instance.update(
          plugin.pluginId,
          id,
          Map<String, dynamic>.from(patch),
          instanceId: instanceId,
        );
        await _trackWhenStorageKeys(Map<String, dynamic>.from(patch));
        return true;
      case 'addToolbarItem':
        PluginToolbarRegistry.instance.registerPayload(
          plugin.pluginId,
          args,
          instanceId: instanceId,
        );
        await _trackWhenStorageKeys(args);
        return true;
      case 'removeToolbarItem':
        final id = args['id'] as String?;
        if (id == null) throw Exception('error.invalid_params: id required');
        PluginToolbarRegistry.instance.remove(
          plugin.pluginId,
          id,
          instanceId: instanceId,
        );
        return true;
      case 'updateToolbarItem':
        final id = args['id'];
        final patch = args['patch'];
        if (id is! String || patch is! Map) {
          throw const PluginToolbarException(
            'error.invalid_params',
            'id and patch are required',
          );
        }
        PluginToolbarRegistry.instance.update(
          plugin.pluginId,
          id,
          Map<String, dynamic>.from(patch),
          instanceId: instanceId,
        );
        await _trackWhenStorageKeys(Map<String, dynamic>.from(patch));
        return true;
      case 'setHighlight':
        if (args['range'] is Map && args['style'] is Map) {
          return _highlightRegistry
              .setHighlight(
                ownerPluginId: plugin.pluginId,
                ownerInstanceId: instanceId,
                payload: args,
              )
              .toJson();
        }
        final bookId = args['bookId'];
        final index = args['index'];
        final color = args['color'];
        final label = args['label'];
        if (bookId is! String ||
            index is! int ||
            index < 0 ||
            (color != null && color is! String) ||
            (label != null && label is! String)) {
          throw const PluginHighlightException(
            'error.invalid_params',
            'bookId and index are required for the legacy API',
          );
        }
        _highlightRegistry.setLegacyHighlight(
          ownerPluginId: plugin.pluginId,
          ownerInstanceId: instanceId,
          bookId: bookId,
          bookUid: args['bookUid'] as String?,
          sectionIndex: index,
          color: color as String?,
          label: label as String?,
        );
        return true;
      case 'updateHighlight':
        return _highlightRegistry
            .updateHighlight(
              ownerPluginId: plugin.pluginId,
              ownerInstanceId: instanceId,
              payload: args,
            )
            .toJson();
      case 'getHighlights':
        final bookId = args['bookId'];
        final sectionIndex = args['sectionIndex'];
        if ((bookId != null && bookId is! String) ||
            (sectionIndex != null && sectionIndex is! int)) {
          throw const PluginHighlightException(
            'error.invalid_params',
            'sectionIndex must be an integer',
          );
        }
        return _highlightRegistry
            .getHighlights(
              ownerPluginId: plugin.pluginId,
              ownerInstanceId: instanceId,
              bookId: bookId as String?,
              sectionIndex: sectionIndex as int?,
              includeStale: args['includeStale'] == true,
            )
            .map((h) => h.toJson())
            .toList();
      case 'revealHighlight':
        final highlightId = args['highlightId'];
        if (highlightId is! String || highlightId.isEmpty) {
          throw const PluginHighlightException(
            'error.invalid_params',
            'highlightId is required',
          );
        }
        final matches = _highlightRegistry.getHighlights(
          ownerPluginId: plugin.pluginId,
          ownerInstanceId: instanceId,
          includeStale: true,
        );
        final highlight = matches.cast<dynamic>().firstWhere(
          (item) => item.highlightId == highlightId,
          orElse: () => null,
        );
        if (highlight == null) {
          throw const PluginHighlightException(
            'error.highlight_not_found',
            'highlight was not found',
          );
        }
        final allBooks = (await DataRepository.instance.library).getAllBooks();
        final highlightUid = highlight.bookUid as String?;
        final book = allBooks.cast<dynamic>().firstWhere(
          (item) {
            if (item == null) return false;
            if (highlightUid != null && highlightUid.isNotEmpty) {
              return PluginBookIdentity.uidOf(item as Book) == highlightUid;
            }
            return item.title == highlight.bookId;
          },
          orElse: () => null,
        );
        if (book == null) return false;
        _dependencies.bookOpenCoordinator.openBook(
          book,
          highlight.sectionIndex,
          '',
          ignoreHistory: true,
        );
        PluginHighlightRevealService.instance.reveal(highlight);
        return true;
      case 'clearHighlight':
        final highlightId = args['highlightId'];
        if (highlightId is String) {
          final removed = _highlightRegistry.clearHighlight(
            ownerPluginId: plugin.pluginId,
            ownerInstanceId: instanceId,
            highlightId: highlightId,
            expectedVersion: args['expectedVersion'],
            expectedEtag: args['expectedEtag'],
          );
          if (!removed) {
            throw const PluginHighlightException(
              'error.highlight_not_found',
              'highlight was not found',
            );
          }
          return true;
        }
        final legacyBookId = args['bookId'];
        final legacyIndex = args['index'];
        if (legacyBookId is! String || legacyIndex is! int) {
          throw const PluginHighlightException(
            'error.invalid_params',
            'highlightId is required',
          );
        }
        final matches = _highlightRegistry.getHighlights(
          ownerPluginId: plugin.pluginId,
          ownerInstanceId: instanceId,
          bookId: legacyBookId,
          sectionIndex: legacyIndex,
          includeStale: true,
        );
        for (final match in matches) {
          _highlightRegistry.clearHighlight(
            ownerPluginId: plugin.pluginId,
            ownerInstanceId: instanceId,
            highlightId: match.highlightId,
          );
        }
        return true;
      case 'clearAllHighlights':
        final bookId = args['bookId'];
        final sectionIndex = args['sectionIndex'];
        if ((bookId != null && bookId is! String) ||
            (sectionIndex != null && sectionIndex is! int)) {
          throw const PluginHighlightException(
            'error.invalid_params',
            'sectionIndex must be an integer',
          );
        }
        _highlightRegistry.clearAll(
          ownerPluginId: plugin.pluginId,
          ownerInstanceId: instanceId,
          bookId: bookId as String?,
          sectionIndex: sectionIndex as int?,
        );
        return true;
      default:
        throw Exception(
          'error.unknown_method: Unknown action in reader: $action',
        );
    }
  }

  Map<String, dynamic> _identityFields(Map<String, dynamic> args) => {
    for (final key in ['id', 'bookId', 'type', 'source', 'external'])
      if (args.containsKey(key)) key: args[key],
  };

  /// עמודי התאמה שהתוסף צירף לפתיחה (חיפוש חיצוני): רשימת עמודים חיוביים,
  /// מוגבלת בגודל. ערך לא תקין נדחה בשקט — פתיחת הספר חשובה מההתאמות.
  ExternalBookMatches? _parseExternalMatches(
    Map<String, dynamic> args,
    String searchQuery,
  ) {
    final rawPages = args['matchPages'];
    if (rawPages is! List || rawPages.isEmpty || rawPages.length > 10000) {
      return null;
    }
    final pages = rawPages
        .whereType<num>()
        .map((page) => page.toInt())
        .where((page) => page > 0)
        .toList();
    if (pages.isEmpty) return null;
    final terms = (args['matchedTerms'] as List? ?? const [])
        .whereType<String>()
        .where((term) => term.isNotEmpty && term.length <= 256)
        .take(64)
        .toList();
    return ExternalBookMatches(
      pages: pages,
      matchedTerms: terms,
      query: searchQuery,
    );
  }

  Future<Map<String, dynamic>> _findTextOccurrences(
    Map<String, dynamic> args,
  ) async {
    final bookId = args['bookId'];
    final sectionIndex = args['sectionIndex'];
    final query = args['query'];
    final layer = args['layer'] ?? 'source';
    final limit = args['limit'] ?? PluginTextOccurrenceService.defaultLimit;
    final cursor = args['cursor'];
    if (bookId is! String ||
        bookId.isEmpty ||
        sectionIndex is! int ||
        query is! String ||
        layer is! String ||
        limit is! int ||
        (cursor != null && cursor is! String)) {
      throw const PluginTextOccurrenceException(
        'error.invalid_params',
        'bookId, sectionIndex, and query are required',
      );
    }
    final section = await _loadPluginTextSection(
      bookId,
      sectionIndex,
      bookUid: args['bookUid'] as String?,
    );
    final map = const TextSourceMapService().build(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: section.rawText,
      settings: section.settings,
    );
    final normalizeJson = _normalizationJson(
      args['normalize'],
      (message) =>
          throw PluginTextOccurrenceException('error.invalid_params', message),
    );
    try {
      final options = _normalizationOptions(normalizeJson, section.settings);
      return const PluginTextOccurrenceService()
          .find(
            bookId: bookId,
            sectionIndex: sectionIndex,
            layer: layer,
            text: layer == 'rendered' ? map.renderedText : map.sourceText,
            textHash: layer == 'rendered'
                ? map.renderedTextHash
                : map.sourceTextHash,
            query: query,
            normalize: options,
            currentRef: section.currentRef,
            limit: limit,
            cursor: cursor as String?,
          )
          .toJson();
    } on FormatException catch (error) {
      throw PluginTextOccurrenceException(
        'error.invalid_params',
        error.message,
      );
    }
  }

  Future<({String rawText, RenderSettings settings, String? currentRef})>
  _loadPluginTextSection(
    String bookId,
    int sectionIndex, {
    String? bookUid,
  }) async {
    if (sectionIndex < 0) {
      throw const PluginTextOccurrenceException(
        'error.invalid_params',
        'sectionIndex must be non-negative',
      );
    }
    final uid = bookUid?.trim();
    // `bookUid` מזהה מדויק; בהיעדרו נשמר זיהוי לפי כותרת כמקודם.
    bool matchesBook(Book b) => uid != null && uid.isNotEmpty
        ? PluginBookIdentity.uidOf(b) == uid
        : b.title == bookId;
    // סריקת חלוניות ולא טאבים: ספר שיושב רק בחלונית של טאב מפוצל לא נמצא,
    // והקריאה נפלה למסלול ה-DB שמאבד את מצב הניקוד החי. החלונית הפעילה
    // ראשונה, כי אותו ספר בשתי חלוניות יכול להיות בהגדרות ניקוד שונות.
    final activePane = _dependencies.tabsBloc.state.readingPane;
    final panes = <OpenedTab>[
      ?activePane,
      ..._dependencies.tabsBloc.state.tabs.expand(leafPanes),
    ];
    for (final tab in panes) {
      if (tab is! TextBookTab || !matchesBook(tab.book)) continue;
      final state = tab.bloc.state;
      if (state is! TextBookLoaded || sectionIndex >= state.content.length) {
        continue;
      }
      final snapshot =
          identical(tab, _dependencies.tabsBloc.state.readingPane) &&
              tab.index == sectionIndex
          ? await resolveReaderLocation(tab)
          : null;
      return (
        rawText: state.content[sectionIndex],
        settings: RenderSettings(
          removeNikud: state.removeNikud,
          removePunctuation: state.removePunctuation,
          removeTeamim:
              !(Settings.getValue<bool>(SettingsRepository.keyShowTeamim) ??
                  true),
          replaceHolyNames:
              Settings.getValue<bool>(SettingsRepository.keyReplaceHolyNames) ??
              false,
        ),
        currentRef: snapshot?.currentRef,
      );
    }

    final library = await DataRepository.instance.library;
    TextBook? book;
    for (final candidate in library.getAllBooks().whereType<TextBook>()) {
      if (matchesBook(candidate)) {
        book = candidate;
        break;
      }
    }
    if (book == null) {
      throw const PluginTextOccurrenceException(
        'error.not_found',
        'text book was not found',
      );
    }
    final range = await TextBookRepository(fileSystem: FileSystemData.instance)
        .getBookContentRange(
          book,
          startLine: sectionIndex,
          endLine: sectionIndex + 1,
        );
    if (range == null || range.lines.isEmpty) {
      throw const PluginTextOccurrenceException(
        'error.not_found',
        'section was not found',
      );
    }
    return (
      rawText: range.lines.first,
      settings: RenderSettings(
        removeTeamim:
            !(Settings.getValue<bool>(SettingsRepository.keyShowTeamim) ??
                true),
        replaceHolyNames:
            Settings.getValue<bool>(SettingsRepository.keyReplaceHolyNames) ??
            false,
      ),
      currentRef: null,
    );
  }

  Future<Map<String, dynamic>> _getSectionTextMap(
    Map<String, dynamic> args,
  ) async {
    final bookId = args['bookId'];
    final sectionIndex = args['sectionIndex'];
    final layer = args['layer'] ?? 'both';
    final includeWords = args['includeWords'] ?? false;
    final includeChars = args['includeChars'] ?? false;
    final includeSourceMap = args['includeSourceMap'] ?? false;
    final includeDomRects = args['includeDomRects'] ?? false;
    final limit = args['limit'] ?? PluginSectionTextMapService.defaultLimit;
    final cursor = args['cursor'];
    if (bookId is! String ||
        bookId.isEmpty ||
        sectionIndex is! int ||
        layer is! String ||
        includeWords is! bool ||
        includeChars is! bool ||
        includeSourceMap is! bool ||
        includeDomRects is! bool ||
        limit is! int ||
        (cursor != null && cursor is! String)) {
      throw const PluginSectionTextMapException(
        'error.invalid_params',
        'section text map parameters are invalid',
      );
    }
    if (includeDomRects) {
      throw const PluginSectionTextMapException(
        'error.unsupported_context',
        'DOM rectangles are not available in this SDK version',
      );
    }
    final normalizeJson = _normalizationJson(
      args['normalize'],
      (message) =>
          throw PluginSectionTextMapException('error.invalid_params', message),
    );
    final section = await _loadPluginTextSection(
      bookId,
      sectionIndex,
      bookUid: args['bookUid'] as String?,
    );
    final map = const TextSourceMapService().build(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: section.rawText,
      settings: section.settings,
    );
    try {
      final options = _normalizationOptions(normalizeJson, section.settings);
      return const PluginSectionTextMapService()
          .build(
            map: map,
            layer: layer,
            includeWords: includeWords,
            includeChars: includeChars,
            includeSourceMap: includeSourceMap,
            normalize: options,
            currentRef: section.currentRef,
            limit: limit,
            cursor: cursor as String?,
          )
          .toJson();
    } on FormatException catch (error) {
      throw PluginSectionTextMapException(
        'error.invalid_params',
        error.message,
      );
    }
  }

  Map<String, dynamic> _normalizationJson(
    Object? value,
    Never Function(String message) invalid,
  ) {
    if (value != null &&
        (value is! Map || value.keys.any((key) => key is! String))) {
      invalid('normalize must be an object');
    }
    final json = value == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(value as Map);
    final overrides = json['overrides'];
    if (overrides != null &&
        (overrides is! Map || overrides.keys.any((key) => key is! String))) {
      invalid('normalize.overrides must be an object');
    }
    return json;
  }

  PluginNormalizeOptions _normalizationOptions(
    Map<String, dynamic> json,
    RenderSettings settings,
  ) {
    final overrides = json['overrides'];
    return PluginNormalizeOptions.forProfile(
      PluginNormalizationProfile.parse(json['profile']),
      displayIgnoreNikud: settings.removeNikud,
      displayIgnoreTeamim: settings.removeTeamim,
      overrides: overrides == null
          ? const {}
          : Map<String, dynamic>.from(overrides as Map),
    );
  }

  // ----------------------------------------------------------------
  // navigation.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleNavigation(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'goTo':
        final target = args['target'] as String?;
        if (target == null) {
          throw Exception("error.invalid_params: target required");
        }
        final Screen screen;
        switch (target) {
          case 'library':
            screen = Screen.library;
            break;
          case 'reading':
            screen = Screen.reading;
            break;
          case 'more':
            ToolsLauncherController.instance.open();
            return true;
          case 'settings':
            screen = Screen.settings;
            break;
          default:
            throw Exception(
              "error.invalid_params: Invalid navigation target: $target. Valid: library, reading, more, settings",
            );
        }
        _dependencies.navigationBloc.add(NavigateToScreen(screen));
        return true;
      default:
        throw Exception(
          "error.unknown_method: Unknown action in navigation: $action",
        );
    }
  }

  // ----------------------------------------------------------------
  // notes.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleNotes(String action, Map<String, dynamic> args) async {
    final repo = _dependencies.personalNotesRepository;
    switch (action) {
      case 'list':
        final bookId = args['bookId'] as String?;
        if (bookId == null) {
          throw Exception("error.invalid_params: bookId required");
        }
        final notes = await repo.loadNotes(bookId);
        return notes
            .map(
              (n) => {
                'id': n.id,
                'lineNumber': n.lineNumber,
                'content': n.content,
                'contentPlain': n.contentPlain,
              },
            )
            .toList();
      case 'getBookNotesSummary':
        final summaries = await repo.listBooksWithNotes();
        return summaries
            .map(
              (s) => {
                'bookId': s.bookId,
                'noteCount': s.noteCount,
                'lastModified': s.lastUpdated.toIso8601String(),
              },
            )
            .toList();
      case 'add':
        final bookId = args['bookId'] as String?;
        final lineNumber = args['lineNumber'] as int?;
        final content = args['content'] as String?;
        if (bookId == null || lineNumber == null || content == null) {
          throw Exception("error.invalid_params: Missing arguments");
        }
        await repo.addNote(
          bookId: bookId,
          lineNumber: lineNumber,
          content: content,
          contentPlain: content,
          contentFormat: PersonalNoteContentFormat.plain,
        );
        return true;
      case 'update':
        final bookId = args['bookId'] as String?;
        final noteId = args['noteId'] as String?;
        final content = args['content'] as String?;
        if (bookId == null || noteId == null || content == null) {
          throw Exception("error.invalid_params: Missing arguments");
        }
        await repo.updateNote(
          bookId: bookId,
          noteId: noteId,
          content: content,
          contentPlain: content,
          contentFormat: PersonalNoteContentFormat.plain,
        );
        return true;
      case 'delete':
        final bookId = args['bookId'] as String?;
        final noteId = args['noteId'] as String?;
        if (bookId == null || noteId == null) {
          throw Exception("error.invalid_params: Missing arguments");
        }
        await repo.deleteNote(bookId: bookId, noteId: noteId);
        return true;
      default:
        throw Exception(
          "error.unknown_method: Unknown action in notes: $action",
        );
    }
  }

  // ----------------------------------------------------------------
  // ui.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleUi(String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'showMessage':
        UiSnack.show(
          args['message'] as String? ?? '',
          onTap: _messageTapHandler(args),
        );
        return true;
      case 'showSuccess':
        UiSnack.showSuccess(
          args['message'] as String? ?? '',
          onTap: _messageTapHandler(args),
        );
        return true;
      case 'showError':
        UiSnack.showError(
          args['message'] as String? ?? '',
          onTap: _messageTapHandler(args),
        );
        return true;
      case 'showConfirm':
        final result = await _dependencies.showConfirmDialog(
          title: args['title'] as String? ?? 'אישור',
          content: args['content'] as String? ?? '',
        );
        return {'confirmed': result};
      case 'showWarning':
        final result = await _dependencies.showWarningDialog(
          title: args['title'] as String? ?? 'אזהרה',
          content: args['content'] as String? ?? '',
          subtitle: args['subtitle'] as String? ?? '',
        );
        return {'confirmed': result};
      case 'pickFolder':
        // פותח דיאלוג בחירת תיקייה. הנתיב שנבחר נרשם כתיקייה מאושרת לתוסף —
        // מכאן ואילך מותר לו לכתוב/למחוק בתוכה (download.destPath, fs.*).
        // ביטול מחזיר {path: null}, והתוסף בודק זאת (data.path).
        final picker = _dependencies.pickFolder ?? _defaultPickFolder;
        final path = await picker(title: args['title'] as String?);
        if (path == null || path.isEmpty) {
          return {'path': null};
        }
        final rejection = await pluginFolderRejectionReason(path);
        if (rejection != null) {
          throw Exception('error.forbidden: $rejection');
        }
        _grantedFolders.add(p.normalize(p.absolute(path)));
        return {'path': path};
      default:
        throw Exception("error.unknown_method: Unknown action in ui: $action");
    }
  }

  static final _tapEventTopicPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

  /// בונה מטפל לחיצה להודעת snack: הלחיצה משגרת לתוסף את האירוע שביקש
  /// ב-`tapEvent` (או `ui.messageClicked`) עם `tapPayload`. null כשלא התבקש.
  VoidCallback? _messageTapHandler(Map<String, dynamic> args) {
    final openPlugin = args['tapOpenPlugin'] == true;
    if (!openPlugin &&
        !args.containsKey('tapEvent') &&
        !args.containsKey('tapPayload')) {
      return null;
    }
    final topic = args['tapEvent'] as String? ?? 'ui.messageClicked';
    // שם האירוע משוקע לתוך JS בעת השיגור — תבנית קשיחה חוסמת הזרקת קוד.
    if (!_tapEventTopicPattern.hasMatch(topic)) {
      throw Exception('error.invalid_params: Invalid tapEvent: $topic');
    }
    final payload = <String, dynamic>{'payload': args['tapPayload']};
    if (openPlugin) {
      // ניווט לדף התוסף עם מסירת האירוע — כמו openPlugin בתפריט ההקשר.
      return () => PluginPageLauncher.instance.open(
        plugin.pluginId,
        topic: topic,
        payload: payload,
      );
    }
    final dispatch =
        _dependencies.dispatchEventToPlugin ??
        PluginRuntimeDispatcher.instance.dispatchEventToPlugin;
    // הלחיצה חוזרת למופע שהציג את ההודעה — לא לבחירת הדיספצ'ר.
    return () => unawaited(
      dispatch(plugin.pluginId, topic, payload, instanceId: instanceId),
    );
  }

  /// בורר התיקיות המוגדר כברירת מחדל — דיאלוג המערכת דרך [FilePicker].
  Future<String?> _defaultPickFolder({String? title}) =>
      FilePicker.getDirectoryPath(lockParentWindow: true, dialogTitle: title);

  /// בודקת אם [targetPath] נמצא בתוך תיקייה שהמשתמש אישר דרך `ui.pickFolder`.
  ///
  /// זהו גבול האבטחה לכל פעולות הכתיבה/מחיקה לדיסק של התוסף. הבדיקה מתבצעת על
  /// הנתיב הקנוני (אחרי פתרון symlinks) של **שני** הצדדים — היעד והתיקייה
  /// המאושרת — כדי לנטרל גם `..` (path-traversal) וגם symlink שמצביע מתוך
  /// תיקייה מאושרת אל מחוץ לה. בלי פתרון ה-symlink בדיקת [p.isWithin] על המחרוזת
  /// בלבד הייתה מאשרת כתיבה/מחיקה מחוץ לתיקייה דרך קישור סימבולי.
  bool _isPathInGrantedFolder(String targetPath) {
    final canonicalTarget = canonicalizeNearestExisting(targetPath);
    if (canonicalTarget == null) return false;
    for (final root in _grantedFolders) {
      final canonicalRoot = canonicalizeNearestExisting(root);
      if (canonicalRoot == null) continue;
      if (p.equals(canonicalTarget, canonicalRoot) ||
          p.isWithin(canonicalRoot, canonicalTarget)) {
        return true;
      }
    }
    return false;
  }

  // ----------------------------------------------------------------
  // fs.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleFs(String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'extractZip':
        final zipPath = args['zipPath'] as String?;
        final destFolder = args['destFolder'] as String?;
        if (zipPath == null || destFolder == null) {
          throw Exception(
            'error.invalid_params: zipPath and destFolder required',
          );
        }
        if (!_isPathInGrantedFolder(zipPath) ||
            !_isPathInGrantedFolder(destFolder)) {
          throw Exception(
            'error.forbidden: path outside a user-selected folder',
          );
        }
        await _fsService.extractZip(zipPath, destFolder);
        return true;
      case 'deleteFile':
        final path = args['path'] as String?;
        if (path == null) {
          throw Exception('error.invalid_params: path required');
        }
        if (!_isPathInGrantedFolder(path)) {
          throw Exception(
            'error.forbidden: path outside a user-selected folder',
          );
        }
        await _fsService.deleteFile(path);
        return true;
      case 'writeFile':
        return await _writeWorkspaceFile(args);
      case 'readFile':
        return await _readWorkspaceFile(args);
      case 'listDir':
        return await _listWorkspaceDir(args);
      case 'makeDir':
        await _fsService.makeWorkspaceDir(
          root: await _workspaceRoot(),
          relativePath: _workspacePathArg(args),
        );
        return true;
      case 'deleteEntry':
        return await _fsService.deleteWorkspaceEntry(
          root: await _workspaceRoot(),
          relativePath: _workspacePathArg(args),
          recursive: args['recursive'] == true,
        );
      case 'stat':
        final entry = await _fsService.statWorkspaceEntry(
          root: await _workspaceRoot(),
          relativePath: _workspacePathArg(args, allowRoot: true),
        );
        return entry == null
            ? {'exists': false}
            : {'exists': true, ...entry.toJson()};
      case 'pickUserFile':
        return await _pickUserFile(args);
      case 'beginBinaryWrite':
        return await _beginBinaryWrite(args);
      case 'commitUserFileWrite':
        return await _commitUserFileWrite(args);
      case 'abortBinaryWrite':
        final writeToken = args['writeToken'] as String?;
        if (writeToken == null) {
          throw Exception('error.invalid_params: writeToken required');
        }
        return await _fileServer.abortUpload(
          pluginId: plugin.pluginId,
          writeToken: writeToken,
        );
      case 'resolveFileUrl':
        return await _resolveUserFileUrl(args);
      case 'readTextFile':
        return await _readUserTextFile(args);
      case 'revokeFile':
        final token = args['token'] as String?;
        if (token == null) {
          throw Exception('error.invalid_params: token required');
        }
        _fileServer.revoke(token);
        await _removeUserFileGrant(token);
        return true;
      default:
        throw Exception('error.unknown_method: Unknown action in fs: $action');
    }
  }

  /// שורש המרחב הפרטי של התוסף. תת-תיקייה של תיקיית הנתונים שלו, כדי שקבצים
  /// שהאפליקציה עצמה תשמור שם בעתיד לא ייחשפו לתוסף. נמחקת בהסרת התוסף.
  Future<String> _workspaceRoot() async {
    final dataPath = await AppPaths.getPluginDataPath(plugin.pluginId);
    return _fsService.ensureWorkspace(p.join(dataPath, 'files'));
  }

  /// קורא את הפרמטר `path` של פעולות המרחב הפרטי. נתיב ריק מותר רק לפעולות
  /// שמשמעותן על השורש עצמו (`listDir`, `stat`).
  String _workspacePathArg(
    Map<String, dynamic> args, {
    bool allowRoot = false,
  }) {
    final path = args['path'];
    if (path == null && allowRoot) return '';
    if (path is! String || (path.trim().isEmpty && !allowRoot)) {
      throw Exception('error.invalid_params: path required');
    }
    return path;
  }

  Future<Map<String, dynamic>> _writeWorkspaceFile(
    Map<String, dynamic> args,
  ) async {
    final relativePath = _workspacePathArg(args);
    final encoding = (args['encoding'] as String?) ?? 'utf8';
    final content = args['content'];
    if (content is! String) {
      throw Exception('error.invalid_params: content must be a string');
    }
    // חסימה מוקדמת לפי אורך המחרוזת — כדי לא לפענח base64 של מאות מגה-בייטים
    // רק כדי לדחות אותו. התקרה המדויקת נאכפת בשירות על הבייטים עצמם.
    if (content.length > _fsService.maxTransferBytes * 2) {
      throw Exception('error.too_large: content exceeds the RPC size limit');
    }
    final List<int> bytes;
    switch (encoding) {
      case 'utf8':
        bytes = utf8.encode(content);
      case 'base64':
        try {
          bytes = base64Decode(content);
        } on FormatException {
          throw Exception('error.invalid_params: content is not valid base64');
        }
      default:
        throw Exception(
          'error.invalid_params: encoding must be utf8 or base64',
        );
    }
    final root = await _workspaceRoot();
    final size = await _fsService.writeWorkspaceFile(
      root: root,
      relativePath: relativePath,
      bytes: bytes,
      append: args['append'] == true,
    );
    return {
      'path': relativePath,
      'size': size,
      'usedBytes': await _fsService.workspaceUsedBytes(root),
      'quotaBytes': _fsService.maxWorkspaceBytes,
    };
  }

  Future<Map<String, dynamic>> _readWorkspaceFile(
    Map<String, dynamic> args,
  ) async {
    final relativePath = _workspacePathArg(args);
    final encoding = (args['encoding'] as String?) ?? 'utf8';
    if (encoding != 'utf8' && encoding != 'base64') {
      throw Exception('error.invalid_params: encoding must be utf8 or base64');
    }
    final bytes = await _fsService.readWorkspaceFile(
      root: await _workspaceRoot(),
      relativePath: relativePath,
    );
    return {
      'path': relativePath,
      'encoding': encoding,
      'size': bytes.length,
      'content': encoding == 'base64'
          ? base64Encode(bytes)
          // הקובץ נכתב ע"י התוסף עצמו, אך עדיין עשוי להיות בינארי — allowMalformed
          // מחזיר תווי החלפה במקום להפיל את הקריאה.
          : utf8.decode(bytes, allowMalformed: true),
    };
  }

  Future<Map<String, dynamic>> _listWorkspaceDir(
    Map<String, dynamic> args,
  ) async {
    final relativePath = _workspacePathArg(args, allowRoot: true);
    final root = await _workspaceRoot();
    final entries = await _fsService.listWorkspaceDir(
      root: root,
      relativePath: relativePath,
    );
    return {
      'path': relativePath,
      'entries': entries.map((e) => e.toJson()).toList(),
      'usedBytes': await _fsService.workspaceUsedBytes(root),
      'quotaBytes': _fsService.maxWorkspaceBytes,
    };
  }

  /// בורר הקבצים המוגדר כברירת מחדל — דיאלוג המערכת דרך [FilePicker].
  Future<String?> _defaultPickFile({
    List<String>? allowedExtensions,
    String? title,
  }) async {
    final hasExtensions =
        allowedExtensions != null && allowedExtensions.isNotEmpty;
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      lockParentWindow: true,
      type: hasExtensions ? FileType.custom : FileType.any,
      allowedExtensions: hasExtensions ? allowedExtensions : null,
    );
    return result?.files.single.path;
  }

  /// `fs.pickUserFile` — פותח דיאלוג בחירת קובץ, רושם אותו כקובץ מאושר ומחזיר
  /// token ו-URL ש-WebView התוסף מורשה לטעון (PDF ב-`<iframe>`/PDF.js, טקסט
  /// כ-`fetch`). הבייטים אינם חוצים את גשר ה-JS. ביטול מחזיר `{cancelled: true}`.
  Future<Map<String, dynamic>> _pickUserFile(Map<String, dynamic> args) async {
    final picker = _dependencies.pickFile ?? _defaultPickFile;
    final rawExt = args['extensions'];
    final extensions = rawExt is List
        ? rawExt
              .map((e) => e.toString().replaceAll('.', '').toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList()
        : null;
    // ברירת המחדל נשארת קריאה: תוסף ותיק שאינו מכיר את השדה מקבל בדיוק מה
    // שקיבל תמיד. בקשת כתיבה דורשת גם את הרשאת הכתיבה, בנוסף להרשאת הקריאה
    // שהגשר כבר אכף.
    final access = args['access'] as String? ?? 'read';
    if (access != 'read' && access != 'readwrite') {
      throw Exception("error.invalid_params: access must be 'read' or 'readwrite'");
    }
    final writable = access == 'readwrite';
    if (writable && !await _hasWritePermission()) {
      throw Exception(
        'error.permission_denied: fs.user_files.write is required for readwrite access',
      );
    }

    final path = await picker(
      allowedExtensions: extensions,
      title: args['title'] as String?,
    );
    if (path == null || path.isEmpty) {
      return {'cancelled': true};
    }
    final canonical = canonicalizeNearestExisting(path);
    if (canonical == null || !File(canonical).existsSync()) {
      throw Exception('error.not_found: selected file does not exist');
    }
    final registration = await _fileServer.register(
      pluginId: plugin.pluginId,
      canonicalPath: canonical,
    );
    await _saveUserFileGrant(registration.token, canonical, writable: writable);
    return {
      'cancelled': false,
      'token': registration.token,
      'url': registration.url,
      'name': p.basename(canonical),
      'size': await File(canonical).length(),
      'access': access,
    };
  }

  Future<bool> _hasWritePermission() async =>
      await _pluginRepo.getPermission(plugin.pluginId, 'fs.user_files.write') ??
      false;

  /// `fs.beginBinaryWrite` — פותח העלאה ומחזיר לאן לשלוח את הבייטים.
  ///
  /// הבייטים אינם עוברים בגשר: התוסף שולח אותם ב-PUT יחיד לשרת ה-loopback,
  /// והכתיבה לדיסק נעשית רק ב-commit. base64 ב-JSON-RPC היה מכפיל את הזיכרון
  /// ותוקע את ה-UI על מסמך גדול.
  Future<Map<String, dynamic>> _beginBinaryWrite(
    Map<String, dynamic> args,
  ) async {
    final purpose = args['purpose'] as String? ?? 'user-file';
    if (purpose != 'user-file') {
      // 'plugin-file' (טיוטה פרטית) יתווסף בשלב נפרד, עם quota משלו.
      throw Exception("error.unsupported: purpose must be 'user-file'");
    }

    final rawSize = args['expectedSize'];
    final expectedSize = rawSize is num ? rawSize.toInt() : null;

    try {
      final ticket = await _fileServer.beginUpload(
        pluginId: plugin.pluginId,
        expectedSize: expectedSize,
      );
      return {
        'writeToken': ticket.writeToken,
        'uploadUrl': ticket.uploadUrl,
        'expiresAt': ticket.expiresAt.toIso8601String(),
        'maxBytes': ticket.maxBytes,
      };
    } on PluginUploadException catch (e) {
      throw Exception('${e.code}: ${e.message}');
    }
  }

  /// `fs.commitUserFileWrite` — כותב את ההעלאה לקובץ של המשתמש.
  ///
  /// שני מסלולים: `targetToken` של קובץ שנפתח עם `access: 'readwrite'` נכתב
  /// במקום, בלי דיאלוג; בלעדיו נפתח „שמור בשם”. בשני המקרים הכתיבה עוברת
  /// staging באותה תיקייה ואז rename, ולכן **כשל אינו הורס את הקובץ הקיים** —
  /// ראו [_atomicWrite] לגבי מה שמובטח ומה תלוי במערכת הקבצים.
  /// ביטול הדיאלוג מוחק את ה-temp ואינו משנה שום grant.
  Future<Map<String, dynamic>> _commitUserFileWrite(
    Map<String, dynamic> args,
  ) async {
    final writeToken = args['writeToken'] as String?;
    if (writeToken == null) {
      throw Exception('error.invalid_params: writeToken required');
    }

    final upload = await _fileServer.takeUpload(
      pluginId: plugin.pluginId,
      writeToken: writeToken,
    );
    if (upload == null) {
      // לא מוכר, של תוסף אחר, פג, טרם הושלם, או שנצרך כבר — הכול אותו כשל.
      throw Exception('error.not_found: unknown or incomplete upload');
    }

    try {
      final targetToken = args['targetToken'] as String?;
      if (targetToken != null) {
        final grant = await _loadUserFileGrant(targetToken);
        if (grant == null) {
          throw Exception('error.not_found: unknown file token');
        }
        if (!grant.writable) {
          // token של פתיחה לקריאה אינו יעד כתיבה. „שמור” הראשון שלו חייב
          // לעבור דרך „שמור בשם”, ומשם מתקבל token שכן ניתן לכתיבה.
          throw Exception('error.permission_denied: file token is read-only');
        }
        final canonical = canonicalizeNearestExisting(grant.path);
        if (canonical == null || !File(canonical).existsSync()) {
          await _removeUserFileGrant(targetToken);
          throw Exception('error.not_found: file no longer exists');
        }
        await _atomicWrite(upload, canonical);
        return {
          'cancelled': false,
          'token': targetToken,
          'name': p.basename(canonical),
          'size': await File(canonical).length(),
        };
      }

      // רק סיומת ממש: כל דבר אחר עלול להגיע ל-fileName של הדיאלוג עם מפרידי
      // נתיב, ולקבוע לאן הוא ייפתח — בניגוד לכלל שאין דרך להזין נתיב מה-JS.
      final rawExtension = (args['extension'] as String?)?.toLowerCase().trim();
      final extension =
          rawExtension != null && RegExp(r'^\.?[a-z0-9]{1,10}$').hasMatch(rawExtension)
          ? rawExtension.replaceAll('.', '')
          : null;
      final suggested = _suggestedSaveName(
        args['suggestedName'] as String?,
        extension,
      );
      final saver = _dependencies.pickSaveLocation ?? _defaultPickSaveLocation;
      final chosen = await saver(
        suggestedName: suggested,
        allowedExtensions: extension == null ? null : [extension],
        title: args['title'] as String?,
      );
      if (chosen == null || chosen.isEmpty) {
        return {'cancelled': true};
      }

      final canonical = canonicalizeNearestExisting(chosen);
      if (canonical == null) {
        throw Exception('error.invalid_params: could not resolve target path');
      }
      await _atomicWrite(upload, canonical);
      final registration = await _fileServer.register(
        pluginId: plugin.pluginId,
        canonicalPath: canonical,
      );
      await _saveUserFileGrant(registration.token, canonical, writable: true);
      return {
        'cancelled': false,
        'token': registration.token,
        'name': p.basename(canonical),
        'size': await File(canonical).length(),
      };
    } finally {
      // סוגר את ה-session ומוחק את ה-temp — בכל מסלול: הצלחה, ביטול או שגיאה.
      // עד לרגע הזה ההעלאה בבעלות השרת, כדי שדיאלוג „שמור בשם” שפתוח לא ישאיר
      // קובץ יתום.
      await _fileServer.finishCommit(
        pluginId: plugin.pluginId,
        writeToken: writeToken,
      );
    }
  }

  /// שם ברירת מחדל לדיאלוג. תווים שאינם חוקיים בשם קובץ מוסרים כאן ולא
  /// נסמכים על הדיאלוג, שמתנהג שונה בכל פלטפורמה.
  String _suggestedSaveName(String? requested, String? extension) {
    final cleaned = (requested ?? '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .trim();
    final base = cleaned.isEmpty ? 'מסמך' : cleaned;
    if (extension == null || extension.isEmpty) return base;
    return base.toLowerCase().endsWith('.$extension')
        ? base
        : '$base.$extension';
  }

  Future<String?> _defaultPickSaveLocation({
    required String suggestedName,
    List<String>? allowedExtensions,
    String? title,
  }) {
    final hasExtensions =
        allowedExtensions != null && allowedExtensions.isNotEmpty;
    // bytes ריק בכוונה: הדיאלוג משמש כאן כבורר נתיב בלבד. file_picker מדלג על
    // הכתיבה כשהמערך ריק, והכתיבה עצמה נעשית ב-_atomicWrite. אם גרסה עתידית
    // תכתוב בכל זאת, ה-rename שאחריה עדיין מביא את היעד למצב הנכון.
    return FilePicker.saveFile(
      dialogTitle: title,
      fileName: suggestedName,
      lockParentWindow: true,
      type: hasExtensions ? FileType.custom : FileType.any,
      allowedExtensions: hasExtensions ? allowedExtensions : null,
      bytes: Uint8List(0),
    );
  }

  /// מעתיק את ההעלאה ליעד: staging באותה תיקייה, ואז rename.
  ///
  /// ה-staging חייב לשבת באותה תיקייה כדי שה-rename יהיה באותו volume; העלאה
  /// שיושבת ב-temp של המערכת עלולה להיות על volume אחר, ואז ה-rename נכשל או
  /// מתדרדר להעתקה. עד ה-rename הקובץ המקורי שלם, ולכן כשל באמצע אינו מאבד
  /// את המסמך הקודם.
  ///
  /// **אין fallback שכותב ישירות ליעד.** rename שנכשל הוא כשל של השמירה, וזה
  /// בכוונה: העתקה על הקובץ הקיים היא בדיוק מה שהחוזה מבטיח שלא יקרה —
  /// קריסה באמצעה משאירה את המסמך של המשתמש קטוע. עדיף להיכשל בגלוי ולהשאיר
  /// את המקור שלם, והתוסף ינסה שוב או יציע „שמור בשם”.
  ///
  /// מה שכן מובטח: המקור אינו נהרס. אטומיות מלאה תלויה במערכת הקבצים —
  /// התיעוד של `File.rename` אינו מבטיח אותה, ובפועל היא מתקיימת ב-POSIX
  /// באותו volume וב-Windows דרך החלפה. לכן אין להצהיר „אטומי” בלי הסתייגות.
  Future<void> _atomicWrite(File source, String targetPath) async {
    final target = File(targetPath);
    final suffix = _randomSuffix();
    final staging = File(
      p.join(target.parent.path, '.${p.basename(targetPath)}.$suffix$_stagingExt'),
    );

    // שאריות מכתיבה שנקטעה (קריסה בין ה-copy ל-rename) — אין להן שום מנגנון
    // אחר שינקה אותן, והן יושבות בתיקיית המסמכים של המשתמש.
    await _sweepStagingLeftovers(target.parent);

    try {
      await source.copy(staging.path);

      // flush לפני ה-rename: File.copy אינו מבטיח שהבייטים ירדו לדיסק, ובלי
      // זה rename שנרשם ל-journal לפני הנתונים יכול להשאיר יעד קטוע אחרי
      // הפסקת חשמל. מול מות תהליך בלבד ה-rename מספיק; זה מכסה גם את השאר.
      final handle = await staging.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }

      await staging.rename(targetPath);
    } catch (_) {
      try {
        if (await staging.exists()) await staging.delete();
      } catch (_) {
        // נעול (אנטי-וירוס ב-Windows) — יימחק ב-sweep של הכתיבה הבאה לתיקייה.
      }
      rethrow;
    }
  }

  static const String _stagingExt = '.otztmp';

  /// suffix אקראי ולא חתימת זמן: שתי שמירות באותה מיקרו-שנייה היו מתנגשות.
  String _randomSuffix() {
    final random = math.Random.secure();
    return List<int>.generate(8, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// מוחק קובצי staging נטושים בתיקיית היעד.
  ///
  /// גיל מינימלי, כדי לא למחוק staging של שמירה שמתרחשת במקביל בתוסף אחר.
  Future<void> _sweepStagingLeftovers(Directory dir) async {
    const minAge = Duration(minutes: 10);
    try {
      if (!await dir.exists()) return;
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File || !entry.path.endsWith(_stagingExt)) continue;
        final age = DateTime.now().difference((await entry.stat()).modified);
        if (age < minAge) continue;
        try {
          await entry.delete();
        } catch (_) {
          // נעול או של תהליך אחר — לא בעיה שלנו.
        }
      }
    } catch (_) {
      // ניקוי best-effort; אין להפיל בגללו שמירה.
    }
  }

  /// `fs.resolveFileUrl` — בונה מחדש URL טרי לקובץ שכבר אושר (לפי token שהתוסף
  /// שמר). נצרך אחרי reload, כשהפורט של השרת השתנה ורישום הזיכרון אבד.
  Future<Map<String, dynamic>> _resolveUserFileUrl(
    Map<String, dynamic> args,
  ) async {
    final token = args['token'] as String?;
    if (token == null) throw Exception('error.invalid_params: token required');
    final canonical = await _resolveGrantedFilePath(token);
    final url = await _fileServer.registerWithToken(
      pluginId: plugin.pluginId,
      canonicalPath: canonical,
      token: token,
    );
    return {
      'token': token,
      'url': url,
      'name': p.basename(canonical),
      'size': await File(canonical).length(),
    };
  }

  /// `fs.readTextFile` — מחזיר את תוכן הקובץ המאושר כמחרוזת (לקבצי טקסט קטנים).
  /// מוגבל ל-10MB כדי לא לתקוע את הגשר; לקבצים גדולים יש להשתמש ב-`resolveFileUrl`.
  Future<String> _readUserTextFile(Map<String, dynamic> args) async {
    final token = args['token'] as String?;
    if (token == null) throw Exception('error.invalid_params: token required');
    final canonical = await _resolveGrantedFilePath(token);
    final file = File(canonical);
    const maxTextBytes = 10 * 1024 * 1024;
    if (await file.length() > maxTextBytes) {
      throw Exception('error.too_large: file exceeds 10MB text limit');
    }
    // קובץ שהמשתמש בחר יכול להיות בכל קידוד; `readAsString` היה זורק על
    // קובץ ANSI עברית והתוסף היה מקבל שגיאה במקום את התוכן.
    return readTextFileSmart(file);
  }

  /// פותר את הנתיב הקנוני של קובץ מאושר לפי [token], או זורק `error.not_found`
  /// אם ה-token לא מוכר או שהקובץ נמחק (ומנקה אז את ה-grant).
  Future<String> _resolveGrantedFilePath(String token) async {
    final stored = await _loadUserFileGrant(token);
    if (stored == null) {
      throw Exception('error.not_found: unknown file token');
    }
    final canonical = canonicalizeNearestExisting(stored.path);
    if (canonical == null || !File(canonical).existsSync()) {
      await _removeUserFileGrant(token);
      throw Exception('error.not_found: file no longer exists');
    }
    return canonical;
  }

  // רישומי הקבצים המאושרים נשמרים ב-KV (`_internal/user_file_grants`) כמיפוי
  // token→נתיב, כך שהתוסף שומר אצלו רק token אטום וה-grant שורד reload.
  static const String _userFileGrantsKey = 'user_file_grants';

  Future<Map<String, dynamic>> _readUserFileGrants() async {
    final raw = await _pluginRepo.getKV(
      plugin.pluginId,
      '_internal',
      _userFileGrantsKey,
    );
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUserFileGrant(
    String token,
    String path, {
    required bool writable,
  }) async {
    final grants = await _readUserFileGrants();
    grants[token] = {
      'path': path,
      'access': writable ? 'readwrite' : 'read',
    };
    await _pluginRepo.setKV(
      plugin.pluginId,
      '_internal',
      _userFileGrantsKey,
      jsonEncode(grants),
    );
  }

  /// קורא grant, כולל הפורמט הישן.
  ///
  /// עד הוספת הכתיבה ה-grant היה `token -> path` כמחרוזת. מיגרציה: מחרוזת
  /// נקראת כהרשאת קריאה בלבד. אין המרה בכתיבה — grant ישן נשאר כמחרוזת עד
  /// שיישמר מחדש, וכך גרסה קודמת של אוצריא עדיין קוראת אותו.
  Future<({String path, bool writable})?> _loadUserFileGrant(
    String token,
  ) async {
    final value = (await _readUserFileGrants())[token];
    if (value is String) return (path: value, writable: false);
    if (value is Map) {
      final path = value['path'];
      if (path is! String) return null;
      return (path: path, writable: value['access'] == 'readwrite');
    }
    return null;
  }

  Future<void> _removeUserFileGrant(String token) async {
    final grants = await _readUserFileGrants();
    if (grants.remove(token) != null) {
      await _pluginRepo.setKV(
        plugin.pluginId,
        '_internal',
        _userFileGrantsKey,
        jsonEncode(grants),
      );
    }
  }

  // ----------------------------------------------------------------
  // shortcut.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleShortcut(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'create':
        final granted = await _pluginRepo.getPermission(
          plugin.pluginId,
          'ui.create_shortcut',
        );
        if (granted != true) {
          throw Exception(
            'error.permission_denied: ui.create_shortcut required',
          );
        }

        final label = (args['label'] as String?)?.trim();
        if (label == null || label.isEmpty) {
          throw Exception('error.invalid_params: label required');
        }

        final locationRaw =
            (args['location'] as String?)?.trim().toLowerCase() ?? 'desktop';
        final ShortcutLocation location;
        switch (locationRaw) {
          case 'desktop':
            location = ShortcutLocation.desktop;
          case 'startmenu':
            location = ShortcutLocation.startMenu;
          default:
            throw Exception(
              'error.invalid_params: location must be "desktop" or "startMenu"',
            );
        }

        final placeLabel = location == ShortcutLocation.startMenu
            ? 'תפריט ההתחל'
            : 'שולחן העבודה';
        final confirmed = await _dependencies.showConfirmDialog(
          title: 'יצירת קיצור דרך',
          content:
              'התוסף "${plugin.name}" מבקש ליצור קיצור דרך בשם "$label" ב$placeLabel.',
        );
        if (!confirmed) {
          return {'created': false};
        }

        // ה-deep-link נבנה תמיד בצד ה-host — קיצור לתוסף הנוכחי בלבד, כך
        // שתוסף אינו יכול לייצר קיצור שמפנה ל-route אחר או לסכמה זרה.
        final path = await _shortcutService.createShortcut(
          deepLink: 'otzaria://open/plugin/${plugin.pluginId}',
          label: label,
          location: location,
        );
        return {'created': true, 'path': path};
      default:
        throw Exception(
          'error.unknown_method: Unknown action in shortcut: $action',
        );
    }
  }

  /// רושם למעקב את מפתחות ה-KV של תנאי ה-`when` בפריט שנרשם בזמן ריצה,
  /// אחרת הסינון שלו לא יגיב ל-`storage.set`.
  Future<void> _trackWhenStorageKeys(Map<String, dynamic> args) async {
    final raw = args['when'];
    if (raw == null) return;
    try {
      final keys = PluginWhenCondition.fromJson(raw).storageKeys;
      if (keys.isEmpty) return;
      await PluginConditionEvaluator.instance.trackStorageKeys(
        plugin.pluginId,
        keys,
        _pluginRepo,
      );
    } on PluginWhenConditionException {
      return;
    }
  }

  // ----------------------------------------------------------------
  // storage.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleStorage(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'get':
        final key = args['key'] as String?;
        if (key == null) throw Exception("error.invalid_params: key required");
        final value = await _pluginRepo.getKV(
          plugin.pluginId,
          kDefaultStorageNamespace,
          key,
        );
        return value != null ? jsonDecode(value) : null;
      case 'set':
        final key = args['key'] as String?;
        final value = args['value'];
        if (key == null || value == null) {
          throw Exception("error.invalid_params: key and value required");
        }
        await _pluginRepo.setKV(
          plugin.pluginId,
          kDefaultStorageNamespace,
          key,
          jsonEncode(value),
        );
        PluginConditionEvaluator.instance.onStorageValueChanged(
          plugin.pluginId,
          key,
          value,
        );
        return true;
      case 'remove':
        final key = args['key'] as String?;
        if (key == null) throw Exception("error.invalid_params: key required");
        await _pluginRepo.removeKV(
          plugin.pluginId,
          kDefaultStorageNamespace,
          key,
        );
        PluginConditionEvaluator.instance.onStorageRemoved(
          plugin.pluginId,
          key,
        );
        return true;
      case 'list':
        return _pluginRepo.listKVKeys(
          plugin.pluginId,
          kDefaultStorageNamespace,
        );
      default:
        throw Exception(
          "error.unknown_method: Unknown action in storage: $action",
        );
    }
  }

  // ----------------------------------------------------------------
  // settings.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleSettings(
    String action,
    Map<String, dynamic> args,
  ) async {
    bool isAllowed(String key) => PluginSettingsAccessPolicy.isReadable(key);

    switch (action) {
      case 'get':
        final key = args['key'] as String?;
        if (key == null) throw Exception('error.invalid_params: key required');
        // מפתח חסום מוחזר כשגיאה ולא כ-null: null זהה להגדרה שלא נקבעה, ולתוסף
        // לא הייתה דרך להבחין בין "אין ערך" ל"אסור לך לקרוא".
        if (!isAllowed(key)) {
          throw Exception(
            'error.forbidden: setting is not readable by plugins',
          );
        }
        return Settings.getValue(key);
      case 'getMany':
        final keys = (args['keys'] as List?)?.cast<String>() ?? [];
        final Map<String, dynamic> res = {};
        for (final k in keys) {
          if (isAllowed(k)) res[k] = Settings.getValue(k);
        }
        return res;
      default:
        throw Exception(
          "error.unknown_method: Unknown action in settings: $action",
        );
    }
  }

  // ----------------------------------------------------------------
  // calendar.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleCalendar(
    String action,
    Map<String, dynamic> args,
  ) async {
    final calendarState = _dependencies.calendarCubit.state;

    // getDailyTimes/getHalachicTimes מקבלים אופציונלית date (ISO) ומיקום —
    // עיר מרשימת הלוח (city) או קואורדינטות (lat+lng, עם elevation/timezone/
    // inIsrael אופציונליים). בלי אף פרמטר מוחזרים זמני התאריך והעיר הנבחרים
    // בלוח (התנהגות הגרסאות הקודמות).
    Map<String, String> resolveDailyTimes() {
      final rawDate = args['date'];
      if (rawDate != null && rawDate is! String) {
        throw Exception(
          'error.invalid_params: Date must be an ISO-8601 string',
        );
      }
      final dateArg = rawDate == null ? null : DateTime.tryParse(rawDate);
      if (rawDate != null && dateArg == null) {
        throw Exception('error.invalid_params: Invalid date: $rawDate');
      }
      final cityArg = (args['city'] as String?)?.trim();
      final latArg = args['lat'], lngArg = args['lng'];
      final date = dateArg ?? calendarState.selectedGregorianDate;

      if ((latArg == null) != (lngArg == null)) {
        throw Exception('error.invalid_params: Both lat and lng are required');
      }
      if (latArg != null && lngArg != null) {
        if (latArg is! num || lngArg is! num) {
          throw Exception('error.invalid_params: Coordinates must be numbers');
        }
        if (cityArg != null && cityArg.isNotEmpty) {
          throw Exception(
            'error.invalid_params: Pass either city or lat/lng, not both',
          );
        }
        final lat = latArg.toDouble(), lng = lngArg.toDouble();
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
          throw Exception('error.invalid_params: Coordinates out of range');
        }
        // בלי אזור זמן מפורש — אזור נומינלי מקו האורך (Etc/GMT הפוך-סימן:
        // Etc/GMT-3 הוא UTC+3). מומלץ להעביר מזהה IANA אמיתי.
        final tzArg = (args['timezone'] as String?)?.trim();
        final nominalOffset = -(lng / 15).round();
        final tzId = (tzArg == null || tzArg.isEmpty)
            ? 'Etc/GMT${nominalOffset >= 0 ? '+' : ''}$nominalOffset'
            : tzArg;
        try {
          return zmanim_helpers.calculateDailyTimesForCoordinates(
            date,
            latitude: lat,
            longitude: lng,
            elevation: (args['elevation'] as num?)?.toDouble() ?? 0,
            timeZoneId: tzId,
            inIsrael: args['inIsrael'] as bool? ?? false,
          );
        } on tz.LocationNotFoundException {
          throw Exception('error.invalid_params: Unknown timezone: $tzId');
        }
      }

      if (dateArg == null && (cityArg == null || cityArg.isEmpty)) {
        return calendarState.dailyTimes;
      }
      final city = (cityArg == null || cityArg.isEmpty)
          ? calendarState.selectedCity
          : cityArg;
      if (getCityData(city) == null) {
        throw Exception('error.invalid_params: Unknown city: $city');
      }
      return zmanim_helpers.calculateDailyTimes(date, city);
    }

    switch (action) {
      case 'getSelectedDate':
        return calendarState.selectedGregorianDate.toIso8601String();
      case 'getDailyTimes':
        return resolveDailyTimes();
      case 'getHalachicTimes':
        // dailyTimes contains all halachic times (shekia, tzet haochavim, etc.)
        return resolveDailyTimes();
      case 'getCities':
        // רשימת הערים שהלוח מכיר — לבחירת עיר ב-getDailyTimes {city}
        return [
          for (final country in cityCoordinates.entries)
            for (final city in country.value.entries)
              {
                'name': city.key,
                'country': country.key,
                'lat': city.value['lat'],
                'lng': city.value['lng'],
                'elevation': city.value['elevation'],
                'timezone': city.value['timezone'],
                'inIsrael': country.key == 'ארץ ישראל',
              },
        ];
      case 'getJewishDate':
        final dateArg = args['date'] != null
            ? DateTime.tryParse(args['date'] as String)
            : null;
        final targetDate = dateArg ?? calendarState.selectedGregorianDate;
        return _buildJewishDatePayload(targetDate, calendarState.inIsrael);
      case 'getEvents':
        final date = args['date'] != null
            ? DateTime.tryParse(args['date'] as String) ??
                  calendarState.selectedGregorianDate
            : calendarState.selectedGregorianDate;
        final events = calendarState.events
            .where((e) {
              final eventDate = e.baseGregorianDate;
              return eventDate.year == date.year &&
                  eventDate.month == date.month &&
                  eventDate.day == date.day;
            })
            .map(
              (e) => {
                'id': e.id,
                'title': e.title,
                'date': e.baseGregorianDate.toIso8601String(),
                'description': e.description,
              },
            )
            .toList();
        return events;
      default:
        throw Exception(
          "error.unknown_method: Unknown action in calendar: $action",
        );
    }
  }

  // ----------------------------------------------------------------
  // publishedData.*
  // ----------------------------------------------------------------
  Future<dynamic> _handlePublishedData(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'upsert':
        final type = args['type'] as String?;
        final scope = args['scope'] as String? ?? 'global';
        final key = args['key'] as String?;
        final payload = args['payload'];
        if (type == null || key == null || payload == null) {
          throw Exception('error.invalid_params: type, key, payload required');
        }
        await _pluginRepo.publishRecord(
          plugin.pluginId,
          type,
          scope,
          key,
          jsonEncode(payload),
          null,
        );
        // רענון חי של לוח השנה כשמדובר באירוע לוח
        if (type == 'calendar.event') {
          _dependencies.calendarCubit.refreshPluginEvents(
            currentBookId: _currentBookId(),
            currentBookUid: _currentBookUid(),
            currentWorkspaceId: _currentWorkspaceId(),
          );
        }
        return true;
      case 'remove':
        final type = args['type'] as String?;
        final scope = args['scope'] as String? ?? 'global';
        final key = args['key'] as String?;
        if (type == null || key == null) {
          throw Exception('error.invalid_params: type and key required');
        }
        await _pluginRepo.unpublishRecord(plugin.pluginId, type, scope, key);
        // רענון חי של לוח השנה
        if (type == 'calendar.event') {
          _dependencies.calendarCubit.refreshPluginEvents(
            currentBookId: _currentBookId(),
            currentBookUid: _currentBookUid(),
            currentWorkspaceId: _currentWorkspaceId(),
          );
        }
        return true;
      case 'listOwn':
        final rows = await _pluginRepo.getPluginPublishedRecords(
          plugin.pluginId,
        );
        return rows
            .map(
              (record) => {
                'type': record.type,
                'scope': record.scope,
                'key': record.key,
                'payload': record.decodedPayload,
              },
            )
            .toList();
      default:
        throw Exception(
          "error.unknown_method: Unknown action in publishedData: $action",
        );
    }
  }

  // ----------------------------------------------------------------
  // feedback.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleFeedback(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'sendEmail':
        final to = args['to'] as String?;
        final subject = args['subject'] as String?;
        final body = args['body'] as String?;
        final includeSystemInfo = args['includeSystemInfo'] as bool? ?? false;

        if (to == null || subject == null || body == null) {
          throw Exception('error.invalid_params: to, subject, body required');
        }

        String finalBody = body;
        if (includeSystemInfo) {
          final packageInfo = await PackageInfo.fromPlatform();
          finalBody += '\n\n---\n';
          finalBody += 'גרסה: ${packageInfo.version}\n';
          finalBody += 'פלטפורמה: ${Platform.operatingSystem}\n';
          finalBody += 'תוסף: ${plugin.name} (${plugin.pluginId})\n';
        }

        final emailUri = Uri(
          scheme: 'mailto',
          path: to,
          query: _encodeQueryParameters({
            'subject': subject,
            'body': finalBody,
          }),
        );

        try {
          final launched = await launchUrl(
            emailUri,
            mode: LaunchMode.externalApplication,
          );
          if (!launched) {
            throw Exception('Failed to launch email client');
          }
          return true;
        } catch (e) {
          throw Exception('error.internal: Failed to open email client: $e');
        }

      case 'report':
        final rawDetails = args['details'];
        final details = rawDetails is String ? rawDetails.trim() : '';
        if (details.isEmpty) {
          throw Exception('error.invalid_params: details required');
        }
        final cappedDetails =
            details.length > PluginReportService.maxDetailsLength
            ? details.substring(0, PluginReportService.maxDetailsLength)
            : details;

        // המייל השמור בהגדרות גובר — כתובת מהתוסף משמשת רק כשאין שמור,
        // כדי שתוסף לא יוכל לעקוף את הכתובת שהמשתמש קבע.
        final rawEmail = args['reporterEmail'];
        var email =
            Settings.getValue<String>(
              SettingsRepository.keyErrorReportSenderEmail,
            )?.trim() ??
            '';
        if (email.isEmpty && rawEmail is String) {
          email = rawEmail.trim();
        }

        final preview = cappedDetails.length > 300
            ? '${cappedDetails.substring(0, 300)}…'
            : cappedDetails;
        // הדיאלוג הוא גבול האבטחה, ולכן חייב לחשוף גם את הכתובת שתישלח —
        // היא עשויה להגיע מהגדרות המשתמש בלי שהתוסף ביקש אותה.
        final emailLine = email.isEmpty ? '' : '\n\nכתובת לחזרה: $email';
        final confirmed = await _dependencies.showConfirmDialog(
          title: 'שליחת דיווח למפתח התוסף',
          content:
              'התוסף "${plugin.name}" מבקש לשלוח דיווח לאתר אוצריא, '
              'שיעביר אותו למפתח התוסף.\n\nתוכן הדיווח:\n$preview$emailLine',
        );
        if (!confirmed) {
          return 'cancelled';
        }

        final record = await _reportService.buildRecord(
          pluginUid: plugin.pluginId,
          pluginName: plugin.name,
          pluginVersion: plugin.version,
          details: cappedDetails,
          reportType: args['reportType'] is String
              ? args['reportType'] as String
              : null,
          reporterEmail: email.isEmpty ? null : email,
        );
        final status = await _reportService.submitReport(record);
        return status == PluginReportDeliveryStatus.sent ? 'sent' : 'queued';

      // ביט אחד בלבד: קיום כתובת שמורה, בלי לחשוף את הכתובת עצמה לתוסף.
      case 'hasReporterEmail':
        final saved = Settings.getValue<String>(
          SettingsRepository.keyErrorReportSenderEmail,
        )?.trim();
        return saved != null && saved.isNotEmpty;

      default:
        throw Exception(
          'error.unknown_method: Unknown action in feedback: $action',
        );
    }
  }

  // ----------------------------------------------------------------
  // history.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleHistory(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'list':
        final limit = args['limit'] as int? ?? 50;
        final historyState = _dependencies.historyBloc.state;
        if (historyState is! HistoryLoaded) return [];

        return historyState.history
            .where((b) => !b.isSearch)
            .take(limit)
            .map(
              (b) => {
                ...PluginBookIdentity.toJsonWithUid(b.book),
                'title': b.book.title,
                'ref': b.ref,
                'index': b.index,
                'workspaceName': b.workspaceName,
              },
            )
            .toList();

      case 'listSearches':
        final limit = args['limit'] as int? ?? 50;
        final historyState = _dependencies.historyBloc.state;
        if (historyState is! HistoryLoaded) return [];

        return historyState.history
            .where((b) => b.isSearch)
            .take(limit)
            .map(
              (b) => {
                'query': b.book.title,
                'ref': b.ref,
                'workspaceName': b.workspaceName,
              },
            )
            .toList();

      case 'clear':
        _dependencies.historyBloc.add(ClearHistory());
        return true;

      case 'remove':
        {
          final id = PluginBookIdentity.parseId(args['id']);
          final bookId = args['bookId'] as String?;
          final type = (args['type'] as String?)?.trim().toLowerCase();
          final source = (args['source'] as String?)?.trim().toLowerCase();
          final index = (args['index'] as num?)?.toInt();
          if (id == null &&
              bookId == null &&
              (args['bookUid'] as String?)?.trim().isNotEmpty != true) {
            throw Exception(
              'error.invalid_params: id, bookUid or bookId required',
            );
          }
          final historyState = _dependencies.historyBloc.state;
          if (historyState is! HistoryLoaded) return false;

          final historyList = historyState.history;
          int? indexToRemove;

          for (int i = 0; i < historyList.length; i++) {
            final item = historyList[i];
            if (!PluginBookIdentity.matches(
              item.book,
              id: id,
              bookId: bookId,
              bookUid: args['bookUid'] as String?,
              type: type,
              source: source,
            )) {
              continue;
            }
            if (index != null && item.index != index) continue;
            indexToRemove = i;
            break;
          }

          if (indexToRemove != null) {
            _dependencies.historyBloc.add(RemoveHistory(indexToRemove));
            return true;
          }
          return false;
        }

      default:
        throw Exception(
          'error.unknown_method: Unknown action in history: $action',
        );
    }
  }

  // ----------------------------------------------------------------
  // bookmarks.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleBookmarks(
    String action,
    Map<String, dynamic> args,
  ) async {
    final bloc = _dependencies.bookmarkBloc;
    if (bloc == null) {
      throw Exception('error.unavailable: bookmarks are not available here');
    }
    switch (action) {
      case 'list':
        final limit = (args['limit'] as num?)?.toInt() ?? 50;
        return bloc.state.bookmarks
            .take(limit < 0 ? 0 : limit)
            .map(
              (b) => {
                ...PluginBookIdentity.toJsonWithUid(b.book),
                'title': b.book.title,
                'ref': b.ref,
                'index': b.index,
                'label': b.label,
                'targetKind': b.targetKind.name,
                'createdAt': b.createdAt?.toIso8601String(),
              },
            )
            .toList();

      case 'add':
        {
          final index = (args['index'] as num?)?.toInt() ?? 0;
          if (index < 0) {
            throw Exception('error.invalid_params: index must not be negative');
          }
          final hasUid =
              (args['bookUid'] as String?)?.trim().isNotEmpty == true;
          if (!hasUid &&
              PluginBookIdentity.parseId(args['id']) == null &&
              (args['bookId'] ?? args['title']) == null) {
            throw Exception(
              'error.invalid_params: id, bookUid or bookId required',
            );
          }
          final book = _findPluginBook(
            await DataRepository.instance.library,
            args,
          );
          if (book == null) return false;
          final label = (args['label'] as String?)?.trim();
          var ref = (args['ref'] as String?)?.trim() ?? '';
          if (ref.isEmpty) {
            ref = book is TextBook
                ? addBookTitleToRef(
                    await refFromIndex(index, book.tableOfContents),
                    book.title,
                  )
                : book.title;
          }
          return await bloc.addBookmarkAndSave(
            ref: ref,
            book: book,
            index: index,
            label: label == null || label.isEmpty ? null : label,
          );
        }

      case 'remove':
        {
          final id = PluginBookIdentity.parseId(args['id']);
          final bookId = args['bookId'] as String?;
          if (id == null &&
              bookId == null &&
              (args['bookUid'] as String?)?.trim().isNotEmpty != true) {
            throw Exception(
              'error.invalid_params: id, bookUid or bookId required',
            );
          }
          final type = (args['type'] as String?)?.trim().toLowerCase();
          final source = (args['source'] as String?)?.trim().toLowerCase();
          final index = (args['index'] as num?)?.toInt();
          final bookmarks = bloc.state.bookmarks;
          for (var i = 0; i < bookmarks.length; i++) {
            final item = bookmarks[i];
            if (!PluginBookIdentity.matches(
              item.book,
              id: id,
              bookId: bookId,
              bookUid: args['bookUid'] as String?,
              type: type,
              source: source,
            )) {
              continue;
            }
            if (index != null && item.index != index) continue;
            return await bloc.removeBookmarkAndSave(i);
          }
          return false;
        }

      default:
        throw Exception(
          'error.unknown_method: Unknown action in bookmarks: $action',
        );
    }
  }

  // ----------------------------------------------------------------
  // tools.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleTools(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'gematria':
        {
          final text = args['text'];
          if (text is! String || text.trim().isEmpty || text.length > 2000) {
            throw Exception('error.invalid_params: text required');
          }
          final method = (args['method'] as String?) ?? 'regular';
          if (!const {'regular', 'small', 'finalLetters'}.contains(method)) {
            throw Exception('error.invalid_params: unknown method "$method"');
          }
          var value = GimatriaSearch.gimatria(text, method: method);
          final words = text
              .split(RegExp(r'\s+'))
              .where((w) => w.trim().isNotEmpty)
              .length;
          // "עם הכולל" אינו חלק מ-gimatria() — מסך הגימטריה מוסיף את מספר
          // המילים בעצמו, ואותו חישוב נשמר כאן.
          if (args['withKolel'] == true) value += words;
          return {'value': value, 'method': method, 'words': words};
        }

      case 'dictionary':
        {
          final term = args['term'];
          if (term is! String || term.trim().isEmpty || term.length > 200) {
            throw Exception('error.invalid_params: term required');
          }
          final repository = DictionaryLookupRepository.instance;
          await repository.ensureAcronymsLoaded();
          await repository.ensureAramaicLoaded();
          return {
            'term': term.trim(),
            'acronyms': repository
                .findAcronymMatches(term)
                .map((e) => {'acronym': e.acronym, 'meanings': e.meanings})
                .toList(),
            'aramaic': repository
                .findAramaicMatches(term)
                .map((e) => {'aramaic': e.aramaic, 'hebrew': e.hebrew})
                .toList(),
          };
        }

      default:
        throw Exception(
          'error.unknown_method: Unknown action in tools: $action',
        );
    }
  }

  // ----------------------------------------------------------------
  // notifications.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleNotifications(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'showInApp':
        // התראה בתוך האפליקציה (UiSnack)
        final message = args['message'] as String?;
        final type = args['type'] as String? ?? 'info';

        if (message == null || message.isEmpty) {
          throw Exception('error.invalid_params: message required');
        }

        final onTap = _messageTapHandler(args);
        switch (type) {
          case 'success':
            UiSnack.showSuccess(message, onTap: onTap);
            break;
          case 'error':
            UiSnack.showError(message, onTap: onTap);
            break;
          case 'info':
          default:
            UiSnack.show(message, onTap: onTap);
            break;
        }
        return true;

      case 'sendSystem':
        // התראה למערכת ההפעלה
        final title = args['title'] as String?;
        final body = args['body'] as String?;
        final id = args['id'] as int?;

        if (title == null || body == null) {
          throw Exception('error.invalid_params: title and body required');
        }

        // בדיקה אם השירות מאותחל
        if (!_notificationService.isInitialized) {
          throw Exception(
            'error.unavailable: Notification service not initialized',
          );
        }

        // בדיקה אם יש הרשאות
        if (!_notificationService.hasPermissions) {
          throw Exception(
            'error.forbidden: Notification permissions not granted',
          );
        }

        // שליחת התראה מיידית
        final notificationId = id ?? DateTime.now().millisecondsSinceEpoch;

        await _notificationService.flutterLocalNotificationsPlugin.show(
          id: notificationId,
          title: title,
          body: body,
          notificationDetails: _buildNotificationDetails(),
        );

        // שמירת ה-ID לעקוב אחרי התראות התוסף
        await _trackNotificationId(notificationId);

        return {'id': notificationId};

      case 'scheduleSystem':
        // תזמון התראה למערכת ההפעלה
        final title = args['title'] as String?;
        final body = args['body'] as String?;
        final scheduledTime = args['scheduledTime'] as String?;
        final id = args['id'] as int?;

        if (title == null || body == null || scheduledTime == null) {
          throw Exception(
            'error.invalid_params: title, body, and scheduledTime required',
          );
        }

        final dateTime = DateTime.tryParse(scheduledTime);
        if (dateTime == null) {
          throw Exception(
            'error.invalid_params: Invalid scheduledTime format. Use ISO 8601.',
          );
        }

        if (dateTime.isBefore(DateTime.now())) {
          throw Exception(
            'error.invalid_params: scheduledTime must be in the future',
          );
        }

        if (!_notificationService.isInitialized) {
          throw Exception(
            'error.unavailable: Notification service not initialized',
          );
        }

        if (!_notificationService.hasPermissions) {
          throw Exception(
            'error.forbidden: Notification permissions not granted',
          );
        }

        final notificationId = id ?? DateTime.now().millisecondsSinceEpoch;

        await _notificationService.scheduleNotification(
          id: notificationId,
          title: title,
          body: body,
          eventDate: dateTime,
          reminderMinutes: 0,
        );

        // שמירת ה-ID לעקוב אחרי התראות התוסף
        await _trackNotificationId(notificationId);

        return {'id': notificationId};

      case 'cancel':
        // ביטול התראה
        final id = args['id'] as int?;
        if (id == null) throw Exception('error.invalid_params: id required');

        if (!_notificationService.isInitialized) {
          throw Exception(
            'error.unavailable: Notification service not initialized',
          );
        }

        await _notificationService.cancelNotification(id);
        await _untrackNotificationId(id);
        return true;

      case 'cancelAll':
        // ביטול כל ההתראות של התוסף
        if (!_notificationService.isInitialized) {
          throw Exception(
            'error.unavailable: Notification service not initialized',
          );
        }

        final notificationIds = await _getTrackedNotificationIds();
        for (final id in notificationIds) {
          await _notificationService.cancelNotification(id);
        }
        await _clearTrackedNotificationIds();
        return true;

      case 'checkPermissions':
        // בדיקת הרשאות התראות
        if (!_notificationService.isInitialized) {
          return {'granted': false, 'initialized': false};
        }

        final hasPermissions = await _notificationService.checkPermissions();
        return {
          'granted': hasPermissions,
          'initialized': _notificationService.isInitialized,
        };

      case 'requestPermissions':
        // בקשת הרשאות התראות
        if (!_notificationService.isInitialized) {
          throw Exception(
            'error.unavailable: Notification service not initialized',
          );
        }

        final granted = await _notificationService.requestPermissions();
        return {'granted': granted};

      default:
        throw Exception(
          'error.unknown_method: Unknown action in notifications: $action',
        );
    }
  }

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------

  /// Encode query parameters for mailto URL
  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }

  /// Build notification details for all platforms
  NotificationDetails _buildNotificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      'plugin_channel',
      'התראות תוספים',
      channelDescription: 'התראות מתוספי אוצריא',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const windowsDetails = WindowsNotificationDetails();

    return const NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
      macOS: iOSDetails,
      linux: LinuxNotificationDetails(),
      windows: windowsDetails,
    );
  }

  /// Track notification ID for this plugin (internal namespace)
  Future<void> _trackNotificationId(int id) async {
    final ids = await _getTrackedNotificationIds();
    if (!ids.contains(id)) {
      ids.add(id);
      await _pluginRepo.setKV(
        plugin.pluginId,
        '_internal',
        'notification_ids',
        jsonEncode(ids),
      );
    }
  }

  /// Untrack notification ID
  Future<void> _untrackNotificationId(int id) async {
    final ids = await _getTrackedNotificationIds();
    if (ids.remove(id)) {
      await _pluginRepo.setKV(
        plugin.pluginId,
        '_internal',
        'notification_ids',
        jsonEncode(ids),
      );
    }
  }

  /// Get all tracked notification IDs for this plugin
  Future<List<int>> _getTrackedNotificationIds() async {
    final value = await _pluginRepo.getKV(
      plugin.pluginId,
      '_internal',
      'notification_ids',
    );
    if (value == null) return [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.cast<int>();
      }
    } catch (_) {}
    return [];
  }

  /// Clear all tracked notification IDs
  Future<void> _clearTrackedNotificationIds() async {
    await _pluginRepo.removeKV(
      plugin.pluginId,
      '_internal',
      'notification_ids',
    );
  }

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------

  Map<String, dynamic> _buildJewishDatePayload(DateTime date, bool inIsrael) {
    final jewishCalendar = JewishCalendar.fromDateTime(date)
      ..inIsrael = inIsrael;
    final formatter = HebrewDateFormatter()..hebrewFormat = true;

    return {
      'year': jewishCalendar.getJewishYear(),
      'month': jewishCalendar.getJewishMonth(),
      'day': jewishCalendar.getJewishDayOfMonth(),
      'gregorian': date.toIso8601String(),
      'monthName': formatter.formatMonth(jewishCalendar),
      'isLeapYear': jewishCalendar.isJewishLeapYear(),
      'isShabbat': jewishCalendar.getDayOfWeek() == 7,
      'parasha': _upcomingParasha(date, inIsrael, formatter),
      'holidays': _buildHolidayPayloads(jewishCalendar, formatter),
    };
  }

  String _upcomingParasha(
    DateTime date,
    bool inIsrael,
    HebrewDateFormatter formatter,
  ) {
    final dayOfWeek = date.weekday; // 1=Mon … 6=Sat, 7=Sun in Dart
    // Dart weekday: Mon=1 … Sat=6, Sun=7. Shabbat = Saturday = 6.
    final daysUntilShabbat = dayOfWeek == 6 ? 0 : (6 - dayOfWeek) % 7;
    final shabbatDate = date.add(Duration(days: daysUntilShabbat));
    final shabbatCalendar = JewishCalendar.fromDateTime(shabbatDate)
      ..inIsrael = inIsrael;
    return formatter.formatParsha(shabbatCalendar);
  }

  List<Map<String, String>> _buildHolidayPayloads(
    JewishCalendar jewishCalendar,
    HebrewDateFormatter formatter,
  ) {
    final holidays = <Map<String, String>>[];
    final seenLabels = <String>{};

    void addHoliday(String label, String kind) {
      final normalizedLabel = label.trim();
      if (normalizedLabel.isEmpty || !seenLabels.add(normalizedLabel)) {
        return;
      }
      holidays.add({'text': normalizedLabel, 'kind': kind});
    }

    final yomTovLabel = formatter.formatYomTov(jewishCalendar);
    if (yomTovLabel.isNotEmpty) {
      final month = jewishCalendar.getJewishMonth();
      final day = jewishCalendar.getJewishDayOfMonth();
      final idx = jewishCalendar.getYomTovIndex();

      // לימים טובים של פסח יש שמות ספציפיים שהספרייה לא מבדילה ביניהם
      if (idx == JewishCalendar.PESACH) {
        if (month == 1 && day == 21) {
          addHoliday('שביעי של פסח', 'yomTov');
        } else if (month == 1 && day == 22) {
          addHoliday('אחרון של פסח', 'yomTov');
        } else if (month == 1 && day == 16) {
          addHoliday('פסח שני', 'yomTov');
        } else {
          addHoliday(
            yomTovLabel,
            _holidayKindForLabel(yomTovLabel, jewishCalendar),
          );
        }
      } else {
        for (final label in yomTovLabel.split(',')) {
          addHoliday(label, _holidayKindForLabel(label, jewishCalendar));
        }
      }
    }

    if (jewishCalendar.isErevRoshChodesh()) {
      addHoliday(formatter.formatErevRoshChodesh(jewishCalendar), 'special');
    }

    if (jewishCalendar.isRoshChodesh()) {
      addHoliday(formatter.formatRoshChodesh(jewishCalendar), 'roshChodesh');
    }

    return holidays;
  }

  String _holidayKindForLabel(String label, JewishCalendar jewishCalendar) {
    final normalizedLabel = label.trim();
    if (normalizedLabel.contains('ראש חודש') ||
        normalizedLabel.contains('ר"ח')) {
      return 'roshChodesh';
    }

    if (jewishCalendar.isTaanis() &&
        jewishCalendar.getYomTovIndex() != JewishCalendar.YOM_KIPPUR) {
      return 'taanit';
    }

    if (jewishCalendar.isYomTovAssurBemelacha()) {
      return 'yomTov';
    }

    return 'special';
  }

  Future<List<String>> _getGrantedPermissions() async {
    return _pluginRepo.getGrantedPermissionNames(plugin.pluginId);
  }

  /// הספר שמייצג טאב כלפי התוספים.
  ///
  /// בטאב מפוצל הכותרת המשולבת אינה ספר, ולכן מדווחת החלונית הפעילה (ובטאב
  /// שאינו הנוכחי — הראשונה). דיווח כל החלוניות מחייב הרחבת הסכמה של
  /// `openTabs`, שהיא שינוי API בפני עצמו.
  /// מצב המפרשים של טאב הקריאה כפי שהוא כבר טעון בטאב — בלי שאילתה נוספת.
  /// `null` כשאין טאב קריאה, כשמצב הטאב עדיין לא נטען או כשאין בו מפרשים.
  Map<String, dynamic>? _getActiveCommentators() {
    final pane = _dependencies.tabsBloc.state.readingPane;
    if (pane is TextBookTab) {
      final state = pane.bloc.state;
      if (state is! TextBookLoaded) return null;
      if (state.availableCommentators.isEmpty &&
          state.activeCommentators.isEmpty) {
        return null;
      }
      return {
        'available': state.availableCommentators,
        'active': state.activeCommentators,
        'rare': state.rareCommentators.toList()..sort(),
        'groups': _commentatorGroupsToJson(state.commentatorGroups),
      };
    }
    if (pane is PdfBookTab) {
      // ל-PDF אין מצב מפרשים טעון; הרשימה נגזרת מהקישורים שכבר בטאב.
      final available = <String>{
        for (final link in pane.links)
          if (LinkTypes.isDependentTextLink(link.connectionType))
            getTitleFromPath(link.path2),
      }.toList()..sort();
      final active = pane.activeCommentators.toList()..sort();
      if (available.isEmpty && active.isEmpty) return null;
      return {
        'available': available,
        'active': active,
        'rare': const <String>[],
        'groups': const <Map<String, dynamic>>[],
      };
    }
    return null;
  }

  /// מוסיף/מסיר מפרשים בחלונית הקריאה הפעילה. מחזיר את הרשימה הפעילה
  /// שאחרי השינוי, או `null` כשאין ספר טקסט פתוח.
  Map<String, dynamic>? _setActiveCommentators(Map<String, dynamic> args) {
    final add = _commentatorNames(args['add']);
    final remove = _commentatorNames(args['remove']);
    if (add.isEmpty && remove.isEmpty) {
      throw Exception('error.invalid_params: add or remove is required');
    }
    final pane = _dependencies.tabsBloc.state.readingPane;
    if (pane is! TextBookTab) return null;
    final state = pane.bloc.state;
    if (state is! TextBookLoaded) return null;
    // רק מפרשים שקיימים בספר — שם שגוי היה מגיע לשמירה פר-ספר ונשאר שם.
    final available = state.availableCommentators.toSet();
    final unknown = add.where((name) => !available.contains(name)).toList();
    if (unknown.isNotEmpty) {
      throw Exception(
        'error.not_found: unknown commentators: ${unknown.join(', ')}',
      );
    }
    final active = state.activeCommentators.toList();
    for (final name in remove) {
      active.remove(name);
    }
    for (final name in add) {
      if (!active.contains(name)) active.add(name);
    }
    pane.bloc.add(UpdateCommentators(active));
    return {
      'available': state.availableCommentators,
      'active': active,
      'rare': state.rareCommentators.toList()..sort(),
      'groups': _commentatorGroupsToJson(state.commentatorGroups),
    };
  }

  List<String> _commentatorNames(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw Exception('error.invalid_params: add/remove must be arrays');
    }
    return raw
        .whereType<String>()
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
  }

  /// מה נתמך **בפועל** בהקשר הקריאה הנוכחי. הדגשות מצוירות רק בטור הטקסט
  /// הראשי (תצוגה משולבת וצורת הדף), ואין הדגשות/בחירה/תפריט הקשר ב-PDF.
  Map<String, dynamic> _getHighlightCapabilities() {
    final pane = _dependencies.tabsBloc.state.readingPane;
    if (pane is TextBookTab) {
      final state = pane.bloc.state;
      final pageShape = state is TextBookLoaded && state.showPageShapeView;
      return {
        'surface': pageShape ? 'pageShape' : 'combined',
        'highlights': true,
        'selection': true,
        'contextMenu': const ['mainText'],
      };
    }
    if (pane is PdfBookTab) {
      return {
        'surface': 'pdf',
        'highlights': false,
        'selection': false,
        'contextMenu': const <String>[],
      };
    }
    return {
      'surface': null,
      'highlights': false,
      'selection': false,
      'contextMenu': const <String>[],
    };
  }

  OpenedTab _paneForPlugins(OpenedTab tab) {
    if (tab is! CombinedTab) return tab;
    final state = _dependencies.tabsBloc.state;
    if (identical(tab, state.currentTab)) return state.activePane ?? tab;
    return leafPanes(tab).first;
  }

  Map<String, dynamic>? _buildCurrentSelection(
    OpenedTab? currentTab,
    String? currentRef,
  ) {
    if (currentTab is! TextBookTab) {
      return null;
    }

    final state = currentTab.bloc.state;
    if (state is! TextBookLoaded) {
      return null;
    }

    final selectedText = state.selectedTextForNote;
    if (selectedText == null || selectedText.trim().isEmpty) {
      return null;
    }

    final legacySelection = <String, dynamic>{
      'id': currentTab.book.id,
      'type': PluginBookIdentity.typeOf(currentTab.book),
      'source': PluginBookIdentity.sourceOf(currentTab.book),
      'bookUid': PluginBookIdentity.uidOf(currentTab.book),
      'text': selectedText,
      'start': state.selectedTextStart,
      'end': state.selectedTextEnd,
      'currentRef': currentRef,
      'currentBook': currentTab.title,
      'currentBookId': currentTab.title,
      'currentIndex': currentTab.index,
    };

    final start = state.selectedTextStart;
    final end = state.selectedTextEnd;
    final sectionIndex = state.selectedTextSectionIndex ?? currentTab.index;
    if (start == null ||
        end == null ||
        sectionIndex < 0 ||
        sectionIndex >= state.content.length) {
      return legacySelection;
    }

    final selection = const ReaderSelectionService().build(
      bookId: currentTab.title,
      bookTitle: currentTab.title,
      sectionIndex: sectionIndex,
      rawText: state.content[sectionIndex],
      settings: RenderSettings(
        removeNikud: state.removeNikud,
        removePunctuation: state.removePunctuation,
        removeTeamim:
            !(Settings.getValue<bool>(SettingsRepository.keyShowTeamim) ??
                true),
        replaceHolyNames:
            Settings.getValue<bool>(SettingsRepository.keyReplaceHolyNames) ??
            false,
      ),
      renderedStartUtf16: start,
      renderedEndUtf16: end,
      currentRef: currentRef,
    );
    if (selection == null) return legacySelection;
    return {...legacySelection, ...selection.toJson()};
  }

  String? _currentBookId() {
    return _dependencies.tabsBloc.state.readingPane?.title;
  }

  /// מזהה יציב של הספר בחלונית הקריאה, ל-scope של `book:<bookUid>`.
  String? _currentBookUid() {
    final pane = _dependencies.tabsBloc.state.readingPane;
    if (pane is TextBookTab) return PluginBookIdentity.uidOf(pane.book);
    if (pane is PdfBookTab) return PluginBookIdentity.uidOf(pane.book);
    return null;
  }

  String? _currentWorkspaceId() {
    return _dependencies.workspaceBloc.state.activeWorkspaceId;
  }

  // ----------------------------------------------------------------
  // database.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleDatabase(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'listSources':
        final sources = _databaseService.listSourcesForPlugin(plugin);
        return {'sources': sources};

      case 'describeSource':
        final sourceId = args['sourceId'] as String?;
        if (sourceId == null) {
          throw const PluginDatabaseException(
            'database.invalid_spec',
            'sourceId is required',
          );
        }
        return _databaseService.describeSource(plugin, sourceId);

      case 'query':
        return await _databaseService.query(plugin, args);

      case 'batchQuery':
        final queries = (args['queries'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>();
        if (queries == null) {
          throw const PluginDatabaseException(
            'database.invalid_spec',
            '"queries" list is required',
          );
        }
        final results = await _databaseService.batchQuery(plugin, queries);
        return {'results': results};

      default:
        throw Exception(
          'error.unknown_method: Unknown database action: $action',
        );
    }
  }

  // ----------------------------------------------------------------
  // plugin.*
  // ----------------------------------------------------------------
  Future<dynamic> _handlePlugin(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'requestInstall':
        final url = args['url'] as String?;
        if (url == null) throw Exception('error.invalid_params: url required');
        final cb = _dependencies.requestPluginInstall;
        if (cb == null) throw Exception('error.unavailable: install not wired');

        // ההורדה מתבצעת לפני דיאלוג ההרשאות ובלי הרשאת רשת, ולכן כתובת חופשית
        // כאן הייתה ערוץ יציאה לרשת לכל תוסף. מותרת רק החנות הרשמית.
        final parsedUrl = Uri.tryParse(url);
        if (parsedUrl == null ||
            !PluginStoreLinkParser.isStoreDownloadUri(parsedUrl)) {
          throw Exception(
            'error.forbidden: url must point to the official plugin store',
          );
        }

        // token+callback אופציונליים — מאפשרים לתוסף חנות לעקוב אחרי תוצאת
        // ההתקנה דרך ה-API של האתר. callback חייב להיות באותו origin של
        // כתובת ההורדה; אחרת מתעלמים מהדיווח וההתקנה ממשיכה כרגיל.
        PluginInstallReportContext? reportContext;
        final token = (args['token'] as String?)?.trim();
        final downloadUri = Uri.tryParse(url);
        if (token != null && token.isNotEmpty && downloadUri != null) {
          final callbackUrl = PluginInstallReportService.validateCallback(
            args['callback'] as String?,
            downloadUri,
          );
          if (callbackUrl != null) {
            reportContext = PluginInstallReportContext(
              token: token,
              callbackUrl: callbackUrl,
            );
          }
        }

        cb(url, reportContext: reportContext);
        return true;
      case 'listInstalled':
        final installed = await _pluginRepo.getAllPlugins();
        return installed
            .map(
              (p) => {
                'pluginId': p.pluginId,
                'name': p.name,
                'version': p.version,
              },
            )
            .toList();
      case 'openSelf':
        PluginPageLauncher.instance.open(
          plugin.pluginId,
          topic: 'plugin.page_opened',
          payload: {'param': args['param']},
        );
        return true;
      case 'openOther':
        final targetId = (args['pluginId'] as String?)?.trim();
        if (targetId == null || targetId.isEmpty) {
          throw Exception('error.invalid_params: pluginId required');
        }
        // רק תוסף מותקן — כלים מובנים אינם נפתחים בערוץ הזה, כדי שההרשאה
        // תישאר במשמעות שהוצגה למשתמש. שאר סיבות אי-הזמינות (מושבת, מוסתר,
        // מנותק) נשארות ל-openToolTabById, שמציג הודעה מדויקת אחת.
        final installed = await _pluginRepo.getAllPlugins();
        if (!installed.any((p) => p.pluginId == targetId)) {
          throw Exception('error.not_found: plugin not installed: $targetId');
        }
        PluginPageLauncher.instance.open(
          targetId,
          topic: 'plugin.page_opened',
          payload: {'param': args['param'], 'openedBy': plugin.pluginId},
        );
        return true;
      case 'backgroundDone':
        return _dependencies.onBackgroundInstanceDone?.call() ?? false;
      default:
        throw Exception(
          'error.unknown_method: Unknown action in plugin: $action',
        );
    }
  }

  // ----------------------------------------------------------------
  // network.*
  // ----------------------------------------------------------------
  /// מחלץ את `url` מהארגומנטים ומחזיר אותו רק אם התוסף רשאי לפנות אליו,
  /// אחרת זורק את השגיאה המתאימה לשלב שנכשל.
  Future<Uri> _requireAllowedNetworkUri(Map<String, dynamic> args) async {
    final url = args['url'] as String?;
    if (url == null) throw Exception('error.invalid_params: url required');
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('error.invalid_params: invalid URL');

    final decision = await evaluatePluginNetworkAccess(
      uri: uri,
      pluginId: plugin.pluginId,
      manifest: plugin.manifest,
      registry: _pluginRepo,
    );
    switch (decision) {
      case PluginNetworkDecision.allowed:
        return uri;
      case PluginNetworkDecision.notDeclared:
        throw Exception(
          'error.permission_denied: '
          'התוסף אינו מצהיר על גישה לאינטרנט במניפסט.',
        );
      case PluginNetworkDecision.permissionMissing:
        final what = requiredNetworkPermissionFor(uri) == 'network.localhost'
            ? 'גישה לשירותים מקומיים (localhost)'
            : 'גישה לאינטרנט';
        throw Exception(
          'error.permission_denied: '
          'לתוסף אין הרשאת $what. '
          'ניתן להפעיל אותה בהגדרות, תחת ניהול תוספים.',
        );
      case PluginNetworkDecision.notAllowlisted:
        throw Exception(
          'error.forbidden: הכתובת אינה ברשימת ההיתר לגישת רשת של תוספים',
        );
    }
  }

  Future<_PluginNetworkRequest> _prepareNetworkRequest(
    Map<String, dynamic> args,
  ) async {
    final uri = await _requireAllowedNetworkUri(args);

    final method = (args['method'] as String? ?? 'GET').toUpperCase();
    if (!RegExp(r'^[A-Z]+$').hasMatch(method)) {
      throw Exception('error.invalid_params: invalid method');
    }
    final rawTimeoutMs = args['timeoutMs'];
    if (rawTimeoutMs != null &&
        (rawTimeoutMs is! int ||
            rawTimeoutMs <= 0 ||
            rawTimeoutMs >
                PluginNetworkFetchService.maxTimeout.inMilliseconds)) {
      throw Exception(
        'error.invalid_params: timeoutMs must be a positive integer '
        'up to ${PluginNetworkFetchService.maxTimeout.inMilliseconds}',
      );
    }
    final rawHeaders = args['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (key is String && value != null) {
          headers[key] = value.toString();
        }
      });
    }

    return _PluginNetworkRequest(
      uri: uri,
      method: method,
      headers: headers.isEmpty ? null : headers,
      body: args['body'] as String?,
      timeout: rawTimeoutMs == null
          ? PluginNetworkFetchService.defaultTimeout
          : Duration(milliseconds: rawTimeoutMs),
    );
  }

  Future<dynamic> _handleNetwork(
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    switch (action) {
      case 'fetch':
        // TODO(0.9.98): להסיר את network.fetch לאחר מעבר התוספים ל-fetchStream.
        final request = await _prepareNetworkRequest(args);
        final result = await _fetchService.fetch(
          request.uri,
          method: request.method,
          headers: request.headers,
          body: request.body,
          timeout: request.timeout,
        );
        return {'status': result.status, 'ok': result.ok, 'body': result.body};

      case 'fetchStream':
        if (args[_cancelStreamIdKey] case final String streamId) {
          return _cancelPluginNetworkFetch(streamId);
        }
        return _runPluginNetworkFetchStream(args, eventSink: eventSink);

      case 'download':
        // הורדה רגילה של קובץ מ-URL מותר אל תיקיית ההורדות של המערכת.
        // הכל מתבצע בצד Flutter — ה-WebView (origin file://) אינו יכול
        // לכתוב לדיסק. נדרשת הרשאת רשת לפי היעד (אינטרנט או localhost).
        final uri = await _requireAllowedNetworkUri(args);

        // destPath אופציונלי: הורדה אל נתיב קובץ מלא שבחר התוסף, במקום
        // תיקיית ההורדות. הנתיב חייב להיות בתוך תיקייה שהמשתמש אישר דרך
        // ui.pickFolder — אותו גבול אבטחה של פעולות ה-fs.
        final destPath = args['destPath'] as String?;
        final resume = args['resume'] == true;
        if (destPath != null && destPath.isNotEmpty) {
          if (!_isPathInGrantedFolder(destPath)) {
            throw Exception(
              'error.forbidden: destPath outside a user-selected folder',
            );
          }
          final result = await _downloadService.downloadToPath(
            uri,
            destPath,
            isAllowed: (candidate) => PluginNetworkAccessResolver.instance
                .isUriAllowedForPlugin(candidate, plugin.manifest),
            isRedirectAllowed: isGithubReleaseRedirectAllowed,
            resume: resume,
          );
          return {'path': result.path, 'filename': result.filename};
        }

        final filename = args['filename'] as String?;
        final result = await _downloadService.downloadToDownloads(
          uri,
          filename: filename,
          isAllowed: (candidate) => PluginNetworkAccessResolver.instance
              .isUriAllowedForPlugin(candidate, plugin.manifest),
          isRedirectAllowed: isGithubReleaseRedirectAllowed,
        );
        return {'path': result.path, 'filename': result.filename};

      default:
        throw Exception(
          'error.unknown_method: Unknown action in network: $action',
        );
    }
  }

  Future<Map<String, dynamic>> _runPluginNetworkFetchStream(
    Map<String, dynamic> args, {
    required PluginRpcEventSink? eventSink,
  }) async {
    final streamId = args[_streamIdKey];
    if (streamId is! String || !_streamIdPattern.hasMatch(streamId)) {
      throw Exception('error.invalid_params: invalid internal stream id');
    }
    if (eventSink == null) {
      throw Exception('error.internal: network stream transport unavailable');
    }
    if (_pendingNetworkFetchCancellations.remove(streamId)) {
      return {'completed': false, 'cancelled': true};
    }
    if (_activeNetworkFetchStreams.containsKey(streamId)) {
      throw Exception('error.invalid_params: duplicate network stream id');
    }
    if (_activeNetworkFetchStreams.length >=
        _maxConcurrentNetworkFetchStreams) {
      throw Exception(
        'error.rate_limited: too many active network fetch streams',
      );
    }

    final publicArgs = Map<String, dynamic>.of(args)..remove(_streamIdKey);
    final request = await _prepareNetworkRequest(publicArgs);
    if (_pendingNetworkFetchCancellations.remove(streamId)) {
      return {'completed': false, 'cancelled': true};
    }

    final abort = Completer<void>();
    final cancellation = Completer<void>();
    StreamIterator<String>? iterator;
    var cancelled = false;
    var expired = false;
    Future<void> cancel() async {
      cancelled = true;
      if (!abort.isCompleted) abort.complete();
      if (!cancellation.isCompleted) cancellation.complete();
      await iterator?.cancel();
    }

    _activeNetworkFetchStreams[streamId] = cancel;
    final deadline = Timer(request.timeout, () {
      expired = true;
      unawaited(cancel());
    });
    var sequence = 0;
    try {
      final response = await Future.any<PluginNetworkFetchStreamResponse?>([
        _fetchService
            .fetchStream(
              request.uri,
              method: request.method,
              headers: request.headers,
              body: request.body,
              abortTrigger: abort.future,
            )
            .then<PluginNetworkFetchStreamResponse?>((value) => value),
        cancellation.future.then<PluginNetworkFetchStreamResponse?>(
          (_) => null,
        ),
      ]);
      if (response == null) {
        if (expired) throw TimeoutException('Network stream timed out');
        return {'completed': false, 'cancelled': true};
      }

      await eventSink(_networkFetchStreamEvent, {
        'streamId': streamId,
        'chunk': {
          'sequence': sequence++,
          'type': 'response',
          'status': response.status,
          'ok': response.ok,
          'headers': response.headers,
        },
      });

      iterator = StreamIterator<String>(response.body);
      while (!cancelled && await iterator.moveNext()) {
        final body = iterator.current;
        if (body.isEmpty) continue;
        for (final fragment in _splitNetworkFetchChunk(body)) {
          if (cancelled) break;
          await eventSink(_networkFetchStreamEvent, {
            'streamId': streamId,
            'chunk': {
              'sequence': sequence++,
              'type': 'data',
              'body': fragment,
            },
          });
        }
      }
      if (expired) throw TimeoutException('Network stream timed out');
      return {
        'completed': !cancelled,
        'cancelled': cancelled,
        'chunks': sequence,
      };
    } on http.RequestAbortedException {
      if (expired) throw TimeoutException('Network stream timed out');
      if (cancelled) return {'completed': false, 'cancelled': true};
      rethrow;
    } finally {
      deadline.cancel();
      _activeNetworkFetchStreams.remove(streamId);
      await iterator?.cancel();
    }
  }

  Map<String, dynamic> _cancelPluginNetworkFetch(String streamId) {
    if (!_streamIdPattern.hasMatch(streamId)) {
      throw Exception('error.invalid_params: invalid internal stream id');
    }
    final cancel = _activeNetworkFetchStreams[streamId];
    if (cancel == null) {
      if (_pendingNetworkFetchCancellations.length < 16) {
        _pendingNetworkFetchCancellations.add(streamId);
      }
      return {'cancelled': false};
    }
    unawaited(cancel());
    return {'cancelled': true};
  }

  Iterable<String> _splitNetworkFetchChunk(String value) sync* {
    var start = 0;
    while (start < value.length) {
      var end = math.min(
        start + _maxNetworkFetchChunkCodeUnits,
        value.length,
      );
      if (end < value.length &&
          _isHighSurrogate(value.codeUnitAt(end - 1)) &&
          _isLowSurrogate(value.codeUnitAt(end))) {
        end--;
      }
      yield value.substring(start, end);
      start = end;
    }
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}
