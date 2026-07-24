import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

void main() {
  test('TextBook toJson/fromJson שומר categoryId בשחזור טאב', () {
    final original = TextBook(
      title: 'בראשית',
      categoryId: 7,
      fileType: 'txt',
      categoryPath: 'תנך/תורה',
      filePath: '/tmp/bereshit.txt',
      heCategories: 'תנ"ך, תורה',
    );

    final restored = Book.fromJson(original.toJson()) as TextBook;

    expect(restored.title, 'בראשית');
    expect(restored.categoryId, 7);
    expect(restored.fileType, 'txt');
    expect(restored.categoryPath, 'תנך/תורה');
  });

  test('TextBook toJson/fromJson שומר מחבר ותקופה בשחזור טאב', () {
    final original = TextBook(
      title: 'פרי מגדים על אורח חיים',
      author: 'יוסף בן מאיר תאומים',
      heEra: 'אחרונים',
      categoryId: 12,
    );

    final restored = Book.fromJson(original.toJson()) as TextBook;

    expect(restored.author, 'יוסף בן מאיר תאומים');
    expect(restored.heEra, 'אחרונים');
  });

  test('PdfBook toJson/fromJson שומר מחבר בשחזור טאב', () {
    final original = PdfBook(
      title: 'ספר',
      path: '/tmp/sefer.pdf',
      author: 'מחבר כלשהו',
    );

    final restored = Book.fromJson(original.toJson()) as PdfBook;

    expect(restored.author, 'מחבר כלשהו');
  });

  group('flattenToc', () {
    test('משטח עץ של מסכת (root יחיד + דפים כצאצאים)', () {
      // מבנה כמו ביומא: root "יומא" וכל הדפים children שלו.
      final root = TocEntry(text: 'יומא', index: 0, level: 0);
      final dafSadBet = TocEntry(
        text: 'דף סד:',
        index: 250,
        level: 1,
        parent: root,
      );
      root.children.addAll([
        TocEntry(text: 'דף ב.', index: 0, level: 1, parent: root),
        dafSadBet,
      ]);

      final flat = flattenToc([root]);

      // הצאצאים נכללים — לא רק השורש
      expect(flat.length, 3);
      expect(flat.map((e) => e.text), containsAll(['יומא', 'דף ב.', 'דף סד:']));
      expect(flat.firstWhere((e) => e.text == 'דף סד:').index, 250);
    });

    test('רשימה שטוחה נשארת כמות שהיא', () {
      final entries = [
        TocEntry(text: 'א', index: 0),
        TocEntry(text: 'ב', index: 1),
      ];
      expect(flattenToc(entries).length, 2);
    });

    test('זרימת openBookAtRef: flatten + התאמת ref מאתרת את הדף הנכון', () {
      // משחזר את הזרימה של reader.openBookAtRef על מבנה כמו ביומא:
      // ref התוסף "ס\"ד ע\"ב" צריך לאתר את הצאצא "דף סד:" עם ה-index שלו.
      final root = TocEntry(text: 'יומא', index: 0, level: 0);
      root.children.addAll([
        TocEntry(text: 'דף סד.', index: 248, level: 1, parent: root),
        TocEntry(text: 'דף סד:', index: 250, level: 1, parent: root),
      ]);

      final flat = flattenToc([root]);
      final entry = flat.firstWhere(
        (e) => tocTextMatchesRef(e.text, 'ס"ד ע"ב'),
      );

      expect(entry.text, 'דף סד:');
      expect(entry.index, 250);
    });

    test('ref שלא קיים ב-TOC אינו מתאים → openBookAtRef ייפול לחיפוש', () {
      final root = TocEntry(text: 'יומא', index: 0, level: 0);
      root.children.add(
        TocEntry(text: 'דף ב.', index: 0, level: 1, parent: root),
      );

      final flat = flattenToc([root]);
      final matches = flat
          .where((e) => tocTextMatchesRef(e.text, 'צ"ט ע"א'))
          .toList();

      // אין התאמה → refFound=false → ה-ref נשאר כ-searchText (fallback בלבד)
      expect(matches, isEmpty);
    });
  });
}
