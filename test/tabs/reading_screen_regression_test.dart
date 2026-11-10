import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_settings_bloc.dart';

/// טסטי רגרסיה ל-`ReadingScreen`: פריסת תצוגה זה-לצד-זה ומסך ריק.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading_screen — שוליים חיצוניים בתצוגה זה-לצד-זה', () {
    // רגרסיה: תוכן החלונית קיבל שוליים בעובי המפריד בצד הדופן החיצונית, והם
    // דחקו את פס הגלילה 12px מהדופן. התוכן חייב למלא את כרטיס החלונית.

    /// שולי הכרטיס מהדופן: [kPaneCardMargin] ועוד עובי המסגרת.
    const cardEdge = kPaneCardMargin + 1.0;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    testWidgets(
      'ReadingScreen עם CombinedTab: החלוניות צמודות לדופן והתוכן ממלא אותן',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final combined = CombinedTab(
          rightTab: _commentaryTab('ימין'),
          leftTab: _commentaryTab('שמאל'),
        );
        addTearDown(combined.dispose);

        final tabsBloc = _FakeTabsBloc(
          TabsState(tabs: [combined], currentTabIndex: 0),
        );
        addTearDown(tabsBloc.close);

        await tester.pumpWidget(
          MaterialApp(
            // עובי המפריד (וממילא השוליים) רחב יותר במגע; כאן נבדק דסקטופ.
            theme: ThemeData(platform: TargetPlatform.windows),
            home: Directionality(
              // כמו באפליקציה האמיתית (locale he): הפריסה נבדקת בכיוון הייצור.
              textDirection: TextDirection.rtl,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SettingsBloc>.value(value: StubSettingsBloc()),
                  BlocProvider<PersonalNotesBloc>.value(
                    value: _FakePersonalNotesBloc(),
                  ),
                  BlocProvider<TabsBloc>.value(value: tabsBloc),
                  Provider<FocusRepository>.value(value: FocusRepository()),
                ],
                child: const ReadingScreen(),
              ),
            ),
          ),
        );
        await tester.pump();

        final panes = find.byType(PdfCommentatorsTabScreen);
        expect(panes, findsNWidgets(2));

        // כל חלונית נצמדת לדופן החלון — הידית ב-Positioned(left:0) יושבת על
        // הדופן האמיתי (x=0 / x=רוחב), ולא 12px פנימה.
        final paneRects = [
          tester.getRect(panes.at(0)),
          tester.getRect(panes.at(1)),
        ];
        final paneLeft = paneRects
            .map((r) => r.left)
            .reduce((a, b) => a < b ? a : b);
        final paneRight = paneRects
            .map((r) => r.right)
            .reduce((a, b) => a > b ? a : b);

        expect(
          paneLeft,
          cardEdge,
          reason:
              'הכרטיס הקיצוני יושב על הדופן עד כדי שוליו הדקים; יותר מזה '
              'דוחק את הידית (Positioned(left:0)) פנימה',
        );
        expect(
          1600 - paneRight,
          paneLeft,
          reason: 'המסגור סימטרי בשני צדי החלון',
        );

        // תוכן הקריאה (AdaptiveSidePane) ממלא את כרטיס החלונית.
        final content = find.byType(AdaptiveSidePane);
        expect(content, findsNWidgets(2));
        final contentRects = [
          tester.getRect(content.at(0)),
          tester.getRect(content.at(1)),
        ];
        final contentLeft = contentRects
            .map((r) => r.left)
            .reduce((a, b) => a < b ? a : b);
        final contentRight = contentRects
            .map((r) => r.right)
            .reduce((a, b) => a > b ? a : b);

        expect(
          contentLeft,
          cardEdge,
          reason:
              'תוכן הקריאה ממלא את הכרטיס — בלי שוליים מוזרקים שדוחקים '
              'את פס הגלילה מהדופן',
        );
        expect(
          contentRight,
          1600 - cardEdge,
          reason: 'תוכן הקריאה ממלא את הכרטיס בשני הצדדים',
        );
      },
    );
  });

  testWidgets('כפתור איתור במסך ריק פותח את חלונית האיתור', (tester) async {
    var findRequests = 0;
    final tabsBloc = _FakeTabsBloc(TabsState.initial());
    addTearDown(tabsBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<TabsBloc>.value(
          value: tabsBloc,
          child: ReadingScreen(onFindRefRequested: () => findRequests++),
        ),
      ),
    );

    await tester.tap(find.text('איתור ספר'));
    await tester.pump();

    expect(findRequests, 1);
  });
}

class _FakePersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _FakePersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _FakeTabsBloc(super.initial) {
    on<TabsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// כרטסיית מפרשים מזויפת — תוכן קל שנטען סינכרונית בתצוגה המפוצלת.
PdfCommentatorsTab _commentaryTab(String title) {
  final sourceTab = PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );
  sourceTab.pdfHeadings = PdfHeadings(
    bookTitle: title,
    headingsMap: {'פרק א': 1},
  );
  sourceTab.currentTitle.value = 'פרק א';
  sourceTab.currentTextLineNumber = 1;
  sourceTab.currentTextLineNumberEnd = 9;
  return PdfCommentatorsTab(sourceTab: sourceTab);
}
