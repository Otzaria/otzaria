import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart' as snack;
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/dictionary/dictionary_context_menu_entries.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';

import '../../test_helpers/stub_navigation_bloc.dart';
import '../../test_helpers/stub_settings_bloc.dart';
import '../../test_helpers/stub_tabs_bloc.dart';

class _RecordingTabs extends StubTabsBloc {
  _RecordingTabs() : super(TabsState.initial());

  final recorded = <TabsEvent>[];

  @override
  void add(TabsEvent event) {
    recorded.add(event);
    super.add(event);
  }
}

class _RecordingNavigation extends StubNavigationBloc {
  final recorded = <NavigationEvent>[];

  @override
  void add(NavigationEvent event) {
    recorded.add(event);
    super.add(event);
  }
}

class _StubPlugins extends Cubit<PluginSystemState>
    implements PluginSystemBloc {
  _StubPlugins() : super(const PluginSystemLoaded([]));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final hidden in [false, true]) {
    testWidgets('פתיחה מהתפריט עם פיסוק מכבדת כלי מוסתר: $hidden', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = DictionaryLookupRepository(
        loadAramaicEntries: () async => const [
          AramaicDictionaryEntry(aramaic: 'ליה', hebrew: 'לו'),
        ],
      );
      await repository.ensureAramaicLoaded();
      final settings = StubSettingsBloc(
        SettingsState.initial().copyWith(
          hiddenBuiltInToolIds: hidden ? {'builtin.aramaic_dictionary'} : {},
        ),
      );
      final tabs = _RecordingTabs();
      final navigation = _RecordingNavigation();
      final plugins = _StubPlugins();
      addTearDown(settings.close);
      addTearDown(tabs.close);
      addTearDown(navigation.close);
      addTearDown(plugins.close);

      Widget wrap(Widget child) => MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<NavigationBloc>.value(value: navigation),
          BlocProvider<PluginSystemBloc>.value(value: plugins),
        ],
        child: MaterialApp(
          navigatorKey: snack.navigatorKey,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.3),
              ),
              child: Scaffold(body: child),
            ),
          ),
        ),
      );

      final key = GlobalKey<AppContextMenuRegionState>();
      await tester.pumpWidget(
        wrap(
          AppContextMenuRegion(
            key: key,
            menuBuilder: (context, _) => buildDictionaryContextMenuEntries(
              context: context,
              selectedText: ' ליה, ',
              repository: repository,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await key.currentState!.openMenuAt(const Offset(300, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('מילון ארמי-עברי'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('פתח במילון הארמי-עברי'));
      await tester.pump();

      ToolTab? tab;
      if (hidden) {
        expect(tabs.recorded, isEmpty);
        expect(navigation.recorded, isEmpty);
      } else {
        tab = tabs.recorded.whereType<OpenOrFocusTab>().single.tab as ToolTab;
        expect(tab.toolId, 'builtin.aramaic_dictionary');
        expect(
          navigation.recorded.whereType<NavigateToScreen>().single.screen,
          Screen.reading,
        );
        await tester.pumpWidget(
          wrap(
            AramaicDictionaryScreen(
              repository: repository,
              queryInbox: tab.queryInbox,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'ליה,',
        );
        expect(find.byType(AramaicResultCard), findsOneWidget);
        final result = tester.widget<AramaicResultCard>(
          find.byType(AramaicResultCard),
        );
        expect(result.aramaic, 'ליה');
        expect(find.text('לו'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      snack.UiSnack.hide();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tab?.dispose();
    });
  }
}
