import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/settings/tabs/system_settings_tab.dart';
import 'package:otzaria/settings/widgets/expandable_settings_tile.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _DelayedHiveCache extends HiveCache {
  Completer<void>? pendingWrites;
  Completer<void>? allWritesStarted;
  int startedWrites = 0;

  @override
  Future<void> setObject<T>(String key, T? value) async {
    final writing = super.setObject(key, value);
    if (pendingWrites != null &&
        BackupService.sectionSettingKeys.contains(key)) {
      startedWrites++;
      if (startedWrites == BackupService.sectionSettingKeys.length) {
        allWritesStarted!.complete();
      }
      await pendingWrites!.future;
    }
    await writing;
  }
}

void main() {
  late Directory root;
  late _DelayedHiveCache cache;
  late _SettingsBloc settings;
  late _LibraryBloc library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup_mode_review_');
    AppPaths.debugOverrideDataRootPath(root.path);
    AppPaths.debugOverrideDocumentsRootPath(root.path);
    Hive.init(root.path);
    cache = _DelayedHiveCache();
    await Settings.init(cacheProvider: cache);
    DataRepository.instance.library = Future.value(Library(categories: []));
    final warmUp = await BackupService.createBackup(
      includeSettings: true,
      includeBookmarks: true,
      includeHistory: true,
      includeNotes: true,
      includeWorkspaces: true,
      includeShamorZachor: true,
      includePlugins: true,
    );
    await File(warmUp.path).delete();
    PackageInfo.setMockInitialValues(
      appName: 'Otzaria',
      packageName: 'org.otzaria',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    settings = _SettingsBloc();
    library = _LibraryBloc();
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    whenListen(
      library,
      const Stream<LibraryState>.empty(),
      initialState: const LibraryState(),
    );
  });

  tearDown(() async {
    await settings.close();
    await library.close();
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideDocumentsRootPath(null);
    await root.delete(recursive: true);
  });

  testWidgets(
    'הבורר והגיבוי מסתנכרנים עם שינויים בסעיפים מחלון אחר',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 8000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget tab() => MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<LibraryBloc>.value(value: library),
          ],
          child: const Scaffold(body: SystemSettingsTab()),
        ),
      );
      await tester.pumpWidget(tab());
      await tester.pump();
      final section = find.byWidgetPredicate(
        (w) => w is ExpandableSection && w.title == 'גיבוי אוטומטי',
      );
      tester.widget<ExpandableSection>(section).onTap();
      await tester.pump();
      final backupMode = find.byWidgetPredicate(
        (w) =>
            w is SegmentedButton &&
            w.segments.any(
              (s) => s.label is Text && (s.label as Text).data == 'גבה הכל',
            ),
      );
      expect(
        tester.widget<SegmentedButton>(backupMode).selected.single.toString(),
        endsWith('.all'),
      );
      await tester.runAsync(
        () => Settings.setValue<bool>('key-backup-history', false),
      );
      await tester.pump();
      expect(Settings.getValue<bool>('key-backup-history'), isFalse);
      expect(
        tester.widget<SegmentedButton>(backupMode).selected.single.toString(),
        endsWith('.custom'),
      );
      final createNow = find.byWidgetPredicate(
        (w) => w is ActionButton && w.text == 'צור כעת',
      );
      await tester.runAsync(() async {
        final dynamic callback = tester
            .widget<ActionButton>(createNow)
            .onPressed;
        await callback();
      });
      final files = await tester.runAsync(BackupService.getAvailableBackups);
      final manifest =
          jsonDecode(
                await tester.runAsync(
                      () => File(files!.single.path).readAsString(),
                    ) ??
                    '',
              )
              as Map;
      final shownMode = tester
          .widget<SegmentedButton>(backupMode)
          .selected
          .single
          .toString();
      expect(
        (manifest['includes'] as Map)['history'],
        shownMode.endsWith('.all') ||
            (Settings.getValue<bool>('key-backup-history') ?? true),
        reason: 'קובץ הגיבוי צריך לשקף את המצב המוצג: $shownMode',
      );

      for (final key in BackupService.sectionSettingKeys) {
        await tester.runAsync(() => Settings.setValue<bool>(key, false));
      }
      await tester.pump();
      for (final key in BackupService.sectionSettingKeys) {
        await tester.runAsync(() => Settings.setValue<bool>(key, true));
        await tester.pump();
        expect(
          tester.widget<SegmentedButton>(backupMode).selected.single.toString(),
          endsWith(BackupService.includesAllSections ? '.all' : '.custom'),
        );
      }

      final mode = tester.widget<SegmentedButton>(backupMode);
      final custom = mode.segments.last.value;
      final all = mode.segments.first.value;
      await tester.tap(
        find.descendant(of: backupMode, matching: find.text('מותאם אישית')),
      );
      await tester.pump();
      expect(BackupService.includesAllSections, isTrue);
      expect(
        tester.widget<SegmentedButton>(backupMode).selected.single,
        custom,
      );
      await tester.runAsync(
        () => Settings.setValue<bool>('key-backup-history', false),
      );
      await tester.pump();
      cache.pendingWrites = Completer<void>();
      cache.allWritesStarted = Completer<void>();
      await tester.runAsync(
        () => tester.tap(
          find.descendant(of: backupMode, matching: find.text('גבה הכל')),
        ),
      );
      await tester.runAsync(
        () =>
            cache.allWritesStarted!.future.timeout(const Duration(seconds: 5)),
      );
      await tester.pump();
      expect(BackupService.includesAllSections, isTrue);
      expect(tester.widget<SegmentedButton>(backupMode).selected.single, all);
      await tester.tap(
        find.descendant(of: backupMode, matching: find.text('מותאם אישית')),
      );
      await tester.pump();
      expect(
        tester.widget<SegmentedButton>(backupMode).selected.single,
        custom,
        reason: 'הבחירה המאוחרת מוצגת עוד לפני השלמת הכתיבות',
      );
      cache.pendingWrites!.complete();
      cache.pendingWrites = null;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(
        tester.widget<SegmentedButton>(backupMode).selected.single,
        custom,
      );
      expect(BackupService.includesAllSections, isTrue);
      await tester.runAsync(
        () => tester.tap(
          find.descendant(of: backupMode, matching: find.text('גבה הכל')),
        ),
      );
      await tester.pump();
      expect(tester.widget<SegmentedButton>(backupMode).selected.single, all);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Settings.setValue<bool>('key-backup-history', false),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
