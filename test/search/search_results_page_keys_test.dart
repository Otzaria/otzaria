import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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

/// PageDown/PageUp ברשימת תוצאות החיפוש (issue #4966): המקשים גוללים את
/// הרשימה בעמוד, בלי תלות ברכיב המחזיק בפוקוס בתוך אזור התוצאות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const resultCount = 20;

  late _StaticSearchBloc searchBloc;
  late _MockSettingsBloc settingsBloc;
  late SearchingTab tab;
  var showPreview = true;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    showPreview = true;
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
    tab = SearchingTab('חיפוש', 'תדע', searchBloc: searchBloc);
  });

  tearDown(() async {
    tab.dispose();
    await searchBloc.close();
    await settingsBloc.close();
  });

  Future<void> pumpResults(WidgetTester tester) async {
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        searchShowPreview: showPreview,
      ),
    );
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
              child: TantivySearchResults(
                tab: tab,
                showPreviewPane: showPreview,
              ),
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

  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  testWidgets('PageDown/PageUp גוללים מסך כשהתצוגה המקדימה פתוחה', (
    tester,
  ) async {
    await pumpResults(tester);
    await tester.tap(find.text('בראשית, קטע 0').first);
    await settle(tester);
    expect(tab.previewTarget.value?.segment, 100);

    await pressKey(tester, LogicalKeyboardKey.pageDown);
    final afterDown = offset(tester);
    expect(afterDown, greaterThan(300), reason: 'PageDown חייב לגלול מסך');

    await pressKey(tester, LogicalKeyboardKey.pageUp);
    expect(offset(tester), lessThan(afterDown));
  });

  testWidgets('לחיצה באזור התוצאות מאפשרת PageDown גם בלי תצוגה מקדימה', (
    tester,
  ) async {
    showPreview = false;
    await pumpResults(tester);
    // לחיצה בלי שחרור (פתיחה בעיון קורית רק בהקשה שהושלמה).
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('בראשית, קטע 0').first),
    );
    await gesture.cancel();
    await settle(tester);

    await pressKey(tester, LogicalKeyboardKey.pageDown);
    expect(offset(tester), greaterThan(300));
  });

  testWidgets('Ctrl+PageDown אינו גולל את הרשימה (שמור לקיצורים)', (
    tester,
  ) async {
    await pumpResults(tester);
    await tester.tap(find.text('בראשית, קטע 0').first);
    await settle(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(offset(tester), 0);
  });
}
