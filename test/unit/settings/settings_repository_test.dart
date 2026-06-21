import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/theme/theme_exports.dart';
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
      when(mockSettingsWrapper.getValue<int>(SettingsRepository.keySwatchColor,
              defaultValue: AppSeedColors.defaultLight.toARGB32()))
          .thenReturn(AppSeedColors.defaultLight.toARGB32());
      when(mockSettingsWrapper.getValue<int>(
              SettingsRepository.keyDarkSwatchColor,
              defaultValue: AppSeedColors.defaultDark.toARGB32()))
          .thenReturn(AppSeedColors.defaultDark.toARGB32());
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
      expect(settings['seedColor'], AppSeedColors.defaultLight);
      expect(settings['darkSeedColor'], AppSeedColors.defaultDark);
      expect(settings['textMaxWidth'], -1.0);
      expect(settings['fontSize'], 25.0);
      expect(settings['fontFamily'], 'FrankRuhlCLM');
      expect(settings['showOtzarHachochma'], false);
      expect(settings['showHebrewBooks'], false);
      expect(settings['showExternalBooks'], false);
      expect(settings['showTeamim'], true);
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
      when(mockSettingsWrapper.getValue<int>(SettingsRepository.keySwatchColor,
              defaultValue: AppSeedColors.defaultLight.toARGB32()))
          .thenReturn(const Color(0xff0000ff).toARGB32()); // Blue
      when(mockSettingsWrapper.getValue<int>(
              SettingsRepository.keyDarkSwatchColor,
              defaultValue: AppSeedColors.defaultDark.toARGB32()))
          .thenReturn(AppSeedColors.defaultDark.toARGB32());
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
      expect(settings['seedColor'], const Color(0xff0000ff));
      expect(settings['darkSeedColor'], AppSeedColors.defaultDark);
      expect(settings['textMaxWidth'], 800.0);
      expect(settings['fontSize'], 20.0);
      expect(settings['fontFamily'], 'Rubik');
      expect(settings['showOtzarHachochma'], true);
      expect(settings['showHebrewBooks'], true);
      expect(settings['showExternalBooks'], true);
      expect(settings['showTeamim'], false);
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
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keySwatchColor, color.toARGB32()))
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

    test('updateDefaultCommentaryOpen calls setValue on settings wrapper',
        () async {
      await repository.updateDefaultCommentaryOpen(true);
      verify(mockSettingsWrapper.setValue(
              SettingsRepository.keyDefaultCommentaryOpen, true))
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
      when(mockSettingsWrapper.getValue<int>(SettingsRepository.keySwatchColor,
              defaultValue: AppSeedColors.defaultLight.toARGB32()))
          .thenReturn(AppSeedColors.defaultLight.toARGB32());
      when(mockSettingsWrapper.getValue<int>(
              SettingsRepository.keyDarkSwatchColor,
              defaultValue: AppSeedColors.defaultDark.toARGB32()))
          .thenReturn(AppSeedColors.defaultDark.toARGB32());
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
      verify(mockSettingsWrapper.setValue(SettingsRepository.keySwatchColor,
              AppSeedColors.defaultLight.toARGB32()))
          .called(1);
      verify(mockSettingsWrapper.setValue(SettingsRepository.keyDarkSwatchColor,
              AppSeedColors.defaultDark.toARGB32()))
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
      when(mockSettingsWrapper.getValue<int>(SettingsRepository.keySwatchColor,
              defaultValue: AppSeedColors.defaultLight.toARGB32()))
          .thenReturn(AppSeedColors.defaultLight.toARGB32());
      when(mockSettingsWrapper.getValue<int>(
              SettingsRepository.keyDarkSwatchColor,
              defaultValue: AppSeedColors.defaultDark.toARGB32()))
          .thenReturn(AppSeedColors.defaultDark.toARGB32());
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

    test('getShortcuts migrates legacy search key to current window search key',
        () async {
      const legacyValue = 'ctrl+shift+f';

      when(mockSettingsWrapper.getValue('shortcuts', defaultValue: {}))
          .thenReturn({
        ShortcutValidator.legacySearchInBookKey: legacyValue,
      });
      when(mockSettingsWrapper.getValue<String?>(
        ShortcutValidator.legacySearchInBookKey,
        defaultValue: legacyValue,
      )).thenReturn(legacyValue);

      final shortcuts = await repository.getShortcuts();

      expect(
        shortcuts[ShortcutValidator.currentWindowSearchKey],
        legacyValue,
      );
    });

    test('updateShortcut removes legacy search key when saving canonical key',
        () async {
      when(mockSettingsWrapper.getValue('shortcuts', defaultValue: {}))
          .thenReturn({
        ShortcutValidator.legacySearchInBookKey: 'ctrl+alt+f',
      });

      await repository.updateShortcut(
        ShortcutValidator.currentWindowSearchKey,
        'ctrl+shift+f',
      );

      verify(mockSettingsWrapper.setValue(
        ShortcutValidator.currentWindowSearchKey,
        'ctrl+shift+f',
      )).called(1);
      verify(mockSettingsWrapper.remove(
        ShortcutValidator.legacySearchInBookKey,
      )).called(1);

      final captured = verify(mockSettingsWrapper.setValue(
        'shortcuts',
        captureAny,
      )).captured.single as Map<String, String>;
      expect(
        captured[ShortcutValidator.currentWindowSearchKey],
        'ctrl+shift+f',
      );
      expect(
        captured.containsKey(ShortcutValidator.legacySearchInBookKey),
        isFalse,
      );
    });

    // ─── Tools-management keys (built-in tools hidden / pinned-to-nav-rail) ──
    //
    // הערכים נשמרים כ-CSV ממוין. בדיקות אלה מבטיחות:
    //   1. סדרת CSV דטרמיניסטית (ממוין) ⇒ אין dirty diffs ב-SharedPreferences.
    //   2. ערכים שנשמרים נטענים זהים — round-trip.
    //   3. סט ריק נשמר כמחרוזת ריקה (ולא כ-`",,"` או דומה).

    test('updateHiddenBuiltInToolIds serializes the set to a sorted CSV',
        () async {
      // הקלט הוא Set לא ממוין; הפלט חייב להיות ממוין כדי שהמחרוזת הנשמרת
      // תהיה דטרמיניסטית בין הפעלות.
      await repository.updateHiddenBuiltInToolIds(
        {'builtin.gematria', 'builtin.calendar', 'builtin.notes'},
      );

      final captured = verify(mockSettingsWrapper.setValue(
        SettingsRepository.keyHiddenBuiltInToolIds,
        captureAny,
      )).captured.single as String;

      expect(captured, 'builtin.calendar,builtin.gematria,builtin.notes');
    });

    test('updateHiddenBuiltInToolIds saves empty set as empty string',
        () async {
      await repository.updateHiddenBuiltInToolIds(<String>{});

      verify(mockSettingsWrapper.setValue(
        SettingsRepository.keyHiddenBuiltInToolIds,
        '',
      )).called(1);
    });

    test('updateBuiltInToolsPinnedToNavRail uses its own key', () async {
      await repository.updateBuiltInToolsPinnedToNavRail(
        {'builtin.calendar'},
      );

      verify(mockSettingsWrapper.setValue(
        SettingsRepository.keyBuiltInToolsPinnedToNavRail,
        'builtin.calendar',
      )).called(1);
    });

    test('loadSettings parses hiddenBuiltInToolIds CSV into a Set', () async {
      // מאתחלים את כל ה-defaults הנדרשים כדי ש-loadSettings יסיים בלי
      // null-cast errors — אבל ה-stubs לערכי ברירת מחדל מספקים את זה דרך
      // ה-MockSettingsWrapper.
      when(mockSettingsWrapper.getValue<bool>('settings_initialized',
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<String>(
        SettingsRepository.keyHiddenBuiltInToolIds,
        defaultValue: '',
      )).thenReturn('builtin.calendar,builtin.gematria');
      when(mockSettingsWrapper.getValue<String>(
        SettingsRepository.keyBuiltInToolsPinnedToNavRail,
        defaultValue: '',
      )).thenReturn('');

      // שאר ה-stubs כבר מוגדרים ב-mock עם defaults — נטען את כל המפה
      final settings = await repository.loadSettings();

      expect(
        settings['hiddenBuiltInToolIds'],
        equals({'builtin.calendar', 'builtin.gematria'}),
      );
      expect(
        settings['builtInToolsPinnedToNavRail'],
        equals(<String>{}),
        reason: 'empty CSV must round-trip to an empty Set, not a Set with an '
            'empty string',
      );
    });

    test('loadSettings tolerates whitespace and empty entries in CSV',
        () async {
      when(mockSettingsWrapper.getValue<bool>('settings_initialized',
              defaultValue: false))
          .thenReturn(true);
      when(mockSettingsWrapper.getValue<String>(
        SettingsRepository.keyHiddenBuiltInToolIds,
        defaultValue: '',
      )).thenReturn('builtin.calendar, ,builtin.notes,');
      when(mockSettingsWrapper.getValue<String>(
        SettingsRepository.keyBuiltInToolsPinnedToNavRail,
        defaultValue: '',
      )).thenReturn('');

      final settings = await repository.loadSettings();

      expect(
        settings['hiddenBuiltInToolIds'],
        equals({'builtin.calendar', 'builtin.notes'}),
        reason: 'parser must trim whitespace and drop empty entries',
      );
    });
  });
}
