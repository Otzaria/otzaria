import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

class SettingsState extends Equatable {
  final bool isDarkMode;
  final bool followSystemTheme;
  final Color seedColor;
  final Color darkSeedColor;
  final double textMaxWidth; // רוחב מקסימלי לטקסט בפיקסלים (0 = ללא הגבלה)
  final double fontSize;
  final String fontFamily;
  final String commentatorsFontFamily;
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
  final bool defaultSidebarOpen;
  final bool defaultCommentaryOpen;
  final bool pinSidebar;
  final double sidebarWidth;
  final double facetFilteringWidth;
  final double commentaryPaneWidth;
  final String copyWithHeaders;
  final String copyHeaderFormat;
  final bool isFullscreen;
  final String libraryViewMode;
  final bool libraryShowPreview;
  final Map<String, String> shortcuts;
  final bool enablePerBookSettings;
  final bool pdfBookViewByDefault;
  final bool isOfflineMode;
  final bool enableHtmlLinks;
  final bool personalNotesCollapsedByDefault;
  final bool protectedModeEnabled;
  final bool autoSyncCatalogs;
  final bool compactMenuMode;

  /// מיזוג תיקיות מותאמות אישית לתוך עץ הספרייה הראשי לפי שם.
  final bool mergeUserBooksIntoLibrary;

  /// מזהי כלים מובנים שהמשתמש בחר להסתיר מהממשק.
  final Set<String> hiddenBuiltInToolIds;

  /// מזהי כלים מובנים שהמשתמש הצמיד לסרגל הניווט הראשי.
  final Set<String> builtInToolsPinnedToNavRail;
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
    required this.defaultSidebarOpen,
    required this.defaultCommentaryOpen,
    required this.pinSidebar,
    required this.sidebarWidth,
    required this.facetFilteringWidth,
    required this.commentaryPaneWidth,
    required this.copyWithHeaders,
    required this.copyHeaderFormat,
    required this.isFullscreen,
    required this.libraryViewMode,
    required this.libraryShowPreview,
    required this.shortcuts,
    required this.enablePerBookSettings,
    required this.pdfBookViewByDefault,
    required this.isOfflineMode,
    required this.enableHtmlLinks,
    required this.personalNotesCollapsedByDefault,
    required this.protectedModeEnabled,
    required this.autoSyncCatalogs,
    this.compactMenuMode = false,
    this.mergeUserBooksIntoLibrary = false,
    this.hiddenBuiltInToolIds = const <String>{},
    this.builtInToolsPinnedToNavRail = const <String>{},
    bool? softwareAndBookUpdatesEnabled,
  }) : _softwareAndBookUpdatesEnabled = softwareAndBookUpdatesEnabled;

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
      defaultSidebarOpen: false,
      defaultCommentaryOpen: false,
      pinSidebar: false,
      sidebarWidth: 300,
      facetFilteringWidth: 235,
      commentaryPaneWidth: 400,
      copyWithHeaders: 'none',
      copyHeaderFormat: 'same_line_after_brackets',
      isFullscreen: false,
      libraryViewMode: 'grid',
      libraryShowPreview: true,
      shortcuts: {},
      enablePerBookSettings: false,
      pdfBookViewByDefault: false,
      isOfflineMode: false,
      enableHtmlLinks: true,
      personalNotesCollapsedByDefault: true,
      protectedModeEnabled: false,
      autoSyncCatalogs: false,
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
    bool? defaultSidebarOpen,
    bool? defaultCommentaryOpen,
    bool? pinSidebar,
    double? sidebarWidth,
    double? facetFilteringWidth,
    double? commentaryPaneWidth,
    String? copyWithHeaders,
    String? copyHeaderFormat,
    bool? isFullscreen,
    String? libraryViewMode,
    bool? libraryShowPreview,
    Map<String, String>? shortcuts,
    bool? enablePerBookSettings,
    bool? pdfBookViewByDefault,
    bool? isOfflineMode,
    bool? enableHtmlLinks,
    bool? personalNotesCollapsedByDefault,
    bool? protectedModeEnabled,
    bool? autoSyncCatalogs,
    bool? compactMenuMode,
    bool? mergeUserBooksIntoLibrary,
    Set<String>? hiddenBuiltInToolIds,
    Set<String>? builtInToolsPinnedToNavRail,
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
      defaultSidebarOpen: defaultSidebarOpen ?? this.defaultSidebarOpen,
      defaultCommentaryOpen:
          defaultCommentaryOpen ?? this.defaultCommentaryOpen,
      pinSidebar: pinSidebar ?? this.pinSidebar,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      facetFilteringWidth: facetFilteringWidth ?? this.facetFilteringWidth,
      commentaryPaneWidth: commentaryPaneWidth ?? this.commentaryPaneWidth,
      copyWithHeaders: copyWithHeaders ?? this.copyWithHeaders,
      copyHeaderFormat: copyHeaderFormat ?? this.copyHeaderFormat,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      libraryViewMode: libraryViewMode ?? this.libraryViewMode,
      libraryShowPreview: libraryShowPreview ?? this.libraryShowPreview,
      shortcuts: shortcuts ?? this.shortcuts,
      enablePerBookSettings:
          enablePerBookSettings ?? this.enablePerBookSettings,
      pdfBookViewByDefault: pdfBookViewByDefault ?? this.pdfBookViewByDefault,
      isOfflineMode: isOfflineMode ?? this.isOfflineMode,
      enableHtmlLinks: enableHtmlLinks ?? this.enableHtmlLinks,
      personalNotesCollapsedByDefault: personalNotesCollapsedByDefault ??
          this.personalNotesCollapsedByDefault,
      protectedModeEnabled: protectedModeEnabled ?? this.protectedModeEnabled,
      autoSyncCatalogs: autoSyncCatalogs ?? this.autoSyncCatalogs,
      compactMenuMode: compactMenuMode ?? this.compactMenuMode,
      mergeUserBooksIntoLibrary:
          mergeUserBooksIntoLibrary ?? this.mergeUserBooksIntoLibrary,
      hiddenBuiltInToolIds: hiddenBuiltInToolIds ?? this.hiddenBuiltInToolIds,
      builtInToolsPinnedToNavRail:
          builtInToolsPinnedToNavRail ?? this.builtInToolsPinnedToNavRail,
      softwareAndBookUpdatesEnabled:
          softwareAndBookUpdatesEnabled ?? this.softwareAndBookUpdatesEnabled,
    );
  }

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
        defaultSidebarOpen,
        defaultCommentaryOpen,
        pinSidebar,
        sidebarWidth,
        facetFilteringWidth,
        commentaryPaneWidth,
        copyWithHeaders,
        copyHeaderFormat,
        isFullscreen,
        libraryViewMode,
        libraryShowPreview,
        shortcuts,
        enablePerBookSettings,
        pdfBookViewByDefault,
        isOfflineMode,
        enableHtmlLinks,
        personalNotesCollapsedByDefault,
        protectedModeEnabled,
        autoSyncCatalogs,
        compactMenuMode,
        mergeUserBooksIntoLibrary,
        hiddenBuiltInToolIds,
        builtInToolsPinnedToNavRail,
        softwareAndBookUpdatesEnabled,
      ];
}
