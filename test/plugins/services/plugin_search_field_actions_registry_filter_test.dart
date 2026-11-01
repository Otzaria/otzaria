import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_library_books_filter.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';

class _EmptyRepository implements PluginRegistryRepository {
  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PluginLibraryBooksRegistry previous;
  late PluginLibraryBooksRegistry books;
  late PluginConditionEvaluator conditions;
  late PluginSearchFieldActionsRegistry actions;

  Map<String, dynamic> filter(String id) => {
    'id': id,
    'title': 'מקור הספרים',
    'mode': 'providerBooksFilter',
  };
  Map<String, dynamic> session(String id, {String field = 'library'}) => {
    'id': id,
    'title': 'חיפוש',
    'fields': [field],
  };

  setUp(() {
    previous = PluginLibraryBooksRegistry.instance;
    conditions = PluginConditionEvaluator.forTesting(
      settingReader: (_) => null,
    );
    books = PluginLibraryBooksRegistry.forTesting(
      conditions: conditions,
      repository: _EmptyRepository(),
    );
    PluginLibraryBooksRegistry.instance = books;
    actions = PluginSearchFieldActionsRegistry.forTesting();
    books.registerPayload('plugin', {
      'id': 'books',
      'provider': 'pluginbooks',
      'title': 'ספרי התוסף',
    });
    actions.registerPayload('plugin', filter('source'));
    books.cycleSource('plugin');
    expect(books.searchesExtraBooksOnly, isTrue);
  });

  tearDown(() {
    actions.dispose();
    PluginLibraryBooksRegistry.instance = previous;
    books.dispose();
    conditions.dispose();
  });

  for (final removeAll in [false, true]) {
    test(
      'removing ${removeAll ? 'all actions' : 'the filter'} resets source',
      () {
        if (removeAll) {
          actions.removeAll('plugin');
        } else {
          actions.remove('plugin', 'source');
        }
        expect(books.hasProviderFor('plugin'), isTrue);
        expect(books.sourceFilter.value, PluginLibraryBooksFilter.all);
      },
    );
  }

  test(
    'replacing the filter with a session in another field resets source',
    () {
      actions.registerPayload('plugin', session('source', field: 'inBook'));
      expect(books.sourceFilter.value, PluginLibraryBooksFilter.all);
    },
  );

  test('reapplying the filter and unrelated removals preserve source', () {
    actions.registerPayload('plugin', filter('source'));
    actions.registerPayload('other', session('dictate'));
    actions.remove('other', 'dictate');
    actions.removeAll('other');
    expect(books.searchesExtraBooksOnly, isTrue);
    actions.registerPayload('plugin', filter('second'));
    actions.remove('plugin', 'source');
    expect(books.searchesExtraBooksOnly, isTrue);
  });

  test('a filter displaced by the field action limit resets source', () {
    actions.registerPayload('plugin', session('second'));
    actions.registerPayload('earlier', session('dictate', field: 'inBook'));
    actions.registerPayload('later', filter('source'));
    books.registerPayload('later', {
      'id': 'books',
      'provider': 'laterbooks',
      'title': 'ספרים נוספים',
    });
    books.cycleSource('later');
    expect(books.sourceFilter.value.pluginId, 'later');
    actions.registerPayload('earlier', session('dictate'));
    expect(books.sourceFilter.value, PluginLibraryBooksFilter.all);
  });
}
