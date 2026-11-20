import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';

typedef PersonalNotesBookContentLoader = Future<String> Function(Book book);

/// משייך הערות ישנות לספר האישי רק כשהכותרת בלעדית לו או שהטקסט מתאים לו בלבד.
class PersonalNotesUserBookKeys {
  PersonalNotesUserBookKeys({
    PersonalNotesDatabase? database,
    PersonalNotesService? service,
    PersonalNotesBookContentLoader? loadContent,
  }) : _database = database ?? PersonalNotesDatabase.instance,
       _service = service ?? PersonalNotesService(),
       _loadContent = loadContent ?? _loadFromRepository;

  final PersonalNotesDatabase _database;
  final PersonalNotesService _service;
  final PersonalNotesBookContentLoader _loadContent;

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
    final running = _running = _assign(library);
    try {
      await running;
    } finally {
      _running = null;
    }
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
