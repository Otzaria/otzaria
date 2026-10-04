import 'package:otzaria/search/search_engine_gateway.dart'
    show SemanticSearchRequest;
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';

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
}

/// מימוש למנוע שאינו תומך בזרימת הוקטורים המותקנים: הכול מדווח כלא זמין.
class UnavailableSemanticEngineBackend implements SemanticEngineBackend {
  const UnavailableSemanticEngineBackend();

  static const SemanticFailure _unavailable = SemanticFailure(
    SemanticFailureKind.featureNotInBuild,
    'The pinned search engine has no installed-vectors API',
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
}

/// נקודת ההחלפה היחידה בין המנוע הנוכחי למתאם ה-ONNX.
///
/// TODO(engine-pin): כשה-pin של otzaria_search_engine עובר ל-78ff9f5, להחזיר
/// כאן `OnnxSemanticEngineAdapter()` מ-`onnx_semantic_engine_adapter.dart`.
SemanticEngineBackend createSemanticEngineBackend() =>
    const UnavailableSemanticEngineBackend();
