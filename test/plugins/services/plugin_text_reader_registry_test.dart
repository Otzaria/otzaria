import 'dart:async';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import '../../test_helpers/memory_cache_provider.dart';

InstalledPlugin plugin({String id = 'test.columns', bool enabled = true}) =>
    InstalledPlugin(
      pluginId: id,
      name: id,
      version: '1.0.0',
      installPath: '/',
      entrypointPath: 'index.html',
      enabled: enabled,
      pinned: false,
      manifest: PluginManifest.fromJson({
        'schemaVersion': 1,
        'id': id,
        'name': id,
        'version': '1.0.0',
        'entrypoint': 'index.html',
        'minAppVersion': '0.9.97',
        'sdkVersion': '1.x',
        'permissions': PluginTextReaderRegistry.requiredPermissions.toList(),
      }),
      installedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class Grants extends PluginRegistryRepository {
  List<String> names = PluginTextReaderRegistry.requiredPermissions.toList();
  Completer<List<String>>? pending;
  @override
  Future<List<String>> getGrantedPermissionNames(String pluginId) async =>
      pending == null ? names : pending!.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));
  tearDown(() => PluginSafeMode.active.value = false);

  test(
    'choice persists and restores only with enabled plugin and all actual grants',
    () async {
      String? stored;
      final grants = Grants();
      final first = PluginTextReaderRegistry(
        loadSelection: () => stored,
        saveSelection: (id) async {
          stored = id;
        },
      );
      addTearDown(first.dispose);
      await first.select(plugin(), true);
      final restored = PluginTextReaderRegistry(loadSelection: () => stored);
      addTearDown(restored.dispose);
      await restored.sync([plugin()], grants);
      expect(restored.activePlugin?.pluginId, 'test.columns');
      await restored.sync([plugin(enabled: false)], grants);
      expect(restored.activePlugin, isNull);
      expect(restored.selectedPluginId, 'test.columns');
      await restored.sync([plugin()], grants);
      grants.names = ['reader.open', 'library.books.read'];
      await restored.sync([plugin()], grants);
      expect(restored.activePlugin, isNull);
      await restored.sync([], grants);
      expect(restored.activePlugin, isNull);
    },
  );

  test(
    'native choice is per book tab, instance IDs stable and different even for the same book',
    () async {
      final registry = PluginTextReaderRegistry(saveSelection: (_) async {});
      addTearDown(registry.dispose);
      final book = TextBook(
        title: 'בראשית',
        source: BookSource.official,
        id: 12,
      );
      final a = TextBookTab(book: book, index: 30),
          b = TextBookTab(book: book, index: 50);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await registry.select(plugin(), true);
      expect(registry.instanceIdFor(a), registry.instanceIdFor(a));
      expect(registry.instanceIdFor(a), isNot(registry.instanceIdFor(b)));
      registry.useNative(a);
      expect(registry.usesPlugin(a), false);
      expect(registry.usesPlugin(b), true);
      final payload = PluginTextReaderRegistry.bookPayload(b);
      expect(payload['embedded'], true);
      expect(payload['currentIndex'], 50);
      expect(payload['source'], 'library');
      expect(payload['bookUid'], isNotEmpty);
      await registry.select(plugin(), true);
      expect(registry.usesPlugin(a), true);
    },
  );

  test(
    'safe mode, uninstall and deselection fall back without corrupting saved choice',
    () async {
      final registry = PluginTextReaderRegistry(saveSelection: (_) async {});
      addTearDown(registry.dispose);
      await registry.select(plugin(), true);
      PluginSafeMode.active.value = true;
      expect(registry.activePlugin, isNull);
      expect(registry.selectedPluginId, 'test.columns');
      PluginSafeMode.active.value = false;
      expect(registry.activePlugin, isNotNull);
      registry.remove('test.columns');
      expect(registry.activePlugin, isNull);
      await registry.select(plugin(), true);
      await registry.select(plugin(id: 'test.other'), false);
      expect(registry.selectedPluginId, 'test.columns');
      await registry.select(plugin(), false);
      expect(registry.activePlugin, isNull);
      expect(registry.selectedPluginId, isNull);
    },
  );

  test('failed setting save preserves prior choice', () async {
    final registry = PluginTextReaderRegistry(
      loadSelection: () => 'test.previous',
      saveSelection: (_) async {
        throw StateError('disk error');
      },
    );
    addTearDown(registry.dispose);
    await expectLater(registry.select(plugin(), true), throwsStateError);
    expect(registry.selectedPluginId, 'test.previous');
    expect(registry.activePlugin, isNull);
  });

  test('safe mode notifies an already displayed reader to fall back', () async {
    final registry = PluginTextReaderRegistry(saveSelection: (_) async {});
    addTearDown(registry.dispose);
    await registry.select(plugin(), true);
    final available = <bool>[];
    registry.addListener(() => available.add(registry.activePlugin != null));
    PluginSafeMode.active.value = true;
    PluginSafeMode.active.value = false;
    expect(available, [false, true]);
  });

  test(
    'removal during a permission load cannot restore the removed reader',
    () async {
      final registry = PluginTextReaderRegistry(
        loadSelection: () => 'test.columns',
      );
      addTearDown(registry.dispose);
      final grants = Grants()..pending = Completer<List<String>>();
      final sync = registry.sync([plugin()], grants);
      registry.remove('test.columns');
      grants.pending!.complete(
        PluginTextReaderRegistry.requiredPermissions.toList(),
      );
      await sync;
      expect(registry.activePlugin, isNull);
      expect(registry.selectedPluginId, 'test.columns');
    },
  );

  test('document formats keep their dedicated native reader', () async {
    final registry = PluginTextReaderRegistry(saveSelection: (_) async {});
    addTearDown(registry.dispose);
    await registry.select(plugin(), true);
    for (final type in ['epub', 'docx']) {
      final tab = TextBookTab(
        book: TextBook(title: 'מסמך', fileType: type),
        index: 0,
      );
      addTearDown(tab.dispose);
      expect(registry.usesPlugin(tab), false);
    }
  });

  test('stale permission load cannot restore an obsolete selection', () async {
    final registry = PluginTextReaderRegistry(
      loadSelection: () => 'test.columns',
      saveSelection: (_) async {},
    );
    addTearDown(registry.dispose);
    final grants = Grants()..pending = Completer<List<String>>();
    final sync = registry.sync([plugin()], grants);
    await registry.select(plugin(id: 'test.other'), true);
    grants.pending!.complete(
      PluginTextReaderRegistry.requiredPermissions.toList(),
    );
    await sync;
    expect(registry.selectedPluginId, 'test.other');
    expect(registry.activePlugin?.pluginId, 'test.other');
  });
}
