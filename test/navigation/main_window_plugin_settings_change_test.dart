import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/theme/app_fonts.dart';

import '../helpers/memory_settings_cache.dart';
import 'small_screens/small_screens_fixture.dart';

void main() {
  Future<void> verifyFirstSettingsChange(
    WidgetTester tester, {
    required double initialFontSize,
    required SettingsEvent update,
    required List<String> expectedTopics,
  }) async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final repository = SettingsRepository();
    await repository.updateOfflineMode(true);
    await repository.updateFontSize(initialFontSize);
    final bloc = SettingsBloc(
      repository: repository,
      initialSettings: repository.readSettings(),
    );
    expect(bloc.state.fontSize, initialFontSize);
    addTearDown(bloc.close);
    const size = Size(1280, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wrap = smallScreenProviders(
      tester,
      screen: SmallScreen.home,
      size: size,
    );

    final topics = <String>[];
    final previousPrint = debugPrint;
    const prefix = 'PluginRuntimeDispatcher: Dispatching ';
    debugPrint = (message, {wrapWidth}) {
      if (message != null && message.startsWith(prefix)) {
        topics.add(message.substring(prefix.length));
      }
    };
    try {
      await tester.pumpWidget(
        wrap(
          BlocProvider<SettingsBloc>.value(
            value: bloc,
            child: const MaterialApp(
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: [Locale('he', 'IL')],
              locale: Locale('he', 'IL'),
              home: MainWindowScreen(),
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      topics.clear();

      bloc.add(update);
      await tester.pump();
      await tester.pump();

      expect(
        topics.where(
          (topic) => topic == 'settings.changed' || topic == 'theme.changed',
        ),
        expectedTopics,
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugPrint = previousPrint;
    }
  }

  testWidgets('שינוי ראשון מגופן שמור ל־25 נשלח לתוספים', (tester) async {
    await verifyFirstSettingsChange(
      tester,
      initialFontSize: 16,
      update: const UpdateFontSize(AppFonts.defaultReadingSize),
      expectedTopics: ['settings.changed', 'theme.changed'],
    );
  });

  testWidgets('שינוי שפת ההגדרות אינו מדווח על שינוי בגופן שמור', (
    tester,
  ) async {
    await verifyFirstSettingsChange(
      tester,
      initialFontSize: 30,
      update: const UpdateSettingsLanguageCode('en'),
      expectedTopics: ['settings.changed'],
    );
  });
}
