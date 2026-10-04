import 'dart:async';

import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/repository/semantic_results_source.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticResultSource;

import 'semantic_test_support.dart' show FakeConsentStore;

export 'semantic_test_support.dart' show FakeConsentStore;

/// רושם מזויף שמתעד כל קריאה.
class RecordingRecorder implements SearchFeedbackRecorder {
  bool collecting = true;
  final List<SemanticSearchContext> searches = [];
  final List<({int offset, List<SemanticResultSnapshot> results})> shown = [];
  final List<({SemanticResultSnapshot result, SearchFeedbackOpenVia via})>
  opens = [];
  final List<({String openId, Duration dwell, SearchFeedbackDwellEnd end})>
  dwells = [];
  final List<({SemanticResultSnapshot result, SearchFeedbackVote vote})> votes =
      [];

  int get total =>
      searches.length +
      shown.length +
      opens.length +
      dwells.length +
      votes.length;

  @override
  bool get isCollecting => collecting;

  @override
  void recordSearch(SemanticSearchContext context) => searches.add(context);

  @override
  void recordResultsShown(
    SemanticSearchContext context,
    int offset,
    List<SemanticResultSnapshot> results,
  ) => shown.add((offset: offset, results: results));

  @override
  String recordOpen(
    SemanticSearchContext context,
    SemanticResultSnapshot result,
    SearchFeedbackOpenVia via,
  ) {
    opens.add((result: result, via: via));
    return 'open-${opens.length}';
  }

  @override
  void recordDwell(
    SemanticSearchContext context,
    String openId,
    Duration dwell,
    SearchFeedbackDwellEnd end,
  ) => dwells.add((openId: openId, dwell: dwell, end: end));

  @override
  void recordVote(
    SemanticSearchContext context,
    SemanticResultSnapshot result,
    SearchFeedbackVote vote,
  ) => votes.add((result: result, vote: vote));
}

SemanticResultItem resultItem(
  int n, {
  SemanticResultSource source = SemanticResultSource.both,
  String? filePath,
  String? html,
}) => SemanticResultItem(
  title: 'ספר $n',
  reference: 'ספר $n, א',
  snippetHtml: html ?? 'טקסט <font color="red">מודגש</font> $n',
  isHighlighted: source != SemanticResultSource.semantic,
  id: BigInt.from(n),
  segment: n,
  isPdf: false,
  filePath: filePath ?? 'id:$n',
  source: source,
  fusedScore: 1 / n,
  lexicalScore: source == SemanticResultSource.semantic ? null : 0.5,
  semanticScore: source == SemanticResultSource.lexical ? null : 0.7,
);

/// מקור מזויף: כל עמוד הוא [pageSize] פריטים מתוך [total].
class FakeResultsSource implements SemanticResultsSource {
  FakeResultsSource({
    this.total = 75,
    this.debug = false,
    this.items,
    this.error,
  });

  final int total;
  final bool debug;
  final List<SemanticResultItem>? items;
  Object? error;
  Completer<void>? gate;
  bool returnsNull = false;
  int cancels = 0;
  final List<({int offset, int limit})> fetches = [];

  @override
  bool get isDebugPreview => debug;

  @override
  SemanticRankingConfig? get ranking => const SemanticRankingConfig();

  @override
  Future<SemanticResultsPage?> fetch(
    SemanticQueryOptions options, {
    required int offset,
    required int limit,
  }) async {
    fetches.add((offset: offset, limit: limit));
    final pending = gate;
    if (pending != null) await pending.future;
    final failure = error;
    if (failure != null) throw failure;
    if (returnsNull) return null;
    final all = items ?? [for (var i = 1; i <= total; i++) resultItem(i)];
    final page = all.skip(offset).take(limit).toList();
    return SemanticResultsPage(
      items: page,
      pageableTotal: all.length,
      executedMode: 'hybrid',
      semanticAvailable: true,
      latencyMs: 12,
      totalCount: all.length,
      lexicalTotalCount: all.length,
      countsAreExact: false,
      truncated: false,
      candidateWindowTruncated: false,
    );
  }

  @override
  void cancel() => cancels++;

  @override
  Future<SemanticEngineSnapshot> engineSnapshot() async =>
      const SemanticEngineSnapshot(state: 'ready');
}

/// בלוק עם fakes לכל התלויות.
SemanticResultsBloc buildResultsBloc({
  required FakeResultsSource? source,
  required RecordingRecorder recorder,
  FakeConsentStore? consent,
  Set<String> userBookPaths = const {},
  int pageSize = 30,
}) {
  var ids = 0;
  return SemanticResultsBloc(
    resolveSource: () async => source,
    feedback: SemanticFeedbackPorts(
      recorder: () => recorder,
      consent: () => consent ?? FakeConsentStore(),
      newId: () => 'id-${++ids}',
      whenQueued: () async {},
    ),
    isUserBook: (item) async => userBookPaths.contains(item.filePath),
    resolvePassage: (item) async => 'הפסקה המלאה של ${item.title}',
    pageSize: pageSize,
  );
}
