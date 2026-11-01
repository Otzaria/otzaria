import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

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

  group('resolveSelectedText', () {
    const item = PluginContextMenuItem(
      id: 'search',
      label: 'חפש',
      showWhenContainsAny: ['ברא'],
      action: {
        'type': 'storage.set',
        'args': {
          'key': 'last',
          'value': {r'$selection': 'selectedText'},
        },
      },
    );

    Future<Map<String, dynamic>> click(
      PluginSelectedTextResolver resolve,
    ) async {
      final sent = <Map<String, dynamic>>[];
      final entry = buildPluginContextMenuEntries(
        records: const [('plugin', item)],
        selection: const {'text': 'בראשית ברא', 'bookTitle': 'בראשית'},
        selectionActionDispatcher: (_, _, payload) async => sent.add(payload),
        resolveSelectedText: resolve,
      ).single;
      entry.onTap!();
      await Future<void>.delayed(Duration.zero);
      return sent.single;
    }

    test('הטקסט נקרא בלחיצה; ההצגה נקבעת לפי ה-payload של התפריט', () async {
      var reads = 0;
      final payload = await click(() async {
        reads++;
        return 'שלום';
      });
      expect(reads, 1);
      expect(payload['selectedText'], 'שלום');
      expect(payload['currentBook'], 'בראשית');
    });

    test('כשל בקריאת הטקסט מוסר את הלחיצה בלי הטקסט', () async {
      final payload = await click(() async => throw StateError('closed'));
      expect(payload['selectedText'], isEmpty);
      expect(payload['currentBook'], 'בראשית');
    });
  });

  test('פריט עם action מבוצע דרך מבצע פעולות הסימון בלבד', () async {
    const item = PluginContextMenuItem(
      id: 'save',
      label: 'שמור לרשימה',
      action: {
        'type': 'storage.set',
        'args': {
          'key': 'savedBooks',
          'value': {r'$selection': 'id'},
        },
      },
    );
    final calls = <(String, Map<String, dynamic>, Map<String, dynamic>)>[];

    final entry = buildPluginContextMenuEntries(
      records: const [('lists', item)],
      selection: const {
        'text': 'טקסט מסומן',
        'id': 42,
        'bookTitle': 'ברכות',
        'sectionIndex': 7,
      },
      selectionActionDispatcher: (pluginId, action, payload) async {
        calls.add((pluginId, action, payload));
      },
    ).single;

    entry.onTap!();

    final (pluginId, action, payload) = calls.single;
    expect(pluginId, 'lists');
    expect(action, item.action);
    expect(payload['id'], 42);
    expect(payload['currentBook'], 'ברכות');
    expect(payload['currentIndex'], 7);
    expect(payload['selectedText'], 'טקסט מסומן');
  });

  test('showWhen hides items whose words are absent from the selection', () {
    const conditional = PluginContextMenuItem(
      id: 'lookup',
      label: 'Lookup',
      showWhenContainsAny: ['רש"י', 'תוספות'],
    );
    const always = PluginContextMenuItem(id: 'always', label: 'Always');

    final without = buildPluginContextMenuEntries(
      records: const [('dict', conditional), ('dict', always)],
      selection: const {'text': 'טקסט רגיל'},
    );
    expect(without.single.label, 'Always');

    final withMatch = buildPluginContextMenuEntries(
      records: const [('dict', conditional), ('dict', always)],
      selection: const {'text': 'פירוש רש"י על הפסוק'},
    );
    expect(withMatch.map((e) => e.label), ['Lookup', 'Always']);
  });

  test('showWhen prefers renderedSelectedText over raw text', () {
    const conditional = PluginContextMenuItem(
      id: 'lookup',
      label: 'Lookup',
      showWhenContainsAny: ['מילה'],
    );

    final entries = buildPluginContextMenuEntries(
      records: const [('dict', conditional)],
      selection: const {'renderedSelectedText': 'יש כאן מילה', 'text': 'אחר'},
    );
    expect(entries, hasLength(1));
  });

  test('showWhen filters submenu children individually', () {
    const item = PluginContextMenuItem(
      id: 'menu',
      type: 'submenu',
      label: 'Menu',
      children: [
        PluginContextMenuItem(id: 'always', label: 'Always'),
        PluginContextMenuItem(
          id: 'conditional',
          label: 'Conditional',
          showWhenContainsAny: ['חסר'],
        ),
      ],
    );

    final entry = buildPluginContextMenuEntries(
      records: const [('dict', item)],
      selection: const {'text': 'טקסט'},
    ).single;
    expect(entry.children!.map((child) => child.label), ['Always']);
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

  group('divider between plugins', () {
    const a1 = PluginContextMenuItem(id: 'a1', label: 'A1');
    const a2 = PluginContextMenuItem(id: 'a2', label: 'A2');
    const b1 = PluginContextMenuItem(id: 'b1', label: 'B1');
    const selection = {'text': 'selected'};

    List<String> shape(List<(String, PluginContextMenuItem)> records) => [
      for (final entry in buildPluginContextMenuEntries(
        records: records,
        selection: selection,
      ))
        entry.isDivider ? '|' : entry.label!,
    ];

    test('separates the item groups of different plugins by default', () {
      expect(shape(const [('a', a1), ('b', b1)]), ['A1', '|', 'B1']);
    });

    test('adds no divider around a single plugin', () {
      expect(shape(const [('a', a1), ('a', a2)]), ['A1', 'A2']);
      expect(shape(const [('a', a1)]), ['A1']);
    });

    test('keeps a plugin items together when registrations interleave', () {
      expect(shape(const [('a', a1), ('b', b1), ('a', a2)]), [
        'A1',
        'A2',
        '|',
        'B1',
      ]);
    });

    test('a plugin opts out on its first item', () {
      const noDivider = PluginContextMenuItem(
        id: 'b1',
        label: 'B1',
        separatorBefore: false,
      );
      expect(shape(const [('a', a1), ('b', noDivider)]), ['A1', 'B1']);
    });

    test('opting out leaves the divider before the next plugin', () {
      const noDivider = PluginContextMenuItem(
        id: 'b1',
        label: 'B1',
        separatorBefore: false,
      );
      const c1 = PluginContextMenuItem(id: 'c1', label: 'C1');
      expect(shape(const [('a', a1), ('b', noDivider), ('c', c1)]), [
        'A1',
        'B1',
        '|',
        'C1',
      ]);
    });

    test('plugin hidden in this context leaves no stray divider', () {
      const other = PluginContextMenuItem(
        id: 'b1',
        label: 'B1',
        contexts: ['reader-highlight'],
      );
      expect(shape(const [('a', a1), ('b', other)]), ['A1']);
    });

    test('does not double a divider the plugin supplied itself', () {
      const leading = PluginContextMenuItem(id: 'sep', type: 'separator');
      const trailing = PluginContextMenuItem(id: 'sep2', type: 'separator');
      expect(
        shape(const [('a', a1), ('a', trailing), ('b', leading), ('b', b1)]),
        ['A1', '|', 'B1'],
      );
    });
  });

  group('openPlugin עם newTab', () {
    const pid = 'click.new.tab.plugin';
    late List<String> opened;
    late List<String> navigated;
    final launcher = PluginPageLauncher.instance;

    String? opener(String pluginId) {
      opened.add(pluginId);
      return 'extra';
    }

    void navigator(String pluginId) => navigated.add(pluginId);

    setUp(() {
      opened = [];
      navigated = [];
      launcher.register(AppWindowKeys.current, navigator);
      launcher.registerInstanceOpener(
        AppWindowKeys.current,
        opener,
        hasOpenTab: (_) => true,
      );
    });

    tearDown(() {
      launcher.unregister(AppWindowKeys.current, navigator);
      launcher.unregisterInstanceOpener(AppWindowKeys.current, opener);
      launcher.markPageClosed(pid, instanceId: 'extra');
      launcher.markPageClosed(pid);
      AppWindowKeys.resetForTest();
    });

    Future<void> click(PluginContextMenuItem item) =>
        dispatchPluginContextMenuItemClick(
          dispatcher: PluginRuntimeDispatcher.instance,
          pluginId: pid,
          item: item,
          selection: const {'text': 'טקסט'},
        );

    test('פותח מופע נוסף ולא מנווט למופע הראשי', () async {
      await click(
        const PluginContextMenuItem(
          id: 'go',
          label: 'go',
          openPlugin: true,
          newTab: true,
        ),
      );

      expect(opened, [pid]);
      expect(navigated, isEmpty);
      expect(launcher.hasPendingFor(pid), isTrue);
    });

    test('בלי newTab הלחיצה מנווטת למופע הראשי ואינה פותחת מופע', () async {
      await click(
        const PluginContextMenuItem(id: 'go', label: 'go', openPlugin: true),
      );

      expect(opened, isEmpty);
      // שני האירועים מכוונים לראשי, אבל ניווט מבוקש פעם אחת בלבד.
      expect(navigated, [pid]);
    });
  });
}
