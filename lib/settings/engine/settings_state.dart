import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

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
  final bool continuousReadingMode;
  final bool showOtzarHachochma;
  final bool showHebrewBooks;
  final bool showExternalBooks;
  final bool showTeamim;
  final bool replaceHolyNames;
  final bool autoUpdateIndex;
  final bool defaultRemoveNikud;
  final bool removeNikudFromTanach;
  final bool defaultSidebarOpen;
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
  final bool alignTabsToRight;
  final bool enableHtmlLinks;
  final bool personalNotesCollapsedByDefault;
  final bool protectedModeEnabled;
  final bool autoSyncCatalogs;
  final bool compactMenuMode;
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
    required this.continuousReadingMode,
    required this.showOtzarHachochma,
    required this.showHebrewBooks,
    required this.showExternalBooks,
    required this.showTeamim,
    required this.replaceHolyNames,
    required this.autoUpdateIndex,
    required this.defaultRemoveNikud,
    required this.removeNikudFromTanach,
    required this.defaultSidebarOpen,
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
    required this.alignTabsToRight,
    required this.enableHtmlLinks,
    required this.personalNotesCollapsedByDefault,
    required this.protectedModeEnabled,
    required this.autoSyncCatalogs,
    this.compactMenuMode = false,
    bool? softwareAndBookUpdatesEnabled,
  }) : _softwareAndBookUpdatesEnabled = softwareAndBookUpdatesEnabled;

  factory SettingsState.initial() {
    return const SettingsState(
      isDarkMode: false,
      followSystemTheme: false,
      seedColor: Color(0xFF2C1B02),
      darkSeedColor: Color(0xFFCE93D8), // סגול בהיר למצב כהה
      textMaxWidth:
          -1, // רוחב מקסימלי לטקסט (-1 = רמה 1 = 95% כברירת מחדל, 0 = ללא הגבלה)
      fontSize: 16,
      fontFamily: 'FrankRuhlCLM',
      commentatorsFontFamily: 'NotoRashiHebrew',
      commentatorsFontSize: 22,
      lineHeight: 1.5,
      continuousReadingMode: false,
      showOtzarHachochma: false,
      showHebrewBooks: false,
      showExternalBooks: false,
      showTeamim: true,
      replaceHolyNames: true,
      autoUpdateIndex: true,
      defaultRemoveNikud: false,
      removeNikudFromTanach: false,
      defaultSidebarOpen: false,
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
      alignTabsToRight: false,
      enableHtmlLinks: true,
      personalNotesCollapsedByDefault: true,
      protectedModeEnabled: false,
      autoSyncCatalogs: false,
      softwareAndBookUpdatesEnabled: true,
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
    bool? continuousReadingMode,
    bool? showOtzarHachochma,
    bool? showHebrewBooks,
    bool? showExternalBooks,
    bool? showTeamim,
    bool? replaceHolyNames,
    bool? autoUpdateIndex,
    bool? defaultRemoveNikud,
    bool? removeNikudFromTanach,
    bool? defaultSidebarOpen,
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
    bool? alignTabsToRight,
    bool? enableHtmlLinks,
    bool? personalNotesCollapsedByDefault,
    bool? protectedModeEnabled,
    bool? autoSyncCatalogs,
    bool? compactMenuMode,
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
      continuousReadingMode:
          continuousReadingMode ?? this.continuousReadingMode,
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
      alignTabsToRight: alignTabsToRight ?? this.alignTabsToRight,
      enableHtmlLinks: enableHtmlLinks ?? this.enableHtmlLinks,
      personalNotesCollapsedByDefault: personalNotesCollapsedByDefault ??
          this.personalNotesCollapsedByDefault,
      protectedModeEnabled: protectedModeEnabled ?? this.protectedModeEnabled,
      autoSyncCatalogs: autoSyncCatalogs ?? this.autoSyncCatalogs,
      compactMenuMode: compactMenuMode ?? this.compactMenuMode,
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
        continuousReadingMode,
        showOtzarHachochma,
        showHebrewBooks,
        showExternalBooks,
        showTeamim,
        replaceHolyNames,
        autoUpdateIndex,
        defaultRemoveNikud,
        removeNikudFromTanach,
        defaultSidebarOpen,
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
        alignTabsToRight,
        enableHtmlLinks,
        personalNotesCollapsedByDefault,
        protectedModeEnabled,
        autoSyncCatalogs,
        compactMenuMode,
        softwareAndBookUpdatesEnabled,
      ];
}
