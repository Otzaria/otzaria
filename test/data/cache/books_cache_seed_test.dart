import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/migration/database/daos/book_dao.dart';

/// שורה כפי שקריאת הקטלוג מחזירה אותה (`selectBooksMinimal` עם עמודות הקובץ).
Map<String, dynamic> _row(
  int id,
  String title, {
  String? fileType,
  double order = 5,
}) => {
  'id': id,
  'title': title,
  'categoryId': 7,
  'orderIndex': order,
  'heShortDesc': null,
  'heDesc': null,
  BookDao.storedFileTypeKey: fileType,
  BookDao.storedFilePathKey: '/books/$title.txt',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => BooksCache.instance.clear());

  group('BooksCache.seedFromRows', () {
    test('זריעה מהקטלוג מסמנת את הקאש כטעון וממפה את כל השדות', () {
      BooksCache.instance.seedFromRows([
        _row(1, 'בראשית', fileType: 'pdf', order: 2),
        _row(2, 'שמות'),
      ], generation: BooksCache.instance.generation);

      expect(BooksCache.instance.isLoaded, isTrue);
      expect(BooksCache.instance.books, hasLength(2));

      final first = BooksCache.instance.getBookById(1)!;
      expect(first.title, 'בראשית');
      expect(first.filePath, '/books/בראשית.txt');
      expect(first.fileType, 'pdf');
      expect(first.categoryId, 7);
      expect(first.orderIndex, 2);

      // fileType ריק ב-DB נחשב 'txt', כמו במסלול הטעינה מה-DB.
      expect(BooksCache.instance.getBookById(2)!.fileType, 'txt');
    });

    test(
      'warmUp אחרי זריעה אינו נוגע ב-DB — שורש ביטול הקריאה הכפולה',
      () async {
        BooksCache.instance.seedFromRows(
          [_row(1, 'בראשית')],
          generation: BooksCache.instance.generation,
        );

        // ללא DB מאותחל, קריאה אמיתית ל-DB הייתה מרוקנת את הקאש; אם הקאש
        // נשמר — warmUp קיצר דרך `isLoaded` ולא קרא את טבלת `book` שוב.
        await BooksCache.instance.warmUp();

        expect(BooksCache.instance.isLoaded, isTrue);
        expect(BooksCache.instance.books, hasLength(1));
      },
    );

    test('זריעה על קאש טעון היא no-op', () {
      final gen = BooksCache.instance.generation;
      BooksCache.instance.seedFromRows([_row(1, 'בראשית')], generation: gen);
      BooksCache.instance.seedFromRows([
        _row(2, 'שמות'),
        _row(3, 'ויקרא'),
      ], generation: gen);

      expect(BooksCache.instance.books, hasLength(1));
      expect(BooksCache.instance.getBookById(1), isNotNull);
    });

    test('שורה פגומה אינה משאירה מטמון חלקי', () {
      final generation = BooksCache.instance.generation;
      expect(
        () => BooksCache.instance.seedFromRows(
          [
            _row(1, 'בראשית'),
            {..._row(2, 'שמות'), 'title': null},
          ],
          generation: generation,
        ),
        throwsA(isA<TypeError>()),
      );

      expect(BooksCache.instance.isLoaded, isFalse);
      expect(BooksCache.instance.books, isEmpty);
      expect(BooksCache.instance.getBookById(1), isNull);

      // A later healthy catalogue load must still work.
      BooksCache.instance.seedFromRows(
        [_row(3, 'ויקרא')],
        generation: generation,
      );
      expect(BooksCache.instance.books.single.title, 'ויקרא');
    });

    test('clear מאפשר זריעה מחדש אחרי החלפת ספרייה', () {
      BooksCache.instance.seedFromRows(
        [_row(1, 'בראשית')],
        generation: BooksCache.instance.generation,
      );
      BooksCache.instance.clear();

      expect(BooksCache.instance.isLoaded, isFalse);

      BooksCache.instance.seedFromRows(
        [_row(9, 'תהלים')],
        generation: BooksCache.instance.generation,
      );
      expect(BooksCache.instance.getBookById(9), isNotNull);
      expect(BooksCache.instance.getBookById(1), isNull);
    });

    test('clear שקרה אחרי צילום הדור פוסל את הזריעה', () {
      final staleGeneration = BooksCache.instance.generation;
      BooksCache.instance.clear(); // החלפת/רענון ספרייה תוך כדי השליפה

      BooksCache.instance.seedFromRows(
        [_row(1, 'בראשית')],
        generation: staleGeneration,
      );

      expect(BooksCache.instance.isLoaded, isFalse);
      expect(BooksCache.instance.books, isEmpty);
    });

    test('שורה בלי categoryId אינה מפילה את הזריעה (ואת בניית הקטלוג)', () {
      BooksCache.instance.seedFromRows([
        {..._row(1, 'בראשית'), 'categoryId': null},
      ], generation: BooksCache.instance.generation);

      expect(BooksCache.instance.getBookById(1)?.categoryId, 0);
    });

    test('books אינו מעתיק את הרשימה בכל גישה, ואינו ניתן לשינוי', () {
      BooksCache.instance.seedFromRows(
        [_row(1, 'בראשית')],
        generation: BooksCache.instance.generation,
      );
      final books = BooksCache.instance.books;

      expect(identical(books, BooksCache.instance.books), isTrue);
      expect(() => books.add(books.first), throwsUnsupportedError);
    });
  });
}
