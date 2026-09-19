// כלי מדידה ידני: מריץ את בניית הקטלוג בדיוק כפי שאוצריא מריצה אותה —
// כולל העלאת בר אילן כשהוא סגור — וכותב לקטלוג האמיתי.
//
// RESPONSA_TARGET=<db> flutter test test/external_catalog/live_build_catalog_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_catalog_build_service.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/external_catalog/responsa/responsa_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('build catalog', () async {
    final target =
        Platform.environment['RESPONSA_TARGET'] ?? ResponsaPaths.catalogPath;
    expect(target, isNotNull);
    print('target: $target');

    final watch = Stopwatch()..start();
    var lastReport = 0;
    await for (final progress in ResponsaCatalogBuildService().build(
      targetPath: target!,
    )) {
      if (progress.scannedNodes - lastReport >= 100000) {
        lastReport = progress.scannedNodes;
        print(
          '  ${progress.stage.name}: $lastReport '
          '(${watch.elapsed.inSeconds}s)',
        );
      }
      if (progress.error != null) {
        fail('build failed: ${progress.error}');
      }
      if (progress.stage.name == 'done') {
        print(
          'done: ${progress.books} books from ${progress.scannedNodes} '
          'nodes in ${watch.elapsed}',
        );
      }
    }

    final repository = ResponsaCatalogRepository()
      ..databasePathOverride = target;
    final info = await repository.info();
    print(
      'catalog: ${info.bookCount} books, schema ${info.schemaVersion}, '
      'version ${info.sourceVersion}, from ${info.installPath}',
    );
    expect(info.bookCount, greaterThan(8000));
    expect(info.isOutdated, isFalse);

    final books = await repository.loadBooks();
    print('loaded ${books.length}; sample:');
    for (final book in books.take(5)) {
      print('   ${book.title}  || ${book.heCategories}');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
