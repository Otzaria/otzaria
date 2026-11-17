import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticResultSource, SemanticPassageHighlight;

import 'semantic_ui_test_support.dart';

class Request {
  Request(this.query, this.offset);
  final String query;
  final int offset;
  final complete = Completer<SemanticResultsPage?>();
}

class ControlledSource extends FakeResultsSource {
  final requests = <Request>[];
  @override
  Future<SemanticResultsPage?> fetch(
    SemanticQueryOptions options, {
    required int offset,
    required int limit,
  }) {
    final request = Request(options.query, offset);
    requests.add(request);
    return request.complete.future;
  }
}

SemanticResultsPage page(
  int start, {
  bool restart = false,
  String mode = 'hybrid',
  bool semantic = false,
}) => SemanticResultsPage(
  items: [
    for (var id = start; id < start + 30; id++)
      resultItem(
        id,
        source: semantic
            ? SemanticResultSource.semantic
            : SemanticResultSource.both,
      ),
  ],
  hasMore: true,
  sessionRestarted: restart,
  executedMode: mode,
  semanticAvailable: mode != 'lexicalOnly',
  latencyMs: 0,
  totalCount: 100,
  lexicalTotalCount: 100,
  countsAreExact: false,
  truncated: false,
  candidateWindowTruncated: false,
);
Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> first(
  SemanticResultsBloc bloc,
  ControlledSource source, {
  String mode = 'hybrid',
  bool semantic = false,
}) async {
  bloc.add(const SemanticSearchSubmitted(SemanticQueryOptions(query: 'old')));
  await settle();
  source.requests[0].complete.complete(page(1, mode: mode, semantic: semantic));
  await settle();
}

void main() {
  test(
    'late flagged continuation cannot restart a newer user search',
    () async {
      final source = ControlledSource();
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      await first(bloc, source);
      bloc.add(const SemanticMoreResultsRequested());
      await settle();
      bloc.add(
        const SemanticSearchSubmitted(SemanticQueryOptions(query: 'new')),
      );
      await settle();
      source.requests[2].complete.complete(page(101));
      await settle();
      final newId = bloc.state.searchId;
      source.requests[1].complete.complete(page(201, restart: true));
      await settle();
      expect(source.requests.map((r) => r.query), ['old', 'old', 'new']);
      expect(bloc.state.searchId, newId);
      expect(bloc.state.options!.query, 'new');
      expect(bloc.state.items.first.id, BigInt.from(101));
      expect(recorder.searches.map((s) => s.query), ['old', 'new']);
    },
  );
  test(
    'cancel during automatic restart suppresses its late first page and feedback',
    () async {
      final source = ControlledSource();
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      await first(bloc, source);
      bloc.add(const SemanticMoreResultsRequested());
      await settle();
      source.requests[1].complete.complete(page(101, restart: true));
      await settle();
      expect(bloc.state.status, SemanticResultsStatus.loading);
      bloc.add(const SemanticSearchCancelRequested());
      await settle();
      source.requests[2].complete.complete(page(101));
      await settle();
      expect(bloc.state.status, SemanticResultsStatus.cancelled);
      expect(bloc.state.items, isEmpty);
      expect(bloc.searchContext, isNull);
      expect(recorder.searches, hasLength(1));
      expect(recorder.shown, hasLength(1));
    },
  );
  test(
    'late old passage highlights cannot contaminate the refreshed page',
    () async {
      final source = ControlledSource();
      final recorder = RecordingRecorder();
      final oldMark = Completer<List<SemanticPassageHighlight>>();
      final newMark = Completer<List<SemanticPassageHighlight>>();
      var calls = 0;
      source.highlighter = (items, cancel) {
        calls++;
        return calls == 1 ? oldMark.future : newMark.future;
      };
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      await first(bloc, source, semantic: true);
      final oldHandle = source.highlightHandles.single;
      bloc.add(const SemanticMoreResultsRequested());
      await settle();
      source.requests[1].complete.complete(
        page(101, restart: true, semantic: true),
      );
      await settle();
      source.requests[2].complete.complete(page(101, semantic: true));
      await settle();
      expect(oldHandle.isCancelled, isTrue);
      oldMark.complete(
        markAll([
          for (var i = 1; i <= 6; i++)
            resultItem(i, source: SemanticResultSource.semantic),
        ], clause: 'old'),
      );
      await settle();
      expect(bloc.state.passageHighlights, isEmpty);
      newMark.complete(
        markAll([
          for (var i = 101; i <= 106; i++)
            resultItem(i, source: SemanticResultSource.semantic),
        ], clause: 'new'),
      );
      await settle();
      expect(bloc.state.passageHighlights[0], contains('new 101'));
      expect(
        bloc.state.passageHighlights.values.every((v) => !v.contains('old')),
        isTrue,
      );
    },
  );
  test(
    'fallback to semantic recovery restarts rather than combining two orders',
    () async {
      final source = ControlledSource();
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      await first(bloc, source, mode: 'lexicalOnly');
      bloc.add(const SemanticMoreResultsRequested());
      await settle();
      source.requests[1].complete.complete(page(101));
      await settle();
      expect(source.requests.map((r) => r.offset), [0, 30, 0]);
      source.requests[2].complete.complete(page(101));
      await settle();
      expect(bloc.state.items.first.id, BigInt.from(101));
      expect(bloc.state.items, hasLength(30));
      expect(recorder.searches.map((s) => s.response.executedMode), [
        'lexicalOnly',
        'hybrid',
      ]);
      expect(recorder.shown.map((s) => s.offset), [0, 0]);
    },
  );
  test(
    'duplicate more requests during restart cannot append an old page',
    () async {
      final source = ControlledSource();
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      await first(bloc, source);
      bloc.add(const SemanticMoreResultsRequested());
      bloc.add(const SemanticMoreResultsRequested());
      await settle();
      expect(source.requests, hasLength(2));
      source.requests[1].complete.complete(page(101, restart: true));
      await settle();
      bloc.add(const SemanticMoreResultsRequested());
      await settle();
      expect(source.requests, hasLength(3));
      source.requests[2].complete.complete(page(101));
      await settle();
      expect(bloc.state.items, hasLength(30));
      expect(recorder.shown.map((s) => s.offset), [0, 0]);
    },
  );
  test(
    'failed refreshed first page leaves an empty failed state and no new feedback',
    () async {
      final source = ControlledSource();
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      await first(bloc, source);
      bloc.add(const SemanticMoreResultsRequested());
      await settle();
      source.requests[1].complete.complete(page(101, restart: true));
      await settle();
      source.requests[2].complete.completeError(StateError('refresh failed'));
      await settle();
      expect(bloc.state.status, SemanticResultsStatus.failed);
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.hasMore, isFalse);
      expect(bloc.state.isLoadingMore, isFalse);
      expect(bloc.searchContext, isNull);
      expect(recorder.searches, hasLength(1));
      expect(recorder.shown, hasLength(1));
    },
  );
  test(
    'new submission while the refreshed first page is pending wins',
    () async {
      final source = ControlledSource();
      final recorder = RecordingRecorder();
      final bloc = buildResultsBloc(source: source, recorder: recorder);
      addTearDown(bloc.close);
      await first(bloc, source);
      bloc.add(const SemanticMoreResultsRequested());
      await settle();
      source.requests[1].complete.complete(page(101, restart: true));
      await settle();
      bloc.add(
        const SemanticSearchSubmitted(SemanticQueryOptions(query: 'new')),
      );
      await settle();
      source.requests[3].complete.complete(page(201));
      await settle();
      source.requests[2].complete.complete(page(101));
      await settle();
      expect(bloc.state.options!.query, 'new');
      expect(bloc.state.items.first.id, BigInt.from(201));
      expect(recorder.searches.map((s) => s.query), ['old', 'new']);
      expect(recorder.shown, hasLength(2));
      expect(source.cancels, greaterThanOrEqualTo(2));
    },
  );
}
