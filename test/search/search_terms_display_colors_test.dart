import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../support/search_engine_test_init.dart';

class _StubSearchBloc extends SearchBloc {
  _StubSearchBloc(SearchState initialState) {
    emit(initialState);
  }
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  // Theme.primaryColor הוא surface במצב כהה, והקיצורים נעלמו ברקע הסרגל.
  group('SearchTermsDisplay — צבעי הקיצורים', () {
    for (final brightness in Brightness.values) {
      testWidgets('קידומת, "או", סיומת ומרווח ב-primary ($brightness)', (
        tester,
      ) async {
        final cs = AppThemeData.createColorScheme(
          brightness == Brightness.dark
              ? AppSeedColors.defaultDark
              : AppSeedColors.defaultLight,
          brightness,
        );
        final theme = brightness == Brightness.dark
            ? AppThemeData.dark(cs, compactMenuMode: false)
            : AppThemeData.light(cs, compactMenuMode: false);
        final tab = SearchingTab('חיפוש', null);
        tab.useGlobalSearchOptions.value = false;
        tab.searchOptions['מכשילן_0'] = {'קידומות': true, 'סיומות': true};
        tab.alternativeWords[0] = ['מכשילים'];
        tab.spacingValues['0-1'] = '3';
        final bloc = _StubSearchBloc(
          const SearchState(searchQuery: 'מכשילן לעתיד'),
        );
        addTearDown(() async {
          tab.dispose();
          await bloc.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: BlocProvider<SearchBloc>.value(
                value: bloc,
                child: SizedBox(
                  width: 600,
                  child: SearchTermsDisplay(tab: tab),
                ),
              ),
            ),
          ),
        );

        final root = tester.widget<RichText>(find.byType(RichText)).text;
        final colors = <String, Color?>{};
        root.visitChildren((span) {
          if (span is TextSpan && span.text != null) {
            colors[span.text!] = span.style?.color;
          }
          return true;
        });

        for (final text in ['(ק)', 'או', '(ס)', '₃']) {
          expect(colors[text], cs.primary, reason: text);
        }
      });
    }
  }, skip: engineReady ? false : searchEngineSkipReason);
}
