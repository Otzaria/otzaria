import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/shared_preferences_cache.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_steps.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_tour_');
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    Hive.init(tempDir.path);
    UserStateDatabase.instance.overridePath(
      p.join(tempDir.path, 'user_state.db'),
    );
    PluginSystemDatabase.instance.resetForTests();
  });

  tearDown(() async {
    await AttachedLibraryRegistry.instance.reset();
    PluginSystemDatabase.instance.resetForTests();
    await UserStateDatabase.instance.flushWrites();
    UserStateDatabase.instance.close();
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  Future<void> configurePaths() async {
    await Settings.setValue<String>(
      SettingsRepository.keyBackupPath,
      p.join(tempDir.path, 'backups'),
    );
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      p.join(tempDir.path, 'databases'),
    );
  }

  test('tour keys identify unmarked backups as full settings scans', () {
    final tourSettings = {
      TourSteps.statusKey: TourSteps.completed,
      LiveTipStorage.resolvedTipsKey: LiveTipId.dictionaryContextMenuHint.name,
      LiveTipStorage.launchCountKey: 12,
    };
    for (final entry in tourSettings.entries) {
      final settings = {entry.key: entry.value};
      expect(BackupService.isPartialSettingsSection(settings, null), isFalse);
      expect(
        BackupService.isPartialSettingsSection(settings, 'declared-keys'),
        isTrue,
      );
    }
  });

  for (final useFallback in [false, true]) {
    final source = useFallback ? 'declared-keys' : 'box';
    test('round-trip preserves tour and dismissed tips from $source', () async {
      if (useFallback) {
        SharedPreferences.setMockInitialValues({});
        await Settings.init(cacheProvider: SharePreferenceCache());
      } else {
        await Settings.init(cacheProvider: HiveCache());
      }
      await configurePaths();
      await Settings.setValue<int>(LiveTipStorage.launchCountKey, 11);

      final original = TourCubit(delayedTipSchedules: const []);
      original.registerSession();
      original.start(libraryLoaded: true);
      await original.complete();
      for (var i = 0; i < 2; i++) {
        await original.recordInteraction(
          TourInteraction(type: TourInteractionType.textSelected),
        );
      }
      expect(
        original.state.activeLiveTipId,
        LiveTipId.dictionaryContextMenuHint,
      );
      original.dismissLiveTip();
      await original.close();

      final backup = await BackupService.createBackup(
        includeSettings: true,
        includeBookmarks: false,
        includeHistory: false,
        includeNotes: false,
        includeWorkspaces: false,
        includeShamorZachor: false,
        includePlugins: false,
      );
      final manifest =
          jsonDecode(await File(backup.path).readAsString())
              as Map<String, dynamic>;
      expect(manifest['settingsSource'], source);
      final settings = manifest['settings'] as Map<String, dynamic>;
      expect(settings[TourSteps.statusKey], TourSteps.completed);
      expect(settings[LiveTipStorage.launchCountKey], 12);
      expect(
        LiveTipStorage.decode(
          settings[LiveTipStorage.resolvedTipsKey] as String?,
        ),
        {LiveTipId.dictionaryContextMenuHint},
      );

      await Settings.clearCache();
      await configurePaths();
      await BackupService.restoreFromBackup(backup.path);

      final restored = TourCubit(delayedTipSchedules: const []);
      addTearDown(restored.close);
      expect(restored.startIfNeeded(libraryLoaded: true), isFalse);
      expect(restored.state.resolvedTips, {
        LiveTipId.dictionaryContextMenuHint,
      });
      expect(Settings.getValue<int>(LiveTipStorage.launchCountKey), 12);
      restored.registerSession();
      expect(Settings.getValue<int>(LiveTipStorage.launchCountKey), 13);
      for (var i = 0; i < 2; i++) {
        await restored.recordInteraction(
          TourInteraction(type: TourInteractionType.textSelected),
        );
      }
      expect(restored.state.activeLiveTipId, isNull);

      for (final title in ['first', 'second', 'first', 'second', 'first']) {
        await restored.recordInteraction(
          TourInteraction(
            type: TourInteractionType.currentTabChanged,
            primaryValue: title,
          ),
        );
      }
      expect(restored.state.activeLiveTipId, LiveTipId.sideBySideSuggestion);
    });
  }
}
