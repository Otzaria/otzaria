import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_in_book_search_service.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/models/books.dart';

class _FakeRepo implements PluginRegistryRepository {
  @override
  Future<void> setPermission(String id, String perm, bool granted) async {}

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];

  @override
  Future<List<String>> getGrantedPermissionNames(String id) async => [];

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];

  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDeclarativeHost implements DeclarativePluginHost {
  final removed = <String>[];

  @override
  void removePlugin(String pluginId) => removed.add(pluginId);

  @override
  Future<void> syncPlugins(List<InstalledPlugin> plugins) async {}

  @override
  Future<void> readerBookChanged(Book? book, {required String context}) async {}

  @override
  Future<void> dispatchAction(
    String pluginId,
    CompiledDeclarativeAction action,
  ) async {}

  @override
  Future<void> dispatchSelectionAction(
    String pluginId,
    Map<String, dynamic> actionTemplate,
    Map<String, dynamic> selectionPayload,
  ) async {}

  @override
  Future<void> dispatchLibraryBookAction(
    String pluginId,
    Map<String, dynamic> actionTemplate,
    Map<String, dynamic> bookPayload,
  ) async {}

  @override
  void dispose() {}
}

Map<String, dynamic> _highlightPayload() => {
  'highlightId': 'h1',
  'bookId': 'book',
  'sectionIndex': 1,
  'range': {
    'type': 'text-range-v1',
    'schemaVersion': 1,
    'layer': 'source',
    'sourceTextHash':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'start': {'grapheme': 2, 'codePoint': 2, 'utf16': 2},
    'end': {'grapheme': 6, 'codePoint': 6, 'utf16': 6},
    'exactText': 'טקסט',
    'beforeText': {
      'raw': 'לפני',
      'normalized': 'לפני',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'afterText': {
      'raw': 'אחרי',
      'normalized': 'אחרי',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'occurrenceIndexInSection': 0,
    'occurrenceCountInSection': 1,
  },
  'style': {'backgroundColor': '#FFE066', 'opacity': 0.7, 'priority': 3},
};

void main() {
  const toolbarItem = PluginToolbarItem(
    id: 'button',
    title: 'Button',
    icon: 'apps_24_regular',
  );
  const menuItem = PluginContextMenuItem(id: 'item', label: 'Item');

  tearDown(() {
    PluginToolbarRegistry.instance.removeAll('p1');
    ContextMenuRegistry.instance.removeAll('p1');
    PluginShortcutRegistry.instance.removeAll('p1');
    PluginHighlightRegistry.instance.removePlugin('p1');
    PluginLazyActivationService.instance.removePlugin('p1');
    PluginExternalSearchService.instance.removePlugin('p1');
    PluginInBookSearchService.instance.removePlugin('p1');
    PluginLazyActivationService.instance.backgroundDeactivator = null;
  });

  Future<void> revoke(String permission) async {
    final bloc = PluginSystemBloc(repository: _FakeRepo());
    addTearDown(bloc.close);
    bloc.add(
      SetPluginPermissionRequested(
        pluginId: 'p1',
        permission: permission,
        granted: false,
      ),
    );
    await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));
  }

  test('revoking reader.toolbar removes the plugin toolbar items', () async {
    PluginToolbarRegistry.instance.register('p1', toolbarItem);

    await revoke('reader.toolbar');

    expect(PluginToolbarRegistry.instance.getAll(), isEmpty);
  });

  test('revoking reader.context_menu removes the context menu items', () async {
    ContextMenuRegistry.instance.register('p1', menuItem);

    await revoke('reader.context_menu');

    expect(ContextMenuRegistry.instance.getAll(), isEmpty);
  });

  test('revoking app.shortcuts removes runtime plugin shortcuts', () async {
    PluginShortcutRegistry.instance.registerPayload('p1', {
      'id': 'runtime-command',
      'label': 'פעולה',
      'key': 'ctrl+alt+r',
      'command': 'run',
    });

    await revoke('app.shortcuts');

    expect(PluginShortcutRegistry.instance.getAll(), isEmpty);
  });

  test('revoking reader.highlight removes the plugin highlights', () async {
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: 'p1',
      payload: _highlightPayload(),
    );

    await revoke('reader.highlight');

    expect(
      PluginHighlightRegistry.instance.getAllHighlights(
        bookId: 'book',
        sectionIndex: 1,
      ),
      isEmpty,
    );
  });

  test('revoking an unrelated permission keeps the registrations', () async {
    PluginToolbarRegistry.instance.register('p1', toolbarItem);
    ContextMenuRegistry.instance.register('p1', menuItem);

    await revoke('notes.read');

    expect(PluginToolbarRegistry.instance.getAll(), hasLength(1));
    expect(ContextMenuRegistry.instance.getAll(), hasLength(1));
  });

  test('כל שינוי הרשאה מבטל מיד תרומה דקלרטיבית פעילה', () async {
    final host = _FakeDeclarativeHost();
    final bloc = PluginSystemBloc(
      repository: _FakeRepo(),
      declarativeHost: host,
    );
    addTearDown(bloc.close);

    bloc.add(
      const SetPluginPermissionRequested(
        pluginId: 'p1',
        permission: 'reader.open',
        granted: false,
      ),
    );
    await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));

    expect(host.removed, ['p1']);
  });

  test('שלילת reader.open מסירה ספקי חיפוש של התוסף', () async {
    PluginExternalSearchService.instance.register('external-p1', 'p1');
    PluginInBookSearchService.instance.register('in-book-p1', 'p1');

    await revoke('reader.open');

    expect(
      PluginExternalSearchService.instance.hasProvider('external-p1'),
      isFalse,
    );
    expect(
      PluginInBookSearchService.instance.hasProvider('in-book-p1'),
      isFalse,
    );
  });

  for (final permission in [
    'app.run_on_startup',
    'app.startup_contributions',
  ]) {
    test(
      'revoking $permission immediately tears down a lazy instance',
      () async {
        final deactivations = <String>[];
        final lazy = PluginLazyActivationService.instance
          ..backgroundDeactivator = deactivations.add
          ..syncPlugin(
            'p1',
            broadcastTopics: const {},
            scheduleStartup: false,
          )
          ..trackIdleTeardown('p1');
        await lazy.onBackgroundInstanceReady('p1');

        await revoke(permission);

        expect(deactivations, ['p1']);
      },
    );
  }
}
