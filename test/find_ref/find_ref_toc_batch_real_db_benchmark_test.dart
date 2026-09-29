import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_factory.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../test_helpers/memory_cache_provider.dart';

/// Benchmark ידני של מסלול האיתור המלא (worker אמיתי) מול ספרייה אמיתית:
/// `OTZARIA_BENCH_DB=/path/to/seforim.db flutter test <this file>`.
/// מדפיס זמנים, מספר תוצאות וטביעת-אצבע שלהן — לא את תוכן הספרים.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dbPath = Platform.environment['OTZARIA_BENCH_DB'];

  test(
    'זמני איתור רב-מילי על ספרייה אמיתית',
    () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath!,
      );
      final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      try {
        final books = db.select(
          'SELECT id, title, categoryId, orderIndex FROM book',
        );
        final categories = {
          for (final row in db.select(
            'SELECT id, parentId, title FROM category',
          ))
            row['id'] as int: (
              parentId: row['parentId'] as int?,
              title: row['title'] as String,
            ),
        };
        String pathOf(int categoryId) {
          final titles = <String>[];
          for (
            var c = categories[categoryId];
            c != null && titles.length < 20;
            c = c.parentId == null ? null : categories[c.parentId]
          ) {
            titles.insert(0, c.title);
          }
          return titles.join(', ');
        }

        final entries = <BookCacheEntry>[
          for (final row in books)
            BookCacheEntry(
              id: row['id'] as int,
              title: row['title'] as String,
              filePath: '',
              fileType: 'txt',
              categoryId: row['categoryId'] as int,
              orderIndex: (row['orderIndex'] as num).toDouble(),
            ),
        ];
        BooksCache.instance.setBooksForTesting(entries);
        final acronymsByBook = <int, List<String>>{};
        for (final row in db.select('SELECT bookId, term FROM book_acronym')) {
          acronymsByBook
              .putIfAbsent(row['bookId'] as int, () => [])
              .add(row['term'] as String);
        }
        AcronymsCache.instance.setAcronymsForTesting(acronymsByBook);
        ReferenceBooksCache.instance
          ..setFsPdfBooksForTesting(const [])
          ..seedForTesting(
            normalizedTitles: {
              for (final b in entries) b.id: normalizeForFindRefMatch(b.title),
            },
            categoryPaths: {
              for (final b in entries) b.id: pathOf(b.categoryId),
            },
          );
      } finally {
        db.close();
      }

      final repo = buildFindRefRepository(respectHiddenLibrary: false);
      final worker = await FindRefDbIsolate.instance();
      addTearDown(() {
        repo.dispose();
        worker.disposeForTesting();
        BooksCache.instance.clear();
        AcronymsCache.instance.clear();
        ReferenceBooksCache.instance.clear();
      });
      await worker.prewarmAltTocFlat();

      const altQueries = [
        ['נח', 'עליה', 'ב'],
        ['פרשת', 'נח'],
        ['עליה', 'א'],
        ['פרק', 'א'],
        ['סימן', 'א'],
        ['הלכות', 'שבת'],
      ];
      for (final tokens in altQueries) {
        final stopwatch = Stopwatch()..start();
        final rows = await worker.searchAltTocFlat(tokens);
        debugPrint(
          'bench alt#${altQueries.indexOf(tokens)} rows=${rows.length} '
          'ms=${stopwatch.elapsedMilliseconds}',
        );
      }

      const queries = [
        'ברכות ב',
        'שבת עא ב',
        'רמבם תפלה',
        'ראש בבא בתרא',
        'שולחן ערוך אורח חיים א',
        'משנה ברורה א',
        'בראשית פרק א',
        'תוספות ברכות',
        'נח עליה ב',
        'פרשת נח',
        'הלכות שבת',
        'בבא קמא ב',
      ];
      final outPath = Platform.environment['OTZARIA_BENCH_OUT'];
      final out = StringBuffer();
      final stopwatch = Stopwatch();
      for (final query in queries) {
        stopwatch
          ..reset()
          ..start();
        final cold = await repo.findRefs(query);
        final coldMs = stopwatch.elapsedMilliseconds;
        final warm = <int>[];
        for (var i = 0; i < 5; i++) {
          stopwatch
            ..reset()
            ..start();
          await repo.findRefs(query);
          warm.add(stopwatch.elapsedMilliseconds);
        }
        warm.sort();
        final rows = [
          for (final r in cold)
            '${r.bookId}:${r.segment}:${r.tocLevel}:${r.isAltToc ? 1 : 0}:'
                '${_fnv(r.reference)}',
        ];
        out.writeln('q#${queries.indexOf(query)} ${rows.join(' ')}');
        debugPrint(
          'bench q#${queries.indexOf(query)} results=${cold.length} '
          'fp=${_fnv(rows.join(','))} coldMs=$coldMs '
          'warmMedianMs=${warm[2]}',
        );
      }
      if (outPath != null) File(outPath).writeAsStringSync(out.toString());
    },
    skip: dbPath == null || dbPath.isEmpty,
    timeout: const Timeout.factor(10),
  );
}

/// FNV-1a יציב בין הרצות (בניגוד ל-[Object.hash]) — להשוואת תוצאות בלי להדפיסן.
String _fnv(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}
