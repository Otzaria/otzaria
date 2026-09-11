/// פירוק הטקסט הנקי לאסימונים. פורט של `tokenizeText` ו-`visibleStamLen`
/// (page_layout_engine.js).
library;

import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// אורך גלוי של מילת סת"ם — תווי ה-PUA של זעירא/רבתי אינם נספרים.
int visibleStamLen(String stam) {
  var n = 0;
  for (var i = 0; i < stam.length; i++) {
    final code = stam.codeUnitAt(i);
    if (code < kZeiraStart || code > kRabatiEnd) n++;
  }
  return n;
}

/// כל סימני הניקוד והטעמים (U+0591–U+05C7). U+05C6 (נו"ן מנוזרת) אינו סימן
/// משולב אלא אות שנכתבת בספר עצמו, ולכן הוא נשמר.
final RegExp kNikudAndTeamim = RegExp('[֑-ׇׅ]');

/// נו"ן מנוזרת (הפוכה) — "ויהי בנסוע הארון" ומקבילותיה.
const String kNunHafukha = '׆';
const int kNunHafukhaCode = 0x05C6;

/// גופני הסת"ם והמנוקד חסרים גליף ל-U+05C6, ולכן היא מרונדרת כנו"ן רגילה
/// בהיפוך אופקי — וזו גם האות שנמדדת לרוחבה.
const String kNunHafukhaGlyph = 'נ';
const int kNunHafukhaGlyphCode = 0x05E0;

String stripNikud(String s) => s.replaceAll(kNikudAndTeamim, '');

final RegExp _newlines = RegExp(r'[\n\r]');
final RegExp _traditionMark = RegExp(r'\{([פס]):([a-z_]+)\}');
final RegExp _traditionToken = RegExp(r'^(PETUCHA|SETUMA)NOT([a-z_]+)$');
// cleanRawText כבר המיר סוגריים לסמן פסוק; רק הצורה המסולסלת מגיעה לכאן.
final RegExp _petuchaMark = RegExp(r'\{פ\}');
final RegExp _setumaMark = RegExp(r'\{ס\}');
final RegExp _bookBreakMark = RegExp('BOOKBREAKMARKER');
final RegExp _chapterMark = RegExp(r'CHAPTERMARK(\d+)MARK');
final RegExp _verseMarkTok = RegExp(r'VERSEMARK(\d+)MARK');
final RegExp _segBreakMark = RegExp('SEGBREAKMARK');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _chapterToken = RegExp(r'^CHAPTER(\d+)$');
final RegExp _verseToken = RegExp(r'^VERSE(\d+)$');

/// ממיר את הטקסט הנקי לרצף אסימונים.
List<TikkunToken> tokenizeText(String rawText) {
  final processed = rawText
      .replaceAll(_newlines, ' ')
      .replaceAllMapped(
        _traditionMark,
        (m) => ' ${m[1] == 'פ' ? 'PETUCHA' : 'SETUMA'}NOT${m[2]} ',
      )
      .replaceAll(_petuchaMark, ' PETUCHA ')
      .replaceAll(_setumaMark, ' SETUMA ')
      .replaceAll(_bookBreakMark, ' BOOKBREAK ')
      .replaceAllMapped(_chapterMark, (m) => ' CHAPTER${m[1]} ')
      .replaceAllMapped(_verseMarkTok, (m) => ' VERSE${m[1]} ')
      .replaceAll(_segBreakMark, ' SEGBREAK ')
      .replaceAll(_spaces, ' ')
      .trim();

  final tokens = <TikkunToken>[];
  for (final part in processed.split(' ')) {
    if (part.isEmpty) continue;
    switch (part) {
      case 'PETUCHA':
        tokens.add(const TikkunToken(type: TikkunTokenType.petucha));
      case 'SETUMA':
        tokens.add(const TikkunToken(type: TikkunTokenType.setuma));
      case 'BOOKBREAK':
        tokens.add(const TikkunToken(type: TikkunTokenType.bookBreak));
      case 'SEGBREAK':
        tokens.add(const TikkunToken(type: TikkunTokenType.segmentBreak));
      default:
        final trad = _traditionToken.firstMatch(part);
        if (trad != null) {
          tokens.add(
            TikkunToken(
              type: trad[1] == 'PETUCHA'
                  ? TikkunTokenType.petucha
                  : TikkunTokenType.setuma,
              excludedTradition: TikkunTradition.byId(trad[2]!),
            ),
          );
          continue;
        }
        final ch = _chapterToken.firstMatch(part);
        if (ch != null) {
          tokens.add(
            TikkunToken(
              type: TikkunTokenType.chapterBreak,
              chapterNum: int.parse(ch[1]!),
            ),
          );
          continue;
        }
        final vs = _verseToken.firstMatch(part);
        if (vs != null) {
          tokens.add(
            TikkunToken(
              type: TikkunTokenType.verseBreak,
              verseNum: int.parse(vs[1]!),
            ),
          );
          continue;
        }
        tokens.add(TikkunToken.word(part));
    }
  }
  return tokens;
}

/// מסיר את סמני הפרשה שאינם קיימים בספרי [tradition]. חייב לרוץ לפני
/// העימוד — סמן פרשה קובע את שבירת השורות שאחריו.
List<TikkunToken> filterByTradition(
  List<TikkunToken> tokens,
  TikkunTradition tradition,
) => [
  for (final tok in tokens)
    if (tok.excludedTradition != tradition) tok,
];
