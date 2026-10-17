import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

void main() {
  group('TextDisplayProfile — גזירת הדגלים', () {
    test('ברירת המחדל: הכול מוצג, שם הוי"ה מוחלף ביקוק', () {
      const p = TextDisplayProfile.defaults;
      expect(p.removeNikud, isFalse);
      expect(p.removeTeamim, isFalse);
      expect(p.removePunctuation, isFalse);
      expect(p.replaceHolyNames, isTrue);
      expect(p.holyNameStyle, HolyNameStyle.kufKuf);
      expect(p.showAnchorMarkers, isTrue);
    });

    test('followNikud: הטעמים נעלמים עם הניקוד ומוצגים איתו', () {
      const hidden = TextDisplayProfile(nikud: MarkVisibility.hide);
      expect(hidden.removeTeamim, isTrue);
      const shown = TextDisplayProfile(nikud: MarkVisibility.show);
      expect(shown.removeTeamim, isFalse);
    });

    test('טעמים מנותקים מהניקוד', () {
      const p = TextDisplayProfile(
        nikud: MarkVisibility.hide,
        teamim: TeamimVisibility.show,
      );
      expect(p.removeNikud, isTrue);
      expect(p.removeTeamim, isFalse);
    });

    test('asIs = בלי החלפת שם הוי"ה', () {
      const p = TextDisplayProfile(holyName: HolyNameDisplay.asIs);
      expect(p.replaceHolyNames, isFalse);
    });

    test('fromLegacy ממפה את שני הדגלים הישנים', () {
      expect(
        HolyNameDisplay.fromLegacy(
          replaceHolyNames: false,
          style: HolyNameStyle.hehApostrophe,
        ),
        HolyNameDisplay.asIs,
      );
      expect(
        HolyNameDisplay.fromLegacy(
          replaceHolyNames: true,
          style: HolyNameStyle.hehApostrophe,
        ),
        HolyNameDisplay.hehApostrophe,
      );
      expect(
        HolyNameDisplay.fromLegacy(
          replaceHolyNames: true,
          style: HolyNameStyle.doubleYod,
        ),
        HolyNameDisplay.doubleYod,
      );
    });

    test('יי נשמר ונטען ב-JSON', () {
      expect(HolyNameDisplay.fromJson('doubleYod'), HolyNameDisplay.doubleYod);
      expect(HolyNameDisplay.doubleYod.style, HolyNameStyle.doubleYod);
    });
  });

  group('TextDisplayPatch', () {
    test('JSON הלוך ושוב, שדות null אינם נכתבים', () {
      const patch = TextDisplayPatch(
        nikud: MarkVisibility.hide,
        holyName: HolyNameDisplay.asIs,
      );
      final json = patch.toJson();
      expect(json, {'nikud': 'hide', 'holyName': 'asIs'});
      expect(TextDisplayPatch.fromJson(json), patch);
    });

    test('ערך לא מוכר ב-JSON נחשב ירושה ולא מפיל', () {
      final patch = TextDisplayPatch.fromJson({'nikud': 'maybe', 'x': 1});
      expect(patch.isEmpty, isTrue);
    });

    test('merge: הצד השני גובר, null לא דורס', () {
      const a = TextDisplayPatch(
        nikud: MarkVisibility.hide,
        punctuation: MarkVisibility.hide,
      );
      const b = TextDisplayPatch(nikud: MarkVisibility.show);
      expect(
        a.merge(b),
        const TextDisplayPatch(
          nikud: MarkVisibility.show,
          punctuation: MarkVisibility.hide,
        ),
      );
    });

    test('pruneAgainst מוחק שדות ששווים לבסיס', () {
      const patch = TextDisplayPatch(
        nikud: MarkVisibility.show,
        punctuation: MarkVisibility.hide,
      );
      final pruned = patch.pruneAgainst(TextDisplayProfile.defaults);
      expect(pruned, const TextDisplayPatch(punctuation: MarkVisibility.hide));
    });
  });

  group('TextDisplaySlot', () {
    test('12 חריצים, מפתחות ייחודיים והלוך ושוב', () {
      final all = TextDisplaySlot.all;
      expect(all.length, 12);
      expect(all.map((s) => s.key).toSet().length, 12);
      for (final slot in all) {
        expect(TextDisplaySlot.fromKey(slot.key), slot);
      }
      expect(TextDisplaySlot.fromKey('body.regular'), isNull);
      expect(TextDisplaySlot.fromKey('body.regular.nope'), isNull);
    });

    test('שרשרת הירושה: תצוגה → יעד → ערוץ, מסתיימת בשורש', () {
      const slot = TextDisplaySlot(
        target: TextTarget.commentary,
        view: TextView.pageShape,
        channel: TextChannel.copy,
      );
      final chain = slot.inheritanceChain.map((s) => s.key).toList();
      expect(chain.first, 'commentary.pageShape.copy');
      expect(chain.last, 'body.regular.display');
      expect(chain.length, 8);
      // המפרשים בתצוגה הרגילה קודמים לגוף בצורת הדף.
      expect(
        chain.indexOf('commentary.regular.copy'),
        lessThan(chain.indexOf('body.pageShape.copy')),
      );
      // כל ערוץ ההעתקה קודם לערוץ התצוגה.
      expect(
        chain.indexOf('body.regular.copy'),
        lessThan(chain.indexOf('commentary.pageShape.display')),
      );
    });

    test('השורש יורש רק מעצמו', () {
      expect(TextDisplaySlot.root.inheritanceChain, [TextDisplaySlot.root]);
    });
  });

  group('TextDisplayLayer', () {
    test('טלאי ריק אינו נשמר, JSON הלוך ושוב', () {
      final layer = TextDisplayLayer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
        TextDisplaySlot.commentaryDisplay: TextDisplayPatch.empty,
      });
      expect(layer.patches.length, 1);
      expect(TextDisplayLayer.fromJson(layer.toJson()), layer);
    });

    test('מפתח לא מוכר ב-JSON מדולג', () {
      final layer = TextDisplayLayer.fromJson({
        'body.regular.display': {'nikud': 'hide'},
        'bogus': {'nikud': 'hide'},
        'commentary.regular.display': 'not-a-map',
      });
      expect(layer.patches.length, 1);
    });

    test('merged ממזג לתוך חריץ קיים, without מסיר', () {
      final layer = TextDisplayLayer()
          .merged(
            TextDisplaySlot.root,
            const TextDisplayPatch(nikud: MarkVisibility.hide),
          )
          .merged(
            TextDisplaySlot.root,
            const TextDisplayPatch(punctuation: MarkVisibility.hide),
          );
      expect(
        layer.patchFor(TextDisplaySlot.root),
        const TextDisplayPatch(
          nikud: MarkVisibility.hide,
          punctuation: MarkVisibility.hide,
        ),
      );
      expect(layer.without(TextDisplaySlot.root).isEmpty, isTrue);
    });
  });
}
