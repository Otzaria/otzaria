import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/recording_search_engine.dart';

void main() {
  group('SemanticSearchRequest', () {
    test('מרחק החיפוש המקורב נחתך לטווח שהמנוע תומך בו', () {
      expect(
        const SemanticSearchRequest(
          query: 'א',
          facets: ['/'],
          fuzzyMaxDistance: -1,
        ).effectiveFuzzyMaxDistance,
        0,
      );
      expect(
        const SemanticSearchRequest(
          query: 'א',
          facets: ['/'],
          fuzzyMaxDistance: 7,
        ).effectiveFuzzyMaxDistance,
        2,
      );
    });
  });

  group('SearchRepository semantic bridge', () {
    test('מעביר חיפוש סמנטי בלי לערבב את ציר החיפוש הלקסיקלי', () async {
      final engine = _RecordingSemanticEngine();
      final repository = SearchRepository(engineProvider: () async => engine);
      const request = SemanticSearchRequest(
        query: 'בריאת העולם',
        facets: ['/תנ״ך'],
        limit: 25,
        offset: 5,
        lexicalMode: SemanticLexicalMode.fuzzy,
        fuzzyMaxDistance: 2,
        retrievalMode: SemanticRetrievalMode.semanticOnly,
        grouping: SemanticGroupingMode.sameSection,
        matchNikud: true,
        matchTaamim: true,
      );

      final response = await repository.searchSemantic(request);

      expect(engine.lastSearchRequest, same(request));
      expect(response.executedMode, SemanticExecutedMode.semanticOnly);
      expect(response.semanticAvailable, isTrue);
    });

    test('מעביר את כל פעולות מחזור החיים הסמנטי', () async {
      final engine = _RecordingSemanticEngine();
      final repository = SearchRepository(engineProvider: () async => engine);
      const config = SemanticConfigInput(
        rootDir: '/semantic',
        modelPath: '/model.gguf',
        modelId: 'otzaria-v1',
        embeddingDim: 1024,
      );
      final book = SemanticBookInput(
        sourceBookKey: 'id:1',
        title: 'בראשית',
        contentFingerprint: BigInt.one,
        isPdf: false,
        topics: '/תנ״ך',
        extraFacets: const [],
        lines: const [],
      );

      await repository.configureSemantic(config);
      await repository.semanticStatus();
      await repository.semanticIndexDiff();
      await repository.semanticIndexBooks([book]);
      await repository.removeSemanticBooks(const ['id:1']);
      await repository.resetSemanticIndex();
      await repository.disableSemantic();

      expect(engine.lastConfig, same(config));
      expect(engine.lastBooks, [book]);
      expect(engine.lastRemovedBookKeys, ['id:1']);
      expect(engine.calls, [
        'configure',
        'status',
        'diff',
        'index',
        'remove',
        'reset',
        'disable',
      ]);
    });

    test('נכשל במפורש כשמוזרק מנוע לקסיקלי בלבד', () async {
      final repository = SearchRepository(
        engineProvider: () async => RecordingSearchEngine(),
      );

      await expectLater(repository.semanticStatus(), throwsStateError);
    });
  });
}

class _RecordingSemanticEngine extends RecordingSearchEngine
    implements SemanticSearchEngineOperations {
  final List<String> calls = [];
  SemanticSearchRequest? lastSearchRequest;
  SemanticConfigInput? lastConfig;
  List<SemanticBookInput>? lastBooks;
  List<String>? lastRemovedBookKeys;

  @override
  Future<SemanticSearchResponse> searchSemantic(
    SemanticSearchRequest request,
  ) async {
    lastSearchRequest = request;
    return SemanticSearchResponse(
      results: const [],
      totalCount: 0,
      lexicalTotalCount: 0,
      countsAreExact: false,
      requestedMode: request.retrievalMode,
      executedMode: SemanticExecutedMode.semanticOnly,
      semanticAvailable: true,
      latencyMs: BigInt.zero,
      candidateWindowTruncated: false,
      truncated: false,
    );
  }

  @override
  Future<SemanticStatus> configureSemantic(SemanticConfigInput config) async {
    calls.add('configure');
    lastConfig = config;
    return _status;
  }

  @override
  Future<void> disableSemantic() async {
    calls.add('disable');
  }

  @override
  Future<SemanticIndexDiff> semanticIndexDiff() async {
    calls.add('diff');
    return const SemanticIndexDiff(
      enabled: true,
      newBooks: [],
      changedBooks: [],
      unverifiableBooks: [],
      removedBooks: [],
      modelMismatch: false,
      chunkingMismatch: false,
      normalizationMismatch: false,
    );
  }

  @override
  Future<SemanticIndexingSummary> semanticIndexBooks(
    List<SemanticBookInput> books,
  ) async {
    calls.add('index');
    lastBooks = books;
    return const SemanticIndexingSummary(
      enabled: true,
      booksIndexed: 1,
      booksSkipped: 0,
      booksEmpty: 0,
      chunksWritten: 1,
    );
  }

  @override
  Future<SemanticRemoveResult> removeSemanticBooks(
    List<String> sourceBookKeys,
  ) async {
    calls.add('remove');
    lastRemovedBookKeys = sourceBookKeys;
    return const SemanticRemoveResult(enabled: true, vectorsRemoved: 1);
  }

  @override
  Future<SemanticResetResult> resetSemanticIndex() async {
    calls.add('reset');
    return const SemanticResetResult(enabled: true, vectorsRemoved: 1);
  }

  @override
  Future<SemanticStatus> semanticStatus() async {
    calls.add('status');
    return _status;
  }
}

const _status = SemanticStatus(
  enabled: true,
  available: true,
  modelLoaded: true,
  indexedBookCount: 1,
  vectorCount: 1,
  modelId: 'otzaria-v1',
  embeddingDim: 1024,
  embeddingBackend: 'llama.cpp',
  vectorBackend: 'memory',
  vectorsPersisted: false,
);
