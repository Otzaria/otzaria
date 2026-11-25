import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/data/official_book_title_renames.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/services/data_collection_service.dart';

typedef PersonalNotesBookContentLoader = Future<String> Function(Book book);

/// משייך הערות ישנות לספר האישי רק כשהכותרת בלעדית לו או שהטקסט מתאים לו בלבד,
/// והערות של כותרת שתוקנה בגרשיים לכותרת החדשה.
class PersonalNotesUserBookKeys {
  PersonalNotesUserBookKeys({
    PersonalNotesDatabase? database,
    PersonalNotesService? service,
    PersonalNotesBookContentLoader? loadContent,
    Future<String> Function()? catalogVersion,
  }) : _database = database ?? PersonalNotesDatabase.instance,
       _service = service ?? PersonalNotesService(),
       _loadContent = loadContent ?? _loadFromRepository,
       _catalogVersion =
           catalogVersion ?? DataCollectionService().readLibraryVersion;

  final PersonalNotesDatabase _database;
  final PersonalNotesService _service;
  final PersonalNotesBookContentLoader _loadContent;
  final Future<String> Function() _catalogVersion;

  static const _renamedTitlesMetaKey = 'renamed_titles_checked';

  static Future<void>? _running;

  static Future<String> _loadFromRepository(Book book) =>
      PersonalNotesRepository().loadBookContent(
        personalNotesBookKey(book),
        categoryId: book.categoryId,
      );

  /// משייך את ההערות הממתינות לפי הקטלוג המלא והטעון [library].
  Future<void> assignPending(Library library) async {
    while (_running != null) {
      await _running;
    }
    final running = _running = _assign(
      library,
    ).then((_) => _assignRenamedTitles(library));
    try {
      await running;
    } finally {
      _running = null;
    }
  }

  /// מעביר רק הערות של ספרי הטקסט שמופו בדלתא הרשמית.
  Future<void> _assignRenamedTitles(Library library) async {
    final version = await _catalogVersion();
    final versionNumber = int.tryParse(version);
    if (versionNumber != null && versionNumber < 40) return;
    final marker = '$version|${await _database.userBookKeysGeneration()}';
    if (await _database.metaValue(_renamedTitlesMetaKey) == marker) return;

    final books = library.getIndexableBooks();
    final officialById = <int, TextBook>{
      for (final book in books)
        if (book is TextBook && book.source.isOfficial && book.id != null)
          book.id!: book,
    };
    if (officialById.isEmpty) return;
    final exactOutsideUser = {
      for (final book in books)
        if (book.source.isOfficial || book.source.isAttached) book.title,
    };
    final users = <String, List<Book>>{};
    for (final book in books) {
      if (book.source.isUser &&
          officialBookTitleRenames.containsKey(book.title)) {
        (users[book.title] ??= []).add(book);
      }
    }

    var complete = true;
    for (final info in await _database.listBooksWithNotes()) {
      final key = info.bookId;
      final rename = officialBookTitleRenames[key];
      if (rename == null) continue;
      final official = officialById[rename.id];
      if (official == null || official.title != rename.title) {
        complete = false;
        continue;
      }
      if (exactOutsideUser.contains(key)) continue;
      final notes = (await _database.loadNotes(
        key,
      )).where((note) => note.pdfAnchor == null).toList();
      final userMatches = users[key];
      if (userMatches == null) {
        complete &= await _database.moveNotesToBook(
          notes,
          official.title,
          recordMove: true,
        );
      } else if (userMatches.length == 1 && userMatches.single is! PdfBook) {
        complete &= await _moveConflictingRenamedNotes(
          notes,
          key,
          official,
          userMatches.single,
        );
      } else {
        complete = false;
      }
    }
    if (complete && version != 'unknown') {
      await _database.setMetaValue(_renamedTitlesMetaKey, marker);
    }
  }

  Future<bool> _moveConflictingRenamedNotes(
    List<PersonalNote> notes,
    String key,
    TextBook official,
    Book user,
  ) async {
    if (notes.isEmpty) return true;
    final officialLines = splitBookContentIntoLines(
      await _loadContent(official),
    );
    final userLines = splitBookContentIntoLines(await _loadContent(user));
    if (officialLines.isEmpty || userLines.isEmpty) return false;
    final toOfficial = <PersonalNote>[];
    final toUser = <PersonalNote>[];
    for (final note in notes) {
      final inOfficial = _matches(note, officialLines, key);
      final inUser = _matches(note, userLines, key);
      if (inOfficial && !inUser) toOfficial.add(note);
      if (inUser && !inOfficial) toUser.add(note);
    }
    final officialMoved = await _database.moveNotesToBook(
      toOfficial,
      official.title,
      recordMove: true,
    );
    final userMoved = await _database.moveNotesToBook(
      toUser,
      personalNotesBookKey(user),
    );
    return officialMoved && userMoved;
  }

  Future<void> _assign(Library library) async {
    if (!await _database.userBookKeysPending()) return;
    final userBooks = <String, Book>{};
    for (final book in library.getIndexableBooks()) {
      if (book.source.isUser) {
        userBooks.putIfAbsent(book.title, () => book);
      }
    }
    if (userBooks.isEmpty) return;
    final generation = await _database.userBookKeysGeneration();
    var complete = true;

    for (final info in await _database.listBooksWithNotes()) {
      final key = info.bookId;
      if (key == PersonalNote.generalBookId ||
          !userBooks.containsKey(key) ||
          parsePersonalNotesBookKey(key).source != null) {
        continue;
      }
      final userBook = findBookForPersonalNotesKey(
        library,
        personalNotesBookKey(userBooks[key]!),
      )!;
      final notes = await _database.loadNotes(key);
      final officialBook = findBookForPersonalNotesKey(library, key);
      if (officialBook == null && officialBookTitleRenames.containsKey(key)) {
        continue;
      }
      final moved = officialBook == null
          ? notes
          : await _userBookNotes(notes, key, officialBook, userBook);
      if (moved == null) {
        complete = false;
        continue;
      }
      final movedAll = await _database.moveNotesToBook(
        moved,
        personalNotesBookKey(userBook),
      );
      complete &= movedAll;
    }
    if (complete) {
      await _database.setUserBookKeysPending(false, ifGeneration: generation);
    }
  }

  Future<List<PersonalNote>?> _userBookNotes(
    List<PersonalNote> notes,
    String key,
    Book officialBook,
    Book userBook,
  ) async {
    if (officialBook is PdfBook || userBook is PdfBook) return const [];
    final officialLines = splitBookContentIntoLines(
      await _loadContent(officialBook),
    );
    final userLines = splitBookContentIntoLines(await _loadContent(userBook));
    // תוכן חסר אינו הכרעה: צריך לנסות שוב אחרי שהספר נגיש.
    if (officialLines.isEmpty || userLines.isEmpty) return null;
    return [
      for (final note in notes)
        if (_matches(note, userLines, key) &&
            !_matches(note, officialLines, key))
          note,
    ];
  }

  bool _matches(PersonalNote note, List<String> lines, String key) {
    final line = note.lineNumber ?? note.lastKnownLineNumber;
    return line != null && _service.noteTextMatchesLine(note, lines, line, key);
  }
}
