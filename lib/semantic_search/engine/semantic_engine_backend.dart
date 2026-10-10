import 'package:otzaria/semantic_search/engine/onnx_semantic_engine_adapter.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/search/search_engine_gateway.dart'
    show SemanticSearchRequest;
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticHighlightTarget, SemanticPassageHighlight;

/// החוזה של שכבת החיפוש הסמנטי מול המנוע.
///
/// כל מתודה זורקת [SemanticFailure] בכשל. [SemanticCancelHandle] שבוטל
/// מסיים את הפעולה ב-[SemanticFailureKind.cancelled], שאינו כשל.
abstract interface class SemanticEngineBackend {
  /// מצב ה-session; לעולם אינו זורק על "אין session".
  Future<SemanticBackendStatus> status();

  /// מה מותקן ב-[vectorsDir]; [SemanticVectorsSummary.absent] כשאין כלום.
  Future<SemanticVectorsSummary> vectorsInfo(String vectorsDir);

  /// מתקין release וקטורים, באטומיות: כשל או ביטול משאירים את הסט הקודם.
  Future<SemanticInstallSummary> installVectors(
    SemanticInstallRequest request, {
    required SemanticCancelHandle cancel,
  });

  /// בדיקת שלמות מלאה של הסט (קורא את כולו).
  Future<void> verifyVectors(
    String vectorsDir, {
    required SemanticCancelHandle cancel,
  });

  /// כמה משורות האינדקס הפתוח מכוסות בסט.
  Future<SemanticCoverageSummary> coverage(
    String vectorsDir, {
    required SemanticCancelHandle cancel,
  });

  /// פותח את הסט והמודל לקריאה ומחזיר את המצב שאחרי הפתיחה.
  Future<SemanticBackendStatus> open(SemanticOpenRequest request);

  /// מאחד את הסט ל-segment אחד כשהמדיניות מבקשת; נחוץ רק עם deltas.
  Future<void> compactVectors(
    String vectorsDir, {
    int? liveLibraryVersion,
    required SemanticCancelHandle cancel,
  });

  /// סוגר את ה-session הפתוח.
  Future<void> disable();

  /// חיפוש היברידי או סמנטי. [ranking] `null` = הדירוג של המנוע.
  Future<SemanticSearchOutcome> search(
    SemanticSearchRequest request, {
    required SemanticCancelHandle cancel,
    SemanticRankingConfig? ranking,
  });

  /// מסמן בשורה של כל יעד את הקטע הקרוב ל-[query]; תשובה אחת לכל יעד,
  /// בסדרם. יעד שלא סומן חוזר עם `isHighlighted == false`.
  Future<List<SemanticPassageHighlight>> passageHighlights(
    String query,
    List<SemanticHighlightTarget> targets, {
    required SemanticCancelHandle cancel,
  });
}

/// מימוש למנוע שאינו תומך בזרימת הוקטורים המותקנים: הכול מדווח כלא זמין.
class UnavailableSemanticEngineBackend implements SemanticEngineBackend {
  const UnavailableSemanticEngineBackend();

  static const SemanticFailure _unavailable = SemanticFailure(
    SemanticFailureKind.featureNotInBuild,
    'Semantic search is not supported on this platform',
  );

  @override
  Future<SemanticBackendStatus> status() async =>
      SemanticBackendStatus.notInBuild;

  @override
  Future<SemanticVectorsSummary> vectorsInfo(String vectorsDir) async =>
      SemanticVectorsSummary.absent;

  @override
  Future<SemanticInstallSummary> installVectors(
    SemanticInstallRequest request, {
    required SemanticCancelHandle cancel,
  }) => Future.error(_unavailable);

  @override
  Future<void> verifyVectors(
    String vectorsDir, {
    required SemanticCancelHandle cancel,
  }) => Future.error(_unavailable);

  @override
  Future<SemanticCoverageSummary> coverage(
    String vectorsDir, {
    required SemanticCancelHandle cancel,
  }) => Future.error(_unavailable);

  @override
  Future<SemanticBackendStatus> open(SemanticOpenRequest request) =>
      Future.error(_unavailable);

  @override
  Future<void> compactVectors(
    String vectorsDir, {
    int? liveLibraryVersion,
    required SemanticCancelHandle cancel,
  }) => Future.error(_unavailable);

  @override
  Future<void> disable() async {}

  @override
  Future<SemanticSearchOutcome> search(
    SemanticSearchRequest request, {
    required SemanticCancelHandle cancel,
    SemanticRankingConfig? ranking,
  }) => Future.error(_unavailable);

  @override
  Future<List<SemanticPassageHighlight>> passageHighlights(
    String query,
    List<SemanticHighlightTarget> targets, {
    required SemanticCancelHandle cancel,
  }) => Future.error(_unavailable);
}

/// בוחר את מתאם ONNX רק בפלטפורמות הנתמכות.
SemanticEngineBackend createSemanticEngineBackend() =>
    isSemanticSearchPlatformSupported()
    ? OnnxSemanticEngineAdapter()
    : const UnavailableSemanticEngineBackend();
