import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/declarative/models/declarative_program.dart';
import 'package:otzaria/plugins/models/plugin_toolbar_item.dart';
import 'package:otzaria/plugins/utils/plugin_toolbar_actions.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/controls/bar_split_button.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

void main() {
  Future<Map<String, dynamic>> emptyLocation() async => const {};

  test('builds a simple button with tooltip, icon, and BarButton widget', () {
    const item = PluginToolbarItem(
      id: 'mark',
      title: 'Mark section',
      icon: 'bookmark_24_regular',
    );

    final action = buildPluginToolbarActions(
      records: const [('marker', item)],
      context: 'reader-text',
      compact: false,
      locationPayload: emptyLocation,
    ).single;

    expect(action.tooltip, 'Mark section');
    expect(action.icon, isNotNull);
    expect(action.widget, isA<BarButton>());
    expect(action.onPressed, isNotNull);
    expect(action.submenuItems, isNull);
  });

  test('שם משותף נפתר לאוצריא, ותחילית fluent כופה את פלואנט', () {
    ActionButtonData actionFor(String icon) => buildPluginToolbarActions(
      records: [('marker', PluginToolbarItem(id: 'i', title: 'T', icon: icon))],
      context: 'reader-text',
      compact: false,
      locationPayload: emptyLocation,
    ).single;

    expect(actionFor('book_24_regular').icon, OtzariaIcons.book_24_regular);
    expect(
      actionFor('fluent:book_24_regular').icon,
      FluentIcons.book_24_regular,
    );
  });

  test('buildOrderedPluginOverflowActions מחזיר רק overflow עם המשקל', () {
    const items = [
      ('a', PluginToolbarItem(id: 'bar', title: 'Bar', placement: 'primary')),
      (
        'a',
        PluginToolbarItem(
          id: 'mid',
          title: 'Mid',
          placement: 'overflow',
          order: 55,
        ),
      ),
      ('b', PluginToolbarItem(id: 'end', title: 'End', placement: 'overflow')),
    ];

    final ordered = buildOrderedPluginOverflowActions(
      records: items,
      context: 'reader-text',
      compact: false,
      locationPayload: emptyLocation,
    );

    expect(ordered.map((entry) => (entry.$1, entry.$2.tooltip)), [
      (55, 'Mid'),
      (PluginToolbarItem.defaultOrder, 'End'),
    ]);
  });

  test('mergeOrderedMenuActions משבץ פריט תוסף לפני "הדפסה" ושומר יציבות', () {
    ActionButtonData action(String tooltip) => ActionButtonData(
      widget: const SizedBox.shrink(),
      icon: FluentIcons.circle_24_regular,
      tooltip: tooltip,
      onPressed: null,
    );

    final merged = mergeOrderedMenuActions(
      [
        (10, action('סימניות')),
        (60, action('הדפסה')),
        (70, action('אודות')),
      ],
      [
        (55, action('תוסף לפני הדפסה')),
        (1000, action('תוסף בלי order')),
        // שוויון משקלים: המובנה קודם, ותוספים לפי סדר הרישום.
        (60, action('תוסף שווה להדפסה')),
      ],
    );

    expect(merged.map((item) => item.tooltip), [
      'סימניות',
      'תוסף לפני הדפסה',
      'הדפסה',
      'תוסף שווה להדפסה',
      'אודות',
      'תוסף בלי order',
    ]);
  });

  test('unknown icon name falls back to the puzzle piece icon', () {
    const item = PluginToolbarItem(
      id: 'mark',
      title: 'Mark',
      icon: 'no_such_icon_24_regular',
    );

    final action = buildPluginToolbarActions(
      records: const [('marker', item)],
      context: 'reader-text',
      compact: false,
      locationPayload: emptyLocation,
    ).single;

    expect(action.icon, FluentIcons.puzzle_piece_24_regular);
  });

  test('builds a dropdown with entries and mirrored submenu items', () {
    const item = PluginToolbarItem(
      id: 'menu',
      type: 'menu',
      title: 'Marker',
      icon: 'highlight_24_regular',
      children: [
        PluginToolbarItem(id: 'add', title: 'Add'),
        PluginToolbarItem(id: 'clear', title: 'Clear'),
      ],
    );

    final action = buildPluginToolbarActions(
      records: const [('marker', item)],
      context: 'reader-text',
      compact: false,
      locationPayload: emptyLocation,
    ).single;

    expect(action.tooltip, 'Marker');
    expect(action.widget, isA<AppPopupMenuButton<String>>());
    final menu = action.widget as AppPopupMenuButton<String>;
    expect(menu.entries!.map((entry) => entry.label), ['Add', 'Clear']);
    expect(
      action.submenuItems!.map((child) => child.tooltip),
      ['Add', 'Clear'],
    );
    expect(action.submenuItems!.first.onPressed, isNotNull);
  });

  test('builds a split button whose overflow starts with the main action', () {
    const item = PluginToolbarItem(
      id: 'split',
      type: 'split',
      title: 'Open edition',
      icon: 'book_24_regular',
      children: [
        PluginToolbarItem(id: 'other', title: 'Other edition'),
      ],
    );

    final action = buildPluginToolbarActions(
      records: const [('marker', item)],
      context: 'reader-text',
      compact: false,
      locationPayload: emptyLocation,
    ).single;

    expect(action.tooltip, 'Open edition');
    expect(action.widget, isA<BarSplitButton<int>>());
    expect(action.onPressed, isNotNull);
    expect(
      action.submenuItems!.map((child) => child.tooltip),
      ['Open edition', 'Other edition'],
    );
    final split = action.widget as BarSplitButton<int>;
    expect(split.entries.map((entry) => entry.label), ['Other edition']);
  });

  test('filters top-level items and menu children by reader context', () {
    const textOnly = PluginToolbarItem(
      id: 'text-only',
      title: 'Text only',
      icon: 'apps_24_regular',
      contexts: ['reader-text'],
    );
    const menu = PluginToolbarItem(
      id: 'menu',
      type: 'menu',
      title: 'Menu',
      icon: 'apps_24_regular',
      children: [
        PluginToolbarItem(id: 'both', title: 'Both'),
        PluginToolbarItem(
          id: 'pdf-only',
          title: 'PDF only',
          contexts: ['reader-pdf'],
        ),
      ],
    );

    final pdfActions = buildPluginToolbarActions(
      records: const [('marker', textOnly), ('marker', menu)],
      context: 'reader-pdf',
      compact: false,
      locationPayload: emptyLocation,
    );

    expect(pdfActions, hasLength(1));
    expect(
      pdfActions.single.submenuItems!.map((child) => child.tooltip),
      ['Both', 'PDF only'],
    );

    final textActions = buildPluginToolbarActions(
      records: const [('marker', textOnly), ('marker', menu)],
      context: 'reader-text',
      compact: false,
      locationPayload: emptyLocation,
    );

    expect(textActions, hasLength(2));
    expect(
      textActions.last.submenuItems!.map((child) => child.tooltip),
      ['Both'],
    );
  });

  test('פעולת Host אינה בונה payload ואינה נשלחת למנוע התוסף', () async {
    const hostAction = CompiledDeclarativeAction(
      type: 'reader.openBook',
      args: {
        'identity': {'id': 10},
      },
      requiredPermission: 'reader.open',
      contextSignature: 'book-7',
      programGeneration: 7,
    );
    const item = PluginToolbarItem(
      id: 'open-default',
      title: 'Open default',
      icon: 'book_24_regular',
      hostAction: hostAction,
    );
    var locationCalls = 0;
    final dispatched = <CompiledDeclarativeAction>[];
    final action = buildPluginToolbarActions(
      records: const [('marker', item)],
      context: 'reader-text',
      compact: false,
      locationPayload: () async {
        locationCalls++;
        throw StateError('legacy payload must not be built');
      },
      hostActionDispatcher: (pluginId, action) async {
        expect(pluginId, 'marker');
        dispatched.add(action);
      },
    ).single;

    action.onPressed!();
    await Future<void>.delayed(Duration.zero);

    expect(dispatched, [hostAction]);
    expect(locationCalls, 0);
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

    Future<void> press(PluginToolbarItem item) async {
      final action = buildPluginToolbarActions(
        records: [(pid, item)],
        context: 'reader-text',
        compact: false,
        locationPayload: emptyLocation,
        dispatcher: PluginRuntimeDispatcher.instance,
      ).single;
      action.onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test('פותח מופע נוסף ולא מנווט למופע הראשי', () async {
      await press(
        const PluginToolbarItem(
          id: 'go',
          title: 'go',
          openPlugin: true,
          newTab: true,
        ),
      );

      expect(opened, [pid]);
      expect(navigated, isEmpty);
      expect(launcher.hasPendingFor(pid), isTrue);
    });

    test('בלי newTab הלחיצה מנווטת למופע הראשי ואינה פותחת מופע', () async {
      await press(
        const PluginToolbarItem(id: 'go', title: 'go', openPlugin: true),
      );

      expect(opened, isEmpty);
      expect(navigated, [pid]);
    });
  });
}
