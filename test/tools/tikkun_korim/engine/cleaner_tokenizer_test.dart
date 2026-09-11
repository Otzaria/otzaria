/// מקרי קצה של ניקוי הטקסט והפירוק לאסימונים — מחרוזות קצרות שנבנות במקום.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

final _kqStart = String.fromCharCode(kKetivQereStart);
final _kqSep = String.fromCharCode(kKetivQereSep);
final _kqEnd = String.fromCharCode(kKetivQereEnd);

void main() {
  group('cleanRawText', () {
    test('כותרת פרק בגימטריה עם גרשיים ופסוקים הופכים לסמנים', () {
      final out = cleanRawText('<h1>ספר</h1><h2>פרק י"א</h2>(א) שלום (ב) עולם');
      expect(out, 'CHAPTERMARK11MARK VERSEMARK1MARK שלום VERSEMARK2MARK עולם');
    });

    test('כתיב וקרי בשני הסדרים', () {
      const k = 'שלום';
      const q = 'עולם';
      final a = cleanRawText(
        '<span class="mam-kq-k">($k)</span> <span class="mam-kq-q">[$q]</span>',
      );
      final b = cleanRawText(
        '<span class="mam-kq-q">[$q]</span> <span class="mam-kq-k">($k)</span>',
      );
      expect(a, '$_kqStart$k$_kqSep$q$_kqEnd');
      expect(b, a);
    });

    test('כתיב בלבד וקרי בלבד שומרים את הסמנים עם צד ריק', () {
      expect(
        cleanRawText('<span class="mam-kq-k">(שלום)</span>'),
        '$_kqStartשלום$_kqSep$_kqEnd',
      );
      expect(
        cleanRawText('<span class="mam-kq-q">[עולם]</span>'),
        '$_kqStart$_kqSepעולם$_kqEnd',
      );
    });

    test('big/small עבריים מסומנים כרבתי/זעירא, לועזיים לא', () {
      final out = cleanRawText('<big>ב</big>שלום <small>x</small>');
      expect(out.codeUnitAt(0), kRabatiStart);
      expect(out.codeUnitAt(2), kRabatiEnd);
      expect(out.endsWith('שלום x'), isTrue);
    });

    test('קמץ קטן מנורמל לקמץ', () {
      expect(cleanRawText('כׇל'), 'כָל');
    });

    test('ארבעה רווחים קשיחים הופכים לסמן הפסק', () {
      final out = cleanRawText('שלום    עולם');
      expect(out, 'שלום SEGBREAKMARK עולם');
    });

    test('סימוני פרשיות נשמרים ומקף עברי הופך לרווח', () {
      expect(cleanRawText('שלום {פ} על־עולם'), 'שלום {פ} על עולם');
    });
  });

  group('tokenizeText', () {
    test('סמנים הופכים לאסימונים מבניים', () {
      final tokens = tokenizeText(
        'CHAPTERMARK3MARK VERSEMARK2MARK שלום {פ} עולם {ס} SEGBREAKMARK',
      );
      expect(tokens.map((t) => t.type), [
        TikkunTokenType.chapterBreak,
        TikkunTokenType.verseBreak,
        TikkunTokenType.word,
        TikkunTokenType.petucha,
        TikkunTokenType.word,
        TikkunTokenType.setuma,
        TikkunTokenType.segmentBreak,
      ]);
      expect(tokens[0].chapterNum, 3);
      expect(tokens[1].verseNum, 2);
    });

    test('סימוני זעירא אינם נספרים באורך הגלוי', () {
      final word =
          'ש${String.fromCharCode(kZeiraStart)}ל'
          '${String.fromCharCode(kZeiraEnd)}ום';
      expect(visibleStamLen(word), 4);
    });
  });

  test('maskDivineName שומר ניקוד וטעמים', () {
    final masked = maskDivineName('יְהֹוָ֖ה');
    expect(masked, 'יְקֹוָ֖ק');
    expect(maskDivineName('שלום'), 'שלום');
  });
}
