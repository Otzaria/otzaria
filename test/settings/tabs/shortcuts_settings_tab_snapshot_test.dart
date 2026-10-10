import 'dart:convert';

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
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_registry.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/shortcuts/view/shortcut_dropdown_tile.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';

import '../../helpers/memory_settings_cache.dart';

class _PluginBloc extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

Widget _buildTab(SettingsBloc settings) {
  final plugins = _PluginBloc();
  whenListen(
    plugins,
    const Stream<PluginSystemState>.empty(),
    initialState: PluginSystemInitial(),
  );
  return MaterialApp(
    navigatorKey: navigatorKey,
    locale: const Locale('he'),
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<PluginSystemBloc>.value(value: plugins),
        ],
        child: const ShortcutsSettingsTab(),
      ),
    ),
  );
}

AppDropdownField<String> _fieldFor(WidgetTester tester, String settingKey) {
  final tile = find.byWidgetPredicate(
    (widget) =>
        widget is ShortcutDropDownTile && widget.settingKey == settingKey,
  );
  return tester.widget<AppDropdownField<String>>(
    find.descendant(of: tile, matching: find.byType(AppDropdownField<String>)),
  );
}

Iterable<String> _entries(WidgetTester tester, String settingKey) =>
    _fieldFor(tester, settingKey).entries.map((entry) => entry.value);

Future<void> _changeShortcut(
  WidgetTester tester,
  SettingsBloc settings,
  void Function() action,
) async {
  await tester.runAsync(() async {
    final changed = settings.stream.first;
    action();
    await changed;
  });
  await tester.pumpAndSettle();
}

void main() {
  late SettingsBloc settings;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    settings = SettingsBloc(repository: SettingsRepository());
  });

  tearDown(() async {
    DynamicShortcutRegistry.instance.clear();
    await settings.close();
  });

  // הקובץ נפרד כדי שה-singleton יתחיל ללא טעינה בבדיקה הראשונה.
  testWidgets('פתיחה ראשונה מסננת קיצור דינמי שמור בכל האריחים', (
    tester,
  ) async {
    const shortcut = DynamicShortcut(
      id: 'saved',
      key: 'ctrl+q',
      kind: DynamicShortcutKind.setTextDisplay,
      change: DynamicDisplayChange(nikud: DynamicMarkChange.hide),
    );
    await Settings.setValue(
      DynamicShortcutRegistry.settingsKey,
      jsonEncode([shortcut.toJson()]),
    );
    expect(
      ShortcutValidator.shortcutKeys.where(
        (key) => key.startsWith('key-shortcut-dynamic-'),
      ),
      isEmpty,
    );

    await tester.pumpWidget(_buildTab(settings));
    expect(
      ShortcutValidator.shortcutKeys,
      contains(shortcut.settingKey),
    );
    final tiles = tester.widgetList<ShortcutDropDownTile>(
      find.byType(ShortcutDropDownTile),
    );
    expect(tiles, isNotEmpty);
    for (final tile in tiles) {
      expect(
        _entries(tester, tile.settingKey),
        isNot(contains(shortcut.key)),
        reason: tile.settingKey,
      );
    }

    const libraryKey = 'key-shortcut-open-library-browser';
    _fieldFor(tester, libraryKey).onSelected?.call(shortcut.key);
    await tester.pump();
    expect(settings.state.shortcuts, isEmpty);
    expect(find.textContaining('הסתר ניקוד'), findsAtLeastNWidgets(1));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(_entries(tester, libraryKey), contains('ctrl+u'));
    DynamicShortcutRegistry.instance.put(shortcut.copyWith(key: 'ctrl+u'));
    await tester.pumpAndSettle();
    expect(_entries(tester, libraryKey), contains('ctrl+q'));
    expect(_entries(tester, libraryKey), isNot(contains('ctrl+u')));

    DynamicShortcutRegistry.instance.remove(shortcut.id);
    await tester.pumpAndSettle();
    expect(_entries(tester, libraryKey), contains('ctrl+u'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('שינוי, ביטול ואיפוס מרעננים את הצירופים המוצעים', (
    tester,
  ) async {
    const libraryKey = 'key-shortcut-open-library-browser';
    const otherKey = 'key-shortcut-open-find-ref';
    await tester.pumpWidget(_buildTab(settings));
    expect(_entries(tester, otherKey), isNot(contains('ctrl+l')));

    await _changeShortcut(
      tester,
      settings,
      () => _fieldFor(tester, libraryKey).onSelected?.call('ctrl+q'),
    );
    expect(settings.state.shortcuts[libraryKey], 'ctrl+q');
    expect(_fieldFor(tester, libraryKey).value, 'ctrl+q');
    expect(_entries(tester, otherKey), contains('ctrl+l'));
    expect(_entries(tester, otherKey), isNot(contains('ctrl+q')));

    await _changeShortcut(
      tester,
      settings,
      () => _fieldFor(tester, libraryKey).onSelected?.call('__clear__'),
    );
    expect(settings.state.shortcuts[libraryKey], '');
    expect(find.text('ספרייה'), findsNothing);
    expect(_entries(tester, otherKey), contains('ctrl+q'));

    await _changeShortcut(
      tester,
      settings,
      () => settings.add(ResetShortcuts()),
    );
    expect(_fieldFor(tester, libraryKey).value, 'ctrl+l');
    expect(_entries(tester, otherKey), isNot(contains('ctrl+l')));
    expect(_entries(tester, otherKey), contains('ctrl+q'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
