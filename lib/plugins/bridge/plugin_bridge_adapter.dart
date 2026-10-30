import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
// dart:io מגדיר Link משלו (קישור בקובץ־מערכת) שמתנגש ב-Link של הקישורים.
import 'dart:io' hide Link;
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria/widgets/dialogs/input_dialog.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/update/app_release_version.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/services/installed_fonts.dart';
import 'package:otzaria/plugins/services/plugin_fonts.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/core/connectivity_status_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/book_common/utils/commentator_group_builder.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/plugins/bridge/plugin_search_api.dart';
import 'package:otzaria/plugins/bridge/plugin_save_target.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchStreamUpdate;
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/plugins/services/plugin_in_book_search_service.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/models/plugin_library_book_provider.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_reader_actions.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/book_common/view/book_source_dialog.dart'
    show getSourceDisplayInfo, libraryDisplayPath;
import 'package:otzaria/tools/biographies/models/biographies_bundle.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';
import 'package:otzaria/tools/biographies/repository/biographies_repository.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/selection/plugin_selection_payload.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/plugins/database/plugin_database_service.dart';
import 'package:otzaria/plugins/utils/reader_location_resolver.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/plugins/view/plugin_new_tab_page_choice.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/services/plugin_print_service.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/models/plugin_network_permission_mode.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';
import 'package:otzaria/plugins/services/plugin_store_link_parser.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/plugins/services/plugin_book_correction_service.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_divine_names_filter.dart';
import 'package:otzaria/plugins/services/plugin_biography_compatibility.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_remote_file_cache.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_settings_access_policy.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_registry.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_service.dart';
import 'package:otzaria/plugins/services/plugin_path_safety.dart';
import 'package:otzaria/plugins/services/plugin_user_folder.dart';
import 'package:otzaria/plugins/services/plugin_user_folder_grants.dart';
import 'package:otzaria/utils/file/file_book_path_resolver.dart';
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
import 'package:otzaria/utils/calendar_days.dart';

/// גופן הממשק שאוצריא מוסרת לתוספים: sans מובנה שנשאר חד ב-11-12px.
/// גופן הקריאה (`fontFamily`) אינו תחליף לו — הוא מצויר ל-25px,
/// והתגיות שלו נמרחות בכפתור או בתפריט.
const String kPluginUiFont = 'Rubik';

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
      AppFonts.defaultFont;
  final commentatorsFontFamily =
      Settings.getValue<String>(SettingsRepository.keyCommentatorsFontFamily) ??
      AppFonts.defaultCommentatorsFont;
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
      'uiFontFamily': kPluginUiFont,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'commentatorsFontFamily': commentatorsFontFamily,
      'commentatorsFontSize': commentatorsFontSize,
    },
  };
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

/// מצב החלון שנלכד בתחילת RPC; אינו משתנה כשבקשה אסינכרונית ממתינה.
typedef PluginBridgeWindowDependencies = ({
  BuildContext? context,
  int? viewId,
  AppWindowKeys? windowKeys,
  HistoryBloc historyBloc,
  TabsBloc tabsBloc,
  NavigationBloc navigationBloc,
  WorkspaceBloc workspaceBloc,
  BookOpenCoordinator bookOpenCoordinator,
  CustomFoldersBloc? customFoldersBloc,
  Future<void> Function(int requestId)? waitForLibraryRefresh,
});

class PluginBridgeDependencies {
  final BuildContext? windowContext;
  final HistoryBloc historyBloc;
  final TabsBloc tabsBloc;
  final NavigationBloc navigationBloc;
  final CalendarCubit calendarCubit;
  final WorkspaceBloc workspaceBloc;
  final SearchRepository searchRepository;
  final BiographiesRepository? biographiesRepository;
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
  ///
  /// `bookId` הוא ה-id המספרי ב-DB (-1 ל-PDF ממערכת הקבצים), ותקף רק במקור
  /// רשמי: שאר המסדים מקצים מזהים באותו טווח, ולכן id שלהם אינו חד-משמעי.
  final Future<
    List<
      ({
        String title,
        int index,
        bool isPdf,
        int bookId,
        String reference,
        String bookPath,
        bool isSourceLine,
        BookSource source,
      })
    >
  >
  Function(String reference)?
  resolveReference;

  /// פותר הפניה לרמת שורה (פסוק/סעיף) דרך ה-heRef הפר-שורתי — מדויק מתחת
  /// לרזולוציית ה-TOC. אופציונלי — אם לא סופק או שאין התאמה, `openBookAtRef`
  /// ממשיך במסלולי ה-TOC הקיימים.
  final Future<int?> Function(TextBook book, String ref)? resolveRefToLine;

  /// מחזיר את מבני ה-AltToc של ספר. אופציונלי — אם לא סופק,
  /// האדפטר משתמש ב-[DatabaseLibraryProvider.instance]. קיים בעיקר להזרקה
  /// בבדיקות (ה-DB אינו זמין בהן).
  final Future<List<AltTocStructure>> Function(TextBook book)?
  altStructuresProvider;

  /// מחזיר את ערכי מבנה ה-AltToc עם ה-lineIndex, לבניית העץ. אופציונלי —
  /// אם לא סופק, האדפטר משתמש ב-[DatabaseLibraryProvider.instance].
  final Future<List<AltTocEntryRow>> Function(int structureId)?
  altTocEntriesProvider;

  /// מקור הנתונים של קריאות הקישורים והמפרשים ב-`library.*`.
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

  /// שורות היעד של הקישור, לסינון שמות הקודש לפי מופעיהן. ברירת המחדל:
  /// [Link.contentLines]; גובר על [linkContentLoader].
  final Future<List<LinkContentLine>> Function(Link link)?
  linkContentLinesLoader;

  /// הגבלת המו"ל של ספר. ברירת המחדל: [BookProtectionRepository].
  final Future<BookProtection> Function(Book book)? bookProtectionResolver;

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

  /// מדפיס את הדף של מופע התוסף (`ui.print`). אופציונלי — ברירת המחדל היא
  /// [PluginPrintService] מעל ה-WebView הרשום; קיים להזרקה בבדיקות.
  final Future<bool> Function(
    String pluginId,
    String instanceId, {
    required String jobName,
    PluginPdfLayout? layout,
  })?
  printPluginPage;

  /// פותח את מסך ההדפסה של אוצריא על קובץ PDF שהוענק לתוסף (`ui.printFile`)
  /// ומחזיר אם המשתמש הדפיס או ייצא. אופציונלי — ברירת המחדל מציגה את
  /// [PrintingScreen] כדיאלוג; קיים להזרקה בבדיקות.
  final Future<bool> Function(File file, {required String jobName})?
  printPluginFile;

  /// פותח את מסך ההדפסה של אוצריא על טווח שורות בספר (`reader.printRange`)
  /// ומחזיר אם המשתמש הדפיס או ייצא. אופציונלי — ברירת המחדל מציגה את
  /// [PrintingScreen] כדיאלוג; קיים להזרקה בבדיקות.
  final Future<bool> Function(
    TextBook book, {
    required int startLine,
    int? endLine,
    required List<String> activeCommentators,
    required List<String> availableCommentators,
  })?
  printBookRange;

  /// מייצר PDF מהדף של מופע התוסף (`ui.exportPdf`). אופציונלי — ברירת המחדל
  /// היא [PluginPrintService] מעל ה-WebView הרשום; קיים להזרקה בבדיקות.
  final Future<Uint8List> Function(
    String pluginId,
    String instanceId, {
    PluginPdfLayout? layout,
  })?
  capturePluginPagePdf;

  /// האם ל-WebView של המופע יש כרגע הפעלת-משתמש חולפת (`navigator
  /// .userActivation`). אופציונלי — ברירת המחדל קוראת מה-WebView הרשום.
  final Future<bool> Function(String pluginId, String instanceId)?
  hasUserActivation;

  /// ה-BLoC של התיקיות האישיות — היעד של `library.refreshUserBooks`. אותה
  /// סריקה שהלחצן „סרוק מחדש תיקיות אישיות” מפעיל, ולכן דרכה ולא בקוד סריקה
  /// משלנו. אופציונלי: כשאינו מסופק (בדיקות), הקריאה מחזירה
  /// `error.unavailable`.
  final CustomFoldersBloc? customFoldersBloc;

  /// ממתין לרענון הקטלוג שנוצר בעקבות `library.refreshUserBooks`. ההרשמה
  /// נעשית לפני תחילת הסריקה, כדי שתוצאת API מוצלחת תבטיח שהספרים החדשים
  /// כבר נראים לקריאה הבאה של התוסף.
  final Future<void> Function(int requestId)? waitForLibraryRefresh;

  PluginBridgeWindowDependencies get window => (
    context: windowContext,
    viewId: windowContext == null ? null : View.of(windowContext!).viewId,
    windowKeys: windowContext == null ? null : AppWindowKeys.of(windowContext!),
    historyBloc: historyBloc,
    tabsBloc: tabsBloc,
    navigationBloc: navigationBloc,
    workspaceBloc: workspaceBloc,
    bookOpenCoordinator: bookOpenCoordinator,
    customFoldersBloc: customFoldersBloc,
    waitForLibraryRefresh: waitForLibraryRefresh,
  );

  const PluginBridgeDependencies({
    this.windowContext,
    required this.historyBloc,
    required this.tabsBloc,
    required this.navigationBloc,
    required this.calendarCubit,
    required this.workspaceBloc,
    required this.searchRepository,
    this.biographiesRepository,
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
    this.linkContentLinesLoader,
    this.bookProtectionResolver,
    this.bookmarkBloc,
    this.onBackgroundInstanceDone,
    this.dispatchEventToPlugin,
    this.printPluginPage,
    this.printPluginFile,
    this.printBookRange,
    this.capturePluginPagePdf,
    this.hasUserActivation,
    this.customFoldersBloc,
    this.waitForLibraryRefresh,
  });
}

/// חלון השורות המרבי לקריאת `library.getLinks` אחת, ותקרת הרשומות בתשובה.
const int _pluginLinksMaxWindowLines = 200;
const int _pluginLinksMaxRecords = 2000;

/// כנ"ל ל-`library.getRawLinks`. גבוה יותר כי מקרה השימוש הוא ייצוא ולא חלון
/// גלילה — אך חסום, כי מסכת עמוסת-מפרשים מממשת עשרות אלפי קישורים בזיכרון.
const int _pluginRawLinksMaxWindowLines = 1000;
const int _pluginRawLinksMaxRecords = 10000;

/// מספר הפריטים המרבי בקריאת `library.getLinkContent` אחת.
const int _pluginLinkContentMaxItems = 25;

typedef PluginRpcEventSink =
    Future<void> Function(String topic, Map<String, dynamic> payload);

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
// Bridge Adapter
// ===================================================================
class PluginBridgeAdapter {
  final InstalledPlugin plugin;
  final TextBookTab? readerTab;

  /// מזהה מופע הריצה שה-adapter משרת (טאב או 'background') — רישומי ה-UI
  /// וההדגשות ממופתחים לפיו, וניקויים ב-dispose מסיר רק אותם.
  final String instanceId;
  final PluginRegistryRepository _pluginRepo;
  final PluginBridgeDependencies _dependencies;
  final PluginBridgeWindowDependencies Function()? windowDependenciesResolver;
  late final _defaultWindowDependencies = _dependencies.window;
  final _windowScopeKey = Object();
  PluginBridgeWindowDependencies get _windowDependencies =>
      Zone.current[_windowScopeKey] as PluginBridgeWindowDependencies? ??
      _defaultWindowDependencies;

  BuildContext? get rpcWindowContext => _windowDependencies.context;

  /// ברקע החלון הפעיל הוא יעד ה-RPC; בקשות חופפות שומרות כל אחת על היעד שלה.
  Future<T> withWindowDependencies<T>(
    Future<T> Function() action, {
    String? domain,
    String? rpcAction,
  }) {
    if (const {
          'app',
          'fonts',
          'storage',
          'settings',
          'calendar',
          'bookmarks',
          'database',
          'network',
          'shortcut',
        }.contains(domain) ||
        (domain == 'notifications' && rpcAction != 'showInApp')) {
      return action();
    }
    final resolve = windowDependenciesResolver;
    if (resolve == null || Zone.current[_windowScopeKey] != null) {
      return action();
    }
    return runZoned(action, zoneValues: {_windowScopeKey: resolve()});
  }

  final CalendarAlertsClient _alerts;
  final PluginDatabaseService _databaseService;
  final PluginHighlightRegistry _highlightRegistry;
  final PluginSearchFieldSessionService _searchFieldSessions;

  PluginBridgeAdapter(
    this.plugin, {
    required this._dependencies,
    this.windowDependenciesResolver,
    this.instanceId = PluginInstanceIds.defaultForeground,
    this.readerTab,
    PluginRegistryRepository? pluginRepository,
    NotificationService? notificationService,
    CalendarAlertsClient? alertsClient,
    PluginDatabaseService? databaseService,
    this._networkFetchService,
    this._fileDownloadService,
    PluginFsService? fsService,
    PluginShortcutService? shortcutService,
    PluginFileServer? fileServer,
    PluginRemoteFileCache? remoteFileCache,
    PluginHighlightRegistry? highlightRegistry,
    PluginReportService? reportService,
    PluginBookCorrectionService? bookCorrectionService,
    PluginSearchFieldSessionService? searchFieldSessions,
  }) : _pluginRepo = pluginRepository ?? PluginRegistryRepository(),
       _pluginReportService = reportService,
       _pluginBookCorrectionService = bookCorrectionService,
       // שירות שהוזרק (בדיקות) מקבל בעלים פרטי; אחרת הבעלים של החלון.
       _alerts =
           alertsClient ??
           (notificationService == null
               ? CalendarAlertsClient.forCurrentWindow()
               : LocalCalendarAlertsClient(
                   CalendarAlertsOwner(
                     notifications: notificationService,
                     pluginIds: RegistryPluginNotificationIdStore(
                       pluginRepository,
                     ),
                   ),
                 )),
       _databaseService = databaseService ?? PluginDatabaseService(),
       _highlightRegistry =
           highlightRegistry ?? PluginHighlightRegistry.instance,
       _pluginFsService = fsService,
       _pluginShortcutService = shortcutService,
       _fileServer = fileServer ?? PluginFileServer.instance,
       _remoteFiles = remoteFileCache ?? PluginRemoteFileCache.instance,
       _searchFieldSessions =
           searchFieldSessions ?? PluginSearchFieldSessionService.instance {
    _stopFolderRevocationListener = PluginUserFolderGrants.onRevoke(
      plugin.pluginId,
      _removeTemporaryFolderGrant,
    );
  }

  // שרת הקבצים הפנימי שמגיש קבצים אישיים ל-WebView (מופע יחיד לכל האפליקציה
  // כברירת מחדל; ניתן להזרקה לבדיקות).
  final PluginFileServer _fileServer;

  // מטמון הקבצים ש-`network.fetchFile` הוריד.
  final PluginRemoteFileCache _remoteFiles;

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

  DirectErrorReportService? _directBookReportService;
  PluginBookCorrectionService? _pluginBookCorrectionService;
  PluginBookCorrectionService get _bookCorrectionService {
    if (_pluginBookCorrectionService case final service?) return service;
    final direct = _directBookReportService ??= DirectErrorReportService();
    return _pluginBookCorrectionService = PluginBookCorrectionService(
      senderEmail: () => direct.senderEmail,
      deliver: direct.submitReport,
    );
  }

  // שירות יצירת קיצורי דרך (shortcut.create) — מופע יחיד לכל adapter.
  PluginShortcutService? _pluginShortcutService;
  PluginShortcutService get _shortcutService =>
      _pluginShortcutService ??= const PluginShortcutService();

  /// תיקיות שהמשתמש בחר במפורש דרך `ui.pickFolder` עבור התוסף בריצה זו.
  ///
  /// **גבול האבטחה לכתיבה/מחיקה בדיסק:** פעולות `fs.extractZip`,
  /// `fs.deleteFile` ו-`network.download` עם `destPath` מותרות אך ורק על
  /// נתיבים בתוך אחת מהתיקיות הללו, או בתוך תיקייה עם גישה קבועה
  /// (`fs.pickUserFolder`, ראה [_isPathInGrantedFolder]). כך גישת התוסף לדיסק
  /// נובעת מהסכמה מפורשת של המשתמש בדיאלוג בחירת התיקייה — ולא מהרשאת
  /// manifest. הקבוצה מאופסת עם `dispose` (טעינה/השבתה מחדש של התוסף).
  final Set<String> _grantedFolders = <String>{};
  late final void Function() _stopFolderRevocationListener;

  void _removeTemporaryFolderGrant(String path) {
    _grantedFolders.removeWhere((root) => p.equals(root, path));
  }

  // שירות בקשות HTTP — מופע יחיד לכל adapter; ניתן להזרקה
  // לבדיקות, נוצר עם השימוש הראשון אם לא הוזרק, ומשוחרר ב-dispose.
  PluginNetworkFetchService? _networkFetchService;
  PluginNetworkFetchService get _fetchService =>
      _networkFetchService ??= PluginNetworkFetchService();

  // LRU קצר לכל תוסף; bookUid מפריד ספרים זהים ממסדים מצורפים שונים.
  final Map<String, String> _bookContentCache = {};
  final List<({String raw, Object key, Future<String> content})>
  _filteredContents = [];
  static const int _bookContentCacheMaxEntries = 4;
  static int _bookContentRevision = 0;
  int _seenBookContentRevision = 0;

  /// אורך מקסימלי לשם שולחן עבודה שתוסף יוצר — השם מוצג בממשק המשתמש.
  static const int _workspaceNameMaxLength = 100;

  /// חסם ההמתנה לפעולת שולחן עבודה שעוברת דרך ה-WorkspaceBloc.
  static const Duration _workspaceActionTimeout = Duration(seconds: 5);

  static Future<void> _workspaceActionQueue = Future.value();

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

  static bool isStreamCancellationPayload(Map<String, dynamic> args) {
    if (args.length != 1) return false;
    final streamId = args[_cancelStreamIdKey];
    return streamId is String && _streamIdPattern.hasMatch(streamId);
  }

  /// ביטול שמגיע לפני תחילת הזרם נשמר ב-[pending], והזרם נעצר כשיתחיל.
  Map<String, dynamic> _cancelStream(
    String streamId,
    Map<String, Future<void> Function()> active,
    Set<String> pending,
  ) {
    if (!_streamIdPattern.hasMatch(streamId)) {
      throw Exception('error.invalid_params: invalid internal stream id');
    }
    final cancel = active[streamId];
    if (cancel == null) {
      if (pending.length < 16) pending.add(streamId);
      return {'cancelled': false};
    }
    unawaited(cancel());
    return {'cancelled': true};
  }

  /// משחרר את מה שקשור לדף הנוכחי — תרומות ו-streams — כשה-WebView שוחרר.
  /// המתאם ממשיך לשמש את הדף הבא של אותו מופע.
  void releaseRuntime() {
    // מסיר רק את תרומות המופע הזה — מופע אחר של אותו תוסף ממשיך לתפקד,
    // וה-dedup בציור חושף את העותקים שלו.
    final key = (pluginId: plugin.pluginId, instanceId: instanceId);
    ContextMenuRegistry.instance.removeInstance(key);
    PluginToolbarRegistry.instance.removeInstance(key);
    PluginUnsavedChangesRegistry.instance.removeInstance(key);
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
  }

  void dispose() {
    _stopFolderRevocationListener();
    releaseRuntime();
    _networkFetchService?.dispose();
    _fileDownloadService?.dispose();
    _bookContentCache.clear();
    _filteredContents.clear();
    unawaited(_directBookReportService?.closeHttpClient());
    _bookIndexLibrary = null;
    _booksById = const {};
    _booksByTitle = const {};
    _booksByUid = const {};
    _booksByIndexedPath = const {};
  }

  static const _restrictedTextMessage =
      "The publisher restricted access to this book's text";

  /// הגבלת המו"ל של [book].
  Future<BookProtection> _protectionOf(Book book) async {
    // הקורא המקושר כבר טען את ההגבלה; בלי await, כדי לא לדחות את קריאת מצבו.
    final boundState = readerTab?.bloc.state;
    if (boundState is TextBookLoaded &&
        PluginBookIdentity.uidOf(boundState.book) ==
            PluginBookIdentity.uidOf(book)) {
      return boundState.protection;
    }
    final resolver =
        _dependencies.bookProtectionResolver ??
        BookProtectionRepository.instance.forBook;
    return resolver(book);
  }

  /// ספר עם הגבלת מו"ל: הטקסט שלו אינו נמסר לתוספים.
  Future<bool> _isTextRestricted(Book book) async =>
      (await _protectionOf(book)).isProtected;

  /// ההגבלה כפי שנמסרת לתוספים — מה מותר, לא רק הרמה, כדי שתוסף לא יצטרך
  /// לשכפל את טבלת הרמות של [BookProtection].
  static Map<String, dynamic> _protectionJson(BookProtection p) => {
    'level': p.effectiveLevel,
    'textAvailable': !p.isProtected,
    'editableExport': p.allowsEditableExport,
    'pdfExport': p.allowsPdfExport,
    'copyLimit': p.maxCopySegments,
    'printLimit': p.maxPrintSegments,
  };

  Future<void> _ensureBookTextAvailable(Book book) async {
    if (await _isTextRestricted(book)) {
      throw Exception('error.forbidden: $_restrictedTextMessage');
    }
  }

  /// LRU מונע טעינה חוזרת של ספר בקריאות מקוטעות; UID שומר על הפרדת המקורות.
  Future<String> _loadBookRawText(Book book) async {
    if (_seenBookContentRevision != _bookContentRevision) {
      _bookContentCache.clear();
      _seenBookContentRevision = _bookContentRevision;
    }
    final key = PluginBookIdentity.uidOf(book);
    final cached = _bookContentCache.remove(key);
    if (cached != null) {
      _bookContentCache[key] = cached; // רענון מיקום ב-LRU
      return cached;
    }
    // ה-TextBook מהקטלוג שומר categoryId/fileType נכונים גם בספרים השמורים רק ב-DB.
    final String rawText;
    if (book is TextBook) {
      rawText =
          await (_dependencies.textBookRepository ??
                  TextBookRepository(
                    fileSystem: FileSystemData.instance,
                  ))
              .getBookContent(book);
    } else {
      rawText = await DataRepository.instance.getBookText(book.title);
    }
    _bookContentCache[key] = rawText;
    if (_bookContentCache.length > _bookContentCacheMaxEntries) {
      _bookContentCache.remove(_bookContentCache.keys.first);
    }
    return rawText;
  }

  /// [request] כפי שהתוסף מקבל אותו. המרת הספר כולו רצה מחוץ ל-UI, ובקשות
  /// מקבילות לאותו טקסט ולאותה תצוגה חולקות אותה.
  Future<String> _filteredBookContent(
    PluginBookContentFilterRequest request,
  ) async {
    final rawText = request.rawText;
    if (!request.names.filters && request.displayProfile == null) {
      return rawText;
    }
    final key = (request.names, request.displayProfile, request.spans);
    final index = _filteredContents.indexWhere(
      (entry) => identical(entry.raw, rawText) && entry.key == key,
    );
    final entry = index >= 0
        ? _filteredContents.removeAt(index)
        : (
            raw: rawText,
            key: key,
            content: compute(filterPluginBookContent, request),
          );
    _filteredContents.add(entry);
    if (_filteredContents.length > _bookContentCacheMaxEntries) {
      _filteredContents.removeAt(0);
    }
    try {
      return await entry.content;
    } catch (_) {
      _filteredContents.removeWhere(
        (cached) => identical(cached.content, entry.content),
      );
      rethrow;
    }
  }

  /// מצב הכרטיסייה שבה [book] פתוח: המקושרת, אחריה החלונית הפעילה ושאר החלוניות.
  TextBookLoaded? _openReaderStateFor(Book book) {
    final uid = PluginBookIdentity.uidOf(book);
    final tabs = _windowDependencies.tabsBloc.state;
    for (final tab in <OpenedTab>[
      ?readerTab,
      ?tabs.readingPane,
      ...tabs.tabs.expand(leafPanes),
    ]) {
      if (tab is! TextBookTab || PluginBookIdentity.uidOf(tab.book) != uid) {
        continue;
      }
      final state = tab.bloc.state;
      if (state is TextBookLoaded) return state;
    }
    return null;
  }

  /// `rawDivineNames: true` — הטקסט כפי שנשמר, בלי החלפת שמות הקודש.
  static bool _rawDivineNamesArg(Map<String, dynamic> args) {
    final value = args['rawDivineNames'];
    if (value != null && value is! bool) {
      throw Exception('error.invalid_params: rawDivineNames must be a boolean');
    }
    return value == true;
  }

  /// הצגת השמות לטקסט נגזר של [book] (כותרות, תקצירים, תוויות).
  Future<PluginDivineNamesDisplay> _derivedTextNames(
    Book? book,
    Map<String, dynamic> args,
  ) => PluginDivineNamesFilter.resolve(
    book: book,
    readerState: book == null ? null : _openReaderStateFor(book),
    raw: _rawDivineNamesArg(args),
  );

  Future<dynamic> execute(
    String domain,
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) => withWindowDependencies(
    () => _execute(domain, action, args, eventSink: eventSink),
    domain: domain,
    rpcAction: action,
  );

  Future<dynamic> _execute(
    String domain,
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    switch (domain) {
      case 'app':
        return await _handleApp(action, args);
      case 'fonts':
        return await _handleFonts(action, args);
      case 'library':
        return await _handleLibrary(action, args);
      case 'search':
        return await _handleSearch(action, args, eventSink: eventSink);
      case 'reader':
        return await _handleReader(action, args);
      case 'workspace':
        return await _enqueueWorkspaceAction(
          () => _handleWorkspace(action, args),
        );
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
      case 'events':
        return await _handleEvents(action, args);
      default:
        throw Exception("error.unknown_method: Unknown domain: $domain");
    }
  }

  // ----------------------------------------------------------------
  // fonts.*, app.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleFonts(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'resolveFamilies':
        final families = args['families'];
        if (families is! List) {
          throw Exception('error.invalid_params: families must be an array');
        }
        return await resolvePluginFontFamilies(families);
      case 'listInstalled':
        return InstalledFonts.list();
      default:
        throw Exception('error.not_supported: fonts.$action');
    }
  }

  /// `app.getDivineNamesDisplay` — איך שמות הקודש יגיעו לתוסף בטקסט של ספר
  /// (או בהגדרה הכללית, בלי ספר), לפי הגדרת המשתמש ברגע הקריאה.
  Future<Map<String, dynamic>> _getDivineNamesDisplay(
    Map<String, dynamic> args,
  ) async {
    final target = switch (args['target'] ?? 'body') {
      'body' => TextTarget.body,
      'commentary' => TextTarget.commentary,
      _ => throw Exception(
        "error.invalid_params: target must be 'body' or 'commentary'",
      ),
    };
    final hasIdentity =
        PluginBookIdentity.parseId(args['id']) != null ||
        (args['bookId'] ?? args['title']) != null ||
        args['bookUid'] != null;
    final book = hasIdentity
        ? _findPluginBook(await DataRepository.instance.library, args)
        : null;
    if (hasIdentity && book == null) {
      throw Exception('error.not_found: book not found');
    }
    final names = await PluginDivineNamesFilter.resolve(
      book: book,
      readerState: book == null ? null : _openReaderStateFor(book),
      target: target,
    );
    return names.toJson();
  }

  Future<dynamic> _handleApp(String action, Map<String, dynamic> args) async {
    switch (action) {
      case 'getInfo':
        final packageInfo = await PackageInfo.fromPlatform();
        return {
          'version': appReleaseVersion(packageInfo),
          'buildNumber': packageInfo.buildNumber,
          'platform': Platform.operatingSystem,
        };
      case 'getTheme':
        return _dependencies.themePayloadBuilder();
      case 'getDivineNamesDisplay':
        return await _getDivineNamesDisplay(args);
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
        // הכתובת עצמה נושאת מידע לאתר. בלי אישור — רק יעד שהתוסף רשאי
        // לפנות אליו ממילא ברשת, אחרת זה ערוץ שליחה שעוקף את רשימת ההיתר.
        final allowed = await isPluginNetworkAccessAllowed(
          uri: uri,
          pluginId: plugin.pluginId,
          manifest: plugin.manifest,
          registry: _pluginRepo,
        );
        if (!allowed && !await _confirmOpenUrl(uri)) return false;
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
      case 'registerShortcut':
        PluginShortcutRegistry.instance.registerPayload(plugin.pluginId, args);
        return true;
      case 'unregisterShortcut':
        final id = args['id'] as String?;
        if (id == null) throw Exception('error.invalid_params: id required');
        PluginShortcutRegistry.instance.remove(plugin.pluginId, id);
        return true;
      case 'updateShortcut':
        final id = args['id'];
        final patch = args['patch'];
        if (id is! String || patch is! Map) {
          throw Exception('error.invalid_params: id and patch are required');
        }
        PluginShortcutRegistry.instance.update(
          plugin.pluginId,
          id,
          Map<String, dynamic>.from(patch),
        );
        return true;
      default:
        throw Exception("error.unknown_method: Unknown action in app: $action");
    }
  }

  // ----------------------------------------------------------------
  // library.*
  // ----------------------------------------------------------------
  /// מזהה בקשת הרענון הבא. סטטי בכוונה: כמה מופעי adapter (טאב + רקע, או
  /// תוספים שונים) יכולים להמתין לאותו BLoC בו-זמנית, והמזהה חייב להיות
  /// ייחודי ביניהם כדי שכל אחד יזהה את התוצאה של הבקשה שלו.
  static int _nextUserBooksRefreshRequestId = 1;

  /// חסם עליון לסריקת התיקיות האישיות. לסריקה עצמה אין timeout טבעי — משכה
  /// תלוי בכמות הקבצים אצל המשתמש — ובלעדיו תוסף שממתין לתשובה נתקע לנצח.
  static const Duration _userBooksRefreshTimeout = Duration(minutes: 15);

  /// `library.refreshUserBooks` — סורק מחדש את התיקיות האישיות של המשתמש
  /// ומרענן בעקבותיה את קטלוג הספרייה. זה המסלול שתוסף שמוריד ספרים למשתמש
  /// משתמש בו כדי שהספרים שהוריד יופיעו בספרייה בלי הפעלה מחדש.
  ///
  /// אילו תיקיות ייסרקו נקבע מהגדרות המשתמש בלבד — התוסף אינו מעביר נתיב,
  /// ולכן אינו יכול לגרום לסריקה של תיקייה שהמשתמש לא הגדיר.
  Future<Map<String, dynamic>> _refreshUserBooks() async {
    final bloc = _windowDependencies.customFoldersBloc;
    if (bloc == null) {
      throw Exception(
        'error.unavailable: personal books refresh is not available',
      );
    }

    final requestId = _nextUserBooksRefreshRequestId++;
    // ההרשמה נעשית לפני ה-add: סריקה שמסתיימת מהר הייתה מספיקה לפלוט את
    // התוצאה לפני שהמאזין נרשם, והקריאה הייתה תקועה עד ה-timeout.
    final completed = bloc.stream
        .firstWhere((state) => state.completedScan?.requestId == requestId)
        .timeout(_userBooksRefreshTimeout);
    final waitForRefresh = _windowDependencies.waitForLibraryRefresh;
    final libraryRefreshCompleted = waitForRefresh == null
        ? null
        : waitForRefresh(requestId).timeout(_userBooksRefreshTimeout);
    bloc.add(
      RescanCustomFolders(showNoChangesMessage: false, requestId: requestId),
    );

    final CustomFoldersScanOutcome outcome;
    try {
      outcome = (await completed).completedScan!;
      if (libraryRefreshCompleted != null) {
        await libraryRefreshCompleted;
      }
    } on TimeoutException {
      throw Exception('error.timeout: personal books refresh timed out');
    }
    if (!outcome.isSuccess) {
      throw Exception('error.internal: ${outcome.failureMessage}');
    }
    return {
      'addedBooks': outcome.addedBooks,
      'updatedBooks': outcome.updatedBooks,
      // כשלים חלקיים: קבצים בודדים שלא נסרקו. הסריקה עצמה הצליחה.
      'errors': outcome.errors,
    };
  }

  /// spec: setProviderBooks({ provider, books }) -> { count }
  Future<Map<String, dynamic>> _setProviderBooks(
    Map<String, dynamic> args,
  ) async {
    final provider = args['provider'];
    if (provider is! String) {
      throw Exception('error.invalid_params: provider must be a string');
    }
    try {
      final count = await PluginLibraryBooksRegistry.instance.setBooks(
        plugin.pluginId,
        provider,
        args['books'],
      );
      return {'count': count};
    } on PluginLibraryBooksException catch (error) {
      final code = error.notFound ? 'error.not_found' : 'error.invalid_params';
      throw Exception('$code: $error');
    }
  }

  Future<dynamic> _handleLibrary(
    String action,
    Map<String, dynamic> args,
  ) async {
    final library = await DataRepository.instance.library;
    switch (action) {
      case 'refreshUserBooks':
        return await _refreshUserBooks();
      case 'setProviderBooks':
        return await _setProviderBooks(args);
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
      case 'resolveRef':
        // spec: resolveRef({ ref, limit? }) -> [{ id, bookId, bookUid, type,
        // title, reference, index, isPdf, isSourceLine, bookPath }]
        //
        // מריץ את מנוע `find_ref` המלא — אותו מנוע שמאחורי "איתור מקורות" —
        // ומחזיר את התוצאה במקום לפתוח אותה. זו הצורה השאילתתית של
        // `reader.openBookAtRef`, לתוספים שבונים קישור או הצעת השלמה.
        {
          final ref = args['ref']?.toString().trim() ?? '';
          final limit = (args['limit'] as num?)?.toInt() ?? 20;
          // סף של שני תווים — כמו ב-FindRefBloc; מחרוזת קצרה מזו מתאימה
          // לחצי הספרייה ורק מבזבזת סריקה.
          if (ref.length < 2 || limit <= 0) return <dynamic>[];
          final resolve = _dependencies.resolveReference;
          if (resolve == null) return <dynamic>[];
          final hits = await resolve(ref);
          final books = library.getAllBooks();
          return hits.take(limit).map((h) {
            // מזהים מספריים של מסדים שונים חופפים — הזהות נקבעת רק יחד עם המקור.
            final identity = h.bookId < 0
                ? null
                : books.firstWhereOrNull(
                    (b) =>
                        b is TextBook &&
                        b.source == h.source &&
                        b.id == h.bookId,
                  );
            return {
              'id': identity?.id,
              'bookId': h.title,
              if (identity != null)
                'bookUid': PluginBookIdentity.uidOf(identity),
              if (identity != null) 'type': PluginBookIdentity.typeOf(identity),
              'title': h.title,
              'reference': h.reference,
              'index': h.index,
              'isPdf': h.isPdf,
              'isSourceLine': h.isSourceLine,
              'isUserBook': h.source.isUser,
              'source': identity != null
                  ? PluginBookIdentity.sourceOf(identity)
                  : PluginBookIdentity.sourceOfBookSource(h.source),
              'bookPath': h.bookPath,
            };
          }).toList();
        }
      case 'getBookMetadata':
        // spec: accepts id, bookId (= title in otzaria), type — all optional,
        // all supplied fields must match the same book.
        {
          _requireBookIdentity(args);
          final book = _findPluginBook(library, args);
          if (book == null) return null;
          return {
            ...PluginBookIdentity.toJsonWithUid(book),
            'title': book.title,
            'topics': book.topics,
            'categoryPath': FacetHelper.resolveCategoryPath(book),
          };
        }
      case 'getBookDetails':
        // spec: אותם שדות זהות כמו getBookMetadata, ומחזיר את נתוני
        // חלון "אודות הספר" — אותו מקור נתונים, כדי שהתצוגות לא ייפרדו.
        {
          _requireBookIdentity(args);
          final book = _findPluginBook(library, args);
          if (book == null) return null;
          final names = await _derivedTextNames(book, args);
          final info = await BookDetailsService().getBookInformation(book);
          final sourceName = info.source?.trim();
          final sourceDisplay = sourceName == null || sourceName.isEmpty
              ? null
              : getSourceDisplayInfo(sourceName);
          return {
            ...PluginBookIdentity.toJsonWithUid(book),
            'title': book.title,
            'authors': info.authors,
            'generation': info.generation,
            'era': book.heEra,
            'categories': info.categories,
            'categoryPath': FacetHelper.resolveCategoryPath(book),
            'compositionDate': book.compDateStringHe,
            'compositionPlace': book.compPlaceStringHe,
            'publicationDates': info.publicationDates,
            'publicationPlaces': info.publicationPlaces,
            'topics': info.topics,
            'shortDescription': switch (info.shortDescription) {
              final text? => filterPluginDivineNamesText(text, names),
              null => null,
            },
            'fullDescription': switch (info.fullDescription) {
              final text? => filterPluginDivineNamesText(text, names),
              null => null,
            },
            'textSource': sourceDisplay == null
                ? null
                : {
                    'key': sourceName,
                    'name': sourceDisplay.text,
                    if (sourceDisplay.url.isNotEmpty) 'url': sourceDisplay.url,
                  },
            'reference': info.reference,
            'protection': _protectionJson(await _protectionOf(book)),
            'lineCount': info.lineCount,
            // רק הנתיב היחסי בספרייה: נתיב מוחלט מסגיר את שם המשתמש.
            'libraryPath': libraryDisplayPath(book.filePath ?? ''),
          };
        }
      case 'getBookProtections':
        // spec: { items } (עד 500) — זהות ספר לכל פריט, כמו getBookMetadata,
        // או כותרת + categoryId כפי שחוזרים מ-getLinks (מפרש). מחזיר מערך
        // באותו סדר; ספר שלא נמצא → null.
        {
          final raw = args['items'];
          if (raw is! List || raw.length > 500) {
            throw Exception(
              'error.invalid_params: items must be an array with at most 500 entries',
            );
          }
          final out = <Map<String, dynamic>?>[];
          for (final item in raw) {
            if (item is! Map) {
              throw Exception('error.invalid_params: items must be objects');
            }
            final itemArgs = Map<String, dynamic>.from(item);
            final title = (itemArgs['bookId'] ?? itemArgs['title']) as String?;
            final book =
                _findPluginBook(library, itemArgs) ??
                (title == null || title.trim().isEmpty
                    ? null
                    : TextBook(
                        title: title,
                        categoryId: PluginBookIdentity.parseId(
                          itemArgs['categoryId'],
                        ),
                      ));
            out.add(
              book == null ? null : _protectionJson(await _protectionOf(book)),
            );
          }
          return out;
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
            _windowDependencies.bookOpenCoordinator,
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
        final historyState = _windowDependencies.historyBloc.state;
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
        await _ensureBookTextAvailable(book ?? TextBook(title: bookId!));
        final rawNames = _rawDivineNamesArg(args);
        final rawText = book == null
            ? await DataRepository.instance.getBookText(bookId!)
            : await _loadBookRawText(book);
        final contentBook = book ?? TextBook(title: bookId!);
        TextDisplayProfile? displayProfile;
        TextBookLoaded? readerState;
        if (args['textReaderDisplay'] == true) {
          final tab = readerTab;
          final state = tab?.bloc.state;
          if (tab == null ||
              state is! TextBookLoaded ||
              book == null ||
              PluginBookIdentity.uidOf(book) !=
                  PluginBookIdentity.uidOf(tab.book)) {
            throw Exception(
              'error.unavailable: Display content requires the bound reader',
            );
          }
          readerState = state;
          displayProfile = PluginDivineNamesFilter.readerProfile(state);
        } else if (book != null) {
          readerState = _openReaderStateFor(book);
        }
        final names = await PluginDivineNamesFilter.resolve(
          book: contentBook,
          readerState: readerState,
          raw: rawNames,
        );
        final PluginBookContentFilterRequest request = (
          rawText: rawText,
          spans: names.filters
              ? await PluginDivineNamesFilter.spansFor(
                  contentBook,
                  readerState: readerState,
                )
              : DivineNameSpans.empty,
          names: names,
          displayProfile: displayProfile,
        );
        final text = await _filteredBookContent(request);
        final limit = args['limit'] as int? ?? 1000;
        final offset = args['offset'] as int? ?? 0;
        final section = args['section'] as String?;
        int startIndex = offset;
        if (section != null && section.isNotEmpty) {
          final idx = identical(text, rawText)
              ? text.indexOf(section)
              : await compute(locatePluginBookSection, (
                  request: request,
                  filtered: text,
                  section: section,
                ));
          // ה-offset נספר יחסית למיקום ה-section, לא לתחילת הטקסט
          if (idx >= 0) startIndex = idx + offset;
        }
        final clampedLimit = limit > 5000 ? 5000 : limit;
        final end = (startIndex + clampedLimit).clamp(0, text.length);
        return text.substring(startIndex.clamp(0, text.length), end);
      case 'getBookToc':
        final book = _findPluginBook(library, args);
        if (book is TextBook) {
          final names = await _derivedTextNames(book, args);
          final toc = flattenToc(await book.tableOfContents);
          return toc
              .map(
                (e) => {
                  'text': filterPluginDivineNamesText(e.text, names),
                  'index': e.index,
                  'level': e.level,
                },
              )
              .toList();
        }
        return [];
      case 'listBookAltStructures':
        {
          final bookId = args['bookId'] ?? args['title'];
          if (bookId is! String || bookId.isEmpty) {
            throw Exception('error.invalid_params: bookId required');
          }
          final book = _findPluginBook(library, args);
          final names = await _derivedTextNames(book, args);
          final structures = book is TextBook
              ? await _loadAltStructures(book)
              : const <AltTocStructure>[];
          // ה-id הפנימי של ה-DB אינו יציב בין גרסאות ספרייה — לא נחשף לתוסף.
          return structures
              .map(
                (s) => {
                  'key': s.key,
                  'title': s.title,
                  'heTitle': s.heTitle == null
                      ? null
                      : filterPluginDivineNamesText(s.heTitle!, names),
                },
              )
              .toList();
        }
      case 'getBookAltToc':
        {
          final bookId = args['bookId'] ?? args['title'];
          if (bookId is! String || bookId.isEmpty) {
            throw Exception('error.invalid_params: bookId required');
          }
          final book = _findPluginBook(library, args);
          final rawKey = args['structureKey'];
          if (rawKey != null && (rawKey is! String || rawKey.isEmpty)) {
            throw Exception(
              'error.invalid_params: structureKey must be a string',
            );
          }
          final structureKey = rawKey as String?;
          final structures = book is TextBook
              ? await _loadAltStructures(book)
              : const <AltTocStructure>[];
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
          final names = await _derivedTextNames(book, args);
          final entries = await _loadAltTocEntries(selected);
          return [
            for (final entry in _flattenAltToc(entries))
              {
                ...entry,
                'text': filterPluginDivineNamesText(
                  entry['text'] as String,
                  names,
                ),
              },
          ];
        }
      case 'getTree':
        // spec: getTree({ path?, includeBooks? }) -> מבנה עץ הספרייה המלא
        // path אופציונלי: מצמצם את העץ לתת-קטגוריה לפי הנתיב שלה (כמו '/תנך/ראשונים').
        //   ברירת מחדל: כל הספרייה.
        // includeBooks אופציונלי (ברירת מחדל true): האם לכלול את רשימות הספרים.
        // types אופציונלי (מ-0.9.98): רק ספרים שה-type שלהם ברשימה, וקטגוריות
        //   שאין תחתן אף ספר כזה נגזמות — עץ "ספרי Word" בלי אלפי ענפים ריקים.
        final path = args['path']?.toString();
        final includeBooks = args['includeBooks'] as bool? ?? true;
        final types = _optionalStringList(
          args['types'],
          'types',
        )?.map((t) => t.toLowerCase()).toSet();
        final root = (path == null || path.isEmpty || path == '/')
            ? library
            : _findCategoryByPath(library, path);
        if (root == null) return null;
        if (types != null) {
          return _categoryToFilteredTree(
                root,
                types: types,
                includeBooks: includeBooks,
              ) ??
              // שורש בלי אף ספר מתאים הוא עץ ריק, לא "נתיב לא נמצא" (null).
              {
                'title': root.title,
                'path': root.path,
                'categories': const <Map<String, dynamic>>[],
                if (includeBooks) 'books': const <Map<String, dynamic>>[],
              };
        }
        return _categoryToTree(root, includeBooks: includeBooks);
      case 'openBookFile':
        return await _openBookFile(library, args);
      case 'getCommentators':
        return await _getCommentators(library, args);
      case 'getLinks':
        return await _getLinks(library, args);
      case 'getRawLinks':
        return await _getRawLinks(library, args);
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
      final source = args['source'] as String?;
      return (_booksByTitle[bookId] ?? const <Book>[])
          .whereType<TextBook>()
          .where((b) => categoryId == null || b.categoryId == categoryId)
          .where((b) => PluginBookIdentity.matches(b, source: source))
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

  /// רשימת-ההיתר של כותרות: כותרת עוברת אם היא ברשימה המפורשת או פותחת
  /// באחת התחיליות. בלי שני הפילטרים — הכל עובר.
  static bool _titleAllowed(
    String title,
    Set<String>? titles,
    List<String>? prefixes,
  ) {
    if (titles == null && prefixes == null) return true;
    if (titles != null && titles.contains(title)) return true;
    return prefixes?.any(title.startsWith) ?? false;
  }

  Future<dynamic> _getCommentators(
    Library library,
    Map<String, dynamic> args,
  ) async {
    final rawStart = args['startLine'];
    final rawEnd = args['endLine'];
    final titlePrefixes = _optionalStringList(
      args['titlePrefixes'],
      'titlePrefixes',
    );
    if ((rawStart == null) != (rawEnd == null)) {
      throw Exception(
        'error.invalid_params: startLine and endLine must be given together',
      );
    }
    final book = _findLinksTextBook(library, args);
    if (book == null) throw Exception('error.not_found: book not found');

    List<CommentatorInfo> commentators;
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
    if (titlePrefixes != null) {
      commentators = [
        for (final c in commentators)
          if (titlePrefixes.any(c.title.startsWith)) c,
      ];
    }

    if (args['grouped'] as bool? ?? false) {
      final titles = [for (final c in commentators) c.title];
      final eras = await splitByEra(
        titles,
        source: book.source,
        sourceByTitle: await _linksRepository.getExternalCommentatorSources(
          book,
        ),
      );
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
    final targetTitlePrefixes = _optionalStringList(
      args['targetTitlePrefixes'],
      'targetTitlePrefixes',
    );
    final connectionTypes = _optionalStringList(
      args['connectionTypes'],
      'connectionTypes',
    );
    final includeAnchors = args['includeAnchors'] as bool? ?? false;
    final rawAnchorNames = _rawDivineNamesArg(args);

    final book = _findLinksTextBook(library, args);
    if (book == null) throw Exception('error.not_found: book not found');

    final links = await _linksRepository.getBookLinksInRange(
      book,
      startIndex: startLine,
      endIndex: endLine,
      // צמצום ב-SQL רק כשאין תחיליות — SQL מכיר רק כותרות מלאות, וצמצום
      // לפי targetTitles לבדו היה מפיל את התאמות התחילית.
      targetBookTitles: targetTitlePrefixes == null ? targetTitles : null,
    );

    // העוגנים נמדדים על השורה המלאה; התוסף מקבל את הטקסט השמור, בלי גופי ההערות.
    final notes = includeAnchors
        ? await BookNotesRepository.instance.notesFor(
            book.title,
            categoryId: book.categoryId,
            source: book.source,
            fileType: book.fileType,
            versionTitle: book.versionTitle,
          )
        : BookNotes.empty;
    final anchorNames = includeAnchors
        ? await PluginDivineNamesFilter.resolve(
            book: book,
            readerState: _openReaderStateFor(book),
            raw: rawAnchorNames,
          )
        : PluginDivineNamesDisplay.raw;

    final filtered = _filterLinkRecords(
      links,
      targetTitles: targetTitles,
      targetTitlePrefixes: targetTitlePrefixes,
      connectionTypes: connectionTypes,
      maxRecords: _pluginLinksMaxRecords,
      // index1/index2 הם 1-based במודל; ה-wire של getLinks 0-based — זו
      // נקודת ההמרה. getRawLinks נשאר 1-based, כמוסכמת links.json.
      toRecord: (link, targetTitle) => {
        'sourceLine': link.index1 - 1,
        'targetTitle': targetTitle,
        'targetLine': link.index2 - 1,
        'targetLineEnd': link.index2End == null ? null : link.index2End! - 1,
        'targetHeRef': link.heRef,
        'connectionType': link.connectionType,
        'isCommentary': LinkTypes.isDependentTextLink(link.connectionType),
        'targetIsUserBook': link.targetIsUserBook,
        'targetSource': link.targetSource.wireKey,
        'targetCategoryId': link.targetCategoryId,
        if (includeAnchors)
          ...?_linkAnchorJson(
            link,
            notes.notesAt(link.index1 - 1),
            anchorNames,
          ),
      },
    );
    return {'links': filtered.records, 'truncated': filtered.truncated};
  }

  /// `library.getRawLinks` — אותם קישורים של [_getLinks], בחמשת המפתחות של
  /// פורמט `links.json` ובחלון שורות רחב יותר, לייצוא בכמויות.
  Future<dynamic> _getRawLinks(
    Library library,
    Map<String, dynamic> args,
  ) async {
    final rawStart = args['startLine'];
    final rawEnd = args['endLine'];
    // "שניהם או אף אחד", כמו ב-getCommentators. גבול בודד היה מחזיר בשקט חלון
    // שלא ביקשו: endLine לבדו נקרא כ-0..endLine ונחתך לתקרת החלון.
    if ((rawStart == null) != (rawEnd == null)) {
      throw Exception(
        'error.invalid_params: startLine and endLine must be given together',
      );
    }

    final int startLine;
    final int endLine;
    if (rawStart == null) {
      startLine = 0;
      endLine = _pluginRawLinksMaxWindowLines - 1;
    } else {
      startLine = _requireWireLine(rawStart, 'startLine');
      endLine = _requireWireLine(rawEnd, 'endLine');
      if (endLine < startLine) {
        throw Exception('error.invalid_params: endLine must be >= startLine');
      }
      if (endLine - startLine + 1 > _pluginRawLinksMaxWindowLines) {
        throw Exception(
          'error.invalid_params: line window must not exceed '
          '$_pluginRawLinksMaxWindowLines lines',
        );
      }
    }

    final targetTitles = _optionalStringList(
      args['targetTitles'],
      'targetTitles',
    );
    final targetTitlePrefixes = _optionalStringList(
      args['targetTitlePrefixes'],
      'targetTitlePrefixes',
    );
    final connectionTypes = _optionalStringList(
      args['connectionTypes'],
      'connectionTypes',
    );

    final book = _findLinksTextBook(library, args);
    if (book == null) throw Exception('error.not_found: book not found');

    final links = await _linksRepository.getBookLinksInRange(
      book,
      startIndex: startLine,
      endIndex: endLine,
      targetBookTitles: targetTitlePrefixes == null ? targetTitles : null,
    );

    final filtered = _filterLinkRecords(
      links,
      targetTitles: targetTitles,
      targetTitlePrefixes: targetTitlePrefixes,
      connectionTypes: connectionTypes,
      maxRecords: _pluginRawLinksMaxRecords,
      toRecord: (link, _) => link.toJson(),
    );
    return {
      'links': filtered.records,
      'truncated': filtered.truncated,
      'startLine': startLine,
      'endLine': endLine,
    };
  }

  /// הסינון המשותף ל-`getLinks` ול-`getRawLinks`, כדי ששתיהן יחזירו בדיוק את
  /// אותה קבוצת קישורים ויישארו כאלה. כל קישור שעבר מומר דרך [toRecord].
  ({List<Map<String, dynamic>> records, bool truncated}) _filterLinkRecords(
    List<Link> links, {
    required List<String>? targetTitles,
    required List<String>? targetTitlePrefixes,
    required List<String>? connectionTypes,
    required int maxRecords,
    required Map<String, dynamic> Function(Link link, String targetTitle)
    toRecord,
  }) {
    final titlesFilter = targetTitles?.toSet();
    final typesFilter = connectionTypes?.map(LinkTypes.normalize).toSet();
    final records = <Map<String, dynamic>>[];
    var truncated = false;
    for (final link in links) {
      final targetTitle = getTitleFromPath(link.path2);
      if (!_titleAllowed(targetTitle, titlesFilter, targetTitlePrefixes)) {
        continue;
      }
      if (typesFilter != null &&
          !typesFilter.contains(LinkTypes.normalize(link.connectionType)) &&
          !typesFilter.contains(LinkTypes.canonicalType(link.connectionType))) {
        continue;
      }
      if (records.length >= maxRecords) {
        truncated = true;
        break;
      }
      records.add(toRecord(link, targetTitle));
    }
    return (records: records, truncated: truncated);
  }

  /// העוגן הראשון של [link] בטקסט השמור של השורה ([notes] — הערותיה); עוגן
  /// שכולו בגוף הערה אינו מוחזר.
  Map<String, dynamic>? _linkAnchorJson(
    Link link,
    List<BookNote> notes,
    PluginDivineNamesDisplay names,
  ) {
    final spans = linkAnchorSpans(link);
    final span =
        (link.anchorOffsetsAreRaw ? spans : projectAnchorSpans(spans, notes))
            .firstOrNull;
    if (span == null) return null;
    return {
      'anchor': {
        'start': span.start,
        'end': span.end,
        'label': switch (span.label) {
          final label? => filterPluginDivineNamesText(label, names),
          null => null,
        },
      },
    };
  }

  Future<dynamic> _getLinkTargetsSummary(
    Library library,
    Map<String, dynamic> args,
  ) async {
    final targetTitles = _optionalStringList(
      args['targetTitles'],
      'targetTitles',
    );
    final targetTitlePrefixes = _optionalStringList(
      args['targetTitlePrefixes'],
      'targetTitlePrefixes',
    );
    final book = _findLinksTextBook(library, args);
    if (book?.categoryId == null) {
      throw Exception('error.not_found: book not found');
    }
    final source = book!.source;
    final provider =
        _dependencies.linkTargetsSummaryProvider ??
        (title, categoryId) => DatabaseLibraryProvider.instance
            .getBookLinkTargetsSummary(title, categoryId, source: source);
    final summary = await provider(book.title, book.categoryId!);
    if (summary == null) {
      throw Exception('error.internal: link targets summary unavailable');
    }
    final titlesFilter = targetTitles?.toSet();
    return {
      'targets': [
        for (final target in summary.targets)
          if (_titleAllowed(
            target.targetTitle,
            titlesFilter,
            targetTitlePrefixes,
          ))
            {
              'targetTitle': target.targetTitle,
              'connectionType': target.connectionType,
              'linkCount': target.linkCount,
            },
      ],
      // maxSourceLine מגיע 1-based מהמסד; -1 = לספר אין קישורים כלל.
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
    final rawNames = _rawDivineNamesArg(args);
    final loader = _dependencies.linkContentLoader;
    final linesLoader =
        _dependencies.linkContentLinesLoader ??
        (loader == null ? (Link link) => link.contentLines : null);
    // הגדרות המפרשים של הכרטיסייה חלות רק על מפרשים של הספר שפתוח בה.
    final boundState = readerTab?.bloc.state;
    final readerState = boundState is TextBookLoaded ? boundState : null;
    final readerTargets = {
      ...?readerState?.availableCommentators,
      for (final link in readerState?.links ?? const <Link>[])
        getTitleFromPath(link.path2),
    };
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
        targetSource: BookSource.fromJson(
          raw,
          key: 'targetSource',
          legacyUserFlagKey: 'targetIsUserBook',
        ),
      );
      final targetBook = TextBook(
        title: targetTitle,
        categoryId: link.targetCategoryId,
        source: link.targetSource,
      );
      if (await _isTextRestricted(targetBook)) {
        items.add(const {'error': 'forbidden'});
        continue;
      }
      try {
        final names = await PluginDivineNamesFilter.resolve(
          book: targetBook,
          readerState: readerTargets.contains(targetTitle) ? readerState : null,
          target: TextTarget.commentary,
          raw: rawNames,
        );
        final String content;
        if (linesLoader != null) {
          final lines = await linesLoader(link);
          final spans = names.filters
              ? await PluginDivineNamesFilter.spansFor(targetBook)
              : DivineNameSpans.empty;
          content = [
            for (final line in lines)
              filterPluginDivineNamesLine(
                line.content,
                line.lineIndex,
                spans,
                names,
              ),
          ].join('<br>');
        } else {
          content = filterPluginDivineNamesText(await loader!(link), names);
        }
        items.add({'content': content});
      } catch (_) {
        items.add(const {'error': 'not_found'});
      }
    }
    return {'items': items};
  }

  /// טוען את מבני ה-AltToc של ספר (דרך התלות המוזרקת או ה-DB).
  Future<List<AltTocStructure>> _loadAltStructures(TextBook book) {
    final provider =
        _dependencies.altStructuresProvider ??
        DatabaseLibraryProvider.instance.getAlternativeStructuresForBook;
    return provider(book);
  }

  /// טוען את ערכי מבנה ה-AltToc עם ה-lineIndex (דרך התלות המוזרקת או ה-DB).
  Future<List<AltTocEntryRow>> _loadAltTocEntries(AltTocStructure structure) {
    final provider = _dependencies.altTocEntriesProvider;
    if (provider != null) return provider(structure.id);
    return DatabaseLibraryProvider.instance.getAltTocEntriesWithLineIndex(
      structure.id,
      source: structure.source,
    );
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

  /// כמו [_categoryToTree], אבל רק עם ספרים שה-`type` שלהם ב-[types].
  /// מחזיר `null` כשאין תחת [category] אף ספר מתאים, כך שענף ריק נגזם עוד
  /// לפני שנבנה עבורו אובייקט. העבודה היא מעבר אחד על הקטלוג שכבר בזיכרון,
  /// ומה שחוצה את הגשר הוא רק תת-העץ הגזום.
  Map<String, dynamic>? _categoryToFilteredTree(
    Category category, {
    required Set<String> types,
    required bool includeBooks,
  }) {
    final children = <Map<String, dynamic>>[];
    for (final sub in category.subCategories) {
      final node = _categoryToFilteredTree(
        sub,
        types: types,
        includeBooks: includeBooks,
      );
      if (node != null) children.add(node);
    }
    final books = category.books
        .where((b) => types.contains(PluginBookIdentity.typeOf(b)))
        .toList();
    if (children.isEmpty && books.isEmpty) return null;
    return {
      'title': category.title,
      'path': category.path,
      'categories': children,
      if (includeBooks) 'books': books.map(_bookToTreeEntry).toList(),
    };
  }

  /// `library.openBookFile` — מוסר לתוסף את הקובץ שמאחורי ספר בספרייה, כ-token
  /// של קובץ משתמש רגיל (resolve/commit/revoke עובדים עליו). הקובץ אינו מועתק:
  /// הנתיב הקיים נרשם בשרת הקבצים.
  ///
  /// כתיבה מותרת לספר אישי בלבד. ספר של הספרייה משותף לכל עדכון ספרייה עתידי,
  /// ושמירה במקום הייתה נדרסת בעדכון הבא — או גרוע מזה, משנה את מה שכל
  /// המשתמשים רואים כ"ספר".
  Future<Map<String, dynamic>> _openBookFile(
    Library library,
    Map<String, dynamic> args,
  ) async {
    _requireBookIdentity(args);
    final writable = _parseUserFileAccess(args);
    final book = _findPluginBook(library, args);
    if (book == null) throw Exception('error.not_found: book not found');
    if (book is! FileBook) {
      throw Exception('error.unsupported: book has no local file');
    }
    final source = PluginBookIdentity.sourceOf(book);
    if (writable) {
      if (source != 'user') {
        throw Exception('error.permission_denied: library books are read-only');
      }
      await _requireWritePermission();
    }
    final canonical = canonicalizeNearestExisting(
      resolveMovedFileBookPath(book.path),
    );
    if (canonical == null || !await File(canonical).exists()) {
      throw Exception('error.not_found: book file does not exist');
    }
    final grant = await _grantUserFile(canonical, writable: writable);
    return {
      'token': grant.token,
      'url': grant.url,
      'name': p.basename(canonical),
      'size': await File(canonical).length(),
      'access': grant.writable ? 'readwrite' : 'read',
      'source': source,
    };
  }

  // ----------------------------------------------------------------
  // Book identity helpers (Plugin SDK)
  // ----------------------------------------------------------------

  Book? _findPluginBook(Library library, Map<String, dynamic> args) {
    final bound = readerTab?.book;
    final uid = args['bookUid'] as String?;
    if (bound != null &&
        ((uid != null && uid == PluginBookIdentity.uidOf(bound)) ||
            (uid == null &&
                PluginBookIdentity.parseId(args['id']) == bound.id &&
                bound.id != null)) &&
        PluginBookIdentity.matches(
          bound,
          id: PluginBookIdentity.parseId(args['id']),
          bookId: (args['bookId'] ?? args['title']) as String?,
          type: args['type'] as String?,
          source: args['source'] as String?,
        )) {
      return bound;
    }
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

  static void _requireBookIdentity(Map<String, dynamic> args) {
    if (PluginBookIdentity.parseId(args['id']) == null &&
        (args['bookId'] ?? args['title']) == null &&
        (args['bookUid'] as String?)?.trim().isNotEmpty != true) {
      throw Exception('error.invalid_params: id, bookUid or bookId required');
    }
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
        final rawNames = _rawDivineNamesArg(args);
        if (query == null || query.isEmpty) return [];
        final results = await _dependencies.searchRepository.searchTexts(
          SearchEngineRequest(query: query, facets: [], limit: limit),
        );
        _ensureBookIndex(await DataRepository.instance.library);
        final restrictedByPath = <String, bool>{};
        for (final result in results) {
          if (result.isPdf || restrictedByPath.containsKey(result.filePath)) {
            continue;
          }
          restrictedByPath[result.filePath] = await _isTextRestricted(
            _booksByIndexedPath[result.filePath] ??
                TextBook(title: result.title),
          );
        }
        final namesByPath = await _searchResultNames(
          results.map((r) => (filePath: r.filePath, title: r.title)),
          _booksByIndexedPath,
          raw: rawNames,
        );
        return results.map((r) {
          final isRestricted =
              !r.isPdf && (restrictedByPath[r.filePath] ?? false);
          return {
            'type': r.isPdf ? 'pdf' : 'text',
            'book': r.title,
            'text': isRestricted
                ? ''
                : filterPluginDivineNamesText(
                    removeAttachedMarks(r.text),
                    namesByPath[r.filePath]!,
                  ),
            'textStatus': r.textStatus.name,
            'continuesToNextLine': r.continuesToNextLine,
            'index': r.segment.toInt(),
            if (isRestricted) 'error': 'forbidden',
          };
        }).toList();
      case 'getOptions':
        return PluginSearchApi.describeOptions();
      case 'setFieldText':
      case 'setFieldActionState':
      case 'endFieldSession':
        return _handleSearchFieldSession(action, args);
      case 'query':
        if (args[_cancelStreamIdKey] case final String streamId) {
          return _cancelStream(
            streamId,
            _activeSearchStreams,
            _pendingSearchCancellations,
          );
        }
        return await _runPluginSearch(args, eventSink: eventSink);
      default:
        throw Exception(
          "error.unknown_method: Unknown action in search: $action",
        );
    }
  }

  /// הצגת השמות בתקצירי [results], לפי ספר — כמו בתוצאות החיפוש של התוכנה.
  Future<Map<String, PluginDivineNamesDisplay>> _searchResultNames(
    Iterable<({String filePath, String title})> results,
    Map<String, Book> booksByPath, {
    required bool raw,
  }) async {
    final names = <String, PluginDivineNamesDisplay>{};
    for (final (:filePath, :title) in results) {
      if (names.containsKey(filePath)) continue;
      final book = booksByPath[filePath];
      names[filePath] = await PluginDivineNamesFilter.resolve(
        book: book ?? TextBook(title: title),
        readerState: book == null ? null : _openReaderStateFor(book),
        raw: raw,
      );
    }
    return names;
  }

  /// `search.setFieldText` / `setFieldActionState` / `endFieldSession`.
  bool _handleSearchFieldSession(String action, Map<String, dynamic> args) {
    final sessionId = args['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw Exception('error.invalid_params: sessionId required');
    }
    final sessions = _searchFieldSessions;
    try {
      switch (action) {
        case 'setFieldText':
          sessions.setFieldText(
            plugin.pluginId,
            sessionId,
            args['text'],
            instanceId: instanceId,
          );
        case 'setFieldActionState':
          sessions.setActionState(
            plugin.pluginId,
            sessionId,
            args['state'],
            tooltip: args['tooltip'],
            instanceId: instanceId,
          );
        default:
          final submit = args['submit'];
          if (submit != null && submit is! bool) {
            throw Exception('error.invalid_params: submit must be boolean');
          }
          sessions.endSession(
            plugin.pluginId,
            sessionId,
            submit: submit == true,
            instanceId: instanceId,
          );
      }
    } on PluginSearchFieldSessionException catch (error) {
      throw Exception(error.toString());
    }
    return true;
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

    final rawNames = _rawDivineNamesArg(args);
    final publicArgs = Map<String, dynamic>.of(args)
      ..remove(_streamIdKey)
      ..remove('rawDivineNames');
    final request = PluginSearchRequest.fromArgs(publicArgs)
      ..validateAgainstQuery();
    final library = await DataRepository.instance.library;
    final facets = PluginSearchApi.resolveFacets(
      publicArgs,
      findBook: (identity) => _findPluginBook(library, identity),
    );
    final stream = _dependencies.searchRepository.searchTextsStreamWithCounts(
      SearchEngineRequest(
        query: request.sanitizedQuery,
        facets: facets,
        limit: request.limit,
        offset: request.offset,
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
        anyOrder: request.anyOrder,
      ),
      chunkSize: 50,
    );
    final vocalizedSearch = SearchQueryBuilder.optionsRequestVocalized(
      request.effectiveSearchOptions,
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
    final restrictedByPath = <String, bool>{};
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
        for (final result in update.results) {
          if (result.isPdf || restrictedByPath.containsKey(result.filePath)) {
            continue;
          }
          restrictedByPath[result.filePath] = await _isTextRestricted(
            booksByPath[result.filePath] ?? TextBook(title: result.title),
          );
        }
        final namesByPath = await _searchResultNames(
          update.results.map((r) => (filePath: r.filePath, title: r.title)),
          booksByPath,
          raw: rawNames,
        );
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
                  textRestricted: restrictedByPath[result.filePath] ?? false,
                  vocalizedSearch: vocalizedSearch,
                  filterText: (text) => filterPluginDivineNamesText(
                    text,
                    namesByPath[result.filePath]!,
                  ),
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

  // ----------------------------------------------------------------
  // reader.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleReader(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'getDefaultTextReader':
        final registry = PluginTextReaderRegistry.instance;
        return {
          'pluginId': registry.selectedPluginId,
          'enabled': registry.selectedPluginId == plugin.pluginId,
          'available': registry.activePlugin != null,
        };
      case 'setDefaultTextReader':
        final enabled = args['enabled'];
        if (enabled is! bool) {
          throw Exception('error.invalid_params: enabled must be boolean');
        }
        final check =
            _dependencies.hasUserActivation ?? _defaultHasUserActivation;
        if (instanceId == PluginInstanceIds.background ||
            !await check(plugin.pluginId, instanceId)) {
          throw Exception('error.forbidden: Requires a user gesture');
        }
        final granted = await _getGrantedPermissions();
        if (!plugin.enabled ||
            !plugin.hasToolPage ||
            !PluginTextReaderRegistry.requiredPermissions.every(
              granted.contains,
            )) {
          throw Exception(
            'error.forbidden: Reader and library permissions required',
          );
        }
        await PluginTextReaderRegistry.instance.select(plugin, enabled);
        return {'enabled': enabled};
      case 'setTextReaderFontSize':
        final tab = _requireEmbeddedTextReader();
        final size = args['fontSize'];
        if (size is! num || !size.isFinite || size < 14 || size > 60) {
          throw Exception(
            'error.invalid_params: fontSize must be between 14 and 60',
          );
        }
        tab.bloc.add(UpdateFontSize(size.toDouble()));
        return true;
      case 'reportTextReaderLocation':
        final tab = _requireEmbeddedTextReader();
        final index = args['index'];
        if (index is! int || index < 0) {
          throw Exception('error.invalid_params: index must be nonnegative');
        }
        tab.lines.reportExternalLine(index);
        final ref = args['ref'];
        if (ref is String && ref.length <= 500) tab.currentTitle.value = ref;
        _windowDependencies.tabsBloc.add(const SaveTabs());
        return true;
      case 'openBook':
        // spec: openBook({ id?, bookId?, type?, index?, searchQuery?,
        //   navigateToPositionIfReused?, matchPages?, matchedTerms? })
        // also accepts legacy 'title' for back-compat; all supplied identity fields must match.
        {
          final index = (args['index'] as num?)?.toInt() ?? 0;
          final searchQuery = args['searchQuery'] as String? ?? '';
          final navigateToPositionIfReused =
              args['navigateToPositionIfReused'] as bool? ?? false;
          final openInSidePane = args['openInSidePane'] as bool? ?? false;
          final externalMatches = _parseExternalMatches(args, searchQuery);
          if (args['external'] == null) _requireBookIdentity(args);
          if (args['external'] != null && args['reader'] != 'native') {
            final access = DeclarativeLibraryBookAccess.otzaria(
              _windowDependencies.bookOpenCoordinator,
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
          final book = args['external'] != null
              ? (await DeclarativeLibraryBookAccess.otzaria(
                  _windowDependencies.bookOpenCoordinator,
                ).findUniqueBooks([_identityFields(args)])).single
              : _findPluginBook(
                  await DataRepository.instance.library,
                  args,
                );
          if (book == null) return false;
          if (args['reader'] == 'native' && book is TextBook) {
            final registry = PluginTextReaderRegistry.instance;
            final coordinator = _windowDependencies.bookOpenCoordinator;
            final tab = coordinator.buildTab(
              book,
              index,
              searchQuery,
              ignoreHistory: true,
            );
            if (tab is TextBookTab) registry.useNative(tab);
            for (final existing
                in _windowDependencies.tabsBloc.state.tabs
                    .expand(leafPanes)
                    .whereType<TextBookTab>()) {
              if (PluginBookIdentity.uidOf(existing.book) ==
                  PluginBookIdentity.uidOf(book)) {
                registry.useNative(existing);
              }
            }
            coordinator.openTab(
              tab,
              navigateToPositionIfReused: true,
              inSidePane: openInSidePane,
            );
            return true;
          }
          _windowDependencies.bookOpenCoordinator.openBook(
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
        // החיפוש (מצב, מרחק, מדיניות התאמה, אפשרויות מילה, שלילה והיקף)
        // בדיוק כמו search.query — ראה PluginOpenSearchTabSettings.
        {
          final query = (args['query'] as String? ?? '').trim();
          if (query.isEmpty || query.length > 500) {
            throw Exception('error.invalid_params: query required');
          }
          final autoSearch = args['autoSearch'] as bool? ?? true;
          final selectItems = (args['selectItems'] as List? ?? const [])
              .whereType<String>()
              .where((id) => RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(id))
              .take(4)
              .toList();
          final rawSettings = args['settings'];
          // הקטלוג נדרש רק כדי לאתר ספרים בהיקף.
          final library = rawSettings is Map && rawSettings['books'] != null
              ? await DataRepository.instance.library
              : null;
          final settings = PluginOpenSearchTabSettings.parse(
            rawSettings,
            query: query,
            findBook: library == null
                ? null
                : (identity) => _findPluginBook(library, identity),
          );
          return openPluginSearchTab(
            coordinator: _windowDependencies.bookOpenCoordinator,
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
          final ref = args['ref'] as String?;
          int index = (args['index'] as num?)?.toInt() ?? 0;
          final highlight = args['highlight'] as bool? ?? false;
          _requireBookIdentity(args);
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
                  _windowDependencies.bookOpenCoordinator.openBook(
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
                    .where(
                      (h) =>
                          h.title == resolvedBookId &&
                          h.source == book.source &&
                          !h.isPdf,
                    )
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
          _windowDependencies.bookOpenCoordinator.openBook(
            book,
            index,
            refFound ? '' : (ref ?? ''),
            ignoreHistory: true,
            markSection: highlight && refFound,
            requiresStableLayout: book is PdfBook,
          );
          return true;
        }
      case 'printRange':
        // spec: printRange({ id?, bookUid?, bookId?, type?, startIndex, endIndex?, commentators? })
        // התוסף אינו מקבל טקסט; המסך נפתח רק מתוך מחוות משתמש.
        {
          final startIndex = _nonNegativeIntArg(args['startIndex']);
          if (startIndex == null) {
            throw Exception(
              'error.invalid_params: startIndex must be a non-negative integer',
            );
          }
          final rawEnd = args['endIndex'];
          final endIndex = rawEnd == null ? null : _nonNegativeIntArg(rawEnd);
          if (rawEnd != null && (endIndex == null || endIndex <= startIndex)) {
            throw Exception(
              'error.invalid_params: endIndex must be an integer greater than '
              'startIndex',
            );
          }
          _requireBookIdentity(args);
          final rawCommentators = args['commentators'];
          if (args.containsKey('commentators') &&
              (rawCommentators is! List ||
                  rawCommentators.length > 256 ||
                  rawCommentators.any(
                    (name) => name is! String || name.trim().isEmpty,
                  ))) {
            throw Exception(
              'error.invalid_params: commentators must be an array of non-empty names',
            );
          }
          final requestedCommentators = rawCommentators == null
              ? null
              : (rawCommentators as List)
                    .cast<String>()
                    .map((name) => name.trim())
                    .toSet()
                    .toList();
          return await _runUserGatedDialog(() async {
            final book = _findPluginBook(
              await DataRepository.instance.library,
              args,
            );
            if (book == null) {
              throw Exception('error.not_found: book not found');
            }
            if (book is! TextBook) {
              throw Exception(
                'error.unsupported: printRange supports text books only',
              );
            }
            final available =
                await (_dependencies.textBookRepository ??
                        TextBookRepository(fileSystem: FileSystemData.instance))
                    .getAvailableCommentators(book);
            final pane = _windowDependencies.tabsBloc.state.readingPane;
            final state =
                pane is TextBookTab &&
                    PluginBookIdentity.uidOf(pane.book) ==
                        PluginBookIdentity.uidOf(book)
                ? pane.bloc.state
                : null;
            final active =
                requestedCommentators ??
                (state is TextBookLoaded
                    ? state.activeCommentators
                          .where(available.contains)
                          .toList()
                    : available);
            if (requestedCommentators != null &&
                active.any((name) => !available.contains(name))) {
              throw Exception('error.not_found: unknown commentators');
            }
            final show = _dependencies.printBookRange ?? _defaultPrintBookRange;
            final printed = await show(
              book,
              startLine: startIndex,
              endLine: endIndex,
              activeCommentators: active,
              availableCommentators: available,
            );
            return {'printed': printed};
          });
        }
      case 'getCurrentState':
        final tabsState = _windowDependencies.tabsBloc.state;
        final tabs = tabsState.tabs;
        final panes = tabs.map(_paneForPlugins).toList();
        // Use the same resolver as getCurrentRef for consistent currentRef values
        final snapshots = await Future.wait(panes.map(resolveReaderLocation));
        final openTabs = List.generate(tabs.length, (i) {
          final t = panes[i];
          // טאב שאינו ספר (חיפוש, כלי, תוסף) — id/type = null
          final tabBook = t is TextBookTab
              ? t.book
              : (t is PdfBookTab ? t.book : null);
          return {
            'toolId': t is ToolTab ? t.toolId : null,
            'tabId': t is TextBookTab
                ? PluginCorrectionSessionService.tabIdFor(t)
                : null,
            'correctionSessionId': t is TextBookTab
                ? PluginCorrectionSessionService.instance.sessionIdForTab(
                    plugin.pluginId,
                    PluginCorrectionSessionService.tabIdFor(t),
                  )
                : null,
            'isSelf':
                t is ToolTab &&
                t.toolId == plugin.pluginId &&
                t.instanceId == instanceId,
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
            'currentTabId': null,
            'currentCorrectionSessionId': null,
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
          'currentTabId': currentPane is TextBookTab
              ? PluginCorrectionSessionService.tabIdFor(currentPane)
              : null,
          'currentCorrectionSessionId': currentPane is TextBookTab
              ? PluginCorrectionSessionService.instance.sessionIdForTab(
                  plugin.pluginId,
                  PluginCorrectionSessionService.tabIdFor(currentPane),
                )
              : null,
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
      case 'closeTab':
        // spec: closeTab({ index }) — האינדקס ברשימת openTabs של getCurrentState.
        {
          final target = _tabAt(args);
          final unsaved = [
            ...unsavedPluginTabs([target]),
            ...await unpersistedCorrectionTabs([target]),
          ];
          if (unsaved.isNotEmpty) {
            final confirmed = await _dependencies.showWarningDialog(
              title: unsavedChangesDialogTitle,
              content: unsavedChangesDialogContent(unsaved),
              subtitle: unsavedChangesDialogSubtitle,
            );
            if (!confirmed) return false;
          }
          _windowDependencies.tabsBloc.add(RemoveTab(target));
          return true;
        }
      case 'activateTab':
        // spec: activateTab({ index })
        {
          final tabsBloc = _windowDependencies.tabsBloc;
          tabsBloc.add(
            SetCurrentTab(tabsBloc.state.tabs.indexOf(_tabAt(args))),
          );
          return true;
        }
      case 'getCurrentRef':
        final snapshot = await resolveReaderLocation(
          _windowDependencies.tabsBloc.state.readingPane,
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
      case 'getPageShapeLayout':
        return _getPageShapeLayout();
      case 'setPageShapeCommentatorVisibility':
        return _setPageShapeCommentatorVisibility(args);
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
            _windowDependencies.tabsBloc,
          ).scrollToSection(sectionIndex, highlight: args['highlight'] == true);
        }
      case 'getSelection':
        final currentPane = _windowDependencies.tabsBloc.state.readingPane;
        final paneState = currentPane is TextBookTab
            ? currentPane.bloc.state
            : null;
        if (currentPane is TextBookTab &&
            !(paneState is TextBookLoaded && paneState.showPageShapeView) &&
            PluginCorrectionSessionService.instance.hasSessionForTab(
              PluginCorrectionSessionService.tabIdFor(currentPane),
            )) {
          throw const PluginCorrectionException(
            'error.unsupported_context',
            'בחירה בנוסח מתוקן אינה ניתנת למיפוי בטוח למקור.',
          );
        }
        final rawNames = _rawDivineNamesArg(args);
        final snapshot = await resolveReaderLocation(currentPane);
        return _buildCurrentSelection(
          currentPane,
          snapshot?.currentRef,
          rawNames: rawNames,
        );
      case 'findTextOccurrences':
        return _findTextOccurrences(args);
      case 'getSectionTextMap':
        return _getSectionTextMap(args);
      case 'beginCorrectionSession':
        return _beginCorrectionSession(args);
      case 'getCorrectionSession':
        return _correctionSessionAction(action, args);
      case 'restoreCorrectionDraft':
        return _correctionSessionAction(action, args);
      case 'resetCorrection':
        return _correctionSessionAction(action, args);
      case 'endCorrectionSession':
        return _correctionSessionAction(action, args);
      case 'acknowledgeCorrectionDraft':
      case 'listCorrectionDrafts':
      case 'getCorrectionDraft':
        return _correctionDraftAction(action, args);
      case 'addContextMenuItem':
        _requireMultipleInstancesForNewTab(args);
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
        _requireMultipleInstancesForNewTab(Map<String, dynamic>.from(patch));
        ContextMenuRegistry.instance.update(
          plugin.pluginId,
          id,
          Map<String, dynamic>.from(patch),
          instanceId: instanceId,
        );
        await _trackWhenStorageKeys(Map<String, dynamic>.from(patch));
        return true;
      case 'addToolbarItem':
        _requireMultipleInstancesForNewTab(args);
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
        _requireMultipleInstancesForNewTab(Map<String, dynamic>.from(patch));
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
        final book = allBooks.cast<dynamic>().firstWhere((item) {
          if (item == null) return false;
          if (highlightUid != null && highlightUid.isNotEmpty) {
            return PluginBookIdentity.uidOf(item as Book) == highlightUid;
          }
          return item.title == highlight.bookId;
        }, orElse: () => null);
        if (book == null) return false;
        _windowDependencies.bookOpenCoordinator.openBook(
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

  /// טאב הספר שבו התוסף הזה מוצג כרגע כקורא הטקסט.
  TextBookTab _requireEmbeddedTextReader() {
    final tab = readerTab;
    final registry = PluginTextReaderRegistry.instance;
    if (tab == null ||
        instanceId == PluginInstanceIds.background ||
        !registry.usesPlugin(tab) ||
        registry.activePlugin?.pluginId != plugin.pluginId ||
        tab.bloc.isClosed) {
      throw Exception('error.unavailable: Not an active embedded text reader');
    }
    return tab;
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
    final rawNames = args['rawDivineNames'] ?? false;
    if (bookId is! String ||
        bookId.isEmpty ||
        sectionIndex is! int ||
        query is! String ||
        layer is! String ||
        limit is! int ||
        rawNames is! bool ||
        (cursor != null && cursor is! String)) {
      throw const PluginTextOccurrenceException(
        'error.invalid_params',
        'bookId, sectionIndex, and query are required',
      );
    }
    if (layer == 'rendered' &&
        PluginCorrectionSessionService.instance.hasSessionForBook(
          bookId,
          args['bookUid'] is String ? args['bookUid'] as String : null,
        )) {
      throw const PluginCorrectionException(
        'error.unsupported_context',
        'חיפוש בנוסח המתוקן אינו ניתן למיפוי בטוח למקור.',
      );
    }
    final section = await _loadPluginTextSection(
      bookId,
      sectionIndex,
      bookUid: args['bookUid'] as String?,
      rawNames: rawNames,
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

  /// [rawText] נושא את סמני השמות, ולכן השכבה המוצגת מחליפה אותם לפי
  /// [RenderSettings]; שכבת המקור (הטקסט בלי התגים) נשארת כפי שנשמרה.
  Future<({String rawText, RenderSettings settings, String? currentRef})>
  _loadPluginTextSection(
    String bookId,
    int sectionIndex, {
    String? bookUid,
    bool rawNames = false,
  }) async {
    if (sectionIndex < 0) {
      throw const PluginTextOccurrenceException(
        'error.invalid_params',
        'sectionIndex must be non-negative',
      );
    }
    final uid = bookUid?.trim();
    // `bookUid` מזהה מדויק; בהיעדרו הזיהוי לפי כותרת.
    bool matchesBook(Book b) => uid != null && uid.isNotEmpty
        ? PluginBookIdentity.uidOf(b) == uid
        : b.title == bookId;
    // סריקת חלוניות ולא טאבים: ספר שיושב רק בחלונית של טאב מפוצל לא נמצא,
    // והקריאה נפלה למסלול ה-DB שמאבד את מצב הניקוד החי. החלונית הפעילה
    // ראשונה, כי אותו ספר בשתי חלוניות יכול להיות בהגדרות ניקוד שונות.
    final activePane = _windowDependencies.tabsBloc.state.readingPane;
    final panes = <OpenedTab>[
      ?activePane,
      ..._windowDependencies.tabsBloc.state.tabs.expand(leafPanes),
    ];
    for (final tab in panes) {
      if (tab is! TextBookTab || !matchesBook(tab.book)) continue;
      final state = tab.bloc.state;
      if (state is! TextBookLoaded || sectionIndex >= state.content.length) {
        continue;
      }
      if (state.protection.isProtected) {
        throw const PluginTextOccurrenceException(
          'error.forbidden',
          _restrictedTextMessage,
        );
      }
      final snapshot =
          identical(tab, _windowDependencies.tabsBloc.state.readingPane) &&
              tab.index == sectionIndex
          ? await resolveReaderLocation(tab)
          : null;
      final profile = PluginDivineNamesFilter.readerProfile(state);
      return (
        rawText: injectDivineNameMarkers(
          state.content[sectionIndex],
          state.divineNames,
          sectionIndex,
        ),
        settings: RenderSettings.fromProfile(
          rawNames ? PluginDivineNamesDisplay.raw.applyTo(profile) : profile,
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
    if (await _isTextRestricted(book)) {
      throw const PluginTextOccurrenceException(
        'error.forbidden',
        _restrictedTextMessage,
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
    final profile = await PluginDivineNamesFilter.bookProfile(book);
    return (
      rawText: rawNames
          ? range.lines.first
          : injectDivineNameMarkers(
              range.lines.first,
              await PluginDivineNamesFilter.spansFor(book),
              sectionIndex,
            ),
      settings: RenderSettings.fromProfile(
        rawNames ? PluginDivineNamesDisplay.raw.applyTo(profile) : profile,
      ),
      currentRef: null,
    );
  }

  TextBookTab _correctionTab(String id) {
    for (final tab in _windowDependencies.tabsBloc.state.tabs.expand(
      leafPanes,
    )) {
      if (tab is TextBookTab &&
          PluginCorrectionSessionService.tabIdFor(tab) == id) {
        return tab;
      }
    }
    throw const PluginCorrectionException(
      'error.not_found',
      'לשונית הספר אינה פתוחה.',
    );
  }

  /// ה-id נפתר לעיתים רק ב-state של ה-bloc, ולכן הספר נלקח משם ולא מהלשונית.
  Future<TextBook> _requireCorrectionContext(TextBookTab tab) async {
    final state = tab.bloc.state;
    final reason = state is! TextBookLoaded
        ? 'הספר עדיין לא נטען. נסו שוב לאחר הטעינה.'
        : state.showPageShapeView
        ? 'עריכה בתוך הספר אינה נתמכת בצורת הדף. עברו למפרשים בצד או מתחת.'
        : PluginTextReaderRegistry.instance.usesPlugin(tab)
        ? 'עריכה בתוך הספר אינה נתמכת בקורא שמופעל באמצעות תוסף.'
        : !state.book.isOfficialLibraryBook
        ? 'עריכה בתוך הספר נתמכת בספרים מהספרייה הרשמית בלבד.'
        : state.book.id == null
        ? 'לספר אין מזהה במסד הספרייה הרשמי ולכן לא ניתן לאמת תיקונים.'
        : state.book.versionTitle != null
        ? 'עריכה בתוך הספר אינה נתמכת במהדורה חלופית של ספריא.'
        : null;
    if (reason != null) {
      throw PluginCorrectionException('error.unsupported_context', reason);
    }
    final book = (state as TextBookLoaded).book;
    await _ensureBookTextAvailable(book);
    return book;
  }

  Future<void> _requireCorrectionPermission() async {
    if (!plugin.enabled ||
        !(await _getGrantedPermissions()).contains('reader.local_edit')) {
      throw const PluginCorrectionException(
        'error.permission_denied',
        'חסרה הרשאת תיקון מקומי.',
      );
    }
  }

  Future<Map<String, dynamic>> _beginCorrectionSession(
    Map<String, dynamic> args,
  ) async {
    if (args.length != 1 ||
        args['tabId'] is! String ||
        (args['tabId'] as String).isEmpty) {
      throw const PluginCorrectionException(
        'error.invalid_params',
        'נדרש tabId של לשונית ספר.',
      );
    }
    final ownerEpoch = PluginCorrectionSessionService.instance.ownerEpoch(
      plugin.pluginId,
    );
    await _requireCorrectionPermission();
    final id = args['tabId'] as String;
    final tab = _correctionTab(id);
    final resolved = await BookDatabaseResolver.resolveBookById(
      (await _requireCorrectionContext(tab)).id!,
    );
    if (resolved == null ||
        !resolved.source.isOfficial ||
        resolved.book.isFileBacked) {
      throw const PluginCorrectionException(
        'error.unsupported_context',
        'נדרש מקור במסד הספרייה הרשמי.',
      );
    }
    final version = await DataCollectionService().readLibraryVersion();
    if (version == 'unknown' || version.trim().isEmpty) {
      throw const PluginCorrectionException(
        'error.source_changed',
        'גרסת הספרייה אינה מזוהה.',
      );
    }
    await _requireCorrectionPermission();
    if (!identical(_correctionTab(id), tab)) {
      throw const PluginCorrectionException(
        'error.not_found',
        'לשונית הספר נסגרה.',
      );
    }
    final book = await _requireCorrectionContext(tab);
    await _requireCorrectionPermission();
    if (!identical(_correctionTab(id), tab)) {
      throw const PluginCorrectionException(
        'error.not_found',
        'לשונית הספר נסגרה.',
      );
    }
    final result = await PluginCorrectionSessionService.instance.begin(
      owner: plugin.pluginId,
      ownerName: plugin.name,
      tabId: id,
      bookId: book.title,
      bookUid: PluginBookIdentity.uidOf(book),
      bookSource: PluginBookIdentity.sourceOf(book),
      libraryVersion: version,
      ownerEpoch: ownerEpoch,
      validateSource: () async {
        final currentVersion = await DataCollectionService()
            .readLibraryVersion();
        if (currentVersion != version) {
          throw const PluginCorrectionException(
            'error.source_changed',
            'גרסת הספרייה השתנתה.',
          );
        }
        await _requireCorrectionPermission();
        await _requireCorrectionContext(_correctionTab(id));
      },
      loadSource: (index) async {
        await _requireCorrectionContext(_correctionTab(id));
        final lines = await DbReadWorker.lines(
          SqliteDataProvider.instance.dbPath,
          resolved.book.id,
          index,
          index,
        );
        if (lines.length != 1) {
          throw const PluginCorrectionException(
            'error.not_found',
            'פסקת המקור אינה קיימת.',
          );
        }
        await _requireCorrectionPermission();
        await _requireCorrectionContext(_correctionTab(id));
        return lines.single.content;
      },
      onEvent: (topic, payload) {
        final injected = _dependencies.dispatchEventToPlugin;
        unawaited(
          injected != null
              ? injected(plugin.pluginId, topic, payload)
              : PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
                  plugin.pluginId,
                  topic,
                  payload,
                  preferBackground: false,
                  resumeForegroundIfNeeded: true,
                ),
        );
      },
    );
    // קריאה חוזרת לאותה לשונית מחזירה snapshot בלבד; הצורה נשמרת אחידה.
    return {...result, 'recovery': result['recovery']};
  }

  Future<Map<String, dynamic>> _correctionSessionAction(
    String action,
    Map<String, dynamic> args,
  ) async {
    final keys = switch (action) {
      'getCorrectionSession' => const {'sessionId'},
      'restoreCorrectionDraft' => const {
        'sessionId',
        'expectedRevision',
        'bookUid',
        'libraryVersion',
        'changes',
      },
      'resetCorrection' => const {
        'sessionId',
        'expectedRevision',
        'sectionIndex',
      },
      _ => const {'sessionId', 'expectedRevision'},
    };
    if (args.keys.any((key) => !keys.contains(key)) ||
        args['sessionId'] is! String ||
        (action != 'getCorrectionSession' &&
            args['expectedRevision'] is! int)) {
      throw const PluginCorrectionException(
        'error.invalid_params',
        'נתוני הסשן אינם תקינים.',
      );
    }
    await _requireCorrectionPermission();
    final service = PluginCorrectionSessionService.instance;
    final id = args['sessionId'] as String;
    final owner = plugin.pluginId;
    final tab = _windowDependencies.tabsBloc.state.tabs
        .expand(leafPanes)
        .whereType<TextBookTab>()
        .where(
          (tab) =>
              service.sessionIdForTab(
                owner,
                PluginCorrectionSessionService.tabIdFor(tab),
              ) ==
              id,
        )
        .firstOrNull;
    if (tab == null) {
      throw const PluginCorrectionException(
        'error.not_found',
        'סשן התיקון אינו זמין לתוסף.',
      );
    }
    if (action == 'endCorrectionSession') {
      await _ensureBookTextAvailable(tab.book);
      await _requireCorrectionPermission();
      return service.end(owner, id, args['expectedRevision'] as int);
    }
    if (action == 'getCorrectionSession') {
      await _ensureBookTextAvailable(tab.book);
      await _requireCorrectionPermission();
      return service.get(owner, id);
    }
    await _requireCorrectionContext(tab);
    await _requireCorrectionPermission();
    final tabId = PluginCorrectionSessionService.tabIdFor(tab);
    if (!identical(_correctionTab(tabId), tab)) {
      throw const PluginCorrectionException(
        'error.not_found',
        'לשונית הספר נסגרה.',
      );
    }
    final revision = args['expectedRevision'] as int;
    // לא דרך get: הוא ממתין לשמירה ושולח אירוע ממתין.
    if (action == 'resetCorrection') {
      if (args['sectionIndex'] is! int) {
        throw const PluginCorrectionException(
          'error.invalid_params',
          'נדרש אינדקס פסקה.',
        );
      }
      return service.reset(owner, id, args['sectionIndex'] as int, revision);
    }
    if (args['bookUid'] is! String ||
        args['libraryVersion'] is! String ||
        args['changes'] is! List) {
      throw const PluginCorrectionException(
        'error.invalid_params',
        'נדרשת טיוטה עם זהות מקור.',
      );
    }
    return service.restore(
      owner: owner,
      id: id,
      expectedRevision: revision,
      bookUid: args['bookUid'] as String,
      libraryVersion: args['libraryVersion'] as String,
      changes: args['changes'] as List<dynamic>,
    );
  }

  /// טיוטות התוסף עצמו בלבד; פועל גם אחרי שהסשן והלשונית נסגרו.
  Future<Map<String, dynamic>> _correctionDraftAction(
    String action,
    Map<String, dynamic> args,
  ) async {
    final keys = switch (action) {
      'acknowledgeCorrectionDraft' => const {'draftId', 'version'},
      'getCorrectionDraft' => const {'draftId'},
      _ => const <String>{},
    };
    final draftId = args['draftId'];
    final version = args['version'];
    if (args.length != keys.length ||
        args.keys.any((key) => !keys.contains(key)) ||
        (keys.contains('draftId') && (draftId is! String || draftId.isEmpty)) ||
        (keys.contains('version') && (version is! int || version < 0))) {
      throw const PluginCorrectionException(
        'error.invalid_params',
        'נתוני הטיוטה אינם תקינים.',
      );
    }
    await _requireCorrectionPermission();
    final service = PluginCorrectionSessionService.instance;
    final owner = plugin.pluginId;
    return switch (action) {
      'acknowledgeCorrectionDraft' => await service.acknowledge(
        owner,
        draftId as String,
        version as int,
      ),
      'getCorrectionDraft' => await service.getDraft(owner, draftId as String),
      _ => {'drafts': await service.listDrafts(owner)},
    };
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
    final rawNames = args['rawDivineNames'] ?? false;
    if (bookId is! String ||
        bookId.isEmpty ||
        sectionIndex is! int ||
        layer is! String ||
        includeWords is! bool ||
        includeChars is! bool ||
        includeSourceMap is! bool ||
        includeDomRects is! bool ||
        limit is! int ||
        rawNames is! bool ||
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
    if ((layer == 'rendered' || layer == 'both' || includeSourceMap) &&
        PluginCorrectionSessionService.instance.hasSessionForBook(
          bookId,
          args['bookUid'] is String ? args['bookUid'] as String : null,
        )) {
      throw const PluginCorrectionException(
        'error.unsupported_context',
        'מיפוי הנוסח המתוקן אינו נתמך; יש לבקש את שכבת המקור.',
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
      rawNames: rawNames,
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
  // workspace.*
  // ----------------------------------------------------------------
  Future<dynamic> _handleWorkspace(
    String action,
    Map<String, dynamic> args,
  ) async {
    final bloc = _windowDependencies.workspaceBloc;
    switch (action) {
      case 'list':
        final activeId = bloc.state.activeWorkspaceId;
        return bloc.state.workspaces
            .map(
              (workspace) => {
                'id': workspace.id,
                'name': workspace.name,
                'isActive': workspace.id == activeId,
                'tabCount': bloc.state
                    .tabsOf(workspace, _windowDependencies.tabsBloc.state.tabs)
                    .length,
              },
            )
            .toList();
      case 'getActive':
        final active = bloc.state.activeWorkspace;
        return {'id': active?.id, 'name': active?.name};
      case 'create':
        final name = (args['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) {
          throw Exception('error.invalid_params: name required');
        }
        if (name.length > _workspaceNameMaxLength) {
          throw Exception(
            'error.invalid_params: name exceeds '
            '$_workspaceNameMaxLength characters',
          );
        }
        final switchTo = args['switchTo'] as bool? ?? false;
        final reuseExisting = args['reuseExisting'] as bool? ?? false;
        if (reuseExisting) {
          for (final workspace in bloc.state.workspaces) {
            if (workspace.name.trim() != name) continue;
            if (switchTo && !await _switchWorkspace(workspace.id)) {
              throw Exception('error.internal: failed to switch workspace');
            }
            return {'id': workspace.id, 'created': false};
          }
        }
        final created = await _createWorkspace(name);
        if (created == null) {
          throw Exception('error.internal: failed to create workspace');
        }
        if (switchTo && !await _switchWorkspace(created.id)) {
          throw Exception('error.internal: failed to switch workspace');
        }
        return {'id': created.id, 'created': true};
      case 'switch':
        final id = (args['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) {
          throw Exception('error.invalid_params: id required');
        }
        // שולחן שאינו קיים אינו שגיאת ארגומנט: תוסף שמסנכרן בין מחשבים מקבל
        // מזהה מהצד השני ונופל בחזרה ל-create לפי השם.
        if (!bloc.state.workspaces.any((workspace) => workspace.id == id)) {
          return false;
        }
        return await _switchWorkspace(id);
      default:
        throw Exception(
          'error.unknown_method: Unknown workspace action: $action',
        );
    }
  }

  /// יוצר שולחן עבודה חדש ומחזיר אותו. ה-`AddWorkspace` אינו מחזיר את המזהה
  /// שנוצר, ולכן מאתרים אותו במצב הראשון שבו נוסף שולחן שלא היה קודם.
  Future<Workspace?> _createWorkspace(String name) async {
    final bloc = _windowDependencies.workspaceBloc;
    final knownIds = bloc.state.workspaces
        .map((workspace) => workspace.id)
        .toSet();
    bool hasNew(WorkspaceState state) =>
        state.workspaces.any((workspace) => !knownIds.contains(workspace.id));
    final state = await _awaitWorkspaceState(
      hasNew,
      () => bloc.add(
        AddWorkspace(name: name, tabs: const [], currentTabIndex: 0),
      ),
    );
    if (state == null) return null;
    return state.workspaces.lastWhere(
      (workspace) => !knownIds.contains(workspace.id),
    );
  }

  /// מעבר לשולחן [id] באותו רצף שהדיאלוג מבצע
  /// (`lib/workspaces/view/workspace_switcher_dialog.dart`): הטאבים הנוכחיים
  /// נמסרים לאירוע כי ה-UI הוא מקור האמת עליהם — בלעדיהם המעבר מוחק אותם.
  /// נמסרת רשימת הטאבים **המלאה**, כולל `ToolTab`, ולא הרשימה שהתוסף רואה.
  Future<bool> _switchWorkspace(String id) async {
    final bloc = _windowDependencies.workspaceBloc;
    if (bloc.state.activeWorkspaceId == id) return true;
    final tabsState = _windowDependencies.tabsBloc.state;
    final state = await _awaitWorkspaceState(
      (workspaceState) => workspaceState.activeWorkspaceId == id,
      () => bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: id,
          currentTabsToSave: tabsState.tabs,
          currentTabIndexToSave: tabsState.currentTabIndex,
        ),
      ),
    );
    return state != null;
  }

  /// מפעיל [trigger] וממתין למצב הראשון שמקיים [test]. פעולות שולחן עבודה
  /// עוברות דרך אירוע ואינן מחזירות ערך, ולכן ה-API ממתין למצב במקום להניח
  /// שהאירוע כבר טופל. מחזיר `null` על שגיאה מהבלוק או על פסק זמן.
  Future<WorkspaceState?> _awaitWorkspaceState(
    bool Function(WorkspaceState state) test,
    void Function() trigger,
  ) async {
    final bloc = _windowDependencies.workspaceBloc;
    final settled = bloc.stream.firstWhere(
      (state) => test(state) || state.error != null,
      orElse: () => bloc.state,
    );
    trigger();
    try {
      final state = await settled.timeout(_workspaceActionTimeout);
      return test(state) ? state : null;
    } on TimeoutException {
      return null;
    }
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
            ToolsLauncherController.instance.open(
              windowKeys: _windowDependencies.windowKeys,
            );
            return true;
          case 'settings':
            screen = Screen.settings;
            break;
          default:
            throw Exception(
              "error.invalid_params: Invalid navigation target: $target. Valid: library, reading, more, settings",
            );
        }
        _windowDependencies.navigationBloc.add(NavigateToScreen(screen));
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
  /// מפתח ההערות מה-wire: `bookUid` נפתר לספר ולמפתח לפי מקורו (ספר ממסד
  /// מצורף); אחרת `bookId` כמות שהוא, כמו מפתח שהוחזר מ-getBookNotesSummary.
  Future<String?> _notesBookKey(Map<String, dynamic> args) async {
    final bookUid = (args['bookUid'] as String?)?.trim();
    if (bookUid != null && bookUid.isNotEmpty) {
      _ensureBookIndex(await DataRepository.instance.library);
      final book = _booksByUid[bookUid];
      if (book != null) return personalNotesBookKey(book);
    }
    return args['bookId'] as String?;
  }

  Future<dynamic> _handleNotes(String action, Map<String, dynamic> args) async {
    final repo = _dependencies.personalNotesRepository;
    switch (action) {
      case 'list':
        final bookId = await _notesBookKey(args);
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
        final bookId = await _notesBookKey(args);
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
        final bookId = await _notesBookKey(args);
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
        final bookId = await _notesBookKey(args);
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
          window: _windowDependencies.windowKeys,
          onTap: _messageTapHandler(args),
        );
        return true;
      case 'showSuccess':
        UiSnack.showSuccess(
          args['message'] as String? ?? '',
          window: _windowDependencies.windowKeys,
          onTap: _messageTapHandler(args),
        );
        return true;
      case 'showError':
        UiSnack.showError(
          args['message'] as String? ?? '',
          window: _windowDependencies.windowKeys,
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
      case 'setUnsavedChanges':
        // spec: setUnsavedChanges({ hasChanges, message? }) — סגירת הכרטיסיה
        // תעבור דרך דיאלוג אישור כל עוד הדגל דלוק.
        final hasChanges = args['hasChanges'];
        if (hasChanges is! bool) {
          throw Exception('error.invalid_params: hasChanges must be boolean');
        }
        PluginUnsavedChangesRegistry.instance.set(
          (pluginId: plugin.pluginId, instanceId: instanceId),
          hasChanges: hasChanges,
          message: args['message'] as String?,
        );
        return true;
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
        final canonical = canonicalizeNearestExisting(path);
        if (canonical == null) {
          throw Exception('error.forbidden: selected folder no longer exists');
        }
        _grantedFolders.add(canonical);
        return {'path': path};
      case 'print':
        final printer = _dependencies.printPluginPage ?? _defaultPrintPage;
        final jobName = (args['jobName'] as String?)?.trim();
        final printLayout = _parsePdfLayout(args);
        return await _runUserGatedDialog(() async {
          final printed = await printer(
            plugin.pluginId,
            instanceId,
            jobName: jobName == null || jobName.isEmpty
                ? plugin.manifest.toolTabTitle
                : jobName,
            layout: printLayout,
          );
          return {'printed': printed};
        });
      case 'printFile':
        return await _printGrantedPdf(args);
      case 'exportPdf':
        final capture =
            _dependencies.capturePluginPagePdf ?? _defaultCapturePagePdf;
        final saver =
            _dependencies.pickSaveLocation ?? _defaultPickSaveLocation;
        final suggested = pluginSaveFileName(
          args['fileName'] as String?,
          'pdf',
        );
        final layout = _parsePdfLayout(args);
        return await _runUserGatedDialog(() async {
          final pdf = await capture(
            plugin.pluginId,
            instanceId,
            layout: layout,
          );
          final chosen = await saver(
            suggestedName: suggested,
            allowedExtensions: const ['pdf'],
            title: args['title'] as String?,
          );
          if (chosen == null || chosen.isEmpty) {
            return {'saved': false, 'name': null};
          }
          // בורר המיקום ניתן להזרקה, וחוזהו אינו מבטיח שהסיומת תושלם.
          final target = chosen.toLowerCase().endsWith('.pdf')
              ? chosen
              : '$chosen.pdf';
          await File(target).writeAsBytes(pdf, flush: true);
          // הנתיב עצמו אינו מוחזר — התוסף אינו מקבל גישה למה שנשמר.
          return {'saved': true, 'name': p.basename(target)};
        });
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
      final viewId = _windowDependencies.viewId;
      final windowKeys = _windowDependencies.windowKeys;
      // ניווט לדף התוסף עם מסירת האירוע — כמו openPlugin בתפריט ההקשר.
      return () => PluginPageLauncher.instance.open(
        plugin.pluginId,
        topic: topic,
        payload: payload,
        viewId: viewId,
        windowKeys: windowKeys,
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
  Future<String?> _defaultPickFolder({String? title}) async {
    final context = rpcWindowContext;
    if (context == null || !context.mounted) return null;
    final windowsOptions = modalWindowsOptions(context);
    if (!await verifySaferModePassword(context)) {
      return null;
    }
    if (!context.mounted) return null;
    return withFilePickerOwner(
      context,
      (picker) => picker.getDirectoryPath(
        windowsOptions: windowsOptions,
        linuxOptions: kModalLinuxOptions,
        dialogTitle: title,
      ),
    );
  }

  /// דיאלוג הדפסה/שמירה פתוח כרגע עבור המופע הזה. שער חד-בו-זמנית: בלעדיו
  /// לולאה בתוסף מערימה דיאלוגים מודאליים עד שהחלון אינו שמיש.
  bool _userDialogOpen = false;

  /// `ui.printFile` — מסך ההדפסה של אוצריא (טווח עמודים, תצוגה מקדימה, עימוד
  /// ואז דיאלוג ההדפסה של המערכת) על PDF שהוענק לתוסף: token של
  /// `fs.pickUserFile`, `fs.openFolderFile` או `network.fetchFile`. התוסף אינו
  /// מקבל את התוכן.
  ///
  /// מחוות המשתמש נדרשת, כמו ב-`reader.printRange`, אף ש"הדפס" הסופי נלחץ
  /// בתוך דיאלוג של האפליקציה שהמשתמש יכול לסגור: המסך מודאלי וחוסם את החלון
  /// הראשי כולו (`barrierDismissible: false`), ובלי השער תוסף ברקע היה מקפיץ
  /// אותו מיוזמתו, בטעינת הדף או בלולאה.
  Future<Map<String, dynamic>> _printGrantedPdf(
    Map<String, dynamic> args,
  ) async {
    final token = args['token'];
    if (token is! String || token.isEmpty) {
      throw Exception('error.invalid_params: token required');
    }
    final rawJobName = args['jobName'];
    if (rawJobName != null && rawJobName is! String) {
      throw Exception('error.invalid_params: jobName must be a string');
    }
    final canonical = await _resolveGrantedFilePath(token);
    if (!_remoteFiles.ownsCanonical(canonical, pluginId: plugin.pluginId) &&
        await _pluginRepo.getPermission(
              plugin.pluginId,
              'fs.user_files.read',
            ) !=
            true) {
      throw Exception(
        'error.permission_denied: fs.user_files.read is required',
      );
    }
    // סיומת `.pdf` אינה מבטיחה PDF (דף שגיאה של שרת נשמר גם הוא בשם הזה), ומסך
    // ההדפסה על קובץ כזה נפתח בלי תצוגה אבל עם כפתור "הדפס" פעיל.
    if (p.extension(canonical).toLowerCase() != '.pdf' ||
        !await _startsLikePdf(canonical)) {
      throw Exception('error.unsupported: printFile supports PDF files only');
    }
    final jobName = _printJobName(
      rawJobName as String?,
      fallback: p.basename(canonical),
    );
    final show = _dependencies.printPluginFile ?? _defaultPrintPluginFile;
    return await _runUserGatedDialog(() async {
      final printed = await show(File(canonical), jobName: jobName);
      return {'printed': printed};
    });
  }

  /// האם `%PDF-` מופיע ב-1024 הבייטים הראשונים — כפי שקוראי PDF דורשים.
  Future<bool> _startsLikePdf(String path) async {
    try {
      final file = await File(path).open();
      try {
        return latin1
            .decode(await file.read(1024), allowInvalid: true)
            .contains('%PDF-');
      } finally {
        await file.close();
      }
    } on FileSystemException {
      // בלי הנתיב: הגשר מחזיר לתוסף את הודעת החריגה כמות שהיא.
      throw Exception('error.unavailable: the file could not be read');
    }
  }

  static const int _maxJobNameLength = 120;

  /// שם עבודת ההדפסה שהתוסף ביקש: בלי תווי בקרה, עד [_maxJobNameLength]
  /// תווים (לפי תווים שלמים, לא חצאי זוגות surrogate). הוא מוצג בכותרת המסך
  /// ומשמש שם עבודה ושם קובץ מוצע בייצוא.
  String _printJobName(String? raw, {required String fallback}) {
    final cleaned = (raw ?? '')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '')
        .trim();
    if (cleaned.isEmpty) return fallback;
    final runes = cleaned.runes;
    return runes.length <= _maxJobNameLength
        ? cleaned
        : String.fromCharCodes(runes.take(_maxJobNameLength)).trim();
  }

  /// מריץ פעולה שפותחת דיאלוג מערכת — רק בתוך חלון הפעולה של המשתמש, ורק
  /// אחת בכל רגע. מונע מתוסף לפתוח דיאלוגים או לכתוב קבצים מיוזמתו.
  Future<Map<String, dynamic>> _runUserGatedDialog(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    if (_userDialogOpen) {
      throw Exception('error.forbidden: A system dialog is already open');
    }
    // הדגל נקבע לפני ה-await הראשון: שתי קריאות רצופות היו שתיהן עוברות את
    // הבדיקה לפני שהראשונה סימנה.
    _userDialogOpen = true;
    try {
      final check =
          _dependencies.hasUserActivation ?? _defaultHasUserActivation;
      if (!await check(plugin.pluginId, instanceId)) {
        throw Exception(
          'error.forbidden: Requires a user gesture — call it directly from a '
          'click handler',
        );
      }
      return await action();
    } finally {
      _userDialogOpen = false;
    }
  }

  /// דיאלוג אישור לפתיחת [uri] בדפדפן. אחד בכל רגע, כמו דיאלוגי המערכת.
  Future<bool> _confirmOpenUrl(Uri uri) async {
    if (_userDialogOpen) {
      throw Exception('error.forbidden: A system dialog is already open');
    }
    _userDialogOpen = true;
    try {
      final url = uri.toString();
      final shown = url.length > 300 ? '${url.substring(0, 300)}…' : url;
      return await _dependencies.showConfirmDialog(
        title: 'פתיחת קישור חיצוני',
        content:
            'התוסף "${plugin.name}" מבקש לפתוח בדפדפן כתובת באתר '
            '${uri.host}:\n$shown\n\nהכתובת יכולה להעביר לאתר מידע מתוך התוסף.',
      );
    } finally {
      _userDialogOpen = false;
    }
  }

  /// ה-WebView של המופע, או חריגה אם אינו חי (טאב שנסגר באמצע).
  InAppWebViewController _requireController(
    String pluginId,
    String instanceId,
  ) {
    final controller = PluginRuntimeDispatcher.instance.controllerOf(
      pluginId,
      instanceId: instanceId,
    );
    if (controller == null) {
      throw Exception('error.forbidden: Plugin view is not available');
    }
    return controller;
  }

  /// נקרא ישירות על ה-WebView ולא מקבל את התשובה מה-JS של התוסף — הערך הזה
  /// הוא מצב דפדפן לקריאה בלבד ולכן אינו ניתן לזיוף מתוך התוסף.
  Future<bool> _defaultHasUserActivation(
    String pluginId,
    String instanceId,
  ) async {
    final result = await _requireController(pluginId, instanceId)
        .evaluateJavascript(
          source:
              "(navigator.userActivation === undefined) ? 'unsupported' : "
              "(navigator.userActivation.isActive ? 'active' : 'inactive')",
        );
    // WKWebView אינו מממש את navigator.userActivation; שם אין מה לאכוף.
    return result != 'inactive';
  }

  /// מסך ההדפסה של הקורא מעל חלון הבקשה (`reader.printRange`).
  Future<bool> _defaultPrintBookRange(
    TextBook book, {
    required int startLine,
    int? endLine,
    required List<String> activeCommentators,
    required List<String> availableCommentators,
  }) async {
    final toc = await book.tableOfContents;
    final context =
        rpcWindowContext ??
        (_windowDependencies.windowKeys?.navigator ?? navigatorKey)
            .currentContext;
    if (context == null || !context.mounted) {
      throw Exception('error.unavailable: No window to show the print screen');
    }
    final printed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrintingScreen(
        data: _loadBookRawText(book),
        bookId: book.title,
        book: book,
        startLine: startLine,
        endLine: endLine,
        tableOfContents: toc,
        activeCommentators: activeCommentators,
        availableCommentators: availableCommentators,
      ),
    );
    return printed ?? false;
  }

  /// קורא את קובץ ה-PDF לפני פתיחת מסך ההדפסה בחלון הבקשה.
  Future<bool> _defaultPrintPluginFile(
    File file, {
    required String jobName,
  }) async {
    final context =
        rpcWindowContext ??
        (_windowDependencies.windowKeys?.navigator ?? navigatorKey)
            .currentContext;
    if (context == null || !context.mounted) {
      throw Exception('error.unavailable: No window to show the print screen');
    }
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      // בלי הנתיב: הגשר מחזיר לתוסף את הודעת החריגה כמות שהיא.
      throw Exception('error.unavailable: the file could not be read');
    }
    if (!context.mounted) {
      throw Exception('error.unavailable: No window to show the print screen');
    }
    final printed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrintingScreen(
        data: Future.value(''),
        // במסלול ה-PDF בלבד: תווית להצגה, לשם עבודת ההדפסה ולשם הקובץ בייצוא.
        bookId: jobName,
        createPdfOverride: (_) async => bytes,
      ),
    );
    return printed ?? false;
  }

  /// מספר שלם אי-שלילי מפרמטר JSON (גם 3.0), או null.
  static int? _nonNegativeIntArg(Object? value) {
    if (value is! num || value < 0 || value != value.truncate()) return null;
    return value.toInt();
  }

  Future<bool> _defaultPrintPage(
    String pluginId,
    String instanceId, {
    required String jobName,
    PluginPdfLayout? layout,
  }) => const PluginPrintService().printWebView(
    _requireController(pluginId, instanceId),
    jobName: jobName,
    layout: layout,
    context: rpcWindowContext,
  );

  Future<Uint8List> _defaultCapturePagePdf(
    String pluginId,
    String instanceId, {
    PluginPdfLayout? layout,
  }) => const PluginPrintService().createPdf(
    _requireController(pluginId, instanceId),
    layout: layout,
  );

  /// גדלי דף נתמכים ב-`ui.exportPdf` וב-`ui.print`, במילימטרים (רוחב, גובה) לאורך.
  static const _pdfPageSizesMm = <String, (double, double)>{
    'a4': (210, 297),
    'a5': (148, 210),
    'letter': (215.9, 279.4),
    'legal': (215.9, 355.6),
  };

  /// גבולות שפיות למידות דף חופשיות ב-`pageSize` (מ"מ). התחתון מתחת ל-0.5
  /// אינץ' (12.7 מ"מ) והעליון מעל 200 אינץ' — מסמכי DOCX חוקיים לא ייחסמו,
  /// ורק תשובה שאינה מידה (אפס, שלילי, אלפי מ"מ) נדחית.
  static const _minPageMm = 10.0;
  static const _maxPageMm = 5080.0;

  /// מפרש את ארגומנטי העימוד של `ui.exportPdf` ו-`ui.print`: `pageSize` (שם קבוע או מפה
  /// `{widthMm, heightMm}` למידות חופשיות), `orientation`, `marginMm` (מספר
  /// או מפה לפי צד) ו-`printBackgrounds`. null כשלא סופק דבר.
  PluginPdfLayout? _parsePdfLayout(Map<String, dynamic> args) {
    final sizeArg = args['pageSize'];
    final orientation = (args['orientation'] as String?)?.trim().toLowerCase();
    final margin = args['marginMm'];
    final backgrounds = args['printBackgrounds'];
    if (sizeArg == null &&
        orientation == null &&
        margin == null &&
        backgrounds == null) {
      return null;
    }

    (double, double)? size;
    if (sizeArg is String) {
      size = _pdfPageSizesMm[sizeArg.trim().toLowerCase()];
      if (size == null) {
        throw Exception(
          'error.invalid_params: unknown pageSize (supported: '
          '${_pdfPageSizesMm.keys.join(', ')}, or {widthMm, heightMm})',
        );
      }
    } else if (sizeArg is Map) {
      double dimMm(Object? v, String name) {
        if (v is! num || v.isNaN || v < _minPageMm || v > _maxPageMm) {
          throw Exception(
            'error.invalid_params: $name must be $_minPageMm-$_maxPageMm (mm)',
          );
        }
        return v.toDouble();
      }

      size = (
        dimMm(sizeArg['widthMm'], 'pageSize.widthMm'),
        dimMm(sizeArg['heightMm'], 'pageSize.heightMm'),
      );
    } else if (sizeArg != null) {
      throw Exception(
        'error.invalid_params: pageSize must be a preset name or a '
        '{widthMm, heightMm} map',
      );
    }

    bool? landscape;
    if (orientation != null) {
      if (orientation != 'portrait' && orientation != 'landscape') {
        throw Exception(
          "error.invalid_params: orientation must be 'portrait' or 'landscape'",
        );
      }
      landscape = orientation == 'landscape';
    }

    double sideMm(Object? v, String name) {
      if (v is! num || v.isNaN || v < 0 || v > 100) {
        throw Exception('error.invalid_params: $name must be 0-100 (mm)');
      }
      return v.toDouble();
    }

    EdgeInsets? marginsMm;
    if (margin != null) {
      if (margin is num) {
        marginsMm = EdgeInsets.all(sideMm(margin, 'marginMm'));
      } else if (margin is Map) {
        marginsMm = EdgeInsets.fromLTRB(
          sideMm(margin['left'] ?? 0, 'marginMm.left'),
          sideMm(margin['top'] ?? 0, 'marginMm.top'),
          sideMm(margin['right'] ?? 0, 'marginMm.right'),
          sideMm(margin['bottom'] ?? 0, 'marginMm.bottom'),
        );
      } else {
        throw Exception(
          'error.invalid_params: marginMm must be a number or a per-side map',
        );
      }
    }

    if (backgrounds != null && backgrounds is! bool) {
      throw Exception('error.invalid_params: printBackgrounds must be a bool');
    }

    return PluginPdfLayout(
      pageWidthMm: size?.$1,
      pageHeightMm: size?.$2,
      marginsMm: marginsMm,
      landscape: landscape,
      printBackgrounds: backgrounds as bool?,
    );
  }

  /// בודקת אם [targetPath] נמצא בתוך תיקייה שהמשתמש אישר — חד-פעמית דרך
  /// `ui.pickFolder` בריצה הזו, או לצמיתות דרך `fs.pickUserFolder` (הרשאה
  /// קבועה כוללת את החד-פעמית).
  ///
  /// זהו גבול האבטחה לכל פעולות הכתיבה/מחיקה לדיסק של התוסף. הבדיקה מתבצעת על
  /// הנתיב הקנוני (אחרי פתרון symlinks) של **שני** הצדדים — היעד והתיקייה
  /// המאושרת — כדי לנטרל גם `..` (path-traversal) וגם symlink שמצביע מתוך
  /// תיקייה מאושרת אל מחוץ לה. בלי פתרון ה-symlink בדיקת [p.isWithin] על המחרוזת
  /// בלבד הייתה מאשרת כתיבה/מחיקה מחוץ לתיקייה דרך קישור סימבולי.
  ///
  /// בהיעדר התאמה להרשאה חד-פעמית, התיקיות הקבועות נקראות מה-KV כדי שביטול
  /// ממסך ההגדרות יחול גם על תוסף שרץ כרגע.
  Future<bool> _isPathInGrantedFolder(
    String targetPath, {
    bool allowRoot = true,
  }) async {
    final canonicalTarget = canonicalizeNearestExisting(targetPath);
    if (canonicalTarget == null) return false;
    bool inside(String root) {
      final canonicalRoot = canonicalizeNearestExisting(root);
      if (canonicalRoot == null || !p.equals(canonicalRoot, root)) return false;
      return (allowRoot && p.equals(canonicalTarget, canonicalRoot)) ||
          p.isWithin(canonicalRoot, canonicalTarget);
    }

    if (_grantedFolders.any(inside)) return true;
    final grants = await _folderGrants.list(plugin.pluginId);
    return grants.any((grant) => inside(grant.path));
  }

  Future<void> _requireInGrantedFolder(
    String path, {
    bool allowRoot = true,
  }) async {
    if (!await _isPathInGrantedFolder(path, allowRoot: allowRoot)) {
      throw Exception('error.forbidden: path outside a user-selected folder');
    }
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
        await _requireInGrantedFolder(zipPath);
        await _requireInGrantedFolder(destFolder);
        await _fsService.extractZip(zipPath, destFolder);
        return true;
      case 'deleteFile':
        final path = args['path'] as String?;
        if (path == null) {
          throw Exception('error.invalid_params: path required');
        }
        await _requireInGrantedFolder(path);
        await _fsService.deleteFile(path);
        return true;
      case 'deleteFolder':
        final folderPath = args['path'] as String?;
        if (folderPath == null) {
          throw Exception('error.invalid_params: path required');
        }
        await _requireInGrantedFolder(folderPath, allowRoot: false);
        await _fsService.deleteFolder(folderPath);
        return true;
      case 'moveEntry':
        final from = args['from'] as String?;
        final to = args['to'] as String?;
        if (from == null || to == null) {
          throw Exception('error.invalid_params: from and to required');
        }
        await _requireInGrantedFolder(from, allowRoot: false);
        await _requireInGrantedFolder(to, allowRoot: false);
        await _fsService.moveEntry(from, to);
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
      case 'pickUserFolder':
        return await _pickUserFolder(args);
      case 'listUserFolder':
        return await _listUserFolder(args);
      case 'openFolderFile':
        return await _openFolderFile(args);
      case 'revokeFolder':
        final folderToken = args['folderToken'];
        if (folderToken is! String || folderToken.isEmpty) {
          throw Exception('error.invalid_params: folderToken required');
        }
        await _folderGrants.revoke(plugin.pluginId, folderToken);
        return true;
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
        // קובץ שהורד ל-`network.fetchFile` נמחק עם ביטול ה-token שלו.
        final revoked = await _loadUserFileGrant(token);
        await _removeUserFileGrant(token);
        if (revoked != null &&
            _remoteFiles.ownsCanonical(
              revoked.path,
              pluginId: plugin.pluginId,
            )) {
          await _remoteFiles.delete(revoked.path);
        }
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
    final context = rpcWindowContext;
    if (context == null || !context.mounted) return null;
    final windowsOptions = modalWindowsOptions(context);
    if (!await verifySaferModePassword(context)) {
      return null;
    }
    final hasExtensions =
        allowedExtensions != null && allowedExtensions.isNotEmpty;
    if (!context.mounted) return null;
    final result = await withFilePickerOwner(
      context,
      (picker) => picker.pickFile(
        dialogTitle: title,
        windowsOptions: windowsOptions,
        linuxOptions: kModalLinuxOptions,
        type: hasExtensions ? FileType.custom : FileType.any,
        allowedExtensions: hasExtensions ? allowedExtensions : null,
      ),
    );
    return result?.path;
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
    final writable = _parseUserFileAccess(args);
    if (writable) await _requireWritePermission();
    final access = writable ? 'readwrite' : 'read';

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

  /// קורא את `access` של פתיחת קובץ משתמש ומחזיר האם התבקשה כתיבה.
  ///
  /// ברירת המחדל נשארת קריאה: תוסף ותיק שאינו מכיר את השדה מקבל בדיוק מה
  /// שקיבל תמיד.
  bool _parseUserFileAccess(Map<String, dynamic> args) {
    final access = args['access'] as String? ?? 'read';
    if (access != 'read' && access != 'readwrite') {
      throw Exception(
        "error.invalid_params: access must be 'read' or 'readwrite'",
      );
    }
    return access == 'readwrite';
  }

  /// בקשת כתיבה דורשת גם את הרשאת הכתיבה, בנוסף להרשאת הקריאה שהגשר כבר
  /// אכף — היא תלויה בארגומנט, ולכן נאכפת כאן ולא בטבלת ההרשאות.
  Future<void> _requireWritePermission() async {
    if (!await _hasWritePermission()) {
      throw Exception(
        'error.permission_denied: fs.user_files.write is required for readwrite access',
      );
    }
  }

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
        // מטמוני getBookContent של כל מופעי התוסף מתעדכנים בקריאה הבאה.
        _bookContentRevision++;
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
          rawExtension != null &&
              RegExp(r'^\.?[a-z0-9]{1,10}$').hasMatch(rawExtension)
          ? rawExtension.replaceAll('.', '')
          : null;
      final suggested = pluginSaveFileName(
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

  Future<T> _enqueueWorkspaceAction<T>(Future<T> Function() action) {
    final result = _workspaceActionQueue.then((_) => action());
    _workspaceActionQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// „שמור בשם” בשני שלבים: בחירת תיקייה דרך דיאלוג המערכת, ואז שם הקובץ
  /// בדיאלוג של התוכנה. **אינו נוגע ביעד** — הכתיבה כולה ב-[_atomicWrite].
  ///
  /// `FilePicker.saveFile` אינו משמש כאן: מאז 12.0 הוא כותב תמיד את הבייטים
  /// שקיבל, ולכן בחירת קובץ קיים הייתה מרוקנת אותו עוד לפני הכתיבה האמיתית.
  /// כשיתווסף אפסטרים בורר-מיקום שאינו כותב, המימוש הזה מתקפל בחזרה אליו:
  /// https://github.com/vicajilau/flutter_file_picker/issues/2156
  Future<String?> _defaultPickSaveLocation({
    required String suggestedName,
    List<String>? allowedExtensions,
    String? title,
  }) async {
    final context = rpcWindowContext;
    if (context == null || !context.mounted) return null;
    final windowsOptions = modalWindowsOptions(context);
    if (!await verifySaferModePassword(context)) {
      return null;
    }
    if (!context.mounted) return null;
    final folder = await withFilePickerOwner(
      context,
      (picker) => picker.getDirectoryPath(
        dialogTitle: pluginSaveFolderDialogTitle(title),
        windowsOptions: windowsOptions,
        linuxOptions: kModalLinuxOptions,
      ),
    );
    if (folder == null) return null;

    final dialogContext = context;
    if (!dialogContext.mounted) return null;
    final typed = await showInputDialog(
      context: dialogContext,
      title: title ?? 'שמירת קובץ',
      labelText: 'שם הקובץ',
      initialValue: suggestedName,
      confirmText: 'שמור',
    );
    if (typed == null || !dialogContext.mounted) return null;

    final fileName = pluginSaveFileName(typed, allowedExtensions?.firstOrNull);
    final target = pluginSaveTargetPath(folder: folder, fileName: fileName);
    if (target == null) return null;

    if (File(target).existsSync()) {
      final replace = await _dependencies.showWarningDialog(
        title: 'הקובץ כבר קיים',
        content: 'הקובץ „$fileName” כבר קיים בתיקייה שנבחרה.',
        subtitle: 'התוכן הקיים יוחלף.',
      );
      if (!replace || !dialogContext.mounted) return null;
    }
    return target;
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
      p.join(
        target.parent.path,
        '.${p.basename(targetPath)}.$suffix$_stagingExt',
      ),
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

  static const String _stagingExt = kUserFolderStagingExtension;

  /// suffix אקראי ולא חתימת זמן: שתי שמירות באותה מיקרו-שנייה היו מתנגשות.
  String _randomSuffix() {
    final random = math.Random.secure();
    return List<int>.generate(
      8,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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

  /// מסדר את הכתיבות לרשימת ה-grants. כל כתיבה קוראת את כל המפה ושומרת אותה
  /// מחדש, ולכן שתי כתיבות מקבילות (למשל `Promise.all` של כמה
  /// `network.fetchFile`) היו דורסות זו את ה-grant של זו. התור משותף לכל
  /// המופעים של אותו תוסף, כי ה-KV משותף להם.
  static final Map<String, Future<void>> _grantWriteQueues = {};

  Future<T> _serializeGrantWrites<T>(Future<T> Function() action) {
    final previous = _grantWriteQueues[plugin.pluginId] ?? Future<void>.value();
    final run = previous.then((_) => action());
    final tail = run.then<void>((_) {}, onError: (_) {});
    _grantWriteQueues[plugin.pluginId] = tail;
    // תור שהתרוקן אינו נשמר, כדי שהמפה לא תצבור תוספים.
    tail.whenComplete(() {
      if (identical(_grantWriteQueues[plugin.pluginId], tail)) {
        _grantWriteQueues.remove(plugin.pluginId);
      }
    });
    return run;
  }

  Future<void> _saveUserFileGrant(
    String token,
    String path, {
    required bool writable,
  }) => _serializeGrantWrites(() async {
    final grants = await _readUserFileGrants();
    grants[token] = {'path': path, 'access': writable ? 'readwrite' : 'read'};
    await _pluginRepo.setKV(
      plugin.pluginId,
      '_internal',
      _userFileGrantsKey,
      jsonEncode(grants),
    );
  });

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

  Future<void> _removeUserFileGrant(String token) =>
      _serializeGrantWrites(() async {
        final grants = await _readUserFileGrants();
        if (grants.remove(token) != null) {
          await _pluginRepo.setKV(
            plugin.pluginId,
            '_internal',
            _userFileGrantsKey,
            jsonEncode(grants),
          );
        }
      });

  /// רושם את [canonical] כקובץ משתמש מאושר, או משתמש שוב ב-token שכבר קיים
  /// לאותו נתיב.
  ///
  /// הכפילות חשובה: התוסף ממפתח את רשימת "אחרונים" לפי token, ופתיחה חוזרת
  /// של אותו קובץ מתיקייה או מהספרייה הייתה מוסיפה לה שורה בכל פעם. grant
  /// קיים לקריאה משודרג לכתיבה כשהתבקשה ואושרה; grant לכתיבה אינו מורד — ה-
  /// `writable` שחוזר הוא מה שה-token מאפשר בפועל.
  Future<({String token, String url, bool writable})> _grantUserFile(
    String canonical, {
    required bool writable,
  }) async {
    final grants = await _readUserFileGrants();
    for (final MapEntry(key: token, :value) in grants.entries) {
      final path = switch (value) {
        final String path => path,
        {'path': final String path} => path,
        _ => null,
      };
      if (path == null || !p.equals(path, canonical)) continue;
      final existingWritable = value is Map && value['access'] == 'readwrite';
      if (writable && !existingWritable) {
        await _saveUserFileGrant(token, canonical, writable: true);
      }
      final url = await _fileServer.registerWithToken(
        pluginId: plugin.pluginId,
        canonicalPath: canonical,
        token: token,
      );
      return (token: token, url: url, writable: writable || existingWritable);
    }
    final registration = await _fileServer.register(
      pluginId: plugin.pluginId,
      canonicalPath: canonical,
    );
    await _saveUserFileGrant(registration.token, canonical, writable: writable);
    return (
      token: registration.token,
      url: registration.url,
      writable: writable,
    );
  }

  // ----------------------------------------------------------------
  // fs.* — תיקיות משתמש עם גישה קבועה
  // ----------------------------------------------------------------

  // תיקיות שהמשתמש הוסיף לתוסף נשמרות ב-KV (`_internal/user_folder_grants`),
  // דרך [PluginUserFolderGrants] — אותו שירות שמסך הגדרות התוסף מבטל דרכו.
  // בניגוד ל-`ui.pickFolder` ה-grant קבוע: זו רשימת התיקיות שבעץ "פתח מסמך",
  // והמשתמש מצפה למצוא אותן גם מחר.
  PluginUserFolderGrants get _folderGrants =>
      PluginUserFolderGrants(_pluginRepo);

  /// `fs.pickUserFolder` — דיאלוג בחירת תיקייה ואחריו דיאלוג הסכמה של אוצריא
  /// לגישה **קבועה**. בחירה חוזרת של תיקייה שכבר אושרה מחזירה את אותו token
  /// בלי לשאול שוב.
  ///
  /// דיאלוג ההסכמה הוא ממשק של המארח, ואין ארגומנט שמדלג עליו: רשומה ב-KV
  /// נוצרת רק אחרי "המשך". דחייה מחזירה `{cancelled: true}` ואינה שומרת דבר.
  Future<Map<String, dynamic>> _pickUserFolder(
    Map<String, dynamic> args,
  ) async {
    // בורר ברירת המחדל עובר דרך סיסמת "מצב בטוח", כמו pickUserFile.
    final picker = _dependencies.pickFolder ?? _defaultPickFolder;
    final picked = await picker(title: args['title'] as String?);
    if (picked == null || picked.isEmpty) return {'cancelled': true};
    final rejection = await pluginFolderRejectionReason(picked);
    if (rejection != null) throw Exception('error.forbidden: $rejection');
    final canonical = canonicalizeNearestExisting(picked);
    if (canonical == null || !await Directory(canonical).exists()) {
      throw Exception('error.not_found: selected folder does not exist');
    }
    final name = p.basename(canonical);
    var folderToken = (await _folderGrants.byPath(
      plugin.pluginId,
      canonical,
    ))?.token;
    if (folderToken == null) {
      final consented = await _dependencies.showWarningDialog(
        title: 'גישה קבועה לתיקייה',
        content:
            'התוסף „${plugin.name}” מבקש גישה קבועה לתיקייה „$name”: לקרוא '
            'ולכתוב בה גם בהפעלות הבאות של אוצריא, בלי לשאול שוב.',
        subtitle: 'אפשר לבטל את הגישה בכל עת בהגדרות התוסף.',
      );
      if (!consented) return {'cancelled': true};
      folderToken = 'dir-${_randomSuffix()}${_randomSuffix()}';
      await _folderGrants.add(plugin.pluginId, (
        token: folderToken,
        path: canonical,
      ));
    }
    return {
      'cancelled': false,
      'folderToken': folderToken,
      'name': name,
      'path': canonical,
    };
  }

  /// השורש הקנוני של תיקייה מאושרת. תיקייה שנעלמה מהדיסק אינה מבטלת את ה-
  /// grant: כונן חיצוני שנותק יחזור, והמשתמש לא אמור להוסיף אותו מחדש.
  Future<String> _userFolderRoot(Map<String, dynamic> args) async {
    final folderToken = args['folderToken'];
    if (folderToken is! String || folderToken.isEmpty) {
      throw Exception('error.invalid_params: folderToken required');
    }
    final grant = await _folderGrants.byToken(plugin.pluginId, folderToken);
    if (grant == null) {
      throw Exception('error.not_found: unknown folder token');
    }
    final path = grant.path;
    try {
      if (await Directory(path).exists()) {
        final current = await Directory(path).resolveSymbolicLinks();
        if (!p.equals(current, path)) {
          throw Exception('error.forbidden: granted folder path changed');
        }
        return current;
      }
    } on FileSystemException {
      // נופל ל-not_found למטה.
    }
    throw Exception('error.not_found: folder no longer exists');
  }

  /// מפענח את `path` של קריאה על תיקייה מאושרת ופותר אותו בתוכה.
  Future<({List<String> segments, String resolved})> _resolveInUserFolder(
    String root,
    Object? rawPath,
  ) async {
    if (rawPath != null && rawPath is! String) {
      throw Exception('error.invalid_params: path must be a string');
    }
    final segments = parseUserFolderRelativePath(rawPath as String? ?? '');
    final resolved = segments == null
        ? null
        : await resolveUserFolderPath(root, segments);
    if (segments == null || resolved == null) {
      throw Exception('error.forbidden: path outside the granted folder');
    }
    return (segments: segments, resolved: resolved);
  }

  /// `fs.listUserFolder` — רמה אחת של תיקייה מאושרת (העץ בתוסף טוען בעצלות).
  Future<Map<String, dynamic>> _listUserFolder(
    Map<String, dynamic> args,
  ) async {
    final extensions = normalizeUserFolderExtensions(
      _optionalStringList(args['extensions'], 'extensions'),
    );
    final root = await _userFolderRoot(args);
    final target = await _resolveInUserFolder(root, args['path']);
    if (await FileSystemEntity.type(target.resolved) !=
        FileSystemEntityType.directory) {
      throw Exception('error.not_found: folder not found');
    }
    final relativePath = joinUserFolderRelativePath(target.segments);
    final UserFolderListing listing;
    try {
      listing = await listUserFolderEntries(
        canonicalRoot: root,
        canonicalDir: target.resolved,
        relativePath: relativePath,
        extensions: extensions,
      );
    } on FileSystemException catch (e) {
      throw Exception('error.forbidden: cannot read folder (${e.message})');
    }
    return {
      'folderToken': args['folderToken'],
      'name': p.basename(root),
      'path': relativePath,
      'entries': listing.entries,
      'truncated': listing.truncated,
    };
  }

  /// `fs.openFolderFile` — פותח קובץ מתוך תיקייה מאושרת כקובץ משתמש רגיל,
  /// באותה צורת תשובה של `fs.pickUserFile`. הקובץ אינו מועתק.
  Future<Map<String, dynamic>> _openFolderFile(
    Map<String, dynamic> args,
  ) async {
    final writable = _parseUserFileAccess(args);
    final rawPath = args['path'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      throw Exception('error.invalid_params: path required');
    }
    if (writable) await _requireWritePermission();
    final root = await _userFolderRoot(args);
    final target = await _resolveInUserFolder(root, rawPath);
    if (target.segments.isEmpty ||
        await FileSystemEntity.type(target.resolved) !=
            FileSystemEntityType.file) {
      throw Exception('error.not_found: file not found');
    }
    final grant = await _grantUserFile(target.resolved, writable: writable);
    return {
      'cancelled': false,
      'token': grant.token,
      'url': grant.url,
      'name': p.basename(target.resolved),
      'size': await File(target.resolved).length(),
      'access': grant.writable ? 'readwrite' : 'read',
    };
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

  /// גם ילד בתפריט יכול לפתוח מופע, ולכן בודקים את כל עץ הפריטים.
  void _requireMultipleInstancesForNewTab(
    Map<String, dynamic> payload, {
    int depth = 0,
  }) {
    if (plugin.manifest.allowMultipleInstances) return;
    if (payload['newTab'] == true) {
      throw Exception(
        'error.forbidden: contributes.toolTab.allowMultipleInstances '
        'is not enabled in the manifest',
      );
    }
    if (depth >= ContextMenuRegistry.maxNestingDepth) return;
    final children = payload['children'];
    if (children is List &&
        children.length <= ContextMenuRegistry.maxChildren) {
      for (final child in children.whereType<Map>()) {
        _requireMultipleInstancesForNewTab(
          Map<String, dynamic>.from(child),
          depth: depth + 1,
        );
      }
    }
  }

  /// עוקב אחר מפתחות תנאי ההצגה כדי שהפריט יגיב לשינוי באחסון.
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
        return value != null ? JavaScriptHandlerJsonResult(value) : null;
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

    // date (ISO) ומיקום אופציונליים: city מרשימת הלוח או lat+lng (ועוד
    // elevation/timezone/inIsrael). בלי פרמטרים: זמני התאריך והעיר שנבחרו בלוח.
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
          unawaited(_alerts.send('pluginEventsChanged'));
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
          unawaited(_alerts.send('pluginEventsChanged'));
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
      case 'submitBookCorrection':
        return _submitBookCorrection(args);
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
          finalBody += 'גרסה: ${appReleaseVersion(packageInfo)}\n';
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

  Future<Map<String, dynamic>> _submitBookCorrection(
    Map<String, dynamic> args,
  ) async {
    final bookId = args['bookId'];
    final bookUid = args['bookUid'];
    if (bookId is! String ||
        bookId.trim().isEmpty ||
        (bookUid != null && (bookUid is! String || bookUid.trim().isEmpty))) {
      throw Exception('error.invalid_params: זהות הספר אינה תקינה.');
    }
    final library = await DataRepository.instance.library;
    _ensureBookIndex(library);
    final book = bookUid is String
        ? _booksByUid[bookUid.trim()]
        : switch (_booksByTitle[bookId]) {
            [final book] => book,
            _ => null,
          };
    if (book == null) {
      throw Exception('error.not_found: הספר לא נמצא באופן חד־משמעי.');
    }
    if (book is! TextBook ||
        !book.isOfficialLibraryBook ||
        book.id == null ||
        book.versionTitle != null) {
      throw Exception(
        'error.unsupported_context: ניתן לדווח רק על ספר טקסט רשמי.',
      );
    }
    final resolved = await BookDatabaseResolver.resolveBookById(book.id!);
    if (resolved == null ||
        !resolved.source.isOfficial ||
        resolved.book.isFileBacked) {
      throw Exception(
        'error.unsupported_context: מקור הספר אינו במסד הספרייה הרשמי.',
      );
    }
    final information = await BookDetailsService().getBookInformation(book);
    final filePath = information.fileDetails['נתיב הקובץ'];
    final package = await PackageInfo.fromPlatform();
    final version = await DataCollectionService().readLibraryVersion();
    return _bookCorrectionService.submit(
      pluginId: plugin.pluginId,
      args: args,
      metadata: PluginBookReportMetadata(
        bookId: resolved.book.id,
        title: book.title,
        sourceFolder: information.source ?? '',
        // האתר מאתר את המקור לפי הנתיב המלא, עם `אוצריא/` והסיומת.
        filePath: filePath == BookDetailsService.bookNotFoundText
            ? ''
            : filePath ?? '',
        libraryVersion: version,
        client: ReportClientInfo(
          appVersion: '${package.version}+${package.buildNumber}',
          platform: Platform.operatingSystem,
        ),
      ),
      loadSource: (index) async {
        final lines = await DbReadWorker.lines(
          SqliteDataProvider.instance.dbPath,
          resolved.book.id,
          index,
          index,
        );
        if (lines.length != 1) {
          throw Exception('error.not_found: פסקת המקור אינה קיימת.');
        }
        return PluginBookReportSource(
          lines.single.content,
          heRef: lines.single.heRef,
        );
      },
    );
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
        final historyState = _windowDependencies.historyBloc.state;
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
        final historyState = _windowDependencies.historyBloc.state;
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
        _windowDependencies.historyBloc.add(ClearHistory());
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
          final historyState = _windowDependencies.historyBloc.state;
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
            _windowDependencies.historyBloc.add(RemoveHistory(indexToRemove));
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
          _requireBookIdentity(args);
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
  Future<dynamic> _handleTools(String action, Map<String, dynamic> args) async {
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
          final dictionaries = args['dictionaries'];
          if (dictionaries != null &&
              (dictionaries is! List ||
                  dictionaries.length > 20 ||
                  dictionaries.any((d) => d is! String || d.length > 100))) {
            throw Exception(
              'error.invalid_params: dictionaries must be a list of names',
            );
          }
          final names = await _derivedTextNames(null, args);
          final repository = DictionaryLookupRepository.instance;
          await repository.ensureAcronymsLoaded();
          await repository.ensureAramaicLoaded();
          return {
            'term': term.trim(),
            'acronyms': repository
                .findAcronymMatches(term)
                .map(
                  (e) => {
                    'acronym': e.acronym,
                    'meanings': [
                      for (final meaning in e.meanings)
                        filterPluginDivineNamesText(meaning, names),
                    ],
                  },
                )
                .toList(),
            'aramaic': repository
                .findAramaicMatches(
                  term,
                  dictionaries: dictionaries == null
                      ? const {AramaicDictionaryEntry.peshitaDictionary}
                      : {...dictionaries.cast<String>()},
                )
                .map(
                  (e) => {
                    'aramaic': e.aramaic,
                    'hebrew': filterPluginDivineNamesText(e.hebrew, names),
                    'dictionary': e.dictionary,
                  },
                )
                .toList(),
          };
        }

      case 'biographies':
        {
          final rawQuery = args['query'];
          if (rawQuery != null &&
              (rawQuery is! String || rawQuery.length > 200)) {
            throw Exception('error.invalid_params: query must be a string');
          }
          final id = args['id'];
          if (id != null &&
              id is! int &&
              (id is! String || id.isEmpty || id.length > 50)) {
            throw Exception(
              'error.invalid_params: id must be a string or integer',
            );
          }
          final formatVersion = args['formatVersion'] ?? 1;
          if (formatVersion is! int ||
              (formatVersion != 1 && formatVersion != 2)) {
            throw Exception(
              'error.invalid_params: formatVersion must be 1 or 2',
            );
          }
          final limit = args['limit'];
          if (limit != null && (limit is! int || limit < 1 || limit > 50)) {
            throw Exception('error.invalid_params: limit must be 1..50');
          }
          final names = await _derivedTextNames(null, args);
          final List<Biography> all;
          try {
            all =
                await (_dependencies.biographiesRepository ??
                        BiographiesRepository.instance)
                    .loadAll();
          } catch (_) {
            throw Exception('error.not_supported: biographies unavailable');
          }
          final matched = switch (id) {
            final String id => all.where((bio) => bio.id == id).toList(),
            final int id =>
              all
                  .where(
                    (bio) =>
                        id < 0 &&
                        PluginBiographyCompatibility.legacyId(bio.id) == id,
                  )
                  .toList(),
            _ => BiographiesRepository.filter(all, (rawQuery as String?) ?? ''),
          };
          return {
            'total': matched.length,
            'results': matched
                .take((limit as int?) ?? 20)
                .map(
                  (bio) =>
                      _biographyToJson(bio, names, legacy: formatVersion == 1),
                )
                .toList(),
          };
        }

      default:
        throw Exception(
          'error.unknown_method: Unknown action in tools: $action',
        );
    }
  }

  /// [names] applies to the prose fields only; the rest are names and keys.
  Map<String, dynamic> _biographyToJson(
    Biography bio,
    PluginDivineNamesDisplay names, {
    required bool legacy,
  }) {
    String? prose(String? text) =>
        text == null ? null : filterPluginDivineNamesText(text, names);
    Map<String, dynamic> person(RelatedPerson p) => {
      'name': p.name,
      'relation': p.relation,
      'ref': p.ref,
    };
    return {
      'id': legacy ? PluginBiographyCompatibility.legacyId(bio.id) : bio.id,
      'name': legacy ? bio.fullName : bio.name,
      if (legacy) ...{
        'communities': <String>[],
        'biographyShort': prose(bio.summary),
      },
      'honorific': bio.honorific,
      'era': bio.era,
      'eraLabel': bio.eraLabel,
      'generation': bio.generation,
      'appelations': bio.knownAs,
      'countries': bio.region,
      'birth': bio.born?.display,
      'death': bio.died?.display,
      'buried': bio.buried,
      'roles': bio.roles,
      'teachers': bio.teachers.map(person).toList(),
      'students': bio.students.map(person).toList(),
      'family': bio.family.map(person).toList(),
      'works': [
        for (final work in bio.works)
          {'title': work.title, 'description': prose(work.description)},
      ],
      'mentionedIn': bio.mentionedIn,
      'summary': prose(bio.summary),
      'remember': prose(bio.remember),
      'sources': [
        for (final source in bio.sources)
          {'credit': source.credit, 'title': source.title, 'url': source.url},
      ],
      'attribution': BiographiesBundle.authorCredit,
    };
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
            UiSnack.showSuccess(
              message,
              onTap: onTap,
              window: _windowDependencies.windowKeys,
            );
            break;
          case 'error':
            UiSnack.showError(
              message,
              onTap: onTap,
              window: _windowDependencies.windowKeys,
            );
            break;
          case 'info':
          default:
            UiSnack.show(
              message,
              onTap: onTap,
              window: _windowDependencies.windowKeys,
            );
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

        final notificationId = id ?? _newNotificationId();
        return _notificationCommand('pluginShow', {
          'id': notificationId,
          'title': title,
          'body': body,
        });

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

        final notificationId = id ?? _newNotificationId();
        return _notificationCommand('pluginSchedule', {
          'id': notificationId,
          'title': title,
          'body': body,
          'at': dateTime.toIso8601String(),
        });

      case 'cancel':
        // ביטול התראה
        final id = args['id'] as int?;
        if (id == null) throw Exception('error.invalid_params: id required');
        return _notificationCommand('pluginCancel', {'id': id});

      case 'cancelAll':
        // ביטול כל ההתראות של התוסף
        return _notificationCommand('pluginCancelAll');

      case 'checkPermissions':
        // בדיקת הרשאות התראות, בלי אתחול
        return _notificationCommand('pluginPermissions');

      case 'requestPermissions':
        // בקשת הרשאות התראות
        final ack = await _alerts.send('ensurePermission');
        if (!ack.ok) throw Exception(ack.error ?? 'error.unavailable');
        return {'granted': ack.value == true};

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

  /// פעולת התראה של התוסף אצל הבעלים, שגם רושם את המזהה בתור שלו.
  Future<Object?> _notificationCommand(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    final ack = await _alerts.send(op, {...args, 'pluginId': plugin.pluginId});
    if (ack.ok) return ack.value;
    throw Exception(ack.error ?? 'error.unavailable: calendar alerts');
  }

  // flutter_local_notifications דוחה מזהה שאינו נכנס ב-32 ביט.
  static int _newNotificationId() => math.Random().nextInt(0x7FFFFFFF);

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
      'dafYomi': _buildDafYomiPayload(jewishCalendar),
      'holidays': _buildHolidayPayloads(jewishCalendar, formatter),
    };
  }

  /// דף היומי (בבלי) לתאריך העברי הנתון. `null` עבור תאריכים שקדמו לתחילת
  /// המחזור הראשון (י"ח באלול תרפ"ג / 11.9.1923), שלגביהם הספרייה זורקת.
  Map<String, dynamic>? _buildDafYomiPayload(JewishCalendar jewishCalendar) {
    try {
      final daf = jewishCalendar.getDafYomiBavli();
      return {'masechet': daf.getMasechta(), 'daf': daf.getDaf()};
    } on ArgumentError {
      return null;
    }
  }

  String _upcomingParasha(
    DateTime date,
    bool inIsrael,
    HebrewDateFormatter formatter,
  ) {
    final dayOfWeek = date.weekday;
    // Dart weekday: Mon=1 … Sat=6, Sun=7. Shabbat = Saturday = 6.
    final daysUntilShabbat = dayOfWeek == 6 ? 0 : (6 - dayOfWeek) % 7;
    final shabbatDate = addCalendarDays(date, daysUntilShabbat);
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

  /// מצב המפרשים של טאב הקריאה כפי שהוא כבר טעון בטאב — בלי שאילתה נוספת.
  /// `null` כשאין טאב קריאה, כשמצב הטאב עדיין לא נטען או כשאין בו מפרשים.
  Map<String, dynamic>? _getActiveCommentators() {
    final pane = _windowDependencies.tabsBloc.state.readingPane;
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
    final pane = _windowDependencies.tabsBloc.state.readingPane;
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

  Map<String, dynamic>? _getPageShapeLayout() {
    final pane = _windowDependencies.tabsBloc.state.readingPane;
    if (pane is! TextBookTab) return null;
    final state = pane.bloc.state;
    if (state is! TextBookLoaded || !state.showPageShapeView) return null;
    return pane.pageShapePluginController.layout?.toJson();
  }

  Map<String, dynamic>? _setPageShapeCommentatorVisibility(
    Map<String, dynamic> args,
  ) {
    final rawCommentator = args['commentator'];
    if (rawCommentator is! String || rawCommentator.trim().isEmpty) {
      throw Exception('error.invalid_params: commentator is required');
    }
    final visible = args['visible'];
    if (visible is! bool) {
      throw Exception('error.invalid_params: visible must be a boolean');
    }

    final pane = _windowDependencies.tabsBloc.state.readingPane;
    if (pane is! TextBookTab) return null;
    final state = pane.bloc.state;
    if (state is! TextBookLoaded || !state.showPageShapeView) return null;

    final commentator = rawCommentator.trim();
    final layout = pane.pageShapePluginController.layout;
    if (layout == null) return null;
    if (!layout.contains(commentator)) {
      throw Exception(
        'error.not_found: commentator is not assigned to a page-shape column',
      );
    }
    return pane.pageShapePluginController
        .setCommentatorVisibility(commentator, visible)
        ?.toJson();
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
  /// הראשי (תצוגה משולבת וצורת הדף), ואין ב-PDF הדגשות ובחירה דרך ה-API.
  Map<String, dynamic> _getHighlightCapabilities() {
    final pane = _windowDependencies.tabsBloc.state.readingPane;
    if (pane is TextBookTab) {
      final state = pane.bloc.state;
      final pageShape = state is TextBookLoaded && state.showPageShapeView;
      return {
        'surface': pageShape ? 'pageShape' : 'combined',
        'highlights': true,
        'selection': true,
        'contextMenu': const ['mainText', 'commentary'],
      };
    }
    if (pane is PdfBookTab) {
      return {
        'surface': 'pdf',
        'highlights': false,
        'selection': false,
        'contextMenu': const ['pdf', 'commentary'],
      };
    }
    return {
      'surface': null,
      'highlights': false,
      'selection': false,
      'contextMenu': const <String>[],
    };
  }

  /// הטאב שבאינדקס `index` שהתוסף מסר (כמו ב-`openTabs`).
  /// אינדקס חסר או מחוץ לתחום נדחה כשגיאת ארגומנטים ולא כחריגה.
  OpenedTab _tabAt(Map<String, dynamic> args) {
    final rawIndex = args['index'];
    if (rawIndex is! num ||
        !rawIndex.isFinite ||
        rawIndex != rawIndex.truncateToDouble()) {
      throw Exception('error.invalid_params: index must be an integer');
    }
    final index = rawIndex.toInt();
    final tabs = _windowDependencies.tabsBloc.state.tabs;
    if (index < 0 || index >= tabs.length) {
      throw Exception(
        'error.invalid_params: index $index out of range '
        '(${tabs.length} open tabs)',
      );
    }
    return tabs[index];
  }

  /// בטאב מפוצל הכותרת המשולבת אינה ספר, ולכן מדווחת החלונית הפעילה (ובטאב
  /// שאינו הנוכחי — הראשונה); דיווח כל החלוניות הוא שינוי API של `openTabs`.
  OpenedTab _paneForPlugins(OpenedTab tab) {
    if (tab is! CombinedTab) return tab;
    final state = _windowDependencies.tabsBloc.state;
    if (identical(tab, state.currentTab)) return state.activePane ?? tab;
    return leafPanes(tab).first;
  }

  /// העוגנים נבנים מול התצוגה שעל המסך; הטקסט המוצג נמסר לפי הגדרת השמות
  /// העדכנית או, עם [rawNames], בלי החלפתם. טקסט המקור נשאר כפי שנשמר.
  Map<String, dynamic>? _buildCurrentSelection(
    OpenedTab? currentTab,
    String? currentRef, {
    bool rawNames = false,
  }) {
    if (currentTab is! TextBookTab) {
      return null;
    }

    final state = currentTab.bloc.state;
    if (state is! TextBookLoaded) {
      return null;
    }

    final rawSelectedText = state.selectedTextForNote;
    if (rawSelectedText == null || rawSelectedText.trim().isEmpty) {
      return null;
    }
    final selectedText = limitTextToCopySegments(
      state.protection,
      rawSelectedText,
    );

    final legacySelection = <String, dynamic>{
      'id': currentTab.book.id,
      'type': PluginBookIdentity.typeOf(currentTab.book),
      'source': PluginBookIdentity.sourceOf(currentTab.book),
      'bookUid': PluginBookIdentity.uidOf(currentTab.book),
      'text': withoutDivineNameJoiners(selectedText),
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
    final names = rawNames
        ? PluginDivineNamesDisplay.raw
        : PluginDivineNamesDisplay.of(
            PluginDivineNamesFilter.readerProfile(state),
          );
    if (sectionIndex < 0 || sectionIndex >= state.content.length) {
      return {
        ...legacySelection,
        'text': filterPluginDivineNamesText(
          legacySelection['text'] as String,
          names,
        ),
      };
    }

    final settings = RenderSettings.fromProfile(state.bodyDisplayProfile);
    if (identical(selectedText, rawSelectedText) &&
        start != null &&
        end != null) {
      final rawLine = injectDivineNameMarkers(
        state.content[sectionIndex],
        state.divineNames,
        sectionIndex,
      );
      const service = ReaderSelectionService();
      final selection = service.build(
        bookId: currentTab.title,
        bookTitle: currentTab.title,
        sectionIndex: sectionIndex,
        rawText: rawLine,
        settings: settings,
        renderedStartUtf16: start,
        renderedEndUtf16: end,
        currentRef: currentRef,
      );
      if (selection != null) {
        return service.withDivineNames(
          {...legacySelection, ...selection.toJson()},
          names: names,
          settings: settings,
          rawTextOf: (_) => rawLine,
        );
      }
    }

    // בחירה רב-פסקתית, מוגבלת-העתקה או בלי טווח תקף: מעוגנת לפי הטקסט, כמו
    // בתפריט ההקשר, ולכן גם בה הטקסט נמסר לפי [names].
    final lineCount = selectedText.split('\n').length;
    final anchored = lineCount > 1
        ? buildPluginMultiSectionSelectionPayload(
            state: state,
            firstSectionIndex: sectionIndex,
            rawTexts: state.content.sublist(
              sectionIndex,
              math.min(sectionIndex + lineCount, state.content.length),
            ),
            selectedText: selectedText,
            startHint: null,
            settings: settings,
          )
        : buildPluginSelectionPayload(
            state: state,
            sectionIndex: sectionIndex,
            rawText: state.content[sectionIndex],
            selectedText: selectedText,
            startHint: start,
            settings: settings,
          );
    return {
      ...legacySelection,
      ...PluginDivineNamesPayload.resolve(anchored, names),
      'start': legacySelection['start'],
      'end': legacySelection['end'],
      'currentRef': currentRef,
      'currentIndex': legacySelection['currentIndex'],
    };
  }

  String? _currentBookId() {
    return _windowDependencies.tabsBloc.state.readingPane?.title;
  }

  /// מזהה יציב של הספר בחלונית הקריאה, ל-scope של `book:<bookUid>`.
  String? _currentBookUid() {
    final pane = _windowDependencies.tabsBloc.state.readingPane;
    if (pane is TextBookTab) return PluginBookIdentity.uidOf(pane.book);
    if (pane is PdfBookTab) return PluginBookIdentity.uidOf(pane.book);
    return null;
  }

  String? _currentWorkspaceId() {
    return _windowDependencies.workspaceBloc.state.activeWorkspaceId;
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
  Future<dynamic> _handleEvents(String action, Map<String, dynamic> args) {
    switch (action) {
      case 'setOptions':
        return _setEventOptions(args);
      default:
        throw Exception('error.unknown_method: Unknown events action: $action');
    }
  }

  /// `events.setOptions` — אפשרויות המסירה של נושא למופע הזה, עד טעינה מחדש
  /// של הדף. הרשאת `events.subscribe:<topic>` נבדקת כאן, לפי הנושא.
  Future<Map<String, dynamic>> _setEventOptions(
    Map<String, dynamic> args,
  ) async {
    // נלכד לפני ה-await: בקשה של דף שנטען מחדש בינתיים לא תחול על הדף החדש.
    final generation = PluginRuntimeDispatcher.instance.eventOptionsGeneration(
      plugin.pluginId,
      instanceId,
    );
    final topic = args['topic'];
    final raw = args['rawDivineNames'];
    if (topic is! String || raw is! bool) {
      throw Exception(
        'error.invalid_params: topic (string) and rawDivineNames (boolean) '
        'are required',
      );
    }
    final permission = 'events.subscribe:$topic';
    if (!pluginValidPermissions.contains(permission)) {
      throw Exception(
        'error.invalid_params: $topic is not an event topic a plugin '
        'subscribes to; context menu items take rawDivineNames themselves',
      );
    }
    if (!pluginBaselinePermissions.contains(permission) &&
        await _pluginRepo.getPermission(plugin.pluginId, permission) != true) {
      throw Exception('error.forbidden: $permission is required');
    }
    if (generation == null ||
        !PluginRuntimeDispatcher.instance.setEventRawDivineNames(
          plugin.pluginId,
          instanceId,
          topic,
          raw: raw,
          generation: generation,
        )) {
      throw Exception('error.unavailable: plugin instance is not running');
    }
    return {'topic': topic, 'rawDivineNames': raw};
  }

  /// אפשרויות האירועים שה-boot החזיר. המארח מחכה להן לפני מסירת אירועים
  /// שהמתינו לדף, כדי שגם האירוע שהעיר את התוסף יכבד אותן.
  Future<void> applyBootEventOptions(Object? bootResult) async {
    if (bootResult is! List) return;
    for (final options in bootResult.take(64)) {
      if (options is! Map) continue;
      try {
        await _setEventOptions(Map<String, dynamic>.from(options));
      } catch (e) {
        debugPrint('Plugin ${plugin.pluginId}: boot event options: $e');
      }
    }
  }

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
                'enabled': p.enabled,
                'showInTools': p.showInTools,
                // מאיפה התוסף הותקן. תוסף חנות שבודק עדכונים צריך את זה:
                // בדיקת העדכונים הפנימית של אוצריא מחריגה תוספי פיתוח
                // (PluginUpdateCheckService.eligiblePlugins), ובלי השדה הזה
                // תוסף אינו יכול להחיל את אותו כלל.
                'sourceType': p.sourceType,
                'toolTabIconName':
                    pluginIconFromName(p.manifest.toolTabIconName) != null
                    ? p.manifest.toolTabIconName
                    : 'puzzle_piece_24_regular',
              },
            )
            .toList();
      case 'setNewTabPage':
        final enabled = args['enabled'];
        if (enabled != null && enabled is! bool) {
          throw Exception('error.invalid_params: enabled must be boolean');
        }
        if (enabled == false) {
          await PluginNewTabPageService.instance.release(
            plugin.pluginId,
            _pluginRepo,
          );
        } else {
          return PluginNewTabPageService.instance.request(
            plugin.pluginId,
            _pluginRepo,
            onConflict: (ownerId) => unawaited(
              notifyPluginNewTabPageConflict(plugin, ownerId, _pluginRepo),
            ),
          );
        }
        return true;
      case 'openSelf':
        final newTab = args['newTab'];
        if (newTab != null && newTab is! bool) {
          throw Exception('error.invalid_params: newTab must be boolean');
        }
        if (newTab == true) {
          // מופע נוסף הוא WebView נוסף מעל אותו אחסון — רק תוסף שהצהיר
          // במניפסט שהוא יודע לחיות לצד עצמו.
          if (!plugin.manifest.allowMultipleInstances) {
            throw Exception(
              'error.forbidden: contributes.toolTab.allowMultipleInstances '
              'is not enabled in the manifest',
            );
          }
          // בלי כרטיסיה פתוחה של התוסף, newTab פותח את הראשית כמו פתיחה רגילה.
          if (openToolInstanceCount(
                _windowDependencies.tabsBloc.state.tabs,
                plugin.pluginId,
              ) >
              0) {
            final openedInstanceId = PluginPageLauncher.instance
                .openNewInstance(
                  plugin.pluginId,
                  topic: 'plugin.page_opened',
                  payload: {'param': args['param']},
                  viewId: _windowDependencies.viewId,
                  windowKeys: _windowDependencies.windowKeys,
                );
            return openedInstanceId != null;
          }
        }
        PluginPageLauncher.instance.open(
          plugin.pluginId,
          topic: 'plugin.page_opened',
          payload: {'param': args['param']},
          viewId: _windowDependencies.viewId,
          windowKeys: _windowDependencies.windowKeys,
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
          viewId: _windowDependencies.viewId,
          windowKeys: _windowDependencies.windowKeys,
        );
        return true;
      case 'backgroundDone':
        return _dependencies.onBackgroundInstanceDone?.call() ?? false;
      case 'setRestoreState':
        // spec: setRestoreState({ state }) — נמסר ב-plugin.boot.restore כשהדף
        // של המופע נטען מחדש (פינוי, נפילה, סשן). למופע רקע אין שחזור.
        if (!args.containsKey('state')) {
          throw Exception('error.invalid_params: state is required');
        }
        if (instanceId == PluginInstanceIds.background) return false;
        try {
          PluginRestoreStateStore.instance.set((
            pluginId: plugin.pluginId,
            instanceId: instanceId,
          ), args['state']);
        } on ArgumentError catch (e) {
          throw Exception('error.invalid_params: ${e.message}');
        }
        return true;
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
          'התוסף אינו מצהיר על גישת רשת במניפסט (network.enabled).',
        );
      case PluginNetworkDecision.permissionMissing:
        final isLocal =
            requiredNetworkPermissionFor(uri) == 'network.localhost';
        final what = isLocal
            ? 'גישה לשירותים מקומיים (network.localhost)'
            : 'גישה לאינטרנט (network.access)';
        final separation = !isLocal
            ? 'network.localhost אינה מכסה אינטרנט.'
            : await PluginNetworkPermissionMode.isStrict()
            ? 'network.access אינה מכסה יעד מקומי.'
            : 'לפני אוצריא 0.9.98.1 גם network.access מכסה יעד מקומי, '
                  'אך משם תידרש network.localhost.';
        throw Exception(
          'error.permission_denied: '
          'לתוסף אין הרשאת $what. $separation '
          'ניתן להפעיל את ההרשאה בהגדרות, תחת ניהול תוספים.',
        );
      case PluginNetworkDecision.notAllowlisted:
        throw Exception(
          isLoopbackHost(uri.host)
              ? 'error.forbidden: היעד המקומי אינו מוצהר ב-network.allowlist '
                    'של התוסף בכתובת זהה (host חשוף כמו "127.0.0.1" מתיר כל '
                    'פורט, אבל "localhost" ו-"127.0.0.1" נבדלים)'
              : 'error.forbidden: הכתובת אינה ברשימת ההיתר לגישת רשת של תוספים',
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
    final rawBody = args['body'];
    if (rawBody != null && rawBody is! String) {
      throw Exception('error.invalid_params: body must be a string');
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
      body: rawBody as String?,
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
      case 'fetchStream':
        if (args[_cancelStreamIdKey] case final String streamId) {
          return _cancelStream(
            streamId,
            _activeNetworkFetchStreams,
            _pendingNetworkFetchCancellations,
          );
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
          if (!await _isPathInGrantedFolder(destPath)) {
            throw Exception(
              'error.forbidden: destPath outside a user-selected folder',
            );
          }
          final result = await _downloadService.downloadToPath(
            uri,
            destPath,
            isAllowed: _isDownloadHopAllowed,
            isRedirectAllowed: isGithubReleaseRedirectAllowed,
            resume: resume,
          );
          return {'path': result.path, 'filename': result.filename};
        }

        final filename = args['filename'] as String?;
        final result = await _downloadService.downloadToDownloads(
          uri,
          filename: filename,
          isAllowed: _isDownloadHopAllowed,
          isRedirectAllowed: isGithubReleaseRedirectAllowed,
        );
        return {'path': result.path, 'filename': result.filename};

      case 'fetchFile':
        return await _fetchRemoteFile(args);

      default:
        throw Exception(
          'error.unknown_method: Unknown action in network: $action',
        );
    }
  }

  /// `network.fetchFile` — מוריד קובץ מ-URL מותר למטמון זמני פרטי של התוסף
  /// ומחזיר אותו כ-token של קובץ משתמש לקריאה בלבד, כמו `fs.pickUserFile`:
  /// `fs.resolveFileUrl`, `fs.revokeFile` ו-`<iframe>` עובדים עליו כרגיל.
  /// התוסף אינו מקבל נתיב דיסק והקובץ אינו נכנס לתיקיית המשתמש.
  Future<Map<String, dynamic>> _fetchRemoteFile(
    Map<String, dynamic> args,
  ) async {
    final generation = _remoteFiles.generationForPlugin(plugin.pluginId);
    final uri = await _requireAllowedNetworkUri(args);
    final timeoutMs = args['timeoutMs'];
    final maxTimeoutMs = PluginRemoteFileCache.maxTimeout.inMilliseconds;
    if (timeoutMs != null &&
        (timeoutMs is! int || timeoutMs <= 0 || timeoutMs > maxTimeoutMs)) {
      throw Exception(
        'error.invalid_params: timeoutMs must be a positive integer '
        'up to $maxTimeoutMs',
      );
    }
    final maxBytes = args['maxBytes'];
    if (maxBytes != null &&
        (maxBytes is! int ||
            maxBytes <= 0 ||
            maxBytes > PluginRemoteFileCache.maxBytesLimit)) {
      throw Exception(
        'error.invalid_params: maxBytes must be a positive integer '
        'up to ${PluginRemoteFileCache.maxBytesLimit}',
      );
    }

    if (generation != _remoteFiles.generationForPlugin(plugin.pluginId)) {
      throw Exception('error.unavailable: remote file download revoked');
    }
    final PluginRemoteFile file;
    try {
      file = await _remoteFiles.fetch(
        plugin.pluginId,
        uri,
        downloader: _downloadService,
        isAllowed: _isDownloadHopAllowed,
        isRedirectAllowed: isGithubReleaseRedirectAllowed,
        maxBytes: maxBytes ?? PluginRemoteFileCache.defaultMaxBytes,
        timeout: timeoutMs == null
            ? PluginRemoteFileCache.defaultTimeout
            : Duration(milliseconds: timeoutMs),
      );
    } on FileSystemException {
      // הודעת החריגה כוללת נתיב מוחלט (תיקיית ה-temp, שם המשתמש), והגשר
      // מחזיר לתוסף את הודעת כל חריגה שאינה מקודדת.
      throw Exception('error.internal: failed to write the downloaded file');
    }
    if (generation != _remoteFiles.generationForPlugin(plugin.pluginId)) {
      await _remoteFiles.delete(file.path);
      throw Exception('error.unavailable: remote file download revoked');
    }
    final canonical = canonicalizeNearestExisting(file.path) ?? file.path;
    final registration = await _fileServer.register(
      pluginId: plugin.pluginId,
      canonicalPath: canonical,
    );
    await _dropEvictedRemoteGrants();
    await _saveUserFileGrant(registration.token, canonical, writable: false);
    if (generation != _remoteFiles.generationForPlugin(plugin.pluginId)) {
      _fileServer.revoke(registration.token);
      await _removeUserFileGrant(registration.token);
      await _remoteFiles.delete(canonical);
      throw Exception('error.unavailable: remote file download revoked');
    }
    return {
      'token': registration.token,
      'url': registration.url,
      'name': file.name,
      'size': file.size,
      'mime': PluginFileServer.contentTypeForPath(canonical).mimeType,
    };
  }

  /// בדיקת היעד בכל קפיצה של הורדה, כולל redirect: אותה הכרעה כמו ל-URL
  /// ההתחלתי, כולל הרשאת `network.localhost` ליעדי loopback. התאמה למניפסט
  /// בלבד הייתה מאפשרת לשרת מותר להפנות ל-127.0.0.1 תוסף שאין לו הרשאה כזו.
  Future<bool> _isDownloadHopAllowed(Uri candidate) =>
      isPluginNetworkAccessAllowed(
        uri: candidate,
        pluginId: plugin.pluginId,
        manifest: plugin.manifest,
        registry: _pluginRepo,
      );

  /// מסיר מה-KV grants של קבצים שהמטמון כבר מחק (פינוי מכסה או הפעלה חדשה),
  /// כדי שלא יצטברו, ומבטל את הרישום שלהם בשרת הקבצים.
  Future<void> _dropEvictedRemoteGrants() async {
    for (final MapEntry(key: token, :value)
        in (await _readUserFileGrants()).entries) {
      final path = switch (value) {
        {'path': final String path} => path,
        _ => null,
      };
      // הנתיב ב-grant כבר קנוני, ולכן בדיקת השייכות לשורש המטמון לקסיקלית
      // וזולה; רק קובץ של המטמון נבדק בדיסק.
      if (path != null &&
          _remoteFiles.ownsCanonical(path) &&
          !File(path).existsSync()) {
        _fileServer.revoke(token);
        await _removeUserFileGrant(token);
      }
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
            'chunk': {'sequence': sequence++, 'type': 'data', 'body': fragment},
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

  Iterable<String> _splitNetworkFetchChunk(String value) sync* {
    var start = 0;
    while (start < value.length) {
      var end = math.min(start + _maxNetworkFetchChunkCodeUnits, value.length);
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
