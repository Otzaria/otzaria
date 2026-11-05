import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// תוצאת חיפוש בהערה נחשפת ומודגשת דרך המסך האמיתי.
/// ההדגשה דורשת מנוע נייטיבי; בלעדיו הבדיקות מדולגות.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  const query = 'מקור';
  const content = [
    'פסקה ראשונה<sup class="footnote-marker">א</sup>',
    'פסקה שנייה<sup class="footnote-marker">ב</sup>',
    'פסקה שלישית<sup class="footnote-marker">ג</sup>',
    'פסקה רביעית על מקור',
  ];

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  TextBookLoaded loadedState({
    List<String> activeCommentators = const [],
    String searchText = '',
  }) {
    final notes = BookNotesBuilder()
      ..add(0, 0, 'א', 'הערה על מקור ראשון')
      ..add(1, 0, 'ב', 'הערה על מקור שני')
      ..add(2, 0, 'ג', 'הערה על שורש הדין');
    return TextBookLoaded(
      book: TextBook(title: 'ספר בדיקה'),
      showLeftPane: true,
      content: content,
      fontSize: 18,
      showSplitView: true,
      activeCommentators: activeCommentators,
      commentatorGroups: const [],
      availableCommentators: const [kNotesCommentatorTitle],
      links: const <Link>[],
      visibleLinks: const <Link>[],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      removePunctuation: false,
      visibleIndices: const [0, 1, 2, 3],
      pinLeftPane: false,
      searchText: searchText,
      searchMode: SearchMode.exact,
      bookNotes: notes.build(),
    );
  }

  /// האם [term] צבוע כהדגשת חיפוש בתוך הטקסט המוצג שמכיל את [text].
  ///
  /// צבע ההדגשה הוא הטוקן [AppSurfaces.searchHit] של ערכת הנושא (DD-17),
  /// ולא האדום הקבוע (#FF0000) שהיה לפני ההכרעה.
  bool isHighlightedIn(
    WidgetTester tester,
    String text, {
    String term = query,
  }) {
    final paragraphs = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(text),
    );
    for (final element in paragraphs.evaluate()) {
      final widget = element.widget as RichText;
      final hit = AppSurfaces.searchHit(
        Theme.of(element).colorScheme,
      ).toARGB32();
      var highlighted = false;
      widget.text.visitChildren((span) {
        if (span is TextSpan &&
            (span.text ?? '').contains(term) &&
            span.style?.color?.toARGB32() == hit) {
          highlighted = true;
        }
        return !highlighted;
      });
      if (highlighted) return true;
    }
    return false;
  }

  group('"מפרשים בצד": לחיצה על תוצאה שנחתה בהערה', () {
    late TextBookTab tab;

    Future<_TestTextBookBloc> pumpSplitedView(
      WidgetTester tester, {
      TextBookLoaded? initial,
    }) async {
      final bloc = _TestTextBookBloc(initial ?? loadedState());
      final book = (bloc.state as TextBookLoaded).book;
      final personalNotesBloc = _TestPersonalNotesBloc(
        const PersonalNotesState.initial(),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
      final tabsBloc = _TestTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final tourCubit = _TestTourCubit();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bloc.close();
        await personalNotesBloc.close();
        await settingsBloc.close();
        await tabsBloc.close();
        await tourCubit.close();
        tab.dispose();
      });

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<TourCubit>.value(value: tourCubit),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SplitedViewScreen(
                content: content,
                openBookCallback: (_) {},
                searchTextController: TextEditingValue.empty,
                openLeftPaneTab: (_, {searchText}) {},
                onSelectedTextChanged: null,
                tab: tab,
                showSplitView: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return bloc;
    }

    /// אותם אירועים שחלונית החיפוש בספר שולחת בלחיצה על תוצאה.
    Future<void> openResult(
      WidgetTester tester,
      _TestTextBookBloc bloc,
      int line, {
      UpdateSearchText search = const UpdateSearchText(query),
    }) async {
      bloc.add(search);
      bloc.add(UpdateSearchResultLines({line}));
      bloc.add(SelectSearchResult(line));
      bloc.add(HighlightLine(line));
      await tester.pumpAndSettle();
    }

    Future<void> togglePane(WidgetTester tester) async {
      tab.toggleCommentatorsPaneNotifier.value++;
      await tester.pumpAndSettle();
    }

    testWidgets(
      'ההתאמה מודגשת בהערה שבחלונית (issue #3824)',
      (tester) async {
        final bloc = await pumpSplitedView(tester);

        await openResult(tester, bloc, 0);

        expect(find.byType(PanelOpenHandle), findsNothing);
        expect(
          find.textContaining('מקור ראשון', findRichText: true),
          findsOneWidget,
        );
        expect(
          isHighlightedIn(tester, 'מקור ראשון'),
          isTrue,
          reason: 'מונח החיפוש חייב להיות מודגש בגוף ההערה',
        );
      },
      skip: !engineReady,
    );

    testWidgets(
      'תוצאה נוספת בהערה פותחת שוב את החלונית שנסגרה (issue #3824)',
      (tester) async {
        final bloc = await pumpSplitedView(tester);
        await openResult(tester, bloc, 0);
        await togglePane(tester);
        expect(find.byType(PanelOpenHandle), findsOneWidget);

        await openResult(tester, bloc, 1);

        expect(find.byType(PanelOpenHandle), findsNothing);
        expect(isHighlightedIn(tester, 'מקור שני'), isTrue);

        // "הבא" לתוצאה בטקסט עצמו ו"הקודם" חזרה אליה — נפתחת שוב.
        await togglePane(tester);
        await openResult(tester, bloc, 3);
        expect(find.byType(PanelOpenHandle), findsOneWidget);
        await openResult(tester, bloc, 1);

        expect(find.byType(PanelOpenHandle), findsNothing);
        expect(isHighlightedIn(tester, 'מקור שני'), isTrue);
      },
      skip: !engineReady,
    );

    testWidgets(
      'תוצאת מנוע במילה חלופית שנמצאת רק בהערה — נפתחת ומודגשת (issue #3824)',
      (tester) async {
        final bloc = await pumpSplitedView(tester);

        await openResult(
          tester,
          bloc,
          2,
          search: const UpdateSearchText(
            query,
            alternativeWords: {
              0: ['שורש'],
            },
            searchMode: SearchMode.advanced,
          ),
        );

        expect(find.byType(PanelOpenHandle), findsNothing);
        expect(isHighlightedIn(tester, 'שורש הדין', term: 'שורש'), isTrue);
      },
      skip: !engineReady,
    );

    for (final search in const [
      UpdateSearchText(
        'הערה מקור',
        searchMode: SearchMode.fuzzy,
      ),
      UpdateSearchText(
        'על ראשון',
        searchMode: SearchMode.advanced,
        searchDistance: 1,
      ),
    ]) {
      testWidgets('תוצאת מנוע ${search.text} נחשפת ומודגשת באותם פרמטרים', (
        tester,
      ) async {
        final bloc = await pumpSplitedView(tester);
        await openResult(tester, bloc, 0, search: search);
        expect(find.byType(PanelOpenHandle), findsNothing);
        expect(
          isHighlightedIn(
            tester,
            'מקור ראשון',
            term: search.searchMode == SearchMode.fuzzy ? 'מקור' : 'ראשון',
          ),
          isTrue,
        );
      }, skip: !engineReady);
    }

    testWidgets('בחירת שורה רגילה אינה פותחת חלונית שנסגרה', (tester) async {
      final bloc = await pumpSplitedView(tester);
      await openResult(tester, bloc, 0);
      await togglePane(tester);
      bloc.add(const UpdateSelectedIndex(1));
      await tester.pumpAndSettle();
      expect(find.byType(PanelOpenHandle), findsOneWidget);
    }, skip: !engineReady);

    testWidgets('בחירה חוזרת באותה תוצאת חיפוש פותחת את ההערה', (tester) async {
      final bloc = await pumpSplitedView(tester);
      await openResult(tester, bloc, 0);
      await togglePane(tester);
      await openResult(tester, bloc, 0);
      expect(find.byType(PanelOpenHandle), findsNothing);
      expect(isHighlightedIn(tester, 'מקור ראשון'), isTrue);
    }, skip: !engineReady);

    TextBookLoaded pendingState({int line = 1, bool initial = false}) =>
        loadedState(
          searchText: initial ? query : '',
        ).copyWith(
          content: [content[0], '', content[2], content[3]],
          bookNotes: BookNotes.empty,
          loadedLineFlags: const [true, false, true, true],
          searchResultNavigation: initial ? (line: line, requestId: 100) : null,
        );

    Future<void> finishLoading(
      WidgetTester tester,
      _TestTextBookBloc bloc,
    ) async {
      final state = bloc.state as TextBookLoaded;
      bloc.emitLoaded(
        state.copyWith(
          content: [
            content[0],
            'פסקה שנייה<i class="footnote">הערה על מקור שני</i>',
            content[2],
            content[3],
          ],
          loadedLineFlags: const [true, true, true, true],
          contentVersion: state.contentVersion + 1,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('תוצאה ממתינה לתוכן באורך קבוע ונפתחת כשההערה נטענת', (
      tester,
    ) async {
      final bloc = await pumpSplitedView(tester, initial: pendingState());
      await openResult(tester, bloc, 1);
      expect(find.byType(PanelOpenHandle), findsOneWidget);
      await finishLoading(tester, bloc);
      expect(find.byType(PanelOpenHandle), findsNothing);
      expect(isHighlightedIn(tester, 'מקור שני'), isTrue);
    }, skip: !engineReady);

    testWidgets('בחירה ידנית מבטלת תוצאה שממתינה לתוכן', (tester) async {
      final bloc = await pumpSplitedView(tester, initial: pendingState());
      await openResult(tester, bloc, 1);
      bloc.add(const UpdateSelectedIndex(0));
      await tester.pumpAndSettle();
      await finishLoading(tester, bloc);
      expect(find.byType(PanelOpenHandle), findsOneWidget);
    }, skip: !engineReady);

    testWidgets('שינוי חיפוש מבטל תוצאה שממתינה לתוכן', (tester) async {
      final bloc = await pumpSplitedView(tester, initial: pendingState());
      await openResult(tester, bloc, 1);
      bloc.add(const UpdateSearchText('מקור שני'));
      await tester.pumpAndSettle();
      await finishLoading(tester, bloc);
      expect(find.byType(PanelOpenHandle), findsOneWidget);
    }, skip: !engineReady);

    testWidgets('סגירה ידנית צורכת בקשה גם לפני שהתוכן נטען', (tester) async {
      final bloc = await pumpSplitedView(tester, initial: pendingState());
      await togglePane(tester);
      await openResult(tester, bloc, 1);
      await togglePane(tester);
      await finishLoading(tester, bloc);
      expect(find.byType(PanelOpenHandle), findsOneWidget);
    }, skip: !engineReady);

    testWidgets('תוצאה ראשונית מהחיפוש הכללי ממתינה להערה', (tester) async {
      final bloc = await pumpSplitedView(
        tester,
        initial: pendingState(initial: true),
      );
      await finishLoading(tester, bloc);
      expect(find.byType(PanelOpenHandle), findsNothing);
    }, skip: !engineReady);

    testWidgets('שינוי שאילתה מבטל גם תוצאה ראשונית שטרם נטענה', (
      tester,
    ) async {
      final bloc = await pumpSplitedView(
        tester,
        initial: pendingState(initial: true),
      );
      bloc.add(const UpdateSearchText('מקור שני'));
      await tester.pumpAndSettle();
      await finishLoading(tester, bloc);
      expect(find.byType(PanelOpenHandle), findsOneWidget);
    }, skip: !engineReady);

    testWidgets('בחירה ידנית מבטלת גם תוצאה ראשונית שטרם נטענה', (
      tester,
    ) async {
      final bloc = await pumpSplitedView(
        tester,
        initial: pendingState(initial: true),
      );
      bloc.add(const UpdateSelectedIndex(0));
      await tester.pumpAndSettle();
      await finishLoading(tester, bloc);
      expect(find.byType(PanelOpenHandle), findsOneWidget);
    }, skip: !engineReady);

    testWidgets(
      'חלונית שנסגרה אינה נפתחת שוב מעצמה לאותה תוצאה',
      (tester) async {
        final bloc = await pumpSplitedView(tester);
        await openResult(tester, bloc, 0);
        await togglePane(tester);

        // שינוי מצב שאינו תוצאה חדשה (הוספת מפרש) מריץ שוב את הבדיקה.
        bloc.add(const UpdateCommentators([kNotesCommentatorTitle, 'רש"י']));
        await tester.pumpAndSettle();

        expect(find.byType(PanelOpenHandle), findsOneWidget);
      },
      skip: !engineReady,
    );

    testWidgets(
      'חלונית שנסגרה אינה נפתחת מעצמה כשהבחירה מתאפסת בגלילה',
      (tester) async {
        final bloc = await pumpSplitedView(tester);
        await openResult(tester, bloc, 1);
        await togglePane(tester);

        // הקורא מאפס את הבחירה כשהשורה יוצאת מהתצוגה; השורה העליונה (0)
        // מכילה את המונח רק בהערה, ובכל זאת אין כאן מעבר לתוצאה.
        bloc.add(const UpdateSelectedIndex(null));
        await tester.pumpAndSettle();

        expect(find.byType(PanelOpenHandle), findsOneWidget);
      },
      skip: !engineReady,
    );
  });

  testWidgets(
    '"מפרשים מתחת": מונח החיפוש מודגש בהערות שמתחת לקטע (issue #3824)',
    (tester) async {
      final bloc = _TestTextBookBloc(
        loadedState(
          activeCommentators: const [kNotesCommentatorTitle],
          searchText: query,
        ),
      );
      final settingsBloc = _TestSettingsBloc(SettingsState.initial());
      final highlight = ValueNotifier<String>(query);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await bloc.close();
        await settingsBloc.close();
        highlight.dispose();
      });

      // כמו כרטיס המפרשים של התצוגה המשולבת: שורה אחת, בלי שדה חיפוש פנימי.
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 500,
                child: CommentaryListBase(
                  indexes: const [1],
                  openBookCallback: (_) {},
                  fontSize: 18,
                  showSearch: false,
                  shrinkWrap: true,
                  highlightQueryListenable: highlight,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(isHighlightedIn(tester, 'מקור שני'), isTrue);
    },
    skip: !engineReady,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  int _requestId = 0;

  void emitLoaded(TextBookLoaded value) => emit(value);

  _TestTextBookBloc(super.initialState) {
    on<UpdateSearchText>(
      (event, emit) => emit(
        (state as TextBookLoaded).copyWith(
          searchText: event.text,
          clearSearchResultNavigation:
              event.text != (state as TextBookLoaded).searchText ||
              event.searchMode != null ||
              event.alternativeWords != null,
          alternativeWords: event.alternativeWords,
          searchMode: event.searchMode,
          searchDistance: event.searchDistance,
          searchOptions: event.searchOptions,
          spacingValues: event.spacingValues,
          matchPolicy: event.matchPolicy,
        ),
      ),
    );
    on<UpdateSearchResultLines>(
      (event, emit) => emit(
        (state as TextBookLoaded).copyWith(searchResultLines: event.lines),
      ),
    );
    on<UpdateSelectedIndex>(
      (event, emit) => emit(
        (state as TextBookLoaded).copyWith(
          searchResultNavigation: event is SelectSearchResult
              ? (line: event.index!, requestId: ++_requestId)
              : null,
          clearSearchResultNavigation: event is! SelectSearchResult,
          selectedIndex: event.index,
          clearSelectedIndex: event.index == null,
          selectedIndices: {if (event.index != null) event.index!},
          clearSelectedIndices: event.index == null,
        ),
      ),
    );
    on<UpdateCommentators>(
      (event, emit) => emit(
        (state as TextBookLoaded).copyWith(
          activeCommentators: event.commentators,
        ),
      ),
    );
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTourCubit extends Cubit<TourState> implements TourCubit {
  _TestTourCubit() : super(const TourState.inactive());

  @override
  Future<void> recordInteraction(TourInteraction interaction) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
