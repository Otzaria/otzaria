import 'dart:math' as math;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState state) {
    emit(state);
  }

  @override
  void add(SearchEvent event) {
    if (event is! LoadMoreResults) super.add(event);
  }
}

const _word = 'בדיקה';

double _contrast(Color a, Color b) {
  final l = [a.computeLuminance(), b.computeLuminance()];
  return (l.reduce(math.max) + .05) / (l.reduce(math.min) + .05);
}

/// #3127: מילת חיפוש רגילה בכרטיס תוצאה מקבלת רקע עדין משלה, שונה מרקע
/// התוצאה הנוכחית ומרקע הסימון, והטקסט האדום נשאר קריא עליו.
void main() {
  for (final brightness in Brightness.values) {
    for (final seed in AppSeedColors.options) {
      testWidgets(
        'רקע למילת החיפוש בכרטיס תוצאה: ${seed.name}/${brightness.name}',
        (tester) async {
          final dark = brightness == Brightness.dark;
          final scheme = AppThemeData.createColorScheme(seed.color, brightness);
          final variant = AppThemeVariant.ofSeed(seed.color);
          final theme = dark
              ? AppThemeData.dark(
                  scheme,
                  compactMenuMode: false,
                  variant: variant,
                )
              : AppThemeData.light(
                  scheme,
                  compactMenuMode: false,
                  variant: variant,
                );
          final searchBloc = _StaticSearchBloc(
            SearchState(
              searchQuery: _word,
              totalResults: 1,
              results: [
                SearchResult(
                  id: BigInt.one,
                  title: 'ספר',
                  reference: 'סימן א',
                  text: 'טקסט <font color="red">$_word</font> נוסף',
                  segment: BigInt.one,
                  isPdf: false,
                  filePath: 'book.txt',
                  mergedCount: 1,
                  merged: const [],
                  textStatus: TextStatus.ok,
                  continuesToNextLine: false,
                ),
              ],
            ),
          );
          final settingsBloc = _MockSettingsBloc();
          whenListen(
            settingsBloc,
            const Stream<SettingsState>.empty(),
            initialState: SettingsState.initial(),
          );
          final tab = SearchingTab('חיפוש', _word);
          addTearDown(() async {
            tab.dispose();
            await searchBloc.close();
            await settingsBloc.close();
          });

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: MultiBlocProvider(
                providers: [
                  BlocProvider<SearchBloc>.value(value: searchBloc),
                  BlocProvider<SettingsBloc>.value(value: settingsBloc),
                ],
                child: Scaffold(
                  body: SizedBox(
                    height: 500,
                    child: TantivySearchResults(tab: tab),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          TextSpan? hit;
          for (final rich in tester.widgetList<RichText>(
            find.byType(RichText),
          )) {
            rich.text.visitChildren((span) {
              if (span is TextSpan && span.text == _word) hit = span;
              return hit == null;
            });
            if (hit != null) break;
          }
          expect(hit, isNotNull);
          final background = hit!.style?.backgroundColor;
          expect(background, isNotNull, reason: 'מילת החיפוש בלי רקע');
          expect(
            background,
            isNot(AppSurfaces.searchHitCurrentBackground(scheme)),
          );
          expect(background, isNot(AppSurfaces.permanentMark(scheme)));
          for (final surface in [
            scheme.surface,
            scheme.surfaceContainerLow,
            scheme.surfaceContainer,
            theme.scaffoldBackgroundColor,
          ]) {
            expect(
              _contrast(
                hit!.style!.color!,
                Color.alphaBlend(background!, surface),
              ),
              greaterThanOrEqualTo(4.5),
              reason: 'הטקסט האדום חייב להישאר קריא על הרקע',
            );
          }
        },
      );
    }
  }
}
