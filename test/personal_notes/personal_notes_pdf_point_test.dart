import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_import_export_service.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_filter.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  final service = PersonalNotesService(database: database);
  late Directory root;
  const point = PdfNoteAnchor(
    pageNumber: 47,
    x: .21,
    y: .78,
    documentId: 'user|document.pdf',
  );

  PersonalNote note({String id = 'point', PdfNoteAnchor? anchor = point}) =>
      PersonalNote(
        id: id,
        bookId: 'מסמך בדיקה|user',
        lineNumber: 47,
        pdfAnchor: anchor,
        lastKnownLineNumber: null,
        status: PersonalNoteStatus.located,
        content: 'תוכן הערה',
        contentPlain: 'תוכן הערה',
        contentFormat: PersonalNoteContentFormat.plain,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('pdf_note_point_');
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

  test('JSON ישן נשאר ללא נקודה; JSON חדש ו-copyWith משמרים אותה', () {
    final old = note(anchor: null);
    expect(old.toJson()['pdfAnchor'], isNull);
    expect(old.toJson().containsKey('pdfAnchor'), isTrue);
    final legacyJson = old.toJson()..remove('pdfAnchor');
    expect(PersonalNote.fromJson(legacyJson), old);
    final saved = note();
    expect(
      PersonalNote.fromJson(jsonDecode(jsonEncode(saved.toJson()))),
      saved,
    );
    expect(saved.copyWith(content: 'עריכה').pdfAnchor, point);
    expect(saved.copyWith(clearPdfAnchor: true).pdfAnchor, isNull);
    for (final invalid in [
      {'pageNumber': 0, 'x': .5, 'y': .5},
      {'pageNumber': 1, 'x': -1, 'y': .5},
      {'pageNumber': 1, 'x': .5, 'y': 2},
      {'pageNumber': 1, 'x': double.nan, 'y': .5},
      {'pageNumber': 1, 'x': .5},
    ]) {
      expect(() => PdfNoteAnchor.fromJson(invalid), throwsFormatException);
    }
  });

  test('מסד ישן מוסיף עמודות בלי לשנות הערות קיימות', () async {
    final path = await AppPaths.resolveNotesDbPath('personal_notes.db');
    final legacy = sqlite3.open(path);
    legacy.execute('''
      CREATE TABLE personal_notes (
        id TEXT PRIMARY KEY, book_id TEXT NOT NULL, line_number INTEGER,
        display_title TEXT, last_known_line INTEGER, status TEXT NOT NULL,
        content TEXT NOT NULL, content_plain TEXT NOT NULL DEFAULT '',
        content_format TEXT NOT NULL DEFAULT 'plain',
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    legacy.execute('''
      INSERT INTO personal_notes
      (id, book_id, line_number, status, content, content_plain, created_at, updated_at)
      VALUES ('legacy', 'מסמך בדיקה|user', 47, 'located', 'ישן', 'ישן',
        '2026-01-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z')
    ''');
    legacy.close();

    final before = (await database.loadNotes(note().bookId)).single;
    expect(before.id, 'legacy');
    expect(before.lineNumber, 47);
    expect(before.pdfAnchor, isNull);
    await database.insertNote(note());
    await database.close();

    final after = await database.loadNotes(note().bookId);
    expect(after.singleWhere((item) => item.id == 'legacy'), before);
    expect(after.singleWhere((item) => item.id == 'point'), note());
    expect(
      (await database.database)
          .select('PRAGMA table_info(personal_notes)')
          .map((row) => row['name']),
      containsAll(['pdf_page', 'pdf_x', 'pdf_y', 'pdf_document_id']),
    );
  });

  test(
    'בחירת PDF ללא טקסט נשמרת, ומקור טקסט מקביל אינו משנה את הנקודה',
    () async {
      final notes = await service.addNote(
        bookId: note().bookId,
        bookContent: '',
        lineNumber: 999,
        pdfAnchor: point,
        selectedText: 'בחירה מתוך המסמך',
        content: 'תוכן',
        contentPlain: 'תוכן',
        contentFormat: PersonalNoteContentFormat.plain,
      );
      final saved = notes.single;
      expect(saved.lineNumber, 47);
      expect(saved.pdfAnchor, point);
      expect(saved.anchorText, isNull);
      expect(saved.displayTitle, 'בחירה מתוך המסמך');
      await database.close();
      final loaded = await service.loadNotes(
        bookId: saved.bookId,
        bookContent: 'טקסט אחר\nקצר יותר',
      );
      expect(loaded.single, saved);
    },
  );

  test('PDF עם טקסט מקביל אינו משתמש במספר עמוד כבשורת טקסט', () async {
    final notes = await service.addNote(
      bookId: note().bookId,
      bookContent: 'שורה ראשונה\nשורה שנייה',
      lineNumber: 1,
      pdfAnchor: point,
      content: 'תוכן',
      contentPlain: 'תוכן',
      contentFormat: PersonalNoteContentFormat.plain,
    );
    expect(notes.single.lineNumber, 47);
    expect(notes.single.displayTitle, isEmpty);
    expect(notes.single.status, PersonalNoteStatus.located);
  });

  test('עריכה ועיגון מחדש שומרים תוכן, מזהה וזמן יצירה', () async {
    final saved = note();
    await database.insertNote(saved);
    await service.updateNote(
      bookId: saved.bookId,
      bookContent: 'שורה',
      noteId: saved.id,
      content: 'עריכה',
      contentPlain: 'עריכה',
    );
    expect((await database.getNote(saved.id))!.pdfAnchor, point);
    const moved = PdfNoteAnchor(pageNumber: 9, x: .85, y: .1);
    await service.repositionNote(
      bookId: saved.bookId,
      bookContent: 'שורה',
      noteId: saved.id,
      lineNumber: 1,
      pdfAnchor: moved,
    );
    await database.close();
    final reloaded = (await database.getNote(saved.id))!;
    expect(reloaded.pdfAnchor, moved);
    expect(reloaded.lineNumber, 9);
    expect(reloaded.contentPlain, 'עריכה');
    expect(reloaded.createdAt, saved.createdAt);
    expect(reloaded.status, PersonalNoteStatus.located);
  });

  test('גיבוי וייבוא מחזירים יחד הערות ישנות ונקודות PDF', () async {
    final saved = [note(), note(id: 'legacy', anchor: null)];
    await database.batchInsertNotes(saved);
    final backup = PersonalNotesImportExportService(database: database);
    final payload = backup.buildExport(
      notes: await database.loadNotes(note().bookId),
    );
    final file = File('${root.path}/backup.json');
    await file.writeAsString(jsonEncode(payload));
    for (final item in saved) {
      await database.deleteNote(item.id);
    }
    final summary = await backup.importFromFile(
      path: file.path,
      strategy: NotesImportConflictStrategy.merge,
    );
    expect(summary.inserted, 2);
    await database.close();
    expect(await database.loadNotes(note().bookId), unorderedEquals(saved));
  });

  test('גיבוי ישן משמר נקודה מקומית, ואילו null מפורש מסיר אותה', () async {
    final original = note();
    final backup = PersonalNotesImportExportService(database: database);
    await database.insertNote(original);
    Future<void> import(Map<String, dynamic> data) async {
      final file = File('${root.path}/restore.json');
      await file.writeAsString(
        jsonEncode({
          'version': '2.0',
          'notes': [data],
        }),
      );
      await backup.importFromFile(
        path: file.path,
        strategy: NotesImportConflictStrategy.merge,
      );
    }

    final legacy =
        original
            .copyWith(
              content: 'עריכה ישנה',
              contentPlain: 'עריכה ישנה',
              updatedAt: DateTime.utc(2026, 2, 1),
            )
            .toJson()
          ..remove('pdfAnchor');
    await import(legacy);
    expect((await database.getNote(original.id))!.pdfAnchor, point);

    final cleared = original.copyWith(
      clearPdfAnchor: true,
      updatedAt: DateTime.utc(2026, 3, 1),
    );
    final payload = backup.buildExport(notes: [cleared]);
    final data = (payload['notes'] as List).single as Map<String, dynamic>;
    expect(data.containsKey('pdfAnchor'), isTrue);
    expect(data['pdfAnchor'], isNull);
    await import(data);
    await database.close();
    expect((await database.getNote(original.id))!.pdfAnchor, isNull);
  });

  for (final lastKnown in [47, 48]) {
    test('ייבוא PDF חסר משמר נקודה רק כשרמז המיקום זהה ($lastKnown)', () async {
      final original = PersonalNote.fromJson({
        ...note().toJson(),
        'lineNumber': null,
        'status': PersonalNoteStatus.missing.name,
        'lastKnownLineNumber': 47,
      });
      await database.insertNote(original);
      final imported =
          original
              .copyWith(
                content: 'תוכן מהגיבוי',
                contentPlain: 'תוכן מהגיבוי',
                updatedAt: DateTime.utc(2026, 2, 1),
              )
              .toJson()
            ..remove('pdfAnchor')
            ..['lastKnownLineNumber'] = lastKnown;
      final file = File('${root.path}/missing-pdf-backup.json');
      await file.writeAsString(
        jsonEncode({
          'version': '2.0',
          'notes': [imported],
        }),
      );
      final backup = PersonalNotesImportExportService(database: database);
      final summary = await backup.importFromFile(
        path: file.path,
        strategy: NotesImportConflictStrategy.merge,
      );
      final restored = (await database.getNote(original.id))!;
      expect(summary.updated, 1);
      expect(restored.content, 'תוכן מהגיבוי');
      expect(restored.lastKnownLineNumber, lastKnown);
      expect(restored.pdfAnchor, lastKnown == 47 ? point : isNull);
    });
  }

  test('סינון עמוד PDF אינו מתבלבל עם השורות הלוגיות או מהדורת הטקסט', () {
    final pointNote = note().copyWith(lineNumber: 1);
    final otherPage =
        note(
          id: 'other',
        ).copyWith(
          pdfAnchor: const PdfNoteAnchor(
            pageNumber: 48,
            x: .5,
            y: .5,
            documentId: 'user|document.pdf',
          ),
        );
    final textNote = note(id: 'text', anchor: null).copyWith(lineNumber: 1);
    final notes = [pointNote, otherPage, textNote];
    final pdf = filterPersonalNotes(
      locatedNotes: notes,
      missingNotes: [],
      searchQuery: '',
      showOnlyVisible: true,
      visibleLineIndices: [0],
      isPdf: true,
      pdfDocumentId: point.documentId,
      visiblePdfPages: [47],
    );
    expect(pdf.locatedNotes.map((n) => n.id), ['point', 'text']);
    final text = filterPersonalNotes(
      locatedNotes: notes,
      missingNotes: [],
      searchQuery: '',
      showOnlyVisible: false,
      visibleLineIndices: [],
    );
    expect(text.locatedNotes, [textNote]);
  });

  test('שתי מהדורות PDF באותו key אינן רואות זו את נקודותיה של זו', () {
    final first = note();
    final second = note(
      id: 'second',
      anchor: const PdfNoteAnchor(
        pageNumber: 47,
        x: .21,
        y: .78,
        documentId: 'user|second.pdf',
      ),
    );
    final unidentified = note(
      id: 'unknown',
      anchor: const PdfNoteAnchor(pageNumber: 47, x: .21, y: .78),
    );
    final legacy = note(id: 'legacy', anchor: null);
    List<String> filtered(String identity, {bool includeUnknown = false}) =>
        filterPersonalNotes(
          locatedNotes: [first, second, unidentified, legacy],
          missingNotes: [],
          searchQuery: '',
          showOnlyVisible: false,
          visibleLineIndices: [],
          isPdf: true,
          pdfDocumentId: identity,
          includeUnidentifiedPdfAnchors: includeUnknown,
        ).locatedNotes.map((note) => note.id).toList();
    expect(filtered('user|document.pdf'), ['point', 'legacy']);
    expect(filtered('user|second.pdf'), ['second', 'legacy']);
    expect(filtered('user|document.pdf', includeUnknown: true), [
      'point',
      'unknown',
      'legacy',
    ]);
  });
}
