import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';

PersonalNote _note(String id, int line, [int? end]) => PersonalNote(
  id: id,
  bookId: 'ספר',
  lineNumber: line,
  endLineNumber: end,
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: id,
  contentPlain: id,
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('אינדקס חוזר לפי זהות ההערות ומתעדכן בטעינה או בעריכה', () {
    final cache = PersonalNotesLineIndex();
    final firstBook = [_note('a', 3), _note('range', 2, 4)];
    final firstIndex = cache.forSnapshot(firstBook);

    expect(firstIndex[3], firstBook);
    expect(cache.forSnapshot(firstBook), same(firstIndex));

    final edited = [firstBook[0], _note('range', 6, 8)];
    final editedIndex = cache.forSnapshot(edited);
    expect(editedIndex, isNot(same(firstIndex)));
    expect(editedIndex[3], [edited[0]]);
    expect(editedIndex[7], [edited[1]]);
    expect(cache.forSnapshot(edited), same(editedIndex));

    expect(cache.forSnapshot(const []), isEmpty);
    final reloaded = [_note('b', 6)];
    final secondIndex = cache.forSnapshot(reloaded);
    expect(secondIndex[3], isNull);
    expect(secondIndex[6], reloaded);
    expect(secondIndex[7], isNull);
    expect(cache.forSnapshot(reloaded), same(secondIndex));
  });

  test('טווחים חופפים ושורות יחידות שומרים את סדר ההערות', () {
    final notes = [
      _note('a', 3),
      _note('b', 2, 4),
      _note('c', 3),
      _note('d', 3, 6),
    ];
    final index = indexPersonalNotesByLine(notes);
    expect(index[3], notes);
    expect(index[2], [notes[1]]);
    expect(index[5], [notes[3]]);
    expect(index[1], isNull);
    expect(index[7], isNull);
    expect(index.containsKey(4), isTrue);
    expect(index.containsKey(7), isFalse);
    expect(index.keys, [2, 3, 4, 5, 6]);
    expect(index.length, 5);
  });

  test('מפתחות מאחדים טווחים חופפים ונפרדים בלי לכלול את הרווחים', () {
    final notes = [
      _note('a', 2, 4),
      _note('b', 4, 6),
      _note('c', 10, 12),
      _note('d', 8),
    ];
    final index = indexPersonalNotesByLine(notes);
    expect(index.keys, [2, 3, 4, 5, 6, 8, 10, 11, 12]);
    expect(index.length, 9);
    expect(index.containsKey(7), isFalse);
    expect(index.containsKey(20), isFalse);
    expect(index[20], isNull);
  });

  test('הערות חסרות מיקום והערות ספר אינן מוסיפות מפתחות', () {
    for (final notes in <List<PersonalNote>>[
      [],
      [
        _note(
          'book',
          1,
        ).copyWith(status: PersonalNoteStatus.book, clearLineNumber: true),
      ],
      [_note('missing', 1).copyWith(status: PersonalNoteStatus.missing)],
    ]) {
      final index = indexPersonalNotesByLine(notes);
      expect(index.keys, isEmpty);
      expect(index.length, 0);
      expect(index.containsKey(1), isFalse);
      expect(index[1], isNull);
    }
  });

  test('טווח מיובא גדול נגיש בלי להקצות לפי מספר השורות', () {
    const end = 1000000000;
    final range = _note('range', 2, end);
    final index = indexPersonalNotesByLine([range, _note('single', end + 2)]);
    expect(index[2], [range]);
    expect(index[end], [range]);
    expect(index[end + 1], isNull);
    expect(index.containsKey(end), isTrue);
    expect(index.length, end);
    expect(index.keys.take(3), [2, 3, 4]);
  });

  test('אינדקס שורות יחידות אינו סורק את כל ההערות בכל גישה', () {
    final notes = [for (var i = 0; i < 10000; i++) _note('$i', i + 1)];
    final index = indexPersonalNotesByLine(notes);
    expect(index.length, notes.length);
    expect(index[8000], [notes[7999]]);
    expect(identical(index[8000], index[8000]), isTrue);
  });
}
