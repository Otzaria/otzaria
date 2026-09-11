// סימון גופן שאינו ממפה טעמים בבורר הגופנים (issue #1028): המשתמש גילה זאת
// עד היום רק כשפתח תנ"ך.

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/tabs/text_settings_tab.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpTab(WidgetTester tester, String fontFamily) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<SettingsBloc>.value(
            value: _TestSettingsBloc(
              SettingsState.initial().copyWith(fontFamily: fontFamily),
            ),
            child: const TextSettingsTab(isDialog: true),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('גופן ללא טעמים מסומן באזהרה בשדה הסגור', (tester) async {
    await pumpTab(tester, 'Rubik');

    expect(find.byIcon(FluentIcons.info_16_regular), findsOneWidget);
  });

  testWidgets('גופן תומך אינו מסומן', (tester) async {
    await pumpTab(tester, 'FrankRuhlCLM');

    expect(find.byIcon(FluentIcons.info_16_regular), findsNothing);
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
