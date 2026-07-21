import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';

void main() {
  group('ContextMenuRegistry', () {
    late ContextMenuRegistry registry;

    setUp(() => registry = ContextMenuRegistry.forTesting());

    test('parses nested items and a color row', () {
      registry.registerPayload('marker', {
        'id': 'marker-menu',
        'type': 'submenu',
        'title': 'Marker',
        'children': [
          {
            'id': 'marker-colors',
            'type': 'color-row',
            'title': 'Color',
            'onColorClickEvent': 'marker.colorSelected',
            'colors': [
              {
                'id': 'yellow',
                'color': '#FFEB3B',
                'label': 'Yellow',
                'selected': true,
              },
              {'id': 'blue', 'color': '#2196F380', 'label': 'Blue'},
              {
                'id': 'remove',
                'color': '#00000000',
                'label': 'Remove',
                'icon': 'eraser_24_regular',
              },
            ],
          },
        ],
      });

      final item = registry.getAll().single.$2;
      expect(item.type, 'submenu');
      expect(item.children.single.type, 'color-row');
      expect(item.children.single.colors, hasLength(3));
      expect(item.children.single.colors.first.selected, isTrue);
      expect(item.children.single.colors.last.icon, 'eraser_24_regular');
      expect(item.children.single.onColorClickEvent, 'marker.colorSelected');
    });

    test('updates an existing item without changing its id', () {
      registry.registerPayload('marker', {
        'id': 'marker-colors',
        'type': 'color-row',
        'title': 'Color',
        'colors': [
          {'id': 'yellow', 'color': '#FFEB3B', 'label': 'Yellow'},
        ],
      });

      final updated = registry.update('marker', 'marker-colors', {
        'title': 'Choose color',
        'colors': [
          {'id': 'green', 'color': '#4CAF50', 'label': 'Green'},
        ],
      });

      expect(updated.id, 'marker-colors');
      expect(updated.title, 'Choose color');
      expect(updated.colors.single.id, 'green');
      expect(registry.getAll(), hasLength(1));
    });

    test('keeps plugin ownership isolated', () {
      const item = PluginContextMenuItem(id: 'same-id', label: 'Item');
      registry.register('first', item);
      registry.register('second', item);

      registry.removeAll('first');

      expect(registry.getAll().single.$1, 'second');
    });

    test('allows at most two top-level items per plugin', () {
      registry.register(
        'marker',
        const PluginContextMenuItem(id: 'first', label: 'First'),
      );
      registry.register(
        'marker',
        const PluginContextMenuItem(id: 'second', label: 'Second'),
      );

      expect(
        () => registry.register(
          'marker',
          const PluginContextMenuItem(id: 'third', label: 'Third'),
        ),
        throwsA(
          isA<PluginContextMenuException>().having(
            (error) => error.code,
            'code',
            'error.invalid_params',
          ),
        ),
      );
      expect(registry.getAll(), hasLength(2));
    });

    test('can replace an existing item when the two-item limit is full', () {
      registry.register(
        'marker',
        const PluginContextMenuItem(id: 'first', label: 'First'),
      );
      registry.register(
        'marker',
        const PluginContextMenuItem(id: 'second', label: 'Second'),
      );

      registry.register(
        'marker',
        const PluginContextMenuItem(id: 'first', label: 'Updated'),
      );

      expect(registry.getAll(), hasLength(2));
      expect(registry.getAll().first.$2.label, 'Updated');
    });

    test('rejects invalid colors and unsupported contexts', () {
      expect(
        () => registry.registerPayload('marker', {
          'id': 'colors',
          'type': 'color-row',
          'title': 'Color',
          'colors': [
            {'id': 'bad', 'color': 'red', 'label': 'Bad'},
          ],
        }),
        throwsA(
          isA<PluginContextMenuException>().having(
            (error) => error.code,
            'code',
            'error.invalid_params',
          ),
        ),
      );
      expect(
        () => registry.registerPayload('marker', {
          'id': 'item',
          'title': 'Item',
          'contexts': ['library'],
        }),
        throwsA(
          isA<PluginContextMenuException>().having(
            (error) => error.code,
            'code',
            'error.unsupported_context',
          ),
        ),
      );
    });

    test('accepts the dedicated page-shape selection context', () {
      registry.registerPayload('marker', {
        'id': 'page-shape-colors',
        'type': 'color-row',
        'title': 'Colors',
        'contexts': ['reader-page-shape-selection'],
        'colors': [
          {'id': 'yellow', 'color': '#FFEB3B', 'label': 'Yellow'},
        ],
      });

      expect(
        registry.getAll().single.$2.contexts,
        ['reader-page-shape-selection'],
      );
    });

    test('accepts multiple contexts and makes children inherit them', () {
      registry.registerPayload('marker', {
        'id': 'marker-menu',
        'type': 'submenu',
        'title': 'Marker',
        'contexts': [
          'reader-selection',
          'reader-page-shape-selection',
        ],
        'children': [
          {'id': 'inherited', 'title': 'Inherited'},
          {
            'id': 'page-only',
            'title': 'Page only',
            'contexts': ['reader-page-shape-selection'],
          },
        ],
      });

      final item = registry.getAll().single.$2;
      expect(item.contexts, hasLength(2));
      expect(item.children.first.contexts, item.contexts);
      expect(
        item.children.last.contexts,
        ['reader-page-shape-selection'],
      );
    });

    test('rejects empty or duplicate contexts', () {
      for (final contexts in [
        <String>[],
        ['reader-selection', 'reader-selection'],
      ]) {
        expect(
          () => registry.registerPayload('marker', {
            'id': 'invalid-contexts',
            'title': 'Invalid',
            'contexts': contexts,
          }),
          throwsA(isA<PluginContextMenuException>()),
        );
      }
    });

    test('rejects a child context outside its parent contexts', () {
      expect(
        () => registry.registerPayload('marker', {
          'id': 'menu',
          'type': 'submenu',
          'title': 'Menu',
          'contexts': ['reader-selection'],
          'children': [
            {
              'id': 'page-only',
              'title': 'Page only',
              'contexts': ['reader-page-shape-selection'],
            },
          ],
        }),
        throwsA(
          isA<PluginContextMenuException>().having(
            (error) => error.code,
            'code',
            'error.unsupported_context',
          ),
        ),
      );
    });
  });
}
