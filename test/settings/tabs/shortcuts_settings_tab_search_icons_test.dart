import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/shortcuts/view/shortcut_dropdown_tile.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../../helpers/memory_settings_cache.dart';

class _PluginBloc extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

/// שלוש שורות החיפוש בטאב הקיצורים (איתור, בכל הספרים, בספר הפתוח) מציירות
/// את האייקון באותו תא ובאותו גודל, גם כשהשורה עם כותרת משנה ונמצאת בכרטיס אחר.
void main() {
  testWidgets('אייקוני החיפוש בטאב הקיצורים באותו גודל', (tester) async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final settings = SettingsBloc(repository: SettingsRepository());
    final plugins = _PluginBloc();
    whenListen(
      plugins,
      const Stream<PluginSystemState>.empty(),
      initialState: PluginSystemInitial(),
    );
    tester.view.physicalSize = const Size(700, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cs = AppThemeData.createColorScheme(
      AppSeedColors.defaultLight,
      Brightness.light,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(cs, compactMenuMode: false),
        locale: const Locale('he', 'IL'),
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<PluginSystemBloc>.value(value: plugins),
            ],
            child: const ShortcutsSettingsTab(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Size iconBox(String key) {
      final tile = find.byWidgetPredicate(
        (w) => w is ShortcutDropDownTile && w.settingKey == key,
      );
      final icon = find.descendant(of: tile, matching: find.byType(Icon)).first;
      return tester.getSize(icon);
    }

    final sizes = {
      for (final key in const [
        'key-shortcut-open-find-ref',
        'key-shortcut-open-new-search',
        ShortcutValidator.currentWindowSearchKey,
      ])
        key: iconBox(key),
    };
    expect(sizes.values.toSet(), hasLength(1), reason: '$sizes');
    expect(sizes.values.first, const Size(24, 24));
  });
}
