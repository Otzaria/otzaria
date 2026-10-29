import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart';

import '../services/external_book_import.dart';

import '../models/book.dart';
import '../models/category.dart';
import '../models/line.dart';
import '../models/toc_entry.dart';
import '../models/topic.dart';
import '../database/repository/seforim_repository.dart';
import 'hebrew_text_utils.dart' as hebrew_text_utils;
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/file/toc_parser.dart'
    show TocParser, isTocExcludedHeadingLine;
import 'package:otzaria/text_book/utils/inline_notes_utils.dart'
    show stripInlineNotesFromHeading;

/// DatabaseGenerator is responsible for generating the Otzaria database from source files.
/// It processes directories and books to create a structured database.
class DatabaseGenerator {
  static final _log = Logger('DatabaseGenerator');

  /// The repository used to store the generated data
  final SeforimRepository repository;

  /// Callback for progress updates
  final void Function(double progress, String message)? onProgress;

  /// Cache of source name -> id from DB
  final Map<String, int> _sourceNameToId = {};

  /// Overall progress across books
  int _processedBooksCount = 0;

  DatabaseGenerator(this.repository, {this.onProgress});

  /// Processes a directory recursively, creating categories and books.
  ///
  /// [directory] The directory to process
  /// [parentCategoryId] The ID of the parent category, if any
  /// [level] The current level in the directory hierarchy
  Future<void> processDirectory(
    String directory,
    int? parentCategoryId,
    int level,
  ) async {
    final dir = Directory(directory);
    final entities = await dir.list().toList();
    final sortedEntities = entities
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    for (final entity in sortedEntities) {
      if (entity is Directory) {
        final categoryId = await createCategory(
          entity.path,
          parentCategoryId,
          level,
        );
        await processDirectory(entity.path, categoryId, level + 1);
      } else if (entity is File &&
          await isSupportedBookFileByContent(entity.path)) {
        if (parentCategoryId == null) {
          continue;
        }
        // כשל של קובץ בודד נרשם והסריקה ממשיכה (§76), גם כשאינו כשל המרה:
        // קובץ שננעל או נמחק באמצע הסריקה לא יבטל את ייבוא הספרייה כולה.
        try {
          await createAndProcessBook(entity.path, parentCategoryId);
        } on DocumentConversionException catch (e) {
          _logConversionFailure(entity.path, e);
        } catch (e, stackTrace) {
          _log.warning(
            'עיבוד הספר נכשל — הקובץ דולג: ${entity.path}',
            e,
            stackTrace,
          );
        }
      }
    }

    // Delete directory if it became empty after processing
    await _deleteIfEmpty(dir);
  }

  /// רושם כשל המרה עם כל מה שנדרש לאבחון מרחוק (§77): הנתיב, הפורמט
  /// שהסיומת הצהירה עליו, הפורמט שזוהה בפועל, וגרסת הממיר שרצה.
  void _logConversionFailure(String bookPath, DocumentConversionException e) {
    final declared = documentFormatFromExtension(bookPath);
    _log.warning(
      'המרת מסמך נכשלה — הספר דולג'
      ' | path=$bookPath'
      ' | declared=${declared?.extension}'
      ' | detected=${e.format?.extension}'
      // הפורמט שזוהה קודם למוצהר: ל-.wbk אין מנוע משל עצמו, ורק התוכן
      // מגלה איזו גרסת ממיר רצה בפועל.
      ' | converterVersion=${converterVersionFor(e.format ?? declared)}'
      ' | error=$e',
      e,
    );
  }

  /// Creates a category in the database.
  ///
  /// [path] The path representing the category
  /// [parentId] The ID of the parent category, if any
  /// [level] The level in the category hierarchy
  /// Returns the ID of the created category
  Future<int> createCategory(
    String categoryPath,
    int? parentId,
    int level,
  ) async {
    final title = path.basename(categoryPath);

    final category = Category(
      parentId: parentId,
      title: title,
      level: level,
    );

    final insertedId = await repository.insertCategory(category);
    return insertedId;
  }

  /// Creates a book in the database and processes its content.
  ///
  /// [bookPath] The path to the book file
  /// [categoryId] The ID of the category the book belongs to
  Future<void> createAndProcessBook(
    String bookPath,
    int categoryId, {
    bool insertContent = true,
    String? sourceName,
  }) async {
    try {
      final filename = path.basename(bookPath);
      final title = path.basenameWithoutExtension(filename);
      final sourceId = await _resolveSourceIdFor(
        bookPath,
        sourceName: sourceName,
      );

      // Extract file type from the file path
      final fileExtension = path.extension(bookPath).toLowerCase();
      final fileType = fileExtension.startsWith('.')
          ? fileExtension.substring(1)
          : fileExtension;
      final format = documentFormatFromExtension(bookPath);
      // רק פורמט ששורותיו נשמרות ב-DB מוותר על הנתיב; כל השאר file-backed
      // וחייב לשמור אותו כדי שאפשר יהיה להמיר בזמן קריאה.
      final storesLinesInDb = format?.canStoreLinesInDb ?? false;
      final targetFilePath = storesLinesInDb && insertContent ? null : bookPath;
      // PDFium גלובלי לתהליך: אין לפתוח PDF ב-isolate של הסנכרון.
      // ה-outline שלו נקרא בהוספת התיקייה.
      final processContent = insertContent || (format?.isTextual ?? false);

      // Check for duplicates in the same category with the same file type
      final existingBook = await repository
          .checkBookExistsInCategoryWithFileType(title, categoryId, fileType);
      if (existingBook != null) {
        if ((format?.isProductionSupported ?? false) && processContent) {
          if (insertContent) {
            await repository.clearBookContent(existingBook.id);
          }
          try {
            await processBookContent(bookPath, existingBook.id, insertContent);
          } catch (_) {
            if (insertContent) {
              await repository.clearBookContent(existingBook.id);
            }
            rethrow;
          }
          // Keep file stats and storage location in sync. If insertContent is true and it's a txt file, filePath becomes null.
          try {
            final file = File(bookPath);
            final stat = await file.stat();
            await repository.updateBookStorage(
              existingBook.id,
              targetFilePath,
              stat.size,
              stat.modified.millisecondsSinceEpoch,
            );
          } catch (e) {
            _log.warning(
              'Failed to update storage stats for file: $bookPath',
              e,
            );
          }
        } else {
          try {
            if (format?.isTextual ?? false) {
              // We're moving to file-backed storage, so clear lines from DB to save space, but preserve TOC
              await repository.deleteBookLines(existingBook.id);
              await repository.updateBookTotalLines(existingBook.id, 0);
            }
            final file = File(bookPath);
            final stat = await file.stat();
            await repository.updateBookStorage(
              existingBook.id,
              targetFilePath,
              stat.size,
              stat.modified.millisecondsSinceEpoch,
            );
          } catch (e) {
            _log.warning(
              'Failed to update storage stats for file: $bookPath',
              e,
            );
          }
        }

        if (existingBook.sourceId != sourceId) {
          await repository.updateBookSourceId(existingBook.id, sourceId);
        }

        _processedBooksCount++;
        onProgress?.call(
          _processedBooksCount.toDouble(),
          'עודכן ספר: $title',
        );
        return;
      }

      int? fileSize;
      int? lastModified;
      try {
        final file = File(bookPath);
        final stat = await file.stat();
        fileSize = stat.size;
        lastModified = stat.modified.millisecondsSinceEpoch;
      } catch (e) {
        _log.warning('Failed to get stats for external file: $bookPath', e);
      }

      final book = Book(
        id: 0,
        categoryId: categoryId,
        sourceId: sourceId,
        title: title,
        authors: [],
        pubPlaces: [],
        pubDates: [],
        heShortDesc: null,
        order: 999.0,
        topics: extractTopics(bookPath),
        isBaseBook: false,
        // רק פורמט ששורותיו נשמרות ב-DB מוותר על הנתיב; כל השאר file-backed.
        filePath: storesLinesInDb && insertContent ? null : bookPath,
        fileType: fileType,
        fileSize: fileSize,
        lastModified: lastModified,
      );

      final insertedBookId = await repository.insertBook(book);

      // Process content of the book
      if (processContent) {
        try {
          await processBookContent(bookPath, insertedBookId, insertContent);
        } catch (_) {
          // כל כשל משאיר את הספר ניתן לניסיון חוזר בסריקה הבאה.
          await repository.deleteBookCompletely(insertedBookId);
          rethrow;
        }
      } else {
        await repository.updateBookTotalLines(insertedBookId, 0);
      }

      // Book-level progress
      _processedBooksCount++;
      onProgress?.call(
        _processedBooksCount.toDouble(),
        'מעבד ספר: $title',
      );
    } catch (e, stackTrace) {
      final title = path.basenameWithoutExtension(bookPath);
      _log.severe(
        '❌ Critical error processing book: $title at $bookPath',
        e,
        stackTrace,
      );
      debugPrint('❌ Critical error processing book: $title');
      debugPrint('   Path: $bookPath');
      debugPrint('   Error: $e');
      debugPrint('   Stack trace: $stackTrace');
      rethrow; // Re-throw so FileSyncService can handle it
    }
  }

  /// Processes the content of a book, extracting lines and TOC entries.
  ///
  /// [bookPath] The path to the book file
  /// [bookId] The ID of the book in the database
  /// [storeLines] בספר חיצוני נשמר רק תוכן העניינים.
  Future<void> processBookContent(
    String bookPath,
    int bookId, [
    bool storeLines = true,
  ]) async {
    final format = documentFormatFromExtension(bookPath);
    if (format == null) {
      throw UnsupportedDocumentFormatException(path: bookPath);
    }

    if (!format.isTextual) {
      // Process PDF outline as TOC
      await _processPdfOutline(bookPath, bookId);
      await repository.updateBookTotalLines(bookId, 0);
      return;
    }

    // המרה בתוך ה-isolate — נמנעת העתקת buffer גדול בין isolates. בלי
    // תמונות: כאן נדרש רק מבנה השורות ותוכן העניינים. אחרת — מטמון ה-RAM.
    final lines = format.requiresConversion
        ? (await Isolate.run(
            () => convertDocumentFileSync(
              bookPath,
              format: format,
              embedImages: false,
            ),
          )).split('\n')
        : await readBookLines(bookPath);

    if (!storeLines) {
      final roots = TocParser.parseEntriesFromContent(lines.join('\n'));
      await repository.replaceExternalBookToc(
        bookId,
        externalBookTocEntries(roots),
      );
      return;
    }

    await processLinesWithTocEntries(bookId, lines);
    await repository.updateBookTotalLines(bookId, lines.length);
  }

  /// Processes PDF outline and inserts TOC entries into the database.
  Future<void> _processPdfOutline(String bookPath, int bookId) async {
    PdfDocument? document;
    try {
      // progressive: בלעדיו pdfium מפענח כל עמוד לפני ה-outline (שניות בסריקה).
      document = await PdfDocument.openFile(
        bookPath,
        useProgressiveLoading: true,
      );
      final outline = await document.loadOutline();

      if (outline.isEmpty) {
        _log.info('No outline found in PDF: $bookPath');
        return;
      }

      // Convert outline to TOC entries and insert them
      await _insertPdfOutlineNodes(outline, bookId, null, level: 1);

      _log.info('Processed PDF outline: $bookPath');
    } catch (e, stackTrace) {
      _log.warning('Failed to process PDF outline: $bookPath', e, stackTrace);
    } finally {
      // סגירת המסמך משחררת את ה-pdfrx worker היחיד (אחרת נשאר פתוח עד GC).
      await document?.dispose();
    }
  }

  /// Recursively inserts PDF outline nodes as TOC entries.
  Future<void> _insertPdfOutlineNodes(
    List<PdfOutlineNode> nodes,
    int bookId,
    int? parentId, {
    required int level,
  }) async {
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final pageNumber = node.dest?.pageNumber ?? 0;
      final isLastChild = i == nodes.length - 1;
      final hasChildren = node.children.isNotEmpty;

      // Create and insert the TOC entry
      final entry = TocEntry(
        bookId: bookId,
        parentId: parentId,
        text: node.title,
        level: level,
        lineIndex: pageNumber, // Using page number as lineIndex for PDFs
        isLastChild: isLastChild,
        hasChildren: hasChildren,
      );

      final insertedId = await repository.insertTocEntry(entry);

      // Process children recursively with the inserted ID as parent
      if (hasChildren) {
        await _insertPdfOutlineNodes(
          node.children,
          bookId,
          insertedId,
          level: level + 1,
        );
      }
    }
  }

  /// Reads book lines from file
  ///
  /// עובר בזיהוי הקידוד המלא: ספר שנשמר ב-ANSI עברית או ב-UTF-16 נכנס
  /// לבסיס הנתונים ולאינדקס כטקסט קריא, ולא כג'יבריש Latin-1.
  static Future<List<String>> readBookLines(String bookPath) async {
    final result = await readTextFileSmartDetailed(File(bookPath));
    if (result.lowConfidence) {
      debugPrint(
        '⚠️ זיהוי קידוד בוודאות נמוכה עבור $bookPath: '
        '${result.encoding.label} (${result.confidence.toStringAsFixed(2)}) — '
        '${result.detectionReason}',
      );
    }
    return result.text.split('\n');
  }

  /// Processes lines of a book, identifying and creating TOC entries.
  /// Lines are inserted in batches; TOC entries in one transaction, in order,
  /// so each child's parentId resolves to its parent's real DB id. After that,
  /// tocEntry.lineId is fixed via SQL (matching on lineIndex) and line_toc is
  /// rebuilt correctly.
  ///
  /// [bookId] The ID of the book in the database
  /// [lines] The lines of the book content

  Future<void> processLinesWithTocEntries(
    int bookId,
    List<String> lines,
  ) async {
    // Collect all TOC entry metadata in a single pass.
    // We use the entry's position in allTocEntries as its local ID.
    final allTocEntries = <TocEntryData>[];

    // level → local index of the most recent entry at that level (for parent tracking)
    final localParentStack = <int, int>{};

    // local-parent-index → [local child indices] (for isLastChild / hasChildren)
    final entriesByParent = <int?, List<int>>{};
    final currentReference = <String>[];

    const batchSize = 1000;
    final linesBatch = <Line>[];
    repository.lineContentWriter?.announceBook(
      bookId,
      lines.fold(0, (sum, line) => sum + line.length),
    );

    // heRef נגזר מ-currentReference ומשתנה רק בשורות כותרת — מחשבים פעם אחת
    // לכל שינוי כותרת ומשתמשים מחדש בשאר השורות.
    String? cachedHeRef;

    // ── PASS 1: Insert lines in batches, collect TOC structure ──────────────
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final level = detectHeaderLevel(line);

      if (level > 0) {
        // כותרת סוגרת את כל הענפים מרמתה ומטה; בלי זה h4 שאחרי h3 ואז h2
        // היה מקבל בטעות את ה-h3 הישן כהורה במקום את ה-h2.
        localParentStack.removeWhere((stackLevel, _) => stackLevel >= level);

        // cleanHtml יקר — מחשבים רק לשורות כותרת שבהן הטקסט נצרך.
        final plainText = cleanHtml(stripInlineNotesFromHeading(line));
        if (plainText.trim().isEmpty) {
          if (currentReference.length >= level) {
            currentReference.removeRange(level - 1, currentReference.length);
          }
        } else {
          // Find the nearest ancestor's local index
          int? parentLocalIdx;
          for (int l = level - 1; l >= 1; l--) {
            if (localParentStack.containsKey(l)) {
              parentLocalIdx = localParentStack[l];
              break;
            }
          }

          final localIdx = allTocEntries.length;
          allTocEntries.add(
            TocEntryData(
              id: localIdx,
              parentId: parentLocalIdx,
              level: level,
              text: plainText,
              lineIndex: lineIndex,
            ),
          );

          if (currentReference.length >= level) {
            currentReference.removeRange(level - 1, currentReference.length);
          }
          currentReference.add(plainText);

          localParentStack[level] = localIdx;
          entriesByParent.putIfAbsent(parentLocalIdx, () => []).add(localIdx);
        }

        cachedHeRef = currentReference.isEmpty
            ? null
            : currentReference.join(', ').trim();
        if (cachedHeRef != null && cachedHeRef.isEmpty) cachedHeRef = null;
      }

      linesBatch.add(
        Line(
          id: 0, // auto-assigned by SQLite
          bookId: bookId,
          lineIndex: lineIndex,
          content: line,
          heRef: cachedHeRef,
        ),
      );

      if (linesBatch.length >= batchSize) {
        await repository.insertLinesBatch(linesBatch);
        linesBatch.clear();
      }
    }

    if (linesBatch.isNotEmpty) {
      await repository.insertLinesBatch(linesBatch);
    }

    // אינדקס ההפניות של הספר — כך רזולוציה לרמת שורה עובדת גם בספרים אישיים.
    await repository.rebuildLineRefIndex(bookId);

    // ── PASS 2: Insert TOC entries in one transaction to get real DB IDs ──────
    // parentId/id are local indices; the repository resolves each child's parent
    // to its parent's real DB ID and returns the local→DB id mapping.
    final localIdxToDbId = await repository.insertGeneratedTocEntries(
      bookId,
      allTocEntries
          .map(
            (e) => TocEntry(
              id: e.id,
              bookId: bookId,
              parentId: e.parentId,
              text: e.text,
              level: e.level,
              lineIndex: e.lineIndex,
              lineId: null, // fixed by SQL below
              isLastChild: false,
              hasChildren: false,
            ),
          )
          .toList(),
    );

    // ── PASS 3: Fix lineId on tocEntries + rebuild line_toc via SQL ──────────
    if (allTocEntries.isNotEmpty) {
      await repository.updateTocEntryLineIdsByLineIndex(bookId);
      await repository.rebuildLineTocForBook(bookId);
    }

    // ── PASS 4: Mark hasChildren / isLastChild ────────────────────────────────
    final parentLocalIdxs = entriesByParent.keys.whereType<int>().toSet();

    final hasChildrenIds = parentLocalIdxs
        .map((idx) => localIdxToDbId[idx])
        .whereType<int>()
        .toList();

    final lastChildIds = entriesByParent.values
        .where((children) => children.isNotEmpty)
        .map((children) => localIdxToDbId[children.last])
        .whereType<int>()
        .toList();

    if (hasChildrenIds.isNotEmpty) {
      await repository.bulkUpdateTocEntryHasChildren(hasChildrenIds, true);
    }
    if (lastChildIds.isNotEmpty) {
      await repository.bulkUpdateTocEntryIsLastChild(lastChildIds, true);
    }
  }

  /// Extracts topics from the file path.
  /// Topics are derived from the directory structure.
  ///
  /// [path] The path to the book file
  /// Returns a list of topics extracted from the path
  List<Topic> extractTopics(String bookPath) {
    // Extract topics from the path
    final parts = path.split(bookPath);
    final topicNames = parts
        .take(parts.length - 1)
        .toList()
        .reversed
        .take(2)
        .toList()
        .reversed;

    return topicNames.map((name) => Topic(name: name)).toList();
  }

  /// Deletes a directory if it is empty.
  Future<void> _deleteIfEmpty(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      if (await dir.list().isEmpty) {
        await dir.delete();
        _log.info('Deleted empty directory: ${dir.path}');
      }
    } catch (e) {
      // Ignore deletion mistakes (e.g. permissions)
    }
  }

  /// Resolves and caches the source id of [sourceName] (`Personal` by default).
  Future<int> _resolveSourceIdFor(
    String filePath, {
    String? sourceName,
  }) async {
    final resolvedSourceName = sourceName ?? 'Personal';
    final cached = _sourceNameToId[resolvedSourceName];
    if (cached != null) return cached;
    final id = await repository.insertSource(resolvedSourceName, -1);
    _sourceNameToId[resolvedSourceName] = id;
    return id;
  }
}

/// Structure to store TOC entry data during processing
class TocEntryData {
  final int id;
  final int? parentId;
  final int level;
  final String text;
  final int lineIndex;

  const TocEntryData({
    required this.id,
    this.parentId,
    required this.level,
    required this.text,
    required this.lineIndex,
  });
}

/// Utility functions for HTML and text processing
String cleanHtml(String html) {
  // Simple HTML tag removal - replace with space to avoid concatenating words
  final tagRegex = RegExp(r'<[^>]*>');
  final cleaned = html.replaceAll(tagRegex, ' ');
  // Clean up multiple spaces and trim
  return hebrew_text_utils.removeNikud(
    cleaned.replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

int detectHeaderLevel(String line) {
  // הורדת אותיות רק לשורה שנפתחת ב-<h — שורות הטקסט ארוכות ורובן כאלה.
  if (!line.startsWith('<h') && !line.startsWith('<H')) return 0;
  final lowerLine = line.toLowerCase();
  final int level;
  if (lowerLine.startsWith('<h1')) {
    level = 1;
  } else if (lowerLine.startsWith('<h2')) {
    level = 2;
  } else if (lowerLine.startsWith('<h3')) {
    level = 3;
  } else if (lowerLine.startsWith('<h4')) {
    level = 4;
  } else if (lowerLine.startsWith('<h5')) {
    level = 5;
  } else if (lowerLine.startsWith('<h6')) {
    level = 6;
  } else {
    return 0;
  }
  // כותרת שהודרה מתוכן העניינים (תוכן עניינים מוטמע קובע) — אינה נספרת.
  if (isTocExcludedHeadingLine(lowerLine)) return 0;
  return level;
}
