import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

class SettingsState extends Equatable {
  final bool isDarkMode;
  final Color seedColor;
  final double paddingSize;
  final double fontSize;
  final String fontFamily;
  final String commentatorsFontFamily;
  final bool showOtzarHachochma;
  final bool showHebrewBooks;
  final bool showExternalBooks;
  final bool showTeamim;
  final bool useFastSearch;
  final bool replaceHolyNames;
  final bool autoUpdateIndex;
  final bool defaultRemoveNikud;
  final bool removeNikudFromTanach;
  final bool defaultSidebarOpen;
  final bool pinSidebar;
  final double sidebarWidth;
  final double facetFilteringWidth;
  final String copyWithHeaders;
  final String copyHeaderFormat;
  final bool isFullscreen;
  final String libraryViewMode;
  final bool libraryShowPreview;
  final bool defaultSplitView;
  final Map<String, String> shortcuts;

  const SettingsState({
    required this.isDarkMode,
    required this.seedColor,
    required this.paddingSize,
    required this.fontSize,
    required this.fontFamily,
    required this.commentatorsFontFamily,
    required this.showOtzarHachochma,
    required this.showHebrewBooks,
    required this.showExternalBooks,
    required this.showTeamim,
    required this.useFastSearch,
    required this.replaceHolyNames,
    required this.autoUpdateIndex,
    required this.defaultRemoveNikud,
    required this.removeNikudFromTanach,
    required this.defaultSidebarOpen,
    required this.pinSidebar,
    required this.sidebarWidth,
    required this.facetFilteringWidth,
    required this.copyWithHeaders,
    required this.copyHeaderFormat,
    required this.isFullscreen,
    required this.libraryViewMode,
    required this.libraryShowPreview,
    required this.defaultSplitView,
    required this.shortcuts,
  });

  factory SettingsState.initial() {
    return const SettingsState(
      isDarkMode: false,
      seedColor: Colors.brown,
      paddingSize: 10,
      fontSize: 16,
      fontFamily: 'FrankRuhlCLM',
      commentatorsFontFamily: 'NotoRashiHebrew',
      showOtzarHachochma: false,
      showHebrewBooks: false,
      showExternalBooks: false,
      showTeamim: true,
      useFastSearch: true,
      replaceHolyNames: true,
      autoUpdateIndex: true,
      defaultRemoveNikud: false,
      removeNikudFromTanach: false,
      defaultSidebarOpen: false,
      pinSidebar: false,
      sidebarWidth: 300,
      facetFilteringWidth: 235,
      copyWithHeaders: 'none',
      copyHeaderFormat: 'same_line_after_brackets',
      isFullscreen: false,
      libraryViewMode: 'grid',
      libraryShowPreview: true,
      defaultSplitView: false,
      shortcuts: {},
    );
  }

  SettingsState copyWith({
    bool? isDarkMode,
    Color? seedColor,
    double? paddingSize,
    double? fontSize,
    String? fontFamily,
    String? commentatorsFontFamily,
    bool? showOtzarHachochma,
    bool? showHebrewBooks,
    bool? showExternalBooks,
    bool? showTeamim,
    bool? useFastSearch,
    bool? replaceHolyNames,
    bool? autoUpdateIndex,
    bool? defaultRemoveNikud,
    bool? removeNikudFromTanach,
    bool? defaultSidebarOpen,
    bool? pinSidebar,
    double? sidebarWidth,
    double? facetFilteringWidth,
    String? copyWithHeaders,
    String? copyHeaderFormat,
    bool? isFullscreen,
    String? libraryViewMode,
    bool? libraryShowPreview,
    bool? defaultSplitView,
    Map<String, String>? shortcuts,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      seedColor: seedColor ?? this.seedColor,
      paddingSize: paddingSize ?? this.paddingSize,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      commentatorsFontFamily:
          commentatorsFontFamily ?? this.commentatorsFontFamily,
      showOtzarHachochma: showOtzarHachochma ?? this.showOtzarHachochma,
      showHebrewBooks: showHebrewBooks ?? this.showHebrewBooks,
      showExternalBooks: showExternalBooks ?? this.showExternalBooks,
      showTeamim: showTeamim ?? this.showTeamim,
      useFastSearch: useFastSearch ?? this.useFastSearch,
      replaceHolyNames: replaceHolyNames ?? this.replaceHolyNames,
      autoUpdateIndex: autoUpdateIndex ?? this.autoUpdateIndex,
      defaultRemoveNikud: defaultRemoveNikud ?? this.defaultRemoveNikud,
      removeNikudFromTanach:
          removeNikudFromTanach ?? this.removeNikudFromTanach,
      defaultSidebarOpen: defaultSidebarOpen ?? this.defaultSidebarOpen,
      pinSidebar: pinSidebar ?? this.pinSidebar,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      facetFilteringWidth: facetFilteringWidth ?? this.facetFilteringWidth,
      copyWithHeaders: copyWithHeaders ?? this.copyWithHeaders,
      copyHeaderFormat: copyHeaderFormat ?? this.copyHeaderFormat,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      libraryViewMode: libraryViewMode ?? this.libraryViewMode,
      libraryShowPreview: libraryShowPreview ?? this.libraryShowPreview,
      defaultSplitView: defaultSplitView ?? this.defaultSplitView,
      shortcuts: shortcuts ?? this.shortcuts,
    );
  }

  @override
  List<Object?> get props => [
        isDarkMode,
        seedColor,
        paddingSize,
        fontSize,
        fontFamily,
        commentatorsFontFamily,
        showOtzarHachochma,
        showHebrewBooks,
        showExternalBooks,
        showTeamim,
        useFastSearch,
        replaceHolyNames,
        autoUpdateIndex,
        defaultRemoveNikud,
        removeNikudFromTanach,
        defaultSidebarOpen,
        pinSidebar,
        sidebarWidth,
        facetFilteringWidth,
        copyWithHeaders,
        copyHeaderFormat,
        isFullscreen,
        libraryViewMode,
        libraryShowPreview,
        defaultSplitView,
        shortcuts,
      ];
}
