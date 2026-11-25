import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../design_system/contracts/contract_harness.dart';
import '../test_helpers/memory_cache_provider.dart';

/// #5562: סימון אפשרות מילה לא מזיז את שאר התיבות (וי מרחיב את התיבה
/// ושובר את השורות של ה-Wrap).
void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final brightness in Brightness.values) {
    testWidgets('סימון אפשרות מילה לא משנה את פריסת התיבות ($brightness)', (
      tester,
    ) async {
      final tab = SearchingTab('חיפוש', '');
      addTearDown(tab.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: AdvancedSearchControls(tab: tab),
            ),
          ),
        ),
      );

      final chips = find.byType(FilterChip);
      expect(chips, findsWidgets);
      List<Rect> rects() => [
        for (var i = 0; i < chips.evaluate().length; i++)
          tester.getRect(chips.at(i)),
      ];
      final before = rects();

      final target = find.widgetWithText(
        FilterChip,
        SearchQueryBuilder.availableWordOptionKeys[1],
      );
      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(tester.widget<FilterChip>(target).selected, isTrue);
      // בלי הווי הבחירה עדיין מוכרזת לקורא מסך.
      expect(
        tester.getSemantics(target),
        isSemantics(isSelected: true),
      );
      expect(rects(), before);
    });
  }
}
