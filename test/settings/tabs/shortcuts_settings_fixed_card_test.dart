import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/search/settings_search_index.dart';
import 'package:otzaria/settings/tabs/shortcuts_settings_tab.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

import '../../helpers/memory_settings_cache.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPluginSystemBloc
    extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

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

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('קיצורים קבועים (issue #5819): כרטיס לקריאה בלבד עם '
      'מעבר בין כרטיסיות ומסך מלא', (tester) async {
    await tester.pumpWidget(_buildTab());

    final card = find.byWidgetPredicate(
      (w) => w is SettingsCard && w.cardId == 'shortcuts.fixed',
    );
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.text(
          'תלוי במסך, במיקוד ובהגדרות',
        ),
      ),
      findsOneWidget,
    );

    const rows = {
      'הכרטיסייה הבאה': 'CTRL + TAB',
      'הכרטיסייה הקודמת': 'CTRL + SHIFT + TAB',
      'מעבר לכרטיסייה לפי מיקומה': 'CTRL + 1–8',
      'הכרטיסייה האחרונה': 'CTRL + 9',
      'מסך מלא': 'F11',
      'יציאה ממסך מלא': 'ESC',
    };
    for (final MapEntry(key: title, value: keys) in rows.entries) {
      final row = find.descendant(
        of: card,
        matching: find.ancestor(
          of: find.text(title),
          matching: find.byType(SettingsActionTile),
        ),
      );
      expect(row, findsOneWidget, reason: title);
      expect(
        find.descendant(of: row, matching: find.text(keys)),
        findsOneWidget,
        reason: title,
      );
    }

    // לקריאה בלבד: אין שדה בחירה, כפתור או פעולת הקשה בכרטיס.
    expect(
      find.descendant(
        of: card,
        matching: find.byType(AppDropdownField<String>),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.byType(ActionButton)),
      findsNothing,
    );
    for (final tile in tester.widgetList<SettingsActionTile>(
      find.descendant(of: card, matching: find.byType(SettingsActionTile)),
    )) {
      expect(tile.onTap, isNull);
    }
  });

  test('קיצורים קבועים (issue #5819): חיפוש בהגדרות מוצא את הכרטיס', () {
    for (final query in ['ctrl+tab', 'מעבר בין כרטיסיות']) {
      final results = SettingsSearchIndex.search(query);
      expect(
        results.map((entry) => entry.cardId),
        contains('shortcuts.fixed'),
        reason: query,
      );
    }
  });
}
