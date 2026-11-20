// issue #4937: אפשרות "כותרת בלבד" בהעתקת הכותרת.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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

  testWidgets('כרטיס ההעתקה מציג "כותרת בלבד" ושולח path_only', (
    tester,
  ) async {
    final settings = _TestSettingsBloc(SettingsState.initial());
    addTearDown(settings.close);
    await tester.binding.setSurfaceSize(const Size(1400, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<SettingsBloc>.value(
            value: settings,
            child: const TextSettingsTab(),
          ),
        ),
      ),
    );
    await tester.pump();

    final option = find.text('כותרת בלבד');
    expect(option, findsOneWidget);
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();

    expect(settings.events.whereType<UpdateCopyWithHeaders>(), [
      const UpdateCopyWithHeaders('path_only'),
    ]);
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) => events.add(event));
  }

  final List<SettingsEvent> events = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
