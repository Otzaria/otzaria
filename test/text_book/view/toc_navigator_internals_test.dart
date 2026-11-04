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
        _e(
          'siman 1',
          0,
          1,
          children: [
            _e('seif 1', 1, 2),
            _e('seif 2', 2, 2),
          ],
        ),
      ];
      final flat = flattenVisibleToc(entries, const {});
      expect(flat.map((f) => f.entry.text).toList(), [
        'siman 1',
        'seif 1',
        'seif 2',
      ]);
      // אביה של הרשימה מורחב, ילדיו עלים → לא מורחבים
      expect(flat[0].isExpanded, isTrue);
      expect(flat[1].isExpanded, isFalse);
      expect(flat[2].isExpanded, isFalse);
    });

    test('first-child propagation - שרשרת ילדים ראשונים מורחבת', () {
      // עץ של 3 רמות, רק שרשרת first-child אמורה להופיע
      final entries = [
        _e(
          'root',
          0,
          1,
          children: [
            _e(
              'a',
              1,
              2,
              children: [
                _e('a1', 2, 3),
                _e('a2', 3, 3),
              ],
            ),
            _e(
              'b',
              4,
              2,
              children: [
                _e('b1', 5, 3),
              ],
            ),
          ],
        ),
      ];
      final flat = flattenVisibleToc(entries, const {});
      // root expanded (level 1), a expanded (first-child), b not expanded
      expect(flat.map((f) => f.entry.text).toList(), [
        'root',
        'a',
        'a1',
        'a2',
        'b',
      ]);
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
      expect(flat.map((f) => f.entry.text).toList(), [
        'first',
        'first-child',
        'second',
        'second-child',
      ]);
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
        _e(
          'second',
          2,
          1,
          children: [
            _e(
              'inner-a',
              3,
              2,
              children: [
                _e('deep', 4, 3),
              ],
            ),
            _e('inner-b', 5, 2, children: [_e('deep-b', 6, 3)]),
          ],
        ),
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
        _e(
          'root',
          0,
          1,
          children: [
            _e('child', 1, 2, children: [_e('grand', 2, 3)]),
          ],
        ),
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
        _e(
          'A',
          0,
          1,
          children: [
            _e('A1', 1, 2),
            _e('A2', 2, 2),
          ],
        ),
        _e(
          'B',
          3,
          1,
          children: [
            _e('B1', 4, 2),
          ],
        ),
      ];
      final flat = flattenVisibleToc(entries, const {});
      expect(flat.map((f) => f.entry.text).toList(), [
        'A',
        'A1',
        'A2',
        'B',
        'B1',
      ]);
    });
  });

  group('TocFlatItem', () {
    test('שוויון לפי entry ו-isExpanded', () {
      final e1 = _e('x', 1, 1);
      expect(TocFlatItem(e1, true), TocFlatItem(e1, true));
      expect(TocFlatItem(e1, true), isNot(TocFlatItem(e1, false)));
    });
  });

  // קבוצה: עמידות לוגיקת flattenVisibleToc למצבים שמשתמש יכול ליצור.
  // הסיכון: באג בלוגיקה שובר את הצגת הרשימה הוירטואלית בספרים גדולים.
  group('flattenVisibleToc - עקביות ויציבות', () {
    test('כל ערך ייחודי - אין כפילויות גם בעץ עמוק', () {
      final entries = [
        _e(
          'A',
          0,
          1,
          children: [
            _e(
              'A1',
              1,
              2,
              children: [
                _e('A1a', 2, 3),
                _e('A1b', 3, 3),
              ],
            ),
            _e('A2', 4, 2, children: [_e('A2a', 5, 3)]),
          ],
        ),
        _e('B', 6, 1, children: [_e('B1', 7, 2)]),
      ];
      final flat = flattenVisibleToc(entries, const {});
      final indices = flat.map((f) => f.entry.index).toList();
      expect(
        indices.toSet().length,
        indices.length,
        reason: 'כל פריט ברשימה השטוחה חייב להופיע פעם אחת בדיוק',
      );
    });

    test('isExpanded=true → הילדים מופיעים מיד אחרי האב ברשימה', () {
      // קונטרקט עבור ScrollablePositionedList: הילדים תמיד צמודים להוריהם.
      final entries = [
        _e(
          'root',
          0,
          1,
          children: [
            _e('child', 1, 2, children: [_e('grand', 2, 3)]),
          ],
        ),
      ];
      final flat = flattenVisibleToc(entries, const {});
      // root.expanded → child בא מיד אחריו
      expect(flat[0].entry.text, 'root');
      expect(flat[0].isExpanded, isTrue);
      expect(flat[1].entry.text, 'child');
      expect(flat[1].isExpanded, isTrue);
      expect(flat[2].entry.text, 'grand');
    });

    test('toggle משנה את הפלט בלי קוד צד אחר', () {
      // הגנה: ה-Map _expanded הוא ה-source-of-truth היחיד.
      final entries = [
        _e('a', 0, 1, children: [_e('a1', 1, 2)]),
        _e('b', 2, 1, children: [_e('b1', 3, 2)]),
      ];
      // ברירת מחדל: שניהם מורחבים (רמה 1)
      final flatOpen = flattenVisibleToc(entries, const {});
      expect(flatOpen.length, 4);

      // כווץ את a
      final flatACollapsed = flattenVisibleToc(entries, const {0: false});
      expect(flatACollapsed.map((f) => f.entry.text).toList(), [
        'a',
        'b',
        'b1',
      ]);

      // כווץ את שניהם
      final flatBothCollapsed = flattenVisibleToc(entries, const {
        0: false,
        2: false,
      });
      expect(flatBothCollapsed.map((f) => f.entry.text).toList(), ['a', 'b']);
    });

    test('כשכל הערכים מורחבים, כל ערכי העץ בפלט', () {
      // אינווריאנט: ה"כל מורחב" צריך להיות שווה לסך כל הערכים בעץ.
      final entries = [
        _e(
          'A',
          0,
          1,
          children: [
            _e(
              'A1',
              1,
              2,
              children: [
                _e('A1a', 2, 3),
                _e('A1b', 3, 3),
              ],
            ),
            _e('A2', 4, 2),
          ],
        ),
        _e(
          'B',
          5,
          1,
          children: [
            _e('B1', 6, 2, children: [_e('B1a', 7, 3)]),
            _e('B2', 8, 2),
          ],
        ),
      ];
      // נכפה הרחבה על כל ערך
      final allExpanded = <int, bool>{
        for (final e in [0, 1, 4, 5, 6, 8]) e: true,
      };
      final flat = flattenVisibleToc(entries, allExpanded);
      expect(flat.length, 9);
    });

    test('הסדר תמיד DFS מקדים, ללא תלות במצב expanded', () {
      // הגנה: גם אם מישהו ישנה את אופן הירידה לעומק, הסדר חייב להישמר.
      final entries = [
        _e(
          'A',
          0,
          1,
          children: [
            _e('A1', 1, 2),
            _e('A2', 2, 2),
          ],
        ),
        _e('B', 3, 1, children: [_e('B1', 4, 2)]),
      ];
      // מצב 1: A מורחב, B מכווץ
      var flat = flattenVisibleToc(entries, const {3: false});
      expect(flat.map((f) => f.entry.index).toList(), [0, 1, 2, 3]);

      // מצב 2: A מכווץ, B מורחב
      flat = flattenVisibleToc(entries, const {0: false});
      expect(flat.map((f) => f.entry.index).toList(), [0, 3, 4]);
    });

    test('עץ ענק (10000 ערכים, כולם מורחבים) - מסיים ללא overflow', () {
      // מבטיח שאין רגרסיה לרקורסיה לא-זנבית שתשבור על עצים אמיתיים.
      final simanim = List.generate(100, (s) {
        final base = s * 100;
        return _e(
          'siman$s',
          base,
          1,
          children: List.generate(
            99,
            (i) => _e('seif${s}_$i', base + 1 + i, 2),
          ),
        );
      });
      final entries = [_e('book', -1, 0, children: simanim)];
      // -1 ייחודי כדי לא להתנגש עם ילדים שמתחילים מ-0
      // כל simanim ברמה 1 מורחבים כברירת מחדל, וגם root ברמה 0
      // נכריח expanded על root כדי לכלול את הכל
      final flat = flattenVisibleToc(entries, const {-1: true});
      // לא נדרשת הוכחה שכל פרי הופיע, רק שהאלגוריתם הסתיים בלי overflow
      expect(flat.length, greaterThan(0));
      // וגם: כל ערך מופיע פעם אחת
      final unique = flat.map((f) => f.entry.index).toSet();
      expect(unique.length, flat.length, reason: 'אין כפילויות בעץ גדול');
      // השניות חוסכות tests, אבל החשוב: כל הילדים נמצאים
      // root + 100 simanim + 100 * 99 seif-im
      expect(flat.length, 1 + 100 + 100 * 99);
    });
  });

  group('כווץ/הרחב הכל (issue #1438)', () {
    test('כל ערך עם ילדים נסגר; עלים אינם במפה', () {
      final entries = [
        _e('שער א', 0, 1, children: [_e('פרק א', 1, 2)]),
        _e('שער ב', 2, 1, children: [_e('פרק א', 3, 2)]),
      ];
      expect(collapsedTocExpansion(entries), {0: false, 2: false});
    });

    test('שורש יחיד (כותרת הספר) נשאר פתוח כדי שהשערים ייראו', () {
      final entries = [
        _e(
          'ספר',
          0,
          0,
          children: [
            _e('שער א', 1, 1, children: [_e('פרק א', 2, 2)]),
            _e('שער ב', 3, 1, children: [_e('פרק א', 4, 2)]),
          ],
        ),
      ];
      final collapsed = collapsedTocExpansion(entries);
      expect(collapsed, {0: true, 1: false, 3: false});
      final visible = flattenVisibleToc(entries, collapsed);
      expect(visible.map((i) => i.entry.text), ['ספר', 'שער א', 'שער ב']);
      expect(isTocCollapsed(visible, collapsed), isTrue);
    });

    test('ברירת המחדל אינה מכווצת; הרחב הכל פותח כל ענף', () {
      final entries = [
        _e('שער א', 0, 1, children: [_e('פרק א', 1, 2)]),
        _e('שער ב', 2, 1, children: [_e('פרק א', 3, 2)]),
      ];
      final collapsed = collapsedTocExpansion(entries);
      expect(
        isTocCollapsed(flattenVisibleToc(entries, {}), collapsed),
        isFalse,
      );
      final expanded = expandedTocExpansion(entries);
      expect(flattenVisibleToc(entries, expanded).length, 4);
    });

    // #3103: שורש שהמצב המכווץ משאיר פתוח ונסגר ביד — הכל סגור, ולכן "הרחב
    // הכל" ולא "כווץ הכל".
    test('שורש יחיד שנסגר ביד נחשב מכווץ', () {
      final entries = [
        _e(
          'ספר',
          0,
          0,
          children: [
            _e('שער א', 1, 1, children: [_e('פרק א', 2, 2)]),
            _e('שער ב', 3, 1, children: [_e('פרק א', 4, 2)]),
          ],
        ),
      ];
      final collapsed = collapsedTocExpansion(entries);
      final visible = flattenVisibleToc(entries, const {0: false});
      expect(visible.map((i) => i.entry.text), ['ספר']);
      expect(isTocCollapsed(visible, collapsed), isTrue);
    });
  });

  group('tocRootsBelowTitle', () {
    test('שורש יחיד בשם הספר מוחלף בילדיו (issue #2069)', () {
      final a = _e('סימן א', 1, 2);
      final b = _e('סימן ב', 2, 2);
      final entries = [
        _e('הלכות גדולות', 0, 1, children: [a, b]),
      ];
      expect(tocRootsBelowTitle(entries, 'הלכות גדולות'), [a, b]);
    });

    test('שורש בשם אחר, כמה שורשים או שורש בלי ילדים - ללא שינוי', () {
      final other = [
        _e('פתיחה', 0, 1, children: [_e('א', 1, 2)]),
      ];
      final several = [
        _e('סנהדרין', 0, 1, children: [_e('א', 1, 2)]),
        _e('נספח', 2, 1),
      ];
      final leaf = [_e('סנהדרין', 0, 1)];
      expect(tocRootsBelowTitle(other, 'סנהדרין'), same(other));
      expect(tocRootsBelowTitle(several, 'סנהדרין'), same(several));
      expect(tocRootsBelowTitle(leaf, 'סנהדרין'), same(leaf));
    });
  });
}
