import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';

import 'semantic_ui_test_support.dart';

const _options = SemanticQueryOptions(query: 'ספרים');

SemanticFeedbackPorts _feedback() {
  final recorder = RecordingRecorder();
  return SemanticFeedbackPorts(
    recorder: () => recorder,
    consent: () => FakeConsentStore(),
    newId: () => 'test-session',
    whenQueued: () async {},
  );
}

void main() {
  test('classifies at most eight results at a time in result order', () async {
    final gates = [for (var i = 0; i < 40; i++) Completer<bool>()];
    final firstBatchStarted = Completer<void>();
    var started = 0;
    var active = 0;
    var peak = 0;
    final bloc = SemanticResultsBloc(
      resolveSource: () async => FakeResultsSource(total: 40),
      feedback: _feedback(),
      pageSize: 40,
      isUserBook: (item) async {
        started++;
        active++;
        if (active > peak) peak = active;
        if (started == 8) firstBatchStarted.complete();
        try {
          return await gates[item.segment - 1].future;
        } finally {
          active--;
        }
      },
    );
    addTearDown(bloc.close);

    bloc.add(const SemanticSearchSubmitted(_options));
    await firstBatchStarted.future.timeout(const Duration(seconds: 2));
    expect(started, 8);
    expect(peak, 8);

    final loaded = bloc.stream.firstWhere(
      (state) => state.status == SemanticResultsStatus.loaded,
    );
    for (var i = gates.length - 1; i >= 0; i--) {
      gates[i].complete(i.isEven);
    }
    await loaded.timeout(const Duration(seconds: 2));

    expect(started, 40);
    expect(peak, lessThanOrEqualTo(8));
    for (var i = 0; i < gates.length; i++) {
      expect(bloc.isUserBookAt(i), i.isEven);
    }
  });

  test('cancellation prevents scheduling more stale lookups', () async {
    final firstBatchStarted = Completer<void>();
    final release = Completer<void>();
    var started = 0;
    final bloc = SemanticResultsBloc(
      resolveSource: () async => FakeResultsSource(total: 40),
      feedback: _feedback(),
      pageSize: 40,
      isUserBook: (_) async {
        started++;
        if (started == 8) firstBatchStarted.complete();
        await release.future;
        return false;
      },
    );
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await bloc.close();
    });

    bloc.add(const SemanticSearchSubmitted(_options));
    await firstBatchStarted.future.timeout(const Duration(seconds: 2));
    expect(started, 8);

    final cancelled = bloc.stream.firstWhere(
      (state) => state.status == SemanticResultsStatus.cancelled,
    );
    bloc.add(const SemanticSearchCancelRequested());
    await cancelled.timeout(const Duration(seconds: 2));
    release.complete();
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(started, 8);
    expect(bloc.state.status, SemanticResultsStatus.cancelled);
  });

  test('failed source classification remains private', () async {
    final bloc = SemanticResultsBloc(
      resolveSource: () async => FakeResultsSource(total: 3),
      feedback: _feedback(),
      pageSize: 3,
      isUserBook: (item) async {
        if (item.segment == 2) throw StateError('classification failed');
        return false;
      },
    );
    addTearDown(bloc.close);
    final loaded = bloc.stream.firstWhere(
      (state) => state.status == SemanticResultsStatus.loaded,
    );
    bloc.add(const SemanticSearchSubmitted(_options));
    await loaded.timeout(const Duration(seconds: 2));

    expect(bloc.isUserBookAt(0), isFalse);
    expect(bloc.isUserBookAt(1), isTrue);
    expect(bloc.isUserBookAt(2), isFalse);
  });
}
