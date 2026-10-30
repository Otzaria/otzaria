import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/services/semantic_fallback_log.dart';

void main() {
  test('כל סוג נרשם פעם אחת בכל פרק זמן; סוג אחר נרשם בנפרד', () {
    var now = DateTime(2026, 10, 30, 12);
    final written = <SemanticFailureKind>[];
    final log = SemanticFallbackLog(
      clock: () => now,
      write: (failure, _) => written.add(failure.kind),
    );
    void record(SemanticFailureKind kind) => log.record(
      kind,
      'reason',
      requestedMode: 'hybrid',
      executedMode: 'lexicalOnly',
    );

    record(SemanticFailureKind.queryFailed);
    record(SemanticFailureKind.queryFailed);
    record(SemanticFailureKind.notConfigured);
    now = now.add(const Duration(minutes: 9));
    record(SemanticFailureKind.queryFailed);
    now = now.add(const Duration(minutes: 1));
    record(SemanticFailureKind.queryFailed);

    expect(written, [
      SemanticFailureKind.queryFailed,
      SemanticFailureKind.notConfigured,
      SemanticFailureKind.queryFailed,
    ]);
  });
}
