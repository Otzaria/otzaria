import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';

void main() {
  test('הבונה מקבץ לפי שורה, ו-empty ריק', () {
    final notes =
        (BookNotesBuilder()
              ..add(3, 0, 'א', 'גוף א')
              ..add(3, 1, null, 'נספחת')
              ..add(7, 0, '*', 'גוף'))
            .build();
    expect(notes.isEmpty, isFalse);
    expect(notes.lineCount, 2);
    expect(notes.notesAt(3).map((n) => n.noteIndex), [0, 1]);
    expect(notes.notesAt(4), isEmpty);
    expect(BookNotes.empty.isEmpty, isTrue);
    expect(BookNotesBuilder().build(), same(BookNotes.empty));
  });

  test('toInlineHtml — בצורת notesForLines של הערות inline', () {
    expect(
      BookNotes.toInlineHtml((noteIndex: 0, marker: 'א', body: 'גוף')),
      '<sup class="footnote-marker">א</sup> גוף',
    );
    expect(
      BookNotes.toInlineHtml((noteIndex: 1, marker: null, body: 'גוף')),
      'גוף',
    );
  });

  group('BookNotesRepository', () {
    final repository = BookNotesRepository.instance;
    var loads = 0;
    final loaded = (BookNotesBuilder()..add(0, 0, 'א', 'גוף')).build();

    setUp(() {
      loads = 0;
      repository.clear();
      repository.debugLoader = (title, {categoryId, required source}) async {
        loads++;
        return loaded;
      };
    });
    tearDown(() {
      repository.debugLoader = null;
      repository.clear();
    });

    test('ספר אישי ומהדורה חלופית — ריק, בלי טעינה', () async {
      expect(
        (await repository.notesFor('ספר', source: BookSource.user)).isEmpty,
        isTrue,
      );
      expect(
        (await repository.notesFor('ספר', versionTitle: 'נוסח')).isEmpty,
        isTrue,
      );
      expect(loads, 0);
    });

    test('טעינה אחת לספר, ממטמון', () async {
      expect(await repository.notesFor('ספר', categoryId: 1), same(loaded));
      expect(await repository.notesFor('ספר', categoryId: 1), same(loaded));
      expect(loads, 1);
      repository.clear();
      await repository.notesFor('ספר', categoryId: 1);
      expect(loads, 2);
    });
  });
}
