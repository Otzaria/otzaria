import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/test_shards.dart';

void main() {
  List<List<String>> split(
    List<String> files,
    Map<String, double> timings,
    int total,
  ) => [for (var i = 0; i < total; i++) shardFiles(files, timings, i, total)];

  test('every file lands in exactly one shard', () {
    final files = [for (var i = 0; i < 23; i++) 'test/f${i}_test.dart'];
    final shards = split(files, {}, 5);
    expect(shards.expand((s) => s).toList()..sort(), files..sort());
  });

  test('balances by recorded time, not by file count', () {
    final files = ['test/a', 'test/b', 'test/c', 'test/d'];
    final shards = split(files, {
      'test/a': 30,
      'test/b': 10,
      'test/c': 10,
      'test/d': 10,
    }, 2);
    expect(shards, [
      ['test/a'],
      ['test/b', 'test/c', 'test/d'],
    ]);
  });

  test('a file without a recorded time weighs the median', () {
    final files = ['test/a', 'test/b', 'test/c', 'test/new'];
    final shards = split(files, {'test/a': 1, 'test/b': 5, 'test/c': 9}, 2);
    expect(shards, [
      ['test/a', 'test/c'],
      ['test/b', 'test/new'],
    ]);
  });

  test('goldens are not sharded: they run in goldens_windows', () {
    expect(isShardedTestFile('test/widgets/foo_test.dart'), isTrue);
    expect(
      isShardedTestFile('test/goldens/app_dialog/app_dialog_golden_test.dart'),
      isFalse,
    );
    expect(
      isShardedTestFile('test/goldens/golden_comparator_test.dart'),
      isFalse,
    );
    expect(isShardedTestFile('test/widgets/helpers.dart'), isFalse);
  });
}
