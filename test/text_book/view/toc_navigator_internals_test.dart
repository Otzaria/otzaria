import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/view/toc_navigator_internals.dart';

/// בונה ערך TOC עם ילדים אופציונליים. עוזר קצר לבדיקות.
TocEntry _e(String text, int index, int level, {List<TocEntry>? children}) {
  final entry = TocEntry(text: text, index: index, level: level);
  if (children != null) {
    for (final c in children) {
      entry.children.add(c);
    }
  }
  return entry;
}

void main() {
  group('countAllTocEntries', () {
    test('רשימה ריקה - 0', () {
      expect(countAllTocEntries(const []), 0);
    });

    test('רמה אחת בלבד', () {
      final entries = [
        _e('א', 0, 1),
        _e('ב', 1, 1),
        _e('ג', 2, 1),
      ];
      expect(countAllTocEntries(entries), 3);
    });

    test('עץ מקונן רקורסיבי', () {
      final entries = [
        _e('root', 0, 1, children: [
          _e('a', 1, 2, children: [
            _e('a1', 2, 3),
            _e('a2', 3, 3),
          ]),
          _e('b', 4, 2),
        ]),
      ];
      // 1 + 2 + 2 + 0 = 5? Let me recount: root + a + a1 + a2 + b = 5
      expect(countAllTocEntries(entries), 5);
    });

    test('סופר את כל הרמות, גם עמוקות', () {
      // עץ עם 1 אב + 100 ילדים
      final children =
          List.generate(100, (i) => _e('c$i', i + 1, 2));
      final entries = [_e('root', 0, 1, children: children)];
      expect(countAllTocEntries(entries), 101);
    });
  });

  group('flattenVisibleToc - ברירת מחדל (מפת expanded ריקה)', () {
    test('עלים בלבד מוחזרים עם isExpanded=false', () {
      final entries = [
        _e('a', 0, 1),
        _e('b', 1, 1),
      ];
      final flat = flattenVisibleToc(entries, const {});
      expect(flat.length, 2);
      expect(flat[0].entry.text, 'a');
      expect(flat[0].isExpanded, isFalse);
      expect(flat[1].entry.text, 'b');
      expect(flat[1].isExpanded, isFalse);
    });

    test('ערך רמה 1 עם ילדים - מורחב כברירת מחדל וילדיו מופיעים', () {
      final entries = [
        _e('siman 1', 0, 1, children: [
          _e('seif 1', 1, 2),
          _e('seif 2', 2, 2),
        ]),
      ];
      final flat = flattenVisibleToc(entries, const {});
      expect(flat.map((f) => f.entry.text).toList(),
          ['siman 1', 'seif 1', 'seif 2']);
      // אביה של הרשימה מורחב, ילדיו עלים → לא מורחבים
      expect(flat[0].isExpanded, isTrue);
      expect(flat[1].isExpanded, isFalse);
      expect(flat[2].isExpanded, isFalse);
    });

    test('first-child propagation - שרשרת ילדים ראשונים מורחבת', () {
      // עץ של 3 רמות, רק שרשרת first-child אמורה להופיע
      final entries = [
        _e('root', 0, 1, children: [
          _e('a', 1, 2, children: [
            _e('a1', 2, 3),
            _e('a2', 3, 3),
          ]),
          _e('b', 4, 2, children: [
            _e('b1', 5, 3),
          ]),
        ]),
      ];
      final flat = flattenVisibleToc(entries, const {});
      // root expanded (level 1), a expanded (first-child), b not expanded
      expect(flat.map((f) => f.entry.text).toList(),
          ['root', 'a', 'a1', 'a2', 'b']);
      // b לא מורחב → b1 לא בפלט
      expect(flat.any((f) => f.entry.text == 'b1'), isFalse);
    });

    test('ילד שני של רמה 1 לא מורחב מעצמו (לא רמה 1, לא first-child)', () {
      final entries = [
        _e('first', 0, 1, children: [_e('first-child', 1, 2)]),
        _e('second', 2, 1, children: [_e('second-child', 3, 2)]),
      ];
      final flat = flattenVisibleToc(entries, const {});
      // שני הראשונים ברמה 1 - שניהם מורחבים (level == 1)
      expect(flat.map((f) => f.entry.text).toList(),
          ['first', 'first-child', 'second', 'second-child']);
    });
  });

  group('flattenVisibleToc - מפת expanded מהמשתמש', () {
    test('expanded=false עוקף את ברירת המחדל של רמה 1', () {
      final entries = [
        _e('siman', 0, 1, children: [_e('seif', 1, 2)]),
      ];
      final flat = flattenVisibleToc(entries, const {0: false});
      // siman קיים אבל לא מורחב, seif לא מופיע
      expect(flat.length, 1);
      expect(flat[0].entry.text, 'siman');
      expect(flat[0].isExpanded, isFalse);
    });

    test('expanded=true פותח ערך שברירת המחדל שלו מכווצת', () {
      final entries = [
        _e('first', 0, 1, children: [_e('fc', 1, 2)]),
        // second-level שני: ברירת מחדל לא מורחב (לא רמה 1, לא first-child)
        _e('second', 2, 1, children: [
          _e('inner-a', 3, 2, children: [
            _e('deep', 4, 3),
          ]),
          _e('inner-b', 5, 2, children: [_e('deep-b', 6, 3)]),
        ]),
      ];
      // ברירת מחדל: inner-b לא מורחב כי אינו first-child וגם לא ברמה 1
      // נכפה אותו פתוח דרך expanded
      final flat = flattenVisibleToc(entries, const {5: true});
      final texts = flat.map((f) => f.entry.text).toList();
      expect(texts.contains('inner-b'), isTrue);
      // עכשיו deep-b אמור להופיע (כי inner-b מורחב במפורש)
      expect(texts.contains('deep-b'), isTrue);
    });

    test('isExpanded בפלט משקף את המצב בפועל', () {
      final entries = [
        _e('root', 0, 1, children: [
          _e('child', 1, 2, children: [_e('grand', 2, 3)]),
        ]),
      ];
      // root מורחב כברירת מחדל (level 1), child מורחב כ-first-child
      final flat = flattenVisibleToc(entries, const {});
      final byText = {for (final f in flat) f.entry.text: f.isExpanded};
      expect(byText['root'], isTrue);
      expect(byText['child'], isTrue);
      expect(byText['grand'], isFalse); // עלה
    });
  });

  group('flattenVisibleToc - שמירת סדר וקפיצות לרמות', () {
    test('הסדר תואם DFS מקדים (כותרת לפני ילדיה)', () {
      final entries = [
        _e('A', 0, 1, children: [
          _e('A1', 1, 2),
          _e('A2', 2, 2),
        ]),
        _e('B', 3, 1, children: [
          _e('B1', 4, 2),
        ]),
      ];
      final flat = flattenVisibleToc(entries, const {});
      expect(flat.map((f) => f.entry.text).toList(),
          ['A', 'A1', 'A2', 'B', 'B1']);
    });
  });

  group('TocFlatItem', () {
    test('שוויון לפי entry ו-isExpanded', () {
      final e1 = _e('x', 1, 1);
      expect(TocFlatItem(e1, true), TocFlatItem(e1, true));
      expect(TocFlatItem(e1, true), isNot(TocFlatItem(e1, false)));
    });
  });

  // טסטים אינטגרטיביים על השפעת הסף - מוודאים שהלוגיקה הטהורה תומכת
  // בהחלטה "האם להפעיל וירטואליזציה" שבמסך עצמו.
  group('סף וירטואליזציה (countAllTocEntries מול ספרים אמיתיים)', () {
    test('ספר עם 700 ערכי רמה 1 בלבד - מעל סף 500', () {
      final entries = List.generate(700, (i) => _e('siman $i', i, 1));
      expect(countAllTocEntries(entries), 700);
      expect(countAllTocEntries(entries) > 500, isTrue);
    });

    test('ספר עם 1 רמה 1 ו-300 ילדים - מתחת לסף 500', () {
      final children = List.generate(300, (i) => _e('c$i', i + 1, 2));
      final entries = [_e('root', 0, 1, children: children)];
      expect(countAllTocEntries(entries), 301);
      expect(countAllTocEntries(entries) > 500, isFalse);
    });

    test('מבנה עמוק כמו כף החיים: 1 + 134 + 8420 - מעל הסף', () {
      // מדמה את המבנה האמיתי של "כף החיים על שו"ע יורה דעה"
      // 134 simanim, כל אחד ~63 se'ifim
      final simanim = List.generate(134, (s) {
        final seifim = List.generate(63, (sf) => _e('seif $sf', s * 100 + sf, 2));
        return _e('siman $s', s * 100, 1, children: seifim);
      });
      final entries = [_e('book', 0, 1, children: simanim)];
      final count = countAllTocEntries(entries);
      expect(count, greaterThan(500));
      expect(count, 1 + 134 + 134 * 63);
    });
  });
}
