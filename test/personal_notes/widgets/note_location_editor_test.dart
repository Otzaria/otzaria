import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/personal_notes/utils/note_location_edit.dart';
import 'package:otzaria/personal_notes/widgets/note_location_editor.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

const _lines = [
  'שורה ראשונה',
  'ויאמר אלהים יהי אור ויהי אור',
  'וירא אלהים את האור כי טוב',
];

PersonalNote _note(String anchorText) {
  final now = DateTime(2026);
  return PersonalNote(
    id: 'n',
    bookId: 'ספר',
    lineNumber: 2,
    anchorText: normalizeAnchorText(anchorText),
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: 'הערה',
    contentPlain: 'הערה',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pump(WidgetTester tester, NoteLocationEdit edit) async {
  await tester.binding.setSurfaceSize(const Size(640, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: NoteLocationEditor(edit: edit, selectedLine: 3),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('מילים: הוספה בקצה, הזזה, ומעבר לשורות ולספר', (tester) async {
    final edit = NoteLocationEdit.of(_note('יהי'), _lines)!;
    await _pump(tester, edit);

    await tester.tap(find.byTooltip('הוספת מילה בסוף'));
    await tester.pump();
    expect(edit.range.text, 'יהי אור');

    await tester.tap(find.byTooltip('הזזה במילה קדימה'));
    await tester.pump();
    expect(edit.range.text, 'אור ויהי');

    await tester.tap(find.text('שורות'));
    await tester.pump();
    expect(edit.scope, PersonalNoteScope.lines);
    await tester.tap(find.byTooltip('הוספת שורה בסוף'));
    await tester.pump();
    expect(edit.range.end.paragraph, 2);
    expect(find.textContaining('2 שורות'), findsOneWidget);

    await tester.tap(find.text('כל הספר'));
    await tester.pump();
    expect(edit.scope, PersonalNoteScope.book);
    expect(find.byTooltip('הוספת שורה בסוף'), findsNothing);
    expect(edit.changed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('העברה לשורה שנבחרה, וחזרה למה שנשמר', (tester) async {
    final edit = NoteLocationEdit.of(_note('יהי'), _lines)!;
    await _pump(tester, edit);

    await tester.tap(find.text('העברה לשורה שנבחרה בספר'));
    await tester.pump();
    expect(edit.range.text, 'וירא אלהים את האור כי טוב');

    await tester.tap(find.text('חזרה למה שנשמר'));
    await tester.pump();
    expect(edit.range.text, 'יהי');
    expect(edit.scope, PersonalNoteScope.words);
    expect(edit.changed, isFalse);
  });

  testWidgets('חזרה למה שנשמר מחזירה גם את סוג המיקום', (tester) async {
    final book = _note('יהי').copyWith(
      status: PersonalNoteStatus.book,
      clearLineNumber: true,
      clearAnchor: true,
    );
    final edit = NoteLocationEdit.of(book, _lines, fallbackLine: 2)!;
    await _pump(tester, edit);
    final reset = find.widgetWithText(ActionButton, 'חזרה למה שנשמר');
    expect(tester.widget<ActionButton>(reset).onPressed, isNull);

    await tester.tap(find.text('שורות'));
    await tester.pump();
    expect(edit.differs, isTrue);
    await tester.tap(reset);
    await tester.pump();
    expect(edit.scope, PersonalNoteScope.book);
    expect(edit.changed, isFalse);
  });
}
