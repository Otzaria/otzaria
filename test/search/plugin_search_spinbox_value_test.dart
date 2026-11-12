import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bridge/plugin_search_api.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/theme_exports.dart';

import '../support/golden_fonts.dart';

void main() {
  late ThemeData theme;
  setUpAll(() async {
    // ה-fixture העברי של DD-22 מונע מדידת תוויות UI כריבועי Ahem.
    await loadGoldenFonts();
    debugDefaultTargetPlatformOverride = goldenPlatform;
    try {
      theme = AppThemeData.light(
        AppThemeData.createColorScheme(
          AppSeedColors.defaultLight,
          Brightness.light,
        ),
        compactMenuMode: false,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  Future<SearchBloc> pumpSetting(
    WidgetTester tester, {
    required bool count,
    int value = 40,
  }) async {
    final parsed = PluginOpenSearchTabSettings.parse({
      'mode': 'advanced',
      if (count) 'wordMatchMode': 'atLeast',
      count ? 'wordMatchCount' : 'distance': value,
    }, query: 'חייב להחזיר');
    final tab = SearchingTab(
      'חיפוש',
      null,
      initialConfiguration: SearchConfiguration(
        searchMode: parsed.searchMode,
        distance: parsed.distance,
        wordMatchMode: parsed.wordMatchMode,
        wordMatchCount: parsed.wordMatchCount,
      ),
    );
    final bloc = tab.searchBloc;
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BlocProvider<SearchBloc>.value(
            value: bloc,
            child: Scaffold(
              body: FuzzyDistance(tab: tab, triggerSearch: false),
            ),
          ),
        ),
      ),
    );
    return bloc;
  }

  String text(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  int valueOf(SearchBloc bloc, bool count) => count
      ? bloc.state.configuration.wordMatchCount
      : bloc.state.configuration.distance;

  for (final count in [false, true]) {
    final name = count ? 'מספר מילים' : 'מרווח';
    testWidgets('$name מתוסף מוצג כמו במודל והקלדת הגבול מעדכנת אותו', (
      tester,
    ) async {
      final bloc = await pumpSetting(tester, count: count);
      expect(valueOf(bloc, count), 40);
      expect(text(tester), '40');

      await tester.enterText(find.byType(EditableText), '30');
      await tester.pumpAndSettle();

      expect(valueOf(bloc, count), 30);
      expect(text(tester), '30');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name חיצוני מתעדכן ללא החלפת הרכיב וניתן להקטנה', (
      tester,
    ) async {
      final bloc = await pumpSetting(tester, count: count, value: 5);
      final initialState = tester.state<SpinBoxState>(find.byType(SpinBox));
      bloc.add(
        count
            ? UpdateWordMatchModeWithoutSearch(
                bloc.state.configuration.wordMatchMode,
                count: 40,
              )
            : UpdateDistanceWithoutSearch(40),
      );
      await tester.pumpAndSettle();

      expect(
        tester.state<SpinBoxState>(find.byType(SpinBox)),
        same(initialState),
      );
      expect(valueOf(bloc, count), 40);
      expect(text(tester), '40');

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(valueOf(bloc, count), 39);
      expect(text(tester), '39');
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name בגבול uint32 נשמר בתצוגה', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const maxUint32 = 4294967295;
      final bloc = await pumpSetting(tester, count: count, value: maxUint32);
      expect(valueOf(bloc, count), maxUint32);
      expect(text(tester), '$maxUint32');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('מעבר ממרווח גדול למקורב שומר את השדה והמודל בטווח 0–2', (
    tester,
  ) async {
    final bloc = await pumpSetting(tester, count: false);
    bloc.add(SetSearchModeWithoutSearch(SearchMode.fuzzy));
    await tester.pumpAndSettle();

    expect(bloc.state.configuration.distance, inInclusiveRange(0, 2));
    expect(tester.widget<SpinBox>(find.byType(SpinBox)).max, 2);
    expect(text(tester), '${bloc.state.configuration.distance}');
    expect(tester.takeException(), isNull);
  });
}
