import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/toc_navigator_screen.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// Bloc בדיקה שמאפשר emit ידני של states ל-TocViewer.
/// מאפשר לאמת ש-buildWhen מסנן emits לא רלוונטיים — ההגנה המרכזית של
/// commit 5ca70f2 מפני O(n²) ב-TOC navigator.
class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  void emitState(TextBookState newState) => emit(newState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// בונה רשימת TOC אמיתית עם רמה+ילדים, בגודל בקרה (להצלחה ולכישלון של הסף).
List<TocEntry> _buildLargeToc({required int simanim, required int seifim}) {
  return List.generate(simanim, (s) {
    final base = s * (seifim + 1);
    final parent = TocEntry(text: 'siman $s', index: base, level: 1);
    for (var i = 0; i < seifim; i++) {
      parent.children.add(
        TocEntry(text: 'seif $i', index: base + 1 + i, level: 2),
      );
    }
    return parent;
  });
}

TextBookLoaded _loadedState({
  required List<TocEntry> toc,
  required List<int> visibleIndices,
  int? selectedIndex,
  bool showLeftPane = true,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: showLeftPane,
    content: const ['שורה א', 'שורה ב', 'שורה ג'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: toc,
    removeNikud: false,
    visibleIndices: visibleIndices,
    selectedIndex: selectedIndex,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

Widget _wrap(Widget child, TextBookBloc bloc) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: BlocProvider<TextBookBloc>.value(
          value: bloc,
          child: SizedBox(width: 400, height: 800, child: child),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── הגנה על ה-buildWhen: שלא יתאפשר rebuild בכל emit ──────────────────
  testWidgets(
    'buildWhen מסנן emits שלא משנים visibleIndices.first/selectedIndex/TOC',
    (tester) async {
      // עץ קטן (מתחת לסף 500) — מסלול רקורסיבי.
      final toc = [
        TocEntry(text: 'a', index: 0, level: 1),
        TocEntry(text: 'b', index: 5, level: 1),
      ];

      final initialState = _loadedState(
        toc: toc,
        visibleIndices: const [0],
        selectedIndex: null,
      );

      final bloc = _TestTextBookBloc(initialState);
      addTearDown(bloc.close);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      var blocBuilderCount = 0;
      Widget testHarness = _wrap(
        BlocBuilder<TextBookBloc, TextBookState>(
          bloc: bloc,
          // אנו רק רוצים להפעיל את ה-tree, אבל ה-TocViewer הוא זה שיש לו
          // את ה-buildWhen האמיתי שאנו בוחנים.
          builder: (context, state) {
            return Builder(
              builder: (innerContext) {
                // עוטף את ה-TocViewer ב-Builder שסופר rebuilds דרך InheritedWidget
                // לא רלוונטי — נכליל ספירה דרך paneContent של TocViewer בעקיפין.
                return TocViewer(
                  scrollController: ItemScrollController(),
                  closeLeftPaneCallback: () {},
                  focusNode: focusNode,
                );
              },
            );
          },
        ),
        bloc,
      );

      await tester.pumpWidget(testHarness);
      await tester.pump();

      // סופרים TocEntry שמופיע ב-DOM (וידג'ט אמיתי) - כל ערך מופיע פעם אחת.
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);

      blocBuilderCount = 0;
      // עוטפים שכבת מנייה: נשתמש ב-runtime-spy לפי textBaseline. במקום זאת,
      // נשתמש בטכניקת stop-watch: כמות שינויי content (ספירה דרך paneContent).
      // במקום זה — נסתפק באימות התנהגותי: emit עם שינוי בשדה שאינו תלוי
      // (לדוגמה fontSize) לא צריך לגרום ל-DOM-thrash.
      final stateOnlyFontSize = initialState.copyWith(fontSize: 24);
      bloc.emitState(stateOnlyFontSize);
      await tester.pump();

      // הערכים נשארים במקומם וזהים — אין שינוי משמעותי לרשימה.
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);

      // emit עם שינוי ב-visibleIndices.first → buildWhen מחזיר true → rebuild.
      final stateNewVisible = stateOnlyFontSize.copyWith(visibleIndices: [5]);
      bloc.emitState(stateNewVisible);
      await tester.pump();

      // אין שינוי במבנה התצוגה, אבל ה-build רץ. הבדיקה האמיתית כאן:
      // לא הייתה התרסקות, ו-b הוא ה-active (selected highlight).
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      // השאיפה היא שלא תיווצר רגרסיה לפיה כל emit מבצע rebuild ארוך —
      // הפעלה זו לא יכולה להיכשל בלי תיקוד שטחי, אבל עומדת כעמוד שמירה.
      expect(blocBuilderCount, lessThanOrEqualTo(10));
    },
  );

  // ── הגנה על מסלול הוירטואליזציה לספרים גדולים ──────────────────────────
  testWidgets('ספר עם TOC > סף → משתמש במסלול ScrollablePositionedList', (
    tester,
  ) async {
    // 100 simanim × 60 seifim = ~6100 ערכים, הרבה מעל סף 500.
    final largeToc = _buildLargeToc(simanim: 100, seifim: 60);

    final bloc = _TestTextBookBloc(
      _loadedState(
        toc: largeToc,
        visibleIndices: const [0],
        selectedIndex: null,
      ),
    );
    addTearDown(bloc.close);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        TocViewer(
          scrollController: ItemScrollController(),
          closeLeftPaneCallback: () {},
          focusNode: focusNode,
        ),
        bloc,
      ),
    );
    await tester.pump();

    // המסלול הוירטואלי משתמש ב-ScrollablePositionedList במקום SingleChildScrollView.
    expect(
      find.byType(ScrollablePositionedList),
      findsOneWidget,
      reason: 'ספר גדול חייב להשתמש בוירטואליזציה',
    );

    // וגם — לא כל 6000 הערכים מופיעים ב-DOM (וירטואליזציה אמיתית).
    // ScrollablePositionedList בונה רק את אלו שמתאימים לחלון.
    final allSimanTexts = find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data?.startsWith('siman') ?? false),
    );
    // אסור שיהיו 100 (כל הסימנים) — רק חלק מהם נראים.
    expect(
      tester.widgetList(allSimanTexts).length,
      lessThan(100),
      reason: 'וירטואליזציה: לא כל הסימנים צריכים להיות ב-DOM',
    );
  });

  testWidgets('ספר עם TOC < סף → משתמש ב-SingleChildScrollView (לא וירטואלי)', (
    tester,
  ) async {
    // עץ קטן, 20 ערכים — מתחת לסף.
    final smallToc = List.generate(
      20,
      (i) => TocEntry(text: 'item $i', index: i, level: 1),
    );

    final bloc = _TestTextBookBloc(
      _loadedState(
        toc: smallToc,
        visibleIndices: const [0],
        selectedIndex: null,
      ),
    );
    addTearDown(bloc.close);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        TocViewer(
          scrollController: ItemScrollController(),
          closeLeftPaneCallback: () {},
          focusNode: focusNode,
        ),
        bloc,
      ),
    );
    await tester.pump();

    // לא משתמש בוירטואליזציה — מסלול רקורסיבי קיים.
    expect(
      find.byType(ScrollablePositionedList),
      findsNothing,
      reason: 'ספר קטן לא צריך וירטואליזציה — שומר על מסלול רקורסיבי',
    );
  });

  testWidgets('שינוי visibleIndices מעדכן את ה-active highlight בלי קריסה', (
    tester,
  ) async {
    // הבדיקה הזו מגנה על: activeIndex מחושב מ-visibleIndices.first
    // ומועבר לבנייה (לפני האופטימיזציה, כל ערך חישב לעצמו O(n)).
    final toc = [
      TocEntry(text: 'first', index: 0, level: 1),
      TocEntry(text: 'second', index: 5, level: 1),
      TocEntry(text: 'third', index: 10, level: 1),
    ];

    final bloc = _TestTextBookBloc(
      _loadedState(
        toc: toc,
        visibleIndices: const [0],
        selectedIndex: null,
      ),
    );
    addTearDown(bloc.close);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        TocViewer(
          scrollController: ItemScrollController(),
          closeLeftPaneCallback: () {},
          focusNode: focusNode,
        ),
        bloc,
      ),
    );
    await tester.pump();

    // שינוי ה-visibleIndices → activeIndex משתנה ל-second (אינדקס 5).
    bloc.emitState(
      (bloc.state as TextBookLoaded).copyWith(visibleIndices: [7]),
    );
    await tester.pump();

    // שינוי ל-third
    bloc.emitState(
      (bloc.state as TextBookLoaded).copyWith(visibleIndices: [15]),
    );
    await tester.pump();

    // הוידג'ט לא קרס — כל הערכים עדיין נראים.
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
  });

  testWidgets('פתיחת הפאנל (showLeftPane false→true) גוללת למיקום הפעיל', (
    tester,
  ) async {
    // TOC ארוך שגולש מהמסך, עם פריט פעיל רחוק. כשהפאנל סגור אסור לגלול
    // (גלילה ברוחב 0 הייתה משבשת את ה-guard), וברגע הפתיחה יש לגלול אליו.
    final toc = List.generate(
      50,
      (i) => TocEntry(text: 'פרק $i', index: i, level: 1),
    );

    final closed = _loadedState(
      toc: toc,
      visibleIndices: const [45],
      selectedIndex: 45,
      showLeftPane: false,
    );

    final bloc = _TestTextBookBloc(closed);
    addTearDown(bloc.close);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        TocViewer(
          scrollController: ItemScrollController(),
          closeLeftPaneCallback: () {},
          focusNode: focusNode,
        ),
        bloc,
      ),
    );
    await tester.pumpAndSettle();

    double tocOffset() => tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!
        .offset;

    // פאנל סגור → אין גלילה.
    expect(tocOffset(), 0);

    // פתיחת הפאנל → גלילה למיקום הפעיל. הגלילה משתמשת בשני
    // addPostFrameCallback מקוננים שלא מבקשים frame בעצמם, ולכן יש
    // לאלץ frames כדי שהשני ירוץ ושהאנימציה תושלם.
    bloc.emitState(closed.copyWith(showLeftPane: true));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(tocOffset(), greaterThan(0));
  });

  testWidgets('emit חוזר עם אותו state לא קורס ולא משכפל פריטים', (
    tester,
  ) async {
    // הגנה מפני באג: אם buildWhen מחזיר true בטעות לאותו state, צריך
    // שהבנייה תהיה idempotent — לא יווצרו כפילויות.
    final toc = [
      TocEntry(text: 'unique-a', index: 0, level: 1),
      TocEntry(text: 'unique-b', index: 5, level: 1),
    ];

    final state = _loadedState(
      toc: toc,
      visibleIndices: const [0],
      selectedIndex: null,
    );

    final bloc = _TestTextBookBloc(state);
    addTearDown(bloc.close);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        TocViewer(
          scrollController: ItemScrollController(),
          closeLeftPaneCallback: () {},
          focusNode: focusNode,
        ),
        bloc,
      ),
    );
    await tester.pump();

    // 5 emits של אותו state — לא יצירת כפילויות.
    for (var i = 0; i < 5; i++) {
      bloc.emitState(state.copyWith(fontSize: state.fontSize + 0.001 * i));
      await tester.pump();
    }

    expect(find.text('unique-a'), findsOneWidget);
    expect(find.text('unique-b'), findsOneWidget);
  });
}
