// ה-RegExp של GimatriaSearch הם static ומשותפים בין כל הקריאות. הטסטים כאן
// נועלים את הסמנטיקה של כל תבנית — כל מקרה נבנה כך שהוא נכשל אם התבנית
// המתאימה נשברת, ולא רק "מריץ" אותה.

import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';
import 'package:path/path.dart' as path;

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GimatriaSearch — ניקוי HTML ו-entities', () {
    String extractWith(String tocText) =>
        GimatriaSearch.extractPathFromTocEntries(
          currentLineIndex: 8,
          bookTitle: 'בראשית',
          tocEntries: [
            const TocEntry(
              id: 1,
              bookId: 1,
              text: 'בראשית',
              level: 1,
              lineIndex: 0,
            ),
            TocEntry(
              id: 2,
              bookId: 1,
              parentId: 1,
              text: tocText,
              level: 2,
              lineIndex: 1,
            ),
          ],
        );

    test('תגיות HTML מוסרות', () {
      expect(extractWith('<span class="c">פרק א</span>'), 'בראשית, פרק א');
    });

    test('entity בעל שם מוחלף בטקסט שלו', () {
      expect(extractWith('פרק&nbsp;א'), 'בראשית, פרק א');
    });

    test('entities עשרוני, הקסדצימלי ולא-מוכר מוסרים', () {
      // כל אחד מהשלושה נופל לתבנית אחרת, ואף אחת מהן לא תופסת את השתיים
      // האחרות — אם אחת נשברת, הפלט יכיל שארית ויכשל.
      expect(extractWith('<b>פרק</b>&#1488;&#x5D0;&foo; א'), 'בראשית, פרק א');
    });
  });

  group('GimatriaSearch — סריקת שורות', () {
    late Directory tempDir;
    late String folder;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'otzaria-gimatria-regexp-',
      );
      folder = path.join(tempDir.path, 'txtbooks');
      await Directory(folder).create(recursive: true);

      await Settings.init(cacheProvider: MemoryCacheProvider());
      AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        '',
      );
      // ללא seforim.db — searchInFiles נופל לסריקת הקבצים שאותה בודקים כאן.
      await SqliteDataProvider.instance.dispose();

      // שורת h1 שגימטרייתה תואמת (חייבת להידלג), ואחריה פסוק עם מספר פסוק
      // בסוגריים ועם קטע בסוגריים מסולסלות שאמור להיות מנוקה.
      await File(path.join(folder, 'בראשית.txt')).writeAsString(
        '<h1>אב</h1>\n'
        '(א) אב {הערה} גדול\n',
      );
    });

    tearDown(() async {
      await SqliteDataProvider.instance.dispose();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('שורת כותרת מדולגת ומספר הפסוק מתחלץ', () {
      // 'אב' = 3. אילו שורת ה-h1 לא הייתה מדולגת היו נמצאות שתי תוצאות.
      return GimatriaSearch.searchInFiles([folder], 3).then((results) {
        expect(results, hasLength(1), reason: 'שורת ה-h1 חייבת להידלג');
        expect(results.single.text, 'אב');
        expect(results.single.verseNumber, 'א');
      });
    });

    test('הנתיב ההיררכי נבנה מכותרת ה-h שמעל השורה', () async {
      final results = await GimatriaSearch.searchInFiles([folder], 3);

      // תופס שבירה ב-backreference או ב-dotAll של תבנית לכידת הכותרת:
      // בלעדיהם לא היה match והנתיב היה יוצא ריק.
      expect(results.single.path, 'אב');
    });

    test('סוגריים מסולסלות ומספר הפסוק אינם נספרים בגימטריה', () async {
      // 'אב גדול' = 46 אחרי ניקוי. אם הסוגריים המסולסלות לא היו מוסרות היה
      // מתקבל 326, ואם קידומת '(א) ' לא הייתה מוסרת — 47. בשני המקרים
      // הפסוק לא היה נמצא.
      final results = await GimatriaSearch.searchInFiles(
        [folder],
        46,
        wholeVerseOnly: true,
      );

      expect(results, hasLength(1));
      expect(results.single.text, 'אב גדול');
    });
  });
}
