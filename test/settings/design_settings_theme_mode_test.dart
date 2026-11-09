// בורר "ערכת נושא" שולח אירוע אחד, UpdateThemeMode, לכל בחירה. קודם בחירה
// של בהיר או כהה שלחה שני אירועים, וכל אחד בנה מחדש את MaterialApp (UI-137).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/tabs/design_settings_tab.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    registerFallbackValue(const UpdateThemeMode(ThemeMode.system));
  });

  Future<_MockSettingsBloc> pumpTab(
    WidgetTester tester,
    SettingsState state,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bloc = _MockSettingsBloc();
    whenListen(bloc, const Stream<SettingsState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<SettingsBloc>.value(
            value: bloc,
            child: const DesignSettingsTab(),
          ),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  for (final (label, mode, initial) in [
    (
      'כהה',
      ThemeMode.dark,
      SettingsState.initial().copyWith(followSystemTheme: true),
    ),
    (
      'בהיר',
      ThemeMode.light,
      SettingsState.initial().copyWith(
        followSystemTheme: false,
        isDarkMode: true,
      ),
    ),
    (
      'מערכת',
      ThemeMode.system,
      SettingsState.initial().copyWith(followSystemTheme: false),
    ),
  ]) {
    testWidgets('בחירת "$label" שולחת אירוע אחד: UpdateThemeMode($mode)', (
      tester,
    ) async {
      final bloc = await pumpTab(tester, initial);

      final option = find.text(label).first;
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump();

      final sent = verify(() => bloc.add(captureAny())).captured;
      expect(sent, [UpdateThemeMode(mode)]);
    });
  }
}
