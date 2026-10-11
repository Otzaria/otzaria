import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

const _bodyPageShape = TextDisplaySlot(
  target: TextTarget.body,
  view: TextView.pageShape,
  channel: TextChannel.display,
);
const _bodyCopy = TextDisplaySlot(
  target: TextTarget.body,
  view: TextView.regular,
  channel: TextChannel.copy,
);
const _commentaryCopy = TextDisplaySlot(
  target: TextTarget.commentary,
  view: TextView.regular,
  channel: TextChannel.copy,
);

TextDisplayLayer _layer(Map<TextDisplaySlot, TextDisplayPatch> patches) =>
    TextDisplayLayer(patches);

void main() {
  group('TextDisplayResolver — ירושה בתוך שכבה', () {
    test('בלי שכבות מתקבלת ברירת המחדל', () {
      final p = TextDisplayResolver.resolve(
        slot: TextDisplaySlot.commentaryDisplay,
        layers: const [],
      );
      expect(p, TextDisplayProfile.defaults);
    });

    test('מפרשים, צורת הדף והעתקה יורשים מהשורש', () {
      final global = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
      });
      for (final slot in TextDisplaySlot.all) {
        final p = TextDisplayResolver.resolve(slot: slot, layers: [global]);
        expect(p.removeNikud, isTrue, reason: slot.key);
      }
    });

    test('טלאי על המפרשים גובר על השורש רק אצל המפרשים', () {
      final global = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
        TextDisplaySlot.commentaryDisplay: const TextDisplayPatch(
          nikud: MarkVisibility.show,
        ),
      });
      expect(
        TextDisplayResolver.resolve(
          slot: TextDisplaySlot.root,
          layers: [global],
        ).removeNikud,
        isTrue,
      );
      expect(
        TextDisplayResolver.resolve(
          slot: TextDisplaySlot.commentaryDisplay,
          layers: [global],
        ).removeNikud,
        isFalse,
      );
      // גם ערוץ ההעתקה של המפרשים יורש מתצוגת המפרשים.
      expect(
        TextDisplayResolver.resolve(
          slot: _commentaryCopy,
          layers: [global],
        ).removeNikud,
        isFalse,
      );
    });

    test('טלאי על צורת הדף של הגוף אינו משפיע על התצוגה הרגילה', () {
      final global = _layer({
        _bodyPageShape: const TextDisplayPatch(
          punctuation: MarkVisibility.hide,
        ),
      });
      expect(
        TextDisplayResolver.resolve(
          slot: _bodyPageShape,
          layers: [global],
        ).removePunctuation,
        isTrue,
      );
      expect(
        TextDisplayResolver.resolve(
          slot: TextDisplaySlot.root,
          layers: [global],
        ).removePunctuation,
        isFalse,
      );
    });

    test('ערוץ העתקה מפורש גובר על התצוגה', () {
      final global = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
        _bodyCopy: const TextDisplayPatch(nikud: MarkVisibility.show),
      });
      expect(
        TextDisplayResolver.resolve(
          slot: _bodyCopy,
          layers: [global],
        ).removeNikud,
        isFalse,
      );
    });
  });

  group('TextDisplayResolver — סדר השכבות', () {
    test('שכבה ספציפית גוברת על כללית באותו חריץ', () {
      final global = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
      });
      final session = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.show,
        ),
      });
      expect(
        TextDisplayResolver.resolve(
          slot: TextDisplaySlot.root,
          layers: [session, global],
        ).removeNikud,
        isFalse,
      );
    });

    test('טלאי מפורש על המפרשים (החרגת התנ"ך) גובר על מה שהיו יורשים '
        'מהגוף, גם כשהגוף הוחלף בשכבת הכרטיסייה', () {
      // מודל התנ"ך: הגוף מנוקד, המפרשים לא.
      final tanach = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.show,
        ),
        TextDisplaySlot.commentaryDisplay: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
      });
      final session = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
      });
      final commentary = TextDisplayResolver.resolve(
        slot: TextDisplaySlot.commentaryDisplay,
        layers: [session, tanach],
      );
      expect(commentary.removeNikud, isTrue);
      // וגם בכיוון ההפוך: הצגה יזומה בגוף אינה מחזירה ניקוד למפרשים.
      final shown = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.show,
        ),
      });
      expect(
        TextDisplayResolver.resolve(
          slot: TextDisplaySlot.commentaryDisplay,
          layers: [shown, tanach],
        ).removeNikud,
        isTrue,
      );
    });

    test('בלי טלאי מפורש למפרשים הם עוקבים אחרי הגוף בשכבת הכרטיסייה', () {
      final global = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
      });
      final session = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.show,
        ),
      });
      expect(
        TextDisplayResolver.resolve(
          slot: TextDisplaySlot.commentaryDisplay,
          layers: [session, global],
        ).removeNikud,
        isFalse,
      );
    });

    test('עקיפה של המפרשים בכרטיסייה גוברת על הגוף', () {
      final session = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
        TextDisplaySlot.commentaryDisplay: const TextDisplayPatch(
          nikud: MarkVisibility.show,
        ),
      });
      expect(
        TextDisplayResolver.resolve(
          slot: TextDisplaySlot.commentaryDisplay,
          layers: [session],
        ).removeNikud,
        isFalse,
      );
    });

    test('שדות נפתרים בנפרד: ניקוד מהכרטיסייה, פיסוק מהגלובלי', () {
      final global = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          punctuation: MarkVisibility.hide,
        ),
      });
      final session = _layer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.hide,
        ),
      });
      final p = TextDisplayResolver.resolve(
        slot: TextDisplaySlot.root,
        layers: [session, global],
      );
      expect(p.removeNikud, isTrue);
      expect(p.removePunctuation, isTrue);
    });

    test('שכבות ריקות מדולגות', () {
      final p = TextDisplayResolver.resolve(
        slot: TextDisplaySlot.root,
        layers: [TextDisplayLayer.empty, TextDisplayLayer.empty],
      );
      expect(p, TextDisplayProfile.defaults);
    });
  });
}
