import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/shelf_description.dart';

Category _category(String shortDescription, String description) => Category(
  title: 'משנה',
  description: description,
  shortDescription: shortDescription,
  order: 0,
  subCategories: [],
  books: [],
  parent: null,
);

void main() {
  group('categoryDescriptionParts', () {
    test('ארוך שפותח בקצר: הקצר ראשון, ואחריו ההמשך בלבד', () {
      final parts = categoryDescriptionParts(
        _category('יסוד המסירה.', 'יסוד המסירה. והוא קיבץ הכל.'),
      );
      expect(parts.lead, 'יסוד המסירה.');
      expect(parts.paragraphs, ['והוא קיבץ הכל.']);
    });

    test('ארוך שאינו פותח בקצר: שניהם, הקצר ראשון', () {
      final parts = categoryDescriptionParts(_category('קצר', 'ארוך אחר'));
      expect(parts.lead, 'קצר');
      expect(parts.paragraphs, ['ארוך אחר']);
    });

    test('ארוך בכמה שורות: פסקה לכל שורה', () {
      final parts = categoryDescriptionParts(_category('', 'א\n\nב'));
      expect(parts.lead, isEmpty);
      expect(parts.paragraphs, ['א', 'ב']);
    });

    test('ארוך זהה לקצר אינו חוזר', () {
      final parts = categoryDescriptionParts(_category('קצר.', 'קצר.'));
      expect(parts.lead, 'קצר.');
      expect(parts.paragraphs, isEmpty);
    });

    test('בלי תיאורים: אין מה להציג', () {
      expect(categoryHasDescription(_category('', '')), isFalse);
      expect(categoryHasDescription(_category('קצר', '')), isTrue);
      expect(categoryHasDescription(_category('', 'ארוך')), isTrue);
    });
  });

  group('shelfDescriptionSpans', () {
    test('עגולות מוקטנות משמעותית ובלי הדגשה, מרובעות מוקטנות מעט', () {
      final spans = shelfDescriptionSpans('א (ב) ג [ד] ה', 20);
      expect(spans.map((s) => s.text), ['א ', '(ב)', ' ג ', '[ד]', ' ה']);
      expect(spans[1].style?.fontSize, closeTo(15.2, 0.001));
      expect(spans[1].style?.fontWeight, FontWeight.w400);
      expect(spans[3].style?.fontSize, closeTo(18.4, 0.001));
      expect(spans[3].style?.fontWeight, isNull);
    });

    test('סוגריים שלא נסגרו נשארות כטקסט רגיל', () {
      final spans = shelfDescriptionSpans('א (ב', 20);
      expect(spans.map((s) => s.text), ['א (ב']);
      expect(spans.single.style, isNull);
    });
  });

  testWidgets('הקצר מודגש ואחריו הארוך בפסקה נפרדת', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ShelfDescription(category: _category('קצר (עי׳ שם)', 'ארוך')),
          ),
        ),
      ),
    );

    final lead = tester.widget<Text>(find.text('קצר (עי׳ שם)'));
    expect((lead.textSpan! as TextSpan).style?.fontWeight, FontWeight.bold);
    final longRect = tester.getRect(find.text('ארוך'));
    final leadRect = tester.getRect(find.text('קצר (עי׳ שם)'));
    expect(longRect.top, greaterThan(leadRect.bottom));
  });
}
