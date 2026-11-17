import 'package:flutter/material.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

import '../golden_harness.dart';

Widget _tree() => SizedBox(
  width: 320,
  child: Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NavTreeTile(
          title: 'תנ"ך',
          level: 0,
          hasChildren: true,
          isExpanded: true,
          count: 24,
          onTap: () {},
          onToggleExpand: () {},
        ),
        NavTreeTile(
          title: 'תורה',
          level: 1,
          hasChildren: true,
          isExpanded: true,
          count: 5,
          onTap: () {},
          onToggleExpand: () {},
        ),
        NavTreeTile(
          title: 'בראשית',
          level: 2,
          isSelected: true,
          onTap: () {},
        ),
        NavTreeTile(
          title: 'שמות',
          subtitle: 'ספר שני',
          level: 2,
          onTap: () {},
        ),
        NavTreeTile(
          title: 'נביאים',
          level: 1,
          hasChildren: true,
          count: 8,
          onTap: () {},
          onToggleExpand: () {},
        ),
      ],
    ),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('NavTreeTile: עץ בשלוש רמות, ${brightness.name}', (
      tester,
    ) async {
      await pumpGolden(tester, _tree(), brightness: brightness);
      await expectGolden('nav_tree_tile_levels.${brightness.name}');
    });
  }
}
