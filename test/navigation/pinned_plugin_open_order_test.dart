import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';

/// רגרסיה: תוסף מוצמד לסרגל הניווט הבליח עם סרגל הלשוניות לפני שנפתח.
///
/// הסיבה הייתה שהניווט למסך הכלים נשלח לפני בחירת התוסף, והבחירה נדחתה
/// ל-addPostFrameCallback — כך שכל אנימציית המעבר הוצגה עם הכלי הקודם והסרגל
/// גלוי. [shouldSelectPinnedPluginBeforeNavigation] קובע מתי מותר להקדים.
void main() {
  group('shouldSelectPinnedPluginBeforeNavigation', () {
    test('תוסף כשהמסך בנוי והתוספים טעונים — נבחר לפני הניווט', () {
      expect(
        shouldSelectPinnedPluginBeforeNavigation(
          isPlugin: true,
          isToolsScreenBuilt: true,
          arePluginsLoaded: true,
        ),
        isTrue,
        reason: 'בחירה אחרי הניווט מציגה את הכלי הקודם עם סרגל הלשוניות',
      );
    });

    test('מסך הכלים טרם נבנה — נדחה למסלול ההמתנה', () {
      expect(
        shouldSelectPinnedPluginBeforeNavigation(
          isPlugin: true,
          isToolsScreenBuilt: false,
          arePluginsLoaded: true,
        ),
        isFalse,
      );
    });

    test('התוספים טרם נטענו — נדחה, אחרת אין descriptor לתוסף', () {
      // בלי descriptor הסרגל מוסתר אך מוצג כלי אחר — המשתמש נתקע בלי דרך לנווט.
      expect(
        shouldSelectPinnedPluginBeforeNavigation(
          isPlugin: true,
          isToolsScreenBuilt: true,
          arePluginsLoaded: false,
        ),
        isFalse,
      );
    });

    test('כלי מובנה אינו מקדים — סרגל הלשוניות נשאר גלוי עבורו ממילא', () {
      // requestOpenTool עלול להציג הודעת שגיאה (כלי מוסתר); הקדמתה לניווט
      // תגרום להודעה לקפוץ בעוד המשתמש רואה את המסך הקודם.
      expect(
        shouldSelectPinnedPluginBeforeNavigation(
          isPlugin: false,
          isToolsScreenBuilt: true,
          arePluginsLoaded: true,
        ),
        isFalse,
      );
    });

    test('שני תנאים בלבד אינם מספיקים', () {
      expect(
        shouldSelectPinnedPluginBeforeNavigation(
          isPlugin: false,
          isToolsScreenBuilt: false,
          arePluginsLoaded: true,
        ),
        isFalse,
      );
    });
  });
}
