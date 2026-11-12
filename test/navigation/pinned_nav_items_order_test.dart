import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

InstalledPlugin _plugin(String id, {bool pinnedToNavRail = true}) =>
    InstalledPlugin(
      pluginId: id,
      name: id,
      version: '1.0.0',
      installPath: '/plugins/$id',
      entrypointPath: 'index.html',
      enabled: true,
      pinned: false,
      pinnedToNavRail: pinnedToNavRail,
      showInTools: true,
      networkAccessGranted: false,
      manifest: PluginManifest(
        schemaVersion: 1,
        id: id,
        name: id,
        version: '1.0.0',
        description: 'test',
        author: 'tester',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: id,
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
        toolTabIconName: 'apps',
      ),
      installedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

List<String> _pinned({
  Set<String> pinnedBuiltIns = const {},
  Set<String> hiddenBuiltIns = const {},
  List<String> order = const [],
  List<InstalledPlugin> plugins = const [],
  bool offline = false,
}) => MainWindowScreenState.pinnedToolIdsForNavRail(
  pluginState: PluginSystemLoaded(plugins),
  pinnedBuiltInIds: pinnedBuiltIns,
  hiddenBuiltInIds: hiddenBuiltIns,
  isOfflineMode: offline,
  builtInToolsOrder: order,
);

/// סרגל הניווט חייב להציג את הכלים המוצמדים באותו סדר שהמשתמש רואה במשגר
/// הכלים — אחרת אותו כלי יושב בשני מקומות שונים בשני מסכים.
void main() {
  test('בלי סדר מותאם: הסדר לפי שדה order של הקטלוג', () {
    expect(
      _pinned(
        pinnedBuiltIns: const {'builtin.measurements', 'builtin.notes'},
      ),
      ['builtin.notes', 'builtin.measurements'],
    );
  });

  test('סדר מותאם של המשתמש נשמר גם בסרגל', () {
    expect(
      _pinned(
        pinnedBuiltIns: const {'builtin.measurements', 'builtin.notes'},
        order: const ['builtin.measurements', 'builtin.notes'],
      ),
      ['builtin.measurements', 'builtin.notes'],
    );
  });

  test('כלי מוסתר שהוצמד בעבר אינו מופיע', () {
    expect(
      _pinned(
        pinnedBuiltIns: const {'builtin.calendar', 'builtin.gematria'},
        hiddenBuiltIns: const {'builtin.calendar'},
      ),
      ['builtin.gematria'],
    );
  });

  test('כלים מובנים לפני תוספים', () {
    expect(
      _pinned(
        pinnedBuiltIns: const {'builtin.calendar'},
        plugins: [_plugin('com.example.a')],
      ),
      ['builtin.calendar', 'com.example.a'],
    );
  });

  test('תוסף שאינו מוצמד אינו מופיע', () {
    expect(
      _pinned(plugins: [_plugin('com.example.a', pinnedToNavRail: false)]),
      isEmpty,
    );
  });

  test('מזהה בסדר השמור שאינו מוצמד אינו מוסיף פריט', () {
    expect(
      _pinned(
        pinnedBuiltIns: const {'builtin.gematria'},
        order: const ['builtin.calendar', 'builtin.gematria'],
      ),
      ['builtin.gematria'],
    );
  });
}
