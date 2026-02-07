import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/utils/color_utils.dart';
import '../../unit/mocks/mock_settings_wrapper.mocks.dart';

void main() {
  group('SettingsRepository', () {
    late SettingsRepository repository;
    late MockSettingsWrapper mockSettingsWrapper;

    setUp(() {
      mockSettingsWrapper = MockSettingsWrapper();
      repository = SettingsRepository(settings: mockSettingsWrapper);
    });

    test('loadSettings returns default values when settings are not set',
        () async {
      // Setup mock to return default values
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyDarkMode,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyFollowSystemTheme,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keySwatchColor,
              defaultValue: '#ff2c1b02'))
          .thenReturn('#ff2c1b02');
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keyDarkSwatchColor,
              defaultValue: '#ffce93d8'))
          .thenReturn('#ffce93d8');
      when(mockSettingsWrapper.getValue<double>(
              SettingsRepository.keyTextMaxWidth,
              defaultValue: -1))
          .thenReturn(-1.0);
      when(mockSettingsWrapper.getValue<double>(SettingsRepository.keyFontSize,
              defaultValue: 25))
          .thenReturn(25.0);
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keyFontFamily,
              defaultValue: 'FrankRuhlCLM'))
          .thenReturn('FrankRuhlCLM');
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowOtzarHachochma,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowHebrewBooks,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowExternalBooks,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyShowTeamim,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyUseFastSearch,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyReplaceHolyNames,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyAutoUpdateIndex,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyDefaultNikud,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyRemoveNikudFromTanach,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyDefaultSidebarOpen,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyPinSidebar,
              defaultValue: false))
          .thenReturn(false);

      final settings = await repository.loadSettings();

      // Verify default values are returned
      expect(settings['isDarkMode'], false);
      expect(settings['followSystemTheme'], false);
      expect(settings['seedColor'], ColorUtils.colorFromString('#ff2c1b02'));
      expect(
          settings['darkSeedColor'], ColorUtils.colorFromString('#ffce93d8'));
      expect(settings['textMaxWidth'], -1.0);
      expect(settings['fontSize'], 25.0);
      expect(settings['fontFamily'], 'FrankRuhlCLM');
      expect(settings['showOtzarHachochma'], false);
      expect(settings['showHebrewBooks'], false);
      expect(settings['showExternalBooks'], false);
      expect(settings['showTeamim'], true);
      expect(settings['useFastSearch'], true);
      expect(settings['replaceHolyNames'], true);
      expect(settings['autoUpdateIndex'], true);
      expect(settings['defaultRemoveNikud'], false);
      expect(settings['removeNikudFromTanach'], false);
      expect(settings['defaultSidebarOpen'], false);
      expect(settings['pinSidebar'], false);
    });

    test('loadSettings returns custom values when settings are set', () async {
      // Setup mock to return custom values
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyDarkMode,
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyFollowSystemTheme,
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keySwatchColor,
              defaultValue: '#ff2c1b02'))
          .thenReturn('#ff0000ff'); // Blue
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keyDarkSwatchColor,
              defaultValue: '#ffce93d8'))
          .thenReturn('#ffce93d8');
      when(mockSettingsWrapper.getValue<double>(
              SettingsRepository.keyTextMaxWidth,
              defaultValue: -1))
          .thenReturn(800.0);
      when(mockSettingsWrapper.getValue<double>(SettingsRepository.keyFontSize,
              defaultValue: 25))
          .thenReturn(20.0);
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keyFontFamily,
              defaultValue: 'FrankRuhlCLM'))
          .thenReturn('Rubik');
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowOtzarHachochma,
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowHebrewBooks,
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowExternalBooks,
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyShowTeamim,
              defaultValue: true))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyUseFastSearch,
              defaultValue: true))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyReplaceHolyNames,
              defaultValue: true))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyAutoUpdateIndex,
              defaultValue: true))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyDefaultNikud,
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyRemoveNikudFromTanach,
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyDefaultSidebarOpen,
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyPinSidebar,
              defaultValue: false))
          .thenReturn(true);

      final settings = await repository.loadSettings();

      // Verify custom values are returned
      expect(settings['isDarkMode'], true);
      expect(settings['followSystemTheme'], true);
      expect(settings['seedColor'], ColorUtils.colorFromString('#ff0000ff'));
      expect(
          settings['darkSeedColor'], ColorUtils.colorFromString('#ffce93d8'));
      expect(settings['textMaxWidth'], 800.0);
      expect(settings['fontSize'], 20.0);
      expect(settings['fontFamily'], 'Rubik');
      expect(settings['showOtzarHachochma'], true);
      expect(settings['showHebrewBooks'], true);
      expect(settings['showExternalBooks'], true);
      expect(settings['showTeamim'], false);
      expect(settings['useFastSearch'], false);
      expect(settings['replaceHolyNames'], false);
      expect(settings['autoUpdateIndex'], false);
      expect(settings['defaultRemoveNikud'], true);
      expect(settings['removeNikudFromTanach'], true);
      expect(settings['defaultSidebarOpen'], true);
      expect(settings['pinSidebar'], true);
    });

    test('updateDarkMode calls setValue on settings wrapper', () async {
      await repository.updateDarkMode(true);
      verify(mockSettingsWrapper.setValue(SettingsRepository.keyDarkMode, true))
          .called(1);
    });

    test('updateFollowSystemTheme calls setValue on settings wrapper',
        () async {
      await repository.updateFollowSystemTheme(true);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyFollowSystemTheme, true))
          .called(1);
    });

    test('updateSeedColor calls setValue on settings wrapper', () async {
      const color = Colors.red;
      await repository.updateSeedColor(color);
      verify(mockSettingsWrapper.setValue(SettingsRepository.keySwatchColor,
              ColorUtils.colorToString(color)))
          .called(1);
    });

    test('updateFontSize calls setValue on settings wrapper', () async {
      await repository.updateFontSize(20.0);
      verify(mockSettingsWrapper.setValue(SettingsRepository.keyFontSize, 20.0))
          .called(1);
    });

    test('updateDefaultRemoveNikud calls setValue on settings wrapper',
        () async {
      await repository.updateDefaultRemoveNikud(true);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyDefaultNikud, true))
          .called(1);
    });

    test('updateRemoveNikudFromTanach calls setValue on settings wrapper',
        () async {
      await repository.updateRemoveNikudFromTanach(true);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyRemoveNikudFromTanach, true))
          .called(1);
    });

    test('updateDefaultSidebarOpen calls setValue on settings wrapper',
        () async {
      await repository.updateDefaultSidebarOpen(true);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyDefaultSidebarOpen, true))
          .called(1);
    });

    test('updatePinSidebar calls setValue on settings wrapper', () async {
      await repository.updatePinSidebar(true);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyPinSidebar, true))
          .called(1);
    });

    test('loadSettings initializes defaults when fontFamily is null', () async {
// Setup mock to return null for fontFamily (indicating first launch)
      when(mockSettingsWrapper.getValue<String?>(
              SettingsRepository.keyFontFamily,
              defaultValue: null)) // שינוי: הוספנו defaultValue
          .thenReturn(null);

      // Setup mock to return default values after initialization
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyDarkMode,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keySwatchColor,
              defaultValue: '#ff2c1b02'))
          .thenReturn('#ff2c1b02');
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keyDarkSwatchColor,
              defaultValue: '#ffce93d8'))
          .thenReturn('#ffce93d8');
      when(mockSettingsWrapper.getValue<double>(
              SettingsRepository.keyTextMaxWidth,
              defaultValue: -1))
          .thenReturn(-1.0);
      when(mockSettingsWrapper.getValue<double>(SettingsRepository.keyFontSize,
              defaultValue: 25))
          .thenReturn(25.0);
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keyFontFamily,
              defaultValue: 'FrankRuhlCLM'))
          .thenReturn('FrankRuhlCLM');
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowOtzarHachochma,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowHebrewBooks,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowExternalBooks,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyShowTeamim,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyUseFastSearch,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyReplaceHolyNames,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyAutoUpdateIndex,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyDefaultNikud,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyDefaultSidebarOpen,
              defaultValue: false))
          .thenReturn(false);

      await repository.loadSettings();

      // Verify that all defaults were written to storage
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyDarkMode, false))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keySwatchColor, '#ff2c1b02'))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyDarkSwatchColor, '#ffce93d8'))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyTextMaxWidth, -1.0))
          .called(1);
      verify(mockSettingsWrapper.setValue(SettingsRepository.keyFontSize, 25.0))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyFontFamily, 'FrankRuhlCLM'))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyShowOtzarHachochma, false))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyShowHebrewBooks, false))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyShowExternalBooks, false))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyShowTeamim, true))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyUseFastSearch, true))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyReplaceHolyNames, true))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyAutoUpdateIndex, true))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyDefaultNikud, false))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyRemoveNikudFromTanach, false))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyDefaultSidebarOpen, false))
          .called(1);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyPinSidebar, false))
          .called(1);
    });

    test('loadSettings does not initialize defaults when fontFamily exists',
        () async {
      // Setup mock to return existing fontFamily value
      when(mockSettingsWrapper.getValue<bool>('settings_initialized',
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<String?>(
              SettingsRepository.keyFontFamily,
              defaultValue: null))
          .thenReturn('FrankRuhlCLM');

      // Setup mock to return values for loadSettings
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyDarkMode,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keySwatchColor,
              defaultValue: '#ff2c1b02'))
          .thenReturn('#ff2c1b02');
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keyDarkSwatchColor,
              defaultValue: '#ffce93d8'))
          .thenReturn('#ffce93d8');
      when(mockSettingsWrapper.getValue<double>(
              SettingsRepository.keyTextMaxWidth,
              defaultValue: -1))
          .thenReturn(-1.0);
      when(mockSettingsWrapper.getValue<double>(SettingsRepository.keyFontSize,
              defaultValue: 25))
          .thenReturn(25.0);
      when(mockSettingsWrapper.getValue<String>(
              SettingsRepository.keyFontFamily,
              defaultValue: 'FrankRuhlCLM'))
          .thenReturn('FrankRuhlCLM');
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowOtzarHachochma,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowHebrewBooks,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyShowExternalBooks,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(SettingsRepository.keyShowTeamim,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyUseFastSearch,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyReplaceHolyNames,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyAutoUpdateIndex,
              defaultValue: true))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyDefaultNikud,
              defaultValue: false))
          .thenReturn(false);
      when(mockSettingsWrapper.getValue<bool>(
              SettingsRepository.keyDefaultSidebarOpen,
              defaultValue: false))
          .thenReturn(false);

      await repository.loadSettings();

      // Verify that setValue was never called for any defaults (since they already exist)
      verifyNever(mockSettingsWrapper.setValue(any, any));
    });
  });
}
