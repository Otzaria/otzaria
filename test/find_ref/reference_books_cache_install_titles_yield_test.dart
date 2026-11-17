import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MyDatabase cacheDb;
  late List<BookCacheEntry> books;

  setUp(() async {
    cacheDb = MyDatabase.withPath(':memory:');
    final cacheRepo = SeforimRepository(cacheDb);
    await cacheRepo.ensureInitialized();
    ReferenceBooksCache.instance.clear();
    FileSystemLibraryProvider.instance.resetForTesting();
    BooksCache.instance.clear();
    AcronymsCache.instance.clear();
    books = [
      for (var i = 0; i < 20000; i++)
        BookCacheEntry(
          id: i + 1,
          title: 'ספר ההלכה והמנהג מספר ${_word(i)} של הדברים',
          filePath: '',
          fileType: 'txt',
          categoryId: 2,
          orderIndex: i.toDouble(),
        ),
    ];
    BooksCache.instance.setBooksForTesting(books);
    final cache = ReferenceBooksCache.instance;
    cache.categoriesProviderOverride = () async => const [];
    cache.pdfOutlineCacheRepositoryOverride = cacheRepo;
    cache.pdfFileMetadataProviderOverride = null;
  });

  tearDown(() {
    final cache = ReferenceBooksCache.instance;
    cache.clear();
    cache.categoriesProviderOverride = null;
    cache.pdfOutlineCacheRepositoryOverride = null;
    FileSystemLibraryProvider.instance.resetForTesting();
    cacheDb.close();
  });

  test(
    'warmUp לא חוסם את ה-UI isolate בבלוק סינכרוני אחד על כל הכותרות',
    () async {
      final titles = {
        for (final b in books) b.id: normalizeForFindRefMatch(b.title),
      };
      final reference = Stopwatch()..start();
      BookTitleIndex(books: books, normalizedTitles: titles);
      reference.stop();

      var maxGapUs = 0;
      var running = true;
      final probe = () async {
        final sw = Stopwatch()..start();
        while (running) {
          await Future<void>.delayed(Duration.zero);
          final gap = sw.elapsedMicroseconds;
          if (gap > maxGapUs) maxGapUs = gap;
          sw.reset();
        }
      }();
      await ReferenceBooksCache.instance.warmUp();
      running = false;
      await probe;

      expect(ReferenceBooksCache.instance.isLoaded, isTrue);
      // הבנייה המלאה של האינדקס כוללת את הבלוק שמפוצל; הבלוק המקסימלי חייב
      // להיות קטן ממנה בהרבה.
      expect(
        maxGapUs,
        lessThan(reference.elapsedMicroseconds ~/ 2),
        reason:
            'max gap ${maxGapUs}us, full index ${reference.elapsedMicroseconds}us',
      );
    },
  );

  test('האינדקס שנבנה ב-warmUp זהה לבנייה סינכרונית', () async {
    await ReferenceBooksCache.instance.warmUp();
    final direct = BookTitleIndex(
      books: books,
      normalizedTitles: {
        for (final b in books) b.id: normalizeForFindRefMatch(b.title),
      },
    );
    for (final query in [
      'הלכה',
      'מנהג מספר',
      'ספר ההלכה והמנהג',
      'דברים',
      'הלכא',
    ]) {
      expect(
        ReferenceBooksCache.instance
            .search(query)
            .map((h) => (h.bookId, h.matchRank, h.matchedTerm))
            .toList(),
        direct
            .search(query)
            .map((h) => (h.bookId, h.matchRank, h.matchedTerm))
            .toList(),
        reason: query,
      );
    }
  });
}

String _word(int i) {
  const letters = 'אבגדהוזחטיכלמנסעפצקרשת';
  var n = i;
  final sb = StringBuffer();
  do {
    sb.write(letters[n % letters.length]);
    n ~/= letters.length;
  } while (n > 0);
  return sb.toString();
}
