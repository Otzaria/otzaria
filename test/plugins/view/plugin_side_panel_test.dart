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
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:mockito/mockito.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc({bool isOfflineMode = false})
      : super(SettingsState.initial().copyWith(isOfflineMode: isOfflineMode)) {
    on<SettingsEvent>((_, __) {});
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
}) {
  return InstalledPlugin(
    pluginId: id,
    name: name,
    version: '1.0.0',
    installPath: '/tmp/$id',
    entrypointPath: '/tmp/$id/index.html',
    enabled: true,
    pinned: true,
    manifest: _manifestFor(
      id: id,
      name: name,
      networkEnabled: networkEnabled,
    ),
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _StaticPluginSystemBloc
    extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  _StaticPluginSystemBloc(super.initial) {
    on<PluginSystemEvent>((_, __) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _wrap({
  required PluginSystemBloc pluginBloc,
  required SettingsBloc settingsBloc,
  bool showDevTools = true,
}) {
  return MaterialApp(
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
  }) async {
    return FilePickerResult([PlatformFile(path: fakeDirectoryPath, name: 'dir', size: 0)]);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
  }) async {
    return fakeDirectoryPath;
  }
}

class FakePluginRegistryRepository extends Mock implements PluginRegistryRepository {
  List<InstalledPlugin> plugins = [];
  
  @override
  Future<void> saveDevelopmentPlugin(InstalledPlugin plugin) async {
    plugins.add(plugin);
  }

  @override Future<List<InstalledPlugin>> getAllPlugins() async => plugins;
  @override Future<List<InstalledPlugin>> getDevelopmentPlugins() async => plugins;
  @override Future<InstalledPlugin?> getPlugin(String id) async => null;
  @override Future<bool?> getPermission(String id, String perm) async => true;
  @override Future<void> setPermission(String id, String perm, bool granted) async {}
  @override Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async => [];
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

  testWidgets('PluginSidePanel shows dev tools explicitly when flag is true', (WidgetTester tester) async {
    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);

    await tester.pumpWidget(_wrap(
      pluginBloc: bloc,
      settingsBloc: _FakeSettingsBloc(),
      showDevTools: true,
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsOneWidget);
  });

  testWidgets('PluginSidePanel hides dev tools explicitly when flag is false', (WidgetTester tester) async {
    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);

    await tester.pumpWidget(_wrap(
      pluginBloc: bloc,
      settingsBloc: _FakeSettingsBloc(),
      showDevTools: false,
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsNothing);
  });

  testWidgets('PluginSidePanel triggers picker and bloc on dev button tap', (WidgetTester tester) async {
    // Pre-cache package info to prevent method channel hang during widget test async pumped frames
    await PackageInfo.fromPlatform();

    final mockRepo = FakePluginRegistryRepository();
    final bloc = PluginSystemBloc(repository: mockRepo);

    final tempDir = Directory.systemTemp.createTempSync('otzaria_test_sidepanel');
    final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
    manifestFile.writeAsStringSync(jsonEncode({
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
      'publishedDataTypes': []
    }));
    File(p.join(tempDir.path, 'index.html')).createSync();

    // Use our custom Fake FilePicker instead of method channels
    FilePickerPlatform.instance = FakeFilePickerPlatform(tempDir.path);

    await tester.pumpWidget(_wrap(
      pluginBloc: bloc,
      settingsBloc: _FakeSettingsBloc(),
      showDevTools: true,
    ));
    await tester.pumpAndSettle();

    // Register the stream expectation BEFORE the action that triggers it.
    // emitsThrough allows intermediate states (e.g. PluginSystemLoading) before the target.
    final loadedExpectation = expectLater(
      bloc.stream,
      emitsThrough(isA<PluginSystemLoaded>()),
    );

    await tester.tap(find.byIcon(FluentIcons.folder_add_24_regular));
    await tester.pump();

    // The DevLoader uses real dart:io which needs real async — runAsync lets
    // the Dart event loop run freely while we wait for the stream to emit.
    await tester.runAsync(() => loadedExpectation);

    // Flush the UiSnack overlay timer so the test teardown doesn't complain.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));

    // Verify UI is still intact
    expect(find.byIcon(FluentIcons.folder_add_24_regular), findsOneWidget);

    // Deep verification: the repository received the correct plugin data
    expect(mockRepo.plugins.isNotEmpty, isTrue);
    expect(mockRepo.plugins.first.pluginId, 'test.ui.plugin');
    expect(mockRepo.plugins.first.name, 'UI Dev Plugin');
    expect(mockRepo.plugins.first.sourceType, 'development');

    tempDir.deleteSync(recursive: true);
  });

  group('סינון לפי מצב מנותק', () {
    testWidgets('במצב מקוון מציג גם תוספים שדורשים אינטרנט וגם שלא דורשים',
        (tester) async {
      final pluginBloc = _StaticPluginSystemBloc(PluginSystemLoaded([
        _pluginFor(id: 'local.plugin', name: 'תוסף מקומי'),
        _pluginFor(
            id: 'cloud.plugin', name: 'תוסף ענן', networkEnabled: true),
      ]));
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(_wrap(
        pluginBloc: pluginBloc,
        settingsBloc: _FakeSettingsBloc(isOfflineMode: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('תוסף מקומי'), findsOneWidget);
      expect(find.text('תוסף ענן'), findsOneWidget);
    });

    testWidgets('במצב מנותק מסתיר תוספים שדורשים אינטרנט',
        (tester) async {
      final pluginBloc = _StaticPluginSystemBloc(PluginSystemLoaded([
        _pluginFor(id: 'local.plugin', name: 'תוסף מקומי'),
        _pluginFor(
            id: 'cloud.plugin', name: 'תוסף ענן', networkEnabled: true),
      ]));
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(_wrap(
        pluginBloc: pluginBloc,
        settingsBloc: _FakeSettingsBloc(isOfflineMode: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('תוסף מקומי'), findsOneWidget);
      expect(find.text('תוסף ענן'), findsNothing);
    });

    testWidgets(
        'במצב מנותק כשכל התוספים דורשים אינטרנט - מציג הודעת empty state ייעודית',
        (tester) async {
      final pluginBloc = _StaticPluginSystemBloc(PluginSystemLoaded([
        _pluginFor(
            id: 'cloud.plugin', name: 'תוסף ענן', networkEnabled: true),
      ]));
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(_wrap(
        pluginBloc: pluginBloc,
        settingsBloc: _FakeSettingsBloc(isOfflineMode: true),
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('הוסתרו במצב מנותק'),
        findsOneWidget,
      );
    });

    testWidgets(
        'כשאין תוספים מותקנים - מציג הודעת empty state רגילה גם במצב מנותק',
        (tester) async {
      final pluginBloc =
          _StaticPluginSystemBloc(const PluginSystemLoaded([]));
      addTearDown(pluginBloc.close);

      await tester.pumpWidget(_wrap(
        pluginBloc: pluginBloc,
        settingsBloc: _FakeSettingsBloc(isOfflineMode: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('לא הותקנו תוספים'), findsOneWidget);
    });
  });

  group('OfflineModePluginFilter extension', () {
    test('במצב מקוון מחזיר את הרשימה ללא שינוי', () {
      final plugins = [
        _pluginFor(id: 'a', name: 'A'),
        _pluginFor(id: 'b', name: 'B', networkEnabled: true),
      ];
      expect(plugins.filterForOfflineMode(false), equals(plugins));
    });

    test('במצב מנותק מסנן רק תוספים עם networkEnabled=true', () {
      final local = _pluginFor(id: 'a', name: 'A');
      final cloud =
          _pluginFor(id: 'b', name: 'B', networkEnabled: true);
      final filtered = [local, cloud].filterForOfflineMode(true);
      expect(filtered, [local]);
    });

    test('רשימה ריקה מוחזרת כרשימה ריקה', () {
      expect(<InstalledPlugin>[].filterForOfflineMode(true), isEmpty);
      expect(<InstalledPlugin>[].filterForOfflineMode(false), isEmpty);
    });
  });

  group('InstalledPlugin.requiresNetwork', () {
    test('מחזיר true כאשר manifest.networkEnabled=true', () {
      final plugin =
          _pluginFor(id: 'a', name: 'A', networkEnabled: true);
      expect(plugin.requiresNetwork, isTrue);
    });

    test('מחזיר false כאשר manifest.networkEnabled=false', () {
      final plugin = _pluginFor(id: 'a', name: 'A');
      expect(plugin.requiresNetwork, isFalse);
    });
  });
}
