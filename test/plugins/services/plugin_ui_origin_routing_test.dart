import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';

class _Repo extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;
  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      null;
  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {}
}

class _Controller extends Fake implements InAppWebViewController {
  final sources = <String>[];
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async {}
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => sources.add(source);
}

class _Window extends Fake implements AppWindowController, AppWindowGeometry {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dispatcher = PluginRuntimeDispatcher.instance;
  final launcher = PluginPageLauncher.instance;
  late AppWindowKeys aKeys;
  late AppWindowKeys bKeys;

  setUp(() async {
    await dispatcher.prepareForAppRestart();
    dispatcher.registerController('__reset', _Controller());
    dispatcher.unregisterController('__reset');
    dispatcher.repositoryForTesting = _Repo();
    aKeys = AppWindowKeys(id: const AppWindowId('a'));
    bKeys = AppWindowKeys(id: const AppWindowId('b'));
    AppWindowKeys.register(aKeys);
    AppWindowKeys.register(bKeys);
    AppWindowKeys.activate(aKeys);
  });

  tearDown(() async {
    await dispatcher.prepareForAppRestart();
    dispatcher.repositoryForTesting = PluginRegistryRepository();
    launcher.forgetWindow(0);
    launcher.forgetWindow(1);
    AppWindowKeys.resetForTest();
  });

  testWidgets('כפתור בשדה B פונה למופע B ושומר אותו עד סגירת הסשן', (
    tester,
  ) async {
    const pluginId = 'origin.voice';
    final a = _Controller();
    final b = _Controller();
    dispatcher.registerController(pluginId, a, instanceId: 'a', viewId: 1);
    dispatcher.registerController(pluginId, b, instanceId: 'b', viewId: 0);
    dispatcher.setVisiblePluginInstances({
      (pluginId: pluginId, instanceId: 'a'),
    }, viewId: 1);
    dispatcher.setVisiblePluginInstances({
      (pluginId: pluginId, instanceId: 'b'),
    }, viewId: 0);
    final registry = PluginSearchFieldActionsRegistry.forTesting()
      ..registerPayload(pluginId, {'id': 'dictate', 'title': 'חיפוש בדיבור'});
    final sessions = PluginSearchFieldSessionService.instance;
    final text = TextEditingController();
    final window = _Window();
    addTearDown(text.dispose);
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      AppWindowScope(
        controller: window,
        geometry: window,
        keys: bKeys,
        child: MaterialApp(
          home: Scaffold(
            body: PluginSearchFieldActions(
              field: PluginSearchField.library,
              controller: text,
              registry: registry,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('חיפוש בדיבור'));
    await tester.pump();
    expect(a.sources.where((s) => s.contains('search.fieldAction.')), isEmpty);
    expect(
      b.sources.where((s) => s.contains('search.fieldAction.invoked')),
      hasLength(1),
    );
    await tester.tap(find.byTooltip('חיפוש בדיבור'));
    await tester.pump();
    expect(
      b.sources.where((s) => s.contains('search.fieldAction.stopRequested')),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(a.sources.where((s) => s.contains('search.fieldAction.')), isEmpty);
    expect(
      b.sources.where((s) => s.contains('search.fieldAction.ended')),
      hasLength(1),
    );
    sessions.removePlugin(pluginId);
  });

  test('פתיחת ספר מספק שומרת את B אחרי המתנה ומוסרת רק לדף שלו', () async {
    const pluginId = 'origin.books';
    final a = _Controller();
    final b = _Controller();
    final conditions = PluginConditionEvaluator.forTesting(
      settingReader: (_) => null,
    );
    final registry = PluginLibraryBooksRegistry.forTesting(
      conditions: conditions,
      repository: _Repo(),
    );
    addTearDown(registry.dispose);
    addTearDown(conditions.dispose);
    registry.registerPayload(pluginId, {
      'id': 'books',
      'provider': 'origin-books',
      'title': 'ספרי התוסף',
    });
    await registry.setBooks(pluginId, 'origin-books', [
      {'id': 1, 'title': 'ספר לדוגמה'},
    ]);
    final aOpened = <String>[];
    final bOpened = <String>[];
    launcher.register(aKeys, aOpened.add);
    launcher.register(bKeys, bOpened.add);
    addTearDown(() {
      launcher.unregister(aKeys, aOpened.add);
      launcher.unregister(bKeys, bOpened.add);
    });
    dispatcher.registerController(pluginId, a, instanceId: 'a', viewId: 1);
    launcher.markPageReady(pluginId, instanceId: 'a', viewId: 1);
    AppWindowKeys.activate(bKeys);
    expect(
      registry.open(registry.visibleBooks.single, viewId: 0, windowKeys: bKeys),
      isTrue,
    );
    AppWindowKeys.activate(aKeys);
    await pumpEventQueue();
    expect(aOpened, isEmpty);
    expect(bOpened, [pluginId]);
    expect(a.sources, isEmpty);
    dispatcher.registerController(pluginId, b, instanceId: 'b', viewId: 0);
    launcher.markPageReady(pluginId, instanceId: 'b', viewId: 0);
    await pumpEventQueue();
    expect(a.sources, isEmpty);
    expect(
      b.sources.single,
      contains(PluginLibraryBooksRegistry.openRequestedTopic),
    );
  });
}
