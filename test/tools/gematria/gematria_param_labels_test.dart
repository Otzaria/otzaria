import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/gematria/gematria_search_screen.dart';

void main() {
  group('GematriaSearchScreenState.buildActiveParamLabels', () {
    List<String> build({
      String method = 'regular',
      bool useWithKolel = false,
      bool wholeVerseOnly = false,
      bool torahOnly = false,
      bool filterDuplicates = false,
    }) => GematriaSearchScreenState.buildActiveParamLabels(
      gematriaMethod: method,
      useWithKolel: useWithKolel,
      wholeVerseOnly: wholeVerseOnly,
      torahOnly: torahOnly,
      filterDuplicates: filterDuplicates,
    );

    test('שיטה רגילה ללא דגלים — מציג רק את שם השיטה', () {
      expect(build(), ['גימטריה רגילה']);
    });

    test('גימטריה קטנה', () {
      expect(build(method: 'small').first, 'גימטריה קטנה');
    });

    test('אותיות סופיות', () {
      expect(build(method: 'finalLetters').first, 'אותיות סופיות');
    });

    test('עם הכולל מופיע כתווית', () {
      expect(build(useWithKolel: true), contains('עם הכולל'));
    });

    test('כל הדגלים פעילים — שיטה תחילה ואז הדגלים לפי הסדר', () {
      expect(
        build(
          method: 'small',
          useWithKolel: true,
          wholeVerseOnly: true,
          torahOnly: true,
          filterDuplicates: true,
        ),
        ['גימטריה קטנה', 'עם הכולל', 'פסוק שלם', 'תורה בלבד', 'ללא כפילויות'],
      );
    });
  });

  group('GematriaSearchScreenState.isLatestSearch', () {
    test('מאשר רק את מזהה החיפוש העדכני', () {
      expect(GematriaSearchScreenState.isLatestSearch(3, 3), isTrue);
      expect(GematriaSearchScreenState.isLatestSearch(2, 3), isFalse);
    });
  });
}
