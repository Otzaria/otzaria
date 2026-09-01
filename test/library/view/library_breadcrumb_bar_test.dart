import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/library_breadcrumb_bar.dart';

Category _category(String title, {Category? parent}) {
  final c = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 999,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent?.subCategories.add(c);
  return c;
}

/// בונה שרשרת קטגוריות מקוננות לפי הכותרות ומחזיר אותן מהעליונה לתחתונה.
List<Category> _chain(List<String> titles) {
  final library = Library(categories: []);
  Category parent = library;
  final result = <Category>[];
  for (final title in titles) {
    parent = _category(title, parent: parent);
    result.add(parent);
  }
  return result;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('מציג את כל הנתיב כשהשרשרת קצרה', (tester) async {
    final chain = _chain(['תנך', 'תורה', 'בראשית']);
    await tester.pumpWidget(
      _wrap(
        LibraryBreadcrumbBar(
          chain: chain,
          onNavigate: (_) {},
          onNavigateHome: () {},
        ),
      ),
    );

    expect(find.text('תנך'), findsOneWidget);
    expect(find.text('תורה'), findsOneWidget);
    expect(find.text('בראשית'), findsOneWidget);
    expect(find.text('…'), findsNothing);
  });

  testWidgets('לחיצה על קטע ביניים מנווטת אליו', (tester) async {
    final chain = _chain(['תנך', 'תורה', 'בראשית']);
    Category? navigated;
    var homeTapped = false;
    await tester.pumpWidget(
      _wrap(
        LibraryBreadcrumbBar(
          chain: chain,
          onNavigate: (c) => navigated = c,
          onNavigateHome: () => homeTapped = true,
        ),
      ),
    );

    await tester.tap(find.text('תורה'));
    expect(navigated, same(chain[1]));

    await tester.tap(find.byType(Tooltip));
    expect(homeTapped, isTrue);
  });

  testWidgets('הקטע הנוכחי אינו לחיץ', (tester) async {
    final chain = _chain(['תנך', 'תורה']);
    Category? navigated;
    await tester.pumpWidget(
      _wrap(
        LibraryBreadcrumbBar(
          chain: chain,
          onNavigate: (c) => navigated = c,
          onNavigateHome: () {},
        ),
      ),
    );

    await tester.tap(find.text('תורה'), warnIfMissed: false);
    expect(navigated, isNull);
  });

  testWidgets('שרשרת ארוכה מתקצרת עם "…" ושומרת ראש וזנב', (tester) async {
    final chain = _chain(['א', 'ב', 'ג', 'ד', 'ה', 'ו']);
    await tester.pumpWidget(
      _wrap(
        LibraryBreadcrumbBar(
          chain: chain,
          onNavigate: (_) {},
          onNavigateHome: () {},
        ),
      ),
    );

    expect(find.text('א'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    expect(find.text('ה'), findsOneWidget);
    expect(find.text('ו'), findsOneWidget);
    expect(find.text('ב'), findsNothing);
    expect(find.text('ג'), findsNothing);
    expect(find.text('ד'), findsNothing);
  });
}
