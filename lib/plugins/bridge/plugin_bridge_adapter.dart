import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:otzaria/theme/app_fonts.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kosher_dart/kosher_dart.dart';
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
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/plugins/database/plugin_database_service.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_service.dart';
import 'package:otzaria/plugins/services/plugin_path_safety.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/plugin_section_text_map_service.dart';
import 'package:otzaria/plugins/services/plugin_text_occurrence_service.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

// ===================================================================
// Spec-compliant allowlist for settings.get/getMany
// keys a plugin CAN read (from plugin_system_plan.md#L954)
// ===================================================================
const _settingsAllowlist = {
  SettingsRepository.keyDarkMode,
  SettingsRepository.keyFollowSystemTheme,
  SettingsRepository.keySwatchColor,
  SettingsRepository.keyDarkSwatchColor,
  SettingsRepository.keyFontSize,
  SettingsRepository.keyFontFamily,
  SettingsRepository.keyCommentatorsFontFamily,
  SettingsRepository.keyCommentatorsFontSize,
  SettingsRepository.keyLineHeight,
  SettingsRepository.keySelectedCity,
  SettingsRepository.keyCalendarType,
  SettingsRepository.keyShowTeamim,
  SettingsRepository.keyDefaultNikud,
  SettingsRepository.keyRemoveNikudFromTanach,
  SettingsRepository.keyReplaceHolyNames,
  SettingsRepository.keyLibraryViewMode,
  SettingsRepository.keyCopyWithHeaders,
  SettingsRepository.keyCopyHeaderFormat,
};

// keys a plugin CANNOT read even if attempted
const _settingsBlocklist = {
  SettingsRepository.keyProtectedModePasswordHash,
  SettingsRepository.keyGoogleCalendarClientSecret,
  SettingsRepository.keyGoogleCalendarCredentialsJson,
  SettingsRepository.keyDbEffectivePath,
  SettingsRepository.keyLibraryPath,
  SettingsRepository.keyIndexPath,
  SettingsRepository.keyBackupPath,
  SettingsRepository.keyHebrewBooksPath,
  SettingsRepository.keyErrorReportSenderEmail,
};

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
  final void Function(String downloadUrl)? requestPluginInstall;

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
    this.resolveReference,
    this.resolveRefToLine,
    this.altStructuresProvider,
    this.altTocEntriesProvider,
  });
}

// ===================================================================
// Bridge Adapter - strict 1:1 with plugin_system_plan.md
// ===================================================================
class PluginBridgeAdapter {
  final InstalledPlugin plugin;
  final PluginRegistryRepository _pluginRepo;
  final PluginBridgeDependencies _dependencies;
  final NotificationService _notificationService;
  final PluginDatabaseService _databaseService;
  final PluginHighlightRegistry _highlightRegistry;

  PluginBridgeAdapter(
    this.plugin, {
    required this._dependencies,
    PluginRegistryRepository? pluginRepository,
    NotificationService? notificationService,
    PluginDatabaseService? databaseService,
    this._networkFetchService,
    this._fileDownloadService,
    PluginFsService? fsService,
    PluginShortcutService? shortcutService,
    PluginFileServer? fileServer,
    PluginHighlightRegistry? highlightRegistry,
  }) : _pluginRepo = pluginRepository ?? PluginRegistryRepository(),
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

  // שירות בקשות HTTP (network.fetch) — מופע יחיד לכל adapter; ניתן להזרקה
  // לבדיקות, נוצר עם השימוש הראשון אם לא הוזרק, ומשוחרר ב-dispose.
  PluginNetworkFetchService? _networkFetchService;
  PluginNetworkFetchService get _fetchService =>
      _networkFetchService ??= PluginNetworkFetchService();

  // bookId → טקסט מלא של הספר (מטמון LRU קצר, per adapter instance) עבור
  // getBookContent. ראה _loadBookRawText.
  final Map<PluginBookIdentityKey, String> _bookContentCache = {};
  static const int _bookContentCacheMaxEntries = 4;

  void dispose() {
    _networkFetchService?.dispose();
    _fileDownloadService?.dispose();
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
    Map<String, dynamic> args,
  ) async {
    switch (domain) {
      case 'app':
        return await _handleApp(action, args);
      case 'library':
        return await _handleLibrary(action, args);
      case 'search':
        return await _handleSearch(action, args);
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
      case 'notifications':
        return await _handleNotifications(action, args);
      case 'database':
        return _handleDatabase(action, args);
      case 'network':
        return await _handleNetwork(action, args);
      case 'fs':
        return await _handleFs(action, args);
      case 'shortcut':
        return await _handleShortcut(action, args);
      case 'plugin':
        return await _handlePlugin(action, args);
      default:
        throw Exception("Unknown domain: $domain");
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
        return {'locale': 'he-IL', 'textDirection': 'rtl'};
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
      case 'getGrantedPermissions':
        return {'permissions': await _getGrantedPermissions()};
      default:
        throw Exception("Unknown action in app: $action");
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
                ...PluginBookIdentity.toJson(b as Book),
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
              bookId == null) {
            throw Exception('id or bookId required');
          }
          final book = _findPluginBook(library, args);
          if (book == null) return null;
          return {
            ...PluginBookIdentity.toJson(book),
            'title': book.title,
            'topics': book.topics,
          };
        }
      case 'listRecentBooks':
        final historyState = _dependencies.historyBloc.state;
        if (historyState is! HistoryLoaded) return [];
        return historyState.history
            .where((b) => !b.isSearch)
            .take(20)
            .map(
              (b) => {
                ...PluginBookIdentity.toJson(b.book),
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
      default:
        throw Exception('Unknown action in library: $action');
    }
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
      ...PluginBookIdentity.toJson(book),
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
    final id = PluginBookIdentity.parseId(args['id']);
    final bookId = (args['bookId'] ?? args['title']) as String?;
    final type = args['type'] as String?;
    final source = args['source'] as String?;
    if (id == null && bookId == null) return null;
    final matches = library.getAllBooks().where(
      (book) => PluginBookIdentity.matches(
        book,
        id: id,
        bookId: bookId,
        type: type,
        source: source,
      ),
    );
    final found = matches.toList();
    if (found.isEmpty) return null;
    if ((id != null || type != null || source != null) && found.length != 1) {
      return null;
    }
    return found.first;
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
    Map<String, dynamic> args,
  ) async {
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
      default:
        throw Exception("Unknown action in search: $action");
    }
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
        // spec: openBook({ id?, bookId?, type?, index?, searchQuery?, navigateToPositionIfReused? })
        // also accepts legacy 'title' for back-compat; all supplied identity fields must match.
        {
          final bookId = (args['bookId'] ?? args['title']) as String?;
          final index = (args['index'] as num?)?.toInt() ?? 0;
          final searchQuery = args['searchQuery'] as String? ?? '';
          final navigateToPositionIfReused =
              args['navigateToPositionIfReused'] as bool? ?? false;
          if (PluginBookIdentity.parseId(args['id']) == null &&
              bookId == null) {
            throw Exception('id or bookId required');
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
          );
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
              bookId == null) {
            throw Exception('id or bookId required');
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
        final tabs = tabsState.tabs;
        final currentTab = tabsState.currentTab;
        // Use the same resolver as getCurrentRef for consistent currentRef values
        final snapshots = await Future.wait(tabs.map(resolveReaderLocation));
        final openTabs = List.generate(tabs.length, (i) {
          final t = tabs[i];
          // SearchingTab ו-CombinedTab אינם ספרים — id/type = null
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
            'book': t.title,
            'index': t is TextBookTab
                ? t.index
                : (t is PdfBookTab ? t.pageNumber : 0),
            'currentRef': snapshots[i]?.currentRef,
          };
        });
        if (currentTab == null) {
          return {
            'currentBook': null,
            'currentId': null,
            'currentType': null,
            'currentSource': null,
            'currentIndex': 0,
            'currentRef': null,
            'openTabs': openTabs,
          };
        }
        final currentTabIndex = tabs.indexOf(currentTab);
        final currentSnapshot = currentTabIndex >= 0
            ? snapshots[currentTabIndex]
            : null;
        final currentTabBook = currentTab is TextBookTab
            ? currentTab.book
            : (currentTab is PdfBookTab ? currentTab.book : null);
        return {
          'currentBook': currentTab.title,
          'currentBookId': currentTab.title,
          'currentId': currentTabBook?.id,
          'currentType': currentTabBook != null
              ? PluginBookIdentity.typeOf(currentTabBook)
              : null,
          'currentSource': currentTabBook != null
              ? PluginBookIdentity.sourceOf(currentTabBook)
              : null,
          'currentIndex': currentTab is TextBookTab
              ? currentTab.index
              : (currentTab is PdfBookTab ? currentTab.pageNumber : 0),
          'currentRef': currentSnapshot?.currentRef,
          'openTabs': openTabs,
        };
      case 'getCurrentRef':
        final snapshot = await resolveReaderLocation(
          _dependencies.tabsBloc.state.currentTab,
        );
        if (snapshot == null) {
          return {
            'currentBook': null,
            'currentBookId': null,
            'currentId': null,
            'currentType': null,
            'currentSource': null,
            'currentIndex': 0,
            'currentRef': null,
          };
        }
        return snapshot.toJson();
      case 'getSelection':
        final currentTab = _dependencies.tabsBloc.state.currentTab;
        final snapshot = await resolveReaderLocation(currentTab);
        return _buildCurrentSelection(currentTab, snapshot?.currentRef);
      case 'findTextOccurrences':
        return _findTextOccurrences(args);
      case 'getSectionTextMap':
        return _getSectionTextMap(args);
      case 'addContextMenuItem':
        ContextMenuRegistry.instance.registerPayload(plugin.pluginId, args);
        return true;
      case 'removeContextMenuItem':
        final id = args['id'] as String?;
        if (id == null) throw Exception('error.invalid_params: id required');
        ContextMenuRegistry.instance.remove(plugin.pluginId, id);
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
        );
        return true;
      case 'setHighlight':
        if (args['range'] is Map && args['style'] is Map) {
          return _highlightRegistry
              .setHighlight(ownerPluginId: plugin.pluginId, payload: args)
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
          bookId: bookId,
          sectionIndex: index,
          color: color as String?,
          label: label as String?,
        );
        return true;
      case 'updateHighlight':
        return _highlightRegistry
            .updateHighlight(ownerPluginId: plugin.pluginId, payload: args)
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
        final book = allBooks.cast<dynamic>().firstWhere(
          (item) => item?.title == highlight.bookId,
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
          bookId: legacyBookId,
          sectionIndex: legacyIndex,
          includeStale: true,
        );
        for (final match in matches) {
          _highlightRegistry.clearHighlight(
            ownerPluginId: plugin.pluginId,
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
          bookId: bookId as String?,
          sectionIndex: sectionIndex as int?,
        );
        return true;
      default:
        throw Exception('Unknown action in reader: $action');
    }
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
    final section = await _loadPluginTextSection(bookId, sectionIndex);
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
  _loadPluginTextSection(String bookId, int sectionIndex) async {
    if (sectionIndex < 0) {
      throw const PluginTextOccurrenceException(
        'error.invalid_params',
        'sectionIndex must be non-negative',
      );
    }
    final tabs = _dependencies.tabsBloc.state.tabs;
    for (final tab in tabs) {
      if (tab is! TextBookTab || tab.title != bookId) continue;
      final state = tab.bloc.state;
      if (state is! TextBookLoaded || sectionIndex >= state.content.length) {
        continue;
      }
      final snapshot =
          tab == _dependencies.tabsBloc.state.currentTab &&
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
      if (candidate.title == bookId) {
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
    final section = await _loadPluginTextSection(bookId, sectionIndex);
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
          throw Exception("target required");
        }
        Screen? screen;
        switch (target) {
          case 'library':
            screen = Screen.library;
            break;
          case 'reading':
            screen = Screen.reading;
            break;
          case 'more':
            screen = Screen.more;
            break;
          case 'settings':
            screen = Screen.settings;
            break;
          default:
            throw Exception(
              "Invalid navigation target: $target. Valid: library, reading, more, settings",
            );
        }
        _dependencies.navigationBloc.add(NavigateToScreen(screen));
        return true;
      default:
        throw Exception("Unknown action in navigation: $action");
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
        if (bookId == null) throw Exception("bookId required");
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
          throw Exception("Missing arguments");
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
          throw Exception("Missing arguments");
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
          throw Exception("Missing arguments");
        }
        await repo.deleteNote(bookId: bookId, noteId: noteId);
        return true;
      default:
        throw Exception("Unknown action in notes: $action");
    }
  }

  // ----------------------------------------------------------------
  // ui.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleUi(String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'showMessage':
        UiSnack.show(args['message'] as String? ?? '');
        return true;
      case 'showSuccess':
        UiSnack.showSuccess(args['message'] as String? ?? '');
        return true;
      case 'showError':
        UiSnack.showError(args['message'] as String? ?? '');
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
        _grantedFolders.add(p.normalize(p.absolute(path)));
        return {'path': path};
      default:
        throw Exception("Unknown action in ui: $action");
    }
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
      case 'pickUserFile':
        return await _pickUserFile(args);
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
        throw Exception('Unknown action in fs: $action');
    }
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
    await _saveUserFileGrant(registration.token, canonical);
    return {
      'cancelled': false,
      'token': registration.token,
      'url': registration.url,
      'name': p.basename(canonical),
      'size': await File(canonical).length(),
    };
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
    return file.readAsString();
  }

  /// פותר את הנתיב הקנוני של קובץ מאושר לפי [token], או זורק `error.not_found`
  /// אם ה-token לא מוכר או שהקובץ נמחק (ומנקה אז את ה-grant).
  Future<String> _resolveGrantedFilePath(String token) async {
    final stored = await _loadUserFileGrant(token);
    if (stored == null) {
      throw Exception('error.not_found: unknown file token');
    }
    final canonical = canonicalizeNearestExisting(stored);
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

  Future<void> _saveUserFileGrant(String token, String path) async {
    final grants = await _readUserFileGrants();
    grants[token] = path;
    await _pluginRepo.setKV(
      plugin.pluginId,
      '_internal',
      _userFileGrantsKey,
      jsonEncode(grants),
    );
  }

  Future<String?> _loadUserFileGrant(String token) async {
    final value = (await _readUserFileGrants())[token];
    return value is String ? value : null;
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
        throw Exception('Unknown action in shortcut: $action');
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
        if (key == null) throw Exception("key required");
        final value = await _pluginRepo.getKV(plugin.pluginId, 'default', key);
        return value != null ? jsonDecode(value) : null;
      case 'set':
        final key = args['key'] as String?;
        final value = args['value'];
        if (key == null || value == null) {
          throw Exception("key and value required");
        }
        await _pluginRepo.setKV(
          plugin.pluginId,
          'default',
          key,
          jsonEncode(value),
        );
        return true;
      case 'remove':
        final key = args['key'] as String?;
        if (key == null) throw Exception("key required");
        await _pluginRepo.removeKV(plugin.pluginId, 'default', key);
        return true;
      case 'list':
        return _pluginRepo.listKVKeys(plugin.pluginId, 'default');
      default:
        throw Exception("Unknown action in storage: $action");
    }
  }

  // ----------------------------------------------------------------
  // settings.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleSettings(
    String action,
    Map<String, dynamic> args,
  ) async {
    bool isAllowed(String key) =>
        _settingsAllowlist.contains(key) && !_settingsBlocklist.contains(key);

    switch (action) {
      case 'get':
        final key = args['key'] as String?;
        if (key == null || !isAllowed(key)) return null;
        return Settings.getValue(key);
      case 'getMany':
        final keys = (args['keys'] as List?)?.cast<String>() ?? [];
        final Map<String, dynamic> res = {};
        for (final k in keys) {
          if (isAllowed(k)) res[k] = Settings.getValue(k);
        }
        return res;
      default:
        throw Exception("Unknown action in settings: $action");
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

    switch (action) {
      case 'getSelectedDate':
        return calendarState.selectedGregorianDate.toIso8601String();
      case 'getDailyTimes':
        return calendarState.dailyTimes;
      case 'getHalachicTimes':
        // dailyTimes contains all halachic times (shekia, tzet haochavim, etc.)
        return calendarState.dailyTimes;
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
        throw Exception("Unknown action in calendar: $action");
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
          throw Exception('type, key, payload required');
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
            currentWorkspaceId: _currentWorkspaceId(),
          );
        }
        return true;
      case 'remove':
        final type = args['type'] as String?;
        final scope = args['scope'] as String? ?? 'global';
        final key = args['key'] as String?;
        if (type == null || key == null) {
          throw Exception('type and key required');
        }
        await _pluginRepo.unpublishRecord(plugin.pluginId, type, scope, key);
        // רענון חי של לוח השנה
        if (type == 'calendar.event') {
          _dependencies.calendarCubit.refreshPluginEvents(
            currentBookId: _currentBookId(),
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
        throw Exception("Unknown action in publishedData: $action");
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
          throw Exception('to, subject, body required');
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
          throw Exception('Failed to open email client: $e');
        }

      default:
        throw Exception('Unknown action in feedback: $action');
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
                ...PluginBookIdentity.toJson(b.book),
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
          if (id == null && bookId == null) {
            throw Exception('id or bookId required');
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
        throw Exception('Unknown action in history: $action');
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
          throw Exception('message required');
        }

        switch (type) {
          case 'success':
            UiSnack.showSuccess(message);
            break;
          case 'error':
            UiSnack.showError(message);
            break;
          case 'info':
          default:
            UiSnack.show(message);
            break;
        }
        return true;

      case 'sendSystem':
        // התראה למערכת ההפעלה
        final title = args['title'] as String?;
        final body = args['body'] as String?;
        final id = args['id'] as int?;

        if (title == null || body == null) {
          throw Exception('title and body required');
        }

        // בדיקה אם השירות מאותחל
        if (!_notificationService.isInitialized) {
          throw Exception('Notification service not initialized');
        }

        // בדיקה אם יש הרשאות
        if (!_notificationService.hasPermissions) {
          throw Exception('Notification permissions not granted');
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
          throw Exception('title, body, and scheduledTime required');
        }

        final dateTime = DateTime.tryParse(scheduledTime);
        if (dateTime == null) {
          throw Exception('Invalid scheduledTime format. Use ISO 8601.');
        }

        if (dateTime.isBefore(DateTime.now())) {
          throw Exception('scheduledTime must be in the future');
        }

        if (!_notificationService.isInitialized) {
          throw Exception('Notification service not initialized');
        }

        if (!_notificationService.hasPermissions) {
          throw Exception('Notification permissions not granted');
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
        if (id == null) throw Exception('id required');

        if (!_notificationService.isInitialized) {
          throw Exception('Notification service not initialized');
        }

        await _notificationService.cancelNotification(id);
        await _untrackNotificationId(id);
        return true;

      case 'cancelAll':
        // ביטול כל ההתראות של התוסף
        if (!_notificationService.isInitialized) {
          throw Exception('Notification service not initialized');
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
          throw Exception('Notification service not initialized');
        }

        final granted = await _notificationService.requestPermissions();
        return {'granted': granted};

      default:
        throw Exception('Unknown action in notifications: $action');
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
    final permissions = await _pluginRepo.getPluginPermissions(plugin.pluginId);
    final grantedPermissions =
        permissions
            .where((permission) => permission.granted)
            .map((permission) => permission.permission)
            .toList()
          ..sort();
    return grantedPermissions;
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
    return _dependencies.tabsBloc.state.currentTab?.title;
  }

  String? _currentWorkspaceId() {
    return _dependencies.workspaceBloc.state.activeWorkspaceId;
  }

  // ----------------------------------------------------------------
  // database.*
  // ----------------------------------------------------------------
  dynamic _handleDatabase(String action, Map<String, dynamic> args) {
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
        return _databaseService.query(plugin, args);

      case 'batchQuery':
        final queries = (args['queries'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>();
        if (queries == null) {
          throw const PluginDatabaseException(
            'database.invalid_spec',
            '"queries" list is required',
          );
        }
        final results = _databaseService.batchQuery(plugin, queries);
        return {'results': results};

      default:
        throw Exception('Unknown database action: $action');
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
        cb(url);
        return true;
      case 'listInstalled':
        final installed = await _pluginRepo.getAllPlugins();
        return installed
            .map((p) => {'name': p.name, 'version': p.version})
            .toList();
      case 'openSelf':
        PluginPageLauncher.instance.open(
          plugin.pluginId,
          topic: 'plugin.page_opened',
          payload: {'param': args['param']},
        );
        return true;
      default:
        throw Exception('Unknown action in plugin: $action');
    }
  }

  // ----------------------------------------------------------------
  // network.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleNetwork(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'fetch':
        if (!plugin.manifest.networkEnabled) {
          throw Exception(
            'error.permission_denied: '
            'התוסף אינו מצהיר על גישה לאינטרנט במניפסט.',
          );
        }

        final url = args['url'] as String?;
        if (url == null) throw Exception('error.invalid_params: url required');

        final uri = Uri.tryParse(url);
        if (uri == null) throw Exception('error.invalid_params: invalid URL');

        final requiredPermission = requiredNetworkPermissionFor(uri);
        final granted = await _pluginRepo.getPermission(
          plugin.pluginId,
          requiredPermission,
        );
        if (granted != true) {
          final what = requiredPermission == 'network.localhost'
              ? 'גישה לשירותים מקומיים (localhost)'
              : 'גישה לאינטרנט';
          throw Exception(
            'error.permission_denied: '
            'לתוסף אין הרשאת $what. '
            'ניתן להפעיל אותה בהגדרות, תחת ניהול תוספים.',
          );
        }

        final allowed = await PluginNetworkAccessResolver.instance
            .isUriAllowedForPlugin(uri, plugin.manifest);
        if (!allowed) {
          throw Exception(
            'error.forbidden: הכתובת אינה ברשימת ההיתר לגישת רשת של תוספים',
          );
        }

        // method/headers/body אופציונליים. הניתוב דרך הגשר נחוץ לתוספים
        // שקוראים ל-APIs חיצוניים (כמו דיקטה) ב-POST: fetch ישיר מה-WebView
        // (origin file://) נחסם ב-CORS, ואילו לקוח ה-HTTP של Flutter אינו
        // כפוף ל-CORS.
        final method = (args['method'] as String? ?? 'GET').toUpperCase();
        if (!RegExp(r'^[A-Z]+$').hasMatch(method)) {
          throw Exception('error.invalid_params: invalid method');
        }
        final requestBody = args['body'] as String?;
        final rawHeaders = args['headers'];
        final headers = <String, String>{};
        if (rawHeaders is Map) {
          rawHeaders.forEach((key, value) {
            if (key is String && value != null) {
              headers[key] = value.toString();
            }
          });
        }

        final result = await _fetchService.fetch(
          uri,
          method: method,
          headers: headers.isEmpty ? null : headers,
          body: requestBody,
        );
        return {'status': result.status, 'ok': result.ok, 'body': result.body};

      case 'download':
        // הורדה רגילה של קובץ מ-URL מותר אל תיקיית ההורדות של המערכת.
        // הכל מתבצע בצד Flutter — ה-WebView (origin file://) אינו יכול
        // לכתוב לדיסק. נדרשת הרשאת רשת לפי היעד (אינטרנט או localhost).
        if (!plugin.manifest.networkEnabled) {
          throw Exception(
            'error.permission_denied: '
            'התוסף אינו מצהיר על גישה לאינטרנט במניפסט.',
          );
        }

        final url = args['url'] as String?;
        if (url == null) throw Exception('error.invalid_params: url required');

        final uri = Uri.tryParse(url);
        if (uri == null) throw Exception('error.invalid_params: invalid URL');

        final requiredPermission = requiredNetworkPermissionFor(uri);
        final granted = await _pluginRepo.getPermission(
          plugin.pluginId,
          requiredPermission,
        );
        if (granted != true) {
          final what = requiredPermission == 'network.localhost'
              ? 'גישה לשירותים מקומיים (localhost)'
              : 'גישה לאינטרנט';
          throw Exception(
            'error.permission_denied: '
            'לתוסף אין הרשאת $what. '
            'ניתן להפעיל אותה בהגדרות, תחת ניהול תוספים.',
          );
        }

        final allowed = await PluginNetworkAccessResolver.instance
            .isUriAllowedForPlugin(uri, plugin.manifest);
        if (!allowed) {
          throw Exception(
            'error.forbidden: הכתובת אינה ברשימת ההיתר לגישת רשת של תוספים',
          );
        }

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
        throw Exception('Unknown action in network: $action');
    }
  }
}
