import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show MergedSibling, SemanticResultSource;

import 'semantic_ui_test_support.dart';

const _options = SemanticQueryOptions(query: 'כיבוד הורים');

Future<void> _settle(SemanticResultsBloc bloc) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
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
      expect(context.params.ranking?['fusionStrategy'], 'weighted');
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
}
