import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WebView prewarm starts once per process and waits for reveal', () {
    final source = File('lib/main.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final singletons = source.substring(
      source.indexOf('Future<void> _initializeProcessSingletons()'),
      source.indexOf('Future<void> _runDeferredWebViewPrewarm()'),
    );
    const invocation = 'unawaited(_runDeferredWebViewPrewarm());';
    expect(singletons, contains(invocation));
    expect(invocation.allMatches(source), hasLength(1));

    final start = source.indexOf('Future<void> _runDeferredWebViewPrewarm()');
    final deferred = source.substring(start, source.indexOf('\n}\n', start));
    expect(deferred, contains('!WebViewEnvironmentHolder.supportsPrewarm'));
    expect(deferred, isNot(contains('!Platform.isWindows')));
    final reveal = deferred.indexOf(
      '_mainWindowRevealedCompleter.future.timeout',
    );
    final prewarm = deferred.indexOf('WebViewEnvironmentHolder.prewarm(');
    expect(reveal, greaterThanOrEqualTo(0));
    expect(prewarm, greaterThan(reveal));
    expect(deferred, contains('hasEnabledPlugin'));
    expect(deferred, contains('_logNonFatalInitializationError'));
  });
}
