import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';

void main() {
  test('converts submenu, separator, and color row entries', () {
    const item = PluginContextMenuItem(
      id: 'menu',
      type: 'submenu',
      label: 'Marker',
      children: [
        PluginContextMenuItem(id: 'remove', label: 'Remove'),
        PluginContextMenuItem(id: 'separator', type: 'separator'),
        PluginContextMenuItem(
          id: 'colors',
          type: 'color-row',
          label: 'Color',
          colors: [
            PluginContextMenuColor(
              id: 'orange',
              color: '#FF9800',
              label: 'Orange',
              selected: true,
            ),
            PluginContextMenuColor(
              id: 'remove',
              color: '#00000000',
              label: 'Remove',
              icon: 'eraser_24_regular',
            ),
          ],
        ),
      ],
    );

    final entry = buildPluginContextMenuEntries(
      records: const [('marker', item)],
      selection: const {'text': 'selected'},
    ).single;

    expect(entry.label, 'Marker');
    expect(entry.children, hasLength(3));
    expect(entry.children![1].isDivider, isTrue);
    expect(entry.children![2].colorRowActions, hasLength(2));
    expect(entry.children![2].colorRowActions!.first.id, 'orange');
    expect(entry.children![2].colorRowActions!.first.selected, isTrue);
    expect(entry.children![2].colorRowActions!.last.icon, isNotNull);
  });

  test('filters top-level items by reader context', () {
    const regular = PluginContextMenuItem(
      id: 'regular',
      label: 'Regular',
      contexts: ['reader-selection'],
    );
    const pageShape = PluginContextMenuItem(
      id: 'page-shape',
      label: 'Page shape',
      contexts: ['reader-page-shape-selection'],
    );

    final entries = buildPluginContextMenuEntries(
      records: const [('marker', regular), ('marker', pageShape)],
      selection: const {'text': 'selected'},
      context: 'reader-page-shape-selection',
    );

    expect(entries.single.label, 'Page shape');
  });

  test('item without explicit contexts appears in both reader contexts', () {
    const legacy = PluginContextMenuItem(id: 'legacy', label: 'Legacy');

    for (final context in [
      'reader-selection',
      'reader-page-shape-selection',
    ]) {
      final entries = buildPluginContextMenuEntries(
        records: const [('marker', legacy)],
        selection: const {'text': 'selected'},
        context: context,
      );
      expect(entries.single.label, 'Legacy');
    }
  });

  test('filters submenu children by their inherited or explicit context', () {
    const item = PluginContextMenuItem(
      id: 'menu',
      type: 'submenu',
      label: 'Menu',
      contexts: ['reader-selection', 'reader-page-shape-selection'],
      children: [
        PluginContextMenuItem(
          id: 'both',
          label: 'Both',
          contexts: ['reader-selection', 'reader-page-shape-selection'],
        ),
        PluginContextMenuItem(
          id: 'page-only',
          label: 'Page only',
          contexts: ['reader-page-shape-selection'],
        ),
      ],
    );

    final regular = buildPluginContextMenuEntries(
      records: const [('marker', item)],
      selection: const {'text': 'selected'},
    ).single;
    final pageShape = buildPluginContextMenuEntries(
      records: const [('marker', item)],
      selection: const {'text': 'selected'},
      context: 'reader-page-shape-selection',
    ).single;

    expect(regular.children!.map((child) => child.label), ['Both']);
    expect(
      pageShape.children!.map((child) => child.label),
      ['Both', 'Page only'],
    );
  });
}
