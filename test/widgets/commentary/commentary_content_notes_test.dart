import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';

PersonalNote _note({
  required String id,
  required int? lineNumber,
  PersonalNoteStatus status = PersonalNoteStatus.located,
}) {
  final now = DateTime(2026, 1, 1);
  return PersonalNote(
    id: id,
    bookId: 'רש״י',
    lineNumber: lineNumber,
    lastKnownLineNumber: null,
    status: status,
    content: 'תוכן ההערה',
    contentPlain: 'תוכן ההערה',
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('מפרש מקבל רק הערות ממוקמות של הפסקה שלו', () {
    final notes = <PersonalNote>[
      _note(id: 'current', lineNumber: 3),
      _note(id: 'other-line', lineNumber: 4),
      _note(
        id: 'missing',
        lineNumber: null,
        status: PersonalNoteStatus.missing,
      ),
    ];

    final byLine = indexCommentaryNotesByLine(notes);
    final result = commentaryNotesForLine(byLine, 3);

    expect(result.map((note) => note.id), <String>['current']);
    expect(byLine.keys, <int>[3, 4]);
  });

  test('אינדקס הערות גדול נבנה פעם אחת ושומר סדר בכל שורה', () {
    final notes = <PersonalNote>[
      for (var i = 0; i < 10000; i++)
        _note(id: 'n$i', lineNumber: (i % 100) + 1),
    ];

    final byLine = indexCommentaryNotesByLine(notes);

    expect(byLine.length, 100);
    expect(commentaryNotesForLine(byLine, 1).length, 100);
    expect(
      commentaryNotesForLine(byLine, 1).take(3).map((note) => note.id),
      <String>['n0', 'n100', 'n200'],
    );
    expect(commentaryNotesForLine(byLine, 101), isEmpty);
  });

  testWidgets('לחיצה על סימון מפרש פותחת את תוכן ההערה', (tester) async {
    late ValueChanged<int>? handler;
    final note = _note(id: 'current', lineNumber: 3);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            handler = commentaryNoteTapHandler(context, [note]);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(handler, isNotNull);
    handler!(2);
    await tester.pumpAndSettle();

    expect(find.text('הערה אישית'), findsOneWidget);
    expect(find.text('תוכן ההערה'), findsOneWidget);
  });

  testWidgets('כשיש יעד ללשונית, הלחיצה מעבירה את ספר ושורת המפרש', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final link = Link(
      heRef: 'רש"י',
      index1: 1,
      path2: 'רש"י',
      index2: 7,
      connectionType: 'commentary',
    );
    Link? capturedLink;
    int? capturedLine;

    openCommentaryPersonalNote(
      context: context,
      link: link,
      notes: [_note(id: 'current', lineNumber: 7)],
      onOpenPersonalNote: (target, line) {
        capturedLink = target;
        capturedLine = line;
      },
    );

    expect(capturedLink, same(link));
    expect(capturedLine, 7);
    expect(find.text('הערה אישית'), findsNothing);
  });
}
