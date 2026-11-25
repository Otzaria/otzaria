import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });
  const anchor = ReadingAnchor(
    line: 12,
    intraLineFraction: 0.9,
    alignment: 0.2,
  );

  for (final phase in ['initial', 'loaded', 'loading', 'error']) {
    for (final results in <Set<int>?>[
      null,
      {},
      {2, 7},
    ]) {
      test('טקסט: $phase משמר תוצאות $results בשכפול ובשמירה', () {
        final loaded = phase == 'loaded';
        final current = _state(phase, results);
        final tab = TextBookTab(
          book: TextBook(title: 'בראשית'),
          index: 12,
          initialReadingAnchor: anchor,
          searchText: 'מקור',
          searchMode: SearchMode.advanced,
          searchDistance: 2,
          searchOptions: const {
            'מקור_0': {'ראשי תיבות': true},
          },
          alternativeWords: const {
            0: ['ראשית'],
          },
          spacingValues: const {'0-1': '2'},
          commentators: ['רש"י'],
          highlightText: 'מקור',
          permanentHighlightLine: 1,
          initialSearchResultLines: loaded ? {99} : results,
          pinpointHighlight: 'מקור',
          pinpointHighlightSectionIndex: 1,
          splitedView: false,
          showPageShapeView: true,
          isPinned: true,
          dedupeKey: 'זמני',
          blocOverride: _StateBloc(current),
        )..historySlot = 'place-$phase';
        addTearDown(tab.dispose);
        final clone = OpenedTab.from(tab) as TextBookTab;
        addTearDown(clone.dispose);
        final json = tab.toJson();
        final restored = TextBookTab.fromJson(json);
        addTearDown(restored.dispose);

        for (final copy in [clone, restored]) {
          expect(copy.historySlot, 'place-$phase');
          expect(copy.searchText, loaded ? 'מעודכן' : 'מקור');
          expect(copy.searchMode, SearchMode.advanced);
          expect(copy.searchDistance, loaded ? 4 : 2);
          expect(copy.searchOptions, {
            '${loaded ? 'מעודכן' : 'מקור'}_0': {'ראשי תיבות': true},
          });
          expect(copy.alternativeWords, {
            0: ['ראשית'],
          });
          expect(copy.spacingValues, {'0-1': '2'});
          expect(copy.highlightText, loaded ? 'מעודכן' : 'מקור');
          expect(copy.permanentHighlightLine, loaded ? 7 : 1);
          expect(copy.initialSearchResultLines, results);
          expect(copy.pinpointHighlight, loaded ? 'מעודכן' : 'מקור');
          expect(copy.pinpointHighlightSectionIndex, loaded ? 7 : 1);
          expect(copy.commentators, loaded ? ['רמב"ן'] : ['רש"י']);
          expect(copy.index, 12);
          expect(copy.readingAnchor, anchor);
          expect(copy.lines, isNot(same(tab.lines)));
          expect(copy.isPinned, isTrue);
        }
        expect(clone.dedupeKey, 'זמני');
        expect(json.containsKey('dedupeKey'), isFalse);
        expect(json['showLeftPane'], current.showLeftPane);
        expect(json['initalIndex'], 12);
        expect(json['readingAnchor'], anchor.toJson());
        expect(json.containsKey('initialSearchResultLines'), results != null);
      });
    }
  }

  test('restored tabs retain independent commentator selections (#4560)', () {
    final book = TextBook(title: 'Shared book');
    for (final selection in <List<String>>[
      ['First'],
      ['Second'],
      <String>[],
    ]) {
      final tab = TextBookTab(book: book, index: 0, commentators: selection);
      addTearDown(tab.dispose);
      final restored = TextBookTab.fromJson(tab.toJson());
      addTearDown(restored.dispose);

      final state = restored.blocState as TextBookInitial;
      expect(state.commentators, selection);
      expect(state.hasExplicitCommentators, isTrue);
    }

    final fresh = TextBookTab(book: book, index: 0);
    addTearDown(fresh.dispose);
    expect(fresh.toJson().containsKey('hasExplicitCommentators'), isFalse);
    expect(
      (fresh.blocState as TextBookInitial).hasExplicitCommentators,
      isFalse,
    );
    final legacy = fresh.toJson()..remove('commentators');
    for (final saved in [
      legacy,
      {...legacy, 'commentators': null},
      {...legacy, 'commentators': <String>[]},
      {...legacy, 'commentators': 'invalid'},
      {
        ...legacy,
        'commentators': [1, 'First'],
      },
    ]) {
      final restored = TextBookTab.fromJson(saved);
      addTearDown(restored.dispose);
      expect(
        (restored.blocState as TextBookInitial).hasExplicitCommentators,
        isFalse,
        reason: '$saved',
      );
    }
  });

  test('שחזור שולחן עבודה שומר בחירה בכל טאב גם אחרי טעינת המפרשים', () async {
    final directory = await Directory.systemTemp.createTemp(
      'commentator_tabs_',
    );
    AppPaths.debugOverrideDataRootPath(directory.path);
    addTearDown(() async {
      await PerBookSettings.settle();
      AppPaths.debugOverrideDataRootPath(null);
      await directory.delete(recursive: true);
    });
    final book = TextBook(
      title: 'ספר בדיקה',
      source: BookSource.official,
    );
    const ownChoices = <List<String>>[
      ['ראשונים'],
      ['אחרונים'],
      [],
    ];
    const savedPerBook = ['מפרש ברירת מחדל'];
    await TextBookPerBookSettings.mutate(
      book,
      (current) => (current ?? TextBookPerBookSettings()).copyWith(
        activeCommentators: savedPerBook,
      ),
    );

    final tabs = [
      for (final selection in ownChoices)
        TextBookTab(
          book: book,
          index: 0,
          commentators: selection,
          openLeftPane: selection == ownChoices.first,
        ),
      TextBookTab(book: book, index: 0),
    ];
    final snapshot = UpdateCurrentWorkspaceTabs(
      sourceWorkspaceId: 'workspace',
      tabs: tabs,
      activeTabIndex: 0,
    );
    for (final tab in tabs) {
      tab.dispose();
    }
    final restored = snapshot.restoreTabs().cast<TextBookTab>();
    final repository = _DelayedCommentatorRepository([
      for (final choice in ownChoices) ...choice,
      ...savedPerBook,
    ]);
    final blocs = [
      for (final tab in restored)
        TextBookBloc(
          repository: repository,
          initialState: tab.blocState as TextBookInitial,
        ),
    ];
    addTearDown(() async {
      for (final bloc in blocs) {
        await bloc.close();
      }
      for (final tab in restored) {
        tab.dispose();
      }
    });

    final initialLoads = [
      for (final bloc in blocs)
        bloc.stream.firstWhere((s) => s is TextBookLoaded),
    ];
    for (final bloc in blocs) {
      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
        ),
      );
    }
    await Future.wait(initialLoads);
    final pending = TextBookTab(book: book, index: 0, blocOverride: blocs.last);
    addTearDown(pending.dispose);
    final pendingSnapshot = pending.toJson();

    final completedLoads = [
      for (final bloc in blocs)
        bloc.stream.firstWhere(
          (s) => s is TextBookLoaded && s.commentatorsLoaded && !s.linksLoading,
        ),
    ];
    repository.ready.complete();
    final results = (await Future.wait(completedLoads)).cast<TextBookLoaded>();
    expect(
      results.map((state) => state.activeCommentators),
      [...ownChoices, savedPerBook],
    );
    expect(results.first.showLeftPane, isTrue);
    final restoredPending = TextBookTab.fromJson(pendingSnapshot);
    addTearDown(restoredPending.dispose);
    expect(
      (restoredPending.blocState as TextBookInitial).hasExplicitCommentators,
      isFalse,
    );
  });

  test('רענון הגדרות שומר בחירת מפרשים שנעשתה בזמן הטעינה', () async {
    final book = TextBook(title: 'ספר אישי', source: BookSource.user);
    final reloadStarted = Completer<void>();
    final reloadNotes = Completer<BookNotes>();
    var notesLoads = 0;
    final bloc = TextBookBloc(
      repository: _Repository(),
      initialState: TextBookInitial.named(book, 0, false, ['מפרש ראשון']),
      bookNotesLoader: (_) {
        if (++notesLoads == 1) return Future.value(BookNotes.empty);
        reloadStarted.complete();
        return reloadNotes.future;
      },
    );
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    addTearDown(tab.dispose);

    final loaded = bloc.stream.firstWhere((state) => state is TextBookLoaded);
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: true,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    await loaded;

    final reloaded = bloc.stream.firstWhere(
      (state) => state is TextBookLoaded && state.fontSize == 22,
    );
    bloc.add(
      const LoadContent(
        fontSize: 22,
        showSplitView: true,
        removeNikud: false,
        preserveState: true,
        loadCommentators: false,
      ),
    );
    await reloadStarted.future;
    final userSelection = bloc.stream.firstWhere(
      (state) => state is TextBookLoaded && state.activeCommentators.isEmpty,
    );
    bloc.add(const UpdateCommentators([]));
    await userSelection;
    reloadNotes.complete(BookNotes.empty);

    expect((await reloaded as TextBookLoaded).activeCommentators, isEmpty);
    final restored = TextBookTab.fromJson(tab.toJson());
    addTearDown(restored.dispose);
    expect(
      (restored.blocState as TextBookInitial).hasExplicitCommentators,
      isTrue,
    );
  });

  test('snapshot לוכד יעד קריאה נוכחי בלי לטעון את הטאב', () async {
    final tab = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 12,
      initialReadingAnchor: anchor,
    );
    addTearDown(tab.dispose);
    await tab.lines.jumpToLine(80, intraLineFraction: 0.3, alignment: 0.4);
    final clone = tab.clone() as TextBookTab;
    final restored = TextBookTab.fromJson(tab.toJson());
    addTearDown(clone.dispose);
    addTearDown(restored.dispose);
    for (final copy in [clone, restored]) {
      expect(
        copy.readingAnchor,
        const ReadingAnchor(line: 80, intraLineFraction: 0.3, alignment: 0.4),
      );
      expect(copy.index, 80);
      expect(copy.lines, isNot(same(tab.lines)));
      // היסטוריית החזרה עוברת לשכפול ולשחזור (issue #4205).
      expect(copy.lines.history.value.back, anchor);
    }
    expect(tab.blocState, isA<TextBookInitial>());
  });

  for (final index in [0, 12]) {
    test('טאב שלא נמדד בשורה $index אינו ממציא עוגן בשכפול ובשמירה', () {
      final tab = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: index,
      );
      addTearDown(tab.dispose);
      final json = tab.toJson();
      expect(json.containsKey('readingAnchor'), isFalse);
      final clone = tab.clone() as TextBookTab;
      final restored = TextBookTab.fromJson(json);
      addTearDown(clone.dispose);
      addTearDown(restored.dispose);
      for (final copy in [clone, restored]) {
        expect(copy.index, index);
        expect(copy.lines.captureAnchor(), isNull);
      }
    });
  }

  test('חלונית פתוחה נשמרת פתוחה, וסגורה נשמרת סגורה', () {
    for (final open in [false, true]) {
      final state = (_state('loaded', null) as TextBookLoaded).copyWith(
        showLeftPane: open,
      );
      final tab = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 0,
        blocOverride: _StateBloc(state),
      );
      addTearDown(tab.dispose);
      final restored = TextBookTab.fromJson(tab.toJson());
      addTearDown(restored.dispose);

      expect(restored.blocState.showLeftPane, open, reason: '$open');
    }
  });

  test('PDF: חלונית פתוחה נשמרת פתוחה, וסגורה נשמרת סגורה', () {
    for (final open in [false, true]) {
      final tab = PdfBookTab(
        book: PdfBook(title: 'ספר', path: '/a.pdf'),
        pageNumber: 1,
        openLeftPane: open,
      );
      addTearDown(tab.dispose);
      final restored = PdfBookTab.fromJson(tab.toJson());
      addTearDown(restored.dispose);

      expect(restored.showLeftPane.value, open, reason: '$open');
    }
  });

  test('PDF: חלונית פתוחה נשמרת שוב גם בטאב שלא הוצג', () {
    final restored = PdfBookTab.fromJson({
      'path': '/a.pdf',
      'book': PdfBook(title: 'ספר', path: '/a.pdf').toJson(),
      'showLeftPane': true,
    });
    addTearDown(restored.dispose);

    expect(restored.toJson()['showLeftPane'], isTrue);
  });

  group('שמירה, שחזור וטעינת הקורא במסך רחב (issue #4126)', () {
    const wide = 1400.0;
    final opener = BookOpenCoordinator(
      tabsBloc: _TabsBloc(),
      historyBloc: _HistoryBloc(),
      navigationBloc: _NavigationBloc(),
      layoutWidth: () => wide,
    );

    Future<TextBookLoaded> loadText(TextBookBloc bloc, double fontSize) async {
      bloc.add(
        LoadContent(
          fontSize: fontSize,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
          preserveState: bloc.state is TextBookLoaded,
        ),
      );
      return await bloc.stream.firstWhere(
            (s) => s is TextBookLoaded && s.fontSize == fontSize,
          )
          as TextBookLoaded;
    }

    Future<PdfBookLoaded> loadPdf(PdfBookTab tab) async {
      final bloc = PdfBookBloc(
        tab: tab,
        initialState: PdfBookInitial(
          book: tab.book,
          initialPageNumber: tab.pageNumber,
          searchText: tab.searchText,
        ),
        pdfrxInit: () async {},
      );
      addTearDown(bloc.close);
      bloc.add(
        DocumentReady(
          documentRef: _DocumentRef(),
          totalPages: 5,
        ),
      );
      return await bloc.stream.firstWhere((s) => s is PdfBookLoaded)
          as PdfBookLoaded;
    }

    test('טקסט: שאילתה שנשארה אינה פותחת חלונית שנשמרה סגורה', () async {
      for (final query in ['מקור', '']) {
        for (final open in [false, true]) {
          final saved = TextBookTab(
            book: TextBook(title: 'בראשית'),
            index: 0,
            blocOverride: _StateBloc(
              (_state('loaded', null) as TextBookLoaded).copyWith(
                searchText: query,
                searchMode: SearchMode.exact,
                showLeftPane: open,
              ),
            ),
          );
          addTearDown(saved.dispose);
          final restored = TextBookTab.fromJson(saved.toJson());
          addTearDown(restored.dispose);
          final bloc = TextBookBloc(
            repository: _Repository(),
            initialState: restored.blocState as TextBookInitial,
          );
          addTearDown(bloc.close);

          // טעינה ראשונה, ואז רענון הגדרות שאינו חיפוש חדש.
          for (final fontSize in [18.0, 19.0]) {
            final loaded = await loadText(bloc, fontSize);
            expect(loaded.searchText, query);
            expect(
              loaded.showLeftPane,
              open,
              reason: 'query="$query" open=$open fontSize=$fontSize',
            );
          }
        }
      }

      final fresh =
          opener.buildTab(TextBook(title: 'בראשית'), 0, 'מקור') as TextBookTab;
      addTearDown(fresh.dispose);
      final bloc = TextBookBloc(
        repository: _Repository(),
        initialState: fresh.blocState as TextBookInitial,
      );
      addTearDown(bloc.close);
      final opened = await loadText(bloc, 18);
      expect(opened.showLeftPane, isTrue);
    });

    test('PDF: שאילתה שנשארה אינה פותחת חלונית שנשמרה סגורה', () async {
      final book = PdfBook(title: 'ספר', path: '/a.pdf');
      for (final query in ['בדיקה', '']) {
        for (final open in [false, true]) {
          final saved = PdfBookTab(
            book: book,
            pageNumber: 1,
            openLeftPane: open,
            searchText: query,
          );
          addTearDown(saved.dispose);
          final restored = PdfBookTab.fromJson(saved.toJson());
          addTearDown(restored.dispose);

          final loaded = await loadPdf(restored);
          expect(loaded.searchText, query);
          expect(
            [loaded.showLeftPane, restored.showLeftPane.value],
            [open, open],
            reason: 'query="$query" open=$open',
          );
        }
      }

      final fresh = opener.buildTab(book, 1, 'בדיקה') as PdfBookTab;
      addTearDown(fresh.dispose);
      final opened = await loadPdf(fresh);
      expect([opened.showLeftPane, fresh.showLeftPane.value], [true, true]);
    });
  });

  test('מצב טעון שנוקה אינו מחזיר חיפוש או הדגשות משדות הטאב', () {
    final cleared = (_state('loaded', {}) as TextBookLoaded).copyWith(
      searchText: '',
      clearHighlightText: true,
      clearPermanentHighlight: true,
      clearSearchResultLines: true,
      clearPinpointHighlight: true,
    );
    final tab = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
      searchText: 'ישן',
      highlightText: 'ישן',
      permanentHighlightLine: 1,
      initialSearchResultLines: {1},
      pinpointHighlight: 'ישן',
      pinpointHighlightSectionIndex: 1,
      blocOverride: _StateBloc(cleared),
    );
    addTearDown(tab.dispose);
    final clone = tab.clone() as TextBookTab;
    addTearDown(clone.dispose);

    expect(clone.searchText, isEmpty);
    expect(clone.highlightText, isEmpty);
    expect(clone.permanentHighlightLine, isNull);
    expect(clone.initialSearchResultLines, isNull);
    expect(clone.pinpointHighlight, isNull);
    final json = tab.toJson();
    for (final field in [
      'searchText',
      'highlightText',
      'permanentHighlightLine',
      'initialSearchResultLines',
      'pinpointHighlight',
      'pinpointHighlightSectionIndex',
    ]) {
      expect(json.containsKey(field), isFalse, reason: field);
    }
  });

  test('שכפול שומר ספר מקורי ושמירה כוללת את ההעשרה מהמצב הטעון', () {
    final originalBook = TextBook(title: 'בראשית');
    final enriched = (_state('loaded', null) as TextBookLoaded).copyWith(
      book: TextBook(title: 'בראשית', id: 42, author: 'מחבר'),
    );
    final tab = TextBookTab(
      book: originalBook,
      index: 0,
      blocOverride: _StateBloc(enriched),
    );
    addTearDown(tab.dispose);
    final clone = tab.clone() as TextBookTab;
    addTearDown(clone.dispose);
    expect(identical(clone.book, originalBook), isTrue);
    expect(tab.toJson()['book'], enriched.book.toJson());
  });

  for (final pdf in [false, true]) {
    test('שכפול ${pdf ? 'PDF' : 'טקסט'} מעתיק אוספים גם בעומק', () {
      final options = {
        'א_0': {'ראשי תיבות': true},
      };
      final alternatives = {
        0: ['מילה'],
      };
      final spacing = {'0-1': '2'};
      final commentators = ['רש"י'];
      final results = {1, 3};
      final OpenedTab tab = pdf
          ? PdfBookTab(
              book: PdfBook(title: 'ספר', path: 'a.pdf'),
              pageNumber: 2,
              searchText: 'א',
              searchOptions: options,
              alternativeWords: alternatives,
              spacingValues: spacing,
            )
          : TextBookTab(
              book: TextBook(title: 'בראשית'),
              index: 2,
              searchText: 'א',
              searchOptions: options,
              alternativeWords: alternatives,
              spacingValues: spacing,
              commentators: commentators,
              initialSearchResultLines: results,
            );
      addTearDown(tab.dispose);
      if (tab is PdfBookTab) tab.activeCommentators.addAll(commentators);
      final clone = tab.clone();
      addTearDown(clone.dispose);
      if (clone is TextBookTab) {
        clone.searchOptions['א_0']!['ראשי תיבות'] = false;
        clone.alternativeWords[0]!.add('שינוי');
        clone.spacingValues['0-1'] = '9';
        clone.commentators!.add('רמב"ן');
        clone.initialSearchResultLines!.add(9);
      } else if (clone is PdfBookTab) {
        clone.searchOptions['א_0']!['ראשי תיבות'] = false;
        clone.alternativeWords[0]!.add('שינוי');
        clone.spacingValues['0-1'] = '9';
        clone.activeCommentators.add('רמב"ן');
        expect((tab as PdfBookTab).activeCommentators, {'רש"י'});
      }
      expect(options, {
        'א_0': {'ראשי תיבות': true},
      });
      expect(alternatives, {
        0: ['מילה'],
      });
      expect(spacing, {'0-1': '2'});
      expect(commentators, ['רש"י']);
      expect(results, {1, 3});
    });
  }

  for (final liveSearch in ['', 'מוקלד']) {
    test('PDF: השמירה משתמשת בבקר החי והשכפול במצב המסונכרן ($liveSearch)', () {
      final tab =
          PdfBookTab(
              book: PdfBook(title: 'ספר', path: 'a.pdf'),
              pageNumber: 7,
              searchText: 'מסונכרן',
              dedupeKey: 'זמני',
              isPinned: true,
            )
            ..pdfViewerController = _PageController()
            ..savedZoom = 1.75
            ..savedLayoutMode = PdfLayoutMode.regularView;
      tab.searchController.text = liveSearch;
      tab.activeCommentators.add('רש"י');
      tab.currentTextLineNumber = 99;
      tab.currentTitle.value = 'נגזר';
      addTearDown(tab.dispose);
      final clone = tab.clone() as PdfBookTab;
      addTearDown(clone.dispose);
      final json = tab.toJson();
      final restored = PdfBookTab.fromJson(json);
      addTearDown(restored.dispose);

      expect(clone.pageNumber, 7);
      expect(restored.pageNumber, 23);
      expect(clone.searchText, 'מסונכרן');
      expect(restored.searchText, liveSearch);
      expect(clone.dedupeKey, 'זמני');
      expect(json.containsKey('dedupeKey'), isFalse);
      for (final copy in [clone, restored]) {
        expect(copy.isPinned, isTrue);
        expect(copy.savedZoom, 1.75);
        expect(copy.savedLayoutMode, PdfLayoutMode.regularView);
        expect(copy.activeCommentators, {'רש"י'});
        expect(copy.currentTextLineNumber, isNull);
        expect(copy.currentTitle.value, isEmpty);
        expect(copy.links, isEmpty);
      }
    });
  }
}

TextBookState _state(String phase, Set<int>? results) {
  final book = TextBook(title: 'בראשית');
  return switch (phase) {
    'initial' => TextBookInitial.named(
      book,
      12,
      true,
      ['רש"י'],
      searchText: 'מקור',
      searchOptions: const {
        'מקור_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ראשית'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 2,
      splitedView: false,
      showPageShapeView: true,
    ),
    'loaded' => TextBookLoaded(
      book: book,
      showLeftPane: true,
      content: const ['א'],
      fontSize: 18,
      showSplitView: true,
      showPageShapeView: false,
      activeCommentators: ['רמב"ן'],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [12],
      selectedIndex: 12,
      searchText: 'מעודכן',
      searchOptions: const {
        'מעודכן_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ראשית'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 4,
      highlightText: 'מעודכן',
      permanentHighlightLine: 7,
      searchResultLines: results,
      pinpointHighlightText: 'מעודכן',
      pinpointHighlightIndex: 7,
    ),
    'loading' => TextBookLoading(book, 12, true, const []),
    _ => TextBookError('שגיאה', book, 12, true, const []),
  };
}

class _StateBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _StateBloc(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PageController extends PdfViewerController {
  @override
  bool get isReady => true;

  @override
  int? get pageNumber => 23;
}

class _TabsBloc extends Fake implements TabsBloc {}

class _NavigationBloc extends Fake implements NavigationBloc {}

class _HistoryBloc extends Fake implements HistoryBloc {
  @override
  HistoryState get state => HistoryLoaded(const []);
}

class _DocumentRef extends Fake implements PdfDocumentRef {}

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  static final _lines = List.generate(20, (i) => 'שורה $i');

  @override
  Future<String> getBookContent(TextBook book) async => _lines.join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async {
    final start = startLine.clamp(0, _lines.length - 1);
    final end = endLine.clamp(start, _lines.length - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: _lines.length,
      lines: _lines.sublist(start, end + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}

class _DelayedCommentatorRepository extends _Repository {
  _DelayedCommentatorRepository(this.commentators);

  final List<String> commentators;
  final ready = Completer<void>();

  @override
  Future<({List<String> all, Set<String> rare})> getCommentatorsWithRarity(
    TextBook book,
  ) async {
    await ready.future;
    return (all: commentators, rare: const <String>{});
  }

  @override
  Future<Map<String, BookSource>> getExternalCommentatorSources(
    TextBook book,
  ) async => const {};
}
