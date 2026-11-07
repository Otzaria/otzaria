import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

import '../../../integration_test/support/perf_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'prepared settings survive real repository startup without defaults',
    () async {
      expect(Settings.isInitialized, isFalse);
      final temporary = await Directory(
        await Directory.systemTemp.resolveSymbolicLinks(),
      ).createTemp('perf-startup-settings-');
      try {
        final fixture = PerfFixture(
          Directory(p.join(temporary.path, 'fixture')),
        );
        await fixture.prepare(preparationOnly: true);
        expect(
          Settings.isInitialized,
          isFalse,
          reason:
              'Preparing files must not initialize the app settings singleton.',
        );
        expect(Hive.isBoxOpen(HiveCache.keyName), isFalse);

        await Settings.init(cacheProvider: HiveCache());
        final expected = <String, Object>{
          SettingsRepository.keyOfflineMode: true,
          SettingsRepository.keySoftwareAndBookUpdatesEnabled: false,
          SettingsRepository.keyAutoUpdateIndex: false,
          SettingsRepository.keyIndexUpdateMode: 'off',
          SettingsRepository.keyAutoSync: false,
          SettingsRepository.keyAppCrashReportMode: 'never',
          SettingsRepository.keyShowLocalHebrewBooks: false,
          SettingsRepository.keyFontFamily: 'NotoSerifHebrew',
          SettingsRepository.keyFontSize: 22.0,
        };
        Map<String, Object?> values() => {
          for (final key in expected.keys) key: Settings.getValue<Object>(key),
        };
        expect(values(), expected);
        await SettingsRepository().loadSettings();
        expect(values(), expected);
        await SettingsRepository().loadSettings();
        expect(
          values(),
          expected,
          reason:
              'Repeated settings loads must preserve the prepared workload.',
        );
      } finally {
        await Hive.close();
        AppPaths.debugOverrideDataRootPath(null);
        AppPaths.debugOverrideDocumentsRootPath(null);
        await temporary.delete(recursive: true);
      }
    },
  );
}
