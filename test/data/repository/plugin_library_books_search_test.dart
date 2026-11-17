import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';

/// ספרים מבחוץ (של תוספים) מצטרפים לאיתור הספרים במסך הספרייה רק כשהמסך
/// מעביר אותם, כמו הקטלוגים החיצוניים.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataRepository repository;

  // אותו מזהה כמו ספר אוצריא: הכינויים והדור של ספר 7 אינם שלו.
  final pluginBook = ExternalLibraryBook(
    title: 'אבני נזר',
    id: 7,
    author: 'רבי אברהם בורנשטיין',
    categoryPath: 'שו"ת, אחרונים',
    link: '',
    externalLibraryId: 'mylib:7',
  );

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    repository = DataRepository()
      ..library = Future.value(
        Library(
          categories: [
            Category(
              title: 'שו"ת',
              description: '',
              shortDescription: '',
              order: 1,
              subCategories: [],
              books: [TextBook(id: 7, title: 'שו"ת אבני נזר')],
              parent: null,
            ),
          ],
        ),
      )
      ..localHebrewBooks = Future.value(const []);
  });
  tearDown(() => repository.bookSearchWorkerForTesting.dispose());

  test('הספרים מבחוץ מצטרפים לתוצאות לפי כותרת, מחבר ונתיב', () async {
    Future<List<Book>> find(String query) async =>
        (await repository.findBooksAndCategories(
          query,
          null,
          extraBooks: [pluginBook],
          sortByRatio: false,
        )).books;

    final byTitle = await find('אבני נזר');
    expect(byTitle.whereType<ExternalLibraryBook>().single, same(pluginBook));
    expect(byTitle.whereType<TextBook>(), hasLength(1));
    expect((await find('בורנשטיין')).single, same(pluginBook));
    expect((await find('אחרונים')).single, same(pluginBook));
  });

  test('extraBooksOnly מחפש רק בספרים מבחוץ, בלי ספרייה ובלי תיקיות', () async {
    final all = await repository.findBooksAndCategories(
      'שו"ת',
      null,
      extraBooks: [pluginBook],
      sortByRatio: false,
    );
    expect(all.categories, isNotEmpty);
    expect(all.books.whereType<TextBook>(), isNotEmpty);

    final only = await repository.findBooksAndCategories(
      'שו"ת',
      null,
      extraBooks: [pluginBook],
      extraBooksOnly: true,
      sortByRatio: false,
    );
    expect(only.books.single, same(pluginBook));
    expect(only.categories, isEmpty);
  });

  test('extraBooksOnly בלי ספרים מבחוץ מחזיר תוצאה ריקה', () async {
    final only = await repository.findBooksAndCategories(
      'אבני נזר',
      null,
      extraBooksOnly: true,
      sortByRatio: false,
    );
    expect(only.books, isEmpty);
    expect(only.categories, isEmpty);
  });

  test('בלי ספרים מבחוץ התוצאות זהות למה שהיו', () async {
    final without = await repository.findBooksAndCategories(
      'אבני נזר',
      null,
      sortByRatio: false,
    );
    final withEmpty = await repository.findBooksAndCategories(
      'אבני נזר',
      null,
      extraBooks: const [],
      sortByRatio: false,
    );

    expect(without.books.whereType<ExternalLibraryBook>(), isEmpty);
    expect(without.books.map((b) => b.title), ['שו"ת אבני נזר']);
    expect(withEmpty.books, without.books);
  });

  test(
    'a new plugin or library snapshot returns the current book objects',
    () async {
      final replacement = ExternalLibraryBook(
        title: pluginBook.title,
        id: 7,
        link: '',
      );
      var extras = <Book>[pluginBook];
      Future<List<Book>> search({bool only = false}) async =>
          (await repository.findBooksAndCategories(
            'אבני נזר',
            null,
            extraBooks: extras,
            extraBooksOnly: only,
            sortByRatio: false,
            reuseCatalog: true,
          )).books;

      expect((await search()).last, same(pluginBook));
      extras = [replacement];
      expect((await search()).last, same(replacement));
      expect(await search(only: true), [same(replacement)]);
      repository.library = Future.value(Library(categories: []));
      expect(await search(), [same(replacement)]);
    },
  );
}
