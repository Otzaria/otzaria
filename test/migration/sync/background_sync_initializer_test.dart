import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/migration/sync/background_sync_initializer.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../unit/mocks/mock_settings_wrapper.mocks.dart';

void main() {
  group('BackgroundSyncInitializer.shouldRunBackgroundSync', () {
    late MockSettingsWrapper mockSettingsWrapper;

    setUp(() {
      mockSettingsWrapper = MockSettingsWrapper();
    });

    test('returns false when offline mode is enabled', () {
      when(
        mockSettingsWrapper.getValue<bool>(
          SettingsRepository.keyOfflineMode,
          defaultValue: false,
        ),
      ).thenReturn(true);
      when(
        mockSettingsWrapper.getValue<bool>(
          SettingsRepository.keySoftwareAndBookUpdatesEnabled,
          defaultValue: true,
        ),
      ).thenReturn(true);

      final result = BackgroundSyncInitializer.shouldRunBackgroundSync(
        settingsWrapper: mockSettingsWrapper,
      );

      expect(result, isFalse);
    });

    test('returns false when software and book updates are disabled', () {
      when(
        mockSettingsWrapper.getValue<bool>(
          SettingsRepository.keyOfflineMode,
          defaultValue: false,
        ),
      ).thenReturn(false);
      when(
        mockSettingsWrapper.getValue<bool>(
          SettingsRepository.keySoftwareAndBookUpdatesEnabled,
          defaultValue: true,
        ),
      ).thenReturn(false);

      final result = BackgroundSyncInitializer.shouldRunBackgroundSync(
        settingsWrapper: mockSettingsWrapper,
      );

      expect(result, isFalse);
    });

    test('returns true when online and updates are enabled', () {
      when(
        mockSettingsWrapper.getValue<bool>(
          SettingsRepository.keyOfflineMode,
          defaultValue: false,
        ),
      ).thenReturn(false);
      when(
        mockSettingsWrapper.getValue<bool>(
          SettingsRepository.keySoftwareAndBookUpdatesEnabled,
          defaultValue: true,
        ),
      ).thenReturn(true);

      final result = BackgroundSyncInitializer.shouldRunBackgroundSync(
        settingsWrapper: mockSettingsWrapper,
      );

      expect(result, isTrue);
    });
  });

  group('BackgroundSyncInitializer.resetForAppRestart', () {
    /// מריצה את הסנכרון ומחכה שיסתיים. בסביבת בדיקה אין DB, ולכן הריצה
    /// נכשלת — מה שנבדק הוא דגל החסימה, לא תוצאת הסריקה.
    Future<void> runSyncIgnoringOutcome() async {
      await BackgroundSyncInitializer.initializeAfterDelay(delaySeconds: 0);
      await BackgroundSyncInitializer.waitForCompletion().catchError(
        (_) => null,
      );
    }

    tearDown(BackgroundSyncInitializer.reset);

    test('משחרר את חסימת הריצה הכפולה', () async {
      // RestartWidget בונה מחדש את העץ בלי לסגור את התהליך, ולכן הדגל הסטטי
      // היה שורד ומונע סריקה של תיקיות ספרים ששוחזרו מגיבוי.
      await runSyncIgnoringOutcome();
      expect(BackgroundSyncInitializer.hasRun, isTrue);

      BackgroundSyncInitializer.resetForAppRestart();

      expect(BackgroundSyncInitializer.hasRun, isFalse);
    });

    test('אחרי האיפוס הסנכרון רץ שוב', () async {
      await runSyncIgnoringOutcome();
      BackgroundSyncInitializer.resetForAppRestart();

      await runSyncIgnoringOutcome();

      expect(BackgroundSyncInitializer.hasRun, isTrue);
    });

    test('מבטל את סימון הסריקה הידנית של הסשן', () async {
      BackgroundSyncInitializer.markCustomFoldersSyncedThisSession();

      BackgroundSyncInitializer.resetForAppRestart();

      // אין getter לדגל, ולכן הבדיקה עקיפה: אחרי איפוס הריצה אינה מדלגת
      // בטענה שהסריקה כבר בוצעה בסשן.
      await runSyncIgnoringOutcome();
      expect(BackgroundSyncInitializer.hasRun, isTrue);
    });

    test('קריאה חוזרת אינה מפילה ואינה משנה מצב', () {
      BackgroundSyncInitializer.resetForAppRestart();
      BackgroundSyncInitializer.resetForAppRestart();

      expect(BackgroundSyncInitializer.hasRun, isFalse);
    });
  });

  group('BackgroundSyncInitializer כשל בסנכרון', () {
    late Directory dataRoot;

    setUp(() {
      dataRoot = Directory.systemTemp.createTempSync('background-sync-test-');
      AppPaths.debugOverrideDataRootPath(dataRoot.path);
    });

    tearDown(() {
      BackgroundSyncInitializer.reset();
      AppPaths.debugOverrideDataRootPath(null);
      dataRoot.deleteSync(recursive: true);
    });

    test('כשל בלי ממתין אינו הופך לשגיאה לא מטופלת', () async {
      final settings = MockSettingsWrapper();
      when(
        settings.getValue<bool>(
          SettingsRepository.keyOfflineMode,
          defaultValue: false,
        ),
      ).thenThrow(TimeoutException('sync worker hang: no progress'));
      BackgroundSyncInitializer.settings = settings;
      final uncaught = <Object>[];

      await runZonedGuarded(
        () => BackgroundSyncInitializer.initializeAfterDelay(delaySeconds: 0),
        (error, _) => uncaught.add(error),
      );
      await pumpEventQueue();

      expect(uncaught, isEmpty);
      await expectLater(
        BackgroundSyncInitializer.waitForCompletion(),
        throwsA(isA<TimeoutException>()),
      );
      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
      expect(
        ErrorLogFile.resolveFile().readAsStringSync(),
        contains('Background sync failed'),
      );
    });
  });
}
