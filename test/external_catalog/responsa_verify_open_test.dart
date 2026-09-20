import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';

/// אימות הספר שנפתח.
///
/// כאן יושבת ההכרעה אם ספר נפתח או לא. כל הרפיה כאן היא ספר שגוי
/// שמדווח כהצלחה, וכל החמרה היא ספר תקין שהמשתמש אינו מקבל — ולכן כל
/// אחד מהמקרים כאן נמדד בפועל מול ההתקנה.
void main() {
  List<String> verify({
    required String window,
    required String selectedResult,
    required String usedRef,
    String? expectedTitle,
  }) => ResponsaAutomation.verifyOpened(
    window: window,
    selectedResult: selectedResult,
    usedRef: usedRef,
    expectedTitle: expectedTitle,
  );

  group('פתיחה תקינה עוברת', () {
    test('כותרת החלון מוסיפה מיקום', () {
      expect(
        verify(
          window: 'שו"ת תורת יקותיאל דיינים סימן א',
          selectedResult: 'שו"ת תורת יקותיאל דיינים',
          usedRef: 'תורת יקותיאל דיינים',
          expectedTitle: 'תורת יקותיאל דיינים',
        ),
        isEmpty,
      );
    });

    test('מדף שנדבק לשם אינו מופיע בכותרת החלון', () {
      // `מדרש רבה (תורה) > שמות רבה (וילנא)` — התוכנה מכנה את החלון
      // בשם החיבור בלבד, ו-13 ספרים נפסלו אף שנפתחו נכון.
      expect(
        verify(
          window: 'שמות רבה (וילנא) פרשת שמות פרשה א',
          selectedResult: 'שמות רבה (וילנא)',
          usedRef: 'שמות רבה',
          expectedTitle: 'מדרש רבה (תורה) שמות רבה (וילנא)',
        ),
        isEmpty,
      );
    });

    test('הסתייגות בצד אחד בלבד אינה פוסלת', () {
      expect(
        verify(
          window: 'אוצר מדרשים (אייזנשטיין) היכלות',
          selectedResult: 'אוצר מדרשים (אייזנשטיין) היכלות',
          usedRef: 'היכלות',
          expectedTitle: "היכלות (עמ' 108-126)",
        ),
        isEmpty,
      );
    });

    test('אות שימוש שהתוכנה מוסיפה', () {
      expect(
        verify(
          window: 'פירוש המשנה לרמב"ם מסכת הוריות',
          selectedResult: 'פירוש המשנה לרמב"ם מסכת הוריות',
          usedRef: 'רמב"ם הוריות',
          expectedTitle: 'רמב"ם הוריות',
        ),
        isEmpty,
      );
    });
  });

  group('פתיחה שגויה נפסלת', () {
    test('מהדורה אחרת', () {
      // `שמות רבה (שנאן)` ו-`שמות רבה (וילנא)` הם שני ספרים.
      expect(
        verify(
          window: 'שמות רבה (וילנא) פרשת שמות פרשה א',
          selectedResult: 'שמות רבה (שנאן)',
          usedRef: 'שמות רבה',
          expectedTitle: 'מדרש רבה (תורה) שמות רבה (שנאן)',
        ),
        contains('selectedEdition'),
      );
    });

    test('חיבור אחר על אותה מסכת', () {
      // נמדד: `בית הבחירה למאירי על הש"ס ברכות` נפתח כ-`שרידי אש`.
      expect(
        verify(
          window: 'שרידי אש על הש"ס ברכות',
          selectedResult: 'שרידי אש על הש"ס ברכות',
          usedRef: 'על הש"ס ברכות',
          expectedTitle: 'בית הבחירה למאירי על הש"ס ברכות',
        ),
        contains('expectedTitle'),
      );
    });

    test('כרך אחר של אותו חיבור', () {
      expect(
        verify(
          window: 'נחלת דוד מסכת בבא קמא דף ב עמוד א',
          selectedResult: 'נחלת דוד בבא קמא',
          usedRef: 'נחלת דוד פסחים',
          expectedTitle: 'נחלת דוד פסחים',
        ),
        isNotEmpty,
      );
    });

    test('השורה שנבחרה אינה החלון שנפתח', () {
      expect(
        verify(
          window: 'דברים רבה (וילנא) פרשת דברים פרשה א',
          selectedResult: 'בראשית רבה (וילנא)',
          usedRef: 'בראשית רבה',
          expectedTitle: 'מדרש רבה (תורה) בראשית רבה (וילנא)',
        ),
        contains('selectedResult'),
      );
    });

    test('אסימון גנרי יחיד אינו מבדיל, והבדיקות האחרות תופסות', () {
      // `דברים` לבדו מוכל גם ב-`דברים רבה`. השורה עוברת, וההגנה
      // מגיעה מהכותרת המצופה — שגם היא `דברים` בלבד ולכן גם היא
      // עוברת. זה **גבול ידוע** של האימות: שם גנרי בן מילה אחת אינו
      // ניתן להבחנה, ומה שמגן עליו הוא בחירת השורה ולא האימות.
      expect(
        verify(
          window: 'דברים רבה (וילנא) פרשת דברים פרשה א',
          selectedResult: 'דברים',
          usedRef: 'דברים',
          expectedTitle: 'דברים',
        ),
        isEmpty,
      );
    });
  });

  test('בלי כותרת מצופה — שתי הבדיקות האחרות עדיין פועלות', () {
    expect(
      verify(
        window: 'שרידי אש על הש"ס ברכות',
        selectedResult: 'שרידי אש על הש"ס ברכות',
        usedRef: 'שרידי אש ברכות',
      ),
      isEmpty,
    );
    expect(
      verify(
        window: 'שרידי אש על הש"ס ברכות',
        selectedResult: 'מהרש"א פסחים',
        usedRef: 'מהרש"א פסחים',
      ),
      isNotEmpty,
    );
  });
}
