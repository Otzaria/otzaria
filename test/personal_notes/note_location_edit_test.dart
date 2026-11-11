import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/range_edit/text_range_edit.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/personal_notes/utils/note_location_edit.dart';

const _lines = [
  'שורה ראשונה',
  '<b>וַיֹּאמֶר</b> אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר',
  'שורה שלישית',
  'שורה רביעית',
];

PersonalNote _note({
  int? line = 2,
  int? endLine,
  String? anchorText,
  String? prefix,
  PersonalNoteStatus status = PersonalNoteStatus.located,
  int? lastKnown,
}) {
  final now = DateTime(2026);
  return PersonalNote(
    id: 'n',
    bookId: 'ספר',
    lineNumber: line,
    endLineNumber: endLine,
    anchorText: anchorText,
    anchorPrefix: prefix,
    lastKnownLineNumber: lastKnown,
    status: status,
    content: 'הערה',
    contentPlain: 'הערה',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('הערה על מילים נפתחת עליהן, גם כשהן חוזרות בשורה', () {
    final edit = NoteLocationEdit.of(
      _note(
        anchorText: normalizeAnchorText('אוֹר'),
        prefix: 'ויאמר אלהים יהי אור ויהי ',
      ),
      _lines,
    )!;
    expect(edit.scope, PersonalNoteScope.words);
    expect(edit.range.text, 'אוֹר');
    expect(
      edit.range.start.offset,
      'וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר'.lastIndexOf('אוֹר'),
    );
    expect(edit.changed, isFalse);
  });

  test('הערה על שורות נפתחת על כל הטווח', () {
    final edit = NoteLocationEdit.of(_note(line: 2, endLine: 4), _lines)!;
    expect(edit.scope, PersonalNoteScope.lines);
    expect(edit.range.unit, TextRangeUnit.paragraphs);
    expect((edit.range.start.paragraph, edit.range.end.paragraph), (1, 3));
  });

  test('הערה על הספר נפתחת בשורה הנבחרת, ומעבר לשורות הוא שינוי', () {
    final edit = NoteLocationEdit.of(
      _note(line: null, status: PersonalNoteStatus.book),
      _lines,
      fallbackLine: 3,
    )!;
    expect(edit.scope, PersonalNoteScope.book);
    expect(edit.changed, isFalse);

    edit.scope = PersonalNoteScope.lines;
    expect(edit.range.start.paragraph, 2);
    expect(edit.changed, isTrue);

    edit.scope = PersonalNoteScope.words;
    expect(edit.range.text, 'שורה שלישית');

    edit.reset();
    expect(edit.scope, PersonalNoteScope.book);
  });

  test('הערה שאיבדה מיקום נפתחת במיקומה האחרון ונשמרת גם בלי שינוי', () {
    final edit = NoteLocationEdit.of(
      _note(line: null, status: PersonalNoteStatus.missing, lastKnown: 4),
      _lines,
      fallbackLine: 1,
    )!;
    expect(edit.range.start.paragraph, 3);
    expect(edit.changed, isTrue);
  });

  test('ספר בלי שורות אינו נערך', () {
    expect(NoteLocationEdit.of(_note(), const []), isNull);
  });
}
