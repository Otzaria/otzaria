import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/data/data_providers/shared_preferences_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_index.g.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/settings/tabs/system_settings_tab.dart';
import 'package:otzaria/settings/widgets/expandable_settings_tile.dart';
import 'package:otzaria/widgets/controls/custom_switch.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

void main() {
  late Directory root;
  late SettingsBloc settings;
  late _LibraryBloc library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup_search_');
    AppPaths.debugOverrideDataRootPath(root.path);
    AppPaths.debugOverrideDocumentsRootPath(root.path);
    UserStateDatabase.instance.overridePath(p.join(root.path, 'user_state.db'));
    PluginSystemDatabase.instance.resetForTests();
    Hive.init(root.path);
    await Settings.init(cacheProvider: HiveCache());
    DataRepository.instance.library = Future.value(Library(categories: []));
    final backup = await BackupService.createBackup(
      includeSettings: true,
      includeBookmarks: true,
      includeHistory: true,
      includeNotes: true,
      includeWorkspaces: true,
      includeShamorZachor: true,
      includePlugins: true,
    );
    await File(backup.path).delete();
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
      initialState: SettingsState.initial().copyWith(
        settingsLanguageCode: 'he',
      ),
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
    await AttachedLibraryRegistry.instance.reset();
    PluginSystemDatabase.instance.resetForTests();
    await UserStateDatabase.instance.flushWrites();
    UserStateDatabase.instance.close();
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideDocumentsRootPath(null);
    await root.delete(recursive: true);
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<LibraryBloc>.value(value: library),
          ],
          child: const Scaffold(body: SystemSettingsTab()),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> navigate(WidgetTester tester, String id) async {
    final entry = kGeneratedSettingsSearchEntries.singleWhere(
      (entry) => entry.id == id,
    );
    final navigation = SettingsSearchRegistry.instance.scrollAndHighlight(
      entry.cardId!,
      section: entry.expandSection,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    await navigation;
  }

  Finder backupSection() => find.byWidgetPredicate(
    (widget) => widget is ExpandableSection && widget.title == 'גיבוי אוטומטי',
  );

  Future<void> startBackupNavigation(
    WidgetTester tester, {
    required bool Function() isCurrent,
  }) async {
    final navigation = SettingsSearchRegistry.instance.scrollAndHighlight(
      'system.advanced',
      section: 'backup.options.notes',
      isCurrent: isCurrent,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await navigation;
    expect(
      tester.widget<ExpandableSection>(backupSection()).isExpanded,
      isTrue,
      reason: 'הבדיקה צריכה להגיע להמתנה שאחרי פתיחת הגיבוי',
    );
  }

  ScrollPosition scrollPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(SystemSettingsTab),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  testWidgets('בקשת גיבוי שבוטלה לפני הפתיחה משאירה את האזור מקופל', (
    tester,
  ) async {
    await pumpTab(tester);
    var current = true;
    final navigation = SettingsSearchRegistry.instance.scrollAndHighlight(
      'system.advanced',
      section: 'backup.options.notes',
      isCurrent: () => current,
    );
    await tester.pump();
    expect(scrollPosition(tester).isScrollingNotifier.value, isTrue);
    current = false;
    await tester.pumpAndSettle();
    await navigation;
    expect(
      tester.widget<ExpandableSection>(backupSection()).isExpanded,
      isFalse,
    );
  });

  testWidgets('ביטול בזמן פתיחת הגיבוי מונע גלילה פנימית מאוחרת', (
    tester,
  ) async {
    await pumpTab(tester);
    var current = true;
    await startBackupNavigation(tester, isCurrent: () => current);
    final position = scrollPosition(tester);
    final before = position.pixels;
    current = false;
    await tester.pumpAndSettle();
    expect(position.pixels, before);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'גלילה פנימית בגיבוי ${cancel ? 'שבוטלה אינה' : 'פעילה'} מהבהבת',
      (
        tester,
      ) async {
        await pumpTab(tester);
        final stored = Map<dynamic, dynamic>.from(
          Hive.box<dynamic>(HiveCache.keyName).toMap(),
        );
        var current = true;
        var flashes = 0;
        final notifier = SettingsSearchRegistry.instance.flashNotifierFor(
          'system.backup.options.notes',
        );
        void onFlash() {
          if (notifier.value) flashes++;
        }

        notifier.addListener(onFlash);
        addTearDown(() => notifier.removeListener(onFlash));
        await startBackupNavigation(tester, isCurrent: () => current);
        await tester.pump(const Duration(milliseconds: 125));
        await tester.pump(const Duration(milliseconds: 125));
        await tester.pump();
        final position = scrollPosition(tester);
        expect(position.isScrollingNotifier.value, isTrue);
        final before = position.pixels;
        await tester.pump(const Duration(milliseconds: 40));
        expect(position.pixels, greaterThan(before));
        expect(flashes, 0);
        if (cancel) current = false;
        await tester.pumpAndSettle();
        expect(flashes, cancel ? 0 : 1);
        expect(Hive.box<dynamic>(HiveCache.keyName).toMap(), stored);
      },
    );
  }

  testWidgets('יעד חדש בזמן פתיחת הגיבוי נשאר יעד הגלילה האחרון', (
    tester,
  ) async {
    await pumpTab(tester);
    var current = true;
    await startBackupNavigation(tester, isCurrent: () => current);
    current = false;
    final replacement = SettingsSearchRegistry.instance.scrollAndHighlight(
      'system.versions',
    );
    await tester.pumpAndSettle();
    await replacement;
    final target = find.byWidgetPredicate(
      (widget) =>
          widget is SettingsAnchor && widget.cardId == 'system.versions',
    );
    expect(tester.getRect(target).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(target).bottom, lessThanOrEqualTo(800));
  });

  for (final duringScroll in [false, true]) {
    testWidgets(
      'הסרת הלשונית בזמן ${duringScroll ? 'גלילת' : 'פתיחת'} גיבוי בטוחה',
      (
        tester,
      ) async {
        await pumpTab(tester);
        await startBackupNavigation(tester, isCurrent: () => true);
        if (duringScroll) {
          await tester.pump(const Duration(milliseconds: 125));
          await tester.pump(const Duration(milliseconds: 125));
          await tester.pump();
          expect(scrollPosition(tester).isScrollingNotifier.value, isTrue);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final option in [
    'settings',
    'bookmarks',
    'history',
    'notes',
    'workspaces',
    'shamor_zachor',
  ]) {
    testWidgets('חיפוש סעיף $option חושף אותו בלי לשנות את בחירת הגיבוי', (
      tester,
    ) async {
      await pumpTab(tester);
      final stored = Map<dynamic, dynamic>.from(
        Hive.box<dynamic>(HiveCache.keyName).toMap(),
      );
      expect(
        tester.widget<ExpandableSection>(backupSection()).isExpanded,
        isFalse,
      );

      await navigate(tester, 'system.advanced.backup.$option');

      expect(
        tester.widget<ExpandableSection>(backupSection()).isExpanded,
        isTrue,
      );
      final target = find.byWidgetPredicate(
        (widget) =>
            widget is SettingsAnchor &&
            widget.cardId == 'system.backup.options.$option',
      );
      expect(target, findsOneWidget);
      final rect = tester.getRect(target);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(800));
      expect(Hive.box<dynamic>(HiveCache.keyName).toMap(), stored);
      expect(BackupService.includesAllSections, isTrue);
    });
  }

  testWidgets('ניווט לניקוי גיבויים פותח את האזור ושומר את מצב גבה הכל', (
    tester,
  ) async {
    await pumpTab(tester);
    await navigate(tester, 'system.advanced.backup.retention');

    expect(
      tester.widget<ExpandableSection>(backupSection()).isExpanded,
      isTrue,
    );
    final mode = find.byWidgetPredicate(
      (widget) =>
          widget is SegmentedButton &&
          widget.segments.any(
            (segment) =>
                segment.label is Text &&
                (segment.label as Text).data == 'גבה הכל',
          ),
    );
    expect(
      tester.widget<SegmentedButton>(mode).selected.single.toString(),
      endsWith('.all'),
    );
    final target = find.byWidgetPredicate(
      (widget) =>
          widget is SettingsAnchor &&
          widget.cardId == 'system.backup.retention',
    );
    expect(target, findsOneWidget);
    expect(tester.getRect(target).bottom, lessThanOrEqualTo(800));
  });

  testWidgets('תוצאה שאינה שייכת לגיבוי משאירה את האזור מקופל', (tester) async {
    await pumpTab(tester);
    await navigate(tester, 'system.advanced.cypher');
    expect(
      tester.widget<ExpandableSection>(backupSection()).isExpanded,
      isFalse,
    );
  });

  testWidgets('לשונית הגיבוי ובחירת הסעיפים עובדות ללא Hive פתוח', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await settings.close();
      await Hive.close();
      SharedPreferences.setMockInitialValues({
        SettingsRepository.keySettingsLanguage: 'he',
      });
      await Settings.init(cacheProvider: SharePreferenceCache());
    });
    final repository = SettingsRepository();
    settings = SettingsBloc(
      repository: repository,
      initialSettings: repository.readSettings(),
      ensureFontLoaded: (_) async {},
    );
    await pumpTab(tester);
    await navigate(tester, 'system.advanced.backup.notes');

    final target = find.byWidgetPredicate(
      (widget) =>
          widget is SettingsAnchor &&
          widget.cardId == 'system.backup.options.notes',
    );
    final toggle = find.descendant(
      of: target,
      matching: find.byType(CustomSwitch),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(Settings.getValue<bool>('key-backup-notes'), isFalse);
    expect(BackupService.includesAllSections, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(Settings.getValue<bool>('key-backup-notes'), isTrue);
    expect(BackupService.includesAllSections, isTrue);
    expect(target, findsNothing);
    expect(Hive.isBoxOpen(HiveCache.keyName), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
