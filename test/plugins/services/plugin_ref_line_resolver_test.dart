import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';

void main() {
  PluginRefLineResolver buildResolver(List<LineRefEntry> entries) =>
      PluginRefLineResolver(fetchLineRefs: (_) async => entries);

  group('PluginRefLineResolver — תנ"ך (פרק:פסוק)', () {
    final bamidbar = TextBook(title: 'במדבר', categoryId: 1);
    final entries = <LineRefEntry>[
      (lineIndex: 1190, heRef: 'במדבר לג, א'),
      (lineIndex: 1194, heRef: 'במדבר לג, ה'),
      (lineIndex: 1204, heRef: 'במדבר לג, טו'),
    ];

    test('פורמט נקודתיים "לג:ה"', () async {
      final resolver = buildResolver(entries);
      expect(
        await resolver.resolve(book: bamidbar, ref: 'לג:ה'),
        1194,
      );
    });

    test('פורמט פסיק ורווח', () async {
      final resolver = buildResolver(entries);
      expect(await resolver.resolve(book: bamidbar, ref: 'לג, ה'), 1194);
      expect(await resolver.resolve(book: bamidbar, ref: 'לג ה'), 1194);
    });

    test('מילות מיקום "פרק לג פסוק ה"', () async {
      final resolver = buildResolver(entries);
      expect(
        await resolver.resolve(book: bamidbar, ref: 'פרק לג פסוק ה'),
        1194,
      );
    });

    test('טווח "לג:ה-ז" נפתח בתחילת הטווח', () async {
      final resolver = buildResolver(entries);
      expect(await resolver.resolve(book: bamidbar, ref: 'לג:ה-ז'), 1194);
    });

    test('"לג:ה" לא נתפס ע"י פסוק טו', () async {
      final resolver = buildResolver(entries);
      expect(await resolver.resolve(book: bamidbar, ref: 'לג:טו'), 1204);
    });

    test('רכיב יחיד ("לג") הוא ברמת TOC — מחזיר null', () async {
      final resolver = buildResolver(entries);
      expect(await resolver.resolve(book: bamidbar, ref: 'לג'), isNull);
    });

    test('הפניה שאינה קיימת מחזירה null', () async {
      final resolver = buildResolver(entries);
      expect(await resolver.resolve(book: bamidbar, ref: 'לד:ב'), isNull);
    });
  });

  group('PluginRefLineResolver — שולחן ערוך (סימן:סעיף, כותרת עם פסיק)', () {
    final shulchanAruch = TextBook(
      title: 'שולחן ערוך, אורח חיים',
      categoryId: 2,
    );
    final entries = <LineRefEntry>[
      (lineIndex: 38, heRef: 'שולחן ערוך, אורח חיים ד, א'),
      (lineIndex: 39, heRef: 'שולחן ערוך, אורח חיים ד, ב'),
    ];

    test('"ד:ב" נפתר לסעיף בתוך הסימן', () async {
      final resolver = buildResolver(entries);
      expect(
        await resolver.resolve(book: shulchanAruch, ref: 'ד:ב'),
        39,
      );
    });

    test('"סימן ד סעיף ב" נפתר גם עם מילות מיקום', () async {
      final resolver = buildResolver(entries);
      expect(
        await resolver.resolve(book: shulchanAruch, ref: 'סימן ד סעיף ב'),
        39,
      );
    });
  });

  group('PluginRefLineResolver — גמרא (דף עמוד, קטע)', () {
    final berachot = TextBook(title: 'ברכות', categoryId: 3);
    // heRef של גמרא: "ברכות ב., א" — הנקודה מציינת עמוד א, והרכיב האחרון
    // הוא מספר הקטע בתוך העמוד.
    final entries = <LineRefEntry>[
      (lineIndex: 10, heRef: 'ברכות ב., א'),
      (lineIndex: 11, heRef: 'ברכות ב., ב'),
      (lineIndex: 20, heRef: 'ברכות ב:, א'),
    ];

    test('"ב. א" נפתר לקטע בעמוד', () async {
      final resolver = buildResolver(entries);
      expect(await resolver.resolve(book: berachot, ref: 'ב. א'), 10);
    });

    test('"ב ע"א ב" — סימון עמוד בגרשיים', () async {
      final resolver = buildResolver(entries);
      expect(await resolver.resolve(book: berachot, ref: 'ב ע"א ב'), 11);
    });

    test('הפניה דו-רכיבית לא נתפסת ע"י heRef תלת-רכיבי', () async {
      final resolver = buildResolver(entries);
      // "ב א" עשוי להתכוון לדף ב עמוד א (רמת TOC) — אסור להתאים לקטע.
      expect(await resolver.resolve(book: berachot, ref: 'ב א'), isNull);
    });
  });

  group('PluginRefLineResolver — קצוות', () {
    test('ספר בלי heRef-ים מחזיר null', () async {
      final resolver = buildResolver(const []);
      expect(
        await resolver.resolve(
          book: TextBook(title: 'ספר ריק', categoryId: 4),
          ref: 'א:ב',
        ),
        isNull,
      );
    });

    test('heRef של ספר אחר עם אותה תבנית לא מותאם', () async {
      final resolver = buildResolver(const [
        (lineIndex: 5, heRef: 'שמות לג, ה'),
      ]);
      expect(
        await resolver.resolve(
          book: TextBook(title: 'במדבר', categoryId: 1),
          ref: 'לג:ה',
        ),
        isNull,
      );
    });
  });
}
