import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

class SettingsState extends Equatable {
  final bool isDarkMode;
  final bool followSystemTheme;
  final Color seedColor;
  final Color darkSeedColor;
  // רוחב מקסימלי לטקסט: שלילי = רמה באחוזים (-2 = 90%), 0 = ללא הגבלה,
  // חיובי = פיקסלים (פורמט ישן, נשמר לתאימות)
  final double textMaxWidth;
  final double fontSize;
  final String fontFamily;
  final String commentatorsFontFamily;

  /// הצגת גופן הטקסט הראשי במשקל מודגש (בולד).
  final bool fontBold;

  /// הצגת גופן המפרשים במשקל מודגש (בולד).
  final bool commentatorsFontBold;
  final double commentatorsFontSize;
  final double
  lineHeight; // מרווח בין שורות (1.0 = רגיל, 1.5 = מרווח וחצי, וכו')
  final bool showOtzarHachochma;
  final bool showHebrewBooks;
  final bool showExternalBooks;
  final bool showTeamim;
  final bool replaceHolyNames;
  final bool autoUpdateIndex;
  final bool defaultRemoveNikud;
  final bool removeNikudFromTanach;

  /// ברירת מחדל להסרת סימני פיסוק בפתיחת ספר (אינה חלה על ספרי תנ"ך).
  final bool defaultRemovePunctuation;

  /// ברירת מחדל להצגת הטקסט ברצף (מצב "קריאה רציפה"). חלה בפתיחת ספר על
  /// ספרים שתומכים בכך בלבד (תנ"ך ותלמוד); בשאר הספרים אין לה השפעה.
  final bool defaultContinuousReadingMode;
  final bool defaultSidebarOpen;
  final bool defaultCommentaryOpen;
  final bool pinSidebar;
  final double sidebarWidth;
  final double facetFilteringWidth;

  /// מיקום בלוק התוצאות ממקור חיצוני (תוסף) במסך החיפוש: true — קודמות
  /// (בראש הרשימה והעץ), false — מאוחרות (בסופם; ברירת המחדל).
  final bool externalResultsFirst;
  final double commentaryPaneWidth;
  final String copyWithHeaders;
  final String copyHeaderFormat;
  final bool isFullscreen;
  final String libraryViewMode;
  final bool libraryShowPreview;
  final bool searchShowPreview;
  final Map<String, String> shortcuts;
  final bool enablePerBookSettings;
  final bool pdfBookViewByDefault;
  final String talmudBavliOpenFormat;
  final bool isOfflineMode;
  final bool enableHtmlLinks;
  final bool personalNotesCollapsedByDefault;
  final bool protectedModeEnabled;

  /// האם הוגדרה סיסמה למצב סייפר. נגזר מה-repository בטעינה ומעודכן בעת שמירה,
  /// כדי שה-UI יתרענן ריאקטיבית גם כשהמצב המוגן עצמו לא מופעל.
  final bool protectedModePasswordSet;
  final bool compactMenuMode;

  /// מיקום כרטיסיות העיון: `top` ברצועת הכותרת, `side` בעמודה אנכית.
  final String readingTabsPlacement;
  final double readingTabsColumnWidth;
  final bool readingTabsColumnCollapsed;

  /// מיזוג תיקיות מותאמות אישית לתוך עץ הספרייה הראשי לפי שם.
  final bool mergeUserBooksIntoLibrary;

  /// מזהי כלים מובנים שהמשתמש בחר להסתיר מהממשק.
  final Set<String> hiddenBuiltInToolIds;

  /// מזהי כלים מובנים שהמשתמש הצמיד לסרגל הניווט הראשי.
  final Set<String> builtInToolsPinnedToNavRail;

  /// סדר הכלים המובנים שהמשתמש קבע (מזהים, לפי הסדר). ריק = סדר הקטלוג.
  final List<String> builtInToolsOrder;

  /// בחירת שפת מסך ההגדרות בלבד: קוד שפה, או `system` להתאמה אוטומטית.
  /// אינה משפיעה על שאר האפליקציה. ראה [resolveSettingsLanguage].
  final String settingsLanguageCode;
  final bool? _softwareAndBookUpdatesEnabled;

  const SettingsState({
    required this.isDarkMode,
    required this.followSystemTheme,
    required this.seedColor,
    required this.darkSeedColor,
    required this.textMaxWidth,
    required this.fontSize,
    required this.fontFamily,
    required this.commentatorsFontFamily,
    this.fontBold = false,
    this.commentatorsFontBold = false,
    required this.commentatorsFontSize,
    required this.lineHeight,
    required this.showOtzarHachochma,
    required this.showHebrewBooks,
    required this.showExternalBooks,
    required this.showTeamim,
    required this.replaceHolyNames,
    required this.autoUpdateIndex,
    required this.defaultRemoveNikud,
    required this.removeNikudFromTanach,
    required this.defaultRemovePunctuation,
    this.defaultContinuousReadingMode = false,
    required this.defaultSidebarOpen,
    required this.defaultCommentaryOpen,
    required this.pinSidebar,
    required this.sidebarWidth,
    required this.facetFilteringWidth,
    required this.externalResultsFirst,
    required this.commentaryPaneWidth,
    required this.copyWithHeaders,
    required this.copyHeaderFormat,
    required this.isFullscreen,
    required this.libraryViewMode,
    required this.libraryShowPreview,
    required this.searchShowPreview,
    required this.shortcuts,
    required this.enablePerBookSettings,
    required this.pdfBookViewByDefault,
    required this.talmudBavliOpenFormat,
    required this.isOfflineMode,
    required this.enableHtmlLinks,
    required this.personalNotesCollapsedByDefault,
    required this.protectedModeEnabled,
    this.protectedModePasswordSet = false,
    this.compactMenuMode = false,
    this.readingTabsPlacement = SettingsRepository.readingTabsPlacementTop,
    this.readingTabsColumnWidth =
        SettingsRepository.defaultReadingTabsColumnWidth,
    this.readingTabsColumnCollapsed = false,
    this.mergeUserBooksIntoLibrary = false,
    this.hiddenBuiltInToolIds = const <String>{},
    this.builtInToolsPinnedToNavRail = const <String>{},
    this.builtInToolsOrder = const <String>[],
    this.settingsLanguageCode = kDefaultSettingsLanguageCode,
    this._softwareAndBookUpdatesEnabled,
  });

  factory SettingsState.initial() {
    return const SettingsState(
      isDarkMode: false,
      followSystemTheme: false,
      seedColor: AppSeedColors.defaultLight,
      darkSeedColor: AppSeedColors.defaultDark,
      textMaxWidth:
          -1, // רוחב מקסימלי לטקסט (-1 = רמה 1 = 95% כברירת מחדל, 0 = ללא הגבלה)
      fontSize: 16,
      fontFamily: 'FrankRuhlCLM',
      commentatorsFontFamily: 'NotoRashiHebrew',
      commentatorsFontSize: 22,
      lineHeight: 1.5,
      showOtzarHachochma: false,
      showHebrewBooks: false,
      showExternalBooks: false,
      showTeamim: true,
      replaceHolyNames: true,
      autoUpdateIndex: true,
      defaultRemoveNikud: false,
      removeNikudFromTanach: false,
      defaultRemovePunctuation: false,
      defaultContinuousReadingMode: false,
      defaultSidebarOpen: false,
      defaultCommentaryOpen: false,
      pinSidebar: false,
      sidebarWidth: 300,
      facetFilteringWidth: 235,
      externalResultsFirst: false,
      commentaryPaneWidth: 400,
      copyWithHeaders: 'none',
      copyHeaderFormat: 'same_line_after_brackets',
      isFullscreen: false,
      libraryViewMode: 'grid',
      libraryShowPreview: true,
      searchShowPreview: true,
      shortcuts: {},
      enablePerBookSettings: false,
      pdfBookViewByDefault: false,
      talmudBavliOpenFormat: 'text',
      isOfflineMode: false,
      enableHtmlLinks: true,
      personalNotesCollapsedByDefault: true,
      protectedModeEnabled: false,
      softwareAndBookUpdatesEnabled: true,
      mergeUserBooksIntoLibrary: false,
    );
  }

  SettingsState copyWith({
    bool? isDarkMode,
    bool? followSystemTheme,
    Color? seedColor,
    Color? darkSeedColor,
    double? textMaxWidth,
    double? fontSize,
    String? fontFamily,
    String? commentatorsFontFamily,
    bool? fontBold,
    bool? commentatorsFontBold,
    double? commentatorsFontSize,
    double? lineHeight,
    bool? showOtzarHachochma,
    bool? showHebrewBooks,
    bool? showExternalBooks,
    bool? showTeamim,
    bool? replaceHolyNames,
    bool? autoUpdateIndex,
    bool? defaultRemoveNikud,
    bool? removeNikudFromTanach,
    bool? defaultRemovePunctuation,
    bool? defaultContinuousReadingMode,
    bool? defaultSidebarOpen,
    bool? defaultCommentaryOpen,
    bool? pinSidebar,
    double? sidebarWidth,
    double? facetFilteringWidth,
    bool? externalResultsFirst,
    double? commentaryPaneWidth,
    String? copyWithHeaders,
    String? copyHeaderFormat,
    bool? isFullscreen,
    String? libraryViewMode,
    bool? libraryShowPreview,
    bool? searchShowPreview,
    Map<String, String>? shortcuts,
    bool? enablePerBookSettings,
    bool? pdfBookViewByDefault,
    String? talmudBavliOpenFormat,
    bool? isOfflineMode,
    bool? enableHtmlLinks,
    bool? personalNotesCollapsedByDefault,
    bool? protectedModeEnabled,
    bool? protectedModePasswordSet,
    bool? compactMenuMode,
    String? readingTabsPlacement,
    double? readingTabsColumnWidth,
    bool? readingTabsColumnCollapsed,
    bool? mergeUserBooksIntoLibrary,
    Set<String>? hiddenBuiltInToolIds,
    Set<String>? builtInToolsPinnedToNavRail,
    List<String>? builtInToolsOrder,
    String? settingsLanguageCode,
    bool? softwareAndBookUpdatesEnabled,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      followSystemTheme: followSystemTheme ?? this.followSystemTheme,
      seedColor: seedColor ?? this.seedColor,
      darkSeedColor: darkSeedColor ?? this.darkSeedColor,
      textMaxWidth: textMaxWidth ?? this.textMaxWidth,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      commentatorsFontFamily:
          commentatorsFontFamily ?? this.commentatorsFontFamily,
      fontBold: fontBold ?? this.fontBold,
      commentatorsFontBold: commentatorsFontBold ?? this.commentatorsFontBold,
      commentatorsFontSize: commentatorsFontSize ?? this.commentatorsFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      showOtzarHachochma: showOtzarHachochma ?? this.showOtzarHachochma,
      showHebrewBooks: showHebrewBooks ?? this.showHebrewBooks,
      showExternalBooks: showExternalBooks ?? this.showExternalBooks,
      showTeamim: showTeamim ?? this.showTeamim,
      replaceHolyNames: replaceHolyNames ?? this.replaceHolyNames,
      autoUpdateIndex: autoUpdateIndex ?? this.autoUpdateIndex,
      defaultRemoveNikud: defaultRemoveNikud ?? this.defaultRemoveNikud,
      removeNikudFromTanach:
          removeNikudFromTanach ?? this.removeNikudFromTanach,
      defaultRemovePunctuation:
          defaultRemovePunctuation ?? this.defaultRemovePunctuation,
      defaultContinuousReadingMode:
          defaultContinuousReadingMode ?? this.defaultContinuousReadingMode,
      defaultSidebarOpen: defaultSidebarOpen ?? this.defaultSidebarOpen,
      defaultCommentaryOpen:
          defaultCommentaryOpen ?? this.defaultCommentaryOpen,
      pinSidebar: pinSidebar ?? this.pinSidebar,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      facetFilteringWidth: facetFilteringWidth ?? this.facetFilteringWidth,
      externalResultsFirst: externalResultsFirst ?? this.externalResultsFirst,
      commentaryPaneWidth: commentaryPaneWidth ?? this.commentaryPaneWidth,
      copyWithHeaders: copyWithHeaders ?? this.copyWithHeaders,
      copyHeaderFormat: copyHeaderFormat ?? this.copyHeaderFormat,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      libraryViewMode: libraryViewMode ?? this.libraryViewMode,
      libraryShowPreview: libraryShowPreview ?? this.libraryShowPreview,
      searchShowPreview: searchShowPreview ?? this.searchShowPreview,
      shortcuts: shortcuts ?? this.shortcuts,
      enablePerBookSettings:
          enablePerBookSettings ?? this.enablePerBookSettings,
      pdfBookViewByDefault: pdfBookViewByDefault ?? this.pdfBookViewByDefault,
      talmudBavliOpenFormat:
          talmudBavliOpenFormat ?? this.talmudBavliOpenFormat,
      isOfflineMode: isOfflineMode ?? this.isOfflineMode,
      enableHtmlLinks: enableHtmlLinks ?? this.enableHtmlLinks,
      personalNotesCollapsedByDefault:
          personalNotesCollapsedByDefault ??
          this.personalNotesCollapsedByDefault,
      protectedModeEnabled: protectedModeEnabled ?? this.protectedModeEnabled,
      protectedModePasswordSet:
          protectedModePasswordSet ?? this.protectedModePasswordSet,
      compactMenuMode: compactMenuMode ?? this.compactMenuMode,
      readingTabsPlacement: readingTabsPlacement ?? this.readingTabsPlacement,
      readingTabsColumnWidth:
          readingTabsColumnWidth ?? this.readingTabsColumnWidth,
      readingTabsColumnCollapsed:
          readingTabsColumnCollapsed ?? this.readingTabsColumnCollapsed,
      mergeUserBooksIntoLibrary:
          mergeUserBooksIntoLibrary ?? this.mergeUserBooksIntoLibrary,
      hiddenBuiltInToolIds: hiddenBuiltInToolIds ?? this.hiddenBuiltInToolIds,
      builtInToolsPinnedToNavRail:
          builtInToolsPinnedToNavRail ?? this.builtInToolsPinnedToNavRail,
      builtInToolsOrder: builtInToolsOrder ?? this.builtInToolsOrder,
      settingsLanguageCode: settingsLanguageCode ?? this.settingsLanguageCode,
      softwareAndBookUpdatesEnabled:
          softwareAndBookUpdatesEnabled ?? this.softwareAndBookUpdatesEnabled,
    );
  }

  /// האם כרטיסיות העיון מוצגות כעמודה אנכית בצד ולא ברצועת הכותרת.
  bool get readingTabsOnSide =>
      readingTabsPlacement == SettingsRepository.readingTabsPlacementSide;

  bool get softwareAndBookUpdatesEnabled =>
      _softwareAndBookUpdatesEnabled ?? true;

  bool get canUseSoftwareAndBookUpdates =>
      !isOfflineMode && softwareAndBookUpdatesEnabled;

  @override
  List<Object?> get props => [
    isDarkMode,
    followSystemTheme,
    seedColor,
    darkSeedColor,
    textMaxWidth,
    fontSize,
    fontFamily,
    commentatorsFontFamily,
    fontBold,
    commentatorsFontBold,
    commentatorsFontSize,
    lineHeight,
    showOtzarHachochma,
    showHebrewBooks,
    showExternalBooks,
    showTeamim,
    replaceHolyNames,
    autoUpdateIndex,
    defaultRemoveNikud,
    removeNikudFromTanach,
    defaultRemovePunctuation,
    defaultContinuousReadingMode,
    defaultSidebarOpen,
    defaultCommentaryOpen,
    pinSidebar,
    sidebarWidth,
    facetFilteringWidth,
    externalResultsFirst,
    commentaryPaneWidth,
    copyWithHeaders,
    copyHeaderFormat,
    isFullscreen,
    libraryViewMode,
    libraryShowPreview,
    searchShowPreview,
    shortcuts,
    enablePerBookSettings,
    pdfBookViewByDefault,
    talmudBavliOpenFormat,
    isOfflineMode,
    enableHtmlLinks,
    personalNotesCollapsedByDefault,
    protectedModeEnabled,
    protectedModePasswordSet,
    compactMenuMode,
    readingTabsPlacement,
    readingTabsColumnWidth,
    readingTabsColumnCollapsed,
    mergeUserBooksIntoLibrary,
    hiddenBuiltInToolIds,
    builtInToolsPinnedToNavRail,
    builtInToolsOrder,
    settingsLanguageCode,
    softwareAndBookUpdatesEnabled,
  ];
}
