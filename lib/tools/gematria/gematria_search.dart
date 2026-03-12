// lib/tools/gematria/gematria_search.dart
//
// לוגיקת חיפוש גימטריה — חיפוש בבסיס נתונים SQLite ו-fallback לקבצים.
// SearchResult הוצא ל-models/search_result.dart.

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/tools/gematria/models/search_result.dart';

class GimatriaSearch {
  // גימטריה רגילה (ברירת מחדל)
  static const Map<String, int> _regularValues = {
    'א': 1,
    'ב': 2,
    'ג': 3,
    'ד': 4,
    'ה': 5,
    'ו': 6,
    'ז': 7,
    'ח': 8,
    'ט': 9,
    'י': 10,
    'כ': 20,
    'ך': 20,
    'ל': 30,
    'מ': 40,
    'ם': 40,
    'נ': 50,
    'ן': 50,
    'ס': 60,
    'ע': 70,
    'פ': 80,
    'ף': 80,
    'צ': 90,
    'ץ': 90,
    'ק': 100,
    'ר': 200,
    'ש': 300,
    'ת': 400,
  };

  // גימטריה קטנה
  static const Map<String, int> _smallValues = {
    'א': 1,
    'ב': 2,
    'ג': 3,
    'ד': 4,
    'ה': 5,
    'ו': 6,
    'ז': 7,
    'ח': 8,
    'ט': 9,
    'י': 1,
    'כ': 2,
    'ך': 2,
    'ל': 3,
    'מ': 4,
    'ם': 4,
    'נ': 5,
    'ן': 5,
    'ס': 6,
    'ע': 7,
    'פ': 8,
    'ף': 8,
    'צ': 9,
    'ץ': 9,
    'ק': 1,
    'ר': 2,
    'ש': 3,
    'ת': 4,
  };

  // גימטריה עם אותיות סופיות שונות
  static const Map<String, int> _finalLettersValues = {
    'א': 1,
    'ב': 2,
    'ג': 3,
    'ד': 4,
    'ה': 5,
    'ו': 6,
    'ז': 7,
    'ח': 8,
    'ט': 9,
    'י': 10,
    'כ': 20,
    'ך': 500,
    'ל': 30,
    'מ': 40,
    'ם': 600,
    'נ': 50,
    'ן': 700,
    'ס': 60,
    'ע': 70,
    'פ': 80,
    'ף': 800,
    'צ': 90,
    'ץ': 900,
    'ק': 100,
    'ר': 200,
    'ש': 300,
    'ת': 400,
  };

  static int gimatria(String text, {String method = 'regular'}) {
    final Map<String, int> values = switch (method) {
      'small' => _smallValues,
      'finalLetters' => _finalLettersValues,
      _ => _regularValues,
    };

    var sum = 0;
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      final v = values[ch];
      if (v != null) sum += v;
    }
    return sum;
  }

  /// חיפוש ב-SQLite עם fallback לחיפוש בקבצים.
  static Future<List<SearchResult>> searchInFiles(
    String folder,
    int targetGimatria, {
    int maxPhraseWords = 8,
    int fileLimit = 1000,
    bool wholeVerseOnly = false,
    bool debug = false,
    String gematriaMethod = 'regular',
    bool useWithKolel = false,
    List<String>? bookTitles,
  }) async {
    final dbProvider = SqliteDataProvider.instance;
    if (await dbProvider.databaseExists() && dbProvider.isInitialized) {
      try {
        return await _searchInDatabase(
          targetGimatria,
          maxPhraseWords: maxPhraseWords,
          fileLimit: fileLimit,
          wholeVerseOnly: wholeVerseOnly,
          debug: debug,
          gematriaMethod: gematriaMethod,
          useWithKolel: useWithKolel,
          bookTitles: bookTitles,
        );
      } catch (e) {
        if (debug) {
          debugPrint('Database search failed, falling back to file search: $e');
        }
      }
    }

    return _searchInFilesLegacy(
      folder,
      targetGimatria,
      maxPhraseWords: maxPhraseWords,
      fileLimit: fileLimit,
      wholeVerseOnly: wholeVerseOnly,
      debug: debug,
      gematriaMethod: gematriaMethod,
      useWithKolel: useWithKolel,
    );
  }

  static Future<List<SearchResult>> _searchInDatabase(
    int targetGimatria, {
    int maxPhraseWords = 8,
    int fileLimit = 1000,
    bool wholeVerseOnly = false,
    bool debug = false,
    String gematriaMethod = 'regular',
    bool useWithKolel = false,
    List<String>? bookTitles,
  }) async {
    final List<SearchResult> found = [];
    final dbProvider = SqliteDataProvider.instance;
    final repository = dbProvider.repository;

    if (repository == null) {
      throw Exception('Database repository not initialized');
    }

    List<int> bookIds = [];
    if (bookTitles != null && bookTitles.isNotEmpty) {
      for (final title in bookTitles) {
        final book = await repository.getBookByTitle(title);
        if (book != null) bookIds.add(book.id);
      }
    } else {
      final allBooks = await repository.getAllBooks();
      bookIds = allBooks.map((b) => b.id).toList();
    }

    if (debug) {
      debugPrint('Searching in ${bookIds.length} books from database');
    }

    for (final bookId in bookIds) {
      if (found.length >= fileLimit) break;

      final book = await repository.getBook(bookId);
      if (book == null) continue;

      final lines = await repository.getLines(bookId, 0, book.totalLines - 1);

      if (debug) {
        debugPrint('Scanning book: ${book.title} (lines: ${lines.length})');
      }

      final tocEntries = await repository.getBookTocs(bookId);

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final content = line.content;

        if (RegExp(r'<h[1-6][^>]*>').hasMatch(content)) continue;

        final verseMatch = RegExp(r'^\(([^\)]+)\)').firstMatch(content);
        final verseNumber = verseMatch?.group(1) ?? '';

        var cleanLine = content.replaceFirst(RegExp(r'^\([^\)]+\)\s*'), '');
        cleanLine = cleanLine.replaceAll(RegExp(r'\{[^\}]*\}'), '');
        final lineWithoutHtml = _cleanHtml(cleanLine);

        final words = lineWithoutHtml
            .split(RegExp(r'\s+'))
            .where((w) => w.trim().isNotEmpty)
            .toList();
        if (words.isEmpty) continue;

        if (wholeVerseOnly) {
          var totalValue = words
              .map((w) => gimatria(w, method: gematriaMethod))
              .fold(0, (a, b) => a + b);
          if (useWithKolel) totalValue += words.length;

          if (totalValue == targetGimatria) {
            final path =
                await _extractPathFromToc(line.id, tocEntries, repository);
            found.add(SearchResult(
              file: book.title,
              line: line.lineIndex + 1,
              text: _cleanHtml(words.join(' ')),
              path: path,
              verseNumber: verseNumber,
            ));
            if (found.length >= fileLimit) return found;
          }
        } else {
          final wordValues =
              words.map((w) => gimatria(w, method: gematriaMethod)).toList();
          for (int start = 0; start < words.length; start++) {
            int acc = 0;
            for (int offset = 0;
                offset < maxPhraseWords && start + offset < words.length;
                offset++) {
              acc += wordValues[start + offset];
              var finalValue = acc;
              if (useWithKolel) finalValue += (offset + 1);

              if (finalValue == targetGimatria) {
                final phrase =
                    words.sublist(start, start + offset + 1).join(' ');
                final path =
                    await _extractPathFromToc(line.id, tocEntries, repository);
                final ctx = _extractContext(words, start, offset);
                found.add(SearchResult(
                  file: book.title,
                  line: line.lineIndex + 1,
                  text: _cleanHtml(phrase),
                  path: path,
                  verseNumber: verseNumber,
                  contextBefore: ctx.$1,
                  contextAfter: ctx.$2,
                ));
                if (found.length >= fileLimit) return found;
              } else if (finalValue > targetGimatria) {
                break;
              }
            }
          }
        }
      }
    }
    return found;
  }

  static Future<String> _extractPathFromToc(
      int lineId, List<dynamic> tocEntries, dynamic repository) async {
    try {
      final tocEntry = await repository.getTocEntryForLine(lineId);
      if (tocEntry == null) return '';

      final List<String> pathParts = [];
      dynamic current = tocEntry;

      while (current != null) {
        final tocText = await repository.getTocText(current.textId);
        if (tocText != null && tocText.text.isNotEmpty) {
          pathParts.insert(0, _cleanHtml(tocText.text));
        }
        current = current.parentId != null
            ? await repository.getTocEntry(current.parentId!)
            : null;
      }

      return pathParts.join(', ');
    } catch (_) {
      return '';
    }
  }

  static Future<List<SearchResult>> _searchInFilesLegacy(
    String folder,
    int targetGimatria, {
    int maxPhraseWords = 8,
    int fileLimit = 1000,
    bool wholeVerseOnly = false,
    bool debug = false,
    String gematriaMethod = 'regular',
    bool useWithKolel = false,
  }) async {
    final List<SearchResult> found = [];
    final dir = Directory(folder);
    if (!await dir.exists()) return found;

    final files = dir
        .list(recursive: true, followLinks: false)
        .where((e) => e is File && e.path.toLowerCase().endsWith('.txt'))
        .cast<File>();

    await for (final file in files) {
      try {
        final String content = await file.readAsString(encoding: utf8);
        final lines = const LineSplitter().convert(content);

        if (debug) {
          debugPrint('Scanning file: ${file.path} (lines: ${lines.length})');
        }

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (RegExp(r'<h[1-6][^>]*>').hasMatch(line)) continue;

          final verseMatch = RegExp(r'^\(([^\)]+)\)').firstMatch(line);
          final verseNumber = verseMatch?.group(1) ?? '';

          var cleanLine = line.replaceFirst(RegExp(r'^\([^\)]+\)\s*'), '');
          cleanLine = cleanLine.replaceAll(RegExp(r'\{[^\}]*\}'), '');
          final lineWithoutHtml = _cleanHtml(cleanLine);

          final words = lineWithoutHtml
              .split(RegExp(r'\s+'))
              .where((w) => w.trim().isNotEmpty)
              .toList();
          if (words.isEmpty) continue;

          if (wholeVerseOnly) {
            var totalValue = words
                .map((w) => gimatria(w, method: gematriaMethod))
                .fold(0, (a, b) => a + b);
            if (useWithKolel) totalValue += words.length;

            if (totalValue == targetGimatria) {
              final path = _extractPathFromLines(lines, i);
              found.add(SearchResult(
                file: file.path,
                line: i + 1,
                text: _cleanHtml(words.join(' ')),
                path: path,
                verseNumber: verseNumber,
              ));
              if (found.length >= fileLimit) return found;
            }
          } else {
            final wordValues =
                words.map((w) => gimatria(w, method: gematriaMethod)).toList();
            for (int start = 0; start < words.length; start++) {
              int acc = 0;
              for (int offset = 0;
                  offset < maxPhraseWords && start + offset < words.length;
                  offset++) {
                acc += wordValues[start + offset];
                var finalValue = acc;
                if (useWithKolel) finalValue += (offset + 1);

                if (finalValue == targetGimatria) {
                  final phrase =
                      words.sublist(start, start + offset + 1).join(' ');
                  final path = _extractPathFromLines(lines, i);
                  final ctx = _extractContext(words, start, offset);
                  found.add(SearchResult(
                    file: file.path,
                    line: i + 1,
                    text: _cleanHtml(phrase),
                    path: path,
                    verseNumber: verseNumber,
                    contextBefore: ctx.$1,
                    contextAfter: ctx.$2,
                  ));
                  if (found.length >= fileLimit) return found;
                } else if (finalValue > targetGimatria) {
                  break;
                }
              }
            }
          }
        }
      } catch (e) {
        if (debug) {
          debugPrint('Skipped file ${file.path} due to read error: $e');
        }
        continue;
      }
      if (found.length >= fileLimit) break;
    }
    return found;
  }

  /// מחלץ הקשר (מילים לפני ואחרי) — מחזיר (contextBefore, contextAfter)
  static (String, String) _extractContext(
      List<String> words, int start, int offset) {
    const contextWordsCount = 3;
    final contextStart =
        start > contextWordsCount ? start - contextWordsCount : 0;
    final contextEnd = start + offset + 1 + contextWordsCount < words.length
        ? start + offset + 1 + contextWordsCount
        : words.length;

    final contextBefore = contextStart < start
        ? words.sublist(contextStart, start).join(' ')
        : '';
    final contextAfter = start + offset + 1 < contextEnd
        ? words.sublist(start + offset + 1, contextEnd).join(' ')
        : '';

    return (contextBefore, contextAfter);
  }

  static String _extractPathFromLines(List<String> lines, int currentIndex) {
    final Map<int, String> lastHeaderByLevel = {};
    final hTag = RegExp(r'<h([1-6])[^>]*>(.*?)</h\1>', dotAll: true);

    for (int i = currentIndex; i >= 0; i--) {
      if (lastHeaderByLevel.containsKey(1) &&
          lastHeaderByLevel.containsKey(2) &&
          lastHeaderByLevel.containsKey(3)) {
        break;
      }
      for (final match in hTag.allMatches(lines[i])) {
        try {
          final level = int.parse(match.group(1)!);
          final text = _cleanHtml(match.group(2)!);
          if (!lastHeaderByLevel.containsKey(level) && text.isNotEmpty) {
            lastHeaderByLevel[level] = text;
          }
        } catch (_) {}
      }
    }

    if (lastHeaderByLevel.isEmpty) return '';
    final sortedLevels = lastHeaderByLevel.keys.toList()..sort();
    return sortedLevels.map((l) => lastHeaderByLevel[l]!).join(', ');
  }

  static String _cleanHtml(String s) {
    var cleaned = s.replaceAll(RegExp(r'<[^>]*>'), '');
    cleaned = cleaned.replaceAll('&nbsp;', ' ');
    cleaned = cleaned.replaceAll('&thinsp;', ' ');
    cleaned = cleaned.replaceAll('&ensp;', ' ');
    cleaned = cleaned.replaceAll('&emsp;', ' ');
    cleaned = cleaned.replaceAll('&lt;', '<');
    cleaned = cleaned.replaceAll('&gt;', '>');
    cleaned = cleaned.replaceAll('&amp;', '&');
    cleaned = cleaned.replaceAll('&quot;', '"');
    cleaned = cleaned.replaceAll('&#39;', "'");
    cleaned = cleaned.replaceAll(RegExp(r'&[a-zA-Z]+;'), '');
    cleaned = cleaned.replaceAll(RegExp(r'&#\d+;'), '');
    cleaned = cleaned.replaceAll(RegExp(r'&#x[0-9a-fA-F]+;'), '');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
