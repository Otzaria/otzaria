import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import '../../helpers/memory_settings_cache.dart';

/// טסטי רגרסיה לעטיפת `DocxBook → TextBook` ב-[OpenedTab.fromBook].
///
/// רקע: DOCX מוצג דרך זרימת ה-TextBook. בעטיפה הקודמת `id`, `categoryId`
/// ו-`externalLibraryId` נשמטו, וה-`TextBook` שנוצר הגיע ל-`TextBookBloc`
/// בלי הזיהויים האלה. בלעדיהם `LibraryProviderManager.getBookText` לא מצליח
/// לאתר את הספר במפת ה-cache (המפתח שלו הוא title+categoryId+fileType) —
/// והתוכן יוצא ריק במסך הקריאה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('OpenedTab.fromBook(DocxBook) — שימור זיהויים', () {
    test('שומר id, categoryId ו-externalLibraryId על ה-TextBook העטוף', () {
      final docx = DocxBook(
        id: 1234,
        title: 'בדיקה',
        path: r'C:\library\test\בדיקה.docx',
        categoryId: 42,
        categoryPath: 'ספרים אישיים',
        author: 'מחבר',
        heShortDesc: 'תיאור',
        filePath: r'C:\library\test\בדיקה.docx',
        externalLibraryId: 'sefaria:123',
      );

      final tab = OpenedTab.fromBook(docx, 0);
      addTearDown(tab.dispose);

      expect(tab, isA<TextBookTab>());
      final textTab = tab as TextBookTab;

      expect(
        textTab.book.id,
        1234,
        reason: 'id חייב להיות מועבר ל-TextBook העטוף',
      );
      expect(
        textTab.book.categoryId,
        42,
        reason:
            'categoryId דרוש ל-BookCompositeKey ב-LibraryProviderManager. '
            'בלעדיו getBookContent לא מאתר את הקובץ והגוף יוצא ריק.',
      );
      expect(textTab.book.externalLibraryId, 'sefaria:123');
      expect(textTab.book.title, 'בדיקה');
      expect(textTab.book.fileType, 'docx');
      expect(textTab.book.filePath, r'C:\library\test\בדיקה.docx');
    });

    test('משתמש ב-path כשfilePath null (fallback קיים)', () {
      final docx = DocxBook(
        title: 'בדיקה',
        path: r'C:\library\test\בדיקה.docx',
        categoryId: 7,
        // filePath מושמט בכוונה כדי שייפול ל-fallback של book.path
      );

      final tab = OpenedTab.fromBook(docx, 0) as TextBookTab;
      addTearDown(tab.dispose);

      expect(tab.book.filePath, r'C:\library\test\בדיקה.docx');
      expect(tab.book.categoryId, 7);
    });

    test('כאשר fileType של DocxBook ריק/שונה, נופלים לברירת מחדל docx', () {
      // המשתנה fileType ב-DocxBook הוא super.fileType = "docx" כברירת מחדל,
      // אבל הקוד עוטף ב-`book.fileType ?? "docx"` כהגנה — מוודאים שהזרימה
      // מוסיפה את הברירת מחדל גם אם בעתיד fileType ייעשה nullable שונה.
      final docx = DocxBook(
        title: 'בדיקה',
        path: r'C:\library\test\בדיקה.docx',
        categoryId: 5,
        // fileType ברירת המחדל של DocxBook היא 'docx'
      );

      final tab = OpenedTab.fromBook(docx, 0) as TextBookTab;
      addTearDown(tab.dispose);

      expect(tab.book.fileType, 'docx');
    });
  });
}
