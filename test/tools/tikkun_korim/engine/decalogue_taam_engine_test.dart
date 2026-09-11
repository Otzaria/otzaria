/// המנוע עם טעם עליון/תחתון: הצורה הנבחרת מחליפה את מילות הדברות בלבד,
/// והמבנה (פרשיות, אותיות חריגות, שאר הפרק) אינו זז. אין טקסט מקרא גלוי.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

final String _joiner = String.fromCharCode(0x034F);

String _skeleton(List<TikkunToken> tokens) => tokens
    .map((t) => t.isWord ? stripNikud(t.value!).replaceAll(_joiner, '') : '')
    .join('|');

/// דיווח כישלון על שוויון נעשה על בוליאני בלבד — המחרוזת נושאת טקסט מקרא.
String _dump(List<TikkunToken> tokens) =>
    tokens.map((t) => t.isWord ? 'w:${t.value}' : t.type.name).join(',');

String _structure(List<TikkunToken> tokens) => tokens
    .map((t) => t.isWord ? 'w' : '${t.type.name}:${t.chapterNum}.${t.verseNum}')
    .join(',');

List<TikkunToken> _run(String id, TikkunDecalogueTaam taam) => tokenizeBook(
  readFixture(id),
  fixtureBookNames[id]!,
  decalogueTaam: taam,
);

void main() {
  for (final id in ['shemot', 'devarim']) {
    final place = TikkunData.decaloguePlaceOf(fixtureBookNames[id]!)!;
    final merged = _run(id, TikkunDecalogueTaam.merged);

    group(id, () {
      test('merged אינו נוגע בטקסט', () {
        final plain = tokenizeBook(readFixture(id), fixtureBookNames[id]!);
        expect(_dump(merged) == _dump(plain), isTrue);
      });

      for (final taam in [
        TikkunDecalogueTaam.elyon,
        TikkunDecalogueTaam.tachton,
      ]) {
        group(taam.id, () {
          final out = _run(id, taam);

          test('העיצורים והמבנה נשמרים', () {
            expect(_skeleton(out), _skeleton(merged));
            expect(_structure(out), _structure(merged));
          });

          test('כל מילות הדברות קיבלו את הצורה הנבחרת', () {
            final forms = out
                .where((t) => t.isWord)
                .map((t) => t.value!)
                .toSet();
            for (final w in place.words) {
              for (final part in w.formFor(taam).split(RegExp('[־ ]+'))) {
                if (part.isEmpty) continue;
                expect(
                  forms,
                  contains(part),
                  reason: escapeNonAscii(part),
                );
              }
            }
          });

          test('הטעמים אינם זהים למשולב', () {
            expect(_dump(out) == _dump(merged), isFalse);
          });
        });
      }
    });
  }
}
