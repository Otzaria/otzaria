// issue #994: בחירת המפרשים בצורת הדף נשמרה לפי כותרת הספר בלבד, ולכן אותו
// ספר הציג את אותם מפרשים בכל שולחנות העבודה. כאן נבדק תחום השמירה
// פר-שולחן-עבודה: הוא גובר על הגדרת הספר, ורק בשולחן שבו נשמר.

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const book = 'שולחן ערוך אורח חיים';
  const categories = 'הלכה, שולחן ערוך, אורח חיים';

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('בחירת מפרשים פר-שולחן עבודה', () {
    test('ההגדרה של השולחן גוברת על הגדרת הספר, ורק באותו שולחן', () async {
      await PageShapeSettingsManager.saveConfiguration(book, {
        'left': 'ט"ז',
        'right': 'מגן אברהם',
      });
      await PageShapeSettingsManager.saveConfiguration(
        book,
        {'left': 'משנה ברורה', 'right': null},
        saveToWorkspaceId: 'ws-2',
      );

      final inWorkspace2 = PageShapeSettingsManager.loadConfiguration(
        book,
        heCategories: categories,
        workspaceId: 'ws-2',
      );
      expect(inWorkspace2?['left'], 'משנה ברורה');

      final inWorkspace1 = PageShapeSettingsManager.loadConfiguration(
        book,
        heCategories: categories,
        workspaceId: 'ws-1',
      );
      expect(inWorkspace1?['left'], 'ט"ז');
      expect(inWorkspace1?['right'], 'מגן אברהם');
    });

    test('שמירה לשולחן אינה מוחקת את הגדרת הספר', () async {
      await PageShapeSettingsManager.saveConfiguration(book, {'left': 'ט"ז'});
      await PageShapeSettingsManager.saveConfiguration(
        book,
        {'left': 'משנה ברורה'},
        saveToWorkspaceId: 'ws-2',
      );

      expect(
        PageShapeSettingsManager.loadConfiguration(book)?['left'],
        'ט"ז',
      );
    });

    test('ההגדרה חלה על הספר שנשמר בלבד, לא על ספר אחר באותו שולחן', () async {
      await PageShapeSettingsManager.saveConfiguration(
        book,
        {'left': 'משנה ברורה'},
        saveToWorkspaceId: 'ws-2',
      );

      expect(
        PageShapeSettingsManager.loadConfiguration(
          'בראשית',
          workspaceId: 'ws-2',
        ),
        isNull,
      );
    });

    test('אין הגדרת ספר - הגדרת השולחן עדיין גוברת על הקטגוריה', () async {
      await PageShapeSettingsManager.saveConfiguration(
        book,
        {'left': 'מגן אברהם'},
        saveToCategory: 'שולחן ערוך',
      );
      await PageShapeSettingsManager.saveConfiguration(
        book,
        {'left': 'משנה ברורה'},
        saveToWorkspaceId: 'ws-2',
      );

      expect(
        PageShapeSettingsManager.loadConfiguration(
          book,
          heCategories: categories,
          workspaceId: 'ws-2',
        )?['left'],
        'משנה ברורה',
      );
      expect(
        PageShapeSettingsManager.loadConfiguration(
          book,
          heCategories: categories,
          workspaceId: 'ws-1',
        )?['left'],
        'מגן אברהם',
      );
    });

    test('איפוס מחזיר את השולחן להגדרת הספר', () async {
      await PageShapeSettingsManager.saveConfiguration(book, {'left': 'ט"ז'});
      await PageShapeSettingsManager.saveConfiguration(
        book,
        {'left': 'משנה ברורה'},
        saveToWorkspaceId: 'ws-2',
      );
      await PageShapeSettingsManager.resetWorkspaceCommentatorConfig(
        'ws-2',
        book,
      );

      expect(
        PageShapeSettingsManager.loadConfiguration(
          book,
          workspaceId: 'ws-2',
        )?['left'],
        'ט"ז',
      );
    });
  });

  group('commentatorWorkspaceTarget - יעד השמירה למסלולים החיים', () {
    test('מחזיר את השולחן רק כשיש לו בחירה משלו לספר', () async {
      expect(
        PageShapeSettingsManager.commentatorWorkspaceTarget('ws-2', book),
        isNull,
      );

      await PageShapeSettingsManager.saveConfiguration(
        book,
        {'left': 'משנה ברורה'},
        saveToWorkspaceId: 'ws-2',
      );

      expect(
        PageShapeSettingsManager.commentatorWorkspaceTarget('ws-2', book),
        'ws-2',
      );
      expect(
        PageShapeSettingsManager.commentatorWorkspaceTarget('ws-1', book),
        isNull,
      );
      expect(
        PageShapeSettingsManager.commentatorWorkspaceTarget(null, book),
        isNull,
      );
    });
  });
}
