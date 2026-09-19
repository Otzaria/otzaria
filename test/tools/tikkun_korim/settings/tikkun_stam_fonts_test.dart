/// "אוצריא אשורית" מגיעה מחבילת `otzaria_ashurit` ומוצהרת ב-pubspec, ולכן
/// היא ברירת המחדל בשני הטורים; ערך שמור של גופן שהוסר נפתר אליה.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';

void main() {
  group('פענוח משפחת הגופן בהגדרות', () {
    test('ברירת המחדל היא אשורית בשני הטורים', () {
      const settings = TikkunSettings();
      expect(settings.stamFontFamily, AppFonts.ashuritFont);
      expect(settings.nikudFontFamily, AppFonts.ashuritNikudFont);
    });

    test('בחירה מפורשת בגופן מוטמע', () {
      const chosen = TikkunSettings(stamFont: 'Sefardi');
      expect(chosen.stamFontFamily, 'SefardiStam');
    });

    test('גופן סת"ם שנבחר לטור המנוקד מוחלף — אין בו מִתאר לסימנים', () {
      for (final family in kTikkunUnpointedFamilies) {
        final chosen = TikkunSettings(
          nikudFont: '$kTikkunSystemFontPrefix$family',
        );
        expect(chosen.nikudFontFamily, kTikkunNikudFallbackFamily);
      }
    });

    test('גופן אוצריא נשמר בקידומת System ומפוענח כשמו', () {
      const chosen = TikkunSettings(stamFont: 'System:FrankRuhlCLM');
      expect(chosen.stamFontFamily, 'FrankRuhlCLM');
    });

    test('ערך שמור של גופן שהוסר נפתר לאשורית', () {
      const stam = TikkunSettings(stamFont: 'Klasi');
      const nikud = TikkunSettings(nikudFont: 'Standard');
      expect(stam.stamFontFamily, AppFonts.ashuritFont);
      expect(nikud.nikudFontFamily, AppFonts.ashuritNikudFont);
    });
  });

  group('הגופן המוטמע של הכלי', () {
    test('לכל משפחה נבחרת יש קובץ לייצוא ה-PDF', () {
      for (final family in [
        AppFonts.ashuritFont,
        AppFonts.ashuritNikudFont,
        'AshkenaziStam',
        'SefardiStam',
      ]) {
        expect(kTikkunBundledFontAssets[family], isNotNull);
      }
    });

    test('לאשורית יש face בולד — אחרת הייצוא מסנתז בולד ממשיחה', () {
      expect(AppFonts.boldFontPaths[AppFonts.ashuritFont], isNotNull);
      expect(AppFonts.boldFontPaths[AppFonts.ashuritNikudFont], isNotNull);
    });

    test('נו"ן מנוזרת מקורית רק במשפחות שיש בהן גליף', () {
      expect(tikkunFamilyHasNunHafukha(AppFonts.ashuritFont), isTrue);
      expect(tikkunFamilyHasNunHafukha(AppFonts.ashuritNikudFont), isTrue);
      expect(tikkunFamilyHasNunHafukha('AshkenaziStam'), isFalse);
      expect(tikkunFamilyHasNunHafukha(null), isFalse);
    });
  });
}
