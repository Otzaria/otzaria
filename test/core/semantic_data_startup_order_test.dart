import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/main.dart').readAsStringSync();

  test('עדכון הנתונים הסמנטיים מתוזמן פעם בתהליך ואינו חוסם את העלייה', () {
    final singletons = source.substring(
      source.indexOf('Future<void> _initializeProcessSingletons()'),
      source.indexOf('Future<void> _runDeferredSemanticDataUpdate()'),
    );
    const invocation = 'unawaited(_runDeferredSemanticDataUpdate());';
    expect(singletons, contains(invocation));
    expect(source.split(invocation), hasLength(2));
    expect(
      singletons.indexOf(invocation),
      greaterThan(singletons.indexOf('initHive')),
    );
  });

  test('המאגר נוצר אחרי החשיפה ורק עבור הורדה שהמשתמש כבר הפעיל', () {
    final deferred = source.substring(
      source.indexOf('Future<void> _runDeferredSemanticDataUpdate()'),
      source.indexOf('Future<void> _runDeferredOsVersion()'),
    );
    final repository = deferred.indexOf('SemanticSearchRepository.instance');
    expect(repository, isNonNegative);
    for (final gate in [
      '_mainWindowRevealedCompleter.future.timeout',
      'SettingsRepository.keySemanticDataEnabled',
      'SettingsRepository.keySemanticDownloadPaused',
    ]) {
      expect(deferred.indexOf(gate), inInclusiveRange(0, repository));
    }
    expect(deferred, contains('repository.scheduleVectorsUpdate();'));
    expect(deferred, contains('_logNonFatalInitializationError('));
  });
}
