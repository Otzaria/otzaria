import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_group.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/view/plugin_group_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';
import 'package:otzaria/tools/plugin_group_entries.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/view/tools_launcher_panel.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

import '../test_helpers/stub_settings_bloc.dart';

InstalledPlugin _plugin(
  String id,
  String title, {
  bool enabled = true,
  bool showInTools = true,
  bool network = false,
}) => InstalledPlugin(
  pluginId: id,
  name: title,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: enabled,
  pinned: false,
  showInTools: showInTools,
  networkAccessGranted: network,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: title,
    version: '1.0.0',
    description: '',
    author: 'test',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: network,
    networkAllowlist: const [],
    toolTabTitle: title,
    toolTabOrder: 900,
    defaultPinned: false,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

PluginGroup _group(String id, List<String> ids, {String name = 'כתיבה'}) =>
    PluginGroup(id: id, name: name, pluginIds: ids);

ToolCatalogEntry _entry(String id) =>
    ToolCatalogEntry.fromPlugin(_plugin(id, id));

class _PluginBloc extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  _PluginBloc(super.initialState) {
    on<PluginSystemEvent>((event, emit) {});
  }

  final List<PluginSystemEvent> recorded = [];

  void publish(PluginSystemState next) => emit(next);

  @override
  void add(PluginSystemEvent event) {
    recorded.add(event);
    super.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TabsBloc() : super(TabsState.initial());

  @override
  void add(TabsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('launcher projection', () {
    test(
      'collapses members at the first visible member without duplication',
      () {
        const builtIn = ToolCatalogEntry(
          toolId: 'builtin.test',
          label: 'מובנה',
          order: 1,
        );
        final entries = [builtIn, _entry('a'), _entry('b'), _entry('c')];
        final grouped = collapsePluginGroups(entries, [
          _group('writing', ['a', 'c']),
        ]);
        expect(grouped.map((entry) => entry.toolId), [
          'builtin.test',
          'plugin-group:writing',
          'b',
        ]);
        final folder = grouped[1] as PluginGroupCatalogEntry;
        expect(folder.members.map((member) => member.toolId), ['a', 'c']);
        expect(folder.plugin, isNull);
        expect(folder.isPlugin, isTrue);
      },
    );

    test('does not restore hidden members and keeps empty groups editable', () {
      final grouped = collapsePluginGroups(
        [_entry('visible')],
        [
          _group('mixed', ['hidden', 'visible']),
          _group('empty', ['unavailable']),
        ],
      ).cast<PluginGroupCatalogEntry>();
      expect(grouped.first.members.map((entry) => entry.toolId), ['visible']);
      expect(grouped.last.members, isEmpty);
    });

    test(
      'reorders a whole folder preserving hidden members and internal order',
      () {
        final folder = PluginGroupCatalogEntry(
          group: _group('folder', ['a', 'hidden', 'c']),
          members: [_entry('a'), _entry('c')],
        );
        expect(
          reorderPluginLauncherEntries(
            ['a', 'b', 'hidden', 'c', 'd'],
            folder,
            _entry('d'),
            placeAfter: true,
          ),
          ['b', 'd', 'a', 'hidden', 'c'],
        );
        expect(
          reorderPluginLauncherEntries(
            ['a', 'b', 'hidden', 'c', 'd'],
            _entry('d'),
            folder,
            placeAfter: false,
          ),
          ['d', 'a', 'b', 'hidden', 'c'],
        );
      },
    );

    test('moving interleaved folders uses the visible target anchor', () {
      final groups = [
        _group('g', ['a', 'd']),
        _group('h', ['b', 'e']),
        _group('i', ['c', 'f']),
      ];
      final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      final entries = collapsePluginGroups(ids.map(_entry).toList(), groups);
      final gAfterH = reorderPluginLauncherEntries(
        ids,
        entries[0],
        entries[1],
        placeAfter: true,
      );
      expect(gAfterH, ['b', 'a', 'd', 'c', 'e', 'f']);
      expect(
        collapsePluginGroups(
          gAfterH.map(_entry).toList(),
          groups,
        ).map((entry) => entry.toolId),
        ['plugin-group:h', 'plugin-group:g', 'plugin-group:i'],
      );
      final iAfterG = reorderPluginLauncherEntries(
        ids,
        entries[2],
        entries[0],
        placeAfter: true,
      );
      expect(iAfterG, ['a', 'c', 'f', 'b', 'd', 'e']);
      expect(
        collapsePluginGroups(
          iAfterG.map(_entry).toList(),
          groups,
        ).map((entry) => entry.toolId),
        ['plugin-group:g', 'plugin-group:i', 'plugin-group:h'],
      );
    });

    test('a hidden target member does not move its visible anchor', () {
      final target = PluginGroupCatalogEntry(
        group: _group('h', ['hidden', 'visible']),
        members: [_entry('visible')],
      );
      expect(
        reorderPluginLauncherEntries(
          ['hidden', 'g', 'c', 'visible'],
          _entry('c'),
          target,
          placeAfter: false,
        ),
        ['hidden', 'g', 'c', 'visible'],
      );
      expect(
        reorderPluginLauncherEntries(
          ['hidden', 'g', 'c', 'visible'],
          _entry('c'),
          target,
          placeAfter: true,
        ),
        ['hidden', 'g', 'visible', 'c'],
      );
    });

    test('missing or overlapping move targets leave the order unchanged', () {
      final folder = PluginGroupCatalogEntry(
        group: _group('folder', ['a', 'b']),
        members: [_entry('a'), _entry('b')],
      );
      for (final target in [folder, _entry('a'), _entry('missing')]) {
        expect(
          reorderPluginLauncherEntries(
            ['a', 'b', 'c'],
            folder,
            target,
            placeAfter: true,
          ),
          ['a', 'b', 'c'],
        );
      }
    });
  });

  test('reordering members preserves the positions of their folders', () {
    final groups = [
      _group('g', ['a', 'c']),
      _group('h', ['b', 'd']),
    ];
    final reordered = reorderPluginLauncherEntries(
      ['a', 'b', 'c', 'd'],
      _entry('a'),
      _entry('c'),
      placeAfter: true,
      withinGroup: groups.first.pluginIds,
    );
    expect(reordered, ['c', 'b', 'a', 'd']);
    expect(
      collapsePluginGroups(
        reordered.map(_entry).toList(),
        groups,
      ).map((entry) => entry.toolId),
      ['plugin-group:g', 'plugin-group:h'],
    );
  });

  group('manual plugin groups in launcher', () {
    late _PluginBloc pluginBloc;
    late _TabsBloc tabsBloc;
    late StubSettingsBloc settingsBloc;
    late List<ToolCatalogEntry> opened;
    late int closed;

    final plugins = [
      _plugin('com.test.notes', 'הערות'),
      _plugin('com.test.editor', 'עורך'),
      _plugin('com.test.review', 'חזרות'),
    ];
    final folder = _group('writing', ['com.test.notes', 'com.test.editor']);

    Future<void> pumpLauncher(
      WidgetTester tester, {
      PluginSystemLoaded? state,
      bool offline = false,
      double width = 360,
      double textScale = 1,
      ThemeData? theme,
      Set<String> visibleBuiltIns = const {},
    }) async {
      pluginBloc = _PluginBloc(
        state ??
            PluginSystemLoaded(plugins, groups: [folder], groupsLoaded: true),
      );
      tabsBloc = _TabsBloc();
      settingsBloc = StubSettingsBloc(
        SettingsState.initial().copyWith(
          hiddenBuiltInToolIds: {
            for (final tool in kBuiltInToolsCatalog)
              if (!visibleBuiltIns.contains(tool.toolId)) tool.toolId,
          },
          isOfflineMode: offline,
          settingsLanguageCode: 'he',
        ),
      );
      opened = [];
      closed = 0;
      addTearDown(() async {
        await pluginBloc.close();
        await tabsBloc.close();
        await settingsBloc.close();
      });
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
            home: Scaffold(
              body: SizedBox(
                width: width,
                height: 600,
                child: ToolsLauncherPanel(
                  showDevTools: false,
                  onToolSelected: opened.add,
                  onClose: () => closed++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder tile(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(ToolTile));

    Material surface(WidgetTester tester, String label) =>
        tester.widget<Material>(
          find
              .descendant(of: tile(label), matching: find.byType(Material))
              .first,
        );

    Future<void> verifyFolderAndPluginSurfaces(WidgetTester tester) async {
      final context = tester.element(tile('כתיבה'));
      final cs = Theme.of(context).colorScheme;
      expect(surface(tester, 'כתיבה').color, AppSurfaces.card(context));
      expect(surface(tester, 'כתיבה').shape, AppCard.shape(cs));
      expect(surface(tester, 'חזרות').color, Colors.transparent);
      expect(surface(tester, 'חזרות').shape, AppTokens.roundedShape);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(tester.widget<ToolTile>(tile('חזרות')).isHighlighted, isTrue);
      expect(surface(tester, 'חזרות').color, AppSurfaces.selectedRow(cs));
      expect(
        surface(tester, 'חזרות').shape,
        AppCard.shape(cs, selectedBorder: AppSurfaces.selectedBorder(context)),
      );
    }

    Future<void> menu(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: tile(label),
          matching: find.byType(AppPopupMenuButton<VoidCallback>),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opening a folder never launches a synthetic tool', (
      tester,
    ) async {
      await pumpLauncher(tester);
      expect(tile('כתיבה'), findsOneWidget);
      expect(tile('הערות'), findsNothing);
      expect(tile('חזרות'), findsOneWidget);
      await tester.tap(find.text('כתיבה'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(tile('הערות'), findsOneWidget);
      expect(tile('עורך'), findsOneWidget);
      expect(tile('חזרות'), findsNothing);
      await tester.tap(find.text('הערות'));
      expect(opened.single.toolId, 'com.test.notes');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tile('כתיבה'), findsOneWidget);
      expect(closed, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
    });

    testWidgets('folder navigation does not focus search on touch', (
      tester,
    ) async {
      await pumpLauncher(
        tester,
        state: PluginSystemLoaded(
          plugins,
          groups: [
            folder,
            _group('empty', [], name: 'קבוצה ריקה'),
          ],
          groupsLoaded: true,
        ),
      );
      final search = tester.widget<TextField>(find.byType(TextField));
      expect(search.focusNode!.hasFocus, isFalse);

      await tester.tap(find.text('כתיבה'));
      await tester.pumpAndSettle();
      expect(tile('הערות'), findsOneWidget);
      expect(search.focusNode!.hasFocus, isFalse);

      await tester.tap(find.byTooltip('חזרה לכל הכלים'));
      await tester.pumpAndSettle();
      expect(tile('כתיבה'), findsOneWidget);
      expect(search.focusNode!.hasFocus, isFalse);

      await tester.tap(find.text('קבוצה ריקה'));
      await tester.pumpAndSettle();
      expect(find.text('אין תוספים זמינים בקבוצה'), findsOneWidget);
      expect(search.focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tile('קבוצה ריקה'), findsOneWidget);
      expect(search.focusNode!.hasFocus, isFalse);
      expect(closed, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
    }, variant: const TargetPlatformVariant({TargetPlatform.android}));

    testWidgets('a matching built-in ID does not make it a folder member', (
      tester,
    ) async {
      const id = 'builtin.calendar';
      await pumpLauncher(
        tester,
        state: PluginSystemLoaded(
          [_plugin(id, 'תוסף לוח')],
          groups: [
            _group('writing', [id]),
          ],
          groupsLoaded: true,
        ),
        visibleBuiltIns: {id},
      );
      expect(tile('לוח שנה'), findsOneWidget);
      await tester.tap(find.text('כתיבה'));
      await tester.pumpAndSettle();
      expect(tile('תוסף לוח'), findsOneWidget);
      expect(tile('לוח שנה'), findsNothing);
    });

    testWidgets('unframed plugin menu does not launch the plugin', (
      tester,
    ) async {
      await pumpLauncher(tester);
      await menu(tester, 'חזרות');
      expect(opened, isEmpty);
      expect(find.text('העבר לקבוצה'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getRect(tile('חזרות')).bottomLeft + const Offset(8, -8),
      );
      await tester.pumpAndSettle();
      expect(opened.single.toolId, 'com.test.review');
    });

    testWidgets(
      'search finds grouped members and Enter opens the real plugin',
      (
        tester,
      ) async {
        await pumpLauncher(tester);
        await tester.enterText(find.byType(TextField), 'הערות');
        await tester.pumpAndSettle();
        expect(tile('הערות'), findsOneWidget);
        expect(tile('כתיבה'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(opened.single.toolId, 'com.test.notes');
      },
    );

    testWidgets(
      'folder name search and keyboard activation open its contents',
      (
        tester,
      ) async {
        await pumpLauncher(tester);
        await tester.enterText(find.byType(TextField), 'כתיבה');
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(opened, isEmpty);
        expect(tile('הערות'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '',
        );
        await tester.tap(find.byTooltip('חזרה לכל הכלים'));
        await tester.pumpAndSettle();
        expect(tile('כתיבה'), findsOneWidget);
      },
    );

    testWidgets(
      'removal is a membership change and live updates refresh the folder',
      (
        tester,
      ) async {
        await pumpLauncher(tester);
        await tester.tap(find.text('כתיבה'));
        await tester.pumpAndSettle();
        await menu(tester, 'הערות');
        await tester.tap(find.text('הוצא מהקבוצה'));
        await tester.pumpAndSettle();
        final move = pluginBloc.recorded
            .whereType<MovePluginToGroupRequested>()
            .single;
        expect(move.pluginId, 'com.test.notes');
        expect(move.groupId, isNull);
        expect(
          pluginBloc.recorded.whereType<UninstallPluginRequested>(),
          isEmpty,
        );
        pluginBloc.publish(
          PluginSystemLoaded(
            plugins,
            groups: [
              _group('writing', ['com.test.editor']),
            ],
            groupsLoaded: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(tile('הערות'), findsNothing);
        expect(tile('עורך'), findsOneWidget);
        pluginBloc.publish(PluginSystemLoaded(plugins, groupsLoaded: true));
        await tester.pumpAndSettle();
        expect(find.byTooltip('חזרה לכל הכלים'), findsNothing);
        expect(tile('הערות'), findsOneWidget);
      },
    );

    testWidgets(
      'disabled hidden and offline plugins stay unavailable in a group',
      (
        tester,
      ) async {
        await pumpLauncher(
          tester,
          offline: true,
          state: PluginSystemLoaded(
            [
              _plugin('disabled', 'מושבת', enabled: false),
              _plugin('hidden', 'מוסתר', showInTools: false),
              _plugin('online', 'מחובר', network: true),
            ],
            groups: [
              _group('writing', ['disabled', 'hidden', 'online']),
            ],
            groupsLoaded: true,
          ),
        );
        await tester.tap(find.text('כתיבה'));
        await tester.pumpAndSettle();
        expect(find.byType(ToolTile), findsNothing);
        expect(find.text('אין תוספים זמינים בקבוצה'), findsOneWidget);
        expect(find.byTooltip('עריכת קבוצה'), findsOneWidget);
      },
    );

    testWidgets(
      'requests groups lazily and disables edits until they are loaded',
      (
        tester,
      ) async {
        await pumpLauncher(tester, state: PluginSystemLoaded(plugins));
        expect(pluginBloc.recorded.whereType<LoadPluginGroups>(), hasLength(1));
        await tester.tap(find.byTooltip('קבוצה חדשה'));
        await tester.pumpAndSettle();
        expect(find.byType(PluginGroupEditor), findsNothing);
        pluginBloc.publish(PluginSystemLoaded(plugins, groupsLoaded: true));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('קבוצה חדשה'));
        await tester.pumpAndSettle();
        expect(find.byType(PluginGroupEditor), findsOneWidget);
      },
    );

    testWidgets(
      'reordering visible members leaves hidden slots and folder order intact',
      (
        tester,
      ) async {
        final groups = [
          _group('g', ['a', 'b', 'c'], name: 'קבוצה א'),
          _group('h', ['x', 'y'], name: 'קבוצה ב'),
        ];
        await pumpLauncher(
          tester,
          state: PluginSystemLoaded(
            [
              _plugin('a', 'הערות'),
              _plugin('x', 'כלי חיצוני א'),
              _plugin('b', 'מוסתר', showInTools: false),
              _plugin('y', 'כלי חיצוני ב'),
              _plugin('c', 'עורך'),
            ],
            groups: groups,
            groupsLoaded: true,
          ),
        );
        await tester.tap(find.text('קבוצה א'));
        await tester.pumpAndSettle();
        await menu(tester, 'הערות');
        await tester.tap(find.text('הזזה'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('הזז קדימה'));
        await tester.pumpAndSettle();
        final ids = pluginBloc.recorded
            .whereType<ReorderPluginsRequested>()
            .single
            .orderedPluginIds;
        expect(ids, ['c', 'x', 'b', 'y', 'a']);
        expect(
          collapsePluginGroups(
            ids.where((id) => id != 'b').map(_entry).toList(),
            groups,
          ).map((entry) => entry.toolId),
          ['plugin-group:g', 'plugin-group:h'],
        );
      },
    );

    Future<void> drag(
      WidgetTester tester,
      String source,
      String destination, {
      bool center = true,
    }) async {
      final gesture = await tester.startGesture(
        tester.getCenter(tile(source)),
        kind: PointerDeviceKind.mouse,
      );
      final target = tester.getRect(tile(destination));
      if (center) {
        await gesture.moveTo(target.center + Offset(target.width * 0.45, 0));
        await tester.pump();
      }
      await gesture.moveTo(
        center ? target.center : target.center + Offset(-target.width / 4, 0),
      );
      await tester.pump();
      if (center) {
        expect(
          find.byKey(const Key('plugin-group-drop-indicator')),
          findsOneWidget,
        );
        expect(find.byKey(kToolDropIndicatorKey), findsNothing);
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('center drop moves a plugin into a folder without reordering', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await pumpLauncher(tester);
        await drag(tester, 'חזרות', 'כתיבה');
        final move = pluginBloc.recorded
            .whereType<MovePluginToGroupRequested>()
            .single;
        expect(move.pluginId, 'com.test.review');
        expect(move.groupId, 'writing');
        expect(
          pluginBloc.recorded.whereType<ReorderPluginsRequested>(),
          isEmpty,
        );
        expect(opened, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'dragging through an empty folder edge then center accepts the plugin',
      (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await pumpLauncher(
            tester,
            state: PluginSystemLoaded(
              plugins,
              groups: [_group('empty', [])],
              groupsLoaded: true,
            ),
          );
          await drag(tester, 'חזרות', 'כתיבה');
          final move = pluginBloc.recorded
              .whereType<MovePluginToGroupRequested>()
              .single;
          expect(move.pluginId, 'com.test.review');
          expect(move.groupId, 'empty');
          expect(
            pluginBloc.recorded.whereType<ReorderPluginsRequested>(),
            isEmpty,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('edge drop keeps folder block reordering', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await pumpLauncher(tester);
        await drag(tester, 'כתיבה', 'חזרות', center: false);
        final reorder = pluginBloc.recorded
            .whereType<ReorderPluginsRequested>()
            .single;
        expect(reorder.orderedPluginIds, [
          'com.test.review',
          'com.test.notes',
          'com.test.editor',
        ]);
        expect(
          pluginBloc.recorded.whereType<MovePluginToGroupRequested>(),
          isEmpty,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'center drop on another plugin opens an editor with both members',
      (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await pumpLauncher(
            tester,
            state: PluginSystemLoaded(plugins, groupsLoaded: true),
          );
          await drag(tester, 'הערות', 'עורך');
          final editor = tester.widget<PluginGroupEditor>(
            find.byType(PluginGroupEditor),
          );
          expect(editor.initialPluginIds, [
            'com.test.editor',
            'com.test.notes',
          ]);
          expect(
            pluginBloc.recorded.whereType<ReorderPluginsRequested>(),
            isEmpty,
          );
          expect(
            pluginBloc.recorded.whereType<CreatePluginGroupRequested>(),
            isEmpty,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    for (final brightness in Brightness.values) {
      for (final width in [360.0, 520.0]) {
        testWidgets(
          'folder layout $brightness width $width with enlarged text',
          (
            tester,
          ) async {
            final colors = AppThemeData.createColorScheme(
              AppSeedColors.brown,
              brightness,
            );
            await pumpLauncher(
              tester,
              width: width,
              textScale: 1.3,
              theme: brightness == Brightness.dark
                  ? AppThemeData.dark(colors, compactMenuMode: false)
                  : AppThemeData.light(colors, compactMenuMode: false),
            );
            expect(tester.takeException(), isNull);
            await verifyFolderAndPluginSurfaces(tester);
            await tester.tap(find.text('כתיבה'));
            await tester.pumpAndSettle();
            expect(surface(tester, 'הערות').color, Colors.transparent);
            expect(surface(tester, 'הערות').shape, AppTokens.roundedShape);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('white theme keeps folder tile and navigation usable', (
      tester,
    ) async {
      await pumpLauncher(
        tester,
        textScale: 1.3,
        theme: AppThemeData.light(
          AppThemeData.createColorScheme(AppSeedColors.white, Brightness.light),
          compactMenuMode: false,
        ),
      );
      await verifyFolderAndPluginSurfaces(tester);
      await tester.tap(find.text('כתיבה'));
      await tester.pumpAndSettle();
      expect(tile('הערות'), findsOneWidget);
      expect(surface(tester, 'הערות').color, Colors.transparent);
      expect(surface(tester, 'הערות').shape, AppTokens.roundedShape);
      expect(tester.takeException(), isNull);
    });
  });
}
