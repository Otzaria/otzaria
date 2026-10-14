import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';

typedef PersonalNotesBookContentLoader = Future<String> Function(Book book);

/// משייך לספר אישי הערות שנשמרו תחת הכותרת בלבד, לפני שלספר אישי היה מפתח
/// `|user` משלו. כותרת שקיימת רק כספר אישי עוברת אליו כולה; כותרת שקיימת גם
/// כספר רשמי — רק הערה שהטקסט שלה נמצא בשורתה בספר האישי ולא בספר הרשמי.
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

  /// משייך את ההערות הממתינות לפי הקטלוג [library]; לא עושה דבר אחרי שכבר רץ.
  Future<void> assignPending(Library library) =>
      _running ??= _assign(library).whenComplete(() => _running = null);

  Future<void> _assign(Library library) async {
    final officialTitles = <String>{};
    final userBooks = <String, Book>{};
    for (final book in library.getAllBooks()) {
      if (book.source.isOfficial) {
        officialTitles.add(book.title);
      } else if (book.source.isUser) {
        userBooks.putIfAbsent(book.title, () => book);
      }
    }
    // בלי ספרים רשמיים הקטלוג עוד לא נטען, וכל כותרת הייתה נראית אישית בלבד.
    if (userBooks.isEmpty || officialTitles.isEmpty) return;
    if (!await _database.userBookKeysPending()) return;

    for (final info in await _database.listBooksWithNotes()) {
      final key = info.bookId;
      final userBook = userBooks[key];
      if (userBook == null || parsePersonalNotesBookKey(key).source != null) {
        continue;
      }
      final notes = await _database.loadNotes(key);
      final officialBook = findBookForPersonalNotesKey(library, key);
      final moved = officialBook == null
          ? notes
          : await _userBookNotes(notes, key, officialBook, userBook);
      await _database.moveNotesToBook(
        moved.map((note) => note.id),
        personalNotesBookKey(userBook),
      );
    }
    await _database.setUserBookKeysPending(false);
  }

  Future<List<PersonalNote>> _userBookNotes(
    List<PersonalNote> notes,
    String key,
    Book officialBook,
    Book userBook,
  ) async {
    final officialLines = splitBookContentIntoLines(
      await _loadContent(officialBook),
    );
    final userLines = splitBookContentIntoLines(await _loadContent(userBook));
    // ספר בלי טקסט (PDF או כשל טעינה) אינו מאפשר הכרעה; ההערות נשארות ברשמי.
    if (officialLines.isEmpty || userLines.isEmpty) return const [];
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
