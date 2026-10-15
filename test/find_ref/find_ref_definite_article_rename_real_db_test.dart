import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// בדיקה ידנית מול קטלוג אמיתי (otzaria-library#127): הוספת ה"א הידיעה לכל
/// כותר שפותח בראשי-תיבות של חכם אינה משנה אילו ספרים נמצאים ובאיזו דרגה.
/// `OTZARIA_BENCH_DB=/path/to/seforim.db flutter test <this file>`
void main() {
  final dbPath = Platform.environment['OTZARIA_BENCH_DB'];

  test(
    'ה"א הידיעה בכותרות אינה משנה את התאמות האיתור',
    skip: dbPath == null ? 'OTZARIA_BENCH_DB not set' : false,
    () {
      final db = sqlite3.sqlite3.open(dbPath!, mode: sqlite3.OpenMode.readOnly);
      final books = <int, ({String title, double order})>{};
      final acronyms = <int, List<String>>{};
      try {
        for (final r in db.select('SELECT id, title, orderIndex FROM book')) {
          books[r['id'] as int] = (
            title: r['title'] as String,
            order: (r['orderIndex'] as num).toDouble(),
          );
        }
        for (final r in db.select('SELECT bookId, term FROM book_acronym')) {
          acronyms.putIfAbsent(r['bookId'] as int, () => []).add(r['term']);
        }
      } finally {
        db.close();
      }

      String firstToken(String s) => normalizeForFindRefMatch(s).split(' ')[0];
      final renamed = {
        for (final MapEntry(key: id, value: b) in books.entries)
          if (sagesTakingDefiniteArticle.contains(firstToken(b.title)))
            id: 'ה${b.title}',
      };
      final taken = {for (final b in books.values) b.title};
      expect(renamed.values.where(taken.contains), isEmpty);

      // book_renames.csv: SeforimLibrary מעביר לשם החדש את כינויי השם הישן
      // ומוסיף את השם הישן עצמו ככינוי (carryAcronymsAcrossRenames).
      final carriedAcronyms = {
        ...acronyms,
        for (final id in renamed.keys) id: [...?acronyms[id], books[id]!.title],
      };

      Map<String, Map<int, int>> run(
        Map<int, String> titles,
        Map<int, List<String>> acronymsById,
        List<String> queries,
      ) {
        final entries = [
          for (final MapEntry(key: id, value: b) in books.entries)
            BookCacheEntry(
              id: id,
              title: titles[id] ?? b.title,
              filePath: '',
              fileType: 'txt',
              categoryId: 0,
              orderIndex: b.order,
            ),
        ];
        BooksCache.instance.setBooksForTesting(entries);
        AcronymsCache.instance.setAcronymsForTesting(acronymsById);
        ReferenceBooksCache.instance
          ..setFsPdfBooksForTesting(const [])
          ..seedForTesting(
            normalizedTitles: {
              for (final e in entries) e.id: normalizeForFindRefMatch(e.title),
            },
            categoryPaths: const {},
          );
        return {
          for (final q in queries)
            q: {
              for (final h in ReferenceBooksCache.instance.search(
                q,
                limit: 100000,
              ))
                if (h.matchRank < ReferenceBooksCache.fuzzyMatchRank)
                  h.bookId: h.matchRank,
            },
        };
      }

      final queries = <String>{
        for (final p in ['ה', 'הג', 'הגר', 'הר', 'הרא', 'הרמ', 'הרש', 'המה']) p,
        for (final id in renamed.keys) ...[
          books[id]!.title,
          renamed[id]!,
          firstToken(books[id]!.title),
          'ה${firstToken(books[id]!.title)}',
          ...?acronyms[id],
          for (final t in acronyms[id] ?? const <String>[]) 'ה$t',
        ],
      }.toList();

      final before = run(const {}, acronyms, queries);
      final after = run(renamed, carriedAcronyms, queries);

      String describe(int id, int? rank) =>
          '${renamed[id] ?? books[id]!.title}(${rank ?? '-'})';
      final changes = [
        for (final q in queries)
          for (final id in {...before[q]!.keys, ...after[q]!.keys})
            if (before[q]![id] != after[q]![id])
              '$q: ${describe(id, before[q]![id])} → ${after[q]![id] ?? '-'}',
      ];
      debugPrint(
        'books=${books.length} renamed=${renamed.length} '
        'queries=${queries.length} changes=${changes.length}',
      );
      debugPrint(changes.take(50).join('\n'));
      expect(changes, isEmpty);
    },
  );
}
