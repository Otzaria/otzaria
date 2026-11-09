// כרטיסי התיקייה בתצוגה צרה (q12 Q8, ss4): בשורות נמוכות משלהם, והספרים
// שאחריהם מתחילים בשורה חדשה בגובה הרגיל. השם בשתי שורות נכנס בלי גלישה
// בגופן הממשק האמיתי.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/golden_fonts.dart';

Category _category(String title) => Category(
  title: title,
  description: '',
  shortDescription: '',
  order: 0,
  subCategories: [],
  books: [],
  parent: null,
);

Future<void> _pumpGrid(
  WidgetTester tester, {
  required double width,
  required List<Category> categories,
  required List<Book> books,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: width,
              child: MyGridView(
                leadingCategoryCount: categories.length,
                items: [
                  for (final c in categories)
                    CategoryGridItem(
                      category: c,
                      onCategoryClickCallback: () {},
                    ),
                  for (final b in books)
                    BookGridItem(book: b, onBookClickCallback: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await loadGoldenFonts();
    // הגופן של ערכת הנושא בבדיקה (Roboto) הוא גופן הממשק האמיתי.
    final roboto = FontLoader('Roboto')
      ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
    await roboto.load();
  });

  testWidgets('עמודה אחת (טלפון): התיקייה נמוכה, והספר בגובה הרגיל', (
    tester,
  ) async {
    await _pumpGrid(
      tester,
      width: 360,
      categories: [_category('תנ"ך'), _category('הלכה')],
      books: [TextBook(title: 'ספר', author: 'מחבר')],
    );
    final categories = find.byType(CategoryGridItem);
    // שתי שורות של שם וריפוד: כ־68 בגופן הממשק, ולא 112 של כרטיס ספר.
    final height = tester.getSize(categories.first).height;
    expect(
      height,
      closeTo(narrowCategoryCardHeight(tester.element(categories.first)), 0.5),
    );
    expect(height, inInclusiveRange(kNarrowCategoryCardHeight, 72));
    final book = find.byType(BookGridItem);
    expect(
      tester.getSize(book).height,
      closeTo(kNarrowGridCardMinHeight, 0.5),
    );
    // הספר מתחת לתיקייה השנייה, עם הריווח הרגיל.
    expect(
      tester.getTopLeft(book).dy - tester.getBottomLeft(categories.last).dy,
      closeTo(kLibraryGridSpacing, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('שתי עמודות: שם ארוך בשתי שורות נכנס, והספרים בשורה חדשה', (
    tester,
  ) async {
    await _pumpGrid(
      tester,
      width: 724,
      categories: [
        _category('שאלות ותשובות מחכמי ספרד ואשכנז בדורות האחרונים'),
        _category('הלכה'),
        _category('חסידות'),
      ],
      books: [
        TextBook(title: 'ספר א', author: 'מחבר'),
        TextBook(title: 'ספר ב', author: 'מחבר'),
      ],
    );
    expect(tester.takeException(), isNull);
    final categories = find.byType(CategoryGridItem);
    final books = find.byType(BookGridItem);
    // התיקייה השלישית לבדה בשורה השנייה; הספר הראשון בשורה שאחריה, בעמודה
    // הראשונה (מימין) ולא ליד התיקייה.
    expect(
      tester.getTopRight(books.first).dx,
      closeTo(tester.getTopRight(categories.first).dx, 0.5),
    );
    expect(
      tester.getTopLeft(books.first).dy,
      greaterThan(tester.getBottomLeft(categories.at(2)).dy),
    );
    expect(
      tester.getSize(books.first).height,
      closeTo(kNarrowGridCardMinHeight, 0.5),
    );
  });

  testWidgets('הגובה גדל עם מידת הטקסט, בלי גלישה', (tester) async {
    await _pumpGrid(
      tester,
      width: 360,
      categories: [_category('שאלות ותשובות מחכמי ספרד ואשכנז')],
      books: const [],
      textScale: 1.3,
    );
    expect(
      tester.getSize(find.byType(CategoryGridItem)).height,
      greaterThanOrEqualTo(kNarrowCategoryCardHeight * 1.3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ברשת רחבה (800 ומעלה) אין שינוי: תיקייה וספר באותו גובה', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpGrid(
      tester,
      width: 1000,
      categories: [_category('הלכה')],
      books: [TextBook(title: 'ספר', author: 'מחבר')],
    );
    expect(
      tester.getSize(find.byType(CategoryGridItem)).height,
      closeTo(tester.getSize(find.byType(BookGridItem)).height, 0.5),
    );
  });
}
