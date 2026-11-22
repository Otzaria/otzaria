import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Widget card(Book book, {double width = 260, double height = 160}) {
    return MaterialApp(
      home: Material(
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: BookGridItem(book: book, onBookClickCallback: () {}),
          ),
        ),
      ),
    );
  }

  testWidgets('הכרטיס מציג את התיאור הקצר, עד שלוש שורות', (tester) async {
    const shortDescription = 'תיאור קצר שמוצג בכרטיס';
    final book = TextBook(
      title: 'ספר מידע',
      heShortDesc: shortDescription,
      heDesc: 'תיאור ארוך שמוצג בריחוף על כפתור המידע בלבד',
    );

    await tester.pumpWidget(card(book));
    await tester.pumpAndSettle();

    expect(find.text(shortDescription), findsOneWidget);
    expect(tester.widget<Text>(find.text(shortDescription)).maxLines, 3);
  });

  testWidgets('תיאור ארוך מקוצר ל-120 תווים בכרטיס', (tester) async {
    final description = List.filled(200, 'א').join();
    final book = TextBook(title: 'ספר מידע', heShortDesc: description);

    await tester.pumpWidget(card(book));
    await tester.pumpAndSettle();

    expect(find.text(description), findsNothing);
    expect(
      find.text(truncateBookCardDescription(description)),
      findsOneWidget,
    );
  });

  testWidgets('בכרטיס נמוך התיאור הקצר מוגבל לשורה אחת', (tester) async {
    const shortDescription = 'תיאור קצר שמוצג בכרטיס נמוך';
    final book = TextBook(title: 'ספר', heShortDesc: shortDescription);

    await tester.pumpWidget(card(book, height: 90));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(shortDescription)).maxLines, 1);
  });

  testWidgets('בלי תיאור קצר אין שורת תיאור, והתיאור המורחב נשאר בריחוף', (
    tester,
  ) async {
    const fullDescription = 'תיאור ארוך שמוצג בריחוף על כפתור המידע בלבד';
    final book = TextBook(title: 'ספר מידע', heDesc: fullDescription);

    await tester.pumpWidget(card(book));
    await tester.pumpAndSettle();

    expect(find.text(fullDescription), findsNothing);
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((tooltip) => tooltip.message),
      contains(fullDescription),
    );
  });
}
