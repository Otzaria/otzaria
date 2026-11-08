import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/topic.dart';
import 'package:otzaria/models/books.dart' as reader;
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:path/path.dart' as path;

/// ספר חיצוני מוכן לכתיבה, ללא חיבור מסד או משאב פלטפורמה.
class PreparedExternalBook {
  const PreparedExternalBook({
    required this.filePath,
    required this.title,
    required this.fileType,
    required this.fileSize,
    required this.lastModified,
    this.tocEntries,
  });

  final String filePath;
  final String title;
  final String fileType;
  final int fileSize;
  final int lastModified;

  /// null משמר TOC קיים; רשימה ריקה מוחקת כותרות שכבר אינן בקובץ.
  final List<TocEntry>? tocEntries;

  /// מיועדת ל-worker: ההמרה ופריסת הכותרות כבדות.
  static Future<PreparedExternalBook> prepare(
    String filePath,
    FileStat stat,
    DocumentFormat format,
  ) async {
    return PreparedExternalBook(
      filePath: filePath,
      title: path.basenameWithoutExtension(filePath),
      fileType: format.extension,
      fileSize: stat.size,
      lastModified: stat.modified.millisecondsSinceEpoch,
      tocEntries: format.isTextual
          ? externalBookTocEntries(
              TocParser.parseEntriesFromContent(
                await convertDocumentFile(filePath, embedImages: false),
              ),
            )
          : null,
    );
  }

  /// חותמת הקובץ מתעדכנת רק לאחר הצלחת החלפת ה-TOC.
  Future<void> update(
    SeforimRepository repository,
    int bookId, {
    int? sourceId,
  }) async {
    if (tocEntries != null) {
      await repository.replaceExternalBookToc(bookId, tocEntries!);
    }
    await repository.updateBookStorage(
      bookId,
      filePath,
      fileSize,
      lastModified,
    );
    if (sourceId != null) {
      await repository.updateBookSourceId(bookId, sourceId);
    }
  }

  /// הכנסת ספר וכותרותיו אטומית; כשל בהשלמת המטא-נתונים מאפשר ניסיון חוזר.
  Future<int> insert(
    SeforimRepository repository, {
    required int categoryId,
    required int sourceId,
    bool isPersonal = false,
    List<TocEntry>? pdfTocEntries,
    List<Topic> topics = const [],
  }) async {
    final id = await repository.insertExternalContentBook(
      categoryId: categoryId,
      title: title,
      filePath: filePath,
      fileType: fileType,
      fileSize: fileSize,
      lastModified: lastModified,
      isPersonal: isPersonal,
      tocEntries: tocEntries ?? pdfTocEntries,
      sourceId: sourceId,
    );
    try {
      for (final topic in topics) {
        await repository.linkTopicToBook(
          await repository.insertTopic(topic.name),
          id,
        );
      }
    } catch (_) {
      await repository.deleteBookCompletely(id);
      rethrow;
    }
    return id;
  }
}

/// מכינה ספר בלי לחסום את ה-isolate הקורא, ובלי לפתוח PDFium.
Future<PreparedExternalBook> prepareExternalBookInIsolate(
  String filePath,
  FileStat stat,
  DocumentFormat format,
) async {
  if (!format.isTextual) {
    return PreparedExternalBook.prepare(filePath, stat, format);
  }
  return Isolate.run(
    () => PreparedExternalBook.prepare(filePath, stat, format),
  );
}

/// מזהים מקומיים בסדר קדם: ההורים נכתבים לפני ילדיהם.
List<TocEntry> externalBookTocEntries(List<reader.TocEntry> roots) {
  final entries = <TocEntry>[];
  void append(List<reader.TocEntry> nodes, int? parentId) {
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final id = entries.length + 1;
      entries.add(
        TocEntry(
          id: id,
          bookId: 0,
          parentId: parentId,
          text: node.text,
          level: node.level,
          lineIndex: node.index,
          hasChildren: node.children.isNotEmpty,
          isLastChild: i == nodes.length - 1,
        ),
      );
      append(node.children, id);
    }
  }

  append(roots, null);
  return entries;
}

/// פותרת שרשרת קטגוריות משותפת להוספה ולרענון של תיקיות אישיות.
Future<({int categoryId, int categoriesCreated})> findOrCreateBookCategoryChain(
  SeforimRepository repository,
  List<String> categoryNames,
) async {
  int? parentId;
  var categoriesCreated = 0;
  for (var level = 0; level < categoryNames.length; level++) {
    final title = categoryNames[level];
    final existing = await repository.getCategoryByTitleAndParent(
      title,
      parentId,
    );
    parentId =
        existing?.id ??
        await repository.insertCategory(
          Category(title: title, parentId: parentId, level: level),
        );
    if (existing == null) categoriesCreated++;
  }
  return (categoryId: parentId!, categoriesCreated: categoriesCreated);
}
