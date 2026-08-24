import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository _repository;

  SettingsBloc({required this._repository}) : super(SettingsState.initial()) {
    on<LoadSettings>(_onLoadSettings);
    on<UpdateDarkMode>(_onUpdateDarkMode);
    on<UpdateFollowSystemTheme>(_onUpdateFollowSystemTheme);
    on<UpdateSeedColor>(_onUpdateSeedColor);
    on<UpdateDarkSeedColor>(_onUpdateDarkSeedColor);
    on<UpdateTextMaxWidth>(_onUpdateTextMaxWidth);
    on<UpdateFontSize>(_onUpdateFontSize);
    on<UpdateFontFamily>(_onUpdateFontFamily);
    on<UpdateCommentatorsFontFamily>(_onUpdateCommentatorsFontFamily);
    on<UpdateFontBold>(_onUpdateFontBold);
    on<UpdateCommentatorsFontBold>(_onUpdateCommentatorsFontBold);
    on<UpdateCommentatorsFontSize>(_onUpdateCommentatorsFontSize);
    on<UpdateLineHeight>(_onUpdateLineHeight);
    on<UpdateShowOtzarHachochma>(_onUpdateShowOtzarHachochma);
    on<UpdateShowHebrewBooks>(_onUpdateShowHebrewBooks);
    on<UpdateShowExternalBooks>(_onUpdateShowExternalBooks);
    on<UpdateShowTeamim>(_onUpdateShowTeamim);
    on<UpdateReplaceHolyNames>(_onUpdateReplaceHolyNames);
    on<UpdateAutoUpdateIndex>(_onUpdateAutoUpdateIndex);
    on<UpdateDefaultRemoveNikud>(_onUpdateDefaultRemoveNikud);
    on<UpdateRemoveNikudFromTanach>(_onUpdateRemoveNikudFromTanach);
    on<UpdateDefaultRemovePunctuation>(_onUpdateDefaultRemovePunctuation);
    on<UpdateDefaultContinuousReadingMode>(
      _onUpdateDefaultContinuousReadingMode,
    );
    on<UpdateDefaultSidebarOpen>(_onUpdateDefaultSidebarOpen);
    on<UpdateDefaultCommentaryOpen>(_onUpdateDefaultCommentaryOpen);
    on<UpdatePinSidebar>(_onUpdatePinSidebar);
    on<UpdateSidebarWidth>(_onUpdateSidebarWidth);
    on<UpdateFacetFilteringWidth>(_onUpdateFacetFilteringWidth);
    on<UpdateExternalResultsFirst>(_onUpdateExternalResultsFirst);
    on<UpdateCommentaryPaneWidth>(_onUpdateCommentaryPaneWidth);
    on<UpdateCopyWithHeaders>(_onUpdateCopyWithHeaders);
    on<UpdateCopyHeaderFormat>(_onUpdateCopyHeaderFormat);
    on<UpdateIsFullscreen>(_onUpdateIsFullscreen);
    on<UpdateLibraryViewMode>(_onUpdateLibraryViewMode);
    on<UpdateLibraryShowPreview>(_onUpdateLibraryShowPreview);
    on<UpdateSearchShowPreview>(_onUpdateSearchShowPreview);
    on<RefreshShortcuts>(_onRefreshShortcuts);
    on<ResetShortcuts>(_onResetShortcuts);
    on<UpdateShortcut>(_onUpdateShortcut);
    on<UpdateEnablePerBookSettings>(_onUpdateEnablePerBookSettings);
    on<UpdatePdfBookViewByDefault>(_onUpdatePdfBookViewByDefault);
    on<UpdateTalmudBavliOpenFormat>(_onUpdateTalmudBavliOpenFormat);
    on<UpdateOfflineMode>(_onUpdateOfflineMode);
    on<UpdateSoftwareAndBookUpdatesEnabled>(
      _onUpdateSoftwareAndBookUpdatesEnabled,
    );
    on<UpdateEnableHtmlLinks>(_onUpdateEnableHtmlLinks);
    on<UpdatePersonalNotesCollapsedByDefault>(
      _onUpdatePersonalNotesCollapsedByDefault,
    );
    on<UpdateCompactMenuMode>(_onUpdateCompactMenuMode);
    on<UpdateReadingTabsPlacement>(_onUpdateReadingTabsPlacement);
    on<UpdateReadingTabsColumnWidth>(_onUpdateReadingTabsColumnWidth);
    on<UpdateReadingTabsColumnCollapsed>(_onUpdateReadingTabsColumnCollapsed);
    on<UpdateMergeUserBooksIntoLibrary>(_onUpdateMergeUserBooksIntoLibrary);
    on<UpdateProtectedModeEnabled>(_onUpdateProtectedModeEnabled);
    on<UpdateProtectedModePassword>(_onUpdateProtectedModePassword);
    on<ClearProtectedModePassword>(_onClearProtectedModePassword);
    on<UpdateHiddenBuiltInToolIds>(_onUpdateHiddenBuiltInToolIds);
    on<UpdateBuiltInToolsPinnedToNavRail>(_onUpdateBuiltInToolsPinnedToNavRail);
    on<UpdateBuiltInToolsOrder>(
      _onUpdateBuiltInToolsOrder,
      transformer: sequential(),
    );
    on<UpdateSettingsLanguageCode>(_onUpdateSettingsLanguageCode);
  }

  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SettingsState> emit,
  ) async {
    final settings = await _repository.loadSettings();

    // בדסקטופ: אם המשתמש בחר גופן מערכת בעבר, נטען אותו כדי שיהיה זמין ב-TextStyle.
    await AppFonts.ensureFontLoaded(settings['fontFamily'] as String);
    await AppFonts.ensureFontLoaded(
      settings['commentatorsFontFamily'] as String,
    );
    // גופן "מפרשים תחתונים" בצורת הדף נשמר מחוץ ל-state — בלי טעינה כאן
    // גופן מערכת מתאפס ל-fallback אחרי הפעלה מחדש (issue #849).
    await AppFonts.ensureFontLoaded(
      settings['pageShapeBottomFont'] as String? ?? AppFonts.defaultFont,
    );

    emit(
      SettingsState(
        isDarkMode: settings['isDarkMode'],
        followSystemTheme: settings['followSystemTheme'] ?? false,
        seedColor: settings['seedColor'],
        darkSeedColor: settings['darkSeedColor'],
        textMaxWidth: settings['textMaxWidth'],
        fontSize: settings['fontSize'],
        fontFamily: settings['fontFamily'],
        commentatorsFontFamily: settings['commentatorsFontFamily'],
        fontBold: settings['fontBold'] ?? false,
        commentatorsFontBold: settings['commentatorsFontBold'] ?? false,
        commentatorsFontSize: settings['commentatorsFontSize'],
        lineHeight: settings['lineHeight'],
        showOtzarHachochma: settings['showOtzarHachochma'],
        showHebrewBooks: settings['showHebrewBooks'],
        showExternalBooks: settings['showExternalBooks'],
        showTeamim: settings['showTeamim'],
        replaceHolyNames: settings['replaceHolyNames'],
        autoUpdateIndex: settings['autoUpdateIndex'],
        defaultRemoveNikud: settings['defaultRemoveNikud'],
        removeNikudFromTanach: settings['removeNikudFromTanach'],
        defaultRemovePunctuation: settings['defaultRemovePunctuation'],
        defaultContinuousReadingMode:
            settings['defaultContinuousReadingMode'] ?? false,
        defaultSidebarOpen: settings['defaultSidebarOpen'],
        defaultCommentaryOpen: settings['defaultCommentaryOpen'],
        pinSidebar: settings['pinSidebar'],
        sidebarWidth: settings['sidebarWidth'],
        facetFilteringWidth: settings['facetFilteringWidth'],
        externalResultsFirst: settings['externalResultsFirst'] ?? false,
        commentaryPaneWidth: settings['commentaryPaneWidth'],
        copyWithHeaders: settings['copyWithHeaders'],
        copyHeaderFormat: settings['copyHeaderFormat'],
        isFullscreen: settings['isFullscreen'],
        libraryViewMode: settings['libraryViewMode'],
        libraryShowPreview: settings['libraryShowPreview'],
        searchShowPreview: settings['searchShowPreview'] ?? true,
        shortcuts: Map<String, String>.unmodifiable(
          Map<String, String>.from(settings['shortcuts'] as Map),
        ),
        enablePerBookSettings: settings['enablePerBookSettings'],
        pdfBookViewByDefault: settings['pdfBookViewByDefault'] ?? false,
        talmudBavliOpenFormat: settings['talmudBavliOpenFormat'] ?? 'text',
        isOfflineMode: settings['isOfflineMode'] ?? false,
        softwareAndBookUpdatesEnabled:
            settings['softwareAndBookUpdatesEnabled'] ?? true,
        enableHtmlLinks: settings['enableHtmlLinks'] ?? true,
        personalNotesCollapsedByDefault:
            settings['personalNotesCollapsedByDefault'] ?? true,
        compactMenuMode: settings['compactMenuMode'] ?? false,
        readingTabsPlacement:
            settings['readingTabsPlacement'] ??
            SettingsRepository.readingTabsPlacementTop,
        readingTabsColumnWidth:
            settings['readingTabsColumnWidth'] ??
            SettingsRepository.defaultReadingTabsColumnWidth,
        readingTabsColumnCollapsed:
            settings['readingTabsColumnCollapsed'] ?? false,
        mergeUserBooksIntoLibrary:
            settings['mergeUserBooksIntoLibrary'] ?? false,
        protectedModeEnabled: settings['protectedModeEnabled'] ?? false,
        protectedModePasswordSet: _repository.hasProtectedModePassword(),
        hiddenBuiltInToolIds:
            (settings['hiddenBuiltInToolIds'] as Set<String>?) ?? <String>{},
        builtInToolsPinnedToNavRail:
            (settings['builtInToolsPinnedToNavRail'] as Set<String>?) ??
            <String>{},
        builtInToolsOrder:
            (settings['builtInToolsOrder'] as List<String>?) ?? <String>[],
        settingsLanguageCode:
            (settings['settingsLanguageCode'] as String?) ??
            kDefaultSettingsLanguageCode,
      ),
    );
  }

  Future<void> _onUpdateSettingsLanguageCode(
    UpdateSettingsLanguageCode event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateSettingsLanguageCode(event.settingsLanguageCode);
    emit(state.copyWith(settingsLanguageCode: event.settingsLanguageCode));
  }

  Future<void> _onUpdateEnablePerBookSettings(
    UpdateEnablePerBookSettings event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateEnablePerBookSettings(event.enablePerBookSettings);
    emit(state.copyWith(enablePerBookSettings: event.enablePerBookSettings));
  }

  Future<void> _onUpdatePdfBookViewByDefault(
    UpdatePdfBookViewByDefault event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updatePdfBookViewByDefault(event.pdfBookViewByDefault);
    emit(state.copyWith(pdfBookViewByDefault: event.pdfBookViewByDefault));
  }

  Future<void> _onUpdateTalmudBavliOpenFormat(
    UpdateTalmudBavliOpenFormat event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateTalmudBavliOpenFormat(event.talmudBavliOpenFormat);
    emit(state.copyWith(talmudBavliOpenFormat: event.talmudBavliOpenFormat));
  }

  Future<void> _onUpdateOfflineMode(
    UpdateOfflineMode event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateOfflineMode(event.isOfflineMode);
    emit(state.copyWith(isOfflineMode: event.isOfflineMode));
  }

  Future<void> _onUpdateSoftwareAndBookUpdatesEnabled(
    UpdateSoftwareAndBookUpdatesEnabled event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateSoftwareAndBookUpdatesEnabled(event.enabled);
    emit(state.copyWith(softwareAndBookUpdatesEnabled: event.enabled));
  }

  Future<void> _onUpdateEnableHtmlLinks(
    UpdateEnableHtmlLinks event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateEnableHtmlLinks(event.enableHtmlLinks);
    emit(state.copyWith(enableHtmlLinks: event.enableHtmlLinks));
  }

  Future<void> _onUpdatePersonalNotesCollapsedByDefault(
    UpdatePersonalNotesCollapsedByDefault event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updatePersonalNotesCollapsedByDefault(
      event.collapsedByDefault,
    );
    emit(
      state.copyWith(personalNotesCollapsedByDefault: event.collapsedByDefault),
    );
  }

  Future<void> _onUpdateCompactMenuMode(
    UpdateCompactMenuMode event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateCompactMenuMode(event.compactMenuMode);
    emit(state.copyWith(compactMenuMode: event.compactMenuMode));
  }

  Future<void> _onUpdateReadingTabsPlacement(
    UpdateReadingTabsPlacement event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateReadingTabsPlacement(event.placement);
    emit(state.copyWith(readingTabsPlacement: event.placement));
  }

  Future<void> _onUpdateReadingTabsColumnWidth(
    UpdateReadingTabsColumnWidth event,
    Emitter<SettingsState> emit,
  ) async {
    final width = event.width.clamp(
      SettingsRepository.minReadingTabsColumnWidth,
      SettingsRepository.maxReadingTabsColumnWidth,
    );
    await _repository.updateReadingTabsColumnWidth(width);
    emit(state.copyWith(readingTabsColumnWidth: width));
  }

  Future<void> _onUpdateReadingTabsColumnCollapsed(
    UpdateReadingTabsColumnCollapsed event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateReadingTabsColumnCollapsed(event.collapsed);
    emit(state.copyWith(readingTabsColumnCollapsed: event.collapsed));
  }

  Future<void> _onUpdateMergeUserBooksIntoLibrary(
    UpdateMergeUserBooksIntoLibrary event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateMergeUserBooksIntoLibrary(
      event.mergeUserBooksIntoLibrary,
    );
    emit(
      state.copyWith(
        mergeUserBooksIntoLibrary: event.mergeUserBooksIntoLibrary,
      ),
    );
  }

  Future<void> _onUpdateProtectedModeEnabled(
    UpdateProtectedModeEnabled event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateProtectedModeEnabled(event.enabled);
    emit(state.copyWith(protectedModeEnabled: event.enabled));
  }

  Future<void> _onUpdateProtectedModePassword(
    UpdateProtectedModePassword event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateProtectedModePassword(event.password);
    emit(state.copyWith(protectedModePasswordSet: true));
  }

  Future<void> _onClearProtectedModePassword(
    ClearProtectedModePassword event,
    Emitter<SettingsState> emit,
  ) async {
    // אי אפשר להסיר סיסמה כשמצב הסייפר פעיל - יש להשבית אותו קודם.
    if (state.protectedModeEnabled) return;
    await _repository.clearProtectedModePassword();
    emit(state.copyWith(protectedModePasswordSet: false));
  }

  Future<void> _onUpdateHiddenBuiltInToolIds(
    UpdateHiddenBuiltInToolIds event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateHiddenBuiltInToolIds(event.hiddenBuiltInToolIds);
    emit(state.copyWith(hiddenBuiltInToolIds: event.hiddenBuiltInToolIds));
  }

  Future<void> _onUpdateBuiltInToolsPinnedToNavRail(
    UpdateBuiltInToolsPinnedToNavRail event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateBuiltInToolsPinnedToNavRail(
      event.builtInToolsPinnedToNavRail,
    );
    emit(
      state.copyWith(
        builtInToolsPinnedToNavRail: event.builtInToolsPinnedToNavRail,
      ),
    );
  }

  Future<void> _onUpdateBuiltInToolsOrder(
    UpdateBuiltInToolsOrder event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateBuiltInToolsOrder(event.builtInToolsOrder);
    emit(state.copyWith(builtInToolsOrder: event.builtInToolsOrder));
  }

  Future<void> _onUpdateDarkMode(
    UpdateDarkMode event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDarkMode(event.isDarkMode);
    emit(state.copyWith(isDarkMode: event.isDarkMode));
  }

  Future<void> _onUpdateFollowSystemTheme(
    UpdateFollowSystemTheme event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateFollowSystemTheme(event.followSystemTheme);
    emit(state.copyWith(followSystemTheme: event.followSystemTheme));
  }

  Future<void> _onUpdateSeedColor(
    UpdateSeedColor event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateSeedColor(event.seedColor);
    emit(state.copyWith(seedColor: event.seedColor));
  }

  Future<void> _onUpdateDarkSeedColor(
    UpdateDarkSeedColor event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDarkSeedColor(event.darkSeedColor);
    emit(state.copyWith(darkSeedColor: event.darkSeedColor));
  }

  Future<void> _onUpdateTextMaxWidth(
    UpdateTextMaxWidth event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateTextMaxWidth(event.textMaxWidth);
    emit(state.copyWith(textMaxWidth: event.textMaxWidth));
  }

  Future<void> _onUpdateFontSize(
    UpdateFontSize event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateFontSize(event.fontSize);
    emit(state.copyWith(fontSize: event.fontSize));

    // ניקוי קבצי per_book_settings מיותרים
    _cleanupRedundantPerBookSettings();
  }

  Future<void> _onUpdateFontFamily(
    UpdateFontFamily event,
    Emitter<SettingsState> emit,
  ) async {
    await AppFonts.ensureFontLoaded(event.fontFamily);
    await _repository.updateFontFamily(event.fontFamily);
    emit(state.copyWith(fontFamily: event.fontFamily));
  }

  Future<void> _onUpdateCommentatorsFontFamily(
    UpdateCommentatorsFontFamily event,
    Emitter<SettingsState> emit,
  ) async {
    await AppFonts.ensureFontLoaded(event.commentatorsFontFamily);
    await _repository.updateCommentatorsFontFamily(
      event.commentatorsFontFamily,
    );
    emit(state.copyWith(commentatorsFontFamily: event.commentatorsFontFamily));
  }

  Future<void> _onUpdateFontBold(
    UpdateFontBold event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateFontBold(event.fontBold);
    emit(state.copyWith(fontBold: event.fontBold));
  }

  Future<void> _onUpdateCommentatorsFontBold(
    UpdateCommentatorsFontBold event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateCommentatorsFontBold(event.commentatorsFontBold);
    emit(state.copyWith(commentatorsFontBold: event.commentatorsFontBold));
  }

  Future<void> _onUpdateCommentatorsFontSize(
    UpdateCommentatorsFontSize event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateCommentatorsFontSize(event.commentatorsFontSize);
    emit(state.copyWith(commentatorsFontSize: event.commentatorsFontSize));
  }

  Future<void> _onUpdateLineHeight(
    UpdateLineHeight event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateLineHeight(event.lineHeight);
    emit(state.copyWith(lineHeight: event.lineHeight));
  }

  Future<void> _onUpdateShowOtzarHachochma(
    UpdateShowOtzarHachochma event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateShowOtzarHachochma(event.showOtzarHachochma);
    emit(state.copyWith(showOtzarHachochma: event.showOtzarHachochma));
  }

  Future<void> _onUpdateShowHebrewBooks(
    UpdateShowHebrewBooks event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateShowHebrewBooks(event.showHebrewBooks);
    emit(state.copyWith(showHebrewBooks: event.showHebrewBooks));
  }

  Future<void> _onUpdateShowExternalBooks(
    UpdateShowExternalBooks event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateShowExternalBooks(event.showExternalBooks);
    emit(state.copyWith(showExternalBooks: event.showExternalBooks));
  }

  Future<void> _onUpdateShowTeamim(
    UpdateShowTeamim event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateShowTeamim(event.showTeamim);
    emit(state.copyWith(showTeamim: event.showTeamim));
  }

  Future<void> _onUpdateReplaceHolyNames(
    UpdateReplaceHolyNames event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateReplaceHolyNames(event.replaceHolyNames);
    emit(state.copyWith(replaceHolyNames: event.replaceHolyNames));
  }

  Future<void> _onUpdateAutoUpdateIndex(
    UpdateAutoUpdateIndex event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateAutoUpdateIndex(event.autoUpdateIndex);
    emit(state.copyWith(autoUpdateIndex: event.autoUpdateIndex));
  }

  Future<void> _onUpdateDefaultRemoveNikud(
    UpdateDefaultRemoveNikud event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDefaultRemoveNikud(event.defaultRemoveNikud);
    emit(state.copyWith(defaultRemoveNikud: event.defaultRemoveNikud));

    // ניקוי קבצי per_book_settings מיותרים
    _cleanupRedundantPerBookSettings();
  }

  Future<void> _onUpdateDefaultContinuousReadingMode(
    UpdateDefaultContinuousReadingMode event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDefaultContinuousReadingMode(
      event.defaultContinuousReadingMode,
    );
    emit(
      state.copyWith(
        defaultContinuousReadingMode: event.defaultContinuousReadingMode,
      ),
    );

    // ניקוי קבצי per_book_settings מיותרים
    _cleanupRedundantPerBookSettings();
  }

  Future<void> _onUpdateRemoveNikudFromTanach(
    UpdateRemoveNikudFromTanach event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateRemoveNikudFromTanach(event.removeNikudFromTanach);
    emit(state.copyWith(removeNikudFromTanach: event.removeNikudFromTanach));
  }

  Future<void> _onUpdateDefaultRemovePunctuation(
    UpdateDefaultRemovePunctuation event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDefaultRemovePunctuation(
      event.defaultRemovePunctuation,
    );
    emit(
      state.copyWith(defaultRemovePunctuation: event.defaultRemovePunctuation),
    );

    // ניקוי קבצי per_book_settings מיותרים
    _cleanupRedundantPerBookSettings();
  }

  Future<void> _onUpdateDefaultSidebarOpen(
    UpdateDefaultSidebarOpen event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDefaultSidebarOpen(event.defaultSidebarOpen);
    emit(state.copyWith(defaultSidebarOpen: event.defaultSidebarOpen));
  }

  Future<void> _onUpdateDefaultCommentaryOpen(
    UpdateDefaultCommentaryOpen event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDefaultCommentaryOpen(event.defaultCommentaryOpen);
    emit(state.copyWith(defaultCommentaryOpen: event.defaultCommentaryOpen));
  }

  Future<void> _onUpdatePinSidebar(
    UpdatePinSidebar event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updatePinSidebar(event.pinSidebar);
    emit(state.copyWith(pinSidebar: event.pinSidebar));
  }

  Future<void> _onUpdateSidebarWidth(
    UpdateSidebarWidth event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateSidebarWidth(event.sidebarWidth);
    emit(state.copyWith(sidebarWidth: event.sidebarWidth));
  }

  Future<void> _onUpdateFacetFilteringWidth(
    UpdateFacetFilteringWidth event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateFacetFilteringWidth(event.facetFilteringWidth);
    emit(state.copyWith(facetFilteringWidth: event.facetFilteringWidth));
  }

  Future<void> _onUpdateExternalResultsFirst(
    UpdateExternalResultsFirst event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateExternalResultsFirst(event.externalResultsFirst);
    emit(state.copyWith(externalResultsFirst: event.externalResultsFirst));
  }

  Future<void> _onUpdateCommentaryPaneWidth(
    UpdateCommentaryPaneWidth event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateCommentaryPaneWidth(event.commentaryPaneWidth);
    emit(state.copyWith(commentaryPaneWidth: event.commentaryPaneWidth));
  }

  Future<void> _onUpdateCopyWithHeaders(
    UpdateCopyWithHeaders event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateCopyWithHeaders(event.copyWithHeaders);
    emit(state.copyWith(copyWithHeaders: event.copyWithHeaders));
  }

  Future<void> _onUpdateCopyHeaderFormat(
    UpdateCopyHeaderFormat event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateCopyHeaderFormat(event.copyHeaderFormat);
    emit(state.copyWith(copyHeaderFormat: event.copyHeaderFormat));
  }

  Future<void> _onUpdateIsFullscreen(
    UpdateIsFullscreen event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateIsFullscreen(event.isFullscreen);
    emit(state.copyWith(isFullscreen: event.isFullscreen));
  }

  Future<void> _onUpdateLibraryViewMode(
    UpdateLibraryViewMode event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateLibraryViewMode(event.libraryViewMode);
    emit(state.copyWith(libraryViewMode: event.libraryViewMode));
  }

  Future<void> _onUpdateLibraryShowPreview(
    UpdateLibraryShowPreview event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateLibraryShowPreview(event.libraryShowPreview);
    emit(state.copyWith(libraryShowPreview: event.libraryShowPreview));
  }

  Future<void> _onUpdateSearchShowPreview(
    UpdateSearchShowPreview event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateSearchShowPreview(event.searchShowPreview);
    emit(state.copyWith(searchShowPreview: event.searchShowPreview));
  }

  Future<void> _onRefreshShortcuts(
    RefreshShortcuts event,
    Emitter<SettingsState> emit,
  ) async {
    // Toggle a value and back to force a state change
    // This is a workaround to trigger UI rebuild when shortcuts change
    emit(state.copyWith(isFullscreen: !state.isFullscreen));
    await Future.delayed(const Duration(milliseconds: 1));
    emit(state.copyWith(isFullscreen: state.isFullscreen));
  }

  Future<void> _onResetShortcuts(
    ResetShortcuts event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.resetShortcuts();
    final shortcuts = await _repository.getShortcuts();
    emit(
      state.copyWith(
        shortcuts: Map<String, String>.unmodifiable(shortcuts),
      ),
    );
  }

  Future<void> _onUpdateShortcut(
    UpdateShortcut event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateShortcut(event.key, event.value);
    final shortcuts = await _repository.getShortcuts();
    emit(
      state.copyWith(
        shortcuts: Map<String, String>.unmodifiable(shortcuts),
      ),
    );
  }

  /// ניקוי קבצי per_book_settings שהפכו למיותרים
  void _cleanupRedundantPerBookSettings() {
    // הרצה אסינכרונית ללא המתנה כדי לא לחסום את ה-UI
    // בטסטים, זה עלול להיכשל בגלל חוסר פלאגין, אז נתפוס שגיאות
    try {
      PerBookSettings.cleanupRedundantSettings(
        defaultFontSize: state.fontSize,
        defaultRemoveNikud: state.defaultRemoveNikud,
        removeNikudFromTanach: state.removeNikudFromTanach,
        defaultRemovePunctuation: state.defaultRemovePunctuation,
        defaultShowSplitView:
            Settings.getValue<bool>('key-splited-view') ?? true,
        defaultContinuousReadingMode: state.defaultContinuousReadingMode,
      );
    } catch (e) {
      // בטסטים או בסביבות ללא פלאגין, זה בסדר להתעלם
      // השגיאה לא קריטית
    }
  }
}
