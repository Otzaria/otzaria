import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

/// כותרת שורת ההרחבה חייבת להצהיר על מה הסימון חל: המשתמש מסמן תיבה
/// אחרי שמיקם את הסמן על מילה, וללא הכותרת הוא מניח שהסימון חל רק עליה.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  /// מרכיב את פקדי החיפוש המתקדם עם שאילתה, מצב היקף ומיקום סמן נתונים.
  Future<void> pumpControls(
    WidgetTester tester, {
    required String query,
    required bool useGlobal,
    int? cursorOffset,
    int? selectionEnd,
  }) async {
    final tab = SearchingTab('חיפוש', query);
    tab.useGlobalSearchOptions.value = useGlobal;
    if (cursorOffset != null) {
      tab.queryController.selection = selectionEnd == null
          ? TextSelection.collapsed(offset: cursorOffset)
          : TextSelection(baseOffset: cursorOffset, extentOffset: selectionEnd);
    }
    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(child: AdvancedSearchControls(tab: tab)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('כותרת הרחבת המילים', () {
    testWidgets('במצב "זהה לכל המילים" הכותרת מצהירה על כל המילים', (
      tester,
    ) async {
      await pumpControls(
        tester,
        query: 'חכמה בינה',
        useGlobal: true,
        cursorOffset: 1,
      );

      expect(find.text('הרחבת כל המילים'), findsOneWidget);
    });

    testWidgets('במצב פר-מילה הכותרת נוקבת במילה שהסמן עליה', (tester) async {
      await pumpControls(
        tester,
        query: 'חכמה בינה',
        useGlobal: false,
        cursorOffset: 1,
      );

      expect(find.text('הרחבת המילה: חכמה'), findsOneWidget);
    });

    testWidgets('בבחירת טווח הכותרת מונה את המילים שנבחרו', (tester) async {
      await pumpControls(
        tester,
        query: 'חכמה בינה דעת',
        useGlobal: false,
        cursorOffset: 0,
        selectionEnd: 9,
      );

      expect(find.text('הרחבת 2 המילים שנבחרו'), findsOneWidget);
    });

    testWidgets('בלי מילה נבחרת הכותרת נשארת כללית', (tester) async {
      await pumpControls(tester, query: 'חכמה בינה', useGlobal: false);

      expect(find.text('הרחבת המילה'), findsOneWidget);
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}
