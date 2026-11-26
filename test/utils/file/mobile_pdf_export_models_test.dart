import 'package:otzaria/utils/file/mobile_pdf_export_models.dart';
import 'package:test/test.dart';

void main() {
  const id = '0123456789abcdef0123456789abcdef';
  Map<String, Object?> saved() => const MobilePdfExportResult(
    operationId: id,
    status: MobilePdfExportStatus.saved,
  ).toMap();

  test('native saved keeps an unknown provider name null', () {
    final result = MobilePdfExportResult.fromMap(saved(), operationId: id);
    expect(result.status, MobilePdfExportStatus.saved);
    expect(result.displayName, isNull);
    expect(result.documentUri, isNull);
  });

  test('actual provider name and cancellation residual survive round-trip', () {
    const original = MobilePdfExportResult(
      operationId: id,
      status: MobilePdfExportStatus.cancelled,
      residualDocument: 'content://provider/partial/8',
      residualDisplayName: 'שם אחר.pdf',
      cleanupStatus: MobilePdfExportCleanupStatus.unsupported,
      cleanupError: 'provider does not support delete',
    );
    final result = MobilePdfExportResult.fromMap(
      original.toMap(),
      operationId: id,
    );
    expect(result.toMap(), original.toMap());
  });

  test('malformed native packets cannot become successful exports', () {
    for (final packet in <Object?>[
      null,
      true,
      {...saved(), 'version': 1.0},
      {...saved(), 'version': 2},
      {...saved(), 'operationId': 'other'},
      {...saved(), 'status': 'success'},
      {...saved(), 'cleanupStatus': null},
      {...saved(), 'displayName': false},
      {...saved(), 'documentUri': 42},
      {...saved(), 'residualDocument': 'content://partial'},
      {...saved(), 'residualDisplayName': 'orphan.pdf'},
    ]) {
      expect(
        () => MobilePdfExportResult.fromMap(packet, operationId: id),
        throwsFormatException,
        reason: '$packet',
      );
    }
  });

  test('a deleted destination cannot also be reported as remaining', () {
    final packet = {
      ...saved(),
      'status': 'cancelled',
      'cleanupStatus': 'deleted',
      'residualDocument': 'content://provider/remaining',
    };
    expect(
      () => MobilePdfExportResult.fromMap(packet, operationId: id),
      throwsFormatException,
    );
  });

  test('empty optional diagnostics cannot discard a remaining document', () {
    final result = MobilePdfExportResult.fromMap({
      ...saved(),
      'status': 'cancelled',
      'cleanupStatus': 'failed',
      'documentUri': '',
      'displayName': '',
      'errorCode': '',
      'errorMessage': '',
      'residualDocument': 'content://provider/partial',
      'residualDisplayName': '',
      'cleanupError': '',
    }, operationId: id);
    expect(result.status, MobilePdfExportStatus.cancelled);
    expect(result.residualDocument, 'content://provider/partial');
    expect(result.cleanupStatus, MobilePdfExportCleanupStatus.failed);
    expect(result.errorMessage, isNull);
    expect(result.residualDisplayName, isNull);
    expect(result.displayName, isNull);
    expect(result.documentUri, isNull);
    expect(result.cleanupError, isNull);
    expect(
      () => MobilePdfExportResult.fromMap({
        ...saved(),
        'operationId': '',
      }, operationId: id),
      throwsFormatException,
    );
  });

  test(
    'secondary staging diagnostics preserve provider cleanup information',
    () {
      const original = MobilePdfExportResult(
        operationId: id,
        status: MobilePdfExportStatus.failed,
        errorCode: 'copy_failed',
        errorMessage: 'provider write failed',
        residualDocument: 'content://provider/partial',
        cleanupStatus: MobilePdfExportCleanupStatus.failed,
        cleanupError: 'provider delete failed',
      );
      final result = original.withStagingCleanupError('local cleanup failed');
      expect(result.status, original.status);
      expect(result.errorCode, original.errorCode);
      expect(result.residualDocument, original.residualDocument);
      expect(result.cleanupStatus, original.cleanupStatus);
      expect(
        result.cleanupError,
        'provider delete failed\nstaging: local cleanup failed',
      );
    },
  );

  test(
    'a native staging refusal survives alongside provider cleanup details',
    () {
      const result = MobilePdfExportResult(
        operationId: id,
        status: MobilePdfExportStatus.cancelled,
        residualDocument: 'content://provider/partial',
        cleanupStatus: MobilePdfExportCleanupStatus.failed,
        cleanupError:
            'provider delete failed; staging_cleanup_failed: source_replaced',
      );
      expect(result.hasNativeStagingCleanupFailure, isTrue);
      expect(
        MobilePdfExportResult.fromMap(
          result.toMap(),
          operationId: id,
        ).hasNativeStagingCleanupFailure,
        isTrue,
      );
      expect(result.residualDocument, 'content://provider/partial');
    },
  );
}
