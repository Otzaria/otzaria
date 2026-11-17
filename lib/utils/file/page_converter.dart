import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/pdf_anchor_cache_entry.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/page_map_builder.dart';
import 'package:pdfrx/pdfrx.dart';

typedef _PageMapKey = (String, BookCompositeKey?);
typedef _PdfAnchors = List<({int page, String ref})>;

class _PageMaps {
  final completed = <_PageMapKey, ({PageMap map, bool fromOutline})>{};
  final loadingFromFile = <_PageMapKey, Future<PageMap>>{};
}

class _CatalogPageMaps {
  final editions = _PageMaps();
  final books = Expando<_PageMaps>();
}

final _catalogPageMaps = Expando<_CatalogPageMaps>();
final _uncatalogedPageMaps = Expando<_PageMaps>();
final _pdfAnchorLoads = <(Object?, String), Future<_PdfAnchors>>{};
final _companionTextBooks = Expando<Expando<({TextBook? book})>>();

typedef PdfAnchorsReader =
    Future<List<({int page, String ref})>> Function(
      String pdfPath,
    );

@visibleForTesting
PdfAnchorsReader? pdfAnchorsReaderForTesting;

/// TTL לרשומות מטמון העוגנים המתמיד — נגזר מהמדיניות של מטמון ה-outline.
const _persistentAnchorCacheTtl = Duration(days: 90);

/// Converts a text book page index to the corresponding PDF page number.
///
/// This function uses a cached, anchor-based map with local interpolation for accuracy and performance.
/// [pdfBook] - מהדורת ה-PDF אם כבר אותרה אצל הקורא; חוסך סריקה מלאה של העץ.
/// [outline] - ה-outline של ה-PDF אם כבר נטען; חוסך את פתיחת הקובץ.
Future<int?> textToPdfPage(
  TextBook textBook,
  int textIndex, {
  PdfBook? pdfBook,
  List<PdfOutlineNode>? outline,
}) async {
  final repository = DataRepository.instance;
  final catalog = pdfBook == null ? repository.library : null;
  final cacheIdentity = repository.libraryCacheIdentity;
  pdfBook ??= (await catalog!).getCompanionBook(textBook, PdfBook) as PdfBook?;
  if (pdfBook == null) {
    return null;
  }

  try {
    final map = await _pageMapFor(textBook, pdfBook, outline, cacheIdentity);
    return map.hasReliableAnchors ? map.textToPdf(textIndex) : null;
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
Future<_PdfAnchors> _getPdfAnchors(String pdfPath) async {
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
            // רשומה ריקה נמחקת ונבנית מחדש; רענון ה-TTL שלה
            // היה מקבע כשל חולף לצמיתות.
            if (anchors.isNotEmpty) {
              unawaited(
                repository
                    .touchPdfAnchorCacheEntry(pdfPath, _nowMillis())
                    .catchError((_) {}),
              );
              return anchors;
            }
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

  final List<({int page, String ref})> anchors;
  final readerForTesting = pdfAnchorsReaderForTesting;
  if (readerForTesting != null) {
    anchors = await readerForTesting(pdfPath);
  } else {
    PdfDocument? doc;
    try {
      // progressive: בלעדיו pdfium מפענח כל עמוד לפני ה-outline (שניות בסריקה).
      doc = await PdfDocument.openFile(pdfPath, useProgressiveLoading: true);
      anchors = collectPdfAnchors(await doc.loadOutline());
    } finally {
      // המתנה לשחרור בפועל — הטאב הסופי עשוי לפתוח מיד את אותו PDF, וה-worker
      // היחיד של pdfrx חייב להשתחרר מהמסמך הזה קודם.
      await doc?.dispose();
    }
  }

  // רשימה ריקה אינה נשמרת: כשל חולף בקריאת ה-outline היה נקבע לצמיתות
  // (המפתח הוא נתיב+גודל+mtime) והספר לא היה נפתח לעולם במיקום המבוקש.
  if (anchors.isNotEmpty && repository != null && metadata != null) {
    unawaited(_savePdfAnchors(repository, pdfPath, metadata, anchors));
  }
  return anchors;
}

Future<_PdfAnchors> _loadPdfAnchors(String path, Object? cacheIdentity) {
  final key = (cacheIdentity, path);
  return _pdfAnchorLoads.putIfAbsent(
    key,
    () => _getPdfAnchors(path).whenComplete(() {
      _pdfAnchorLoads.remove(key);
    }),
  );
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

/// מהדורת הטקסט של [pdfBook], או null.
///
/// נקרא בכל מעבר עמוד; החיפוש בלי מלווה סורק את כל הספרייה, וגם "אין" נשמר.
Future<TextBook?> companionTextBookOf(PdfBook pdfBook) async =>
    _companionTextBookOf(await DataRepository.instance.library, pdfBook);

TextBook? _companionTextBookOf(Library library, PdfBook pdfBook) {
  final companions = _companionTextBooks[library] ??= Expando();
  return (companions[pdfBook] ??= (
    book: library.getCompanionBook(pdfBook, TextBook) as TextBook?,
  )).book;
}

/// Converts a PDF page number to the corresponding text book index.
///
/// This function uses a cached, anchor-based map with local interpolation for accuracy and performance.
/// [outline] - ה-outline של הטאב אם כבר נטען; אחרת הסימניות נקראות מהקובץ.
Future<int?> pdfToTextPage(
  PdfBook pdfBook,
  List<PdfOutlineNode> outline,
  int pdfPage,
) async {
  final catalog = DataRepository.instance.library;
  final textBook = _companionTextBookOf(await catalog, pdfBook);
  if (textBook == null) {
    return null;
  }
  try {
    final map = await _pageMapFor(textBook, pdfBook, outline, catalog);
    return map.hasReliableAnchors ? map.pdfToText(pdfPage) : null;
  } catch (e, st) {
    debugPrint(
      '[PageConverter] pdfToTextPage failed for "${pdfBook.path}": $e\n$st',
    );
    return null;
  }
}

Future<PageMap> _pageMapFor(
  TextBook textBook,
  PdfBook pdfBook,
  List<PdfOutlineNode>? outline,
  Object? cacheIdentity,
) {
  final edition = BookCompositeKey.fromBook(textBook);
  final catalogMaps = cacheIdentity == null
      ? null
      : _catalogPageMaps[cacheIdentity] ??= _CatalogPageMaps();
  final maps = catalogMaps != null && edition != null
      ? catalogMaps.editions
      : (catalogMaps?.books ?? _uncatalogedPageMaps)[textBook] ??= _PageMaps();
  final key = (pdfBook.path, edition);
  final hasOutline = outline != null && outline.isNotEmpty;
  final cached = maps.completed[key];
  if (cached != null &&
      (!hasOutline || cached.fromOutline || cached.map.hasReliableAnchors)) {
    return Future.value(cached.map);
  }

  Future<PageMap> load() async {
    final anchorsPdf = hasOutline
        ? collectPdfAnchors(outline)
        : await _loadPdfAnchors(pdfBook.path, cacheIdentity);
    final anchorsText = collectTextAnchors(await textBook.tableOfContents);
    final map = _buildPageMap(pdfBook, anchorsPdf, anchorsText);
    // שומרים גם תוצאה שלילית כדי לא לפתוח שוב PDF שאין בו סימניות.
    // טעינה מאוחרת מהקובץ אינה מחליפה מפה שכבר נשמרה.
    if (anchorsText.isNotEmpty &&
        (hasOutline || !maps.completed.containsKey(key))) {
      maps.completed[key] = (map: map, fromOutline: hasOutline);
    }
    return map;
  }

  if (hasOutline) return load();
  return maps.loadingFromFile.putIfAbsent(
    key,
    () => load().whenComplete(() {
      maps.loadingFromFile.remove(key);
    }),
  );
}

/// Builds the synchronized anchor map from PDF anchors and text Table of Contents.
PageMap _buildPageMap(
  PdfBook pdf,
  List<({int page, String ref})> anchorsPdf,
  List<({int index, String ref})> anchorsText,
) {
  final map = buildPageMapFromAnchors(anchorsPdf, anchorsText);

  debugPrint(
    '🗺️ [PDF-DEBUG] _buildPageMap "${pdf.title}": pdfAnchors=${anchorsPdf.length}, textAnchors=${anchorsText.length}, matched=${map.pdfPages.length}',
  );
  if (map.pdfPages.isNotEmpty) {
    debugPrint(
      '🗺️ [PDF-DEBUG] First 5 matches: ${List.generate(map.pdfPages.length > 5 ? 5 : map.pdfPages.length, (i) => "pdf${map.pdfPages[i]}→txt${map.textIndices[i]}").join(", ")}',
    );
  }
  // הבחנה בלוג: TOC ריק אינו "אין התאמה" אלא ספר בלי תוכן עניינים או כשל
  // בטעינתו — שני המצבים מחזירים null לקורא.
  if (anchorsText.isEmpty) {
    debugPrint(
      '🗺️ [PDF-DEBUG] ⚠️ EMPTY TOC for "${pdf.title}" — no text anchors to '
      'match (TOC missing or failed to load), not a matching failure',
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
