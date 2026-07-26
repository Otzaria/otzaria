import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/view/plugin_side_panel.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mockito/mockito.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  @override
  bool hasProtectedModePassword() => false;
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc({bool isOfflineMode = false})
    : super(SettingsState.initial().copyWith(isOfflineMode: isOfflineMode)) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PluginManifest _manifestFor({
  required String id,
  required String name,
  bool networkEnabled = false,
}) {
  return PluginManifest(
    schemaVersion: 1,
    id: id,
    name: name,
    version: '1.0.0',
    description: 'test',
    author: 'tester',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: networkEnabled,
    networkAllowlist: const [],
    toolTabTitle: name,
    toolTabOrder: 100,
    defaultPinned: true,
    publishedDataTypes: const [],
  );
}

InstalledPlugin _pluginFor({
  required String id,
  required String name,
  bool networkEnabled = false,
  bool networkAccessGranted = false,
  bool showInTools = true,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: name,
    version: '1.0.0',
    installPath: '/tmp/$id',
    entrypointPath: '/tmp/$id/index.html',
    enabled: true,
    pinned: true,
    showInTools: showInTools,
    networkAccessGranted: networkAccessGranted,
    manifest: _manifestFor(
      id: id,
      name: name,
      networkEnabled: networkEnabled,
    ),
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _StaticPluginSystemBloc extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  _StaticPluginSystemBloc(super.initial) {
    on<PluginSystemEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// כמו [_StaticPluginSystemBloc] אך מתעד את האירועים שנשלחו, לאימות פעולות.
class _RecordingPluginSystemBloc
    extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  final List<PluginSystemEvent> recorded = [];
  _RecordingPluginSystemBloc(super.initial) {
    on<PluginSystemEvent>((event, _) => recorded.add(event));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _wrap({
  required PluginSystemBloc pluginBloc,
  required SettingsBloc settingsBloc,
  bool showDevTools = true,
}) {
  return Provider<SettingsRepository>.value(
    value: _FakeSettingsRepository(),
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: PluginSidePanel(showDevTools: showDevTools),
        ),
      ),
    ),
  );
}

// Mock FilePicker platform to avoid MissingPluginException and LateInitializationError.
class FakeFilePickerPlatform extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  final String fakeDirectoryPath;
  FakeFilePickerPlatform(this.fakeDirectoryPath);

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    return FilePickerResult([
      PlatformFile(path: fakeDirectoryPath, name: 'dir', size: 0),
    ]);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    return fakeDirectoryPath;
  }
}

class FakePluginRegistryRepository extends Mock
    implements PluginRegistryRepository {
  List<InstalledPlugin> plugins = [];

  @override
  Future<void> saveDevelopmentPlugin(InstalledPlugin plugin) async {
    plugins.add(plugin);
  }

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => plugins;
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => plugins;
  @override
  Future<InstalledPlugin?> getPlugin(String id) async => null;
  @override
  Future<bool?> getPermission(String id, String perm) async => true;
  @override
  Future<void> setPermission(String id, String perm, bool granted) async {}
  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];
  @override
  Future<int?> getNextUserOrderForNewPlugin() async => null;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'Otzaria',
      packageName: 'com.otzaria.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('PluginSidePanel shows dev tools explicitly when flag is true', (
    WidgetTester tester,
  ) async {
    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);

    await tester.pumpWidget(
      _wrap(
        pluginBloc: bloc,
        settingsBloc: _FakeSettingsBloc(),
        showDevTools: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsOneWidget);
  });

  testWidgets('PluginSidePanel hides dev tools explicitly when flag is false', (
    WidgetTester tester,
  ) async {
    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);

    await tester.pumpWidget(
      _wrap(
        pluginBloc: bloc,
        settingsBloc: _FakeSettingsBloc(),
        showDevTools: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsNothing);
  });

  testWidgets('PluginSidePanel triggers picker and bloc on dev button tap', (
    WidgetTester tester,
  ) async {
    // Pre-cache package info to prevent method channel hang during widget test async pumped frames
    await PackageInfo.fromPlatform();

    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);

    final tempDir = Directory.systemTemp.createTempSync(
      'otzaria_test_sidepanel',
    );
    final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
    manifestFile.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'id': 'test.ui.plugin',
        'version': '1.0.0',
        'name': 'UI Dev Plugin',
        'entrypoint': 'index.html',
        'permissions': [],
        'minAppVersion': '1.0.0',
        'description': 'test',
        'author': 'tester',
        'homepage': 'https://test.com',
        'sdkVersion': '1.0.0',
        'networkEnabled': false,
        'networkAllowlist': [],
        'toolTabTitle': 'Tab',
        'toolTabOrder': 0,
        'publishedDataTypes': [],
      }),
    );
    File(p.join(tempDir.path, 'index.html')).createSync();

    FilePickerPlatform.instance = FakeFilePickerPlatform(tempDir.path);

    await tester.pumpWidget(
      _wrap(
        pluginBloc: bloc,
        settingsBloc: _FakeSettingsBloc(),
        showDevTools: true,
      ),
    );
    await tester.pumpAndSettle();

    // Step 1: Tapping folder_add → expects PluginSystemDevInstallRequiresPermissions
    // (first install always shows the permissions dialog; PluginSystemLoaded
    // is only emitted after the user confirms).
    final permExpectation = expectLater(
      bloc.stream,
      emitsThrough(isA<PluginSystemDevInstallRequiresPermissions>()),
    );

    await tester.tap(find.byIcon(FluentIcons.folder_add_24_regular));
    await tester.pump();

    await tester.runAsync(() => permExpectation);

    // Step 2: Simulate dialog confirmation — dispatch ConfirmDevPluginInstall
    // with the manifest the BLoC already fetched and stored in the state.
    final permState = bloc.state as PluginSystemDevInstallRequiresPermissions;

    final loadedExpectation = expectLater(
      bloc.stream,
      emitsThrough(isA<PluginSystemLoaded>()),
    );

    bloc.add(
      ConfirmDevPluginInstall(
        manifest: permState.manifest,
        sourcePath: permState.sourcePath,
        sourceType: permState.sourceType,
        grantedPermissions: const {},
        allowOrderBeforeBuiltInsGranted: false,
      ),
    );

    await tester.runAsync(() => loadedExpectation);

    // Flush the UiSnack overlay timer so the test teardown doesn't complain.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));

    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsOneWidget);

    // Deep verification: the repository received the correct plugin data.
    expect(mockRepo.plugins.isNotEmpty, isTrue);
    expect(mockRepo.plugins.first.pluginId, 'test.ui.plugin');
    expect(mockRepo.plugins.first.name, 'UI Dev Plugin');
    expect(mockRepo.plugins.first.sourceType, 'development');

    tempDir.deleteSync(recursive: true);
  });

  group('סינון לפי מצב מנותק', () {
    testWidgets('במצב מקוון מציג גם תוספים שדורשים אינטרנט וגם שלא דורשים', (
      tester,
    ) async {
      final pluginBloc = _StaticPluginSystemBloc(
        PluginSystemLoaded([
          _pluginFor(id: 'local.plugin', name: 'תוסף מקומי'),
          _pluginFor(
            id: 'cloud.plugin',
            name: 'תוסף ענן',
            networkEnabled: true,
          ),
        ]),
      );
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(
        _wrap(
          pluginBloc: pluginBloc,
          settingsBloc: _FakeSettingsBloc(isOfflineMode: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('תוסף מקומי'), findsOneWidget);
      expect(find.text('תוסף ענן'), findsOneWidget);
    });

    testWidgets('במצב מנותק מסתיר תוספים שדורשים אינטרנט והרשאתם דלוקה', (
      tester,
    ) async {
      final pluginBloc = _StaticPluginSystemBloc(
        PluginSystemLoaded([
          _pluginFor(id: 'local.plugin', name: 'תוסף מקומי'),
          _pluginFor(
            id: 'cloud.plugin',
            name: 'תוסף ענן',
            networkEnabled: true,
            networkAccessGranted: true,
          ),
        ]),
      );
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(
        _wrap(
          pluginBloc: pluginBloc,
          settingsBloc: _FakeSettingsBloc(isOfflineMode: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('תוסף מקומי'), findsOneWidget);
      expect(find.text('תוסף ענן'), findsNothing);
    });

    testWidgets(
      'במצב מנותק תוסף רשת שהמשתמש כיבה בו את הרשאת הרשת ממשיך להופיע',
      (tester) async {
        final pluginBloc = _StaticPluginSystemBloc(
          PluginSystemLoaded([
            _pluginFor(
              id: 'cloud.plugin',
              name: 'תוסף ענן',
              networkEnabled: true,
              networkAccessGranted: false,
            ),
          ]),
        );
        addTearDown(pluginBloc.close);

        await tester.pumpWidget(
          _wrap(
            pluginBloc: pluginBloc,
            settingsBloc: _FakeSettingsBloc(isOfflineMode: true),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('תוסף ענן'), findsOneWidget);
      },
    );

    testWidgets(
      'במצב מנותק כשכל התוספים דורשים אינטרנט - מציג הודעת empty state ייעודית',
      (tester) async {
        final pluginBloc = _StaticPluginSystemBloc(
          PluginSystemLoaded([
            _pluginFor(
              id: 'cloud.plugin',
              name: 'תוסף ענן',
              networkEnabled: true,
              networkAccessGranted: true,
            ),
          ]),
        );
        addTearDown(pluginBloc.close);

        await tester.pumpWidget(
          _wrap(
            pluginBloc: pluginBloc,
            settingsBloc: _FakeSettingsBloc(isOfflineMode: true),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('הוסתרו במצב מנותק'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'כשאין תוספים מותקנים - מציג הודעת empty state רגילה גם במצב מנותק',
      (tester) async {
        final pluginBloc = _StaticPluginSystemBloc(
          const PluginSystemLoaded([]),
        );
        addTearDown(pluginBloc.close);

        await tester.pumpWidget(
          _wrap(
            pluginBloc: pluginBloc,
            settingsBloc: _FakeSettingsBloc(isOfflineMode: true),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('לא הותקנו תוספים'), findsOneWidget);
      },
    );
  });

  group('showInTools — פאנל הצד מציג את כל התוספים הפעילים', () {
    testWidgets(
      'תוסף עם showInTools=false עדיין מופיע בפאנל הצד כי ה-side panel מציג הכל',
      (tester) async {
        final pluginBloc = _StaticPluginSystemBloc(
          PluginSystemLoaded([
            _pluginFor(id: 'visible.plugin', name: 'תוסף גלוי'),
            _pluginFor(
              id: 'hidden.plugin',
              name: 'תוסף לא בכלים',
              showInTools: false,
            ),
          ]),
        );
        addTearDown(pluginBloc.close);

        await tester.pumpWidget(
          _wrap(
            pluginBloc: pluginBloc,
            settingsBloc: _FakeSettingsBloc(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('תוסף גלוי'), findsOneWidget);
        expect(
          find.text('תוסף לא בכלים'),
          findsOneWidget,
          reason:
              'showInTools only hides from tools screen, not from side panel',
        );
      },
    );
  });

  group('OfflineModePluginFilter extension', () {
    test('במצב מקוון מחזיר את הרשימה ללא שינוי', () {
      final plugins = [
        _pluginFor(id: 'a', name: 'A'),
        _pluginFor(id: 'b', name: 'B', networkEnabled: true),
      ];
      expect(plugins.filterForOfflineMode(false), equals(plugins));
    });

    test('במצב מנותק מסנן רק תוספי רשת שהרשאתם הוענקה בפועל', () {
      final local = _pluginFor(id: 'a', name: 'A');
      final cloud = _pluginFor(
        id: 'b',
        name: 'B',
        networkEnabled: true,
        networkAccessGranted: true,
      );
      final filtered = [local, cloud].filterForOfflineMode(true);
      expect(filtered, [local]);
    });

    test('במצב מנותק תוסף רשת ללא הרשאת רשת מוענקת אינו מסונן', () {
      final local = _pluginFor(id: 'a', name: 'A');
      final cloudRevoked = _pluginFor(
        id: 'b',
        name: 'B',
        networkEnabled: true,
        networkAccessGranted: false,
      );
      final filtered = [local, cloudRevoked].filterForOfflineMode(true);
      expect(filtered, [local, cloudRevoked]);
    });

    test('רשימה ריקה מוחזרת כרשימה ריקה', () {
      expect(<InstalledPlugin>[].filterForOfflineMode(true), isEmpty);
      expect(<InstalledPlugin>[].filterForOfflineMode(false), isEmpty);
    });
  });

  group('InstalledPlugin.requiresNetwork', () {
    test('מחזיר true כאשר manifest.networkEnabled=true', () {
      final plugin = _pluginFor(id: 'a', name: 'A', networkEnabled: true);
      expect(plugin.requiresNetwork, isTrue);
    });

    test('מחזיר false כאשר manifest.networkEnabled=false', () {
      final plugin = _pluginFor(id: 'a', name: 'A');
      expect(plugin.requiresNetwork, isFalse);
    });
  });

  group('InstalledPlugin.blockedInOfflineMode', () {
    test('true כשהתוסף דורש רשת והרשאתו הוענקה', () {
      final plugin = _pluginFor(
        id: 'a',
        name: 'A',
        networkEnabled: true,
        networkAccessGranted: true,
      );
      expect(plugin.blockedInOfflineMode, isTrue);
    });

    test('false כשהתוסף דורש רשת אך הרשאתו כובתה — חייב להיפתח במנותק', () {
      final plugin = _pluginFor(
        id: 'a',
        name: 'A',
        networkEnabled: true,
        networkAccessGranted: false,
      );
      expect(plugin.blockedInOfflineMode, isFalse);
    });

    test('false כשהתוסף אינו דורש רשת כלל', () {
      final plugin = _pluginFor(id: 'a', name: 'A');
      expect(plugin.blockedInOfflineMode, isFalse);
    });
  });

  group('תפריט פעולות', () {
    testWidgets('פתיחת התפריט מציגה את כל הפעולות', (tester) async {
      final pluginBloc = _StaticPluginSystemBloc(
        PluginSystemLoaded([_pluginFor(id: 'a', name: 'תוסף א')]),
      );
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(
        _wrap(
          pluginBloc: pluginBloc,
          settingsBloc: _FakeSettingsBloc(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('פעולות'));
      await tester.pumpAndSettle();

      expect(find.text('ניהול הרשאות'), findsOneWidget);
      expect(find.text('הצמד לסרגל הניווט'), findsOneWidget);
      expect(find.text('הסתר מהממשק'), findsOneWidget);
      expect(find.text('השבת'), findsOneWidget);
      expect(find.text('מחק תוסף'), findsOneWidget);
    });

    testWidgets('לחיצה על "השבת" שולחת DisablePluginRequested', (tester) async {
      final pluginBloc = _RecordingPluginSystemBloc(
        PluginSystemLoaded([_pluginFor(id: 'a', name: 'תוסף א')]),
      );
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(
        _wrap(
          pluginBloc: pluginBloc,
          settingsBloc: _FakeSettingsBloc(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('פעולות'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('השבת'));
      await tester.pumpAndSettle();

      expect(
        pluginBloc.recorded.whereType<DisablePluginRequested>().single.pluginId,
        'a',
      );
    });

    testWidgets('נפתח כלפי מעלה ליד תחתית המסך ולא נחתך', (tester) async {
      tester.view.physicalSize = const Size(420, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final pluginBloc = _StaticPluginSystemBloc(
        PluginSystemLoaded([
          _pluginFor(id: 'a', name: 'תוסף א'),
          _pluginFor(id: 'b', name: 'תוסף ב'),
          _pluginFor(id: 'c', name: 'תוסף ג'),
        ]),
      );
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(
        _wrap(
          pluginBloc: pluginBloc,
          settingsBloc: _FakeSettingsBloc(),
        ),
      );
      await tester.pumpAndSettle();

      final actionButton = find.text('פעולות').last;
      final buttonTop = tester.getTopLeft(actionButton).dy;

      await tester.tap(actionButton);
      await tester.pumpAndSettle();

      final firstItemTop = tester.getTopLeft(find.text('ניהול הרשאות')).dy;
      final lastItemBottom = tester.getBottomLeft(find.text('מחק תוסף')).dy;

      expect(firstItemTop, greaterThanOrEqualTo(0));
      expect(firstItemTop, lessThan(buttonTop));
      expect(lastItemBottom, lessThanOrEqualTo(320));
    });
  });

  group('Reorder UI', () {
    testWidgets('mounting inside a LayoutBuilder ancestor does not crash — '
        'regression for the _RenderLayoutBuilder mutation assert and the '
        '_retakeInactiveElement assert that fired when ReorderableListView '
        'tried to use a root OverlayPortal through outer LayoutBuilders', (
      tester,
    ) async {
      final pluginBloc = _StaticPluginSystemBloc(
        PluginSystemLoaded([
          _pluginFor(id: 'a', name: 'A'),
          _pluginFor(id: 'b', name: 'B'),
          _pluginFor(id: 'c', name: 'C'),
        ]),
      );
      addTearDown(pluginBloc.close);

      // מדמים את המסגרת האמיתית בה הפאנל נמצא ב-ToolsScreen: עטוף
      // ב-LayoutBuilder (FloatingPanel/ContextOverlayPanel) ובלי Material
      // ישיר. אם הקריסה תחזור — היא תתפוס פה לפני שתגיע למשתמש.
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: LayoutBuilder(
              builder: (ctx, constraints) => SizedBox(
                width: 400,
                height: constraints.maxHeight,
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
                    BlocProvider<SettingsBloc>.value(
                      value: _FakeSettingsBloc(),
                    ),
                  ],
                  child: const PluginSidePanel(showDevTools: false),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // הפאנל נטען בהצלחה והרשימה רנדרה — אין FlutterError ב-tester.
      expect(tester.takeException(), isNull);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });
  });
}
