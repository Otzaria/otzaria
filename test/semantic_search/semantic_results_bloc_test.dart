import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search/utils/result_text_status.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_feedback_snapshots.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show MergedSibling, SemanticPassageHighlight, SemanticResultSource;

import 'semantic_ui_test_support.dart';

const _options = SemanticQueryOptions(query: 'כיבוד הורים');

Future<void> _settle(SemanticResultsBloc bloc) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('דפדוף שאיבד את הסשן', () {
    test('מחזיר עמוד ראשון חדש, מאפס הצבעות וסימונים ומשוב', () async {
      final items = [for (var i = 1; i <= 60; i++) resultItem(i)];
      final source = FakeResultsSource(items: items);
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      final oldId = bloc.state.searchId;
      final oldContext = bloc.searchContext;
      bloc.add(const SemanticVoteToggled(0, SearchFeedbackVote.like));
      await _settle(bloc);
      expect(bloc.state.votes, isNotEmpty);

      items
        ..clear()
        ..addAll([for (var i = 101; i <= 160; i++) resultItem(i)]);
      source.restartContinuation = true;
      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);

      expect(bloc.state.items, hasLength(30));
      expect(bloc.state.items.first.id, BigInt.from(101));
      expect(bloc.state.votes, isEmpty);
      expect(bloc.state.passageHighlights, isEmpty);
      expect(bloc.state.searchId, greaterThan(oldId));
      expect(identical(bloc.searchContext, oldContext), isFalse);
      expect(recorder.searches, hasLength(2));
      expect(recorder.shown.map((page) => page.offset), [0, 0]);
      expect(source.fetches.map((page) => page.offset), [0, 30, 0]);
      expect(bloc.state.message, SemanticSearchMessages.resultsRefreshed);

      source.restartContinuation = false;
      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      expect(bloc.state.items, hasLength(60));
      expect(bloc.state.items.map((item) => item.id).toSet(), hasLength(60));
    });

    test('מעבר למצב fallback אינו מצרף סדר אחר', () async {
      final source = FakeResultsSource(total: 60);
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      source.executedMode = 'lexicalOnly';
      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      expect(bloc.state.items, hasLength(30));
      expect(recorder.searches.last.response.executedMode, 'lexicalOnly');
      expect(source.fetches.map((page) => page.offset), [0, 30, 0]);
      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      expect(bloc.state.items, hasLength(60));
    });
  });

  group('שער ההסכמה', () {
    test('בלי הסכמה אין חיפוש ואין רישום', () async {
      final source = FakeResultsSource();
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(
        source: source,
        recorder: recorder,
        consent: FakeConsentStore(SearchFeedbackConsent.declined),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      expect(bloc.state.status, SemanticResultsStatus.unavailable);
      expect(
        bloc.state.message,
        SemanticSearchMessages.consentRequired,
      );
      expect(source.fetches, isEmpty);
      expect(recorder.total, 0);
    });

    test('בלי מקור זמין — לא זמין, בלי רישום', () async {
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: null, recorder: recorder);
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      expect(bloc.state.status, SemanticResultsStatus.unavailable);
      expect(recorder.total, 0);
    });
  });

  group('חיפוש ודפדוף', () {
    test('חיפוש רושם search פעם אחת ו-results_shown לכל עמוד', () async {
      final source = FakeResultsSource(total: 75);
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      expect(bloc.state.status, SemanticResultsStatus.loaded);
      expect(bloc.state.items, hasLength(30));
      expect(bloc.state.hasMore, isTrue);

      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);

      expect(bloc.state.items, hasLength(75));
      expect(bloc.state.hasMore, isFalse);
      expect(recorder.searches, hasLength(1));
      expect(recorder.shown.map((page) => page.offset), [0, 30, 60]);
      expect(recorder.shown.last.results.first.rank, 61);
      expect(recorder.shown.last.results.last.rank, 75);
      expect(source.fetches.map((fetch) => fetch.offset), [0, 30, 60]);
    });

    test('ההקשר נושא את הפרמטרים, התשובה ותמונת המנוע', () async {
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(
        source: FakeResultsSource(total: 3),
        recorder: recorder,
      );
      addTearDown(bloc.close);

      bloc.add(
        const SemanticSearchSubmitted(
          SemanticQueryOptions(
            query: 'תשובה',
            facets: ['/תנ״ך'],
            includeLexical: false,
            groupIdenticalText: false,
          ),
        ),
      );
      await _settle(bloc);

      final context = recorder.searches.single;
      expect(context.searchSessionId, 'id-1');
      expect(context.query, 'תשובה');
      expect(context.params.retrievalMode, 'semanticOnly');
      expect(context.params.grouping, isNull);
      expect(context.params.facets, ['/תנ״ך']);
      expect(context.params.allLibrary, isFalse);
      expect(context.params.pageSize, 30);
      expect(context.params.ranking?['fusionStrategy'], 'rrf');
      expect(context.params.ranking?['foundationalBonus'], 0.002);
      expect(context.params.ranking?['foundationalCandidateShare'], 0.5);
      // החיפוש החכם שולח fuzzy במרחק 0 — ערך קיים ברשימה הסגורה של השרת.
      expect(context.params.lexicalMode, 'fuzzy');
      expect(context.params.fuzzyMaxDistance, 0);
      expect(context.response.executedMode, 'hybrid');
      expect(context.response.totalCount, 3);
      expect(context.engine.state, 'ready');
    });

    test('חיפוש חדש מקבל מזהה סשן חדש', () async {
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(
        source: FakeResultsSource(total: 3),
        recorder: recorder,
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      expect(
        recorder.searches.map((context) => context.searchSessionId).toSet(),
        hasLength(2),
      );
    });

    test('כשל של המנוע מוצג בהודעה העברית', () async {
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(
        source: FakeResultsSource(
          error: const SemanticFailure(SemanticFailureKind.modelMissing),
        ),
        recorder: recorder,
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      expect(bloc.state.status, SemanticResultsStatus.failed);
      expect(
        bloc.state.message,
        SemanticSearchMessages.modelMissing,
      );
      expect(recorder.total, 0);
    });

    test('תוצאה null (הוחלף) מסתיימת כמבוטל', () async {
      final source = FakeResultsSource()..returnsNull = true;
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      expect(bloc.state.status, SemanticResultsStatus.cancelled);
    });

    test('עצירה בזמן חיפוש מבטלת את המקור ולא רושמת', () async {
      final source = FakeResultsSource()..gate = Completer<void>();
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      bloc.add(const SemanticSearchCancelRequested());
      await _settle(bloc);
      source.gate!.complete();
      await _settle(bloc);

      expect(bloc.state.status, SemanticResultsStatus.cancelled);
      expect(source.cancels, greaterThan(0));
      expect(recorder.total, 0);
    });
  });

  group('ספרים אישיים', () {
    test('תוצאה מספר אישי מסומנת ואינה נרשמת בפתיחה ובסימון', () async {
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(
        source: FakeResultsSource(total: 3),
        recorder: recorder,
        userBookPaths: {'id:2'},
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      final flags = recorder.shown.single.results.map((r) => r.isUserBook);
      expect(flags, [false, true, false]);
      expect(bloc.isUserBookAt(1), isTrue);
      expect(
        await bloc.recordOpen(1, SearchFeedbackOpenVia.click),
        isNull,
      );
      bloc.add(const SemanticVoteToggled(1, SearchFeedbackVote.like));
      await _settle(bloc);
      expect(recorder.opens, isEmpty);
      expect(recorder.votes, isEmpty);
    });

    test('רק ספר רשמי שפוענח ציבורי; שלא פוענח — פרטי', () {
      expect(semanticResultIsPrivate(null), isTrue);
      expect(
        semanticResultIsPrivate(TextBook(title: 'א', source: BookSource.user)),
        isTrue,
      );
      expect(
        semanticResultIsPrivate(
          TextBook(title: 'א', source: BookSource.attached('lib')),
        ),
        isTrue,
      );
      expect(semanticResultIsPrivate(TextBook(title: 'א')), isFalse);
    });
  });

  group('פתיחה וסימון', () {
    test('פתיחה מחזירה openId ורושמת פסקה מלאה ודירוג', () async {
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(
        source: FakeResultsSource(total: 3),
        recorder: recorder,
      );
      addTearDown(bloc.close);
      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      final openId = await bloc.recordOpen(2, SearchFeedbackOpenVia.keyboard);

      expect(openId, 'open-1');
      final open = recorder.opens.single;
      expect(open.via, SearchFeedbackOpenVia.keyboard);
      expect(open.result.rank, 3);
      expect(open.result.passageText, 'הפסקה המלאה של ספר 3');
      expect(open.result.passageTextSource, 'line');
      expect(open.result.matchedText, ['מודגש']);
      expect(open.result.snippetText, 'טקסט מודגש 3');
    });

    test('פתיחת sibling: דירוג ומקור של הכרטיס, מיקום של ה-sibling', () async {
      MergedSibling sibling(int n, String path) => MergedSibling(
        title: 'ספר מקביל $n',
        reference: 'ספר מקביל $n, ב',
        id: BigInt.from(100 + n),
        segment: BigInt.from(40 + n),
        isPdf: false,
        filePath: path,
      );
      final parent = SemanticResultItem(
        title: 'ספר 1',
        reference: 'ספר 1, א',
        snippetHtml: 'טקסט',
        isHighlighted: false,
        id: BigInt.one,
        segment: 1,
        isPdf: false,
        filePath: 'id:1',
        source: SemanticResultSource.semantic,
        fusedScore: 0.9,
        semanticScore: 0.8,
        mergedCount: 3,
        merged: [sibling(1, 'id:7'), sibling(2, 'uid:3')],
      );
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(
        source: FakeResultsSource(items: [resultItem(9), parent]),
        recorder: recorder,
        userBookPaths: {'uid:3'},
      );
      addTearDown(bloc.close);
      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      final openId = await bloc.recordOpen(
        1,
        SearchFeedbackOpenVia.background,
        sibling: parent.merged.first,
      );
      final skipped = await bloc.recordOpen(
        1,
        SearchFeedbackOpenVia.click,
        sibling: parent.merged.last,
      );

      expect(openId, isNotNull);
      expect(skipped, isNull);
      final open = recorder.opens.single;
      expect(open.via, SearchFeedbackOpenVia.background);
      expect(open.result.rank, 2);
      expect(open.result.title, 'ספר מקביל 1');
      expect(open.result.reference, 'ספר מקביל 1, ב');
      expect(open.result.segment, 41);
      expect(open.result.source, 'semantic');
      expect(open.result.semanticScore, 0.8);
      expect(open.result.fusedScore, 0.9);
      expect(open.result.passageText, 'הפסקה המלאה של ספר מקביל 1');
    });

    test('לחיצה חוזרת על הסימון הפעיל מבטלת אותו', () async {
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(
        source: FakeResultsSource(total: 3),
        recorder: recorder,
      );
      addTearDown(bloc.close);
      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      bloc.add(const SemanticVoteToggled(0, SearchFeedbackVote.like));
      await _settle(bloc);
      expect(bloc.state.votes, {0: SearchFeedbackVote.like});
      bloc.add(const SemanticVoteToggled(0, SearchFeedbackVote.dislike));
      await _settle(bloc);
      expect(bloc.state.votes, {0: SearchFeedbackVote.dislike});
      bloc.add(const SemanticVoteToggled(0, SearchFeedbackVote.dislike));
      await _settle(bloc);
      expect(bloc.state.votes, isEmpty);

      expect(recorder.votes.map((vote) => vote.vote), [
        SearchFeedbackVote.like,
        SearchFeedbackVote.dislike,
        SearchFeedbackVote.cleared,
      ]);
      expect(recorder.votes.first.result.rank, 1);
    });

    test('רושם שאינו אוסף — שום דבר לא נרשם', () async {
      final recorder = RecordingRecorder()..collecting = false;
      final bloc = buildResultsBloc(
        source: FakeResultsSource(total: 3),
        recorder: recorder,
      );
      addTearDown(bloc.close);
      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      bloc.add(const SemanticVoteToggled(0, SearchFeedbackVote.like));
      await _settle(bloc);

      expect(bloc.state.status, SemanticResultsStatus.loaded);
      expect(await bloc.recordOpen(0, SearchFeedbackOpenVia.click), isNull);
      expect(recorder.total, 0);
    });
  });
  test('חיפוש חדש מתעלם מהשלמת חיפוש ישן', () async {
    final first = FakeResultsSource(items: [resultItem(1)])
      ..gate = Completer<void>();
    final second = FakeResultsSource(items: [resultItem(3)]);
    FakeResultsSource current = first;
    final recorder = RecordingRecorder();
    final bloc = SemanticResultsBloc(
      resolveSource: () async => current,
      feedback: SemanticFeedbackPorts(
        recorder: () => recorder,
        consent: () => FakeConsentStore(),
        newId: () => 'id',
        whenQueued: () async {},
      ),
      isUserBook: (_) async => false,
    );
    addTearDown(bloc.close);
    bloc.add(
      const SemanticSearchSubmitted(SemanticQueryOptions(query: 'first')),
    );
    await _settle(bloc);
    current = second;
    bloc.add(
      const SemanticSearchSubmitted(SemanticQueryOptions(query: 'second')),
    );
    await _settle(bloc);
    first.gate!.complete();
    await _settle(bloc);
    expect(bloc.state.items.single.id, BigInt.from(3));
    expect(bloc.searchContext!.query, 'second');
    expect(recorder.searches, hasLength(1));
  });
  test(
    'ביטול דפדוף מתעלם מהשלמה מאוחרת ומבקשות כפולות',
    () async {
      final source = FakeResultsSource(total: 100);
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      bloc.add(
        const SemanticSearchSubmitted(SemanticQueryOptions(query: 'query')),
      );
      await _settle(bloc);
      source.gate = Completer<void>();
      for (var i = 0; i < 50; i++) {
        bloc.add(const SemanticMoreResultsRequested());
      }
      await _settle(bloc);
      expect(source.fetches, hasLength(2));
      bloc.add(const SemanticSearchCancelRequested());
      await _settle(bloc);
      expect(bloc.state.isLoadingMore, isFalse);
      source.gate!.complete();
      await _settle(bloc);
      expect(bloc.state.items, hasLength(30));
      expect(recorder.shown, hasLength(1));
    },
  );
  test('סגירה בזמן חיפוש מונעת רישום מאוחר', () async {
    final source = FakeResultsSource()..gate = Completer<void>();
    final recorder = RecordingRecorder();
    final bloc = buildResultsBloc(source: source, recorder: recorder);
    bloc.add(
      const SemanticSearchSubmitted(SemanticQueryOptions(query: 'query')),
    );
    await _settle(bloc);
    await bloc.close();
    source.gate!.complete();
    await _settle(bloc);
    expect(bloc.isClosed, isTrue);
    expect(source.cancels, greaterThan(0));
    expect(recorder.total, 0);
  });
  test('פתיחה מושהית דורשת את ההקשר ואת התוצאה של הלחיצה המקורית', () async {
    final recorder = RecordingRecorder();
    final bloc = buildResultsBloc(
      source: FakeResultsSource(total: 3),
      recorder: recorder,
    );
    addTearDown(bloc.close);
    bloc.add(const SemanticSearchSubmitted(_options));
    await _settle(bloc);
    final firstContext = bloc.searchContext!;
    final firstItem = bloc.state.items.first;
    expect(
      await bloc.recordOpen(
        0,
        SearchFeedbackOpenVia.click,
        expectedContext: firstContext,
        expectedItem: resultItem(3),
      ),
      isNull,
    );
    bloc.add(
      const SemanticSearchSubmitted(SemanticQueryOptions(query: 'חיפוש אחר')),
    );
    await _settle(bloc);
    expect(
      await bloc.recordOpen(
        0,
        SearchFeedbackOpenVia.click,
        expectedContext: firstContext,
        expectedItem: firstItem,
      ),
      isNull,
    );
    expect(recorder.opens, isEmpty);
    expect(
      await bloc.recordOpen(
        0,
        SearchFeedbackOpenVia.click,
        expectedContext: bloc.searchContext,
        expectedItem: firstItem,
      ),
      isNotNull,
    );
    expect(recorder.opens.single.result.rank, 1);
    expect(recorder.opens.single.result.title, firstItem.title);
  });

  group('דפדוף לפי hasMore של המקור', () {
    test('אין עוד עמוד כשהמקור אומר כך, גם כשהספירה גדולה', () async {
      final source = FakeResultsSource(total: 75)..reportsHasMore = false;
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      expect(bloc.state.items, hasLength(30));
      expect(bloc.state.hasMore, isFalse);
    });

    test('יש עוד עמוד כשהמקור אומר כך; עמוד ריק סוגר את הדפדוף', () async {
      final source = FakeResultsSource(total: 3)..reportsHasMore = true;
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      expect(bloc.state.hasMore, isTrue);

      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      expect(bloc.state.items, hasLength(3));
      expect(bloc.state.hasMore, isFalse);
      expect(source.fetches.map((f) => f.offset), [0, 3]);
    });
  });

  group('סימון הקטע לפי עניין', () {
    final mixed = [
      resultItem(1),
      resultItem(2, source: SemanticResultSource.semantic),
      resultItem(3, source: SemanticResultSource.lexical),
      resultItem(
        4,
        source: SemanticResultSource.semantic,
        html: unavailableResultText,
      ),
      resultItem(5, source: SemanticResultSource.semantic),
    ];

    blocTest<SemanticResultsBloc, SemanticResultsState>(
      'רק תוצאות לפי עניין עם טקסט; העמוד מוצג לפני הסימון',
      build: () => buildResultsBloc(
        source: FakeResultsSource(items: mixed)
          ..highlighter = (items, _) async => markAll(items),
        recorder: RecordingRecorder(),
      ),
      act: (bloc) => bloc.add(const SemanticSearchSubmitted(_options)),
      wait: const Duration(milliseconds: 20),
      expect: () => [
        isA<SemanticResultsState>().having(
          (s) => s.status,
          'status',
          SemanticResultsStatus.loading,
        ),
        isA<SemanticResultsState>()
            .having((s) => s.status, 'status', SemanticResultsStatus.loaded)
            .having((s) => s.items, 'items', mixed)
            .having((s) => s.passageHighlights, 'highlights', isEmpty),
        isA<SemanticResultsState>()
            .having((s) => s.items, 'items', mixed)
            .having((s) => s.passageHighlights, 'highlights', {
              1: 'לפני <mark>הקטע הקרוב 2</mark> אחרי',
              4: 'לפני <mark>הקטע הקרוב 5</mark> אחרי',
            }),
      ],
    );

    test('באצוות של 6 לפי סדר התצוגה, גם בעמוד הבא', () async {
      final source = FakeResultsSource(
        items: [
          for (var i = 1; i <= 40; i++)
            resultItem(i, source: SemanticResultSource.semantic),
        ],
      )..highlighter = (items, _) async => markAll(items);
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      expect(source.highlightCalls.map((c) => c.items.length), [
        6,
        6,
        6,
        6,
        6,
      ]);
      expect(source.highlightCalls.first.query, _options.query);

      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      expect(source.highlightCalls.map((c) => c.items.length), [
        6,
        6,
        6,
        6,
        6,
        6,
        4,
      ]);
      expect(
        [
          for (final call in source.highlightCalls)
            for (final item in call.items) item.id.toInt(),
        ],
        [for (var i = 1; i <= 40; i++) i],
      );
      expect(bloc.state.passageHighlights.keys, [
        for (var i = 0; i < 40; i++) i,
      ]);
      expect(bloc.state.passageHighlights[39], contains('הקטע הקרוב 40'));
    });

    test('חיפוש חדש מבטל את הסימון הרץ, ותשובתו המאוחרת נזרקת', () async {
      final gate = Completer<void>();
      final source = FakeResultsSource(
        items: [
          for (var i = 1; i <= 8; i++)
            resultItem(i, source: SemanticResultSource.semantic),
        ],
      );
      source.highlighter = (items, cancel) async {
        if (source.highlightCalls.length == 1) await gate.future;
        return markAll(items, clause: 'ישן');
      };
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      final first = source.highlightHandles.single;
      expect(first.isCancelled, isFalse);

      source.highlighter = (items, _) async => markAll(items, clause: 'חדש');
      bloc.add(const SemanticSearchSubmitted(SemanticQueryOptions(query: 'ב')));
      await _settle(bloc);
      expect(first.isCancelled, isTrue);

      // התשובה הישנה מגיעה אחרי הביטול, ורק אז רץ הסימון של החיפוש החדש.
      gate.complete();
      await _settle(bloc);
      expect(identical(source.highlightHandles.last, first), isFalse);
      expect(bloc.state.options?.query, 'ב');
      expect(bloc.state.passageHighlights, hasLength(8));
      expect(
        bloc.state.passageHighlights.values.where((h) => h.contains('ישן')),
        isEmpty,
      );
    });

    test('סגירה מבטלת את הסימון הרץ', () async {
      final source = FakeResultsSource(
        items: [resultItem(1, source: SemanticResultSource.semantic)],
      );
      // כמו המנוע: ביטול מסיים את הקריאה בכשל cancelled.
      source.highlighter = (items, cancel) {
        final done = Completer<List<SemanticPassageHighlight>>();
        cancel.onCancel(
          () => done.completeError(
            const SemanticFailure(SemanticFailureKind.cancelled),
          ),
        );
        return done.future;
      };
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      expect(source.highlightHandles.single.isCancelled, isFalse);
      await bloc.close();
      expect(source.highlightHandles.single.isCancelled, isTrue);
      expect(bloc.state.passageHighlights, isEmpty);
    });

    test('כשל משאיר את הקטע המקורי ועוצר את שאר האצוות', () async {
      final items = [
        for (var i = 1; i <= 12; i++)
          resultItem(i, source: SemanticResultSource.semantic),
      ];
      final source = FakeResultsSource(items: items)
        ..highlighter = (_, _) async =>
            throw const SemanticFailure(SemanticFailureKind.queryFailed);
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      expect(source.highlightCalls, hasLength(1));
      expect(bloc.state.status, SemanticResultsStatus.loaded);
      expect(bloc.state.message, isNull);
      expect(bloc.state.items, items);
      expect(bloc.state.passageHighlights, isEmpty);
    });

    test('תשובה שלא סומנה או שאינה של הפריט — הקטע המקורי נשאר', () async {
      final source = FakeResultsSource(
        items: [
          for (var i = 1; i <= 3; i++)
            resultItem(i, source: SemanticResultSource.semantic),
        ],
      );
      source.highlighter = (items, _) async => [
        SemanticPassageHighlight(
          filePath: items[0].filePath,
          id: items[0].id,
          snippetHtml: '',
          isHighlighted: false,
        ),
        SemanticPassageHighlight(
          filePath: 'id:99',
          id: BigInt.from(99),
          snippetHtml: '<mark>זר</mark>',
          isHighlighted: true,
        ),
        ...markAll([items[2]]),
      ];
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);

      expect(bloc.state.passageHighlights.keys, [2]);
    });

    test('R4: הסימון אינו משנה את תמונת התוצאה שנשלחת לשרת', () async {
      final items = [
        resultItem(
          1,
          source: SemanticResultSource.semantic,
          html: 'כבד את אביך',
        ),
        resultItem(2),
      ];
      final recorder = RecordingRecorder();
      final source = FakeResultsSource(items: items)
        ..highlighter = (items, _) async => markAll(items, clause: 'כבד');
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      expect(bloc.state.passageHighlights.keys, [0]);
      final shown = recorder.shown.single.results.first;

      await bloc.recordOpen(0, SearchFeedbackOpenVia.click);
      bloc.add(const SemanticVoteToggled(0, SearchFeedbackVote.like));
      await _settle(bloc);

      final original = semanticSnippetText('כבד את אביך');
      for (final snapshot in [
        shown,
        recorder.opens.single.result,
        recorder.votes.single.result,
      ]) {
        expect(snapshot.snippetText, original.plain);
        expect(snapshot.matchedText, isEmpty);
        expect(snapshot.source, 'semantic');
        expect(snapshot.semanticScore, items.first.semanticScore);
        expect(snapshot.fusedScore, items.first.fusedScore);
      }
      expect(recorder.opens.single.result.passageText, 'הפסקה המלאה של ספר 1');
      expect(identical(bloc.state.items.first, items.first), isTrue);
    });

    List<SemanticResultItem> semanticItems(int count) => [
      for (var i = 1; i <= count; i++)
        resultItem(i, source: SemanticResultSource.semantic),
    ];

    test(
      'עמוד 2 נטען בזמן שאצוות של עמוד 1 ממתינות: כל סימון במקומו',
      () async {
        final gate = Completer<void>();
        final source = FakeResultsSource(items: semanticItems(60));
        source.highlighter = (items, _) async {
          if (source.highlightCalls.length == 1) await gate.future;
          return markAll(items);
        };
        final bloc = buildResultsBloc(
          source: source,
          recorder: RecordingRecorder(),
        );
        addTearDown(bloc.close);

        bloc.add(const SemanticSearchSubmitted(_options));
        await _settle(bloc);
        expect(source.highlightCalls, hasLength(1));
        bloc.add(const SemanticMoreResultsRequested());
        await _settle(bloc);
        expect(bloc.state.items, hasLength(60));
        bloc.add(const SemanticVoteToggled(3, SearchFeedbackVote.like));
        await _settle(bloc);
        // הסימון של עמוד 2 ממתין מאחורי עמוד 1.
        expect(source.highlightCalls, hasLength(1));

        gate.complete();
        await _settle(bloc);
        expect(bloc.state.passageHighlights, hasLength(60));
        for (var i = 0; i < 60; i++) {
          expect(
            bloc.state.passageHighlights[i],
            contains('הקטע הקרוב ${i + 1}<'),
          );
        }
        expect(bloc.state.votes[3], SearchFeedbackVote.like);
        expect(bloc.state.isLoadingMore, isFalse);
      },
    );

    test('סימון שמגיע בזמן טעינת עמוד שומר את מצב הטעינה', () async {
      final source = FakeResultsSource(items: semanticItems(60));
      final gate = Completer<void>();
      source.highlighter = (items, _) async {
        await gate.future;
        return markAll(items);
      };
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      source.gate = Completer<void>();
      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      expect(bloc.state.isLoadingMore, isTrue);

      gate.complete();
      await _settle(bloc);
      expect(bloc.state.passageHighlights, hasLength(30));
      expect(bloc.state.isLoadingMore, isTrue);

      source.gate!.complete();
      await _settle(bloc);
      expect(bloc.state.isLoadingMore, isFalse);
      expect(bloc.state.items, hasLength(60));
      expect(bloc.state.passageHighlights, hasLength(60));
    });

    test('ביטול טעינת עמוד אינו עוצר את הסימון', () async {
      final source = FakeResultsSource(items: semanticItems(60))
        ..highlighter = (items, _) async => markAll(items);
      final bloc = buildResultsBloc(
        source: source,
        recorder: RecordingRecorder(),
      );
      addTearDown(bloc.close);

      bloc.add(const SemanticSearchSubmitted(_options));
      await _settle(bloc);
      source.gate = Completer<void>();
      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      bloc.add(const SemanticSearchCancelRequested());
      await _settle(bloc);
      source.gate!.complete();
      await _settle(bloc);
      expect(bloc.state.items, hasLength(30));
      expect(bloc.state.passageHighlights, hasLength(30));

      source.gate = null;
      bloc.add(const SemanticMoreResultsRequested());
      await _settle(bloc);
      expect(bloc.state.items, hasLength(60));
      expect(bloc.state.passageHighlights, hasLength(60));
    });
  });
}
