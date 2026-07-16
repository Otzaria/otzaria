import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';

void main() {
  group('shouldShowFacetFilterBanner', () {
    test('אין שאילתה → אין באנר', () {
      expect(
        shouldShowFacetFilterBanner(
          searchQuery: '',
          searchScopeFacets: const ['/תנ"ך'],
        ),
        isFalse,
      );
    });

    test('ברירת המחדל ["/"] (כל הספרייה) → אין באנר', () {
      expect(
        shouldShowFacetFilterBanner(
          searchQuery: 'דבר',
          searchScopeFacets: const ['/'],
        ),
        isFalse,
      );
    });

    test('טווח ריק [] (כל הספרייה) → אין באנר', () {
      expect(
        shouldShowFacetFilterBanner(
          searchQuery: 'דבר',
          searchScopeFacets: const [],
        ),
        isFalse,
      );
    });

    test('טווח מוגבל לקטגוריה אחת → באנר מוצג', () {
      expect(
        shouldShowFacetFilterBanner(
          searchQuery: 'דבר',
          searchScopeFacets: const ['/תנ"ך'],
        ),
        isTrue,
      );
    });

    test('טווח מוגבל לכמה קטגוריות → באנר מוצג', () {
      expect(
        shouldShowFacetFilterBanner(
          searchQuery: 'דבר',
          searchScopeFacets: const ['/תנ"ך', '/משנה'],
        ),
        isTrue,
      );
    });

    test('פאסט שורש "/" מנורמל החוצה אך קטגוריה אמיתית עדיין מציגה באנר', () {
      // ['/', '/תנ"ך'] → אחרי נרמול {'/תנ"ך'} → הטווח מוגבל → באנר.
      expect(
        shouldShowFacetFilterBanner(
          searchQuery: 'דבר',
          searchScopeFacets: const ['/', '/תנ"ך'],
        ),
        isTrue,
      );
    });

    test('הטווח הוא כל הספרייה (סינון זמני בעץ בלבד) → אין באנר', () {
      // סינון זמני שנבחר בעץ התוצאות (currentFacets) אינו נכנס יותר לחישוב:
      // הבאנר מופיע רק כשהוגדר טווח (scope) מראש.
      expect(
        shouldShowFacetFilterBanner(
          searchQuery: 'דבר',
          searchScopeFacets: const ['/'],
        ),
        isFalse,
      );
    });
  });
}
