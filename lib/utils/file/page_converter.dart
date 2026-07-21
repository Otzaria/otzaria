import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/pdf_anchor_cache_entry.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/page_map_builder.dart';
import 'package:pdfrx/pdfrx.dart';

// A cache for the generated page maps to avoid rebuilding them on every conversion.
final _pageMapCache = <String, PageMap>{};

/// TTL לרשומות מטמון העוגנים המתמיד — נגזר מהמדיניות של מטמון ה-outline.
const _persistentAnchorCacheTtl = Duration(days: 90);

/// Converts a text book page index to the corresponding PDF page number.
///
/// This function uses a cached, anchor-based map with local interpolation for accuracy and performance.
/// [pdfBook] - מהדורת ה-PDF אם כבר אותרה אצל הקורא; חוסך סריקה מלאה של העץ.
Future<int?> textToPdfPage(
  TextBook textBook,
  int textIndex, {
  PdfBook? pdfBook,
}) async {
  pdfBook ??=
      (await DataRepository.instance.library).getCompanionBook(
            textBook,
            PdfBook,
          )
          as PdfBook?;
  if (pdfBook == null) {
    return null;
  }

  final key = '${pdfBook.path}::${textBook.title}';
  final cached = _pageMapCache[key];
  if (cached != null) {
    if (!cached.hasReliableAnchors) {
      return null;
    }
    return cached.textToPdf(textIndex);
  }

  try {
    final anchorsPdf = await _getPdfAnchors(pdfBook.path);
    final map = _pageMapCache[key] ??= await _buildPageMap(
      pdfBook,
      anchorsPdf,
      textBook,
    );
    if (!map.hasReliableAnchors) {
      return null;
    }

    return map.textToPdf(textIndex);
  } catch (e, st) {
    // null = אין מיפוי (הקוראים מסתמכים על כך). נבלע כאן גם PDF מוגן
    // בסיסמה (לגיטימי) וגם כשל בבניית המפה — הלוג מבחין ביניהם.
    debugPrint(
      '[PageConverter] textToPdfPage failed for '
      '"${pdfBook.path}": $e\n$st',
    );
    return null;
  }
}

/// מחזיר את עוגני ה-outline של [pdfPath] — מהמטמון המתמיד (cache.db) אם
/// הרשומה תואמת את מטא-נתוני הקובץ, אחרת בפתיחת ה-PDF (החלק הכבד, 1-2ש')
/// ושמירה למטמון לפעם הבאה.
Future<List<({int page, String ref})>> _getPdfAnchors(String pdfPath) async {
  final metadata = await _readPdfFileMetadata(pdfPath);
  final repository = await _anchorCacheRepository();

  if (repository != null && metadata != null) {
    try {
      final entry = await repository.getPdfAnchorCacheEntry(pdfPath);
      if (entry != null) {
        final matchesCurrentFile =
            entry.fileSize == metadata.size &&
            entry.lastModified == metadata.lastModified;
        if (matchesCurrentFile) {
          try {
            final anchors = entry.decodeAnchors();
            unawaited(
              repository
                  .touchPdfAnchorCacheEntry(pdfPath, _nowMillis())
                  .catchError((_) {}),
            );
            return anchors;
          } on FormatException {
            // רשומה מגרסת סכמה ישנה — self-healing: מחיקה ובנייה מחדש.
          }
        }
        // הקובץ השתנה או שהרשומה אינה ניתנת לפענוח — נבנה מחדש מה-PDF.
        await repository.deletePdfAnchorCacheEntry(pdfPath);
      }
    } catch (e) {
      debugPrint('[PageConverter] anchor cache read failed for $pdfPath: $e');
    }
  }

  PdfDocument? doc;
  final List<({int page, String ref})> anchors;
  try {
    doc = await PdfDocument.openFile(pdfPath);
    anchors = collectPdfAnchors(await doc.loadOutline());
  } finally {
    // המתנה לשחרור בפועל — הטאב הסופי עשוי לפתוח מיד את אותו PDF, וה-worker
    // היחיד של pdfrx חייב להשתחרר מהמסמך הזה קודם.
    await doc?.dispose();
  }

  // גם רשימה ריקה נשמרת — PDF ללא outline לא ייפתח וייסרק מחדש בכל המרה.
  if (repository != null && metadata != null) {
    unawaited(_savePdfAnchors(repository, pdfPath, metadata, anchors));
  }
  return anchors;
}

Future<void> _savePdfAnchors(
  SeforimRepository repository,
  String pdfPath,
  ({int size, int lastModified}) metadata,
  List<({int page, String ref})> anchors,
) async {
  try {
    final now = _nowMillis();
    await repository.upsertPdfAnchorCacheEntry(
      PdfAnchorCacheEntry(
        filePath: pdfPath,
        fileSize: metadata.size,
        lastModified: metadata.lastModified,
        anchorsJson: PdfAnchorCacheEntry.encode(anchors),
        createdAt: now,
        accessedAt: now,
      ),
    );
    await repository.prunePdfAnchorCacheAccessedBefore(
      now - _persistentAnchorCacheTtl.inMilliseconds,
    );
  } catch (e) {
    debugPrint('[PageConverter] anchor cache write failed for $pdfPath: $e');
  }
}

Future<({int size, int lastModified})?> _readPdfFileMetadata(
  String pdfPath,
) async {
  try {
    final stat = await File(pdfPath).stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return (
      size: stat.size,
      lastModified: stat.modified.millisecondsSinceEpoch,
    );
  } catch (_) {
    return null;
  }
}

/// cache.db הכתיב (ולא seforim.db שנפתח read-only). null = אין מטמון מתמיד,
/// וההמרה עובדת ישירות מול ה-PDF כמקודם.
Future<SeforimRepository?> _anchorCacheRepository() async {
  try {
    return await CacheDatabaseHolder.instance.repository;
  } catch (e) {
    debugPrint('[PageConverter] cache.db unavailable for anchor cache: $e');
    return null;
  }
}

int _nowMillis() => DateTime.now().millisecondsSinceEpoch;

/// Converts a PDF page number to the corresponding text book index.
///
/// This function uses a cached, anchor-based map with local interpolation for accuracy and performance.
Future<int?> pdfToTextPage(
  PdfBook pdfBook,
  List<PdfOutlineNode> outline,
  int pdfPage,
  BuildContext ctx,
) async {
  final textBook =
      (await DataRepository.instance.library).getCompanionBook(
            pdfBook,
            TextBook,
          )
          as TextBook?;
  if (textBook == null) {
    return null;
  }
  final key = '${pdfBook.path}::${textBook.title}';
  final map = _pageMapCache[key] ??= await _buildPageMap(
    pdfBook,
    collectPdfAnchors(outline),
    textBook,
  );
  if (!map.hasReliableAnchors) {
    return null;
  }

  return map.pdfToText(pdfPage);
}

/// Builds the synchronized anchor map from PDF anchors and text Table of Contents.
Future<PageMap> _buildPageMap(
  PdfBook pdf,
  List<({int page, String ref})> anchorsPdf,
  TextBook text,
) async {
  final toc = await text.tableOfContents;
  final anchorsText = collectTextAnchors(toc);

  final map = buildPageMapFromAnchors(anchorsPdf, anchorsText);

  debugPrint(
    '🗺️ [PDF-DEBUG] _buildPageMap "${pdf.title}": pdfAnchors=${anchorsPdf.length}, textAnchors=${anchorsText.length}, matched=${map.pdfPages.length}',
  );
  if (map.pdfPages.isNotEmpty) {
    debugPrint(
      '🗺️ [PDF-DEBUG] First 5 matches: ${List.generate(map.pdfPages.length > 5 ? 5 : map.pdfPages.length, (i) => "pdf${map.pdfPages[i]}→txt${map.textIndices[i]}").join(", ")}',
    );
  }
  if (anchorsPdf.isNotEmpty &&
      anchorsText.isNotEmpty &&
      map.pdfPages.length < 3) {
    debugPrint(
      '🗺️ [PDF-DEBUG] ⚠️ POOR MATCH! PDF sample refs: ${anchorsPdf.take(3).map((a) => '"${a.ref}"').join(", ")}',
    );
    debugPrint(
      '🗺️ [PDF-DEBUG] ⚠️ Text sample refs: ${anchorsText.take(3).map((a) => '"${a.ref}"').join(", ")}',
    );
  }

  // Fallback: if no anchors matched, anchor to page 1 / index 0.
  if (map.pdfPages.isEmpty) {
    return PageMap([1], [0]);
  }

  return map;
}

/// אוסף עוגנים (עמוד + נתיב מנורמל) מתוך ה-outline של ה-PDF, רקורסיבית.
///
/// צמתים ללא יעד (dest) או עם מספר עמוד לא חוקי מדולגים יחד עם תתי-העץ שלהם.
List<({int page, String ref})> collectPdfAnchors(
  List<PdfOutlineNode> nodes, [
  String prefix = '',
]) {
  final List<({int page, String ref})> anchors = [];
  for (final node in nodes) {
    final page = node.dest?.pageNumber;
    if (page != null && page > 0) {
      final currentPath = prefix.isEmpty
          ? node.title.trim()
          : '$prefix/${node.title.trim()}';
      anchors.add((page: page, ref: normalizeRef(currentPath)));
      anchors.addAll(collectPdfAnchors(node.children, currentPath));
    }
  }
  return anchors;
}

/// אוסף עוגנים (אינדקס שורה + נתיב מנורמל) מתוכן העניינים של ספר טקסט, רקורסיבית.
List<({int index, String ref})> collectTextAnchors(
  List<TocEntry> entries, [
  String prefix = '',
]) {
  final List<({int index, String ref})> anchors = [];
  for (final entry in entries) {
    final currentPath = prefix.isEmpty
        ? entry.text.trim()
        : '$prefix/${entry.text.trim()}';
    anchors.add((index: entry.index, ref: normalizeRef(currentPath)));
    anchors.addAll(collectTextAnchors(entry.children, currentPath));
  }
  return anchors;
}
