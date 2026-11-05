import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup_appearance_');
    AppPaths.debugOverrideDataRootPath(root.path);
    AppPaths.debugOverrideDocumentsRootPath(root.path);
    RunnerWindowChannel.debugSupportedOverride = false;
    UserStateDatabase.instance.overridePath(p.join(root.path, 'user_state.db'));
    Hive.init(root.path);
    await Settings.init(cacheProvider: HiveCache());
    await SettingsRepository().loadSettings();
  });

  tearDown(() async {
    await Hive.close();
    UserStateDatabase.instance.close();
    RunnerWindowChannel.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideDocumentsRootPath(null);
    await root.delete(recursive: true);
  });

  test('גיבוי הגדרות משחזר צבעים ושמות גופנים גם לאחר טעינה מחדש', () async {
    const lightColor = Color(0xff123456);
    const darkColor = Color(0xffabcdef);
    const textFont = 'Local Text Font';
    const commentaryFont = 'Local Commentary Font';
    const bottomFont = 'Local Bottom Font';
    final source = SettingsRepository();
    await source.updateSeedColor(lightColor);
    await source.updateDarkSeedColor(darkColor);
    await source.updateFontFamily(textFont);
    await source.updateCommentatorsFontFamily(commentaryFont);
    await Settings.setValue(
      SettingsRepository.keyPageShapeBottomFont,
      bottomFont,
    );

    final backup = await BackupService.createBackup(
      includeSettings: true,
      includeBookmarks: false,
      includeHistory: false,
      includeNotes: false,
      includeWorkspaces: false,
      includeShamorZachor: false,
      includePlugins: false,
    );
    expect(backup.skippedSections, isEmpty);
    final manifest = jsonDecode(await File(backup.path).readAsString()) as Map;
    final saved = manifest['settings'] as Map;
    expect(saved[SettingsRepository.keySwatchColor], lightColor.toARGB32());
    expect(saved[SettingsRepository.keyDarkSwatchColor], darkColor.toARGB32());
    expect(saved[SettingsRepository.keyFontFamily], textFont);
    expect(saved[SettingsRepository.keyCommentatorsFontFamily], commentaryFont);
    expect(saved[SettingsRepository.keyPageShapeBottomFont], bottomFont);
    final includes = manifest['includes'] as Map;
    expect(
      includes.entries
          .where((entry) => entry.value == true)
          .map((entry) => entry.key),
      ['settings'],
    );
    expect(manifest.containsKey('plugins'), isFalse);

    // התקנה נקייה מאתחלת ברירות מחדל לפני שמסך השחזור זמין.
    await Settings.clearCache();
    final defaults = await SettingsRepository().loadSettings();
    expect(defaults['seedColor'], isNot(lightColor));
    expect(defaults['darkSeedColor'], isNot(darkColor));
    expect(defaults['fontFamily'], isNot(textFont));

    final restored = await BackupService.restoreFromBackup(backup.path);
    expect(restored.skippedSections, isEmpty);
    expect(restored.hasLegacyPartialSettings, isFalse);

    await Hive.close();
    await Settings.init(cacheProvider: HiveCache());
    final destination = SettingsRepository();
    final requestedFonts = <String>[];
    final bloc = SettingsBloc(
      repository: destination,
      initialSettings: destination.readSettings(),
      ensureFontLoaded: (family) async => requestedFonts.add(family),
    );
    addTearDown(() async {
      if (!bloc.isClosed) await bloc.close();
    });
    expect(bloc.state.seedColor, lightColor);
    expect(bloc.state.darkSeedColor, darkColor);
    expect(bloc.state.fontFamily, textFont);
    expect(bloc.state.commentatorsFontFamily, commentaryFont);

    final loaded = bloc.stream.first;
    bloc.add(LoadSettings());
    await loaded;
    await bloc.close();
    expect(bloc.state.seedColor, lightColor);
    expect(bloc.state.darkSeedColor, darkColor);
    expect(bloc.state.fontFamily, textFont);
    expect(bloc.state.commentatorsFontFamily, commentaryFont);
    expect(requestedFonts, [textFont, commentaryFont, bottomFont]);
  });
}
