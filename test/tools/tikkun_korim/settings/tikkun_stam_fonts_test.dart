/// גופני גוטמן אינם מוטמעים: כשהם מותקנים במערכת הם נבחרים, ואחרת הבחירה
/// נופלת לגופן Culmus המוטמע.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';

void main() {
  tearDown(TikkunStamFonts.debugReset);

  group('זמינות גופני גוטמן', () {
    test('משפחה מוטמעת שמישה תמיד', () {
      TikkunStamFonts.debugSetAvailability();
      expect(TikkunStamFonts.isUsable('AshkenaziStam'), isTrue);
      expect(TikkunStamFonts.isUsable('SefardiStam'), isTrue);
    });

    test('גוטמן שמיש רק כשהותקן', () {
      TikkunStamFonts.debugSetAvailability();
      expect(TikkunStamFonts.isUsable(kGuttmanStamFamily), isFalse);
      expect(TikkunStamFonts.isUsable(kGuttmanNikudFamily), isFalse);

      TikkunStamFonts.debugSetAvailability(stam: true, nikud: true);
      expect(TikkunStamFonts.isUsable(kGuttmanStamFamily), isTrue);
      expect(TikkunStamFonts.isUsable(kGuttmanNikudFamily), isTrue);
    });

    test('שני הטורים נבדקים בנפרד', () {
      TikkunStamFonts.debugSetAvailability(stam: true);
      expect(TikkunStamFonts.isUsable(kGuttmanStamFamily), isTrue);
      expect(TikkunStamFonts.isUsable(kGuttmanNikudFamily), isFalse);
    });
  });

  group('פענוח משפחת הגופן בהגדרות', () {
    const settings = TikkunSettings();

    test('ברירת המחדל היא גוטמן כשהוא מותקן', () {
      TikkunStamFonts.debugSetAvailability(stam: true, nikud: true);
      expect(settings.stamFontFamily, kGuttmanStamFamily);
      expect(settings.nikudFontFamily, kGuttmanNikudFamily);
    });

    test('כשגוטמן חסר: הסת"ם נופל ל-Culmus והמנוקד ל"כתר"', () {
      TikkunStamFonts.debugSetAvailability();
      expect(settings.stamFontFamily, kTikkunFallbackFamily);
      expect(settings.nikudFontFamily, kTikkunNikudFallbackFamily);
    });

    test('טור שגוטמן שלו חסר נופל, והשני נשאר', () {
      TikkunStamFonts.debugSetAvailability(stam: true);
      expect(settings.stamFontFamily, kGuttmanStamFamily);
      expect(settings.nikudFontFamily, kTikkunNikudFallbackFamily);
    });

    test('בחירה מפורשת בגופן מוטמע אינה מושפעת מזמינות גוטמן', () {
      TikkunStamFonts.debugSetAvailability();
      const chosen = TikkunSettings(stamFont: 'Sefardi');
      expect(chosen.stamFontFamily, 'SefardiStam');
    });

    test('גופן סת"ם שנבחר לטור המנוקד מוחלף — אין בו מִתאר לסימנים', () {
      TikkunStamFonts.debugSetAvailability(stam: true, nikud: true);
      for (final family in kTikkunUnpointedFamilies) {
        final chosen = TikkunSettings(
          nikudFont: '$kTikkunSystemFontPrefix$family',
        );
        expect(chosen.nikudFontFamily, kTikkunNikudFallbackFamily);
      }
      // ערך שמור מהרשימה הישנה — הבורר כבר אינו מציע גופני סת"ם למנוקד.
      const stale = TikkunSettings(nikudFont: 'Ashkenazi');
      expect(stale.nikudFontFamily, kGuttmanNikudFamily);
    });

    test('גופן אוצריא נשמר בקידומת System ומפוענח כשמו', () {
      TikkunStamFonts.debugSetAvailability();
      const chosen = TikkunSettings(stamFont: 'System:FrankRuhlCLM');
      expect(chosen.stamFontFamily, 'FrankRuhlCLM');
    });

    test('ערך שמור שאינו מוכר נופל לערך הראשון במפה', () {
      TikkunStamFonts.debugSetAvailability(stam: true);
      const chosen = TikkunSettings(stamFont: 'לא-קיים');
      expect(chosen.stamFontFamily, kGuttmanStamFamily);
    });
  });
}
