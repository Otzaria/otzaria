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

    test('מקבל את ההקשר reader-highlight (לחיצה על הדגשה ללא בחירה)', () {
      registry.registerPayload('marker', {
        'id': 'marker-remove-highlight',
        'title': 'הסר סימון',
        'contexts': ['reader-highlight'],
      });

      final item = registry.getAll().single.$2;
      expect(item.contexts, ['reader-highlight']);
    });

    test('מקבל reader-book ומוריש אותו לפריטי משנה ללא שינוי ברירת המחדל', () {
      final item = registry.registerPayload('corrections', {
        'id': 'book-menu',
        'title': 'פעולות בספר',
        'type': 'submenu',
        'contexts': ['reader-book'],
        'children': [
          {'id': 'correct-book', 'title': 'העבר את הספר לתיקון'},
        ],
      });
      expect(item.contexts, ['reader-book']);
      expect(item.children.single.contexts, ['reader-book']);
      final legacy = registry.registerPayload('legacy', {
        'id': 'selection',
        'title': 'פעולה על סימון',
      });
      expect(legacy.contexts, [
        'reader-selection',
        'reader-page-shape-selection',
      ]);
    });

    group('action — פעולת host דקלרטיבית', () {
      Map<String, dynamic> actionItem({
        Map<String, dynamic> extra = const {},
      }) => {
        'id': 'save-book',
        'title': 'שמור לרשימה',
        'action': {
          'type': 'storage.set',
          'args': {
            'key': 'savedBooks',
            'value': {r'$selection': 'id'},
          },
        },
        ...extra,
      };

      test('פריט עם action תקין נרשם ונשמר ב-toJson', () {
        registry.registerPayload('marker', actionItem());

        final item = registry.getAll().single.$2;
        expect(item.action, isNotNull);
        expect(item.toJson()['action'], item.action);
      });

      test('action מותר גם על ילד של submenu', () {
        registry.registerPayload('marker', {
          'id': 'menu',
          'type': 'submenu',
          'title': 'רשימות',
          'children': [actionItem()],
        });

        expect(registry.getAll().single.$2.children.single.action, isNotNull);
      });

      test('action על submenu עצמו נדחה', () {
        expect(
          () => registry.registerPayload('marker', {
            'id': 'menu',
            'type': 'submenu',
            'title': 'רשימות',
            'children': [
              {'id': 'child', 'title': 'ילד'},
            ],
            'action': actionItem()['action'],
          }),
          throwsA(isA<PluginContextMenuException>()),
        );
      });

      test('שילוב action עם onClickEvent או openPlugin נדחה', () {
        expect(
          () => registry.registerPayload(
            'marker',
            actionItem(extra: {'onClickEvent': 'my.event'}),
          ),
          throwsA(isA<PluginContextMenuException>()),
        );
        expect(
          () => registry.registerPayload(
            'marker',
            actionItem(extra: {'openPlugin': true}),
          ),
          throwsA(isA<PluginContextMenuException>()),
        );
      });

      test('תבנית פגומה נדחית ברישום', () {
        expect(
          () => registry.registerPayload('marker', {
            'id': 'bad',
            'title': 'פגום',
            'action': {
              'type': 'storage.get',
              'args': {'key': 'k'},
            },
          }),
          throwsA(isA<PluginContextMenuException>()),
        );
      });

      test(r'localService.post עם $storage נרשם; $book אינו זמין כאן', () {
        registry.registerPayload('marker', {
          'id': 'search',
          'title': 'חיפוש בשירות',
          'action': {
            'type': 'localService.post',
            'args': {
              'port': {r'$storage': 'servicePort'},
              'path': '/text/search',
              'body': {
                'text': {r'$selection': 'selectedText'},
              },
            },
          },
        });
        expect(registry.findItem('marker', 'search')?.action, isNotNull);

        expect(
          () => registry.registerPayload('marker', {
            'id': 'book',
            'title': 'ספר',
            'action': {
              'type': 'localService.post',
              'args': {
                'port': 39700,
                'path': '/x',
                'body': {
                  'id': {r'$book': 'id'},
                },
              },
            },
          }),
          throwsA(isA<PluginContextMenuException>()),
        );
      });
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

    test('findItem מוצא פריט עליון ופריט בתת-תפריט', () {
      registry.registerPayload('marker', {
        'id': 'menu',
        'type': 'submenu',
        'title': 'Menu',
        'children': [
          {'id': 'child-action', 'title': 'Child'},
        ],
      });
      registry.registerPayload('marker', {'id': 'top-action', 'title': 'Top'});

      expect(registry.findItem('marker', 'top-action')?.label, 'Top');
      expect(registry.findItem('marker', 'child-action')?.label, 'Child');
      expect(registry.findItem('marker', 'missing'), isNull);
      expect(registry.findItem('other', 'top-action'), isNull);
    });

    test('findItem מוצא גם פריט בעומק שני', () {
      registry.registerPayload('marker', {
        'id': 'root',
        'type': 'submenu',
        'title': 'Root',
        'children': [
          {
            'id': 'nested',
            'type': 'submenu',
            'title': 'Nested',
            'children': [
              {'id': 'target', 'title': 'Target'},
            ],
          },
        ],
      });

      expect(registry.findItem('marker', 'target')?.label, 'Target');
      expect(registry.isItemVisible('marker', 'target'), isTrue);
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

      expect(registry.getAll().single.$2.contexts, [
        'reader-page-shape-selection',
      ]);
    });

    test('accepts multiple contexts and makes children inherit them', () {
      registry.registerPayload('marker', {
        'id': 'marker-menu',
        'type': 'submenu',
        'title': 'Marker',
        'contexts': ['reader-selection', 'reader-page-shape-selection'],
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
      expect(item.children.last.contexts, ['reader-page-shape-selection']);
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

    test('parses showWhen.selectionContainsAny', () {
      final item = registry.registerPayload('dict', {
        'id': 'lookup',
        'title': 'Lookup',
        'showWhen': {
          'selectionContainsAny': ['רש"י', 'תוספות'],
        },
      });

      expect(item.showWhenContainsAny, ['רש"י', 'תוספות']);
      expect(item.isVisibleForSelection('דברי רש"י כאן'), isTrue);
      expect(item.isVisibleForSelection('טקסט אחר'), isFalse);
      expect(item.toJson()['showWhen'], {
        'selectionContainsAny': ['רש"י', 'תוספות'],
      });
    });

    test('rejects invalid showWhen payloads', () {
      Matcher throwsInvalidParams() => throwsA(
        isA<PluginContextMenuException>().having(
          (error) => error.code,
          'code',
          'error.invalid_params',
        ),
      );

      expect(
        () => registry.registerPayload('dict', {
          'id': 'bad1',
          'title': 'Bad',
          'showWhen': 'not-a-map',
        }),
        throwsInvalidParams(),
      );
      expect(
        () => registry.registerPayload('dict', {
          'id': 'bad2',
          'title': 'Bad',
          'showWhen': {'selectionContainsAny': []},
        }),
        throwsInvalidParams(),
      );
      expect(
        () => registry.registerPayload('dict', {
          'id': 'bad3',
          'title': 'Bad',
          'showWhen': {'selectionContainsAny': List.filled(51, 'מ')},
        }),
        throwsInvalidParams(),
      );
    });
  });
}
