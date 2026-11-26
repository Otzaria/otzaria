import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:pdfrx/pdfrx.dart';

// issue #4497: בחולין PDF, חיפוש "ב." בחלונית הניווט הוביל ל"נ." וחיפוש
// "קיא:" הוביל ל"קב" — הנקודה והנקודתיים נמחקו בנרמול, ו"ב" התאים לכל דף
// שיש בו האות ב, בסדר תוכן העניינים.
List<String> _filter(List<String> titles, String query) {
  final outline = [
    for (final t in titles)
      PdfOutlineNode(title: t, dest: null, children: const []),
  ];
  return filterPdfOutline(
    flattenPdfOutlineForSearch(outline),
    query,
  ).map((e) => e.node.title).toList();
}

void main() {
  const chullin = ['ב.', 'ב:', 'יב.', 'נ.', 'נב.', 'קב.', 'קיא.', 'קיא:'];

  test('"ב." מוצא את דף ב עמוד א בלבד, ולא נב./יב./קב.', () {
    expect(_filter(chullin, 'ב.'), ['ב.']);
  });

  test('"קיא:" מוצא את עמוד ב ולא את עמוד א', () {
    expect(_filter(chullin, 'קיא:'), ['קיא:']);
    expect(_filter(chullin, 'קיא.'), ['קיא.']);
  });

  test('דף עם עמוד בתוך כותרת ארוכה נמצא, ובלי עמוד — כל הדף', () {
    const titles = ['חולין דף ב.', 'חולין דף ב:', 'חולין דף נב.', 'מסכת ב"ב'];
    expect(_filter(titles, 'ב:'), ['חולין דף ב:']);
    expect(_filter(titles, 'דף ב.'), ['חולין דף ב.']);
    // כותרת בלי סימן עמוד אינה נפסלת בגלל העמוד.
    expect(_filter(['דף ב', 'דף נב'], 'ב.'), ['דף ב']);
  });

  test('בלי סימן עמוד: התאמה מדויקת ותחילית קודמות להכלה', () {
    expect(_filter(chullin, 'קיא'), ['קיא.', 'קיא:']);
    expect(_filter(chullin, 'ב').take(2), ['ב.', 'ב:']);
    expect(_filter(['בבא בתרא דף ב', 'דף ג', 'דף קו'], 'דף'), [
      'דף ג',
      'דף קו',
      'בבא בתרא דף ב',
    ]);
  });
}
