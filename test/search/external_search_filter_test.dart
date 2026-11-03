import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/search/view/external_search_results_section.dart';

void main() {
  group('externalFilterCategoryOf', () {
    test('נתיב קטגוריה נשאר כמות שהוא — גם עם רווחים', () {
      expect(externalFilterCategoryOf('/תלמוד בבלי'), '/תלמוד בבלי');
      expect(
        externalFilterCategoryOf('/הלכה/שולחן ערוך'),
        '/הלכה/שולחן ערוך',
      );
      expect(externalFilterCategoryOf('/'), '/');
    });

    test('facet של ספר מתקפל לקטגוריית האם', () {
      expect(externalFilterCategoryOf('/הלכה/id:1234'), '/הלכה');
      expect(externalFilterCategoryOf('/תנ"ך/תורה/uid:7'), '/תנ"ך/תורה');
      expect(externalFilterCategoryOf('/הלכה/ext:hb:42'), '/הלכה');
      expect(externalFilterCategoryOf('/id:9'), '/');
    });

    test('facet של ספר בדלי אינו מתקפל — הוא הבחירה עצמה', () {
      expect(
        externalFilterCategoryOf('/עוד מהיברובוקס/#42'),
        '/עוד מהיברובוקס/#42',
      );
    });
  });

  group('externalVisibleIdsFor', () {
    const index = [
      ExternalSearchIndexEntry(id: 1, hits: 5, categoryPath: '/תלמוד בבלי'),
      ExternalSearchIndexEntry(id: 2, hits: 3, categoryPath: '/הלכה'),
      ExternalSearchIndexEntry(id: 3, hits: 1),
      ExternalSearchIndexEntry(
        id: 4,
        hits: 2,
        categoryPath: '/תלמוד בבלי/מסכת ברכות',
      ),
    ];
    final categories = {
      for (final entry in index) entry.id: entry.categoryPath,
    };

    test('קטגוריה עם רווח תואמת את עצמה ואת צאצאיה', () {
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/תלמוד בבלי'],
          otherFacet: '/עוד מהיברובוקס',
        ),
        [1, 4],
      );
    });

    test('דלי "עוד מ" תואם רק תוצאות ללא סיווג', () {
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/עוד מהיברובוקס'],
          otherFacet: '/עוד מהיברובוקס',
        ),
        [3],
      );
    });

    test('כמה קטגוריות — OR; קטגוריה זרה — ריק; השורש — הכול', () {
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/הלכה', '/עוד מהיברובוקס'],
          otherFacet: '/עוד מהיברובוקס',
        ),
        [2, 3],
      );
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/קבלה'],
          otherFacet: '/עוד מהיברובוקס',
        ),
        isEmpty,
      );
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/'],
          otherFacet: null,
        ),
        [1, 2, 3, 4],
      );
    });

    test('facet של ספר בדלי תואם את אותו ספר בלבד', () {
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/עוד מהיברובוקס/#3'],
          otherFacet: '/עוד מהיברובוקס',
        ),
        [3],
      );
      // ספר מסווג נבחר דרך הדלי אינו קיים שם — הבחירה מחזירה ריק.
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/עוד מהיברובוקס/#999'],
          otherFacet: '/עוד מהיברובוקס',
        ),
        isEmpty,
      );
      // בלי דלי (אינדקס בלי סיווג) אין facet כזה.
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/עוד מהיברובוקס/#3'],
          otherFacet: null,
        ),
        isEmpty,
      );
    });

    test('ספר בדלי לצד קטגוריה — OR ביניהם, בסדר האינדקס', () {
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/הלכה', '/עוד מהיברובוקס/#1'],
          otherFacet: '/עוד מהיברובוקס',
        ),
        [1, 2],
      );
    });

    test('קטגוריה שהיא קידומת-מחרוזת אך לא קידומת-נתיב אינה תואמת', () {
      expect(
        externalVisibleIdsFor(
          index: index,
          categories: categories,
          facets: const ['/תלמוד'],
          otherFacet: null,
        ),
        isEmpty,
      );
    });
  });

  group('externalValidatedCategoryOf', () {
    const validPaths = {'/תנ"ך', '/תנ"ך/תורה/בראשית', '/הלכה'};

    test('נתיב קיים בעץ מתקבל כמות שהוא — גם נתיב עמוק', () {
      expect(
        externalValidatedCategoryOf('/תנ"ך/תורה/בראשית', validPaths),
        '/תנ"ך/תורה/בראשית',
      );
      expect(externalValidatedCategoryOf('/הלכה', validPaths), '/הלכה');
    });

    test('נתיב לא קיים נופל לקטגוריית-העל שלו כשהיא קיימת', () {
      expect(
        externalValidatedCategoryOf('/תנ"ך/נביאים/ישעיהו', validPaths),
        '/תנ"ך',
      );
    });

    test('תיקייה ששמה מכיל פסיק מסווגת ל-facet שלה בשתי צורות הנתיב', () {
      // עץ הספרייה של התוסף נותן את השם עם הפסיק; נתיב הספר — מנורמל.
      const facet = '/הלכה/נתיבות המשפט/ביאורים';
      for (final suggested in ['/הלכה/נתיבות המשפט, ביאורים', facet]) {
        expect(
          externalValidatedCategoryOf(suggested, {'/הלכה', facet}),
          facet,
          reason: suggested,
        );
      }
    });

    test('נתיב זר לגמרי, ריק או null — אין סיווג (דלי "עוד מ")', () {
      expect(externalValidatedCategoryOf('/קבלה/זוהר', validPaths), isNull);
      expect(externalValidatedCategoryOf('/', validPaths), isNull);
      expect(externalValidatedCategoryOf(null, validPaths), isNull);
    });
  });
}
