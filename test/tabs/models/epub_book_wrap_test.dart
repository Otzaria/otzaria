import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import '../../helpers/memory_settings_cache.dart';

/// טסטי רגרסיה לעטיפת `EpubBook → TextBook` ב-[OpenedTab.fromBook] —
/// מקבילים לטסטי DocxBook: בלי שימור `id`/`categoryId`/`externalLibraryId`
/// ה-cache לא מאתר את הספר והתוכן יוצא ריק במסך הקריאה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('OpenedTab.fromBook(EpubBook) — שימור זיהויים', () {
    test('שומר id, categoryId ו-externalLibraryId על ה-TextBook העטוף', () {
      final epub = EpubBook(
        id: 1234,
        title: 'בדיקה',
        path: r'C:\library\test\בדיקה.epub',
        categoryId: 42,
        categoryPath: 'ספרים אישיים',
        author: 'מחבר',
        heShortDesc: 'תיאור',
        filePath: r'C:\library\test\בדיקה.epub',
        externalLibraryId: 'sefaria:123',
      );

      final tab = OpenedTab.fromBook(epub, 0);
      addTearDown(tab.dispose);

      expect(tab, isA<TextBookTab>());
      final textTab = tab as TextBookTab;

      expect(textTab.book.id, 1234);
      expect(
        textTab.book.categoryId,
        42,
        reason:
            'categoryId דרוש ל-BookCompositeKey ב-LibraryProviderManager. '
            'בלעדיו getBookContent לא מאתר את הקובץ והגוף יוצא ריק.',
      );
      expect(textTab.book.externalLibraryId, 'sefaria:123');
      expect(textTab.book.title, 'בדיקה');
      expect(textTab.book.fileType, 'epub');
      expect(textTab.book.filePath, r'C:\library\test\בדיקה.epub');
    });

    test('משתמש ב-path כשfilePath null (fallback קיים)', () {
      final epub = EpubBook(
        title: 'בדיקה',
        path: r'C:\library\test\בדיקה.epub',
        categoryId: 7,
        // filePath מושמט בכוונה כדי שייפול ל-fallback של book.path
      );

      final tab = OpenedTab.fromBook(epub, 0) as TextBookTab;
      addTearDown(tab.dispose);

      expect(tab.book.filePath, r'C:\library\test\בדיקה.epub');
      expect(tab.book.categoryId, 7);
      expect(tab.book.fileType, 'epub');
    });
  });

  group('EpubBook — סריאליזציה', () {
    test('toJson/fromJson משמרים את השדות דרך Book.fromJson', () {
      final epub = EpubBook(
        id: 77,
        title: 'ספר',
        path: r'C:\books\ספר.epub',
        author: 'מחבר',
        categoryPath: 'קטגוריה',
        categoryId: 42,
        isUserBook: true,
      );

      final restored = Book.fromJson(epub.toJson());

      expect(restored, isA<EpubBook>());
      final restoredEpub = restored as EpubBook;
      expect(restoredEpub.title, 'ספר');
      expect(restoredEpub.path, r'C:\books\ספר.epub');
      expect(restoredEpub.author, 'מחבר');
      expect(restoredEpub.isUserBook, isTrue);
      expect(restoredEpub.fileType, 'epub');
      // בלי id/categoryId שחזור טאב שמור נכשל באיתור התוכן (BookCompositeKey).
      expect(restoredEpub.id, 77);
      expect(restoredEpub.categoryId, 42);
    });
  });
}
