import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/note_tile.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_sidebar.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/reading_toc.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Widget buildPanel({
    int? initialTabIndex,
    Function(int)? onTabChanged,
    bool showSplitView = true,
    TextBookTab? tab,
    _RecordingTabsBloc? tabsBloc,
    List<String> activeCommentators = const [],
    _TestTextBookBloc? textBookBlocOverride,
    Widget? notesFooter,
    String? notesBookIdOverride,
    PersonalNotesState notesState = const PersonalNotesState.initial(),
    LibraryBloc? libraryBloc,
  }) {
    final textBookBloc =
        textBookBlocOverride ??
        _TestTextBookBloc(
          _loadedState(activeCommentators: activeCommentators),
        );
    final personalNotesBloc = _TestPersonalNotesBloc(notesState);
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    return MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          if (tabsBloc != null) BlocProvider<TabsBloc>.value(value: tabsBloc),
          if (libraryBloc != null)
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
        ],
        child: Scaffold(
          body: TabbedCommentaryPanel(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: true,
            initialTabIndex: initialTabIndex,
            onTabChanged: onTabChanged,
            showSplitView: showSplitView,
            tab: tab,
            notesFooter: notesFooter,
            notesBookIdOverride: notesBookIdOverride,
          ),
        ),
      ),
    );
  }

  testWidgets('ה-footer נשמר בספר הראשי ומוסתר בהערות מפרש שנפתח', (
    tester,
  ) async {
    const footer = Text('הערות המפרשים');
    await tester.pumpWidget(
      buildPanel(
        initialTabIndex: kNotesTabIndex,
        notesFooter: footer,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PersonalNotesSidebar>(find.byType(PersonalNotesSidebar))
          .footer,
      same(footer),
    );

    await tester.pumpWidget(
      buildPanel(
        initialTabIndex: kNotesTabIndex,
        notesFooter: footer,
        notesBookIdOverride: 'רש"י',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PersonalNotesSidebar>(find.byType(PersonalNotesSidebar))
          .footer,
      isNull,
    );
  });

  testWidgets('סימון טקסט בטקסט הראשי אינו בונה מחדש את חלונית המפרשים', (
    tester,
  ) async {
    // הסימון מתעדכן בכל תזוזת עכבר בזמן גרירה, והחלונית מאזינה ל-bloc בעצמה:
    // בלי שער כל תזוזה בונה את כל המפרשים מחדש (issue #976).
    final initial = _loadedState();
    final textBookBloc = _TestTextBookBloc(initial);
    await tester.pumpWidget(buildPanel(textBookBlocOverride: textBookBloc));
    await tester.pump();

    final before = tester.widget(find.byType(TabBarView));

    for (var i = 0; i < 3; i++) {
      textBookBloc.emitState(
        initial.copyWith(
          selectedTextForNote: 'טקסט $i',
          selectedTextSectionIndex: 0,
          selectedTextStart: i,
          selectedTextEnd: i + 4,
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    expect(
      identical(tester.widget(find.byType(TabBarView)), before),
      isTrue,
      reason: 'החלונית לא נבנתה מחדש בגלל עדכוני סימון',
    );

    textBookBloc.emitState(
      initial.copyWith(activeCommentators: const ['רש"י']),
    );
    await tester.pump();
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(TabBarView)), before),
      isFalse,
      reason: 'שינוי אמיתי במפרשים הפעילים כן בונה מחדש',
    );
  });

  testWidgets('מציג את שלושת הכרטיסיות', (tester) async {
    await tester.pumpWidget(buildPanel());
    await tester.pump();

    expect(find.text('מפרשים'), findsOneWidget);
    expect(find.text('קישורים'), findsOneWidget);
    expect(find.text('הערות'), findsOneWidget);
  });

  testWidgets('לשונית סינון המפרשים מציגה את אייקון כרטיסיית המפרשים', (
    tester,
  ) async {
    await tester.pumpWidget(buildPanel(showSplitView: false));
    await tester.pump();

    expect(find.text('סינון מפרשים'), findsOneWidget);
    expect(find.byIcon(OtzariaIcons.apps_list_24_regular), findsOneWidget);
  });

  testWidgets('onTabChanged נקרא עם האינדקס הנכון כשהמשתמש מחליף טאב', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reportedIndex = -1;

    await tester.pumpWidget(
      buildPanel(
        initialTabIndex: 0,
        onTabChanged: (index) => reportedIndex = index,
      ),
    );
    await tester.pump();

    // לחיצה על "קישורים" (טאב 1)
    await tester.tap(find.text('קישורים'));
    await tester.pumpAndSettle();

    expect(reportedIndex, 1);
  });

  testWidgets('onTabChanged נקרא עם אינדקס 2 כשלוחצים על הערות', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reportedIndex = -1;

    await tester.pumpWidget(
      buildPanel(
        initialTabIndex: 0,
        onTabChanged: (index) => reportedIndex = index,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('הערות'));
    await tester.pumpAndSettle();

    expect(reportedIndex, 2);
  });

  testWidgets('שינוי initialTabIndex גורם למעבר לטאב החדש', (tester) async {
    // בדיקה ש-didUpdateWidget מחליף טאב כשהאינדקס משתנה
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reportedIndex = -1;

    await tester.pumpWidget(
      _TabSwitcherWrapper(
        initialTabIndex: 0,
        onTabChanged: (index) => reportedIndex = index,
      ),
    );
    await tester.pump();

    // מעבר פרוגרמטי לטאב 2 (הערות)
    final state = tester.state<_TabSwitcherWrapperState>(
      find.byType(_TabSwitcherWrapper),
    );
    state.switchTo(2);
    await tester.pumpAndSettle();

    expect(reportedIndex, 2);
  });

  testWidgets('initialTabIndex זהה לא מאפס טאב שנשתנה ידנית (P1 regression)', (
    tester,
  ) async {
    // תרחיש: פתיחה על מפרשים (0), משתמש עובר לקישורים (1),
    // הורה שולח שוב initialTabIndex: 0 — הטאב צריך להישאר על 1 (בחירת המשתמש)
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var reportedIndex = -1;

    await tester.pumpWidget(
      _TabSwitcherWrapper(
        initialTabIndex: 0,
        onTabChanged: (index) => reportedIndex = index,
      ),
    );
    await tester.pump();

    // משתמש עובר לקישורים
    await tester.tap(find.text('קישורים'));
    await tester.pumpAndSettle();
    expect(reportedIndex, 1);

    // הורה שולח שוב אותו initialTabIndex: 0 (לא השתנה)
    final state = tester.state<_TabSwitcherWrapperState>(
      find.byType(_TabSwitcherWrapper),
    );
    state.switchTo(0); // לא שינוי — אותו ערך
    await tester.pumpAndSettle();

    // הטאב צריך להישאר על 1 (בחירת המשתמש) ולא לחזור ל-0
    expect(reportedIndex, 1);
  });

  testWidgets('כפתור ההרחבה מוסיף CommentatorsTab ל-TabsBloc', (tester) async {
    // הגדרת רוחב מסוים כדי שכל הלחצנים ייכנסו בלי תפריט גלישה
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sourceTab = TextBookTab(
      book: TextBook(title: 'ספר בדיקה'),
      index: 0,
      blocOverride: _TestTextBookBloc(
        _loadedState(activeCommentators: const ['רש"י']),
      ),
    );
    addTearDown(sourceTab.dispose);

    final tabsBloc = _RecordingTabsBloc();
    addTearDown(tabsBloc.close);

    await tester.pumpWidget(
      buildPanel(
        tab: sourceTab,
        tabsBloc: tabsBloc,
        activeCommentators: const ['רש"י'],
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('פתח כרטיסיית מפרשים'));
    await tester.pump();

    expect(tabsBloc.recordedEvents, hasLength(1));
    final event = tabsBloc.recordedEvents.single;
    expect(event, isA<AddTab>());
    expect((event as AddTab).tab, isA<CommentatorsTab>());
    expect((event.tab as CommentatorsTab).sourceTab, same(sourceTab));
  });
  testWidgets('note navigation scrolls to the one based source line', (
    tester,
  ) async {
    final lines = LineScrollController();
    addTearDown(lines.dispose);
    final navigated = <int>[];
    lines.externalNavigator = (line) async => navigated.add(line);
    const content = [
      '<h2>א</h2>',
      '1',
      '2',
      '3',
      '<h2>ב</h2>',
      '5',
      '6',
      '7',
      '8',
    ];
    final bloc = _TestTextBookBloc(
      _loadedState().copyWith(
        content: content,
        continuousReadingMode: true,
        supportsContinuousReadingMode: true,
        tableOfContents: headerToc(content),
      ),
    );
    addTearDown(bloc.close);
    await tester.pumpWidget(
      LineScrollScope(
        controller: lines,
        child: buildPanel(
          initialTabIndex: kNotesTabIndex,
          textBookBlocOverride: bloc,
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<PersonalNotesSidebar>(find.byType(PersonalNotesSidebar))
        .onNavigateToLine(8);
    await tester.pumpAndSettle();
    expect(navigated, [7]);
    expect(bloc.recordedEvents.whereType<UpdateSelectedIndex>().last.index, 7);
    expect(bloc.recordedEvents.whereType<HighlightLine>().last.lineIndex, 7);
  });

  // issue #2532: הערה על מילים בסוף שורה ארוכה גוללת אליהן ולא לראש השורה.
  testWidgets('לחיצה על הערה במילים גוללת למיקומן בתוך השורה', (tester) async {
    final lines = LineScrollController();
    addTearDown(lines.dispose);
    lines.externalNavigator = (_) async {};
    final longLine =
        '${List.filled(80, '<b>מילה</b> ארוכה').join(' ')} יעד ההערה סוף';
    final content = ['<h2>א</h2>', 'שורה', longLine];
    final note = PersonalNote(
      id: 'n1',
      bookId: 'ספר בדיקה',
      lineNumber: 3,
      anchorText: 'יעד ההערה',
      anchorStart: longLine.indexOf('יעד'),
      lastKnownLineNumber: 3,
      status: PersonalNoteStatus.located,
      content: 'תוכן',
      contentPlain: 'תוכן',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final bloc = _TestTextBookBloc(_loadedState().copyWith(content: content));
    addTearDown(bloc.close);
    await tester.pumpWidget(
      LineScrollScope(
        controller: lines,
        child: buildPanel(
          initialTabIndex: kNotesTabIndex,
          textBookBlocOverride: bloc,
          notesBookIdOverride: 'ספר בדיקה',
          notesState: PersonalNotesState(
            isLoading: false,
            bookId: 'ספר בדיקה',
            locatedNotes: [note],
            missingNotes: const [],
            errorMessage: null,
            showOnlyVisible: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.widget<NoteTile>(find.byType(NoteTile)).onTap!();
    await tester.pumpAndSettle();

    expect(lines.position.value?.topLine, 2);
    expect(lines.position.value?.intraLineFraction, greaterThan(0.95));
  });

  // הערות מפרש שנפתחו מהמפרשים מוצגות בחלונית מעל קורא של הספר הראשי (הטור).
  group('הערות מפרש בחלונית ההערות (issue #3208)', () {
    // הטור נגמר בחושן משפט סימן תכו, ושורה 50 בבית יוסף היא יורה דעה סימן צח
    // — הרבה אחרי סוף הטור.
    final turToc = [
      TocEntry(text: 'חושן משפט', index: 0, level: 1)
        ..children.add(TocEntry(text: 'סימן תכו', index: 1, level: 2)),
    ];
    final beitYosefToc = [
      TocEntry(text: 'יורה דעה', index: 10, level: 1)
        ..children.add(TocEntry(text: 'סימן צח', index: 49, level: 2)),
      TocEntry(text: 'חושן משפט', index: 100, level: 1)
        ..children.add(TocEntry(text: 'סימן תכו', index: 120, level: 2)),
    ];

    PersonalNote noteOn(String bookId) => PersonalNote(
      id: 'by-98',
      bookId: bookId,
      lineNumber: 50,
      displayTitle: 'הערה בשורה 50',
      lastKnownLineNumber: 50,
      status: PersonalNoteStatus.located,
      content: 'הערה על בית יוסף',
      contentPlain: 'הערה על בית יוסף',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    /// ספרייה עם בית יוסף, שתוכן העניינים שלו מגיע מ-[provider].
    LibraryBloc libraryWithBeitYosef(
      _TocProvider provider, {
      List<String> titles = const ['בית יוסף'],
    }) {
      final books = [
        for (final title in titles) TextBook(title: title, categoryId: 2),
      ];
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {
          for (final book in books) BookCompositeKey.fromBook(book)!: provider,
        },
        providers: [provider],
      );
      addTearDown(LibraryProviderManager.instance.resetForTesting);
      final bloc = _TestLibraryBloc(
        LibraryState(
          library: Library(categories: [])..books.addAll(books),
          isLoading: false,
          currentCategory: null,
        ),
      );
      addTearDown(bloc.close);
      return bloc;
    }

    Future<void> pumpNotes(
      WidgetTester tester, {
      required TextBookLoaded reader,
      String? notesBookIdOverride = 'בית יוסף',
      bool showOnlyVisible = false,
      LibraryBloc? libraryBloc,
    }) async {
      final textBookBloc = _TestTextBookBloc(reader);
      addTearDown(textBookBloc.close);
      final notesBookId = notesBookIdOverride ?? reader.book.title;
      await tester.pumpWidget(
        buildPanel(
          initialTabIndex: kNotesTabIndex,
          textBookBlocOverride: textBookBloc,
          notesBookIdOverride: notesBookIdOverride,
          libraryBloc: libraryBloc,
          notesState: PersonalNotesState(
            isLoading: false,
            bookId: notesBookId,
            locatedNotes: [noteOn(notesBookId)],
            missingNotes: const [],
            errorMessage: null,
            showOnlyVisible: showOnlyVisible,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('הכתובת לפי תוכן העניינים של המפרש', (tester) async {
      await pumpNotes(
        tester,
        reader: _loadedState().copyWith(
          book: TextBook(title: 'טור'),
          tableOfContents: turToc,
        ),
        libraryBloc: libraryWithBeitYosef(
          _TocProvider({'בית יוסף': beitYosefToc}),
        ),
      );

      expect(find.text('בית יוסף, חושן משפט, סימן תכו'), findsNothing);
      expect(find.text('בית יוסף, יורה דעה, סימן צח'), findsOneWidget);
    });

    testWidgets('מעבר למפרש שנטען אינו מציג תוכן עניינים של מפרש קודם', (
      tester,
    ) async {
      final pendingToc = Completer<List<TocEntry>?>();
      final libraryBloc = libraryWithBeitYosef(
        _TocProvider({
          'בית יוסף': beitYosefToc,
          'דרכי משה': pendingToc.future,
        }),
        titles: ['בית יוסף', 'דרכי משה'],
      );
      final reader = _loadedState().copyWith(book: TextBook(title: 'טור'));
      await pumpNotes(tester, reader: reader, libraryBloc: libraryBloc);
      expect(find.text('בית יוסף, יורה דעה, סימן צח'), findsOneWidget);

      await pumpNotes(
        tester,
        reader: reader,
        notesBookIdOverride: 'דרכי משה',
        libraryBloc: libraryBloc,
      );
      expect(find.textContaining('יורה דעה'), findsNothing);
      expect(find.text('הערה בשורה 50'), findsOneWidget);

      pendingToc.complete([TocEntry(text: 'סימן אחר', index: 0, level: 1)]);
      await tester.pumpAndSettle();
      expect(find.text('דרכי משה, סימן אחר'), findsOneWidget);
    });

    testWidgets('תוכן העניינים מתעדכן כשהספרייה נטענת ומתרעננת', (
      tester,
    ) async {
      final provider = _TocProvider({'בית יוסף': beitYosefToc});
      final loaded = libraryWithBeitYosef(provider).state.library!;
      final libraryBloc = _TestLibraryBloc(
        const LibraryState(isLoading: true),
      );
      addTearDown(libraryBloc.close);
      await pumpNotes(
        tester,
        reader: _loadedState().copyWith(book: TextBook(title: 'טור')),
        libraryBloc: libraryBloc,
      );
      expect(find.textContaining('יורה דעה'), findsNothing);

      libraryBloc.replaceLibrary(loaded);
      await tester.pumpAndSettle();
      expect(find.text('בית יוסף, יורה דעה, סימן צח'), findsOneWidget);
      await tester.tap(find.byTooltip('פתח'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('סגור'), findsOneWidget);

      provider.tocByTitle['בית יוסף'] = [
        TocEntry(text: 'כותרת מעודכנת', index: 0, level: 1),
      ];
      libraryBloc.replaceLibrary(
        Library(categories: [])..books.addAll(loaded.books),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('יורה דעה'), findsNothing);
      expect(find.text('בית יוסף, כותרת מעודכנת'), findsOneWidget);
      expect(find.byTooltip('סגור'), findsOneWidget);

      final failedToc = Completer<List<TocEntry>?>();
      provider.tocByTitle['בית יוסף'] = failedToc.future;
      libraryBloc.replaceLibrary(
        Library(categories: [])..books.addAll(loaded.books),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('כותרת מעודכנת'), findsNothing);
      failedToc.completeError(StateError('toc'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('כותרת מעודכנת'), findsNothing);
      expect(find.byTooltip('סגור'), findsOneWidget);
    });

    testWidgets('בלי תוכן העניינים של המפרש — ההערה מוצגת בלי כתובת', (
      tester,
    ) async {
      final reader = _loadedState().copyWith(
        book: TextBook(title: 'טור'),
        tableOfContents: turToc,
      );
      final emptyLibrary = _TestLibraryBloc(
        LibraryState(
          library: Library(categories: []),
          isLoading: false,
          currentCategory: null,
        ),
      );
      addTearDown(emptyLibrary.close);

      // המפרש אינו בספרייה
      await pumpNotes(tester, reader: reader, libraryBloc: emptyLibrary);
      expect(find.text('הערה בשורה 50'), findsOneWidget);
      expect(find.textContaining('חושן משפט'), findsNothing);

      // טעינת תוכן העניינים נכשלת
      await tester.pumpWidget(const SizedBox());
      await pumpNotes(
        tester,
        reader: reader,
        libraryBloc: libraryWithBeitYosef(
          _TocProvider(const {}, error: StateError('toc')),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('הערה בשורה 50'), findsOneWidget);
      expect(find.textContaining('חושן משפט'), findsNothing);
    });

    testWidgets('שינוי שיוך אינו מציע את השורה הנבחרת בספר הראשי', (
      tester,
    ) async {
      final reader = _loadedState().copyWith(
        book: TextBook(title: 'טור'),
        selectedIndex: 4,
      );

      // בהערות הספר שבקורא — השורה הנבחרת מוצעת.
      await pumpNotes(tester, reader: reader, notesBookIdOverride: null);
      await tester.tap(find.byTooltip('שנה שיוך לשורה נבחרת'));
      await tester.pumpAndSettle();
      expect(find.text('שייך לשורה נבחרת (5)'), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      // בהערות המפרש — שורה 5 בטור אינה שורה בבית יוסף; רק הקלדת מספר שורה.
      await pumpNotes(tester, reader: reader);
      await tester.tap(find.byTooltip('שנה שיוך לשורה נבחרת'));
      await tester.pumpAndSettle();
      expect(find.text('שייך לשורה נבחרת (5)'), findsNothing);
      expect(find.text('מיקום נוכחי: שורה 50'), findsOneWidget);
    });

    testWidgets('"רק לטקסט הנראה" אינו מסנן לפי השורות הנראות בספר הראשי', (
      tester,
    ) async {
      final reader = _loadedState().copyWith(
        book: TextBook(title: 'טור'),
        visibleIndices: const [0, 1],
      );

      await pumpNotes(tester, reader: reader, showOnlyVisible: true);

      expect(find.text('אין הערות לטקסט הנראה במסך'), findsNothing);
      expect(find.text('הערה בשורה 50'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
    });
  });
}

// ===== Wrapper widget לבדיקת דינמיקת initialTabIndex =====

class _TabSwitcherWrapper extends StatefulWidget {
  const _TabSwitcherWrapper({
    required this.initialTabIndex,
    this.onTabChanged,
  });

  final int initialTabIndex;
  final Function(int)? onTabChanged;

  @override
  State<_TabSwitcherWrapper> createState() => _TabSwitcherWrapperState();
}

class _TabSwitcherWrapperState extends State<_TabSwitcherWrapper> {
  late int _currentTabIndex;

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.initialTabIndex;
  }

  void switchTo(int index) {
    setState(() => _currentTabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final textBookBloc = _TestTextBookBloc(_loadedState());
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    return MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: TabbedCommentaryPanel(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: true,
            initialTabIndex: _currentTabIndex,
            onTabChanged: widget.onTabChanged,
            showSplitView: true,
          ),
        ),
      ),
    );
  }
}

// ===== Helpers =====

TextBookLoaded _loadedState({
  List<String> activeCommentators = const [],
}) => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: const ['שורה א', 'שורה ב'],
  fontSize: 18,
  showSplitView: true,
  showPageShapeView: false,
  activeCommentators: activeCommentators,
  commentatorGroups: const [],
  availableCommentators: activeCommentators,
  links: const <Link>[],
  visibleLinks: const <Link>[],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: null,
  pinLeftPane: false,
  searchText: '',
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  final List<TextBookEvent> recordedEvents = [];
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {
      recordedEvents.add(event);
    });
  }

  void emitState(TextBookState next) => emit(next);

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

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLibraryBloc extends Bloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  _TestLibraryBloc(super.initialState) {
    on<LibraryEvent>((event, emit) {});
  }

  void replaceLibrary(Library library) => emit(LibraryState(library: library));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TocProvider implements LibraryProvider {
  _TocProvider(this.tocByTitle, {this.error});

  final Map<String, FutureOr<List<TocEntry>?>> tocByTitle;
  final Object? error;

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    if (error case final error?) throw error;
    return tocByTitle[title];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingTabsBloc extends Bloc<TabsEvent, TabsState>
    implements TabsBloc {
  _RecordingTabsBloc() : super(TabsState.initial()) {
    on<TabsEvent>((event, emit) {
      recordedEvents.add(event);
    });
  }

  final List<TabsEvent> recordedEvents = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
