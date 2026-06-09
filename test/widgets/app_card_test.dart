import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

void main() {
  // --- AppCard (single child) ---

  testWidgets('AppCard renders child', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppCard(child: const Text('hello'))),
    ));
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('AppCard without onTap uses Material and no InkWell',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppCard(key: key, child: const SizedBox())),
    ));
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
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AppCard(key: key, onTap: () {}, child: const SizedBox())),
    ));
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
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppCard(
          onTap: () => tapped = true,
          child: const Text('tap me'),
        ),
      ),
    ));
    await tester.tap(find.text('tap me'));
    expect(tapped, isTrue);
  });

  testWidgets('AppCard with selected adds ColoredBox overlay', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AppCard(key: key, selected: true, child: const SizedBox())),
    ));
    final cardFinder = find.byKey(key);
    expect(
      find.descendant(of: cardFinder, matching: find.byType(ColoredBox)),
      findsWidgets,
    );
  });

  // --- AppCard.section ---

  testWidgets('AppCard.section renders all children', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppCard.section(children: const [
          Text('one'),
          Text('two'),
          Text('three'),
        ]),
      ),
    ));
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
  });

  testWidgets('AppCard.section inserts N-1 Container gaps between N children',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppCard.section(
          key: key,
          children: const [Text('a'), Text('b'), Text('c')],
        ),
      ),
    ));
    final cardFinder = find.byKey(key);
    final allContainers = tester.widgetList<Container>(
      find.descendant(of: cardFinder, matching: find.byType(Container)),
    );
    final dividers = allContainers
        .where((c) {
          final constraints = c.constraints;
          return constraints != null &&
              constraints.minHeight == AppCard.sectionSpacing &&
              constraints.maxHeight == AppCard.sectionSpacing;
        })
        .toList();
    expect(dividers.length, 2); // N-1 = 3-1 = 2
  });

  testWidgets('AppCard.section uses single Material with clip', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppCard.section(
          key: key,
          children: const [SizedBox(), SizedBox()],
        ),
      ),
    ));
    final cardFinder = find.byKey(key);
    expect(
      find.descendant(of: cardFinder, matching: find.byType(Material)),
      findsOneWidget,
    );
    final material = tester.widget<Material>(
      find.descendant(of: cardFinder, matching: find.byType(Material)),
    );
    expect(material.clipBehavior, Clip.antiAlias);
  });

  testWidgets('AppCard.section does not use ClipRRect', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppCard.section(key: key, children: const [SizedBox()]),
      ),
    ));
    final cardFinder = find.byKey(key);
    expect(
      find.descendant(of: cardFinder, matching: find.byType(ClipRRect)),
      findsNothing,
    );
  });

  testWidgets('AppCard.section with single child has no gap', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppCard.section(key: key, children: const [SizedBox()]),
      ),
    ));
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

  testWidgets('sectionDivider returns Divider with scaffoldBackgroundColor',
      (tester) async {
    late Color dividerColor;
    late Color scaffoldColor;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        scaffoldColor = Theme.of(context).scaffoldBackgroundColor;
        final divider = AppCard.sectionDivider(context) as Divider;
        dividerColor = divider.color!;
        return const Scaffold(body: SizedBox());
      }),
    ));
    expect(dividerColor, equals(scaffoldColor));
  });
}
