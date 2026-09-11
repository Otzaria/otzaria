/// שירת האזינו — שבעים שיטין, וראשי חצאי-השיטין כרשימת הרמב"ם.
/// המקור: משנה תורה, הל' תפילין ומזוזה וספר תורה ח, ד — "צורת שירת האזינו...
/// וכותבין אותה בשבעים שיטות. ואלו הן התבות שבראש כל שיטה ושיטה".
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

/// 140 ראשי חצאי-השיטין לפי סדרם: ימין, שמאל, ימין, שמאל...
/// כינויי השם שברמב"ם ("יי׳") הוחלפו בשם המפורש כפי שהוא בטקסט המקרא.
const List<String> _rambamHalfLineHeads = [
  '\u05d4\u05d0\u05d6\u05d9\u05e0\u05d5',
  '\u05d5\u05ea\u05e9\u05de\u05e2',
  '\u05d9\u05e2\u05e8\u05e3',
  '\u05ea\u05d6\u05dc',
  '\u05db\u05e9\u05e2\u05d9\u05e8\u05dd',
  '\u05d5\u05db\u05e8\u05d1\u05d9\u05d1\u05d9\u05dd',
  '\u05db\u05d9',
  '\u05d4\u05d1\u05d5',
  '\u05d4\u05e6\u05d5\u05e8',
  '\u05db\u05d9',
  '\u05d0\u05dc',
  '\u05e6\u05d3\u05d9\u05e7',
  '\u05e9\u05d7\u05ea',
  '\u05d3\u05d5\u05e8',
  '\u05d4\u05dc\u05d9\u05d4\u05d5\u05d4',
  '\u05e2\u05dd',
  '\u05d4\u05dc\u05d5\u05d0',
  '\u05d4\u05d5\u05d0',
  '\u05d6\u05db\u05e8',
  '\u05d1\u05d9\u05e0\u05d5',
  '\u05e9\u05d0\u05dc',
  '\u05d6\u05e7\u05e0\u05d9\u05da',
  '\u05d1\u05d4\u05e0\u05d7\u05dc',
  '\u05d1\u05d4\u05e4\u05e8\u05d9\u05d3\u05d5',
  '\u05d9\u05e6\u05d1',
  '\u05dc\u05de\u05e1\u05e4\u05e8',
  '\u05db\u05d9',
  '\u05d9\u05e2\u05e7\u05d1',
  '\u05d9\u05de\u05e6\u05d0\u05d4\u05d5',
  '\u05d5\u05d1\u05ea\u05d4\u05d5',
  '\u05d9\u05e1\u05d1\u05d1\u05e0\u05d4\u05d5',
  '\u05d9\u05e6\u05e8\u05e0\u05d4\u05d5',
  '\u05db\u05e0\u05e9\u05e8',
  '\u05e2\u05dc',
  '\u05d9\u05e4\u05e8\u05e9',
  '\u05d9\u05e9\u05d0\u05d4\u05d5',
  '\u05d9\u05d4\u05d5\u05d4',
  '\u05d5\u05d0\u05d9\u05df',
  '\u05d9\u05e8\u05db\u05d1\u05d4\u05d5',
  '\u05d5\u05d9\u05d0\u05db\u05dc',
  '\u05d5\u05d9\u05e0\u05e7\u05d4\u05d5',
  '\u05d5\u05e9\u05de\u05df',
  '\u05d7\u05de\u05d0\u05ea',
  '\u05e2\u05dd',
  '\u05d1\u05e0\u05d9',
  '\u05e2\u05dd',
  '\u05d5\u05d3\u05dd',
  '\u05d5\u05d9\u05e9\u05de\u05df',
  '\u05e9\u05de\u05e0\u05ea',
  '\u05d5\u05d9\u05d8\u05e9',
  '\u05d5\u05d9\u05e0\u05d1\u05dc',
  '\u05d9\u05e7\u05e0\u05d0\u05d4\u05d5',
  '\u05d1\u05ea\u05d5\u05e2\u05d1\u05ea',
  '\u05d9\u05d6\u05d1\u05d7\u05d5',
  '\u05d0\u05dc\u05d4\u05d9\u05dd',
  '\u05d7\u05d3\u05e9\u05d9\u05dd',
  '\u05dc\u05d0',
  '\u05e6\u05d5\u05e8',
  '\u05d5\u05ea\u05e9\u05db\u05d7',
  '\u05d5\u05d9\u05e8\u05d0',
  '\u05de\u05db\u05e2\u05e1',
  '\u05d5\u05d9\u05d0\u05de\u05e8',
  '\u05d0\u05e8\u05d0\u05d4',
  '\u05db\u05d9',
  '\u05d1\u05e0\u05d9\u05dd',
  '\u05d4\u05dd',
  '\u05db\u05e2\u05e1\u05d5\u05e0\u05d9',
  '\u05d5\u05d0\u05e0\u05d9',
  '\u05d1\u05d2\u05d5\u05d9',
  '\u05db\u05d9',
  '\u05d5\u05ea\u05d9\u05e7\u05d3',
  '\u05d5\u05ea\u05d0\u05db\u05dc',
  '\u05d5\u05ea\u05dc\u05d4\u05d8',
  '\u05d0\u05e1\u05e4\u05d4',
  '\u05d7\u05e6\u05d9',
  '\u05de\u05d6\u05d9',
  '\u05d5\u05e7\u05d8\u05d1',
  '\u05d5\u05e9\u05df',
  '\u05e2\u05dd',
  '\u05de\u05d7\u05d5\u05e5',
  '\u05d5\u05de\u05d7\u05d3\u05e8\u05d9\u05dd',
  '\u05d2\u05dd',
  '\u05d9\u05d5\u05e0\u05e7',
  '\u05d0\u05de\u05e8\u05ea\u05d9',
  '\u05d0\u05e9\u05d1\u05d9\u05ea\u05d4',
  '\u05dc\u05d5\u05dc\u05d9',
  '\u05e4\u05df',
  '\u05e4\u05df',
  '\u05d5\u05dc\u05d0',
  '\u05db\u05d9',
  '\u05d5\u05d0\u05d9\u05df',
  '\u05dc\u05d5',
  '\u05d9\u05d1\u05d9\u05e0\u05d5',
  '\u05d0\u05d9\u05db\u05d4',
  '\u05d5\u05e9\u05e0\u05d9\u05dd',
  '\u05d0\u05dd',
  '\u05d5\u05d9\u05d4\u05d5\u05d4',
  '\u05db\u05d9',
  '\u05d5\u05d0\u05d9\u05d1\u05d9\u05e0\u05d5',
  '\u05db\u05d9',
  '\u05d5\u05de\u05e9\u05d3\u05de\u05ea',
  '\u05e2\u05e0\u05d1\u05de\u05d5',
  '\u05d0\u05e9\u05db\u05dc\u05ea',
  '\u05d7\u05de\u05ea',
  '\u05d5\u05e8\u05d0\u05e9',
  '\u05d4\u05dc\u05d0',
  '\u05d7\u05ea\u05d5\u05dd',
  '\u05dc\u05d9',
  '\u05dc\u05e2\u05ea',
  '\u05db\u05d9',
  '\u05d5\u05d7\u05e9',
  '\u05db\u05d9',
  '\u05d5\u05e2\u05dc',
  '\u05db\u05d9',
  '\u05d5\u05d0\u05e4\u05e1',
  '\u05d5\u05d0\u05de\u05e8',
  '\u05e6\u05d5\u05e8',
  '\u05d0\u05e9\u05e8',
  '\u05d9\u05e9\u05ea\u05d5',
  '\u05d9\u05e7\u05d5\u05de\u05d5',
  '\u05d9\u05d4\u05d9',
  '\u05e8\u05d0\u05d5',
  '\u05d5\u05d0\u05d9\u05df',
  '\u05d0\u05e0\u05d9',
  '\u05de\u05d7\u05e6\u05ea\u05d9',
  '\u05d5\u05d0\u05d9\u05df',
  '\u05db\u05d9',
  '\u05d5\u05d0\u05de\u05e8\u05ea\u05d9',
  '\u05d0\u05dd',
  '\u05d5\u05ea\u05d0\u05d7\u05d6',
  '\u05d0\u05e9\u05d9\u05d1',
  '\u05d5\u05dc\u05de\u05e9\u05e0\u05d0\u05d9',
  '\u05d0\u05e9\u05db\u05d9\u05e8',
  '\u05d5\u05d7\u05e8\u05d1\u05d9',
  '\u05de\u05d3\u05dd',
  '\u05de\u05e8\u05d0\u05e9',
  '\u05d4\u05e8\u05e0\u05d9\u05e0\u05d5',
  '\u05db\u05d9',
  '\u05d5\u05e0\u05e7\u05dd',
  '\u05d5\u05db\u05e4\u05e8',
];

/// ראש התא — אות רבתי/זעירא היא מילה נפרדת באסימונים, ולכן היא מצטרפת
/// למילה שאחריה כדי להשוות לתיבה השלמה שהרמב"ם מונה.
String _cellHead(List<LayoutWord> words) {
  if (words.isEmpty) return '';
  final first = words.first.stam;
  final hasPua = first.codeUnits.any(
    (c) => c >= kZeiraStart && c <= kRabatiEnd,
  );
  final stripPua = RegExp('[\u{E000}-\u{E0FF}]');
  final head = first.replaceAll(stripPua, '');
  if (!hasPua || words.length < 2) return head;
  return head + words[1].stam.replaceAll(stripPua, '');
}

List<TikkunLine> _haazinuLines(TikkunTradition tradition) {
  final tokens = tokenizeBook(
    readFixture('devarim'),
    'דברים',
    tradition: tradition,
  );
  final lines = paginateAllTokens(tokens, const StamWidthModel.uniform());
  final startIdx = tokens.indexWhere(
    (t) =>
        t.type == TikkunTokenType.specialStart &&
        t.section?.id == 'shirat_haazinu',
  );
  expect(startIdx, greaterThan(-1));
  final run = <TikkunLine>[];
  for (final line in lines) {
    if (line.startTokenIdx >= startIdx && line.layout.isSpecial) {
      run.add(line);
    } else if (run.isNotEmpty && !line.layout.isSpecial) {
      break;
    }
  }
  return run;
}

void main() {
  test('רשימת הרמב"ם — 140 חצאי שיטין', () {
    expect(_rambamHalfLineHeads.length, 140);
  });

  for (final tradition in TikkunTradition.values) {
    group('שירת האזינו — ${tradition.id}', () {
      late List<TikkunLine> run;

      setUpAll(() => run = _haazinuLines(tradition));

      test('שבעים שיטין, כל אחת חלוקה לשתיים', () {
        expect(run.length, 70);
        for (final line in run) {
          expect(line.manualCells?.length, 2);
        }
      });

      test('ראשי חצאי-השיטין כרשימת הרמב"ם', () {
        final heads = <String>[
          for (final line in run)
            for (final cell in line.manualCells!) _cellHead(cell.words),
        ];
        expect(heads.length, _rambamHalfLineHeads.length);
        for (var i = 0; i < heads.length; i++) {
          expect(
            escapeNonAscii(heads[i]),
            escapeNonAscii(_rambamHalfLineHeads[i]),
            reason: 'שיטה ${i ~/ 2 + 1}, חצי ${i % 2 == 0 ? 'ימין' : 'שמאל'}',
          );
        }
      });
    });
  }
}
