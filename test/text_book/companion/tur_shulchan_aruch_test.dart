import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../../test_helpers/memory_cache_provider.dart';

import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/companion/tur_shulchan_aruch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveTurShulchanAruchTarget with a database', () {
    late Directory tempDir;
    final tur = TextBook(id: 1, title: 'טור');
    final yorehDeah = TextBook(id: 2, title: 'שולחן ערוך, יורה דעה');
    final choshenMishpat = TextBook(id: 3, title: 'שולחן ערוך, חושן משפט');

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      tempDir = await Directory.systemTemp.createTemp('otzaria-paired-book-');
      AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data'));
      final dbPath = path.join(tempDir.path, 'seforim.db');
      final database = MyDatabase.withPath(dbPath);
      final repository = SeforimRepository(database);
      await repository.ensureInitialized();
      final db = await database.database;
      for (final book in [tur, yorehDeah, choshenMishpat]) {
        db.execute(
          'INSERT INTO book (id, categoryId, sourceId, title) VALUES (?, 1, 1, ?)',
          [book.id, book.title],
        );
      }
      for (final (id, bookId, index, heRef) in [
        (1, 1, 20, 'טור, יורה דעה, קסט, א'),
        (2, 1, 30, 'טור, יורה דעה, כה, א'),
        (3, 1, 40, 'טור, יורה דעה, הקדמה, ב'),
        (4, 2, 10, 'שולחן ערוך, יורה דעה, כה, ב'),
        (5, 2, 30, 'שולחן ערוך, יורה דעה, כה, א'),
        (6, 3, 10, 'שולחן ערוך, חושן משפט, תכז, א'),
      ]) {
        db.execute(
          'INSERT INTO line (id, bookId, lineIndex, content, heRef) '
          'VALUES (?, ?, ?, ?, ?)',
          [id, bookId, index, 'תוכן', heRef],
        );
      }
      for (final book in [tur, yorehDeah, choshenMishpat]) {
        await repository.rebuildLineRefIndex(book.id!);
      }
      database.close();
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      await SqliteDataProvider.instance.initialize();
    });

    tearDown(() async {
      await SqliteDataProvider.instance.dispose();
      AppPaths.debugOverrideDataRootPath(null);
      await tempDir.delete(recursive: true);
    });

    test(
      'a missing Tur siman does not open the beginning of Orach Chaim',
      () async {
        expect(
          await resolveTurShulchanAruchTarget(choshenMishpat, 10, [tur]),
          isNull,
        );
      },
    );

    test(
      'a missing Shulchan Arukh siman does not open its beginning',
      () async {
        expect(
          await resolveTurShulchanAruchTarget(tur, 20, [yorehDeah]),
          isNull,
        );
      },
    );

    test(
      'an existing siman opens at its first seif in both directions',
      () async {
        expect(await resolveTurShulchanAruchTarget(tur, 30, [yorehDeah]), (
          book: yorehDeah,
          index: 30,
        ));
        expect(await resolveTurShulchanAruchTarget(yorehDeah, 10, [tur]), (
          book: tur,
          index: 30,
        ));
      },
    );

    test('a heading looks ahead to the following siman', () async {
      expect(await resolveTurShulchanAruchTarget(tur, 28, [yorehDeah]), (
        book: yorehDeah,
        index: 30,
      ));
    });

    test(
      'an introduction still opens the paired book at its beginning',
      () async {
        expect(await resolveTurShulchanAruchTarget(tur, 40, [yorehDeah]), (
          book: yorehDeah,
          index: 0,
        ));
      },
    );

    test(
      'a book heading with a single target still opens its beginning',
      () async {
        expect(await resolveTurShulchanAruchTarget(yorehDeah, 0, [tur]), (
          book: tur,
          index: 0,
        ));
      },
    );

    test('a missing part does not open a different target', () async {
      expect(
        await resolveTurShulchanAruchTarget(tur, 30, [choshenMishpat]),
        isNull,
      );
    });
  });
  group('turShulchanAruchPairTitles', () {
    test('the Tur pairs with the four Shulchan Arukh parts', () {
      expect(turShulchanAruchPairTitles(TextBook(title: 'טור')), [
        'שולחן ערוך, אורח חיים',
        'שולחן ערוך, יורה דעה',
        'שולחן ערוך, אבן העזר',
        'שולחן ערוך, חושן משפט',
      ]);
    });

    test('each Shulchan Arukh part pairs with the Tur', () {
      expect(
        turShulchanAruchPairTitles(TextBook(title: 'שולחן ערוך, אבן העזר')),
        ['טור'],
      );
    });

    test('other and unofficial books have no pair', () {
      expect(
        turShulchanAruchPairTitles(TextBook(title: 'משנה ברורה')),
        isEmpty,
      );
      expect(
        turShulchanAruchPairTitles(TextBook(title: 'שולחן ערוך, הקדמה')),
        isEmpty,
      );
      expect(
        turShulchanAruchPairTitles(
          TextBook(title: 'טור', source: BookSource.user),
        ),
        isEmpty,
      );
    });
  });

  group('turShulchanAruchTarget', () {
    test('Tur → the Shulchan Arukh part at the same siman', () {
      expect(turShulchanAruchTarget('טור', 'טור, אורח חיים,  כה, א'), (
        title: 'שולחן ערוך, אורח חיים',
        refKey: 'כה א',
      ));
      expect(turShulchanAruchTarget('טור', 'טור, חושן משפט, תכז, ג'), (
        title: 'שולחן ערוך, חושן משפט',
        refKey: 'תכז א',
      ));
    });

    test('Shulchan Arukh → the Tur at the same siman', () {
      expect(
        turShulchanAruchTarget(
          'שולחן ערוך, אורח חיים',
          'שולחן ערוך, אורח חיים, תקפח, ב',
        ),
        (title: 'טור', refKey: 'אורח חיים תקפח א'),
      );
    });

    test('extra spaces after the comma are ignored', () {
      expect(
        turShulchanAruchTarget(
          'שולחן ערוך, אבן העזר',
          'שולחן ערוך, אבן העזר,  א, ב',
        ),
        (title: 'טור', refKey: 'אבן העזר א א'),
      );
    });

    test('an introduction opens the other book with no siman', () {
      expect(turShulchanAruchTarget('טור', 'טור, יורה דעה, הקדמה,  ב'), (
        title: 'שולחן ערוך, יורה דעה',
        refKey: null,
      ));
    });

    test('a heRef of another book has no target', () {
      expect(turShulchanAruchTarget('טור', 'משנה ברורה, א, א'), isNull);
      expect(
        turShulchanAruchTarget('שולחן ערוך, יורה דעה', 'טור, יורה דעה, א, א'),
        isNull,
      );
    });
  });
}
