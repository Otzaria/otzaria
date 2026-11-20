// סעיף 63 (q63): כרטיס קטגוריה מציג את התיאור הקצר, כמו כרטיס ספר.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

Category _category(
  String title, {
  String shortDescription = '',
  String description = '',
}) => Category(
  title: title,
  description: description,
  shortDescription: shortDescription,
  order: 0,
  subCategories: [],
  books: [],
  parent: null,
);

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Widget card(Category category, {double width = 300, double? height}) {
    return MaterialApp(
      home: Material(
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: CategoryGridItem(
              category: category,
              onCategoryClickCallback: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('הכרטיס מציג את התיאור הקצר, עד שתי שורות', (tester) async {
    const shortDescription = 'שולחן ערוך ונושאי כליו';
    await tester.pumpWidget(
      card(
        _category(
          'הלכה',
          shortDescription: shortDescription,
          description: 'תיאור מורחב שנשאר בריחוף',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(shortDescription), findsOneWidget);
    expect(tester.widget<Text>(find.text(shortDescription)).maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('בלי תיאור קצר אין שורת תיאור, והמורחב נשאר בריחוף', (
    tester,
  ) async {
    const fullDescription = 'תיאור מורחב שנשאר בריחוף';
    await tester.pumpWidget(
      card(_category('הלכה', description: fullDescription)),
    );
    await tester.pumpAndSettle();

    expect(find.text(fullDescription), findsNothing);
    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((tooltip) => tooltip.message),
      contains(fullDescription),
    );
  });

  testWidgets('בכרטיס בגובה קבוע התיאור נכנס בשורה אחת בלי גלישה', (
    tester,
  ) async {
    const shortDescription = 'תיאור קצר שנכנס בשורה אחת';
    await tester.pumpWidget(
      card(_category('הלכה', shortDescription: shortDescription), height: 72),
    );
    await tester.pumpAndSettle();

    expect(find.text(shortDescription), findsOneWidget);
    expect(tester.widget<Text>(find.text(shortDescription)).maxLines, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('שם ארוך שתופס את הכרטיס מסתיר את התיאור, בלי גלישה', (
    tester,
  ) async {
    const shortDescription = 'תיאור קצר שאין לו מקום';
    await tester.pumpWidget(
      card(
        _category(
          'שאלות ותשובות מחכמי ספרד ואשכנז בדורות האחרונים',
          shortDescription: shortDescription,
        ),
        width: 200,
        height: 80,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(shortDescription), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
