import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sql/query_loader.dart';
import 'package:otzaria/migration/models/toc_entry.dart';

/// יעד סריקה יחיד עבור ה-isolate: נתיב DB ומזהי הספרים שבתוכו.
/// מכיל ערכים ניתנים-להעברה בלבד, כדי שיוכל לחצות את גבול ה-isolate.
class _ScanTarget {
  final String dbPath;
  final List<int> bookIds;

  const _ScanTarget(this.dbPath, this.bookIds);
}

class SearchResult {
  final String file;
  final int line;
  final String text;
  final String path; // הנתיב ההיררכי (כותרות)
  final String verseNumber; // מספר הפסוק
  final String contextBefore; // מילים לפני התוצאה
  final String contextAfter; // מילים אחרי התוצאה

  const SearchResult({
    required this.file,
    required this.line,
    required this.text,
    this.path = '',
    this.verseNumber = '',
    this.contextBefore = '',
    this.contextAfter = '',
  });
}

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

  // RegExp לשימוש חוזר: קומפילציה חד-פעמית במקום פר-שורה בלולאת הסריקה החמה.
  static final RegExp _headerTagRe = RegExp(r'<h[1-6][^>]*>');
  static final RegExp _leadingVerseCaptureRe = RegExp(r'^\(([^\)]+)\)');
  static final RegExp _leadingVersePrefixRe = RegExp(r'^\([^\)]+\)\s*');
  static final RegExp _curlyBracesRe = RegExp(r'\{[^\}]*\}');
  static final RegExp _whitespaceRe = RegExp(r'\s+');
  static final RegExp _htmlTagRe = RegExp(r'<[^>]*>');
  static final RegExp _namedEntityRe = RegExp(r'&[a-zA-Z]+;');
  static final RegExp _decimalEntityRe = RegExp(r'&#\d+;');
  static final RegExp _hexEntityRe = RegExp(r'&#x[0-9a-fA-F]+;');
  static final RegExp _headingCaptureRe = RegExp(
    r'<h([1-6])[^>]*>(.*?)</h\1>',
    dotAll: true,
  );

  static int gimatria(String text, {String method = 'regular'}) {
    Map<String, int> values;
    switch (method) {
      case 'small':
        values = _smallValues;
        break;
      case 'finalLetters':
        values = _finalLettersValues;
        break;
      case 'regular':
      default:
        values = _regularValues;
        break;
    }

    var sum = 0;
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      final v = values[ch];
      if (v != null) sum += v;
    }
    return sum;
  }

  /// Search in SQLite database for phrases whose gimatria equals [targetGimatria].
  /// Falls back to file search across all [folders] if database is not available
  /// or fails mid-query. [maxPhraseWords] bounds phrase length to avoid explosion.
  static Future<List<SearchResult>> searchInFiles(
    List<String> folders,
    int targetGimatria, {
    int maxPhraseWords = 8,
    int fileLimit = 1000,
    bool wholeVerseOnly = false,
    bool debug = false,
    String gematriaMethod = 'regular',
    bool useWithKolel = false,
    List<String>? bookTitles,
  }) async {
    // initialize אקטיבי (לא isInitialized פסיבי): חיפוש בזמן שה-DB לא מאותחל
    // (למשל sync פעיל) חייב להמתין ולא ליפול ל-fallback ריק = "אין תוצאות".
    final dbProvider = SqliteDataProvider.instance;
    try {
      await dbProvider.initialize();
      if (dbProvider.isInitialized) {
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
      }
    } catch (e) {
      if (debug) {
        debugPrint('Database search failed, falling back to file search: $e');
      }
      // Fall through to file search across all folders
    }

    // Fallback to file search across all folders.
    // חלוקת ה-budget בין התיקיות כדי לכבד את fileLimit כסך כולל,
    // ולא להשקיע עבודה מיותרת בתיקיות הבאות אחרי שכבר נצברו תוצאות.
    final List<SearchResult> all = [];
    for (final folder in folders) {
      final remaining = fileLimit - all.length;
      if (remaining <= 0) break;
      final results = await _searchInFilesLegacy(
        folder,
        targetGimatria,
        maxPhraseWords: maxPhraseWords,
        fileLimit: remaining,
        wholeVerseOnly: wholeVerseOnly,
        debug: debug,
        gematriaMethod: gematriaMethod,
        useWithKolel: useWithKolel,
      );
      all.addAll(results);
    }
    return all;
  }

  /// Search in SQLite database for phrases whose gimatria equals [targetGimatria]
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
    final dbProvider = SqliteDataProvider.instance;
    final repository = dbProvider.repository;

    if (repository == null) {
      throw Exception('Database repository not initialized');
    }

    // פתרון הספרים נשען על ה-singletons של הספרייה ולכן חייב לרוץ כאן;
    // ל-isolate מועברים רק נתיבי DB ומזהי ספרים.
    final bookIdsByDbPath = <String, List<int>>{};
    if (bookTitles != null && bookTitles.isNotEmpty) {
      for (final title in bookTitles) {
        final resolvedBook = await BookDatabaseResolver.resolveBook(
          title: title,
        );
        if (resolvedBook != null) {
          bookIdsByDbPath
              .putIfAbsent(
                resolvedBook.repository.database.path,
                () => <int>[],
              )
              .add(resolvedBook.book.id);
        }
      }
    } else {
      // ⚠️ ללא bookTitles - סריקת כל הספרים בספרייה (כבד מאוד!).
      // המסך אמור תמיד להעביר bookTitles כדי לתחום לתנ"ך.
      final allBooks = await repository.getAllBooks();
      bookIdsByDbPath[repository.database.path] = allBooks
          .map((b) => b.id)
          .toList();
    }

    if (debug) {
      final totalBooks = bookIdsByDbPath.values.fold<int>(
        0,
        (sum, ids) => sum + ids.length,
      );
      debugPrint('Searching in $totalBooks books from database');
    }

    return _scanInIsolate(
      [
        for (final entry in bookIdsByDbPath.entries)
          _ScanTarget(entry.key, entry.value),
      ],
      targetGimatria,
      maxPhraseWords: maxPhraseWords,
      fileLimit: fileLimit,
      wholeVerseOnly: wholeVerseOnly,
      gematriaMethod: gematriaMethod,
      useWithKolel: useWithKolel,
    );
  }

  /// עוטף את [Isolate.run] במתודה נפרדת: ה-closure לוכד את כל ה-scope שבו
  /// נוצר, ולכן הוא חייב לחיות במקום שכל המשתנים בו ניתנים להעברה.
  static Future<List<SearchResult>> _scanInIsolate(
    List<_ScanTarget> targets,
    int targetGimatria, {
    required int maxPhraseWords,
    required int fileLimit,
    required bool wholeVerseOnly,
    required String gematriaMethod,
    required bool useWithKolel,
  }) {
    // חייב להיבנות כאן: rootBundle אינו זמין ב-isolate, ולכן ה-SQL נשלח
    // כ-snapshot מוכן במקום להיטען שם מחדש.
    final queryCache = QueryLoader.cacheSnapshot;
    return Isolate.run(
      () => _scanTargets(
        targets,
        targetGimatria,
        queryCache: queryCache,
        maxPhraseWords: maxPhraseWords,
        fileLimit: fileLimit,
        wholeVerseOnly: wholeVerseOnly,
        gematriaMethod: gematriaMethod,
        useWithKolel: useWithKolel,
      ),
    );
  }

  /// הסריקה עצמה — רצה ב-isolate נפרד ופותחת חיבור read-only משלה לכל DB,
  /// מכיוון שחיבור sqlite אינו ניתן להעברה בין isolates.
  static Future<List<SearchResult>> _scanTargets(
    List<_ScanTarget> targets,
    int targetGimatria, {
    required Map<String, Map<String, String>> queryCache,
    required int maxPhraseWords,
    required int fileLimit,
    required bool wholeVerseOnly,
    required String gematriaMethod,
    required bool useWithKolel,
  }) async {
    // ה-statics אינם עוברים ל-isolate חדש; בלי זה ה-DAOs נכשלים על
    // QueryLoader לא-מאותחל.
    QueryLoader.seedCache(queryCache);

    final List<SearchResult> found = [];

    for (final target in targets) {
      final database = MyDatabase.withPath(target.dbPath, readOnly: true);
      final searchRepository = SeforimRepository(database);

      try {
        // חיבור טרי מתחיל עם ברירות המחדל של SQLite; בלי זה אין mmap
        // והמטמון קטן פי-25 מזה שה-main isolate מקבל.
        await searchRepository.ensureInitialized();

        // Search in each book
        for (final bookId in target.bookIds) {
          if (found.length >= fileLimit) break;

          final book = await searchRepository.getBook(bookId);
          if (book == null) continue;

          // Get all lines for this book
          final lines = await searchRepository.getLines(
            bookId,
            0,
            book.totalLines - 1,
          );

          // Get TOC entries for path extraction
          final tocEntries = await searchRepository.getBookTocs(bookId);

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            final content = line.content;

            // Skip header lines (h1-h6)
            if (_headerTagRe.hasMatch(content)) {
              continue;
            }

            // Extract verse number from parentheses at start of line
            final verseMatch = _leadingVerseCaptureRe.firstMatch(content);
            final verseNumber = verseMatch?.group(1) ?? '';

            // Remove verse number parentheses from line
            var cleanLine = content.replaceFirst(_leadingVersePrefixRe, '');

            // Remove curly braces with content
            cleanLine = cleanLine.replaceAll(_curlyBracesRe, '');

            // Clean HTML tags
            final lineWithoutHtml = _cleanHtml(cleanLine);

            final words = lineWithoutHtml
                .split(_whitespaceRe)
                .where((w) => w.trim().isNotEmpty)
                .toList();
            if (words.isEmpty) continue;

            // Search for whole verse only
            if (wholeVerseOnly) {
              var totalValue = words
                  .map((w) => gimatria(w, method: gematriaMethod))
                  .fold(0, (a, b) => a + b);

              if (useWithKolel) {
                totalValue += words.length;
              }

              if (totalValue == targetGimatria) {
                final phrase = words.join(' ');
                final path = extractPathFromTocEntries(
                  currentLineIndex: line.lineIndex,
                  bookTitle: book.title,
                  tocEntries: tocEntries,
                );
                final cleanPhrase = _cleanHtml(phrase);
                found.add(
                  SearchResult(
                    file: book.title,
                    line: line.lineIndex + 1,
                    text: cleanPhrase,
                    path: path,
                    verseNumber: verseNumber,
                    contextBefore: '',
                    contextAfter: '',
                  ),
                );
                if (found.length >= fileLimit) return found;
              }
            } else {
              // Regular search - any phrase
              final wordValues = words
                  .map((w) => gimatria(w, method: gematriaMethod))
                  .toList();
              for (int start = 0; start < words.length; start++) {
                int acc = 0;
                for (
                  int offset = 0;
                  offset < maxPhraseWords && start + offset < words.length;
                  offset++
                ) {
                  acc += wordValues[start + offset];

                  var finalValue = acc;
                  if (useWithKolel) {
                    finalValue += (offset + 1);
                  }

                  if (finalValue == targetGimatria) {
                    final phrase = words
                        .sublist(start, start + offset + 1)
                        .join(' ');
                    final path = extractPathFromTocEntries(
                      currentLineIndex: line.lineIndex,
                      bookTitle: book.title,
                      tocEntries: tocEntries,
                    );
                    final cleanPhrase = _cleanHtml(phrase);

                    // Extract context - 2-3 words before and after
                    final contextWordsCount = 3;
                    final contextStart = start > contextWordsCount
                        ? start - contextWordsCount
                        : 0;
                    final contextEnd =
                        start + offset + 1 + contextWordsCount < words.length
                        ? start + offset + 1 + contextWordsCount
                        : words.length;

                    final contextBefore = contextStart < start
                        ? words.sublist(contextStart, start).join(' ')
                        : '';
                    final contextAfter = start + offset + 1 < contextEnd
                        ? words
                              .sublist(start + offset + 1, contextEnd)
                              .join(' ')
                        : '';

                    found.add(
                      SearchResult(
                        file: book.title,
                        line: line.lineIndex + 1,
                        text: cleanPhrase,
                        path: path,
                        verseNumber: verseNumber,
                        contextBefore: contextBefore,
                        contextAfter: contextAfter,
                      ),
                    );
                    if (found.length >= fileLimit) return found;
                  } else if (finalValue > targetGimatria) {
                    break;
                  }
                }
              }
            }
          }
        }
      } finally {
        database.close();
      }
    }
    return found;
  }

  /// Extract hierarchical path from TOC entries using the line index.
  ///
  /// This avoids relying on a direct line_toc lookup, which may resolve to the
  /// root book entry and omit the chapter heading for Tanach books.
  @visibleForTesting
  static String extractPathFromTocEntries({
    required int currentLineIndex,
    required String bookTitle,
    required List<TocEntry> tocEntries,
  }) {
    if (tocEntries.isEmpty) {
      return '';
    }

    TocEntry? bestEntry;
    for (final entry in tocEntries) {
      final lineIndex = entry.lineIndex;
      if (lineIndex == null || lineIndex > currentLineIndex) {
        continue;
      }

      if (bestEntry == null ||
          lineIndex > bestEntry.lineIndex! ||
          (lineIndex == bestEntry.lineIndex! &&
              entry.level > bestEntry.level)) {
        bestEntry = entry;
      }
    }

    if (bestEntry == null) {
      return '';
    }

    final tocEntriesById = {
      for (final entry in tocEntries) entry.id: entry,
    };

    final pathParts = <String>[];
    TocEntry? current = bestEntry;
    while (current != null) {
      final text = _cleanHtml(current.text);
      if (text.isNotEmpty && text != bookTitle) {
        pathParts.insert(0, text);
      }

      final parentId = current.parentId;
      current = parentId == null ? null : tocEntriesById[parentId];
    }

    if (pathParts.isEmpty) {
      return bookTitle;
    }

    return <String>[bookTitle, ...pathParts].join(', ');
  }

  /// Legacy file-based search (fallback)
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
        // קריאה בטקסט UTF-8 (עם חלופה לקבצים לא תקינים)
        final String content = await file.readAsString(encoding: utf8);
        final lines = const LineSplitter().convert(content);

        if (debug) {
          // הדפס קובץ ונקודות בדיקה מהירות
          debugPrint('Scanning file: ${file.path} (lines: ${lines.length})');
        }

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];

          // דילוג על שורות כותרות (h1-h6)
          if (_headerTagRe.hasMatch(line)) {
            continue;
          }

          // חילוץ מספר הפסוק מהסוגריים בתחילת השורה
          final verseMatch = _leadingVerseCaptureRe.firstMatch(line);
          final verseNumber = verseMatch?.group(1) ?? '';

          // הסרת הסוגריים עם מספר הפסוק מהשורה
          var cleanLine = line.replaceFirst(_leadingVersePrefixRe, '');

          // הסרת סוגריים מסולסלות עם תוכן
          cleanLine = cleanLine.replaceAll(_curlyBracesRe, '');

          // ניקוי תגיות HTML מהשורה
          final lineWithoutHtml = _cleanHtml(cleanLine);

          final words = lineWithoutHtml
              .split(_whitespaceRe)
              .where((w) => w.trim().isNotEmpty)
              .toList();
          if (words.isEmpty) continue;

          // אם מחפשים פסוק שלם, בדוק את כל השורה
          if (wholeVerseOnly) {
            var totalValue = words
                .map((w) => gimatria(w, method: gematriaMethod))
                .fold(0, (a, b) => a + b);

            // הוספת הכולל אם נדרש
            if (useWithKolel) {
              totalValue += words.length;
            }

            if (totalValue == targetGimatria) {
              final phrase = words.join(' ');
              final path = _extractPathFromLines(lines, i);
              final cleanPhrase = _cleanHtml(phrase);
              found.add(
                SearchResult(
                  file: file.path,
                  line: i + 1,
                  text: cleanPhrase,
                  path: path,
                  verseNumber: verseNumber,
                  contextBefore: '',
                  contextAfter: '',
                ),
              );
              if (found.length >= fileLimit) return found;
            }
          } else {
            // חיפוש רגיל - כל קטע
            final wordValues = words
                .map((w) => gimatria(w, method: gematriaMethod))
                .toList();
            for (int start = 0; start < words.length; start++) {
              int acc = 0;
              for (
                int offset = 0;
                offset < maxPhraseWords && start + offset < words.length;
                offset++
              ) {
                acc += wordValues[start + offset];

                // הוספת הכולל אם נדרש
                var finalValue = acc;
                if (useWithKolel) {
                  finalValue += (offset + 1); // מספר המילים בקטע הנוכחי
                }

                if (finalValue == targetGimatria) {
                  final phrase = words
                      .sublist(start, start + offset + 1)
                      .join(' ');
                  final path = _extractPathFromLines(lines, i);
                  // ניקוי תגיות HTML מהטקסט
                  final cleanPhrase = _cleanHtml(phrase);

                  // חילוץ ההקשר - 2-3 מילים לפני ואחרי
                  final contextWordsCount = 3;
                  final contextStart = start > contextWordsCount
                      ? start - contextWordsCount
                      : 0;
                  final contextEnd =
                      start + offset + 1 + contextWordsCount < words.length
                      ? start + offset + 1 + contextWordsCount
                      : words.length;

                  final contextBefore = contextStart < start
                      ? words.sublist(contextStart, start).join(' ')
                      : '';
                  final contextAfter = start + offset + 1 < contextEnd
                      ? words.sublist(start + offset + 1, contextEnd).join(' ')
                      : '';

                  found.add(
                    SearchResult(
                      file: file.path,
                      line: i + 1,
                      text: cleanPhrase,
                      path: path,
                      verseNumber: verseNumber,
                      contextBefore: contextBefore,
                      contextAfter: contextAfter,
                    ),
                  );
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

  /// מחלץ את הנתיב ההיררכי (כותרות) מהשורות שלפני המיקום הנוכחי
  static String _extractPathFromLines(List<String> lines, int currentIndex) {
    final Map<int, String> lastHeaderByLevel = {};

    // סריקה אחורה מהמיקום הנוכחי
    for (int i = currentIndex; i >= 0; i--) {
      // אם מצאנו כותרות מספיק, אפשר לעצור
      if (lastHeaderByLevel.containsKey(1) &&
          lastHeaderByLevel.containsKey(2) &&
          lastHeaderByLevel.containsKey(3)) {
        break;
      }

      final line = lines[i];
      for (final match in _headingCaptureRe.allMatches(line)) {
        try {
          final level = int.parse(match.group(1)!);
          final text = _cleanHtml(match.group(2)!);

          // שומרים רק את הכותרת הראשונה שנמצאה עבור כל רמה
          if (!lastHeaderByLevel.containsKey(level) && text.isNotEmpty) {
            lastHeaderByLevel[level] = text;
          }
        } catch (_) {
          // התעלם אם תגית ה-h אינה תקינה
        }
      }
    }

    if (lastHeaderByLevel.isEmpty) return '';

    // הרכבת הנתיב לפי סדר הרמות
    final sortedLevels = lastHeaderByLevel.keys.toList()..sort();
    final parts = <String>[];
    for (final level in sortedLevels) {
      parts.add(lastHeaderByLevel[level]!);
    }

    return parts.join(', ');
  }

  /// ניקוי תגיות HTML ו-HTML entities
  static String _cleanHtml(String s) {
    // הסרת תגיות HTML
    var cleaned = s.replaceAll(_htmlTagRe, '');

    // הסרת HTML entities נפוצות
    cleaned = cleaned.replaceAll('&nbsp;', ' ');
    cleaned = cleaned.replaceAll('&thinsp;', ' ');
    cleaned = cleaned.replaceAll('&ensp;', ' ');
    cleaned = cleaned.replaceAll('&emsp;', ' ');
    cleaned = cleaned.replaceAll('&lt;', '<');
    cleaned = cleaned.replaceAll('&gt;', '>');
    cleaned = cleaned.replaceAll('&amp;', '&');
    cleaned = cleaned.replaceAll('&quot;', '"');
    cleaned = cleaned.replaceAll('&#39;', "'");

    // הסרת כל HTML entities שנשארו (פורמט &#xxxx; או &name;)
    cleaned = cleaned.replaceAll(_namedEntityRe, '');
    cleaned = cleaned.replaceAll(_decimalEntityRe, '');
    cleaned = cleaned.replaceAll(_hexEntityRe, '');

    // ניקוי רווחים מיותרים
    return cleaned.replaceAll(_whitespaceRe, ' ').trim();
  }
}
