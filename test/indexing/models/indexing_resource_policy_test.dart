import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/models/indexing_resource_policy.dart';

void main() {
  test(
    'automatic policy considers CPU, RAM, available memory and platform',
    () {
      const strong = IndexingResourcePolicy(
        cpuCount: 16,
        mobile: false,
        totalRamMb: 32768,
        availableRamMb: 8192,
      );
      expect(strong.useEconomy(IndexingResourceMode.automatic), isFalse);
      for (final constrained in [
        const IndexingResourcePolicy(
          cpuCount: 2,
          mobile: false,
          totalRamMb: 32768,
        ),
        const IndexingResourcePolicy(
          cpuCount: 8,
          mobile: false,
          totalRamMb: 4096,
        ),
        const IndexingResourcePolicy(
          cpuCount: 8,
          mobile: false,
          totalRamMb: 32768,
          availableRamMb: 512,
        ),
        const IndexingResourcePolicy(
          cpuCount: 16,
          mobile: true,
          totalRamMb: 16384,
        ),
        const IndexingResourcePolicy(cpuCount: 16, mobile: false),
      ]) {
        expect(constrained.useEconomy(IndexingResourceMode.automatic), isTrue);
        expect(constrained.useEconomy(IndexingResourceMode.normal), isFalse);
      }
      expect(strong.useEconomy(IndexingResourceMode.economy), isTrue);
    },
  );

  test('a missing or future preference restores automatic mode', () {
    expect(
      IndexingResourceMode.fromStorage(null),
      IndexingResourceMode.automatic,
    );
    expect(
      IndexingResourceMode.fromStorage('invalid'),
      IndexingResourceMode.automatic,
    );
    for (final mode in IndexingResourceMode.values) {
      expect(IndexingResourceMode.fromStorage(mode.name), mode);
    }
  });
}
