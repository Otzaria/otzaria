/// סימון העליות לפי טווחי פסוקים: כל עליה נופלת על הפסוק שבנתונים, גם
/// כשמילות הפתיחה שלה חוזרות בטקסט, והמפטיר מסומן גם כשהוא בתוך עליה ז'.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

const StamWidthModel _widths = StamWidthModel.uniform();

/// טקסט סינתטי בפורמט שהמנקה מצפה לו: כותרת פרק ומספרי פסוקים בגימטריה.
String _fakeBook(List<(int, List<String>)> chapters) {
  const letters = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט', 'י'];
  final buf = StringBuffer();
  for (final (ch, verses) in chapters) {
    buf.write('<h2>פרק ${letters[ch]}</h2>');
    for (var v = 0; v < verses.length; v++) {
      buf.write(' (${letters[v + 1]}) ${verses[v]}');
    }
  }
  return buf.toString();
}

void main() {
  group('אינדקס הפסוקים של החומש', () {
    test('פסוק שמילותיו חוזרות מאותר לפי מיקומו ולא לפי ההתאמה הראשונה', () {
      const repeated = 'וידבר יהוה אל משה לאמר';
      final tokens = tokenizeBook(
        _fakeBook([
          (1, ['$repeated ראשון', '$repeated שני']),
          (2, ['$repeated שלישי']),
        ]),
        'בראשית',
      );
      final index = BookVerseIndex(tokens, 0, tokens.length);

      String wordAfter(int ch, int vs) {
        final idx = index.wordIdx(ch, vs);
        expect(idx, greaterThan(-1), reason: '$ch:$vs');
        return tokens[idx + 5].value!;
      }

      expect(escapeNonAscii(wordAfter(1, 1)), escapeNonAscii('ראשון'));
      expect(escapeNonAscii(wordAfter(1, 2)), escapeNonAscii('שני'));
      expect(escapeNonAscii(wordAfter(2, 1)), escapeNonAscii('שלישי'));
    });
  });

  group('סימון העליות על התורה', () {
    late ProcessedTorah torah;
    late Map<String, (int, int)> bookRanges;

    setUpAll(() {
      final raw = {
        for (final id in TikkunData.booksOrder) id: readFixture(id),
      };
      torah = processTorah(raw, _widths);
      bookRanges = bookTokenRanges(torah.tokens, torah.bookStartTokenIdx);
    });

    /// שם העליה שסומן על השורה שמכילה את הפסוק [ch]:[vs] בחומש [bookId].
    String? aliyaAt(String bookId, int ch, int vs) {
      final range = bookRanges[bookId]!;
      final idx = BookVerseIndex(
        torah.tokens,
        range.$1,
        range.$2,
      ).wordIdx(ch, vs);
      expect(idx, greaterThan(-1), reason: '$bookId $ch:$vs');
      final lineIdx = LineIndexLookup(torah.allLines).find(idx);
      return torah.allLines[lineIdx].aliyaName;
    }

    test('כל עליה מסומנת על שורת פסוק הפתיחה שבנתונים', () {
      for (final bookId in TikkunData.booksOrder) {
        final book = TikkunData.torahBooks[bookId]!;
        for (final parasha in book.parashot) {
          final aliyot =
              TikkunData.aliyotIndex[book.name]![parasha] ??
              TikkunData.aliyotIndex[book
                  .name]![TikkunData.normalizeParashaName(parasha)]!;
          for (final a in aliyot) {
            // המפטיר נופל בתוך עליה ז'; שורתו כבר נושאת את שם עליה ז'.
            if (a.aliya == 'מפטיר') continue;
            expect(
              escapeNonAscii(aliyaAt(bookId, a.fromCh, a.fromVs)),
              escapeNonAscii(TikkunData.aliyaDisplayNames[a.aliya]),
              reason: '${escapeNonAscii(parasha)} ${escapeNonAscii(a.aliya)}',
            );
          }
        }
      }
    });

    test('העליות שמילות הפתיחה שלהן חוזרות — במקום הנכון', () {
      // אמור, קרח, נשא, צו ומסעי: "וידבר ה' אל משה לאמר" חוזר בהן.
      const cases = [
        ('vayikra', 8, 1, 'רביעי'), // צו ד
        ('vayikra', 22, 17, 'שלישי'), // אמור ג
        ('vayikra', 23, 1, 'רביעי'), // אמור ד
        ('vayikra', 23, 23, 'חמישי'), // אמור ה
        ('vayikra', 23, 33, 'ששי'), // אמור ו
        ('vayikra', 24, 1, 'שביעי'), // אמור ז
        ('bamidbar', 5, 11, 'רביעי'), // נשא ד
        ('bamidbar', 17, 9, 'רביעי'), // קרח ד
        ('bamidbar', 17, 16, 'חמישי'), // קרח ה
        ('bamidbar', 34, 16, 'רביעי'), // מסעי ד
      ];
      for (final (bookId, ch, vs, label) in cases) {
        expect(
          escapeNonAscii(aliyaAt(bookId, ch, vs)),
          escapeNonAscii(label),
          reason: '$bookId $ch:$vs',
        );
      }
    });

    test('המפטיר מסומן בכל 53 הפרשות, גם כשהוא בתוך עליה ז', () {
      // בעקב ובנצבים המפטיר מתחיל באותו פסוק כמו עליה ז'; בוזאת הברכה אין.
      final marked = torah.allLines.where((l) => l.maftirName != null).length;
      expect(marked, 53);
      for (final (ch, vs) in const [(11, 22), (30, 15)]) {
        final range = bookRanges['devarim']!;
        final idx = BookVerseIndex(
          torah.tokens,
          range.$1,
          range.$2,
        ).wordIdx(ch, vs);
        final lineIdx = LineIndexLookup(torah.allLines).find(idx);
        expect(
          escapeNonAscii(torah.allLines[lineIdx].maftirName),
          escapeNonAscii('מפטיר'),
          reason: 'devarim $ch:$vs',
        );
      }
    });

    test('הפסקות שני וחמישי מסומנות בכל 54 הפרשות', () {
      final marked = torah.allLines
          .where((l) => l.weekdayAliyaName != null)
          .length;
      expect(marked, 54 * 3);
    });
  });

  group('סימון ספר תורה נוסף בקריאות המועדים', () {
    late Map<String, List<TikkunToken>> tokensByBook;

    setUpAll(() {
      tokensByBook = {
        for (final id in fixtureBookNames.keys)
          fixtureBookNames[id]!: tokenizeBook(
            readFixture(id),
            fixtureBookNames[id]!,
          ),
      };
    });

    List<TikkunLine> linesOf(String id) => buildTorahReadingLines(
      TikkunData.torahReadings.firstWhere((r) => r.id == id),
      tokensByBook,
      _widths,
    );

    test('מפטיר מחומש אחר מסומן כספר תורה שני', () {
      final lines = linesOf('tr:Shabbat Shekalim (on Rosh Chodesh)');
      final labels = [
        for (final l in lines)
          if (l.torahScrollLabel != null) l.torahScrollLabel!,
      ];
      expect(
        labels.map(escapeNonAscii),
        [escapeNonAscii('ספר תורה שני')],
      );
      expect(
        lines.where((l) => l.maftirName != null).length,
        1,
        reason: 'המפטיר מסומן בשדה נפרד',
      );
    });

    test('דילוג פנימי באותו חומש אינו החלפת ספר', () {
      final lines = linesOf('tr:Fast Day (Morning)');
      expect(lines.every((l) => l.torahScrollLabel == null), isTrue);
    });
  });
}
