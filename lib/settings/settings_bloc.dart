import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/settings/per_book_settings.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsRepository _repository;

  SettingsBloc({required SettingsRepository repository})
      : _repository = repository,
        super(SettingsState.initial()) {
    on<LoadSettings>(_onLoadSettings);
    on<UpdateDarkMode>(_onUpdateDarkMode);
    on<UpdateSeedColor>(_onUpdateSeedColor);
    on<UpdateDarkSeedColor>(_onUpdateDarkSeedColor);
    on<UpdateTextMaxWidth>(_onUpdateTextMaxWidth);
    on<UpdateFontSize>(_onUpdateFontSize);
    on<UpdateFontFamily>(_onUpdateFontFamily);
    on<UpdateCommentatorsFontFamily>(_onUpdateCommentatorsFontFamily);
    on<UpdateCommentatorsFontSize>(_onUpdateCommentatorsFontSize);
    on<UpdateShowOtzarHachochma>(_onUpdateShowOtzarHachochma);
    on<UpdateShowHebrewBooks>(_onUpdateShowHebrewBooks);
    on<UpdateShowExternalBooks>(_onUpdateShowExternalBooks);
    on<UpdateShowTeamim>(_onUpdateShowTeamim);
    on<UpdateUseFastSearch>(_onUpdateUseFastSearch);
    on<UpdateReplaceHolyNames>(_onUpdateReplaceHolyNames);
    on<UpdateAutoUpdateIndex>(_onUpdateAutoUpdateIndex);
    on<UpdateDefaultRemoveNikud>(_onUpdateDefaultRemoveNikud);
    on<UpdateRemoveNikudFromTanach>(_onUpdateRemoveNikudFromTanach);
    on<UpdateDefaultSidebarOpen>(_onUpdateDefaultSidebarOpen);
    on<UpdatePinSidebar>(_onUpdatePinSidebar);
    on<UpdateSidebarWidth>(_onUpdateSidebarWidth);
    on<UpdateFacetFilteringWidth>(_onUpdateFacetFilteringWidth);
    on<UpdateCommentaryPaneWidth>(_onUpdateCommentaryPaneWidth);
    on<UpdateCopyWithHeaders>(_onUpdateCopyWithHeaders);
    on<UpdateCopyHeaderFormat>(_onUpdateCopyHeaderFormat);
    on<UpdateIsFullscreen>(_onUpdateIsFullscreen);
    on<UpdateLibraryViewMode>(_onUpdateLibraryViewMode);
    on<UpdateLibraryShowPreview>(_onUpdateLibraryShowPreview);
    on<RefreshShortcuts>(_onRefreshShortcuts);
    on<ResetShortcuts>(_onResetShortcuts);
    on<UpdateShortcut>(_onUpdateShortcut);
    on<UpdateEnablePerBookSettings>(_onUpdateEnablePerBookSettings);
    on<UpdateOfflineMode>(_onUpdateOfflineMode);
    on<UpdateAlignTabsToRight>(_onUpdateAlignTabsToRight);
    on<UpdateEnableHtmlLinks>(_onUpdateEnableHtmlLinks);
  }

  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SettingsState> emit,
  ) async {
    final settings = await _repository.loadSettings();

    // בדסקטופ: אם המשתמש בחר גופן מערכת בעבר, נטען אותו כדי שיהיה זמין ב-TextStyle.
    await AppFonts.ensureFontLoaded(settings['fontFamily'] as String);
    await AppFonts.ensureFontLoaded(settings['commentatorsFontFamily'] as String);

    emit(SettingsState(
      isDarkMode: settings['isDarkMode'],
      seedColor: settings['seedColor'],
      darkSeedColor: settings['darkSeedColor'],
      textMaxWidth: settings['textMaxWidth'],
      fontSize: settings['fontSize'],
      fontFamily: settings['fontFamily'],
      commentatorsFontFamily: settings['commentatorsFontFamily'],
      commentatorsFontSize: settings['commentatorsFontSize'],
      showOtzarHachochma: settings['showOtzarHachochma'],
      showHebrewBooks: settings['showHebrewBooks'],
      showExternalBooks: settings['showExternalBooks'],
      showTeamim: settings['showTeamim'],
      useFastSearch: settings['useFastSearch'],
      replaceHolyNames: settings['replaceHolyNames'],
      autoUpdateIndex: settings['autoUpdateIndex'],
      defaultRemoveNikud: settings['defaultRemoveNikud'],
      removeNikudFromTanach: settings['removeNikudFromTanach'],
      defaultSidebarOpen: settings['defaultSidebarOpen'],
      pinSidebar: settings['pinSidebar'],
      sidebarWidth: settings['sidebarWidth'],
      facetFilteringWidth: settings['facetFilteringWidth'],
      commentaryPaneWidth: settings['commentaryPaneWidth'],
      copyWithHeaders: settings['copyWithHeaders'],
      copyHeaderFormat: settings['copyHeaderFormat'],
      isFullscreen: settings['isFullscreen'],
      libraryViewMode: settings['libraryViewMode'],
      libraryShowPreview: settings['libraryShowPreview'],
      shortcuts: Map<String, String>.unmodifiable(
        Map<String, String>.from(settings['shortcuts'] as Map),
      ),
      enablePerBookSettings: settings['enablePerBookSettings'],
      isOfflineMode: settings['isOfflineMode'] ?? false,
      alignTabsToRight: settings['alignTabsToRight'] ?? false,
      enableHtmlLinks: settings['enableHtmlLinks'] ?? true,
    ));
  }

  Future<void> _onUpdateEnablePerBookSettings(
    UpdateEnablePerBookSettings event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateEnablePerBookSettings(event.enablePerBookSettings);
    emit(state.copyWith(enablePerBookSettings: event.enablePerBookSettings));
  }

  Future<void> _onUpdateOfflineMode(
    UpdateOfflineMode event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateOfflineMode(event.isOfflineMode);
    emit(state.copyWith(isOfflineMode: event.isOfflineMode));
  }

  Future<void> _onUpdateAlignTabsToRight(
    UpdateAlignTabsToRight event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateAlignTabsToRight(event.alignTabsToRight);
    emit(state.copyWith(alignTabsToRight: event.alignTabsToRight));
  }

  Future<void> _onUpdateEnableHtmlLinks(
    UpdateEnableHtmlLinks event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateEnableHtmlLinks(event.enableHtmlLinks);
    emit(state.copyWith(enableHtmlLinks: event.enableHtmlLinks));
  }

  Future<void> _onUpdateDarkMode(
    UpdateDarkMode event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDarkMode(event.isDarkMode);
    emit(state.copyWith(isDarkMode: event.isDarkMode));
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
    await _repository
        .updateCommentatorsFontFamily(event.commentatorsFontFamily);
    emit(state.copyWith(commentatorsFontFamily: event.commentatorsFontFamily));
  }

  Future<void> _onUpdateCommentatorsFontSize(
    UpdateCommentatorsFontSize event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateCommentatorsFontSize(event.commentatorsFontSize);
    emit(state.copyWith(commentatorsFontSize: event.commentatorsFontSize));
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

  Future<void> _onUpdateUseFastSearch(
    UpdateUseFastSearch event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateUseFastSearch(event.useFastSearch);
    emit(state.copyWith(useFastSearch: event.useFastSearch));
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

  Future<void> _onUpdateRemoveNikudFromTanach(
    UpdateRemoveNikudFromTanach event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateRemoveNikudFromTanach(event.removeNikudFromTanach);
    emit(state.copyWith(removeNikudFromTanach: event.removeNikudFromTanach));
  }

  Future<void> _onUpdateDefaultSidebarOpen(
    UpdateDefaultSidebarOpen event,
    Emitter<SettingsState> emit,
  ) async {
    await _repository.updateDefaultSidebarOpen(event.defaultSidebarOpen);
    emit(state.copyWith(defaultSidebarOpen: event.defaultSidebarOpen));
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
    PerBookSettings.cleanupRedundantSettings(
      defaultFontSize: state.fontSize,
      defaultRemoveNikud: state.defaultRemoveNikud,
      defaultShowSplitView:
          Settings.getValue<bool>('key-splited-view') ?? false,
    );
  }
}
