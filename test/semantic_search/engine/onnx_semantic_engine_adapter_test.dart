import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/semantic_search/engine/onnx_semantic_engine_adapter.dart';
import 'package:otzaria/semantic_search/engine/semantic_engine_backend.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

const onnxConfig = SemanticConfigInput(
  rootDir: '/semantic',
  modelPath: '/model.onnx',
  modelId: 'otzaria-v1',
  embeddingDim: 1024,
  pooling: 'in-graph',
  maxTokens: 256,
  modelQuantization: 'int8',
  embeddingTextVersion: 2,
);

const onnxStatus = SemanticStatus(
  state: SemanticState.ready,
  enabled: true,
  available: true,
  modelLoaded: true,
  indexedBookCount: 1,
  vectorCount: 1,
  modelId: 'otzaria-v1',
  embeddingDim: 1024,
  embeddingBackend: 'onnxruntime-sentence-v1',
  vectorBackend: 'memory',
  vectorsPersisted: false,
  vectorSegments: 0,
  needsCompaction: false,
);

class _Token implements SemanticCancellationToken {
  bool cancelled = false;
  bool disposed = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isCancelled => cancelled;

  @override
  void dispose() => disposed = true;

  @override
  bool get isDisposed => disposed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine implements SearchEngine {
  SemanticVectorsInstallInput? installInput;
  SemanticArtifactInput? openInput;
  SemanticRankingOptions? ranking;
  SemanticCancellationToken? searchToken;
  Object? failure;
  Completer<void>? searchPause;
  SemanticStatus status = onnxStatus;

  @override
  Future<SemanticStatus> semanticStatus() async => status;

  @override
  Future<SemanticVectorsInstallReport> installSemanticVectors({
    required SemanticVectorsInstallInput input,
    required SemanticCancellationToken cancellation,
  }) async {
    installInput = input;
    final error = failure;
    if (error != null) throw error;
    return SemanticVectorsInstallReport(
      kind: SemanticVectorsPackageKind.base,
      libraryVersion: 30,
      generation: BigInt.one,
      segments: 1,
      slotsAdded: BigInt.from(6347587),
      tombstonesApplied: BigInt.zero,
      duplicatesRemoved: BigInt.zero,
      foreignUnresolved: BigInt.zero,
      bytesOnDisk: BigInt.from(1779752972),
      needsCompaction: false,
      alreadyApplied: false,
    );
  }

  @override
  Future<SemanticStatus> openSemanticArtifact({
    required SemanticArtifactInput config,
  }) async {
    openInput = config;
    return status;
  }

  @override
  Future<SemanticSearchResponse> searchSemantic({
    required String query,
    required List<String> facets,
    required int limit,
    required int offset,
    required SemanticLexicalMode lexicalMode,
    required int fuzzyMaxDistance,
    required SemanticRetrievalMode retrievalMode,
    SemanticGroupingMode? grouping,
    required bool matchNikud,
    required bool matchTaamim,
    SemanticRankingOptions? ranking,
    required SemanticCancellationToken cancellation,
  }) async {
    this.ranking = ranking;
    searchToken = cancellation;
    await searchPause?.future;
    return SemanticSearchResponse(
      results: const [],
      totalCount: 0,
      lexicalTotalCount: 0,
      countsAreExact: false,
      requestedMode: retrievalMode,
      executedMode: SemanticExecutedMode.lexicalOnly,
      semanticAvailable: false,
      fallbackKind: SemanticErrorKind.notConfigured,
      latencyMs: BigInt.zero,
      candidateWindowTruncated: false,
      truncated: false,
    );
  }

  String? highlightQuery;
  List<SemanticHighlightTarget>? highlightTargets;
  SemanticCancellationToken? highlightToken;

  @override
  Future<List<SemanticPassageHighlight>> semanticPassageHighlights({
    required String query,
    required List<SemanticHighlightTarget> targets,
    required SemanticCancellationToken cancellation,
  }) async {
    highlightQuery = query;
    highlightTargets = targets;
    highlightToken = cancellation;
    final error = failure;
    if (error != null) throw error;
    return [
      for (final target in targets)
        SemanticPassageHighlight(
          filePath: target.filePath,
          id: target.id,
          snippetHtml: '',
          isHighlighted: false,
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeEngine engine;
  late List<_Token> tokens;
  late OnnxSemanticEngineAdapter adapter;

  setUp(() {
    engine = _FakeEngine();
    tokens = [];
    adapter = OnnxSemanticEngineAdapter(
      engine: () async => engine,
      tokenFactory: () {
        final token = _Token();
        tokens.add(token);
        return token;
      },
    );
  });

  test('factory בוחר ONNX בפלטפורמה נתמכת', () {
    expect(
      createSemanticEngineBackend(),
      isSemanticSearchPlatformSupported()
          ? isA<OnnxSemanticEngineAdapter>()
          : isA<UnavailableSemanticEngineBackend>(),
    );
  });

  test('installVectors מעביר את כל השדות ומחזיר את הדוח', () async {
    final summary = await adapter.installVectors(
      const SemanticInstallRequest(
        vectorsDir: '/root/vectors',
        segmentPath: '/root/vectors-download/v30-base.oxv.zst',
        manifestJson: '{}',
        publishedManifestSha256: 'ab',
        modelIdentityJson: '{"family_id":"x"}',
      ),
      cancel: SemanticCancelHandle(),
    );

    expect(engine.installInput?.vectorsDir, '/root/vectors');
    expect(engine.installInput?.publishedManifestSha256, 'ab');
    expect(summary.kind, 'base');
    expect(summary.libraryVersion, 30);
    expect(tokens.single.isDisposed, isTrue);
  });

  test('SemanticError ממופה לפי סוג', () async {
    engine.failure = const SemanticError(
      kind: SemanticErrorKind.insufficientDiskSpace,
      message: 'need 1.78GB',
    );

    await expectLater(
      adapter.installVectors(
        const SemanticInstallRequest(
          vectorsDir: '/v',
          segmentPath: '/s',
          manifestJson: '{}',
          publishedManifestSha256: null,
          modelIdentityJson: '{}',
        ),
        cancel: SemanticCancelHandle(),
      ),
      throwsA(
        isA<SemanticFailure>().having(
          (f) => f.kind,
          'kind',
          SemanticFailureKind.insufficientDiskSpace,
        ),
      ),
    );
  });

  test('vectorsBusy ממופה לסוג האפליקציה', () async {
    engine.failure = const SemanticError(
      kind: SemanticErrorKind.vectorsBusy,
      message: 'another install is running',
      field: 'vectors_dir',
    );

    await expectLater(
      adapter.installVectors(
        const SemanticInstallRequest(
          vectorsDir: '/v',
          segmentPath: '/s',
          manifestJson: '{}',
          publishedManifestSha256: 'ab',
          modelIdentityJson: '{}',
        ),
        cancel: SemanticCancelHandle(),
      ),
      throwsA(
        isA<SemanticFailure>()
            .having((f) => f.kind, 'kind', SemanticFailureKind.vectorsBusy)
            .having((f) => f.field, 'field', 'vectors_dir'),
      ),
    );
  });

  test('search: ביטול מגיע ל-token, והדירוג ו-fallbackKind ממופים', () async {
    final cancel = SemanticCancelHandle();
    final outcome = await adapter.search(
      const SemanticSearchRequest(query: 'חסד', facets: ['/']),
      cancel: cancel,
      ranking: const SemanticRankingConfig(
        fusion: SemanticFusion.rrf,
        rrfK: 30,
      ),
    );
    cancel.cancel();

    expect(engine.ranking?.fusionStrategy, SemanticFusionStrategy.rrf);
    expect(engine.ranking?.rrfK, 30);
    expect(outcome.fallbackKind, SemanticFailureKind.notConfigured);
    expect(identical(engine.searchToken, tokens.single), isTrue);

    final early = SemanticCancelHandle()..cancel();
    await adapter.search(
      const SemanticSearchRequest(query: 'אמת', facets: ['/']),
      cancel: early,
    );
    expect(tokens.last.isCancelled, isTrue);
  });

  test('mapRanking ממפה את כל השדות, כולל ספרי היסוד', () {
    const config = SemanticRankingConfig(
      foundationalBonus: 0.004,
      foundationalCandidateShare: 0.25,
    );
    final options = OnnxSemanticEngineAdapter.mapRanking(config);
    expect(options.foundationalBonus, 0.004);
    expect(options.foundationalCandidateShare, 0.25);

    final defaults = OnnxSemanticEngineAdapter.mapRanking(
      const SemanticRankingConfig(),
    );
    // ברירות המחדל של האפליקציה זהות לאלה של המנוע.
    expect(defaults, const SemanticRankingOptions());
  });

  test('passageHighlights מעביר שאילתה ויעדים, ומשחרר את ה-token', () async {
    final targets = [
      SemanticHighlightTarget(filePath: 'id:1', id: BigInt.one),
      SemanticHighlightTarget(filePath: 'id:2', id: BigInt.two),
    ];
    final marked = await adapter.passageHighlights(
      'כבוד אב',
      targets,
      cancel: SemanticCancelHandle(),
    );

    expect(engine.highlightQuery, 'כבוד אב');
    expect(engine.highlightTargets, targets);
    expect(identical(engine.highlightToken, tokens.single), isTrue);
    expect(tokens.single.isDisposed, isTrue);
    expect(marked.map((h) => h.id), [BigInt.one, BigInt.two]);

    engine.failure = const SemanticError(
      kind: SemanticErrorKind.cancelled,
      message: 'cancelled',
    );
    await expectLater(
      adapter.passageHighlights(
        'כבוד אב',
        targets,
        cancel: SemanticCancelHandle(),
      ),
      throwsA(
        isA<SemanticFailure>().having(
          (f) => f.kind,
          'kind',
          SemanticFailureKind.cancelled,
        ),
      ),
    );
  });

  test('ביטול בזמן חיפוש נשלח למנוע ומשחרר את ה-token בסיום', () async {
    engine.searchPause = Completer<void>();
    final cancel = SemanticCancelHandle();
    final pending = adapter.search(
      const SemanticSearchRequest(query: 'אמת', facets: ['/']),
      cancel: cancel,
    );
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    expect(engine.searchToken?.isCancelled, isTrue);
    expect(tokens.single.isDisposed, isFalse);
    engine.searchPause!.complete();
    await pending;
    expect(tokens.single.isDisposed, isTrue);
  });

  test('open מעביר את ONNX Runtime המצורף', () async {
    await adapter.open(
      const SemanticOpenRequest(
        vectorsDir: '/root/vectors',
        modelPath: '/root/otzaria/m/seforim-embed-round2-int8.onnx',
        modelIdentityJson: '{}',
        onnxRuntimePath: '/app/onnxruntime/onnxruntime.dll',
      ),
    );
    expect(
      engine.openInput?.onnxRuntimePath,
      '/app/onnxruntime/onnxruntime.dll',
    );
  });

  test('מצבי המנוע', () {
    expect(
      OnnxSemanticEngineAdapter.mapStatus(onnxStatus).rawState,
      'ready',
    );
    const notInBuild = SemanticStatus(
      state: SemanticState.notInBuild,
      enabled: false,
      available: false,
      modelLoaded: false,
      indexedBookCount: 0,
      vectorCount: 0,
      modelId: '',
      embeddingDim: 0,
      vectorBackend: '',
      vectorsPersisted: false,
      errorKind: SemanticErrorKind.featureNotInBuild,
      vectorSegments: 0,
      needsCompaction: false,
    );
    final mapped = OnnxSemanticEngineAdapter.mapStatus(notInBuild);
    expect(mapped.state, SemanticBackendState.notInBuild);
    expect(mapped.errorKind, SemanticFailureKind.featureNotInBuild);
  });
}
