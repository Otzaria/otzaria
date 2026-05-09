import 'package:flutter/foundation.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';

/// In-memory cache for reference finding.
///
/// Uses shared caches:
/// - BooksCache: shared with library screen (book table)
/// - AcronymsCache: exclusive to FindRef (book_acronym table)
///
/// This avoids loading the same data twice into memory.
/// Scope: only the "book selection" phase. TOC lookup is handled elsewhere.
class ReferenceBooksCache {
  ReferenceBooksCache._();

  static final ReferenceBooksCache instance = ReferenceBooksCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;

  // Normalized titles cache (computed from BooksCache)
  final Map<int, String> _normalizedTitles = <int, String>{};

  // PDF books from file system (not in DB) — stored as (normalizedTitle, hit)
  final List<(String, ReferenceBookHit)> _fsPdfBooks =
      <(String, ReferenceBookHit)>[];

  // Lazy PDF outline cache: filePath → Future of outline entries
  // Populated on demand, not during warmup.
  final Map<String, Future<List<(String, String, int)>>> _pdfOutlineCache =
      <String, Future<List<(String, String, int)>>>{};

  bool get isLoaded => _isLoaded;

  Future<void> warmUp() async {
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;

    _loadingFuture = _loadInternal();

    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _loadInternal() async {
    try {
      // Warm up shared caches
      await BooksCache.instance.warmUp();
      await AcronymsCache.instance.warmUp();

      // Pre-compute normalized titles for fast matching
      _normalizedTitles.clear();
      for (final book in BooksCache.instance.books) {
        _normalizedTitles[book.id] = _normalizeForMatch(book.title);
      }

      // Collect DB PDF titles to avoid duplicates with file-system PDFs
      final dbPdfTitles = BooksCache.instance.books
          .where((b) => b.fileType == 'pdf')
          .map((b) => b.title)
          .toSet();

      // Load PDF books from file system that are not in the DB.
      // PDF outline parsing is NOT done here — it happens lazily via getPdfOutlineEntries().
      _fsPdfBooks.clear();
      if (FileSystemLibraryProvider.instance.isInitialized) {
        final keyToPath = await FileSystemLibraryProvider.instance.keyToPath;
        for (final entry in keyToPath.entries) {
          final key = BookCompositeKey.tryParse(entry.key);
          if (key == null || key.fileType != 'pdf') continue;
          if (dbPdfTitles.contains(key.title)) continue;

          final normalizedTitle = _normalizeForMatch(key.title);
          if (normalizedTitle.isEmpty) continue;

          _fsPdfBooks.add((
            normalizedTitle,
            ReferenceBookHit(
              bookId: -1,
              title: key.title,
              filePath: entry.value,
              fileType: 'pdf',
              matchRank: 0,
              orderIndex: 999.0,
            ),
          ));
        }
        debugPrint(
            '[ReferenceBooksCache] Added ${_fsPdfBooks.length} FS PDF books');
      }

      _isLoaded = true;
      debugPrint(
        '[ReferenceBooksCache] Ready with ${BooksCache.instance.books.length} DB books'
        ' + ${_fsPdfBooks.length} FS PDF books',
      );
    } catch (e) {
      debugPrint('[ReferenceBooksCache] Warmup failed: $e');
      _normalizedTitles.clear();
      _fsPdfBooks.clear();
      _isLoaded = true;
    }
  }

  void clear() {
    _normalizedTitles.clear();
    _fsPdfBooks.clear();
    _pdfOutlineCache.clear();
    _isLoaded = false;
    _loadingFuture = null;
    // Note: We don't clear the shared caches here as they may be used by other components
  }

  /// Returns outline entries for a file-system PDF, parsed lazily and cached.
  /// Each entry is (normalizedTitle, originalTitle, pageNumber).
  Future<List<(String, String, int)>> getPdfOutlineEntries(
      String filePath) async {
    return _pdfOutlineCache.putIfAbsent(
        filePath, () => _parsePdfOutlineEntries(filePath));
  }

  /// Searches books by title and acronym from memory.
  ///
  /// Input must already be normalized similarly to [_normalizeForMatch], but we
  /// normalize again defensively.
  List<ReferenceBookHit> search(String query, {int limit = 50}) {
    final q = _normalizeForMatch(query);
    if (q.isEmpty) return const <ReferenceBookHit>[];

    final starts = <ReferenceBookHit>[];
    final contains = <ReferenceBookHit>[];

    for (final book in BooksCache.instance.books) {
      final t = _normalizedTitles[book.id] ?? '';
      if (t.isEmpty) continue;

      int? matchRank;
      String? matchedTerm;

      if (t == q) {
        matchRank = 0;
      } else if (t.startsWith(q)) {
        matchRank = 1;
      } else if (t.contains(q)) {
        matchRank = 2;
      } else {
        // acronym match
        final rawAcronyms = AcronymsCache.instance.getAcronymsForBook(book.id);
        if (rawAcronyms != null) {
          for (final rawAcr in rawAcronyms) {
            final a = _normalizeForMatch(rawAcr);
            if (a.isEmpty) continue;

            if (a == q) {
              matchRank = 3;
              matchedTerm = a;
              break;
            }
            if (a.startsWith(q)) {
              matchRank ??= 4;
              matchedTerm ??= a;
            } else if (a.contains(q)) {
              matchRank ??= 5;
              matchedTerm ??= a;
            }
          }
        }
      }

      if (matchRank == null) continue;

      final hit = ReferenceBookHit(
        bookId: book.id,
        title: book.title,
        filePath: book.filePath ?? '',
        fileType: book.fileType,
        matchRank: matchRank,
        matchedTerm: matchedTerm,
        orderIndex: book.orderIndex,
      );

      if (matchRank <= 1) {
        starts.add(hit);
      } else {
        contains.add(hit);
      }
    }

    // Search file-system PDF books
    for (final (t, baseHit) in _fsPdfBooks) {
      int? matchRank;
      if (t == q) {
        matchRank = 0;
      } else if (t.startsWith(q)) {
        matchRank = 1;
      } else if (t.contains(q)) {
        matchRank = 2;
      }
      if (matchRank == null) continue;

      final hit = ReferenceBookHit(
        bookId: baseHit.bookId,
        title: baseHit.title,
        filePath: baseHit.filePath,
        fileType: baseHit.fileType,
        matchRank: matchRank,
        orderIndex: baseHit.orderIndex,
      );

      if (matchRank <= 1) {
        starts.add(hit);
      } else {
        contains.add(hit);
      }
    }

    int cmp(ReferenceBookHit a, ReferenceBookHit b) {
      final r = a.matchRank.compareTo(b.matchRank);
      if (r != 0) return r;
      // Prefer lower orderIndex, then shorter title.
      final o = a.orderIndex.compareTo(b.orderIndex);
      if (o != 0) return o;
      return a.title.length.compareTo(b.title.length);
    }

    starts.sort(cmp);
    contains.sort(cmp);

    final merged = <ReferenceBookHit>[...starts, ...contains];
    return merged.length > limit ? merged.take(limit).toList() : merged;
  }

  static String _normalizeForMatch(String input) {
    var cleaned = removeTeamim(removeVolwels(input));

    // Remove quotes/gershayim completely (don't convert to space)
    // This way מ"ב becomes מב (not מ ב)
    cleaned = cleaned.replaceAll('"', '').replaceAll("'", '');
    cleaned = cleaned.replaceAll('״', '').replaceAll('׳', '');

    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9֐-׿\s]'), ' ');
    cleaned = cleaned.toLowerCase();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Future<List<(String, String, int)>> _parsePdfOutlineEntries(
      String filePath) async {
    try {
      final doc = await PdfDocument.openFile(filePath);
      final outline = await doc.loadOutline();
      final entries = <(String, String, int)>[];
      _collectOutlineEntries(outline, entries, maxDepth: 2, currentDepth: 0);
      debugPrint(
          '[ReferenceBooksCache] Parsed ${entries.length} outline entries for $filePath');
      return entries;
    } catch (e) {
      debugPrint(
          '[ReferenceBooksCache] Failed to parse outline for $filePath: $e');
      return const [];
    }
  }

  static void _collectOutlineEntries(
    List<PdfOutlineNode> nodes,
    List<(String, String, int)> out, {
    required int maxDepth,
    required int currentDepth,
  }) {
    if (currentDepth >= maxDepth) return;
    for (final node in nodes) {
      final page = node.dest?.pageNumber;
      if (page != null && node.title.isNotEmpty) {
        out.add((_normalizeForMatch(node.title), node.title, page));
      }
      _collectOutlineEntries(node.children, out,
          maxDepth: maxDepth, currentDepth: currentDepth + 1);
    }
  }
}

class ReferenceBookHit {
  final int bookId;
  final String title;
  final String filePath;
  final String fileType;
  final int matchRank;
  final String? matchedTerm;
  final double orderIndex;

  const ReferenceBookHit({
    required this.bookId,
    required this.title,
    required this.filePath,
    required this.fileType,
    required this.matchRank,
    required this.orderIndex,
    this.matchedTerm,
  });
}
