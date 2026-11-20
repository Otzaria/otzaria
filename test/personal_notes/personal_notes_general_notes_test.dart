import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_notes_import_export_service.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/services/personal_notes_user_book_keys.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_link_detection.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

const _general = PersonalNote.generalBookId;

PersonalNote _note(
  String id, {
  String bookId = 'ספר',
  int? lineNumber = 3,
  PersonalNoteStatus status = PersonalNoteStatus.located,
  String content = 'תוכן',
  PersonalNoteContentFormat format = PersonalNoteContentFormat.plain,
}) => PersonalNote(
  id: id,
  bookId: bookId,
  lineNumber: lineNumber,
  displayTitle: lineNumber == null ? null : 'כותרת',
  lastKnownLineNumber: null,
  status: status,
  content: content,
  contentPlain: content,
  contentFormat: format,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 2, 1),
);

PersonalNote _generalNote(String id, {String content = 'לבדוק את הנושא'}) =>
    _note(
      id,
      bookId: _general,
      lineNumber: null,
      status: PersonalNoteStatus.book,
      content: content,
    );

String _linkDelta(String label, String targetId) => jsonEncode([
  {'insert': 'ראה '},
  {
    'insert': label,
    'attributes': {'link': personalNoteLinkUrl(targetId)},
  },
  {'insert': '\n'},
]);

Library _library(List<Book> books) {
  final category = Category(
    title: 'root',
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: books,
    parent: null,
  );
  final library = Library(categories: [category]);
  category.parent = library;
  return library;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  late Directory root;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('personal_notes_general_');
    await Directory('${root.path}/databases').create();
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
  });

  tearDown(() async {
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  group('הערות כלליות', () {
    test('נשמרות כהערת ספר תחת המפתח השמור ונטענות חזרה', () async {
      final repository = PersonalNotesRepository();
      final created = await repository.createNote(
        bookId: _general,
        lineNumber: null,
        content: 'לזכור לעיין',
        contentPlain: 'לזכור לעיין',
        contentFormat: PersonalNoteContentFormat.plain,
      );

      expect(created.isGeneralNote, isTrue);
      expect(created.isBookNote, isTrue);
      expect(created.hasLocation, isFalse);
      expect(created.title, 'לזכור לעיין');
      expect(await database.getNote(created.id), created);
      expect(await repository.loadNotes(_general), [created]);
      final books = await repository.listBooksWithNotes();
      expect(books.single.bookId, _general);

      final saved = await repository.persistNote(
        bookId: _general,
        noteId: created.id,
        content: 'לזכור לעיין שוב',
        contentPlain: 'לזכור לעיין שוב',
        contentFormat: PersonalNoteContentFormat.plain,
      );
      expect(saved.status, PersonalNoteStatus.book);
      expect(saved.contentPlain, 'לזכור לעיין שוב');
    });

    test('אין יצירה של הערה כללית במיקום בשורה', () async {
      final service = PersonalNotesService(database: database);
      await expectLater(
        service.createNote(
          bookId: _general,
          bookContent: '',
          lineNumber: 2,
          content: 'x',
          contentPlain: 'x',
          contentFormat: PersonalNoteContentFormat.plain,
        ),
        throwsArgumentError,
      );
      expect(await database.listBooksWithNotes(), isEmpty);
    });

    test('המפתח אינו נפתר לספר בספרייה גם כשיש ספר באותה כותרת', () async {
      final library = _library([
        TextBook(title: _general),
        PdfBook(title: _general, path: '/x/general.pdf'),
      ]);
      expect(findBookForPersonalNotesKey(library, _general), isNull);
      expect(findTextBookForPersonalNotesKey(library, _general), isNull);
      expect(findPdfBookForPersonalNotesKey(library, _general), isNull);
      expect(await personalNotesBookToc(library, _general), isNull);
      expect(personalNotesBookDisplayTitle(_general), 'הערות כלליות');
      expect(personalNotesBookDisplayTitle('ספר|user'), 'ספר');
      expect(await PersonalNotesRepository().loadBookContent(_general), '');
    });

    test('שיוך הערות מגיבוי לא מעביר הערה כללית לספר אישי', () async {
      final note = _generalNote('g');
      await database.batchInsertNotes([note]);
      final userBook = TextBook(title: _general, source: BookSource.user);
      await PersonalNotesUserBookKeys(
        database: database,
      ).assignPending(_library([userBook]));

      expect(await database.loadNotes(_general), [note]);
      expect(await database.loadNotes(personalNotesBookKey(userBook)), isEmpty);
    });

    test('גיבוי JSON וייבוא שומרים את ההערה הכללית כפי שהיא', () async {
      final service = PersonalNotesImportExportService();
      final note = _generalNote('g1');
      final file = File('${root.path}/export.json');
      await file.writeAsString(jsonEncode(service.buildExport(notes: [note])));

      final summary = await service.importFromFile(
        path: file.path,
        strategy: NotesImportConflictStrategy.merge,
      );

      expect(summary.inserted, 1);
      final restored = await database.getNote('g1');
      expect(restored, note);
      expect(restored!.isGeneralNote, isTrue);
    });

    test('ייצוא טקסט ו-Word מציגים את הקבוצה בשמה בלי "על הספר כולו"', () {
      final service = PersonalNotesImportExportService();
      final notes = [_generalNote('g1'), _note('b1')];

      final text = service.buildPlainTextExport(notes: notes);
      expect(text, contains('הערות כלליות'));
      expect(text, isNot(contains(_general)));
      expect(text, contains('ספר: ספר'));

      final blocks = service.buildWordExportBlocks(
        notes: notes,
        locationRef: (_) => 'מיקום',
      );
      final headings = blocks
          .where((block) => block.kind == PrintBlockKind.heading)
          .map((block) => block.text)
          .toList();
      expect(headings, contains('הערות כלליות'));
      expect(headings, isNot(contains('על הספר כולו')));
      expect(headings, isNot(contains(_general)));
    });
  });

  group('קישורים בין הערות בייבוא', () {
    test(
      '"שמור גם וגם" מעביר קישורים בין ההערות המיובאות למזהים החדשים',
      () async {
        final service = PersonalNotesImportExportService();
        final target = _generalNote('target');
        final source = _note(
          'source',
          content: _linkDelta('יעד', 'target'),
          format: PersonalNoteContentFormat.quillDelta,
        );
        final outside = _generalNote(
          'outside',
          content: 'otzaria://note?id=target ו-otzaria://note?id=other',
        );
        await database.insertNote(target);
        await database.insertNote(source);
        final file = File('${root.path}/links.json');
        await file.writeAsString(
          jsonEncode(service.buildExport(notes: [source, target, outside])),
        );

        final summary = await service.importFromFile(
          path: file.path,
          strategy: NotesImportConflictStrategy.keepBoth,
        );

        expect(summary.duplicated, 2);
        expect(summary.inserted, 1);
        expect(await database.getNote('source'), source);
        expect(await database.getNote('target'), target);

        final all = [
          ...await database.loadNotes('ספר'),
          ...await database.loadNotes(_general),
        ];
        final sourceCopy = all.singleWhere(
          (n) => n.id != 'source' && n.bookId == 'ספר',
        );
        final targetCopy = all.singleWhere(
          (n) => n.id != 'target' && n.id != 'outside' && n.isGeneralNote,
        );
        expect(
          sourceCopy.content,
          contains(personalNoteLinkUrl(targetCopy.id)),
        );
        expect(sourceCopy.content, isNot(contains('id=target"')));

        final outsideNote = all.singleWhere((n) => n.id == 'outside');
        expect(
          outsideNote.contentPlain,
          'otzaria://note?id=${targetCopy.id} ו-otzaria://note?id=other',
        );
      },
    );

    test('מזג שומר מזהים, ולכן הקישורים נשארים כמות שהם', () async {
      final service = PersonalNotesImportExportService();
      final source = _note(
        'source',
        content: _linkDelta('יעד', 'target'),
        format: PersonalNoteContentFormat.quillDelta,
      );
      final file = File('${root.path}/merge.json');
      await file.writeAsString(
        jsonEncode(
          service.buildExport(notes: [source, _generalNote('target')]),
        ),
      );

      await service.importFromFile(
        path: file.path,
        strategy: NotesImportConflictStrategy.merge,
      );

      expect((await database.getNote('source'))!.content, source.content);
      expect(await database.getNote('target'), isNotNull);
    });
  });

  group('כתובות קישור להערה', () {
    test('מזהה יעד רק בקישור להערה', () {
      expect(personalNoteLinkTarget(personalNoteLinkUrl('pn_1_ab')), 'pn_1_ab');
      expect(personalNoteLinkTarget('otzaria://note?line=4'), isNull);
      expect(personalNoteLinkTarget('otzaria://note?id=%FF'), isNull);
      expect(personalNoteLinkTarget('otzaria://note-marker?id=x'), isNull);
      expect(personalNoteLinkTarget('otzaria://book?bookId=a&line=1'), isNull);
      expect(personalNoteLinkTarget('https://example.com'), isNull);
    });

    test('מחליף רק מזהים שבמפה, גם בתוך JSON של Delta', () {
      final delta = _linkDelta('א', 'old');
      final encoded = personalNoteLinkUrl('ישן & /');
      expect(personalNoteLinkTarget(encoded), 'ישן & /');
      expect(
        remapPersonalNoteLinks('ראה $encoded.', {'ישן & /': 'new'}),
        'ראה ${personalNoteLinkUrl('new')}.',
      );
      expect(
        remapPersonalNoteLinks('https://example.com/?target=$encoded', {
          'ישן & /': 'new',
        }),
        'https://example.com/?target=$encoded',
      );
      final remapped = remapPersonalNoteLinks(delta, {'old': 'new'});
      expect(
        jsonDecode(remapped)[1]['attributes']['link'],
        personalNoteLinkUrl('new'),
      );
      expect(remapPersonalNoteLinks(delta, {'other': 'new'}), delta);
      expect(
        remapPersonalNoteLinks('otzaria://note?id=old2', {'old': 'new'}),
        'otzaria://note?id=old2',
      );
    });
  });

  test('ייבוא מקביל עם אותו שעון ומחולל אינו מאבד עותקים או קישורים', () async {
    PersonalNotesImportExportService importer() =>
        PersonalNotesImportExportService(
          database: database,
          random: Random(1),
          now: () => DateTime.utc(2026, 11, 20),
        );
    final store = _note('target', content: 'מקור מקומי');
    await database.insertNote(store);
    final file = File('${root.path}/notes.json');
    await file.writeAsString(
      jsonEncode(
        importer().buildExport(
          notes: [
            _note(
              'source',
              content: _linkDelta('יעד', 'target'),
              format: PersonalNoteContentFormat.quillDelta,
            ),
            _note('target', content: 'עותק מיובא'),
          ],
        ),
      ),
    );

    await Future.wait([
      importer().importFromFile(
        path: file.path,
        strategy: NotesImportConflictStrategy.keepBoth,
      ),
      importer().importFromFile(
        path: file.path,
        strategy: NotesImportConflictStrategy.keepBoth,
      ),
    ]);

    final notes = await database.loadNotes(store.bookId);
    final sourceNotes = notes.where(
      (n) => n.contentFormat == PersonalNoteContentFormat.quillDelta,
    );
    final targetIds = [
      for (final note in sourceNotes)
        personalNoteLinkTarget(
          jsonDecode(note.content)[1]['attributes']['link'] as String,
        ),
    ];
    expect(notes, hasLength(5));
    expect(targetIds.toSet(), hasLength(2));
    for (final id in targetIds) {
      expect((await database.getNote(id!))?.content, 'עותק מיובא');
    }
    expect(await database.getNote(store.id), store);
  });
}
