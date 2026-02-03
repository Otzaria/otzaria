import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';

void main() {
  testWidgets('renders link chips for delta links', (tester) async {
    final delta = jsonEncode([
      {
        'insert': 'קישור',
        'attributes': {
          'link': 'otzaria://book?bookId=Test&line=1',
        },
      },
      {'insert': '\n'},
    ]);

    final note = PersonalNote(
      id: 'pn_1',
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: delta,
      contentPlain: 'קישור',
      contentFormat: PersonalNoteContentFormat.quillDelta,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalNoteContentView(note: note),
        ),
      ),
    );

    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.text('קישור'), findsOneWidget);
  });
}
