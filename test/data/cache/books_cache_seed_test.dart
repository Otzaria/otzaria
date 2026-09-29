import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/migration/models/book.dart' as db_models;

db_models.Book _book(
  int id,
  String title, {
  String? fileType,
  double order = 5,
}) => db_models.Book(
  id: id,
  categoryId: 7,
  sourceId: 1,
  title: title,
  order: order,
  filePath: '/books/$title.txt',
  fileType: fileType,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => BooksCache.instance.clear());

  group('BooksCache.seedFromBooks', () {
    test('זריעה מהקטלוג מסמנת את הקאש כטעון וממפה את כל השדות', () {
      BooksCache.instance.seedFromBooks([
        _book(1, 'בראשית', fileType: 'pdf', order: 2),
        _book(2, 'שמות'),
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
        BooksCache.instance.seedFromBooks(
          [_book(1, 'בראשית')],
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
      BooksCache.instance.seedFromBooks([_book(1, 'בראשית')], generation: gen);
      BooksCache.instance.seedFromBooks([
        _book(2, 'שמות'),
        _book(3, 'ויקרא'),
      ], generation: gen);

      expect(BooksCache.instance.books, hasLength(1));
      expect(BooksCache.instance.getBookById(1), isNotNull);
    });

    test('clear מאפשר זריעה מחדש אחרי החלפת ספרייה', () {
      BooksCache.instance.seedFromBooks(
        [_book(1, 'בראשית')],
        generation: BooksCache.instance.generation,
      );
      BooksCache.instance.clear();

      expect(BooksCache.instance.isLoaded, isFalse);

      BooksCache.instance.seedFromBooks(
        [_book(9, 'תהלים')],
        generation: BooksCache.instance.generation,
      );
      expect(BooksCache.instance.getBookById(9), isNotNull);
      expect(BooksCache.instance.getBookById(1), isNull);
    });

    test('clear שקרה אחרי צילום הדור פוסל את הזריעה', () {
      final staleGeneration = BooksCache.instance.generation;
      BooksCache.instance.clear(); // החלפת/רענון ספרייה תוך כדי השליפה

      BooksCache.instance.seedFromBooks(
        [_book(1, 'בראשית')],
        generation: staleGeneration,
      );

      expect(BooksCache.instance.isLoaded, isFalse);
      expect(BooksCache.instance.books, isEmpty);
    });

    test('books אינו מעתיק את הרשימה בכל גישה, ואינו ניתן לשינוי', () {
      BooksCache.instance.seedFromBooks(
        [_book(1, 'בראשית')],
        generation: BooksCache.instance.generation,
      );
      final books = BooksCache.instance.books;

      expect(identical(books, BooksCache.instance.books), isTrue);
      expect(() => books.add(books.first), throwsUnsupportedError);
    });
  });
}
