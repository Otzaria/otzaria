import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('אתחול Sentry ממתין לחשיפת החלון ללא timeout', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _initializeSentry() async {');
    final end = source.indexOf('Future<void> _runAppBootstrap()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final initializer = source.substring(start, end);
    const revealWait = 'await _mainWindowRevealedCompleter.future;';
    expect(initializer, contains(revealWait));
    expect(
      initializer,
      isNot(contains('_mainWindowRevealedCompleter.future.timeout')),
    );
    expect(
      initializer.indexOf(revealWait),
      lessThan(initializer.indexOf('SentryFlutter.init(')),
    );
  });

  test('מסד sentry-native בתיקיית הלוגים, לא בתיקיית העבודה', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _initializeSentry() async {');
    final end = source.indexOf('Future<void> _runAppBootstrap()', start);
    expect(
      source.substring(start, end),
      contains(
        'options.nativeDatabasePath = UncleanExitDetector.sentryDatabasePath();',
      ),
    );
  });

  test('במצב מנותק Sentry אינו מאותחל', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _initializeSentry() async {');
    final end = source.indexOf('Future<void> _runAppBootstrap()', start);
    final initializer = source.substring(start, end);

    const offlineCheck = 'SettingsRepository.keyOfflineMode';
    expect(initializer, contains(offlineCheck));
    expect(
      initializer.indexOf(offlineCheck),
      lessThan(initializer.indexOf('SentryFlutter.init(')),
    );
  });
}
