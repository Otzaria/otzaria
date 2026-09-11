/// אימות אינדקס העליות מול מבנה החומשים: רציפות הטווחים, כיסוי הפרשה
/// מתחילתה ועד סופה, שבע עליות ומפטיר, וזהות הפרשות המחוברות.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

/// הפסוק האחרון בכל חומש לפי המסורה.
const Map<String, (int, int)> _lastVerse = {
  'bereshit': (50, 26),
  'shemot': (40, 38),
  'vayikra': (27, 34),
  'bamidbar': (36, 13),
  'devarim': (34, 12),
};

List<ParashaAliya> _aliyot(String bookName, String parasha) {
  final byBook = TikkunData.aliyotIndex[bookName]!;
  return byBook[parasha] ??
      byBook[TikkunData.normalizeParashaName(parasha)] ??
      const [];
}

/// האם [b] הוא הפסוק שאחרי [a] — או באותו פרק, או ראש הפרק הבא.
bool _isNext((int, int) a, (int, int) b) =>
    (b.$1 == a.$1 && b.$2 == a.$2 + 1) || (b.$1 == a.$1 + 1 && b.$2 == 1);

void main() {
  group('אינדקס העליות', () {
    test('לכל 61 הפרשות שבע עליות, ולכולן פרט לוזאת הברכה גם מפטיר', () {
      var count = 0;
      for (final bookId in TikkunData.booksOrder) {
        final bookName = TikkunData.torahBooks[bookId]!.name;
        for (final entry in TikkunData.aliyotIndex[bookName]!.entries) {
          count++;
          final names = entry.value.map((a) => a.aliya).toList();
          final expected = [
            'עליה א',
            'עליה ב',
            'עליה ג',
            'עליה ד',
            'עליה ה',
            'עליה ו',
            'עליה ז',
            if (entry.key != 'וזאת הברכה') 'מפטיר',
          ];
          expect(
            names.map(escapeNonAscii),
            expected.map(escapeNonAscii),
            reason: escapeNonAscii(entry.key),
          );
        }
      }
      expect(count, 61);
    });

    test('שבע העליות רצופות, והמפטיר מסתיים בסוף העליה השביעית', () {
      for (final bookId in TikkunData.booksOrder) {
        final bookName = TikkunData.torahBooks[bookId]!.name;
        for (final entry in TikkunData.aliyotIndex[bookName]!.entries) {
          final list = entry.value;
          final reason = escapeNonAscii(entry.key);
          for (var i = 1; i < 7; i++) {
            expect(
              _isNext(
                (list[i - 1].toCh, list[i - 1].toVs),
                (list[i].fromCh, list[i].fromVs),
              ),
              isTrue,
              reason: '$reason — עליה ${i + 1}',
            );
          }
          if (list.length == 8) {
            final maftir = list[7];
            expect(
              (maftir.toCh, maftir.toVs),
              (list[6].toCh, list[6].toVs),
              reason: '$reason — סוף המפטיר',
            );
            // המפטיר חוזר על סוף העליה השביעית, ולכן מתחיל בתוכה.
            expect(
              maftir.fromCh > list[6].fromCh ||
                  (maftir.fromCh == list[6].fromCh &&
                      maftir.fromVs >= list[6].fromVs),
              isTrue,
              reason: '$reason — תחילת המפטיר',
            );
          }
        }
      }
    });

    test('הפרשות מכסות את החומש ברצף, מפסוק א,א ועד סופו', () {
      for (final bookId in TikkunData.booksOrder) {
        final book = TikkunData.torahBooks[bookId]!;
        (int, int)? prevEnd;
        for (final parasha in book.parashot) {
          final list = _aliyot(book.name, parasha);
          expect(list, isNotEmpty, reason: escapeNonAscii(parasha));
          final start = (list.first.fromCh, list.first.fromVs);
          if (prevEnd == null) {
            expect(start, (1, 1), reason: escapeNonAscii(parasha));
          } else {
            expect(
              _isNext(prevEnd, start),
              isTrue,
              reason: escapeNonAscii(parasha),
            );
          }
          prevEnd = (list[6].toCh, list[6].toVs);
        }
        expect(prevEnd, _lastVerse[bookId], reason: bookId);
      }
    });

    test('פרשה מחוברת מתחילה בראשונה ומסתיימת בשנייה', () {
      for (final bookId in TikkunData.booksOrder) {
        final bookName = TikkunData.torahBooks[bookId]!.name;
        final byBook = TikkunData.aliyotIndex[bookName]!;
        for (final name in byBook.keys.where((k) => k.contains('-'))) {
          final parts = name.split('-');
          final combined = byBook[name]!;
          final first = _aliyot(bookName, parts[0]);
          final second = _aliyot(bookName, parts[1]);
          expect(
            (combined.first.fromCh, combined.first.fromVs),
            (first.first.fromCh, first.first.fromVs),
            reason: escapeNonAscii(name),
          );
          expect(
            (combined[6].toCh, combined[6].toVs),
            (second[6].toCh, second[6].toVs),
            reason: escapeNonAscii(name),
          );
        }
      }
    });

    test('קריאת שני וחמישי — שלוש עליות רצופות מתחילת הפרשה', () {
      for (final bookId in TikkunData.booksOrder) {
        final book = TikkunData.torahBooks[bookId]!;
        for (final parasha in book.parashot) {
          final weekday =
              TikkunData.weekdayAliyotIndex[book.name]![parasha] ??
              TikkunData.weekdayAliyotIndex[book
                  .name]![TikkunData.normalizeParashaName(parasha)];
          final reason = escapeNonAscii(parasha);
          expect(weekday, isNotNull, reason: reason);
          expect(weekday!.length, 3, reason: reason);
          final full = _aliyot(book.name, parasha);
          expect(
            (weekday.first.fromCh, weekday.first.fromVs),
            (full.first.fromCh, full.first.fromVs),
            reason: reason,
          );
          for (var i = 1; i < 3; i++) {
            expect(
              _isNext(
                (weekday[i - 1].toCh, weekday[i - 1].toVs),
                (weekday[i].fromCh, weekday[i].fromVs),
              ),
              isTrue,
              reason: '$reason — עליה ${i + 1}',
            );
          }
        }
      }
    });
  });
}
