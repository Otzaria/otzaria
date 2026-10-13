import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/view/copy_as_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// Builds the "העתק כ..." entry and returns helpers that act on its current
/// children, the way the context menu rebuilds them after every click.
({
  AppContextMenuEntry entry,
  List<AppContextMenuEntry> Function() children,
  void Function(String label) tap,
  bool Function(String label) checked,
  List<TextDisplayProfile> copied,
})
copyAs(TextDisplayProfile base, {String? selectedText = 'שלום'}) {
  final copied = <TextDisplayProfile>[];
  final entry = buildCopyAsMenuEntry(
    base: base,
    selectedText: selectedText,
    onCopy: copied.add,
  );
  List<AppContextMenuEntry> children() => entry.childrenBuilder!();
  AppContextMenuEntry find(String label) =>
      children().singleWhere((e) => e.label == label);
  return (
    entry: entry,
    children: children,
    tap: (label) => find(label).onTap!(),
    checked: (label) => find(label).isSelected,
    copied: copied,
  );
}

void main() {
  group('buildCopyAsMenuEntry — מצב התחלתי', () {
    test('ברירת המחדל: הכול מסומן חוץ משם הוי"ה ככתבו', () {
      final menu = copyAs(const TextDisplayProfile());
      expect(menu.children().map((e) => e.label), [
        'ניקוד',
        'טעמים',
        'פיסוק',
        'שם הוי"ה ככתבו',
        'ציוני המפרשים',
        null,
        'העתק',
        'כמו בתצוגה',
      ]);
      expect(menu.checked('ניקוד'), isTrue);
      expect(menu.checked('טעמים'), isTrue);
      expect(menu.checked('פיסוק'), isTrue);
      expect(menu.checked('שם הוי"ה ככתבו'), isFalse);
      expect(menu.checked('ציוני המפרשים'), isTrue);
    });

    test('טעמים followNikud מוצגים לפי הנראות האפקטיבית', () {
      final hidden = copyAs(
        const TextDisplayProfile(
          nikud: MarkVisibility.hide,
          teamim: TeamimVisibility.followNikud,
        ),
      );
      expect(hidden.checked('ניקוד'), isFalse);
      expect(hidden.checked('טעמים'), isFalse);

      final shown = copyAs(
        const TextDisplayProfile(teamim: TeamimVisibility.followNikud),
      );
      expect(shown.checked('טעמים'), isTrue);
    });

    test('שורות התיבות נשארות פתוחות; "העתק" ו"כמו בתצוגה" סוגרות', () {
      final menu = copyAs(const TextDisplayProfile());
      final rows = menu.children().where((e) => !e.isDivider).toList();
      expect(rows.take(5).every((e) => e.keepOpen), isTrue);
      expect(rows.skip(5).any((e) => e.keepOpen), isFalse);
    });

    test('ציונים מוסתרים בבסיס — אין שורת ציוני המפרשים', () {
      final menu = copyAs(
        const TextDisplayProfile(anchorMarkers: MarkVisibility.hide),
      );
      expect(
        menu.children().map((e) => e.label),
        isNot(contains('ציוני המפרשים')),
      );
    });
  });

  group('buildCopyAsMenuEntry — העתקה', () {
    test('"העתק" בלי שינוי נותן בדיוק את הבסיס, כמו "כמו בתצוגה"', () {
      const base = TextDisplayProfile(
        teamim: TeamimVisibility.followNikud,
        holyName: HolyNameDisplay.hehApostrophe,
      );
      final menu = copyAs(base);
      menu.tap('העתק');
      menu.tap('כמו בתצוגה');
      expect(menu.copied, [base, base]);
    });

    test('שילוב: בלי פיסוק וטעמים, שם הוי"ה ככתבו', () {
      final menu = copyAs(const TextDisplayProfile());
      menu.tap('פיסוק');
      menu.tap('טעמים');
      menu.tap('שם הוי"ה ככתבו');
      expect(menu.checked('פיסוק'), isFalse);
      expect(menu.checked('טעמים'), isFalse);
      expect(menu.checked('שם הוי"ה ככתבו'), isTrue);
      expect(menu.checked('ניקוד'), isTrue);

      menu.tap('העתק');
      final copied = menu.copied.single;
      expect(copied.removePunctuation, isTrue);
      expect(copied.removeTeamim, isTrue);
      expect(copied.removeNikud, isFalse);
      expect(copied.holyName, HolyNameDisplay.asIs);
      expect(copied.showAnchorMarkers, isTrue);
    });

    test('"כמו בתצוגה" מתעלם מהטיוטה', () {
      const base = TextDisplayProfile();
      final menu = copyAs(base);
      menu.tap('ניקוד');
      menu.tap('כמו בתצוגה');
      expect(menu.copied, [base]);
    });

    test('ניקוד כבוי וטעמים דולקים — הטעמים לא נגררים אחרי הניקוד', () {
      final menu = copyAs(
        const TextDisplayProfile(teamim: TeamimVisibility.followNikud),
      );
      menu.tap('ניקוד');
      expect(menu.checked('ניקוד'), isFalse);
      expect(menu.checked('טעמים'), isTrue);

      menu.tap('העתק');
      expect(menu.copied.single.removeNikud, isTrue);
      expect(menu.copied.single.removeTeamim, isFalse);
    });

    test('הדלקת טעמים כשהניקוד כבוי כותבת show מפורש', () {
      final menu = copyAs(
        const TextDisplayProfile(
          nikud: MarkVisibility.hide,
          teamim: TeamimVisibility.followNikud,
        ),
      );
      menu.tap('טעמים');
      menu.tap('העתק');
      expect(menu.copied.single.teamim, TeamimVisibility.show);
      expect(menu.copied.single.removeNikud, isTrue);
    });

    test('שם הוי"ה: ביטול הסימון חוזר לסגנון ההחלפה של הבסיס', () {
      final menu = copyAs(
        const TextDisplayProfile(holyName: HolyNameDisplay.hehApostrophe),
      );
      menu.tap('שם הוי"ה ככתבו');
      menu.tap('שם הוי"ה ככתבו');
      menu.tap('העתק');
      expect(menu.copied.single.holyName, HolyNameDisplay.hehApostrophe);
    });

    test('שם הוי"ה: בסיס ככתבו — ביטול הסימון מחליף ביקוק', () {
      final menu = copyAs(
        const TextDisplayProfile(holyName: HolyNameDisplay.asIs),
      );
      expect(menu.checked('שם הוי"ה ככתבו'), isTrue);
      menu.tap('שם הוי"ה ככתבו');
      menu.tap('העתק');
      expect(menu.copied.single.holyName, HolyNameDisplay.kufKuf);
    });

    test('ביטול ציוני המפרשים מסיר אותם בהעתקה', () {
      final menu = copyAs(const TextDisplayProfile());
      menu.tap('ציוני המפרשים');
      menu.tap('העתק');
      expect(menu.copied.single.showAnchorMarkers, isFalse);
    });

    test('כל פתיחה של התפריט מתחילה מחדש מהבסיס', () {
      const base = TextDisplayProfile();
      copyAs(base).tap('ניקוד');
      final reopened = copyAs(base);
      expect(reopened.checked('ניקוד'), isTrue);
    });
  });

  group('buildCopyAsMenuEntry — בלי בחירה', () {
    test('הכול disabled', () {
      for (final text in [null, '', '  ']) {
        final menu = copyAs(const TextDisplayProfile(), selectedText: text);
        expect(menu.entry.label, 'העתק כ...');
        expect(menu.entry.enabled, isFalse);
        expect(
          menu.children().where((e) => !e.isDivider).every((e) => !e.enabled),
          isTrue,
        );
      }
    });
  });
}
