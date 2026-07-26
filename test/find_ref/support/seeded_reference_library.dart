import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// עזרים לבדיקת מסלול ההתאמה **האמיתי** של "איתור מקורות": זורעים ספרייה
/// קטנה לשלושת המטמונים ש-[ReferenceBooksCache.search] קורא מהם, ומריצים
/// [FindRefRepository.findRefs] בלי להזריק `searchReferenceBooks`.
///
/// הכותרות, ראשי-התיבות ומזהי הספרים בטסטים הם נתוני אמת מ-`seforim.db`.
typedef SeedBook = ({int id, String title, List<String> acronyms});

/// זורע את הספרים ל-[BooksCache], [AcronymsCache] ו-[ReferenceBooksCache].
/// ה-`orderIndex` נקבע לפי מקום הספר ברשימה, כדי שסדר התוצאות יהיה צפוי.
void seedLibrary(List<SeedBook> books) {
  BooksCache.instance.setBooksForTesting([
    for (var i = 0; i < books.length; i++)
      BookCacheEntry(
        id: books[i].id,
        title: books[i].title,
        filePath: '',
        fileType: 'txt',
        categoryId: 1,
        orderIndex: i.toDouble(),
      ),
  ]);
  AcronymsCache.instance.setAcronymsForTesting({
    for (final b in books) b.id: b.acronyms,
  });
  ReferenceBooksCache.instance
    ..setFsPdfBooksForTesting(const [])
    ..seedForTesting(
      normalizedTitles: {
        for (final b in books) b.id: normalizeForFindRefMatch(b.title),
      },
      categoryPaths: {for (final b in books) b.id: 'ספרייה'},
    );
}

final _repos = <FindRefRepository>[];

/// בונה repository שכל שאילתות ה-DB שלו מוזרקות, אבל התאמת שם-הספר עוברת
/// דרך [ReferenceBooksCache.search] האמיתי.
///
/// [tocEntries] ממופה לפי `bookId`; [tocQueryTokensSeen] אוסף את הטוקנים
/// שנשלחו לחיפוש ה-TOC — כך אפשר לוודא *מה* נותר לחיפוש הפנימי.
FindRefRepository buildFindRefRepo({
  Map<int, List<Map<String, dynamic>>> tocEntries = const {},
  List<List<String>?>? tocQueryTokensSeen,
}) {
  final repo = FindRefRepository(
    isReferenceBooksCacheLoaded: () => true,
    warmUpReferenceBooksCache: () async {},
    getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async {
      tocQueryTokensSeen?.add(queryTokens);
      return tocEntries[bookId] ?? const <Map<String, dynamic>>[];
    },
    getAltTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
        const <Map<String, dynamic>>[],
    getAllAltTocFlatEntries: () async => const <Map<String, dynamic>>[],
    getCategoryPath: (bookId) async => 'ספרייה',
  );
  _repos.add(repo);
  return repo;
}

/// לקריאה ב-`tearDown`: מנקה את ה-repositories ואת שלושת המטמונים.
void resetSeededLibrary() {
  for (final repo in _repos) {
    repo.disposeForTesting();
  }
  _repos.clear();
  BooksCache.instance.clear();
  AcronymsCache.instance.clear();
  ReferenceBooksCache.instance.clear();
}
