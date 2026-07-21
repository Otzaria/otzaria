// טסט רגרסיה ל-de574a7e9: בחירת מפרש "לכל הקטגוריה" בצורת הדף השתמשה
// בקטגוריה הראשונה בתוך heCategories כפי שהיא (למשל "אוצריא"/"תלמוד"/"הלכה"),
// שהיא כללית מדי ומשותפת לכל ספרי הספרייה מאותו סוג — כך שההגדרה דלפה
// לספרים אחרים שלא היו אמורים להיות מושפעים ממנה (פורום #774, #393).

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('parseCategories מסנן קטגוריות כלליות מדי', () {
    test('מסיר את הקטגוריה הכללית ומשאיר את הספציפית ראשונה', () {
      expect(
        PageShapeSettingsManager.parseCategories(
          'הלכה, משנה תורה, ספר מדע, הלכות יסודי התורה',
        ),
        ['משנה תורה', 'ספר מדע', 'הלכות יסודי התורה'],
      );
    });

    test('מסיר גם "אוצריא" וגם "תנ"ך" הכלליות', () {
      expect(
        PageShapeSettingsManager.parseCategories('אוצריא, תנ"ך, תורה, בראשית'),
        ['תורה', 'בראשית'],
      );
    });

    test('כשכל הקטגוריות כלליות, נופל חזרה לרשימה המקורית', () {
      expect(
        PageShapeSettingsManager.parseCategories('הלכה, תלמוד'),
        ['הלכה', 'תלמוד'],
      );
    });
  });

  group('getParentCategory לא בוחר קטגוריה כללית מדי', () {
    test('בוחר "משנה תורה" ולא "הלכה"', () {
      expect(
        PageShapeSettingsManager.getParentCategory(
          'הלכה, משנה תורה, ספר מדע, הלכות יסודי התורה',
        ),
        'משנה תורה',
      );
    });

    test('בוחר "תורה" ולא "תנ"ך"', () {
      expect(
        PageShapeSettingsManager.getParentCategory('אוצריא, תנ"ך, תורה, בראשית'),
        'תורה',
      );
    });
  });

  test(
      'רגרסיה: שמירת מפרש לקטגוריה של ספר אחד לא מדליפה לספר אחר תחת קטגוריית-אב משותפת',
      () async {
    // שני ספרי תנ"ך שונים החולקים קטגוריית-אב כללית ("אוצריא, תנ"ך") אך
    // נמצאים תחת ספר-מסגרת שונה ("תורה" מול "נביאים").
    const bereshitCategories = 'אוצריא, תנ"ך, תורה, בראשית';
    const yeshayahuCategories = 'אוצריא, תנ"ך, נביאים, ישעיהו';

    // המשתמש שומר בחירת מפרש "לכל הקטגוריה" מתוך ספר בראשית, בלי לבחור
    // קטגוריה ידנית — הקטגוריה נגזרת אוטומטית מ-getParentCategory, בדיוק
    // כפי שקורה ב-simple_text_viewer.dart וב-page_shape_screen.dart.
    final categoryToSave =
        PageShapeSettingsManager.getActiveCategory(bereshitCategories) ??
            PageShapeSettingsManager.getParentCategory(bereshitCategories);

    await PageShapeSettingsManager.saveConfiguration(
      'בראשית',
      const {
        'left': 'רש"י על בראשית',
        'right': null,
        'bottom': null,
        'bottomRight': null,
      },
      saveToCategory: categoryToSave,
    );

    // ההגדרה שנשמרה חייבת לחול על ספר בראשית עצמו...
    final bereshitConfig = PageShapeSettingsManager.loadConfiguration(
      'בראשית',
      heCategories: bereshitCategories,
    );
    expect(bereshitConfig?['left'], 'רש"י');

    // ...אך לא לדלוף לישעיהו, שאינו תחת אותה קטגוריית-אב ספציפית ("תורה").
    final yeshayahuConfig = PageShapeSettingsManager.loadConfiguration(
      'ישעיהו',
      heCategories: yeshayahuCategories,
    );
    expect(yeshayahuConfig, isNull);
  });
}
