import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/services/parallel_editions_service.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/declarative/services/declarative_host_action_executor.dart';
import 'package:otzaria/plugins/declarative/services/declarative_program_executor.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/plugin_external_book_loader.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/navigation/otzar_utils.dart';

typedef DeclarativeBookListLoader = Future<List<Book>> Function();
typedef DeclarativeExternalBookListLoader =
    Future<List<Book>> Function(String provider, Set<Object> externalIds);
typedef DeclarativeBookOpen =
    void Function(
      Book book,
      int index,
      String searchQuery, {
      required bool navigateToPositionIfReused,
      required bool inSidePane,
      ExternalBookMatches? externalMatches,
    });
typedef DeclarativeExternalBookOpen =
    Future<bool> Function(ExternalLibraryBook book);

class DeclarativeLibraryBookAccess
    implements DeclarativeBookResolver, DeclarativeBookOpener {
  final DeclarativeBookListLoader _libraryBooks;
  final DeclarativeExternalBookListLoader _externalBooks;
  final DeclarativeBookOpen _openBook;
  final DeclarativeExternalBookOpen externalBookOpener;

  DeclarativeLibraryBookAccess(
    this._libraryBooks,
    this._externalBooks,
    this._openBook, {
    required this.externalBookOpener,
  });

  factory DeclarativeLibraryBookAccess.otzaria(
    BookOpenCoordinator coordinator,
  ) {
    return DeclarativeLibraryBookAccess(
      () async => (await DataRepository.instance.library).getAllBooks(),
      loadExternalBooksByProvider,
      (
        book,
        index,
        searchQuery, {
        required navigateToPositionIfReused,
        required inSidePane,
        externalMatches,
      }) => coordinator.openBook(
        book,
        index,
        searchQuery,
        ignoreHistory: true,
        requiresStableLayout: book is PdfBook,
        navigateToPositionIfReused: navigateToPositionIfReused,
        inSidePane: inSidePane,
        externalMatches: externalMatches,
      ),
      externalBookOpener: (book) async {
        final url = book.link;
        return url != null && await OtzarUtils.launchOtzarWeb(url);
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>?>> resolveUniqueBatch(
    List<Map<String, dynamic>> identities,
  ) async {
    final books = await findUniqueBooks(identities);
    return [
      for (final book in books)
        if (book == null) null else PluginBookIdentity.toJson(book),
    ];
  }

  Future<Map<String, dynamic>?> resolveUnique(
    Map<String, dynamic> identity,
  ) async {
    final book = (await findUniqueBooks([identity])).single;
    return book == null ? null : PluginBookIdentity.toJson(book);
  }

  @override
  Future<bool> openUnique(
    Map<String, dynamic> identity, {
    required int index,
    required String searchQuery,
    bool navigateToPositionIfReused = false,
    bool inSidePane = false,
    ExternalBookMatches? externalMatches,
  }) async {
    final book = (await findUniqueBooks([identity])).single;
    if (book == null) return false;
    if (book is ExternalLibraryBook) {
      return externalBookOpener(book);
    }
    _openBook(
      book,
      index,
      searchQuery,
      navigateToPositionIfReused: navigateToPositionIfReused,
      inSidePane: inSidePane,
      externalMatches: externalMatches,
    );
    return true;
  }

  /// מהדורות מקבילות (מובנית + היברובוקס מקומיות) לזהות ספר, כשורות
  /// דקלרטיביות `{title, isCompanion, identity}` — עבור הפקודה
  /// `library.parallelEditions`. הזהות מנוקה משדות null לפני החיפוש:
  /// כשיש זהות חיצונית היא מספיקה לבדה, אחרת נשמרים רק השדות שסופקו.
  Future<List<Map<String, dynamic>>> parallelEditionsForIdentity(
    Map<String, dynamic> identity,
  ) async {
    final sanitized = _sanitizeContextIdentity(identity);
    if (sanitized == null) return const [];
    final book = (await findUniqueBooks([sanitized])).single;
    if (book == null) return const [];
    final editions = await ParallelEditionsService.find(book);
    return [
      for (final edition in editions)
        {
          'title': edition.book.title,
          'isCompanion': edition.isCompanion,
          'identity': PluginBookIdentity.toJson(edition.book),
        },
    ];
  }

  /// זהות שנבנתה משדות `$context` עשויה לכלול null-ים (למשל external.provider
  /// כשאין ספר חיצוני) — מנקים אותם כדי שהוולידציה של הזהות תעבור.
  Map<String, dynamic>? _sanitizeContextIdentity(Map<String, dynamic> raw) {
    final external = raw['external'];
    if (external is Map &&
        external['provider'] is String &&
        external['id'] != null) {
      return {
        'external': {'provider': external['provider'], 'id': external['id']},
      };
    }
    final sanitized = <String, dynamic>{
      for (final field in const ['id', 'bookId', 'type', 'source'])
        if (raw[field] != null) field: raw[field],
    };
    return sanitized.isEmpty ? null : sanitized;
  }

  /// פותר אצווה של זהויות לספרים בלי לחשוף נתיבים או לבצע פתיחה.
  Future<List<Book?>> findUniqueBooks(
    List<Map<String, dynamic>> identities,
  ) async {
    final parsed = [
      for (final identity in identities) _parseIdentity(identity),
    ];
    final needsLibrary = parsed.any(
      (identity) => identity != null && identity.external == null,
    );
    final externalIds = <String, Set<Object>>{};
    for (final identity in parsed) {
      final external = identity?.external;
      if (external != null) {
        externalIds.putIfAbsent(external.provider, () => {}).add(external.id);
      }
    }

    final libraryFuture = needsLibrary ? _libraryBooks() : null;
    final externalFutures = {
      for (final entry in externalIds.entries)
        entry.key: _externalBooks(entry.key, Set.unmodifiable(entry.value)),
    };
    final libraryIndex = libraryFuture == null
        ? null
        : _BookLookupIndex(await libraryFuture);
    final externalIndexes = <String, _BookLookupIndex>{};
    for (final entry in externalFutures.entries) {
      externalIndexes[entry.key] = _BookLookupIndex(await entry.value);
    }

    return [
      for (final identity in parsed)
        if (identity == null)
          null
        else if (identity.external case final external?)
          externalIndexes[external.provider]?.findUnique(identity)
        else
          libraryIndex?.findUnique(identity),
    ];
  }

  _ParsedBookIdentity? _parseIdentity(Map<String, dynamic> identity) {
    const allowed = {'id', 'bookId', 'type', 'source', 'external'};
    if (identity.keys.any((key) => !allowed.contains(key))) return null;
    final id = PluginBookIdentity.parseId(identity['id']);
    if (identity.containsKey('id') && id == null) return null;
    final bookId = identity['bookId'];
    final type = identity['type'];
    final source = identity['source'];
    if ((bookId != null && bookId is! String) ||
        (type != null && type is! String) ||
        (source != null && source is! String)) {
      return null;
    }
    final external = _parseExternal(identity['external']);
    if (identity['external'] != null && external == null) return null;
    if (id == null && bookId == null && external == null) return null;
    return (
      id: id,
      bookId: bookId as String?,
      type: type as String?,
      source: source as String?,
      external: external,
    );
  }

  ({String provider, Object id})? _parseExternal(Object? value) {
    if (value is! Map || value.length != 2) return null;
    final provider = value['provider'];
    final id = value['id'];
    if (provider is! String ||
        !const {'hebrewbooks', 'otzar'}.contains(provider) ||
        (id is! int && (id is! String || id.isEmpty))) {
      return null;
    }
    return (provider: provider, id: id);
  }
}

typedef _ParsedBookIdentity = ({
  int? id,
  String? bookId,
  String? type,
  String? source,
  ({String provider, Object id})? external,
});

class _BookLookupIndex {
  final Map<int, List<Book>> _byId = {};
  final Map<String, List<Book>> _byBookId = {};
  final Map<String, List<Book>> _byExternal = {};

  _BookLookupIndex(List<Book> books) {
    for (final book in books) {
      if (book.id case final id?) {
        _byId.putIfAbsent(id, () => []).add(book);
      }
      _byBookId.putIfAbsent(book.title, () => []).add(book);
      if (PluginBookIdentity.externalOf(book) case final external?) {
        _byExternal.putIfAbsent(_externalKey(external), () => []).add(book);
      }
    }
  }

  Book? findUnique(_ParsedBookIdentity identity) {
    final List<Book>? candidates;
    if (identity.external case final external?) {
      candidates = _byExternal[_externalKey(external)];
    } else if (identity.id case final id?) {
      candidates = _byId[id];
    } else if (identity.bookId case final bookId?) {
      candidates = _byBookId[bookId];
    } else {
      candidates = null;
    }
    if (candidates == null) return null;
    Book? match;
    for (final book in candidates) {
      if (!PluginBookIdentity.matches(
        book,
        id: identity.id,
        bookId: identity.bookId,
        type: identity.type,
        source: identity.source,
      )) {
        continue;
      }
      if (match != null) return null;
      match = book;
    }
    return match;
  }

  static String _externalKey(({String provider, Object id}) external) =>
      '${external.provider}:${external.id}';
}
