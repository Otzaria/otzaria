/// הנכס של טעם עליון/תחתון: שלוש הצורות חולקות עיצורים, וכל מילה נמצאת
/// בטקסט הספרייה בפסוק שהנכס תולה בה. אין בבדיקה טקסט מקרא גלוי.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

final RegExp _separator = RegExp('[־\\s]+');

final RegExp _joiner = RegExp('\u034F');

List<String> _parts(String word) =>
    word.split(_separator).where((p) => p.isNotEmpty).toList();

String _consonants(String word) => stripNikud(word).replaceAll(_joiner, '');

/// מילות הפרק מהפיקסצ'ר, עם מספר הפסוק של כל אחת.
List<({int verse, String word})> _placeWords(
  String fixtureId,
  DecaloguePlace place,
) {
  final tokens = tokenizeText(cleanRawText(readFixture(fixtureId)));
  final out = <({int verse, String word})>[];
  var chapter = 0;
  var verse = 0;
  for (final tok in tokens) {
    switch (tok.type) {
      case TikkunTokenType.chapterBreak:
        chapter = tok.chapterNum!;
      case TikkunTokenType.verseBreak:
        verse = tok.verseNum!;
      case TikkunTokenType.word:
        if (chapter == place.chapter &&
            verse >= place.fromVerse &&
            verse <= place.toVerse) {
          out.add((verse: verse, word: tok.value!));
        }
      default:
        break;
    }
  }
  return out;
}

void main() {
  const places = {'שמות': 'shemot', 'דברים': 'devarim'};

  test('הנכס מכסה את שני המקומות שיש בהם שתי מערכות טעמים', () {
    expect(TikkunData.decaloguePlaces.keys, containsAll(places.keys));
    for (final name in places.keys) {
      expect(TikkunData.decaloguePlaceOf(name)!.words, isNotEmpty);
    }
  });

  for (final entry in places.entries) {
    group(entry.key, () {
      final place = TikkunData.decaloguePlaceOf(entry.key)!;

      test('העיצורים זהים בשלוש הצורות, והטעמים נבדלים', () {
        var differing = 0;
        for (final word in place.words) {
          final skeleton = _parts(word.merged).map(_consonants).toList();
          for (final form in [word.elyon, word.tachton]) {
            expect(
              _parts(form).map(_consonants).toList(),
              skeleton,
              reason: escapeNonAscii(word.merged),
            );
          }
          if (word.elyon != word.tachton) differing++;
        }
        expect(differing, place.words.length);
      });

      test('כל מילה בנכס נמצאת בטקסט הספרייה בפסוק שהנכס תולה בה', () {
        final words = _placeWords(entry.value, place);
        final consonants = words.map((w) => _consonants(w.word)).toList();
        var pos = 0;
        for (final word in place.words) {
          final target = _parts(word.merged).map(_consonants).toList();
          var found = -1;
          for (var j = pos; j + target.length <= consonants.length; j++) {
            if (List.generate(
              target.length,
              (k) => consonants[j + k] == target[k],
            ).every((ok) => ok)) {
              found = j;
              break;
            }
          }
          expect(
            found,
            isNonNegative,
            reason: 'missing word #${place.words.indexOf(word)}',
          );
          expect(
            words[found].verse,
            inInclusiveRange(word.vFrom, word.vTo),
            reason: 'wrong verse for word #${place.words.indexOf(word)}',
          );
          pos = found + target.length;
        }
      });
    });
  }
}
