import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';

class _MemoryNotesDb implements PersonalNotesDatabase {
  final notes = <String, PersonalNote>{};
  int loads = 0;
  void Function()? afterSnapshot;

  @override
  final revision = ValueNotifier<int>(0);

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async {
    loads++;
    final snapshot = notes.values
        .where((note) => note.bookId == bookId)
        .toList();
    afterSnapshot?.call();
    return snapshot;
  }

  @override
  Future<void> batchUpdateNotes(List<PersonalNote> changed) async {
    for (final note in changed) {
      notes[note.id] = note;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PersonalNote _note(String id, int line) => PersonalNote(
  id: id,
  bookId: 'ספר',
  lineNumber: line,
  displayTitle: 'שורה $line',
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: 'הערה',
  contentPlain: 'הערה',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<int> _fastestMicros(Future<void> Function() run) async {
  var best = 1 << 62;
  for (var i = 0; i < 5; i++) {
    final stopwatch = Stopwatch()..start();
    await run();
    if (stopwatch.elapsedMicroseconds < best) {
      best = stopwatch.elapsedMicroseconds;
    }
  }
  return best;
}

void main() {
  test('קורא תוכן רק כשנדרש ומרענן אחריו את ההערות', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database);
    var contentLoads = 0;
    Future<String> loadContent() async {
      contentLoads++;
      return 'שורה 1\nשורה 2';
    }

    expect(
      await service.loadNotes(bookId: 'ספר', loadBookContent: loadContent),
      isEmpty,
    );
    expect(contentLoads, 0);
    expect(database.loads, 1);

    database.notes['book'] = _note(
      'book',
      1,
    ).copyWith(status: PersonalNoteStatus.book, clearLineNumber: true);
    database.notes['pdf'] = _note(
      'pdf',
      99,
    ).copyWith(pdfAnchor: const PdfNoteAnchor(pageNumber: 99, x: 0.2, y: 0.3));
    final unanchored = await service.loadNotes(
      bookId: 'ספר',
      loadBookContent: loadContent,
    );
    expect(unanchored, unorderedEquals(database.notes.values));
    expect(contentLoads, 0);
    expect(database.loads, 2);

    database.notes['a'] = _note('a', 1);
    database.notes['b'] = _note('b', 2);
    final reconciled = await service.loadNotes(
      bookId: 'ספר',
      loadBookContent: loadContent,
    );
    expect(reconciled, unorderedEquals(database.notes.values));
    expect(contentLoads, 1);
    expect(database.loads, 4);
  });

  test('עריכה ומחיקה בזמן קריאת התוכן נשמרות ביישוב', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database);
    database.notes['a'] = _note('a', 9);
    database.notes['deleted'] = _note('deleted', 9);
    final started = Completer<void>();
    final content = Completer<String>();
    final loading = service.loadNotes(
      bookId: 'ספר',
      loadBookContent: () {
        started.complete();
        return content.future;
      },
    );
    await started.future;
    database.notes['a'] = _note(
      'a',
      1,
    ).copyWith(content: 'עריכה חדשה', contentPlain: 'עריכה חדשה');
    database.notes.remove('deleted');
    database.revision.value++;
    content.complete('שורה 1');
    final loaded = await loading;

    expect(loaded.single.contentPlain, 'עריכה חדשה');
    expect(loaded.single.lineNumber, 1);
    expect(loaded.single.status, PersonalNoteStatus.located);
    expect(database.loads, 2);
    expect(database.notes.keys, ['a']);
  });

  test('שינוי לפני חזרת קריאת ההערות הראשונה אינו נדרס', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database);
    database.notes['a'] = _note('a', 9);
    database.afterSnapshot = () {
      database.afterSnapshot = null;
      database.notes['a'] = _note('a', 1);
      database.revision.value++;
    };

    final loaded = await service.loadNotes(
      bookId: 'ספר',
      loadBookContent: () async => 'שורה 1',
    );

    expect(loaded.single.lineNumber, 1);
    expect(loaded.single.status, PersonalNoteStatus.located);
    expect(database.loads, 2);
  });

  test('ספר בלי הערות אינו מפוצל לשורות בטעינה (perf)', () async {
    // בגודל ספר גדול (כ-18 מיליון תווים בערוך השולחן); כאן 6 מיליון.
    final content = List.filled(
      200000,
      'שורה בספר עם כמה מילים לבדיקה',
    ).join('\n');
    final service = PersonalNotesService(database: _MemoryNotesDb());

    final split = await _fastestMicros(
      () async => splitBookContentIntoLines(content),
    );
    final load = await _fastestMicros(
      () => service.loadNotes(bookId: 'ספר', bookContent: content),
    );

    expect(load, lessThan(split ~/ 4), reason: 'split=$splitµs load=$loadµs');
  });

  test('ספר בלי הערות מחזיר רשימה ריקה; עם הערות היישוב לא השתנה', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database);
    const content = 'שורה 1\nשורה 2\nשורה 3';

    final empty = await service.loadNotes(bookId: 'ספר', bookContent: content);
    expect(empty, isEmpty);
    empty.add(_note('x', 1));

    database.notes['a'] = _note('a', 3);
    database.notes['b'] = _note('b', 9);
    final notes = await service.loadNotes(bookId: 'ספר', bookContent: content);

    expect(notes.map((note) => note.id), ['a', 'b']);
    expect(notes.first.status, PersonalNoteStatus.located);
    expect(notes.last.status, PersonalNoteStatus.missing);
    expect(notes.last.lastKnownLineNumber, 9);
  });
}
