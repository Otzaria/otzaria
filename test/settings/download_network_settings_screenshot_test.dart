import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:ui' as ui;
import '../support/golden_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadGoldenFonts();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
  });
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
        softwareAndBookUpdatesEnabled: false,
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

  testWidgets('צילום מסך הגדרות הרשת האמיתי באנדרואיד', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(420, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('he', 'IL'),
            supportedLocales: const [Locale('he', 'IL')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppThemeData.light(
              AppThemeData.createColorScheme(
                AppSeedColors.defaultLight,
                Brightness.light,
              ),
              compactMenuMode: false,
            ),
            home: MultiBlocProvider(
              providers: [
                BlocProvider<SettingsBloc>.value(value: settings),
                BlocProvider<LibraryBloc>.value(value: library),
              ],
              child: const Scaffold(body: SystemSettingsTab()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final updates = find.text('עדכוני מערכת');
      await Scrollable.ensureVisible(tester.element(updates), alignment: 0.02);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(updates).dy, inInclusiveRange(0, 24));
      expect(
        find.text('רשת להורדת קבצים'),
        const bool.fromEnvironment('ISSUE4096_AFTER', defaultValue: true)
            ? findsOneWidget
            : findsNothing,
      );
      expect(tester.takeException(), isNull);
      const output = String.fromEnvironment('ISSUE4096_SCREENSHOT');
      if (output.isNotEmpty) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(output);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
