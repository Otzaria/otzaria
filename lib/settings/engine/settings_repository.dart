import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/settings/engine/settings_wrapper.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class SettingsRepository {
  static const String keyDarkMode = 'key-dark-mode';
  static const String keyFollowSystemTheme = 'key-follow-system-theme';
  static const String keySwatchColor = 'key-swatch-color';
  static const String keyDarkSwatchColor = 'key-dark-swatch-color';
  static const String keyTextMaxWidth = 'key-text-max-width';
  static const String keyFontSize = 'key-font-size';
  static const String keyFontFamily = 'key-font-family';
  static const String keyCommentatorsFontFamily =
      'key-commentators-font-family';
  static const String keyPageShapeBottomFont = 'page_shape_bottom_font';
  static const String keyFontBold = 'key-font-bold';
  static const String keyCommentatorsFontBold = 'key-commentators-font-bold';
  static const String keyCommentatorsFontSize = 'key-commentators-font-size';
  static const String keyLineHeight = 'key-line-height';
  static const String keyShowOtzarHachochma = 'key-show-otzar-hachochma';
  static const String keyShowHebrewBooks = 'key-show-hebrew-books';
  static const String keyShowExternalBooks = 'key-show-external-books';
  static const String keyShowTeamim = 'key-show-teamim';
  static const String keyReplaceHolyNames = 'key-replace-holy-names';
  static const String keyAutoUpdateIndex = 'key-auto-index-update';
  static const String keyDefaultNikud = 'key-default-nikud';
  static const String keyRemoveNikudFromTanach = 'key-remove-nikud-tanach';
  static const String keyDefaultRemovePunctuation =
      'key-default-remove-punctuation';
  static const String keyContinuousReadingMode = 'key-continuous-reading-mode';
  static const String keyDefaultSidebarOpen = 'key-default-sidebar-open';
  static const String keyDefaultCommentaryOpen = 'key-default-commentary-open';

  /// CSV של סוגי הקישורים המוצגים בפאנל הקישורים. ריק = הכל מוצג, כדי שסוג
  /// חדש שיתווסף ל-DB יופיע מאליו ולא ייחשב כמסונן.
  static const String keySelectedLinkTypes = 'key-selected-link-types';

  static const String keyPinSidebar = 'key-pin-sidebar';
  static const String keySidebarWidth = 'key-sidebar-width';
  static const String keyFacetFilteringWidth = 'key-facet-filtering-width';
  static const String keyExternalResultsFirst = 'key-external-results-first';
  static const String keyCommentaryPaneWidth = 'key-commentary-pane-width';
  static const String keyCalendarType = 'key-calendar-type';
  static const String keyCalendarDayTransition = 'key-calendar-day-transition';
  static const String keySelectedCity = 'key-selected-city';
  static const String keyCalendarEvents = 'key-calendar-events';
  static const String keyCopyWithHeaders = 'key-copy-with-headers';
  static const String keyCopyHeaderFormat = 'key-copy-header-format';
  static const String keyIsFullscreen = 'key-is-fullscreen';
  static const String keyLibraryViewMode = 'key-library-view-mode';
  static const String keyLibraryShowPreview = 'key-library-show-preview';
  static const String keySearchShowPreview = 'key-search-show-preview';
  static const String keyEnablePerBookSettings = 'key-enable-per-book-settings';
  static const String keyPdfBookViewByDefault = 'key-pdf-book-view-by-default';
  static const String keyTalmudBavliOpenFormat = 'key-talmud-bavli-open-format';
  static const String keyOfflineMode = 'key-offline-mode';
  static const String keyAutoSync = 'key-auto-sync';
  static const String keySoftwareAndBookUpdatesEnabled =
      'key-software-and-book-updates-enabled';
  static const String keyErrorReportSenderEmail =
      'key-error-report-sender-email';
  static const String keyQueueErrorReportsWhenOffline =
      'key-queue-error-reports-when-offline';
  static const String keyLibraryPath = 'key-library-path';
  static const String keyIndexPath = 'key-index-path';
  static const String keyDatabasesPath = 'key-databases-path';
  static const String keyBackupPath = 'key-backup-path';
  static const String keyLibraryFolderName = 'key-library-folder-name';

  /// Android only: nתיב ה-DB שנגיש ל-sqlite3 native (override ל-getDatabasePath).
  /// נוצר כאשר המשתמש בחר ספרייה באחסון חיצוני ו-DB הועתק/הועבר פנימה.
  static const String keyDbEffectivePath = 'key-db-effective-path';

  /// Android only: שורש הספרייה שבחר המשתמש (למשל תיקיית האפליקציה על כרטיס
  /// SD). משפיע רק על מיקום הספרייה (ספרים/אינדקס/מסדי נתונים); שאר נתוני
  /// האפליקציה (Hive, תוספים, גיבויים) נשארים באחסון הפנימי. כשריק — הכל פנימי.
  static const String keyAndroidLibraryRoot = 'key-android-library-root';
  static const String keyHebrewBooksPath = 'key-hebrew-books-path';
  static const String keyDevChannel = 'key-dev-channel';
  static const String keyCustomFolders = 'key-custom-folders';

  /// כאשר מופעל, תיקיות מותאמות אישית ימוזגו לתוך עץ הספרייה הראשי
  /// לפי שם (במקום להופיע תחת קטגוריית "ספרים אישיים"). ברירת מחדל: כבוי.
  static const String keyMergeUserBooksIntoLibrary =
      'key-merge-user-books-into-library';
  static const String keyEnableHtmlLinks = 'key-enable-html-links';
  static const String keyPersonalNotesCollapsedByDefault =
      'key-personal-notes-collapsed';
  static const String keyCompactMenuMode = 'key-compact-menu-mode';

  /// מיקום רצועת כרטיסיות העיון: `top` בשורת הכותרת, `side` בעמודה אנכית.
  static const String keyReadingTabsPlacement = 'key-reading-tabs-placement';
  static const String keyReadingTabsColumnWidth =
      'key-reading-tabs-column-width';
  static const String keyReadingTabsColumnCollapsed =
      'key-reading-tabs-column-collapsed';

  static const String readingTabsPlacementTop = 'top';
  static const String readingTabsPlacementSide = 'side';
  static const double defaultReadingTabsColumnWidth = 220;
  static const double minReadingTabsColumnWidth = 160;
  static const double maxReadingTabsColumnWidth = 400;

  /// CSV של מזהי כלים מובנים שהמשתמש הסתיר מהממשק (לשונית הכלים).
  static const String keyHiddenBuiltInToolIds = 'key-hidden-builtin-tool-ids';

  /// CSV של מזהי כלים מובנים שהמשתמש הצמיד לסרגל הניווט הראשי.
  static const String keyBuiltInToolsPinnedToNavRail =
      'key-builtin-tools-pinned-to-nav-rail';

  /// CSV של סדר הכלים המובנים שהמשתמש קבע. הסדר משמעותי — אינו ממוין.
  static const String keyBuiltInToolsOrder = 'key-builtin-tools-order';

  // Protected Mode Settings
  static const String keyProtectedModeEnabled = 'key-protected-mode-enabled';
  static const String keyProtectedModePasswordHash =
      'key-protected-mode-password-hash';

  // Calendar Notification Settings
  static const String keyCalendarNotificationsEnabled =
      'key-calendar-notifications-enabled';
  static const String keyCalendarNotificationTime =
      'key-calendar-notification-time';
  static const String keyCalendarNotificationSound =
      'key-calendar-notification-sound';

  // Calendar per-time (zman) alerts
  static const String keyCalendarZmanAlerts = 'key-calendar-zman-alerts';

  // רשימת מזהי הזמנים המוצגים בלוח (JSON array). חסר = ברירת המחדל
  // מתוך רישום הזמנים (kDefaultEnabledZmanim).
  static const String keyCalendarEnabledZmanim = 'key-calendar-enabled-zmanim';

  // Internal tracking of scheduled calendar event notification IDs
  static const String keyCalendarEventNotificationIds =
      'key-calendar-event-notification-ids';

  // Google Calendar integration
  static const String keyGoogleCalendarEnabled = 'key-google-calendar-enabled';
  static const String keyGoogleCalendarSelectedIds =
      'key-google-calendar-selected-ids';
  static const String keyGoogleCalendarClientId =
      'key-google-calendar-client-id';
  static const String keyGoogleCalendarClientSecret =
      'key-google-calendar-client-secret';
  static const String keyGoogleCalendarCredentialsJson =
      'key-google-calendar-credentials-json';
  static const String keyGoogleCalendarSyncPastDays =
      'key-google-calendar-sync-past-days';
  static const String keyGoogleCalendarSyncFutureDays =
      'key-google-calendar-sync-future-days';
  static const String keyGoogleCalendarLastSync =
      'key-google-calendar-last-sync';
  static const String keySettingsLanguage = 'key-settings-language';

  /// כל מפתחות ההגדרות המוצהרים במחלקה זו.
  ///
  /// משמש כרשת ביטחון לגיבוי כשלא ניתן לסרוק את ה-Hive box ישירות (ראה
  /// [BackupService.backupSettingsFromKeys]). `settings_repository_all_keys_test`
  /// נכשל אם מפתח חדש הוגדר כאן ולא נוסף לרשימה — אחרת הוא נשמט מהגיבוי בשקט.
  static const List<String> allKeys = [
    keyDarkMode,
    keyFollowSystemTheme,
    keySwatchColor,
    keyDarkSwatchColor,
    keyTextMaxWidth,
    keyFontSize,
    keyFontFamily,
    keyCommentatorsFontFamily,
    keyPageShapeBottomFont,
    keyFontBold,
    keyCommentatorsFontBold,
    keyCommentatorsFontSize,
    keyLineHeight,
    keyShowOtzarHachochma,
    keyShowHebrewBooks,
    keyShowExternalBooks,
    keyShowTeamim,
    keyReplaceHolyNames,
    keyAutoUpdateIndex,
    keyDefaultNikud,
    keyRemoveNikudFromTanach,
    keyDefaultRemovePunctuation,
    keyContinuousReadingMode,
    keyDefaultSidebarOpen,
    keyDefaultCommentaryOpen,
    keySelectedLinkTypes,
    keyPinSidebar,
    keySidebarWidth,
    keyFacetFilteringWidth,
    keyExternalResultsFirst,
    keyCommentaryPaneWidth,
    keyCalendarType,
    keyCalendarDayTransition,
    keySelectedCity,
    keyCalendarEvents,
    keyCopyWithHeaders,
    keyCopyHeaderFormat,
    keyIsFullscreen,
    keyLibraryViewMode,
    keyLibraryShowPreview,
    keySearchShowPreview,
    keyEnablePerBookSettings,
    keyPdfBookViewByDefault,
    keyTalmudBavliOpenFormat,
    keyOfflineMode,
    keyAutoSync,
    keySoftwareAndBookUpdatesEnabled,
    keyErrorReportSenderEmail,
    keyQueueErrorReportsWhenOffline,
    keyLibraryPath,
    keyIndexPath,
    keyDatabasesPath,
    keyBackupPath,
    keyLibraryFolderName,
    keyDbEffectivePath,
    keyAndroidLibraryRoot,
    keyHebrewBooksPath,
    keyDevChannel,
    keyCustomFolders,
    keyMergeUserBooksIntoLibrary,
    keyEnableHtmlLinks,
    keyPersonalNotesCollapsedByDefault,
    keyCompactMenuMode,
    keyReadingTabsPlacement,
    keyReadingTabsColumnWidth,
    keyReadingTabsColumnCollapsed,
    keyHiddenBuiltInToolIds,
    keyBuiltInToolsPinnedToNavRail,
    keyBuiltInToolsOrder,
    keyProtectedModeEnabled,
    keyProtectedModePasswordHash,
    keyCalendarNotificationsEnabled,
    keyCalendarNotificationTime,
    keyCalendarNotificationSound,
    keyCalendarZmanAlerts,
    keyCalendarEnabledZmanim,
    keyCalendarEventNotificationIds,
    keyGoogleCalendarEnabled,
    keyGoogleCalendarSelectedIds,
    keyGoogleCalendarClientId,
    keyGoogleCalendarClientSecret,
    keyGoogleCalendarCredentialsJson,
    keyGoogleCalendarSyncPastDays,
    keyGoogleCalendarSyncFutureDays,
    keyGoogleCalendarLastSync,
    keySettingsLanguage,
  ];

  final SettingsWrapper _settings;

  SettingsRepository({SettingsWrapper? settings})
    : _settings = settings ?? SettingsWrapper();

  Future<Map<String, dynamic>> loadSettings() async {
    // Initialize default settings to disk if needed
    await _initializeDefaultsIfNeeded();
    await removeUnrecognizedShortcuts();

    return {
      'isDarkMode': _settings.getValue<bool>(keyDarkMode, defaultValue: false),
      'followSystemTheme': _settings.getValue<bool>(
        keyFollowSystemTheme,
        defaultValue: false,
      ),
      'seedColor': Color(
        _settings.getValue<int>(
          keySwatchColor,
          defaultValue: AppSeedColors.defaultLight.toARGB32(),
        ),
      ),
      'darkSeedColor': Color(
        _settings.getValue<int>(
          keyDarkSwatchColor,
          defaultValue: AppSeedColors.defaultDark.toARGB32(),
        ),
      ),
      'textMaxWidth': _settings.getValue<double>(
        keyTextMaxWidth,
        defaultValue: -1,
      ),
      'fontSize': _settings.getValue<double>(keyFontSize, defaultValue: 25),
      'fontFamily': _settings.getValue<String>(
        keyFontFamily,
        defaultValue: AppFonts.defaultFont,
      ),
      'commentatorsFontFamily': _settings.getValue<String>(
        keyCommentatorsFontFamily,
        defaultValue: AppFonts.defaultCommentatorsFont,
      ),
      'pageShapeBottomFont': _settings.getValue<String>(
        keyPageShapeBottomFont,
        defaultValue: AppFonts.defaultFont,
      ),
      'fontBold': _settings.getValue<bool>(keyFontBold, defaultValue: false),
      'commentatorsFontBold': _settings.getValue<bool>(
        keyCommentatorsFontBold,
        defaultValue: false,
      ),
      'commentatorsFontSize': _settings.getValue<double>(
        keyCommentatorsFontSize,
        defaultValue: 22,
      ),
      'lineHeight': _settings.getValue<double>(
        keyLineHeight,
        defaultValue: 1.5,
      ),
      'showOtzarHachochma': _settings.getValue<bool>(
        keyShowOtzarHachochma,
        defaultValue: false,
      ),
      'showHebrewBooks': _settings.getValue<bool>(
        keyShowHebrewBooks,
        defaultValue: false,
      ),
      'showExternalBooks': _settings.getValue<bool>(
        keyShowExternalBooks,
        defaultValue: false,
      ),
      'showTeamim': _settings.getValue<bool>(
        keyShowTeamim,
        defaultValue: true,
      ),
      'replaceHolyNames': _settings.getValue<bool>(
        keyReplaceHolyNames,
        defaultValue: true,
      ),
      'autoUpdateIndex': _settings.getValue<bool>(
        keyAutoUpdateIndex,
        defaultValue: true,
      ),
      'defaultRemoveNikud': _settings.getValue<bool>(
        keyDefaultNikud,
        defaultValue: false,
      ),
      'removeNikudFromTanach': _settings.getValue<bool>(
        keyRemoveNikudFromTanach,
        defaultValue: false,
      ),
      'defaultRemovePunctuation': _settings.getValue<bool>(
        keyDefaultRemovePunctuation,
        defaultValue: false,
      ),
      'defaultContinuousReadingMode': _settings.getValue<bool>(
        keyContinuousReadingMode,
        defaultValue: false,
      ),
      'defaultSidebarOpen': _settings.getValue<bool>(
        keyDefaultSidebarOpen,
        defaultValue: false,
      ),
      'defaultCommentaryOpen': _settings.getValue<bool>(
        keyDefaultCommentaryOpen,
        defaultValue: false,
      ),
      'pinSidebar': _settings.getValue<bool>(
        keyPinSidebar,
        defaultValue: false,
      ),
      'sidebarWidth': _settings.getValue<double>(
        keySidebarWidth,
        defaultValue: 300,
      ),
      'facetFilteringWidth': _settings.getValue<double>(
        keyFacetFilteringWidth,
        defaultValue: 235,
      ),
      'externalResultsFirst': _settings.getValue<bool>(
        keyExternalResultsFirst,
        defaultValue: false,
      ),
      'commentaryPaneWidth': _settings.getValue<double>(
        keyCommentaryPaneWidth,
        defaultValue: 400,
      ),
      'calendarType': _settings.getValue<String>(
        keyCalendarType,
        defaultValue: 'combined',
      ),
      'calendarDayTransition': _settings.getValue<String>(
        keyCalendarDayTransition,
        defaultValue: 'sunset',
      ),
      'selectedCity': _settings.getValue<String>(
        keySelectedCity,
        defaultValue: 'ירושלים',
      ),
      'calendarEvents': _settings.getValue<String>(
        keyCalendarEvents,
        defaultValue: '[]',
      ),
      'copyWithHeaders': _settings.getValue<String>(
        keyCopyWithHeaders,
        defaultValue: 'none',
      ),
      'copyHeaderFormat': _settings.getValue<String>(
        keyCopyHeaderFormat,
        defaultValue: 'same_line_after_brackets',
      ),
      'isFullscreen': _settings.getValue<bool>(
        keyIsFullscreen,
        defaultValue: false,
      ),
      'libraryViewMode': _settings.getValue<String>(
        keyLibraryViewMode,
        defaultValue: 'grid',
      ),
      'libraryShowPreview': _settings.getValue<bool>(
        keyLibraryShowPreview,
        defaultValue: true,
      ),
      'searchShowPreview': _settings.getValue<bool>(
        keySearchShowPreview,
        defaultValue: true,
      ),
      'shortcuts': await getShortcuts(),
      'enablePerBookSettings': _settings.getValue<bool>(
        keyEnablePerBookSettings,
        defaultValue: false,
      ),
      'pdfBookViewByDefault': _settings.getValue<bool>(
        keyPdfBookViewByDefault,
        defaultValue: false,
      ),
      'talmudBavliOpenFormat': _settings.getValue<String>(
        keyTalmudBavliOpenFormat,
        defaultValue: 'text',
      ),
      'isOfflineMode': _settings.getValue<bool>(
        keyOfflineMode,
        defaultValue: false,
      ),
      'softwareAndBookUpdatesEnabled': _settings.getValue<bool>(
        keySoftwareAndBookUpdatesEnabled,
        defaultValue: true,
      ),
      'enableHtmlLinks': _settings.getValue<bool>(
        keyEnableHtmlLinks,
        defaultValue: true,
      ),
      'personalNotesCollapsedByDefault': _settings.getValue<bool>(
        keyPersonalNotesCollapsedByDefault,
        defaultValue: true,
      ),
      'compactMenuMode': _settings.getValue<bool>(
        keyCompactMenuMode,
        defaultValue: false,
      ),
      'readingTabsPlacement': _settings.getValue<String>(
        keyReadingTabsPlacement,
        defaultValue: readingTabsPlacementTop,
      ),
      'readingTabsColumnWidth': _settings.getValue<double>(
        keyReadingTabsColumnWidth,
        defaultValue: defaultReadingTabsColumnWidth,
      ),
      'readingTabsColumnCollapsed': _settings.getValue<bool>(
        keyReadingTabsColumnCollapsed,
        defaultValue: false,
      ),
      'mergeUserBooksIntoLibrary': _settings.getValue<bool>(
        keyMergeUserBooksIntoLibrary,
        defaultValue: false,
      ),
      'hiddenBuiltInToolIds': _parseToolIdSet(
        _settings.getValue<String>(
          keyHiddenBuiltInToolIds,
          defaultValue: '',
        ),
      ),
      'builtInToolsPinnedToNavRail': _parseToolIdSet(
        _settings.getValue<String>(
          keyBuiltInToolsPinnedToNavRail,
          defaultValue: '',
        ),
      ),
      'builtInToolsOrder': _parseToolIdList(
        _settings.getValue<String>(
          keyBuiltInToolsOrder,
          defaultValue: '',
        ),
      ),

      // Protected Mode
      'protectedModeEnabled': _settings.getValue<bool>(
        keyProtectedModeEnabled,
        defaultValue: false,
      ),

      // Calendar Notification Settings
      'calendarNotificationsEnabled': _settings.getValue<bool>(
        keyCalendarNotificationsEnabled,
        defaultValue: true,
      ),
      'calendarNotificationTime': _settings.getValue<int>(
        keyCalendarNotificationTime,
        defaultValue: 60,
      ),
      'calendarNotificationSound': _settings.getValue<bool>(
        keyCalendarNotificationSound,
        defaultValue: true,
      ),

      // Calendar per-time (zman) alerts
      'calendarZmanAlerts': _settings.getValue<String>(
        keyCalendarZmanAlerts,
        defaultValue: '{}',
      ),

      // Enabled zmanim ids (JSON array). '' = use registry defaults.
      'calendarEnabledZmanim': _settings.getValue<String>(
        keyCalendarEnabledZmanim,
        defaultValue: '',
      ),

      // Google Calendar integration
      'googleCalendarEnabled': _settings.getValue<bool>(
        keyGoogleCalendarEnabled,
        defaultValue: false,
      ),
      'googleCalendarSelectedIds': _settings.getValue<String>(
        keyGoogleCalendarSelectedIds,
        defaultValue: 'primary',
      ),
      'googleCalendarClientId': _settings.getValue<String>(
        keyGoogleCalendarClientId,
        defaultValue: '',
      ),
      'googleCalendarClientSecret': _settings.getValue<String>(
        keyGoogleCalendarClientSecret,
        defaultValue: '',
      ),
      'googleCalendarCredentialsJson': _settings.getValue<String>(
        keyGoogleCalendarCredentialsJson,
        defaultValue: '',
      ),
      'googleCalendarSyncPastDays': _settings.getValue<int>(
        keyGoogleCalendarSyncPastDays,
        defaultValue: 60,
      ),
      'googleCalendarSyncFutureDays': _settings.getValue<int>(
        keyGoogleCalendarSyncFutureDays,
        defaultValue: 365,
      ),
      'googleCalendarLastSync': _settings.getValue<int>(
        keyGoogleCalendarLastSync,
        defaultValue: 0,
      ),

      // שפת מסך ההגדרות בלבד. משתמש קיים שאין לו את המפתח מקבל זיהוי אוטומטי.
      'settingsLanguageCode': _settings.getValue<String>(
        keySettingsLanguage,
        defaultValue: kDefaultSettingsLanguageCode,
      ),
    };
  }

  Future<void> updateSettingsLanguageCode(String value) async {
    await _settings.setValue(keySettingsLanguage, value);
  }

  Future<void> updateDarkMode(bool value) async {
    await _settings.setValue(keyDarkMode, value);
  }

  Future<void> updateFollowSystemTheme(bool value) async {
    await _settings.setValue(keyFollowSystemTheme, value);
  }

  Future<void> updateSeedColor(Color value) async {
    await _settings.setValue(keySwatchColor, value.toARGB32());
  }

  Future<void> updateDarkSeedColor(Color value) async {
    await _settings.setValue(keyDarkSwatchColor, value.toARGB32());
  }

  Future<void> updateTextMaxWidth(double value) async {
    await _settings.setValue(keyTextMaxWidth, value);
  }

  Future<void> updateFontSize(double value) async {
    await _settings.setValue(keyFontSize, value);
  }

  Future<void> updateFontFamily(String value) async {
    await _settings.setValue(keyFontFamily, value);
  }

  Future<void> updateCommentatorsFontFamily(String value) async {
    await _settings.setValue(keyCommentatorsFontFamily, value);
  }

  Future<void> updateFontBold(bool value) async {
    await _settings.setValue(keyFontBold, value);
  }

  Future<void> updateCommentatorsFontBold(bool value) async {
    await _settings.setValue(keyCommentatorsFontBold, value);
  }

  Future<void> updateCommentatorsFontSize(double value) async {
    await _settings.setValue(keyCommentatorsFontSize, value);
  }

  Future<void> updateLineHeight(double value) async {
    await _settings.setValue(keyLineHeight, value);
  }

  Future<void> updateShowOtzarHachochma(bool value) async {
    await _settings.setValue(keyShowOtzarHachochma, value);
  }

  Future<void> updateShowHebrewBooks(bool value) async {
    await _settings.setValue(keyShowHebrewBooks, value);
  }

  Future<void> updateShowExternalBooks(bool value) async {
    await _settings.setValue(keyShowExternalBooks, value);
  }

  Future<void> updateShowTeamim(bool value) async {
    await _settings.setValue(keyShowTeamim, value);
  }

  Future<void> updateReplaceHolyNames(bool value) async {
    await _settings.setValue(keyReplaceHolyNames, value);
  }

  Future<void> updateAutoUpdateIndex(bool value) async {
    await _settings.setValue(keyAutoUpdateIndex, value);
  }

  Future<void> updateDefaultRemoveNikud(bool value) async {
    await _settings.setValue(keyDefaultNikud, value);
  }

  Future<void> updateRemoveNikudFromTanach(bool value) async {
    await _settings.setValue(keyRemoveNikudFromTanach, value);
  }

  Future<void> updateDefaultRemovePunctuation(bool value) async {
    await _settings.setValue(keyDefaultRemovePunctuation, value);
  }

  Future<void> updateDefaultContinuousReadingMode(bool value) async {
    await _settings.setValue(keyContinuousReadingMode, value);
  }

  Future<void> updateDefaultSidebarOpen(bool value) async {
    await _settings.setValue(keyDefaultSidebarOpen, value);
  }

  Future<void> updateDefaultCommentaryOpen(bool value) async {
    await _settings.setValue(keyDefaultCommentaryOpen, value);
  }

  Future<void> updatePinSidebar(bool value) async {
    await _settings.setValue(keyPinSidebar, value);
  }

  Future<void> updateSidebarWidth(double value) async {
    await _settings.setValue(keySidebarWidth, value);
  }

  Future<void> updateFacetFilteringWidth(double value) async {
    await _settings.setValue(keyFacetFilteringWidth, value);
  }

  Future<void> updateExternalResultsFirst(bool value) async {
    await _settings.setValue(keyExternalResultsFirst, value);
  }

  Future<void> updateCommentaryPaneWidth(double value) async {
    await _settings.setValue(keyCommentaryPaneWidth, value);
  }

  Future<void> updateCalendarType(String value) async {
    await _settings.setValue(keyCalendarType, value);
  }

  Future<void> updateCalendarDayTransition(String value) async {
    await _settings.setValue(keyCalendarDayTransition, value);
  }

  Future<void> updateSelectedCity(String value) async {
    await _settings.setValue(keySelectedCity, value);
  }

  Future<void> updateCalendarEvents(String eventsJson) async {
    await _settings.setValue(keyCalendarEvents, eventsJson);
  }

  Future<void> updateCopyWithHeaders(String value) async {
    await _settings.setValue(keyCopyWithHeaders, value);
  }

  Future<void> updateCopyHeaderFormat(String value) async {
    await _settings.setValue(keyCopyHeaderFormat, value);
  }

  Future<void> updateIsFullscreen(bool value) async {
    await _settings.setValue(keyIsFullscreen, value);
  }

  Future<void> updateLibraryViewMode(String value) async {
    await _settings.setValue(keyLibraryViewMode, value);
  }

  Future<void> updateLibraryShowPreview(bool value) async {
    await _settings.setValue(keyLibraryShowPreview, value);
  }

  Future<void> updateSearchShowPreview(bool value) async {
    await _settings.setValue(keySearchShowPreview, value);
  }

  Future<void> updateEnablePerBookSettings(bool value) async {
    await _settings.setValue(keyEnablePerBookSettings, value);
  }

  Future<void> updatePdfBookViewByDefault(bool value) async {
    await _settings.setValue(keyPdfBookViewByDefault, value);
  }

  Future<void> updateTalmudBavliOpenFormat(String value) async {
    await _settings.setValue(keyTalmudBavliOpenFormat, value);
  }

  Future<void> updateOfflineMode(bool value) async {
    await _settings.setValue(keyOfflineMode, value);
  }

  Future<void> updateSoftwareAndBookUpdatesEnabled(bool value) async {
    await _settings.setValue(keySoftwareAndBookUpdatesEnabled, value);
  }

  Future<void> updateEnableHtmlLinks(bool value) async {
    await _settings.setValue(keyEnableHtmlLinks, value);
  }

  Future<void> updatePersonalNotesCollapsedByDefault(bool value) async {
    await _settings.setValue(keyPersonalNotesCollapsedByDefault, value);
  }

  Future<void> updateCompactMenuMode(bool value) async {
    await _settings.setValue(keyCompactMenuMode, value);
  }

  Future<void> updateReadingTabsPlacement(String value) async {
    await _settings.setValue(keyReadingTabsPlacement, value);
  }

  Future<void> updateReadingTabsColumnWidth(double value) async {
    await _settings.setValue(keyReadingTabsColumnWidth, value);
  }

  Future<void> updateReadingTabsColumnCollapsed(bool value) async {
    await _settings.setValue(keyReadingTabsColumnCollapsed, value);
  }

  Future<void> updateMergeUserBooksIntoLibrary(bool value) async {
    await _settings.setValue(keyMergeUserBooksIntoLibrary, value);
  }

  Future<void> updateHiddenBuiltInToolIds(Set<String> value) async {
    await _settings.setValue(
      keyHiddenBuiltInToolIds,
      _serializeToolIdSet(value),
    );
  }

  Future<void> updateBuiltInToolsPinnedToNavRail(Set<String> value) async {
    await _settings.setValue(
      keyBuiltInToolsPinnedToNavRail,
      _serializeToolIdSet(value),
    );
  }

  Future<void> updateBuiltInToolsOrder(List<String> value) async {
    await _settings.setValue(keyBuiltInToolsOrder, value.join(','));
  }

  /// פירוק רשימת מזהי כלים מ-CSV. מתעלם מערכים ריקים ומ-whitespace.
  static Set<String> _parseToolIdSet(String raw) {
    if (raw.isEmpty) return <String>{};
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// פירוק סדר מזהי כלים מ-CSV, תוך שמירת הסדר וללא כפילויות.
  static List<String> _parseToolIdList(String raw) {
    if (raw.isEmpty) return const <String>[];
    final seen = <String>{};
    return [
      for (final id in raw.split(','))
        if (id.trim().isNotEmpty && seen.add(id.trim())) id.trim(),
    ];
  }

  /// סדרת מזהי כלים ל-CSV. ממוין דטרמיניסטית.
  static String _serializeToolIdSet(Set<String> value) {
    final list = value.toList()..sort();
    return list.join(',');
  }

  // Protected Mode
  Future<void> updateProtectedModeEnabled(bool value) async {
    await _settings.setValue(keyProtectedModeEnabled, value);
  }

  Future<void> updateProtectedModePassword(String password) async {
    final hash = _hashPassword(password);
    await _settings.setValue(keyProtectedModePasswordHash, hash);
  }

  bool verifyProtectedModePassword(String password) {
    final storedHash = _settings.getValue<String>(
      keyProtectedModePasswordHash,
      defaultValue: '',
    );

    if (storedHash.isEmpty) {
      return false;
    }

    final inputHash = _hashPassword(password);
    return inputHash == storedHash;
  }

  bool hasProtectedModePassword() {
    final hash = _settings.getValue<String>(
      keyProtectedModePasswordHash,
      defaultValue: '',
    );
    return hash.isNotEmpty;
  }

  Future<void> clearProtectedModePassword() async {
    await _settings.remove(keyProtectedModePasswordHash);
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  // Calendar Notification Settings
  Future<void> updateCalendarNotificationsEnabled(bool value) async {
    await _settings.setValue(keyCalendarNotificationsEnabled, value);
  }

  Future<void> updateCalendarNotificationTime(int value) async {
    await _settings.setValue(keyCalendarNotificationTime, value);
  }

  Future<void> updateCalendarNotificationSound(bool value) async {
    await _settings.setValue(keyCalendarNotificationSound, value);
  }

  String getCalendarZmanAlertsJson() {
    return _settings.getValue<String>(
      keyCalendarZmanAlerts,
      defaultValue: '{}',
    );
  }

  Future<void> updateCalendarZmanAlertsJson(String json) async {
    await _settings.setValue(keyCalendarZmanAlerts, json);
  }

  Future<void> updateCalendarEnabledZmanim(String json) async {
    await _settings.setValue(keyCalendarEnabledZmanim, json);
  }

  String getCalendarEventNotificationIdsJson() {
    return _settings.getValue<String>(
      keyCalendarEventNotificationIds,
      defaultValue: '[]',
    );
  }

  Future<void> updateCalendarEventNotificationIdsJson(String json) async {
    await _settings.setValue(keyCalendarEventNotificationIds, json);
  }

  // Google Calendar integration
  String getGoogleCalendarCredentialsJson() {
    return _settings.getValue<String>(
      keyGoogleCalendarCredentialsJson,
      defaultValue: '',
    );
  }

  String getGoogleCalendarClientId() {
    return _settings.getValue<String>(
      keyGoogleCalendarClientId,
      defaultValue: '',
    );
  }

  String getGoogleCalendarClientSecret() {
    return _settings.getValue<String>(
      keyGoogleCalendarClientSecret,
      defaultValue: '',
    );
  }

  Future<void> updateGoogleCalendarEnabled(bool value) async {
    await _settings.setValue(keyGoogleCalendarEnabled, value);
  }

  Future<void> updateGoogleCalendarSelectedIds(List<String> value) async {
    await _settings.setValue(keyGoogleCalendarSelectedIds, value.join(','));
  }

  Future<void> updateGoogleCalendarClientId(String value) async {
    await _settings.setValue(keyGoogleCalendarClientId, value);
  }

  Future<void> updateGoogleCalendarClientSecret(String value) async {
    await _settings.setValue(keyGoogleCalendarClientSecret, value);
  }

  Future<void> updateGoogleCalendarCredentialsJson(String value) async {
    await _settings.setValue(keyGoogleCalendarCredentialsJson, value);
  }

  Future<void> updateGoogleCalendarSyncPastDays(int value) async {
    await _settings.setValue(keyGoogleCalendarSyncPastDays, value);
  }

  Future<void> updateGoogleCalendarSyncFutureDays(int value) async {
    await _settings.setValue(keyGoogleCalendarSyncFutureDays, value);
  }

  Future<void> updateGoogleCalendarLastSync(int value) async {
    await _settings.setValue(keyGoogleCalendarLastSync, value);
  }

  Future<Map<String, String>> getShortcuts() async {
    // Start with the default shortcuts
    final shortcuts = Map<String, String>.from(
      ShortcutValidator.defaultShortcuts,
    );

    // Load the central 'shortcuts' map which contains overrides
    final savedShortcutsRaw = _settings.getValue<Map<dynamic, dynamic>>(
      'shortcuts',
      defaultValue: <dynamic, dynamic>{},
    );
    final savedShortcutsMap = Map<String, dynamic>.from(savedShortcutsRaw);
    shortcuts.addAll(savedShortcutsMap.cast<String, String>());

    // Load individual shortcut keys, which take the highest precedence
    // This is important for custom shortcuts set via the dialog
    for (final key in ShortcutValidator.shortcutKeys) {
      final value = _settings.getValue<String?>(key, defaultValue: null);
      if (value != null) {
        shortcuts[key] = value;
      }
    }

    for (final entry in ShortcutValidator.legacyShortcutAliases.entries) {
      final canonicalKey = entry.key;
      final hasCanonicalOverride =
          shortcuts[canonicalKey] !=
          ShortcutValidator.defaultShortcuts[canonicalKey];
      if (hasCanonicalOverride) continue;

      for (final legacyKey in entry.value) {
        final legacyValue = _settings.getValue<String?>(
          legacyKey,
          defaultValue: savedShortcutsMap[legacyKey] as String?,
        );
        if (legacyValue != null && legacyValue.isNotEmpty) {
          shortcuts[canonicalKey] = legacyValue;
          break;
        }
      }
    }

    return Map<String, String>.unmodifiable(shortcuts);
  }

  /// מוחק קיצורים שמורים שהמקש שלהם אינו מוכר, כך שהפעולה חוזרת לקיצור
  /// ברירת המחדל שעובד. קיצור שהוקלט בפריסה לא-לטינית לפני שההקלטה נורמלה
  /// נשמר עם התו המקומי (`ctrl+shift+כ`) ולעולם אינו נתפס.
  Future<void> removeUnrecognizedShortcuts() async {
    final storedRaw = _settings.getValue<Map<dynamic, dynamic>>(
      'shortcuts',
      defaultValue: <dynamic, dynamic>{},
    );
    final stored = Map<String, dynamic>.from(storedRaw).cast<String, String>();

    final keysToCheck = <String>{
      ...ShortcutValidator.shortcutKeys,
      ...ShortcutValidator.legacyShortcutAliases.values.expand((keys) => keys),
      ...stored.keys,
    };

    for (final key in keysToCheck) {
      final value = _settings.getValue<String?>(key, defaultValue: null);
      if (value != null && !ShortcutHelper.isRecognized(value)) {
        await _settings.remove(key);
      }
    }

    final cleaned = Map<String, String>.from(stored)
      ..removeWhere((_, value) => !ShortcutHelper.isRecognized(value));
    if (cleaned.length != stored.length) {
      await _settings.setValue('shortcuts', cleaned);
    }
  }

  Future<void> resetShortcuts() async {
    // Remove all individual shortcut settings
    for (final key in ShortcutValidator.shortcutKeys) {
      await _settings.remove(key);
    }
    for (final legacyKeys in ShortcutValidator.legacyShortcutAliases.values) {
      for (final legacyKey in legacyKeys) {
        await _settings.remove(legacyKey);
      }
    }
    // Set the main shortcuts map back to the default values
    await _settings.setValue('shortcuts', ShortcutValidator.defaultShortcuts);
  }

  Future<void> updateShortcut(String key, String value) async {
    final canonicalKey = ShortcutValidator.canonicalSettingKey(key);

    // Update the individual setting key for the UI
    await _settings.setValue(canonicalKey, value);
    for (final legacyKey in ShortcutValidator.legacyKeysFor(canonicalKey)) {
      await _settings.remove(legacyKey);
    }

    // Update the central shortcuts map for the application logic
    final storedShortcutsRaw = _settings.getValue<Map<dynamic, dynamic>>(
      'shortcuts',
      defaultValue: <dynamic, dynamic>{},
    );
    final storedShortcuts = Map<String, dynamic>.from(storedShortcutsRaw);
    final updatedShortcuts = Map<String, String>.from(
      storedShortcuts.cast<String, String>(),
    );
    updatedShortcuts[canonicalKey] = value;
    for (final legacyKey in ShortcutValidator.legacyKeysFor(canonicalKey)) {
      updatedShortcuts.remove(legacyKey);
    }
    await _settings.setValue('shortcuts', updatedShortcuts);
  }

  /// Initialize default settings to disk if this is the first app launch
  Future<void> _initializeDefaultsIfNeeded() async {
    if (!_settings.getValue<bool>(
      'settings_initialized',
      defaultValue: false,
    )) {
      await _writeDefaultsToStorage();
    }
  }

  /// Write all default settings to persistent storage
  Future<void> _writeDefaultsToStorage() async {
    await _settings.setValue(keyDarkMode, false);
    await _settings.setValue(
      keySwatchColor,
      AppSeedColors.defaultLight.toARGB32(),
    );
    await _settings.setValue(
      keyDarkSwatchColor,
      AppSeedColors.defaultDark.toARGB32(),
    );
    await _settings.setValue(keyTextMaxWidth, -1.0);
    await _settings.setValue(keyFontSize, 25.0);
    await _settings.setValue(keyFontFamily, AppFonts.defaultFont);
    await _settings.setValue(
      keyCommentatorsFontFamily,
      AppFonts.defaultCommentatorsFont,
    );
    await _settings.setValue(keyFontBold, false);
    await _settings.setValue(keyCommentatorsFontBold, false);
    await _settings.setValue(keyCommentatorsFontSize, 22.0);
    await _settings.setValue(keyLineHeight, 1.5);
    await _settings.setValue(keyShowOtzarHachochma, false);
    await _settings.setValue(keyShowHebrewBooks, false);
    await _settings.setValue(keyShowExternalBooks, false);
    await _settings.setValue(keyShowTeamim, true);
    await _settings.setValue(keyReplaceHolyNames, true);
    await _settings.setValue(keyAutoUpdateIndex, true);
    await _settings.setValue(keyDefaultNikud, false);
    await _settings.setValue(keyRemoveNikudFromTanach, false);
    await _settings.setValue(keyContinuousReadingMode, false);
    await _settings.setValue(keyDefaultSidebarOpen, false);
    await _settings.setValue(keyDefaultCommentaryOpen, false);
    await _settings.setValue(keyPinSidebar, false);
    await _settings.setValue(keySidebarWidth, 300.0);
    await _settings.setValue(keyFacetFilteringWidth, 235.0);
    await _settings.setValue(keyExternalResultsFirst, false);
    await _settings.setValue(keyCommentaryPaneWidth, 400.0);
    await _settings.setValue(keyCalendarType, 'combined');
    await _settings.setValue(keyCalendarDayTransition, 'sunset');
    await _settings.setValue(keySelectedCity, 'ירושלים');
    await _settings.setValue(keyCalendarEvents, '[]');
    await _settings.setValue(keyCopyWithHeaders, 'none');
    await _settings.setValue(keyCopyHeaderFormat, 'same_line_after_brackets');
    await _settings.setValue(keyIsFullscreen, false);
    await _settings.setValue(keyLibraryViewMode, 'grid');
    await _settings.setValue(keyLibraryShowPreview, true);
    await _settings.setValue(keySearchShowPreview, true);
    await _settings.setValue(keyEnablePerBookSettings, false);
    await _settings.setValue(keyPdfBookViewByDefault, false);
    await _settings.setValue(keyTalmudBavliOpenFormat, 'text');
    await _settings.setValue(keySoftwareAndBookUpdatesEnabled, true);
    await _settings.setValue(keyErrorReportSenderEmail, '');
    await _settings.setValue(keyQueueErrorReportsWhenOffline, true);
    await _settings.setValue(keyPersonalNotesCollapsedByDefault, true);

    // Calendar Notification Settings
    await _settings.setValue(keyCalendarNotificationsEnabled, true);
    await _settings.setValue(keyCalendarNotificationTime, 60);
    await _settings.setValue(keyCalendarNotificationSound, true);

    // Calendar per-time (zman) alerts
    await _settings.setValue(keyCalendarZmanAlerts, '{}');

    // Internal tracking of scheduled calendar event notification IDs
    await _settings.setValue(keyCalendarEventNotificationIds, '[]');

    // Google Calendar integration defaults
    await _settings.setValue(keyGoogleCalendarEnabled, false);
    await _settings.setValue(keyGoogleCalendarSelectedIds, 'primary');
    await _settings.setValue(keyGoogleCalendarClientId, '');
    await _settings.setValue(keyGoogleCalendarClientSecret, '');
    await _settings.setValue(keyGoogleCalendarCredentialsJson, '');
    await _settings.setValue(keyGoogleCalendarSyncPastDays, 60);
    await _settings.setValue(keyGoogleCalendarSyncFutureDays, 365);
    await _settings.setValue(keyGoogleCalendarLastSync, 0);

    // Protected Mode defaults
    await _settings.setValue(keyProtectedModeEnabled, false);

    // מיזוג תיקיות מותאמות אישית לעץ הספרייה — ברירת מחדל כבוי
    await _settings.setValue(keyMergeUserBooksIntoLibrary, false);

    await _settings.setValue('settings_initialized', true);
  }
}
