import 'package:otzaria/indexing/models/indexing_resource_policy.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class LoadSettings extends SettingsEvent {}

class UpdateDarkMode extends SettingsEvent {
  final bool isDarkMode;

  const UpdateDarkMode(this.isDarkMode);

  @override
  List<Object?> get props => [isDarkMode];
}

class UpdateFollowSystemTheme extends SettingsEvent {
  final bool followSystemTheme;

  const UpdateFollowSystemTheme(this.followSystemTheme);

  @override
  List<Object?> get props => [followSystemTheme];
}

/// מצב התצוגה מהבורר "בהיר / לפי המערכת / כהה" באירוע אחד, כדי ש־MaterialApp
/// ייבנה מחדש פעם אחת ולא פעמיים. ‏[ThemeMode.system] משאיר את [isDarkMode]
/// כמו שהוא.
class UpdateThemeMode extends SettingsEvent {
  final ThemeMode mode;

  const UpdateThemeMode(this.mode);

  @override
  List<Object?> get props => [mode];
}

class UpdateSeedColor extends SettingsEvent {
  final Color seedColor;

  const UpdateSeedColor(this.seedColor);

  @override
  List<Object?> get props => [seedColor];
}

class UpdateDarkSeedColor extends SettingsEvent {
  final Color darkSeedColor;

  const UpdateDarkSeedColor(this.darkSeedColor);

  @override
  List<Object?> get props => [darkSeedColor];
}

class UpdateTextMaxWidth extends SettingsEvent {
  final double textMaxWidth;

  const UpdateTextMaxWidth(this.textMaxWidth);

  @override
  List<Object?> get props => [textMaxWidth];
}

class UpdateFontSize extends SettingsEvent {
  final double fontSize;

  const UpdateFontSize(this.fontSize);

  @override
  List<Object?> get props => [fontSize];
}

class UpdateFontFamily extends SettingsEvent {
  final String fontFamily;

  const UpdateFontFamily(this.fontFamily);

  @override
  List<Object?> get props => [fontFamily];
}

class UpdateCommentatorsFontFamily extends SettingsEvent {
  final String commentatorsFontFamily;

  const UpdateCommentatorsFontFamily(this.commentatorsFontFamily);

  @override
  List<Object?> get props => [commentatorsFontFamily];
}

class UpdateFontBold extends SettingsEvent {
  final bool fontBold;

  const UpdateFontBold(this.fontBold);

  @override
  List<Object?> get props => [fontBold];
}

class UpdateCommentatorsFontBold extends SettingsEvent {
  final bool commentatorsFontBold;

  const UpdateCommentatorsFontBold(this.commentatorsFontBold);

  @override
  List<Object?> get props => [commentatorsFontBold];
}

/// גודל הטקסט בקטעי תוצאות החיפוש (#2826).
class UpdateSearchResultsFontSize extends SettingsEvent {
  final double searchResultsFontSize;

  const UpdateSearchResultsFontSize(this.searchResultsFontSize);

  @override
  List<Object?> get props => [searchResultsFontSize];
}

sealed class CommentatorsFontSizeEvent extends SettingsEvent {
  const CommentatorsFontSizeEvent();
}

class UpdateCommentatorsFontSize extends CommentatorsFontSizeEvent {
  final double commentatorsFontSize;

  const UpdateCommentatorsFontSize(this.commentatorsFontSize);

  @override
  List<Object?> get props => [commentatorsFontSize];
}

class AdjustCommentatorsFontSize extends CommentatorsFontSizeEvent {
  final double delta;

  const AdjustCommentatorsFontSize(this.delta);

  @override
  List<Object?> get props => [delta];
}

class UpdateLineHeight extends SettingsEvent {
  final double lineHeight;

  const UpdateLineHeight(this.lineHeight);

  @override
  List<Object?> get props => [lineHeight];
}

class UpdateShowOtzarHachochma extends SettingsEvent {
  final bool showOtzarHachochma;

  const UpdateShowOtzarHachochma(this.showOtzarHachochma);

  @override
  List<Object?> get props => [showOtzarHachochma];
}

class UpdateShowHebrewBooks extends SettingsEvent {
  final bool showHebrewBooks;

  const UpdateShowHebrewBooks(this.showHebrewBooks);

  @override
  List<Object?> get props => [showHebrewBooks];
}

class UpdateShowLocalHebrewBooks extends SettingsEvent {
  final bool showLocalHebrewBooks;

  const UpdateShowLocalHebrewBooks(this.showLocalHebrewBooks);

  @override
  List<Object?> get props => [showLocalHebrewBooks];
}

class UpdateShowExternalBooks extends SettingsEvent {
  final bool showExternalBooks;

  const UpdateShowExternalBooks(this.showExternalBooks);

  @override
  List<Object?> get props => [showExternalBooks];
}

class UpdateIndexingResourceMode extends SettingsEvent {
  final IndexingResourceMode mode;

  const UpdateIndexingResourceMode(this.mode);

  @override
  List<Object?> get props => [mode];
}

class UpdateIndexUpdateMode extends SettingsEvent {
  final IndexUpdateMode indexUpdateMode;

  const UpdateIndexUpdateMode(this.indexUpdateMode);

  @override
  List<Object?> get props => [indexUpdateMode];
}

/// עדכון מלא של מדיניות תצוגת הטקסט (עורך ההגדרות החדש).
class UpdateTextDisplayPolicy extends SettingsEvent {
  final TextDisplayPolicy textDisplayPolicy;

  const UpdateTextDisplayPolicy(this.textDisplayPolicy);

  @override
  List<Object?> get props => [textDisplayPolicy];
}

class UpdateDefaultContinuousReadingMode extends SettingsEvent {
  final bool defaultContinuousReadingMode;

  const UpdateDefaultContinuousReadingMode(this.defaultContinuousReadingMode);

  @override
  List<Object?> get props => [defaultContinuousReadingMode];
}

class UpdateDefaultSidebarOpen extends SettingsEvent {
  final bool defaultSidebarOpen;

  const UpdateDefaultSidebarOpen(this.defaultSidebarOpen);

  @override
  List<Object?> get props => [defaultSidebarOpen];
}

class UpdateDefaultCommentaryOpen extends SettingsEvent {
  final bool defaultCommentaryOpen;

  const UpdateDefaultCommentaryOpen(this.defaultCommentaryOpen);

  @override
  List<Object?> get props => [defaultCommentaryOpen];
}

class UpdatePinSidebar extends SettingsEvent {
  final bool pinSidebar;

  const UpdatePinSidebar(this.pinSidebar);

  @override
  List<Object?> get props => [pinSidebar];
}

class UpdateSidebarWidth extends SettingsEvent {
  final double sidebarWidth;

  const UpdateSidebarWidth(this.sidebarWidth);

  @override
  List<Object?> get props => [sidebarWidth];
}

class UpdateFacetFilteringWidth extends SettingsEvent {
  final double facetFilteringWidth;

  const UpdateFacetFilteringWidth(this.facetFilteringWidth);

  @override
  List<Object?> get props => [facetFilteringWidth];
}

/// מיקום בלוק התוצאות ממקור חיצוני במסך החיפוש: true — קודמות, false — מאוחרות.
class UpdateExternalResultsFirst extends SettingsEvent {
  final bool externalResultsFirst;

  const UpdateExternalResultsFirst(this.externalResultsFirst);

  @override
  List<Object?> get props => [externalResultsFirst];
}

class UpdateCommentaryPaneWidth extends SettingsEvent {
  final double commentaryPaneWidth;

  const UpdateCommentaryPaneWidth(this.commentaryPaneWidth);

  @override
  List<Object?> get props => [commentaryPaneWidth];
}

class UpdateCopyWithHeaders extends SettingsEvent {
  final String copyWithHeaders;

  const UpdateCopyWithHeaders(this.copyWithHeaders);

  @override
  List<Object?> get props => [copyWithHeaders];
}

class UpdateCopyHeaderFormat extends SettingsEvent {
  final String copyHeaderFormat;

  const UpdateCopyHeaderFormat(this.copyHeaderFormat);

  @override
  List<Object?> get props => [copyHeaderFormat];
}

class UpdateLibraryViewMode extends SettingsEvent {
  final String libraryViewMode;

  const UpdateLibraryViewMode(this.libraryViewMode);

  @override
  List<Object?> get props => [libraryViewMode];
}

class UpdateLibraryShowPreview extends SettingsEvent {
  final bool libraryShowPreview;

  /// הבחירה נעשתה בחלון נמוך: נשמרת בנפרד
  /// (`SettingsState.libraryShowPreviewShortWindow`).
  final bool shortWindow;

  const UpdateLibraryShowPreview(
    this.libraryShowPreview, {
    this.shortWindow = false,
  });

  @override
  List<Object?> get props => [libraryShowPreview, shortWindow];
}

class UpdateSearchShowPreview extends SettingsEvent {
  final bool searchShowPreview;

  const UpdateSearchShowPreview(this.searchShowPreview);

  @override
  List<Object?> get props => [searchShowPreview];
}

class ResetShortcuts extends SettingsEvent {}

class UpdateShortcut extends SettingsEvent {
  final String key;
  final String value;

  const UpdateShortcut(this.key, this.value);

  @override
  List<Object?> get props => [key, value];
}

class UpdateEnablePerBookSettings extends SettingsEvent {
  final bool enablePerBookSettings;

  const UpdateEnablePerBookSettings(this.enablePerBookSettings);

  @override
  List<Object?> get props => [enablePerBookSettings];
}

class UpdatePdfBookViewByDefault extends SettingsEvent {
  final bool pdfBookViewByDefault;

  const UpdatePdfBookViewByDefault(this.pdfBookViewByDefault);

  @override
  List<Object?> get props => [pdfBookViewByDefault];
}

class UpdateTalmudBavliOpenFormat extends SettingsEvent {
  final String talmudBavliOpenFormat;

  const UpdateTalmudBavliOpenFormat(this.talmudBavliOpenFormat);

  @override
  List<Object?> get props => [talmudBavliOpenFormat];
}

class UpdateOfflineMode extends SettingsEvent {
  final bool isOfflineMode;

  const UpdateOfflineMode(this.isOfflineMode);

  @override
  List<Object?> get props => [isOfflineMode];
}

class UpdateSoftwareAndBookUpdatesEnabled extends SettingsEvent {
  final bool enabled;

  const UpdateSoftwareAndBookUpdatesEnabled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class UpdatePersonalNotesCollapsedByDefault extends SettingsEvent {
  final bool collapsedByDefault;

  const UpdatePersonalNotesCollapsedByDefault(this.collapsedByDefault);

  @override
  List<Object?> get props => [collapsedByDefault];
}

class UpdateAutoSync extends SettingsEvent {
  final bool enabled;

  const UpdateAutoSync(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

/// [value] הוא `UpdateCheckFrequency.storageValue`.
class UpdateUpdateCheckFrequency extends SettingsEvent {
  final String value;

  const UpdateUpdateCheckFrequency(this.value);

  @override
  List<Object?> get props => [value];
}

class UpdateRestoreAllWindows extends SettingsEvent {
  final bool enabled;

  const UpdateRestoreAllWindows(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

/// תיקיית הגיבוי שנבחרה; ריק = תיקיית ברירת המחדל.
class UpdateBackupPath extends SettingsEvent {
  final String path;

  const UpdateBackupPath(this.path);

  @override
  List<Object?> get props => [path];
}

/// none / daily / weekly / monthly.
class UpdateAutoBackupFrequency extends SettingsEvent {
  final String frequency;

  const UpdateAutoBackupFrequency(this.frequency);

  @override
  List<Object?> get props => [frequency];
}

/// [profile] הוא `RetentionProfile.name`.
class UpdateBackupRetentionProfile extends SettingsEvent {
  final String profile;

  const UpdateBackupRetentionProfile(this.profile);

  @override
  List<Object?> get props => [profile];
}

/// מתג סעיף גיבוי אחד מתוך `SettingsRepository.backupSectionKeys`.
class UpdateBackupSection extends SettingsEvent {
  final String key;
  final bool include;

  const UpdateBackupSection(this.key, this.include);

  @override
  List<Object?> get props => [key, include];
}

/// "גבה הכל": כל סעיפי הגיבוי דולקים.
class IncludeAllBackupSections extends SettingsEvent {
  const IncludeAllBackupSections();
}

/// הצגת המפרשים בחלונית בצד, כברירת מחדל לספרים שנפתחים.
class UpdateSplitedView extends SettingsEvent {
  final bool splitedView;

  const UpdateSplitedView(this.splitedView);

  @override
  List<Object?> get props => [splitedView];
}

/// מפתח בקובץ ההגדרות השתנה, אולי מחוץ לבלוק: חלון אחר, הקורא (מפצל המפרשים),
/// שחזור גיבוי. הבלוק קורא מחדש את ההגדרות ופולט מצב אם משהו השתנה.
class ExternalSettingChanged extends SettingsEvent {
  final String key;

  const ExternalSettingChanged(this.key);

  @override
  List<Object?> get props => [key];
}

class UpdateCompactMenuMode extends SettingsEvent {
  /// null: "אוטומטי" — מוחק את הבחירה, והצפיפות שוב לפי גודל החלון
  /// (`SettingsState.compactMenuModeFor`).
  final bool? compactMenuMode;

  const UpdateCompactMenuMode(this.compactMenuMode);

  @override
  List<Object?> get props => [compactMenuMode];
}

class UpdateReadingTabsPlacement extends SettingsEvent {
  final String placement;

  const UpdateReadingTabsPlacement(this.placement);

  @override
  List<Object?> get props => [placement];
}

class UpdateReadingTabsColumnWidth extends SettingsEvent {
  final double width;

  const UpdateReadingTabsColumnWidth(this.width);

  @override
  List<Object?> get props => [width];
}

class UpdateReadingTabsColumnCollapsed extends SettingsEvent {
  final bool collapsed;

  const UpdateReadingTabsColumnCollapsed(this.collapsed);

  @override
  List<Object?> get props => [collapsed];
}

class UpdateMergeUserBooksIntoLibrary extends SettingsEvent {
  final bool mergeUserBooksIntoLibrary;

  const UpdateMergeUserBooksIntoLibrary(this.mergeUserBooksIntoLibrary);

  @override
  List<Object?> get props => [mergeUserBooksIntoLibrary];
}

class UpdateProtectedModeEnabled extends SettingsEvent {
  final bool enabled;

  const UpdateProtectedModeEnabled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class UpdateProtectedModePassword extends SettingsEvent {
  final String password;

  const UpdateProtectedModePassword(this.password);

  @override
  List<Object?> get props => [password];
}

class ClearProtectedModePassword extends SettingsEvent {
  const ClearProtectedModePassword();

  @override
  List<Object?> get props => [];
}

class UpdateHiddenBuiltInToolIds extends SettingsEvent {
  final Set<String> hiddenBuiltInToolIds;

  const UpdateHiddenBuiltInToolIds(this.hiddenBuiltInToolIds);

  @override
  List<Object?> get props => [hiddenBuiltInToolIds];
}

class UpdateBuiltInToolsPinnedToNavRail extends SettingsEvent {
  final Set<String> builtInToolsPinnedToNavRail;

  const UpdateBuiltInToolsPinnedToNavRail(this.builtInToolsPinnedToNavRail);

  @override
  List<Object?> get props => [builtInToolsPinnedToNavRail];
}

class UpdateBuiltInToolsOrder extends SettingsEvent {
  final List<String> builtInToolsOrder;

  const UpdateBuiltInToolsOrder(this.builtInToolsOrder);

  @override
  List<Object?> get props => [builtInToolsOrder];
}

class UpdateSettingsLanguageCode extends SettingsEvent {
  final String settingsLanguageCode;

  const UpdateSettingsLanguageCode(this.settingsLanguageCode);

  @override
  List<Object?> get props => [settingsLanguageCode];
}
