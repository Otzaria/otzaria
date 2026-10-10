import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/shortcuts/view/shortcut_dropdown_tile.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';

import '../../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPluginSystemBloc
    extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

/// סופר פניות לאחסון ההגדרות; כל קריאת קיצור עוברת דרך containsKey.
class _CountingSettingsCache extends MemorySettingsCache {
  int reads = 0;

  @override
  bool containsKey(String key) {
    reads++;
    return super.containsKey(key);
  }
}

void _registerPluginShortcuts(int count) {
  const letters = 'qwertyuiopasdfghjklzxcvbnm';
  ShortcutValidator.registerPluginShortcuts({
    for (var i = 0; i < count; i++)
      ShortcutValidator.pluginShortcutKey('p$i', 's'): (
        pluginId: 'p$i',
        shortcutId: 's',
        label: 'תוסף $i',
        defaultKey: 'ctrl+alt+${letters[i]}',
        command: 'run',
        contextMenuItemId: null,
      ),
  });
}

Widget _buildTab() {
  final settingsBloc = _MockSettingsBloc();
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  final pluginBloc = _MockPluginSystemBloc();
  whenListen(
    pluginBloc,
    const Stream<PluginSystemState>.empty(),
    initialState: PluginSystemInitial(),
  );
  return MaterialApp(
    navigatorKey: navigatorKey,
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PluginSystemBloc>.value(value: pluginBloc),
        ],
        child: const ShortcutsSettingsTab(),
      ),
    ),
  );
}

/// הסינון המקורי של האריח: כל מפתח אחר נקרא ישירות מההגדרות.
Set<String> _expectedEntries(ShortcutDropDownTile tile) {
  final current =
      ShortcutValidator.getShortcutValue(tile.settingKey) ?? tile.selected;
  final used = <String>{};
  for (final key in ShortcutValidator.shortcutKeys) {
    if (key != tile.settingKey &&
        !ShortcutValidator.canShareShortcut(tile.settingKey, key)) {
      final value = ShortcutValidator.getShortcutValue(key);
      if (value != null && value.isNotEmpty) used.add(value);
    }
  }
  return {
    '__custom__',
    '__clear__',
    for (final entry in tile.allShortcuts.entries)
      if (entry.key == current || !used.contains(entry.key)) entry.key,
    if (!tile.allShortcuts.containsKey(current)) current,
  };
}

void main() {
  late _CountingSettingsCache cache;

  setUp(() async {
    cache = _CountingSettingsCache();
    await Settings.init(cacheProvider: cache);
  });

  tearDown(() => ShortcutValidator.registerPluginShortcuts(const {}));

  for (final pluginCount in [0, 10]) {
    testWidgets(
      'בניית הלשונית קוראת כל קיצור פעם אחת ולא פעם לכל אריח '
      '($pluginCount קיצורי תוספים)',
      (tester) async {
        _registerPluginShortcuts(pluginCount);
        cache.reads = 0;

        await tester.pumpWidget(_buildTab());

        expect(find.byType(ShortcutDropDownTile), findsAtLeastNWidgets(30));
        // לפני: 2,210 ו-35,390 פניות (מספר האריחים כפול מספר המפתחות).
        expect(cache.reads, lessThan(pluginCount == 0 ? 600 : 4000));
      },
    );
  }

  testWidgets('כל אריח מציע בדיוק את הקיצורים שאינם תפוסים בידי מפתח אחר', (
    tester,
  ) async {
    _registerPluginShortcuts(5);
    await Settings.setValue<String>('key-shortcut-open-find-ref', 'ctrl+y');
    await Settings.setValue<String>('key-shortcut-open-bookmarks', '');

    await tester.pumpWidget(_buildTab());

    final tiles = tester
        .widgetList<ShortcutDropDownTile>(find.byType(ShortcutDropDownTile))
        .toList();
    expect(tiles, isNotEmpty);
    for (final tile in tiles) {
      final field = tester.widget<AppDropdownField<String>>(
        find.descendant(
          of: find.byWidget(tile),
          matching: find.byType(AppDropdownField<String>),
        ),
      );
      expect(
        field.entries.map((e) => e.value).toSet(),
        _expectedEntries(tile),
        reason: tile.settingKey,
      );
    }
  });
}
