import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';

/// קבוצת הגרסאות של הספר האישי [bookId] — הראשית תחילה, ואחריה לפי עדיפות
/// ושם. ריק כשהספר אינו בקבוצה, או כשהגרסה הראשית אינה בקטלוג.
///
/// [catalogPrimaries] — הספר הרשמי/המצורף שנפתר לכל גרסה שהראשי שלה אינו
/// אישי, לפי מזהה ספר הגרסה.
List<BookVersionInfo> buildUserBookVersions({
  required int bookId,
  required List<UserBookVersionRecord> records,
  required Map<int, Book> booksById,
  Map<int, Book> catalogPrimaries = const {},
}) {
  final own = records.where((v) => v.versionBookId == bookId).firstOrNull;
  if (own != null && own.hasCatalogPrimary) {
    final primary = catalogPrimaries[bookId];
    if (primary == null) return const [];
    return [
      BookVersionInfo(
        versionTitle: primary.title,
        hasContent: true,
        separateBook: primary,
      ),
      ...buildPersonalVersionsOfCatalogBook(
        primary: primary,
        records: records,
        booksById: booksById,
        catalogPrimaries: catalogPrimaries,
      ),
    ];
  }

  final userRecords = records.where((v) => !v.hasCatalogPrimary).toList();
  final primaryId = own?.primaryBookId ?? bookId;
  final members = userRecords
      .where(
        (v) => v.primaryBookId == primaryId && v.versionBookId != primaryId,
      )
      .toList();
  final primary = booksById[primaryId];
  if (members.isEmpty || primary == null) return const [];

  _sortVersions(members);
  final primaryRow = userRecords
      .where((v) => v.versionBookId == primaryId)
      .firstOrNull;
  return [
    BookVersionInfo(
      versionTitle: primaryRow?.versionTitle ?? primary.title,
      heVersionNotes: primaryRow?.versionNotes,
      hasContent: true,
      separateBook: primary,
    ),
    for (final member in members)
      if (booksById[member.versionBookId] case final target?)
        _versionInfo(member, target),
  ];
}

/// הגרסאות האישיות של ספר רשמי או ממסד מצורף [primary], לפי עדיפות ושם.
List<BookVersionInfo> buildPersonalVersionsOfCatalogBook({
  required Book primary,
  required List<UserBookVersionRecord> records,
  required Map<int, Book> booksById,
  required Map<int, Book> catalogPrimaries,
}) {
  final members = [
    for (final record in records)
      if (catalogPrimaries[record.versionBookId] case final resolved?
          when record.hasCatalogPrimary && isSameCatalogBook(resolved, primary))
        record,
  ];
  _sortVersions(members);
  return [
    for (final member in members)
      if (booksById[member.versionBookId] case final target?)
        _versionInfo(member, target),
  ];
}

/// הספר בקטלוג שהרשומה [record] מצהירה עליו כראשי, או null כשאינו נמצא או
/// כשהכותרת מתאימה לכמה ספרים בקטגוריות שונות. [catalogByTitle] ממופתח
/// ב-[normalizeVersionTitle].
Book? resolveCatalogPrimary(
  UserBookVersionRecord record,
  Map<String, List<Book>> catalogByTitle,
) {
  final title = record.primaryTitle;
  if (title == null) return null;
  final wanted = _categorySegments(record.primaryCategoryPath);
  final candidates = [
    for (final book
        in catalogByTitle[normalizeVersionTitle(title)] ?? const <Book>[])
      if (book.source == record.primarySource &&
          _endsWith(_categorySegments(book.categoryPath), wanted))
        book,
  ];
  // ספר טקסט ו-PDF באותו שם הם אותו ספר; הגרסה נקשרת לטקסט.
  final textual = candidates.where((b) => b is! PdfBook).toList();
  final pool = textual.isNotEmpty ? textual : candidates;
  final categories = {for (final b in pool) b.categoryPath ?? ''};
  return categories.length == 1 ? pool.first : null;
}

/// כותרת להשוואה: גרשיים עבריים כ-ASCII ורווחים מכווצים.
String normalizeVersionTitle(String title) => title
    .replaceAll('״', '"')
    .replaceAll('׳', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// אותו ספר בקטלוג, גם כשהמופע שונה (טאב משוחזר).
bool isSameCatalogBook(Book a, Book b) =>
    a.source == b.source &&
    a.title == b.title &&
    a.runtimeType == b.runtimeType &&
    (a.categoryId == null ||
        b.categoryId == null ||
        a.categoryId == b.categoryId);

List<String> _categorySegments(String? path) {
  final segments = [
    for (final part in (path ?? '').split(RegExp(r'[,/\\>]')))
      if (normalizeVersionTitle(part) case final s when s.isNotEmpty) s,
  ];
  if (segments.isNotEmpty && segments.first == 'ספריית אוצריא') {
    segments.removeAt(0);
  }
  return segments;
}

bool _endsWith(List<String> path, List<String> suffix) {
  if (suffix.length > path.length) return false;
  final offset = path.length - suffix.length;
  for (var i = 0; i < suffix.length; i++) {
    if (path[offset + i] != suffix[i]) return false;
  }
  return true;
}

void _sortVersions(List<UserBookVersionRecord> members) {
  members.sort((a, b) {
    final byPriority = (b.priority ?? 0).compareTo(a.priority ?? 0);
    return byPriority != 0
        ? byPriority
        : a.versionTitle.compareTo(b.versionTitle);
  });
}

BookVersionInfo _versionInfo(UserBookVersionRecord member, Book target) =>
    BookVersionInfo(
      versionTitle: member.versionTitle,
      heVersionNotes: member.versionNotes,
      priority: member.priority,
      hasContent: true,
      separateBook: target,
    );
