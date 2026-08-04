import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';

InstalledPlugin _plugin(
  String id, {
  String? title,
  int order = 900,
  int? userOrder,
  bool enabled = true,
  bool showInTools = true,
  bool pinnedToNavRail = false,
  bool allowOrderBeforeBuiltIns = false,
  bool allowOrderGranted = true,
  bool networkEnabled = false,
  bool networkAccessGranted = false,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: title ?? id,
    version: '1.0.0',
    installPath: '/plugins/$id',
    entrypointPath: 'index.html',
    enabled: enabled,
    pinned: false,
    pinnedToNavRail: pinnedToNavRail,
    showInTools: showInTools,
    allowOrderBeforeBuiltInsGranted: allowOrderGranted,
    networkAccessGranted: networkAccessGranted,
    manifest: PluginManifest(
      schemaVersion: 1,
      id: id,
      name: title ?? id,
      version: '1.0.0',
      description: 'test',
      author: 'tester',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '1.0.0',
      sdkVersion: '1.x',
      permissions: const [],
      networkEnabled: networkEnabled,
      networkAllowlist: const [],
      toolTabTitle: title ?? id,
      toolTabOrder: order,
      allowOrderBeforeBuiltIns: allowOrderBeforeBuiltIns,
      defaultPinned: false,
      publishedDataTypes: const [],
    ),
    installedAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    userOrder: userOrder,
  );
}

void main() {
  group('buildToolCatalog', () {
    test('כולל את כל הכלים המובנים כשאין הסתרות', () {
      final entries = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemInitial(),
      );
      expect(entries.map((e) => e.toolId), contains('builtin.calendar'));
      expect(entries.map((e) => e.toolId), contains('builtin.gematria'));
      expect(entries.every((e) => !e.isPlugin), isTrue);
    });

    test('מסנן כלי מובנה מוסתר', () {
      final entries = buildToolCatalog(
        hiddenBuiltInToolIds: const {'builtin.calendar'},
        isOfflineMode: false,
        pluginState: PluginSystemInitial(),
      );
      expect(
        entries.map((e) => e.toolId),
        isNot(contains('builtin.calendar')),
      );
    });

    test('מסנן תוסף מושבת ותוסף מוסתר מהממשק', () {
      final entries = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemLoaded([
          _plugin('p.on'),
          _plugin('p.disabled', enabled: false),
          _plugin('p.hidden', showInTools: false),
        ]),
      );
      final ids = entries.map((e) => e.toolId);
      expect(ids, contains('p.on'));
      expect(ids, isNot(contains('p.disabled')));
      expect(ids, isNot(contains('p.hidden')));
    });

    test('תוסף מוצמד-לסרגל מופיע גם כשהוא מוסתר מהממשק', () {
      final entries = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemLoaded([
          _plugin('p.pinned', showInTools: false, pinnedToNavRail: true),
        ]),
      );
      expect(entries.map((e) => e.toolId), contains('p.pinned'));
    });

    test('מצב מנותק מסנן תוסף שדורש רשת והרשאתו הוענקה', () {
      final plugins = [
        _plugin('p.net', networkEnabled: true, networkAccessGranted: true),
        // הרשאת רשת כבויה — התוסף אינו ניגש לרשת ולכן נשאר זמין
        _plugin('p.net.off', networkEnabled: true, networkAccessGranted: false),
      ];
      final online = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemLoaded(plugins),
      ).map((e) => e.toolId);
      final offline = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: true,
        pluginState: PluginSystemLoaded(plugins),
      ).map((e) => e.toolId);

      expect(online, contains('p.net'));
      expect(offline, isNot(contains('p.net')));
      expect(offline, contains('p.net.off'));
    });

    test('כלים מובנים מופיעים לפני תוספים גם כשה-order של התוסף נמוך', () {
      final entries = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemLoaded([_plugin('p.early', order: 1)]),
      );
      final pluginIndex = entries.indexWhere((e) => e.toolId == 'p.early');
      final lastBuiltIn = entries.lastIndexWhere((e) => !e.isPlugin);
      expect(pluginIndex, greaterThan(lastBuiltIn));
    });

    test('תוסף שאושר להקדים כלים מובנים מופיע לפניהם', () {
      final entries = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemLoaded([
          _plugin('p.first', order: 1, allowOrderBeforeBuiltIns: true),
        ]),
      );
      expect(entries.first.toolId, 'p.first');
    });

    // המיון חייב להיות יציב: תוספים רבים חולקים את order 900 מברירת המחדל
    // של המניפסט, והסדר ביניהם נקבע כבר ב-repository.
    test('המיון יציב עבור רשומות עם אותו order', () {
      final entries = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemLoaded([
          _plugin('p.a'),
          _plugin('p.b'),
          _plugin('p.c'),
        ]),
      );
      final pluginIds = entries
          .where((e) => e.isPlugin)
          .map((e) => e.toolId)
          .toList();
      expect(pluginIds, ['p.a', 'p.b', 'p.c']);
    });

    test('סדר ידני של המשתמש גובר על ה-order מהמניפסט', () {
      final entries = buildToolCatalog(
        hiddenBuiltInToolIds: const {},
        isOfflineMode: false,
        pluginState: PluginSystemLoaded([
          _plugin('p.second', userOrder: 1),
          _plugin('p.first', userOrder: 0),
        ]),
      );
      final pluginIds = entries
          .where((e) => e.isPlugin)
          .map((e) => e.toolId)
          .toList();
      expect(pluginIds, ['p.first', 'p.second']);
    });
  });

  group('lookupTool', () {
    ToolLookupResult lookup(
      String toolId, {
      Set<String> hidden = const {},
      bool offline = false,
      PluginSystemState? state,
    }) => lookupTool(
      toolId,
      hiddenBuiltInToolIds: hidden,
      isOfflineMode: offline,
      pluginState: state ?? PluginSystemLoaded(const []),
    );

    test('כלי מובנה זמין', () {
      final result = lookup('builtin.calendar');
      expect(result, isA<ToolAvailable>());
      expect((result as ToolAvailable).entry.label, 'לוח שנה');
    });

    test('כלי מובנה מוסתר מדווח סיבה ושם', () {
      final result = lookup(
        'builtin.calendar',
        hidden: const {'builtin.calendar'},
      );
      expect(result, isA<ToolUnavailable>());
      expect(
        (result as ToolUnavailable).reason,
        ToolUnavailableReason.builtInHidden,
      );
      expect(result.name, 'לוח שנה');
    });

    // תוספים נטענים אסינכרונית: לפני PluginSystemLoaded אסור להכריז
    // "לא נמצא" — הטאב צריך להציג טעינה.
    test('לפני טעינת התוספים מדווח loading ולא notFound', () {
      final result = lookup('p.x', state: PluginSystemInitial());
      expect(
        (result as ToolUnavailable).reason,
        ToolUnavailableReason.loading,
      );
    });

    test('תוסף לא קיים', () {
      final result = lookup('p.missing');
      expect(
        (result as ToolUnavailable).reason,
        ToolUnavailableReason.notFound,
      );
    });

    test('תוסף מושבת / מוסתר / דורש אינטרנט', () {
      final state = PluginSystemLoaded([
        _plugin('p.off', title: 'כבוי', enabled: false),
        _plugin('p.hidden', title: 'מוסתר', showInTools: false),
        _plugin(
          'p.net',
          title: 'רשת',
          networkEnabled: true,
          networkAccessGranted: true,
        ),
      ]);
      expect(
        (lookup('p.off', state: state) as ToolUnavailable).reason,
        ToolUnavailableReason.pluginDisabled,
      );
      expect(
        (lookup('p.hidden', state: state) as ToolUnavailable).reason,
        ToolUnavailableReason.pluginHiddenFromTools,
      );
      expect(
        (lookup('p.net', state: state, offline: true) as ToolUnavailable)
            .reason,
        ToolUnavailableReason.pluginRequiresInternet,
      );
      expect(lookup('p.net', state: state), isA<ToolAvailable>());
    });
  });
}
