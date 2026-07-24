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

  testWidgets('כתובת otzaria:// שהודבקה כטקסט רגיל הופכת לקישור לחיץ', (
    tester,
  ) async {
    final note = PersonalNote(
      id: 'pn_1',
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: jsonEncode([
        {'insert': 'ראה otzaria://open/book/2156 כאן'},
        {'insert': '\n'},
      ]),
      contentPlain: 'ראה otzaria://open/book/2156 כאן',
      contentFormat: PersonalNoteContentFormat.quillDelta,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    String? tappedUrl;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalNoteContentView(
            note: note,
            onLinkTap: (url) => tappedUrl = url,
          ),
        ),
      ),
    );

    // הכתובת זוהתה כקישור ומופיעה כ-chip לחיץ.
    expect(find.byType(ActionChip), findsOneWidget);
    await tester.tap(find.byType(ActionChip));
    expect(tappedUrl, 'otzaria://open/book/2156');
  });

  testWidgets('בונה מחדש את הקישורים כשה-note מתחלף', (tester) async {
    PersonalNote noteWithLink(String label, String url) => PersonalNote(
      id: 'pn_1',
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: jsonEncode([
        {
          'insert': label,
          'attributes': {'link': url},
        },
        {'insert': '\n'},
      ]),
      contentPlain: label,
      contentFormat: PersonalNoteContentFormat.quillDelta,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    late StateSetter setState;
    var note = noteWithLink('קישור ראשון', 'otzaria://book?bookId=A&line=1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              // אותו מיקום ב-widget tree (ללא key ייחודי) → החלפת ה-note
              // עוברת דרך didUpdateWidget ולא דרך initState של מופע חדש.
              return PersonalNoteContentView(note: note);
            },
          ),
        ),
      ),
    );

    expect(find.text('קישור ראשון'), findsOneWidget);

    setState(() {
      note = noteWithLink('קישור שני', 'otzaria://book?bookId=B&line=2');
    });
    await tester.pump();

    expect(find.text('קישור ראשון'), findsNothing);
    expect(find.text('קישור שני'), findsOneWidget);
  });

  testWidgets('maxPreviewChars מקצר טקסט פשוט ארוך', (tester) async {
    final note = PersonalNote(
      id: 'pn_1',
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: 'א' * 500,
      contentPlain: 'א' * 500,
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalNoteContentView(note: note, maxPreviewChars: 100),
        ),
      ),
    );

    final textWidget = tester.widget<Text>(find.byType(Text));
    // 100 תווים + תו ההשמטה
    expect(textWidget.data, '${'א' * 100}…');
  });

  testWidgets('תצוגה מקדימה של Delta ארוך נבנית ללא שגיאה', (tester) async {
    final note = PersonalNote(
      id: 'pn_1',
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: jsonEncode([
        {'insert': 'מילה ' * 1000},
        {'insert': '\n'},
      ]),
      contentPlain: 'מילה ' * 1000,
      contentFormat: PersonalNoteContentFormat.quillDelta,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: PersonalNoteContentView(note: note, maxPreviewChars: 120),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(PersonalNoteContentView), findsOneWidget);
  });

  testWidgets('שינוי maxPreviewChars בונה מחדש ומסנן קישורים שמעבר לסף', (
    tester,
  ) async {
    final note = PersonalNote(
      id: 'pn_1',
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: jsonEncode([
        {'insert': 'אבג '}, // 4 תווים
        {
          'insert': 'קישור',
          'attributes': {'link': 'https://example.com'},
        },
        {'insert': '\n'},
      ]),
      contentPlain: 'אבג קישור',
      contentFormat: PersonalNoteContentFormat.quillDelta,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    late StateSetter setState;
    var maxChars = 3;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return PersonalNoteContentView(
                note: note,
                maxPreviewChars: maxChars,
              );
            },
          ),
        ),
      ),
    );

    // עם סף של 3 תווים הקישור (מתחיל ב-offset 4) נחתך → אין chip
    expect(find.byType(ActionChip), findsNothing);

    // הגדלת הסף בונה מחדש (didUpdateWidget) וכוללת את הקישור
    setState(() => maxChars = 100);
    await tester.pump();

    expect(find.byType(ActionChip), findsOneWidget);
  });

  testWidgets('PersonalNotesListView מציגה את כל ההערות של השורה עם מפריד', (
    tester,
  ) async {
    PersonalNote plainNote(String id, String text) => PersonalNote(
      id: id,
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: text,
      contentPlain: text,
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalNotesListView(
            notes: [
              plainNote('pn_1', 'הערה ראשונה'),
              plainNote('pn_2', 'הערה שנייה'),
            ],
          ),
        ),
      ),
    );

    // שתי ההערות מוצגות (לא רק האחרונה), עם מפריד אחד ביניהן.
    expect(find.text('הערה ראשונה'), findsOneWidget);
    expect(find.text('הערה שנייה'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });
}
