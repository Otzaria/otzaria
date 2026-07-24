import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

void main() {
  // --- AppCard (single child) ---

  testWidgets('AppCard renders child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppCard(child: const Text('hello'))),
      ),
    );
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('AppCard without onTap uses Material and no InkWell', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(key: key, child: const SizedBox()),
        ),
      ),
    );
    final cardFinder = find.byKey(key);
    expect(
      find.descendant(of: cardFinder, matching: find.byType(Material)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('AppCard with onTap uses Material + InkWell', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(key: key, onTap: () {}, child: const SizedBox()),
        ),
      ),
    );
    final cardFinder = find.byKey(key);
    expect(
      find.descendant(of: cardFinder, matching: find.byType(InkWell)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.byType(Material)),
      findsOneWidget,
    );
  });

  testWidgets('AppCard onTap is called on tap', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(
            onTap: () => tapped = true,
            child: const Text('tap me'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tap me'));
    expect(tapped, isTrue);
  });

  testWidgets('AppCard with selected adds ColoredBox overlay', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(key: key, selected: true, child: const SizedBox()),
        ),
      ),
    );
    final cardFinder = find.byKey(key);
    expect(
      find.descendant(of: cardFinder, matching: find.byType(ColoredBox)),
      findsWidgets,
    );
  });

  // --- AppCard.section ---

  testWidgets('AppCard.section renders all children', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard.section(
            children: const [
              Text('one'),
              Text('two'),
              Text('three'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
  });

  testWidgets('AppCard.section inserts N-1 SizedBox gaps between N children', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard.section(
            key: key,
            children: const [Text('a'), Text('b'), Text('c')],
          ),
        ),
      ),
    );
    final cardFinder = find.byKey(key);
    final gaps = tester
        .widgetList<SizedBox>(
          find.descendant(of: cardFinder, matching: find.byType(SizedBox)),
        )
        .where((s) => s.height == AppCard.sectionSpacing)
        .toList();
    expect(gaps.length, 2); // N-1 = 3-1 = 2
  });

  testWidgets('AppCard.section uses ClipRRect for clipping', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard.section(
            key: key,
            children: const [SizedBox(), SizedBox()],
          ),
        ),
      ),
    );
    final cardFinder = find.byKey(key);
    expect(
      find.descendant(of: cardFinder, matching: find.byType(ClipRRect)),
      findsOneWidget,
    );
  });

  testWidgets('AppCard.section wraps each child in its own Material', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard.section(
            key: key,
            children: const [SizedBox(), SizedBox()],
          ),
        ),
      ),
    );
    final cardFinder = find.byKey(key);
    // Each child gets its own Material — 2 children → 2 Material widgets
    expect(
      find.descendant(of: cardFinder, matching: find.byType(Material)),
      findsNWidgets(2),
    );
  });

  testWidgets('AppCard.section with single child has no gap', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard.section(key: key, children: const [SizedBox()]),
        ),
      ),
    );
    final cardFinder = find.byKey(key);
    final gaps = tester
        .widgetList<SizedBox>(
          find.descendant(of: cardFinder, matching: find.byType(SizedBox)),
        )
        .where((s) => s.height == 1.5)
        .toList();
    expect(gaps.length, 0);
  });

  // --- AppCard.sectionDivider ---

  testWidgets('sectionDivider returns a Divider widget', (tester) async {
    late Widget divider;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            divider = AppCard.sectionDivider(context);
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    expect(divider, isA<Divider>());
    final d = divider as Divider;
    expect(d.thickness, AppCard.sectionSpacing);
  });
}
