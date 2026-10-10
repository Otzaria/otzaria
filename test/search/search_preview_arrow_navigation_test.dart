import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState initialState) {
    emit(initialState);
  }

  @override
  void add(SearchEvent event) {}
}

/// ניווט חיצים בין תוצאות כשהתצוגה המקדימה פתוחה (issue #1045): חץ מטה/מעלה
/// מעביר את התצוגה לתוצאה השכנה, והרשימה נגללת כדי שהתוצאה שנבחרה תישאר
/// בתחום הנראה — גם כשהיא מחוץ לחלון.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const resultCount = 20;

  late _StaticSearchBloc searchBloc;
  late _MockSettingsBloc settingsBloc;
  late SearchingTab tab;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    final library = Library(categories: const []);
    library.books.add(TextBook(id: 1, title: 'בראשית'));
    DataRepository.instance.library = Future.value(library);

    searchBloc = _StaticSearchBloc(
      SearchState(
        searchQuery: 'תדע',
        totalResults: resultCount,
        results: [
          for (var i = 0; i < resultCount; i++)
            SearchResult(
              id: BigInt.from(i + 1),
              title: 'בראשית',
              reference: 'בראשית, קטע $i',
              // טקסט ארוך — כרטיסים גבוהים כמו באפליקציה, כדי שהכרטיס השכן
              // ייצא מחוץ לחלון (ואף מחוץ ל-cacheExtent) אחרי צעדים ספורים.
              text: List.filled(
                6,
                'ידע תדע כי־גר יהיה זרעך בארץ לא להם ועבדום וענו אותם '
                'ארבע מאות שנה וגם את הגוי אשר יעבדו דן אנכי',
              ).join('\n'),
              segment: BigInt.from(100 + i),
              isPdf: false,
              filePath: 'id:1',
              mergedCount: 1,
              merged: const [],
              textStatus: TextStatus.ok,
              continuesToNextLine: false,
            ),
        ],
      ),
    );
    settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(searchShowPreview: true),
    );
    tab = SearchingTab('חיפוש', 'תדע', searchBloc: searchBloc);
  });

  tearDown(() async {
    tab.dispose();
    await searchBloc.close();
    await settingsBloc.close();
  });

  Future<void> pumpResults(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 600,
              child: TantivySearchResults(tab: tab, showPreviewPane: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// ממתין להשלמת פעולות אסינכרוניות (זיהוי הספר מול הקטלוג) בין פריימים.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openPreviewOnFirstResult(WidgetTester tester) async {
    await tester.tap(find.text('בראשית, קטע 0').first);
    await settle(tester);
    expect(tab.previewTarget.value?.segment, 100);
  }

  Future<void> pressArrow(
    WidgetTester tester,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  testWidgets('חץ מטה עובר לתוצאה הבאה וחץ מעלה חוזר', (tester) async {
    await pumpResults(tester);
    await openPreviewOnFirstResult(tester);

    await pressArrow(tester, LogicalKeyboardKey.arrowDown);
    expect(tab.previewTarget.value?.segment, 101);

    await pressArrow(tester, LogicalKeyboardKey.arrowUp);
    expect(tab.previewTarget.value?.segment, 100);
  });

  testWidgets('חץ מעלה בתוצאה הראשונה נשאר בה והתצוגה לא נסגרת', (
    tester,
  ) async {
    await pumpResults(tester);
    await openPreviewOnFirstResult(tester);

    await pressArrow(tester, LogicalKeyboardKey.arrowUp);
    expect(tab.previewTarget.value?.segment, 100);
  });

  testWidgets('ניווט מטה מעבר לחלון גולל את הרשימה אל התוצאה שנבחרה', (
    tester,
  ) async {
    await pumpResults(tester);
    await openPreviewOnFirstResult(tester);

    // מספיק צעדים כדי שהתוצאה הנבחרת תצא מגבולות חלון של 600 פיקסלים —
    // ואחרי כל צעד הכותרת של התוצאה שנבחרה חייבת להיות בתוך החלון בפועל.
    for (var i = 1; i <= 8; i++) {
      await pressArrow(tester, LogicalKeyboardKey.arrowDown);
      expect(tab.previewTarget.value?.segment, 100 + i);

      final titleRect = tester.getRect(find.text('בראשית, קטע $i').first);
      expect(
        titleRect.top,
        inInclusiveRange(0, 600),
        reason: 'התוצאה שנבחרה (קטע $i) חייבת להיגלל אל תוך החלון',
      );
      expect(titleRect.bottom, lessThanOrEqualTo(600));
    }

    // ובחזרה מעלה — אותה דרישה בכיוון ההפוך.
    for (var i = 7; i >= 0; i--) {
      await pressArrow(tester, LogicalKeyboardKey.arrowUp);
      expect(tab.previewTarget.value?.segment, 100 + i);

      final titleRect = tester.getRect(find.text('בראשית, קטע $i').first);
      expect(
        titleRect.top,
        inInclusiveRange(0, 600),
        reason: 'התוצאה שנבחרה (קטע $i) חייבת להיגלל אל תוך החלון',
      );
    }
  });

  testWidgets('כשאין תצוגה מקדימה פתוחה החיצים לא נוגעים ברשימה', (
    tester,
  ) async {
    await pumpResults(tester);

    await pressArrow(tester, LogicalKeyboardKey.arrowDown);
    expect(tab.previewTarget.value, isNull);
  });
}
