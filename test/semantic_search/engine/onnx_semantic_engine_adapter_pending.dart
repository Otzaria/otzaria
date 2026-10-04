// לא פעיל עד מעבר ה-pin ל-78ff9f5: אז לשנות את השם ל-..._test.dart, ולהחליף
// ב-test/search/semantic_search_gateway_test.dart את config/_status ב-onnxConfig/onnxStatus.

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/semantic_search/engine/onnx_semantic_engine_adapter.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// הערכים שבמסירה במקום ה-GGUF של הבדיקה הישנה (`/model.gguf`, `llama.cpp`).
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
