import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/search/view/search_results_layout.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart'
    show OtzariaSearchDisplayBar;

import '../test_helpers/memory_cache_provider.dart';
import '../test_helpers/stub_settings_bloc.dart';

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState state) {
    emit(state);
  }

  @override
  void add(SearchEvent event) {}
}

/// סרגל תוצאות החיפוש בחלון צר מ-600 (סבב ב', סעיף 36): מילות החיפוש עוברות
/// לשורה שנייה ברוחב מלא, כדי שייראו במלואן ושיהיה נוח ללחוץ עליהן. מ-600
/// ומעלה הן נשארות במרכז הסרגל.
void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpLayout(
    WidgetTester tester,
    double width, {
    VoidCallback? onEditSearch,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final searchBloc = _StaticSearchBloc(
      const SearchState(searchQuery: 'בדיקה', totalResults: 12),
    );
    final settingsBloc = StubSettingsBloc();
    final tab = SearchingTab('חיפוש', 'בדיקה', searchBloc: searchBloc);
    tab.isLeftPaneOpen.value = false;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tab.dispose();
      await searchBloc.close();
      await settingsBloc.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: SearchResultsLayout(
                tab: tab,
                hasQuery: true,
                onEditSearch: onEditSearch ?? () {},
                countsBuilder: (context, collapsed) => const Text('12 תוצאות'),
                resultsBuilder: (_) => const SizedBox.expand(),
                facetPane: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect queryRect(WidgetTester tester) =>
      tester.getRect(find.byType(SearchTermsDisplay));

  /// הסרגל הלחיץ שעוטף את מילות החיפוש (ולא רק הטקסט שבתוכו).
  Rect queryBarRect(WidgetTester tester) =>
      tester.getRect(find.byType(OtzariaSearchDisplayBar));

  for (final width in const [320.0, 400.0, 599.0]) {
    testWidgets('ברוחב $width מילות החיפוש בשורה שנייה ברוחב מלא', (
      tester,
    ) async {
      await pumpLayout(tester, width);

      final query = queryRect(tester);
      final counts = tester.getRect(find.text('12 תוצאות'));
      expect(
        query.top,
        greaterThanOrEqualTo(counts.bottom),
        reason: 'השאילתה צריכה להיות מתחת לשורת הכפתורים',
      );
      expect(
        queryBarRect(tester).width,
        greaterThan(width * 0.6),
        reason: 'השאילתה צריכה לקבל את רוחב החלון ולא 80 פיקסלים',
      );
    });
  }

  testWidgets('לחיצה על מילות החיפוש בשורה השנייה פותחת עריכת חיפוש', (
    tester,
  ) async {
    var edits = 0;
    await pumpLayout(tester, 320, onEditSearch: () => edits++);

    await tester.tap(find.byType(SearchTermsDisplay));
    await tester.pump();

    expect(edits, 1);
  });

  for (final width in const [600.0, 900.0]) {
    testWidgets('ברוחב $width מילות החיפוש נשארות במרכז הסרגל', (tester) async {
      await pumpLayout(tester, width);

      final query = queryRect(tester);
      final counts = tester.getRect(find.text('12 תוצאות'));
      expect(
        query.center.dy,
        closeTo(counts.center.dy, 12),
        reason: 'השאילתה צריכה להישאר באותה שורה עם המונים',
      );
    });
  }
}
