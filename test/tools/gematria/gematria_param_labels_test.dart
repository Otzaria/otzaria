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

    test('אותיות סופיות', () {
      expect(build(method: 'finalLetters').first, 'אותיות סופיות');
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
}
