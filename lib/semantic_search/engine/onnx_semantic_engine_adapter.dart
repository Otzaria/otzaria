// המתאם היחיד ל-API של otzaria_search_engine ב-78ff9f5 (ענף onnx-backend).
// אין לייבא אותו לפני מעבר ה-pin; ההחלפה ב-createSemanticEngineBackend.

import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/search/search_engine_gateway.dart'
    show SemanticSearchRequest;
import 'package:otzaria/semantic_search/engine/semantic_engine_backend.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// מממש את [SemanticEngineBackend] מעל ה-API של המנוע: התקנה, פתיחה וחיפוש
/// של סט וקטורים מוכן, עם ביטול דרך [SemanticCancellationToken].
class OnnxSemanticEngineAdapter implements SemanticEngineBackend {
  OnnxSemanticEngineAdapter({
    Future<SearchEngine> Function()? engine,
    SemanticCancellationToken Function()? tokenFactory,
  }) : _engine = engine ?? (() => TantivyDataProvider.instance.engine),
       _newToken = tokenFactory ?? SemanticCancellationToken.new;

  final Future<SearchEngine> Function() _engine;
  final SemanticCancellationToken Function() _newToken;

  @override
  Future<SemanticBackendStatus> status() async =>
      mapStatus(await (await _engine()).semanticStatus());

  @override
  Future<SemanticVectorsSummary> vectorsInfo(String vectorsDir) => _guard(
    () async => mapVectorsInfo(
      await (await _engine()).semanticVectorsInfo(vectorsDir: vectorsDir),
    ),
  );

  @override
  Future<SemanticInstallSummary> installVectors(
    SemanticInstallRequest request, {
    required SemanticCancelHandle cancel,
  }) => _withToken(cancel, (token) async {
    final report = await (await _engine()).installSemanticVectors(
      input: SemanticVectorsInstallInput(
        vectorsDir: request.vectorsDir,
        segmentPath: request.segmentPath,
        manifestJson: request.manifestJson,
        publishedManifestSha256: request.publishedManifestSha256,
        modelIdentityJson: request.modelIdentityJson,
      ),
      cancellation: token,
    );
    return SemanticInstallSummary(
      kind: report.kind.name,
      libraryVersion: report.libraryVersion,
      segments: report.segments,
      bytesOnDisk: report.bytesOnDisk.toInt(),
      needsCompaction: report.needsCompaction,
      alreadyApplied: report.alreadyApplied,
    );
  });

  @override
  Future<void> verifyVectors(
    String vectorsDir, {
    required SemanticCancelHandle cancel,
  }) => _withToken(cancel, (token) async {
    await (await _engine()).verifySemanticVectors(
      vectorsDir: vectorsDir,
      cancellation: token,
    );
  });

  @override
  Future<SemanticCoverageSummary> coverage(
    String vectorsDir, {
    required SemanticCancelHandle cancel,
  }) => _withToken(cancel, (token) async {
    final coverage = await (await _engine()).semanticCoverage(
      vectorsDir: vectorsDir,
      cancellation: token,
    );
    return SemanticCoverageSummary(
      liveKeyedLines: coverage.liveKeyedLines.toInt(),
      coveredLines: coverage.coveredLines.toInt(),
      booksLive: coverage.booksLive,
      booksCovered: coverage.booksCovered,
      vectorsLibraryVersion: coverage.vectorsLibraryVersion,
      ratio: coverage.ratio,
    );
  });

  @override
  Future<SemanticBackendStatus> open(SemanticOpenRequest request) => _guard(
    () async => mapStatus(
      await (await _engine()).openSemanticArtifact(
        config: SemanticArtifactInput(
          vectorsDir: request.vectorsDir,
          modelPath: request.modelPath,
          modelIdentityJson: request.modelIdentityJson,
          onnxRuntimePath: request.onnxRuntimePath,
        ),
      ),
    ),
  );

  @override
  Future<void> compactVectors(
    String vectorsDir, {
    int? liveLibraryVersion,
    required SemanticCancelHandle cancel,
  }) => _withToken(cancel, (token) async {
    await (await _engine()).compactSemanticVectors(
      vectorsDir: vectorsDir,
      liveLibraryVersion: liveLibraryVersion,
      cancellation: token,
    );
  });

  @override
  Future<void> disable() async => (await _engine()).disableSemantic();

  @override
  Future<SemanticSearchOutcome> search(
    SemanticSearchRequest request, {
    required SemanticCancelHandle cancel,
    SemanticRankingConfig? ranking,
  }) => _withToken(cancel, (token) async {
    final response = await (await _engine()).searchSemantic(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      lexicalMode: request.lexicalMode,
      fuzzyMaxDistance: request.effectiveFuzzyMaxDistance,
      retrievalMode: request.retrievalMode,
      grouping: request.grouping,
      matchNikud: request.matchNikud,
      matchTaamim: request.matchTaamim,
      ranking: ranking == null ? null : mapRanking(ranking),
      cancellation: token,
    );
    final fallback = response.fallbackKind;
    return SemanticSearchOutcome(
      response: response,
      fallbackKind: fallback == null
          ? null
          : SemanticFailureKind.fromEngineName(fallback.name),
    );
  });

  /// ממפה את מצב המנוע; מצב שאינו מוכר לאפליקציה הוא [SemanticBackendState.other].
  static SemanticBackendStatus mapStatus(SemanticStatus status) {
    final errorKind = status.errorKind;
    return SemanticBackendStatus(
      state: switch (status.state) {
        SemanticState.notInBuild => SemanticBackendState.notInBuild,
        SemanticState.notConfigured => SemanticBackendState.notConfigured,
        SemanticState.ready => SemanticBackendState.ready,
        _ => SemanticBackendState.other,
      },
      rawState: status.state.name,
      errorKind: errorKind == null
          ? null
          : SemanticFailureKind.fromEngineName(errorKind.name),
      lastError: status.lastError,
      vectorsLibraryVersion: status.vectorsLibraryVersion,
      vectorSegments: status.vectorSegments,
      needsCompaction: status.needsCompaction,
    );
  }

  static SemanticVectorsSummary mapVectorsInfo(SemanticVectorsInfo info) {
    if (!info.present) return SemanticVectorsSummary.absent;
    return SemanticVectorsSummary(
      present: true,
      identityDigest: info.identityDigest,
      libraryVersion: info.libraryVersion,
      libraryReleaseTag: info.libraryReleaseTag,
      segments: [
        for (final segment in info.segments)
          SemanticSegmentSummary(
            id: segment.id,
            kind: segment.kind.name,
            fromLibraryVersion: segment.fromLibraryVersion,
            toLibraryVersion: segment.toLibraryVersion,
            sizeBytes: segment.size.toInt(),
          ),
      ],
      bytesOnDisk: info.bytesOnDisk.toInt(),
      needsCompaction: info.needsCompaction,
      recoveredFromPrevious: info.recoveredFromPrevious,
    );
  }

  static SemanticRankingOptions mapRanking(SemanticRankingConfig config) {
    return SemanticRankingOptions(
      fusionStrategy: switch (config.fusion) {
        SemanticFusion.weighted => SemanticFusionStrategy.weighted,
        SemanticFusion.rrf => SemanticFusionStrategy.rrf,
        SemanticFusion.adaptive => SemanticFusionStrategy.adaptive,
      },
      rrfK: config.rrfK,
      alphaOverride: config.alphaOverride,
      alphaByQueryType: SemanticQueryTypeAlphas(
        quotedPhrase: config.alphaQuotedPhrase,
        exactReference: config.alphaExactReference,
        short: config.alphaShort,
        mixed: config.alphaMixed,
        conceptual: config.alphaConceptual,
        unknown: config.alphaUnknown,
      ),
      bm25SaturationK: config.bm25SaturationK,
      semanticThreshold: config.semanticThreshold,
      agreementBonus: config.agreementBonus,
      phraseMatchBonus: config.phraseMatchBonus,
      rareTermBonus: config.rareTermBonus,
      sectionCoverageBonus: config.sectionCoverageBonus,
      duplicatePenalty: config.duplicatePenalty,
      metadataRankingEnabled: config.metadataRankingEnabled,
      candidateWindowMultiplier: config.candidateWindowMultiplier,
    );
  }

  /// כל [SemanticError] של המנוע הופך ל-[SemanticFailure] של האפליקציה.
  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on SemanticError catch (error) {
      throw SemanticFailure(
        SemanticFailureKind.fromEngineName(error.kind.name),
        error.message,
        error.field,
      );
    }
  }

  /// token חדש לכל קריאה, מקושר ל-[cancel]; המנוע שואל אותו בעצמו.
  Future<T> _withToken<T>(
    SemanticCancelHandle cancel,
    Future<T> Function(SemanticCancellationToken token) body,
  ) {
    final token = _newToken();
    final unlink = cancel.onCancel(token.cancel);
    return _guard(() => body(token)).whenComplete(() {
      unlink();
      token.dispose();
    });
  }
}
