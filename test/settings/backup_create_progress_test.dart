// "צור כעת" מציג התקדמות ומושבת בזמן ההרצה, ולחיצה כפולה לא יוצרת שני
// גיבויים במקביל.
import 'dart:async';
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
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/settings/tabs/system_settings_tab.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

void main() {
  late Directory root;
  late SettingsBloc settings;
  late _LibraryBloc library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('backup_create_progress_');
    AppPaths.debugOverrideDataRootPath(root.path);
    AppPaths.debugOverrideDocumentsRootPath(root.path);
    UserStateDatabase.instance.overridePath(p.join(root.path, 'user_state.db'));
    PluginSystemDatabase.instance.resetForTests();
    Hive.init(root.path);
    await Settings.init(cacheProvider: HiveCache());
    DataRepository.instance.library = Future.value(Library(categories: []));
    // חימום מחוץ ל-FakeAsync של testWidgets: האתחול העצל הראשון של הגיבוי
    // (מסדי נתונים, ספקי ספרייה) נתקע בתוכו.
    final warmup = await BackupService.createBackup(
      includeSettings: true,
      includeBookmarks: true,
      includeHistory: true,
      includeNotes: true,
      includeWorkspaces: true,
      includeShamorZachor: true,
      includePlugins: true,
    );
    await File(warmup.path).delete();
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
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Windows: קובץ מסד נתונים של ספק הספרייה עדיין פתוח; תיקיית temp בלבד.
    }
  });

  Finder createButton() => find.byWidgetPredicate(
    (widget) => widget is ActionButton && widget.text == 'צור כעת',
  );

  testWidgets('לחיצה כפולה על "צור כעת" יוצרת גיבוי אחד ומציגה התקדמות', (
    tester,
  ) async {
    var started = 0;
    final gate = Completer<void>();
    BackupService.debugBeforeCreateBackup = () async {
      started++;
      await gate.future;
      throw StateError('הבדיקה עוצרת כאן');
    };
    addTearDown(() => BackupService.debugBeforeCreateBackup = null);
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
    await tester.ensureVisible(createButton());
    await tester.pump();

    await tester.tap(createButton());
    await tester.pump();

    // היצירה רצה: הכפתור מציג התקדמות ואינו לחיץ.
    expect(
      find.byWidgetPredicate((w) => w is ActionButton && w.isLoading),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ActionButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byWidgetPredicate((w) => w is ActionButton && w.isLoading),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(started, 1, reason: 'לחיצה שנייה בזמן הריצה לא מתחילה גיבוי נוסף');

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<ActionButton>(createButton()).isLoading,
      isFalse,
      reason: 'אחרי הסיום (גם בשגיאה) הכפתור חוזר להיות פעיל',
    );
  });
}
