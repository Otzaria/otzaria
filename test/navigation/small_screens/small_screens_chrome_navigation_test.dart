import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/layout/chrome_auto_hide.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';
import 'small_screens_fixture.dart';

class _ReaderBloc extends Cubit<TextBookState> implements TextBookBloc {
  _ReaderBloc(super.initialState);
  @override
  void add(dynamic event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SearchBloc extends SearchBloc {
  @override
  void add(SearchEvent event) {}
}

Future<TabsBloc> _pumpWindow(
  WidgetTester tester, {
  Size size = const Size(360, 640),
}) async {
  await Settings.init(cacheProvider: MemorySettingsCache());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final wrap = smallScreenProviders(
    tester,
    screen: SmallScreen.reader,
    size: size,
  );
  final colors = AppThemeData.createColorScheme(
    AppSeedColors.defaultLight,
    Brightness.light,
  );
  await tester.pumpWidget(
    wrap(
      MaterialApp(
        localizationsDelegates: const [
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('he', 'IL')],
        locale: const Locale('he', 'IL'),
        theme: AppThemeData.light(colors, compactMenuMode: false),
        home: const MainWindowScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.element(find.byType(MainWindowScreen)).read<TabsBloc>();
}

ChromeAutoHideController _controller(WidgetTester tester) => tester
    .widget<ChromeAutoHideScope>(find.byType(ChromeAutoHideScope))
    .notifier!;

void _publish(TabsBloc bloc, TabsState state) => (bloc as dynamic).emit(state);

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
  });
  for (final replacement in [
    'close active',
    'workspace',
    'active pane',
    'search',
  ]) {
    testWidgets('$replacement at unchanged index reveals chrome', (
      tester,
    ) async {
      final tabs = await _pumpWindow(
        tester,
        size: replacement == 'active pane'
            ? const Size(1024, 600)
            : const Size(360, 640),
      );
      final original = tabs.state.currentTab! as TextBookTab;
      final other = replacement == 'search'
          ? SearchingTab(
              'חיפוש',
              '',
              searchBloc: _SearchBloc(),
              autoRunInitialSearch: false,
            )
          : TextBookTab(
              book: original.book,
              index: 0,
              blocOverride: _ReaderBloc(original.bloc.state),
            );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        other.dispose();
      });
      if (replacement == 'close active') {
        _publish(tabs, tabs.state.copyWith(tabs: [original, other]));
      } else if (replacement == 'active pane') {
        _publish(
          tabs,
          tabs.state.copyWith(
            tabs: [CombinedTab(rightTab: original, leftTab: other)],
            activePane: ActivePaneUpdate.set(original),
          ),
        );
      }
      await tester.pumpAndSettle();
      final chrome = _controller(tester)..hide();
      await tester.pumpAndSettle();
      expect(chrome.visible, isFalse);
      _publish(
        tabs,
        replacement == 'active pane'
            ? tabs.state.copyWith(activePane: ActivePaneUpdate.set(other))
            : tabs.state.copyWith(tabs: [other], currentTabIndex: 0),
      );
      await tester.pumpAndSettle();
      expect(chrome.visible, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unrelated tab changes keep chrome hidden', (tester) async {
    final tabs = await _pumpWindow(tester);
    final chrome = _controller(tester)..hide();
    await tester.pumpAndSettle();
    final shell = tester.widget<ChromeAutoHideScope>(
      find.byType(ChromeAutoHideScope),
    );
    for (var i = 0; i < 10; i++) {
      _publish(tabs, tabs.state.copyWith(forceUpdate: true));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(chrome.visible, isFalse);
    expect(
      tester.widget<ChromeAutoHideScope>(find.byType(ChromeAutoHideScope)),
      same(shell),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
