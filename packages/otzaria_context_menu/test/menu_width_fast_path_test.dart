import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';

class _CountingEntries extends ListBase<AppMenuEntry<int>> {
  int reads = 0;

  @override
  int get length => 60000;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  AppMenuEntry<int> operator [](int index) {
    reads++;
    return AppMenuEntry(value: index, label: 'Item $index');
  }

  @override
  void operator []=(int index, AppMenuEntry<int> value) =>
      throw UnsupportedError('read only');
}

void main() {
  final metrics = AppMenuMetrics.create(compactMenus: false);

  test('width bounded by menu floor skips all 60000 entry inspections', () {
    final entries = _CountingEntries();
    for (final cap in [
      0.0,
      metrics.menuMinWidth - 1,
      metrics.menuMinWidth,
    ]) {
      final width = calculateAppMenuPreferredWidth(metrics, entries,
          maxWidth: cap);
      expect(width, cap);
    }
    expect(entries.reads, 0);
  });

  test('async bounded width also avoids all menu entry inspections', () async {
    final entries = _CountingEntries();
    final width = await calculateAppMenuPreferredWidthAsync(
      metrics,
      entries,
      maxWidth: metrics.menuMinWidth,
    );
    expect(width, metrics.menuMinWidth);
    expect(entries.reads, 0);
  });

  testWidgets('leading icons and trailing items retain full width accuracy', (
    tester,
  ) async {
    final items = [
      const AppMenuEntry<int>(value: 1, label: 'short'),
      const AppMenuEntry<int>(
        value: 2,
        label: 'A rather long action label',
        icon: Icons.search,
      ),
      const AppMenuEntry<int>(
        value: 3,
        label: 'another',
        trailing: Icon(Icons.check),
      ),
    ];
    final total = calculateAppMenuPreferredWidth(metrics, items);
    final capped = calculateAppMenuPreferredWidth(
      metrics,
      items,
      maxWidth: total - 8,
    );
    expect(capped, total - 8);
    expect(
      await calculateAppMenuPreferredWidthAsync(metrics, items),
      total,
    );
  });
}
