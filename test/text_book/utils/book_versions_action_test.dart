import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/utils/book_versions_action.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('hasBookVersionsToOpen — מי זכאי לנוסחאות', () {
    test('ספר משתמש נדחה בלי לגשת למאגר', () async {
      final book = TextBook(
        title: 'ספר אישי',
        categoryId: 3,
        source: BookSource.user,
      );

      expect(await hasBookVersionsToOpen(book), isFalse);
    });

    test('ספר בלי categoryId נדחה — המהדורות מאותרות לפי הקטגוריה', () async {
      expect(await hasBookVersionsToOpen(TextBook(title: 'ספר')), isFalse);
    });

    test('נוסח יחיד שכבר פתוח אינו מוצע שוב', () async {
      availableBookVersionsProbeForTesting = (_) async => const [
        BookVersionInfo(
          versionTitle: 'Davidson',
          heVersionTitle: 'מהדורת דיווידסון',
          hasContent: true,
        ),
      ];
      addTearDown(() => availableBookVersionsProbeForTesting = null);

      final book = TextBook(title: 'ספר', categoryId: 7).copyWith(
        versionTitle: 'Davidson',
      );

      expect(await hasBookVersionsToOpen(book), isFalse);
    });

    test('נוסח פתוח עדיין מציע נוסחים אחרים', () async {
      availableBookVersionsProbeForTesting = (_) async => const [
        BookVersionInfo(
          versionTitle: 'Davidson',
          heVersionTitle: 'מהדורת דיווידסון',
          hasContent: true,
        ),
        BookVersionInfo(
          versionTitle: 'Vilna',
          heVersionTitle: 'מהדורת וילנא',
          hasContent: true,
        ),
      ];
      addTearDown(() => availableBookVersionsProbeForTesting = null);

      final book = TextBook(title: 'ספר', categoryId: 7).copyWith(
        versionTitle: 'Davidson',
      );

      expect(await hasBookVersionsToOpen(book), isTrue);
    });
  });

  group('כותרת הכרטיסייה של נוסח', () {
    test('נושאת את שם המהדורה בעברית, ולא את מפתח ה-DB האנגלי', () {
      final versionBook = TextBook(title: 'כתובות', categoryId: 5).copyWith(
        versionTitle: 'William Davidson Edition - Aramaic',
        heVersionTitle: 'מהדורת דיווידסון',
      );

      final tab = TextBookTab(book: versionBook, index: 0);
      addTearDown(tab.dispose);

      expect(tab.title, 'כתובות (מהדורת דיווידסון)');
    });
  });
}
