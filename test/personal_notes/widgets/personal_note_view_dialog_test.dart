import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/utils/note_link_detection.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_link_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_view_dialog.dart';

PersonalNote _note(
  String id, {
  String bookId = 'ספר',
  int? lineNumber = 4,
  PersonalNoteStatus status = PersonalNoteStatus.located,
  required String content,
  PersonalNoteContentFormat format = PersonalNoteContentFormat.plain,
  String contentPlain = '',
}) => PersonalNote(
  id: id,
  bookId: bookId,
  lineNumber: lineNumber,
  displayTitle: lineNumber == null ? null : 'כותרת $id',
  lastKnownLineNumber: null,
  status: status,
  content: content,
  contentPlain: contentPlain.isEmpty ? content : contentPlain,
  contentFormat: format,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 2),
);

PersonalNote _linkingNote(String targetUrl) => _note(
  'a',
  content: jsonEncode([
    {'insert': 'ראה '},
    {
      'insert': 'יעד',
      'attributes': {'link': targetUrl},
    },
    {'insert': '\n'},
  ]),
  contentPlain: 'ראה יעד',
  format: PersonalNoteContentFormat.quillDelta,
);

Future<void> _dismissSnack(WidgetTester tester) async {
  UiSnack.hide();
  await tester.pump(const Duration(seconds: 7));
}

void main() {
  late BuildContext hostContext;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }

  testWidgets('מציג את כל ההערה לקריאה ומעביר לעריכה אחרי סגירה', (
    tester,
  ) async {
    await pumpHost(tester);
    final longText = '${'מילה ' * 120}סוף ההערה';
    final note = _note('a', content: longText);
    PersonalNote? edited;
    PersonalNote? opened;

    showPersonalNoteViewDialog(
      hostContext,
      note,
      subtitleFor: (_) => 'ספר · דף ב',
      onEdit: (n) => edited = n,
      onOpenInBook: (n) => opened = n,
    );
    await tester.pumpAndSettle();

    expect(find.byType(PersonalNoteViewDialog), findsOneWidget);
    expect(find.textContaining('סוף ההערה'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text(longText),
        matching: find.byType(SelectionArea),
      ),
      findsOneWidget,
    );
    expect(find.text('כותרת a'), findsOneWidget);
    expect(find.text('ספר · דף ב'), findsOneWidget);
    expect(find.text('פתח בספר'), findsOneWidget);

    await tester.tap(find.text('עריכה'));
    await tester.pumpAndSettle();

    expect(find.byType(PersonalNoteViewDialog), findsNothing);
    expect(edited, note);
    expect(opened, isNull);
  });

  testWidgets('הערה כללית ללא כפתור פתיחה בספר', (tester) async {
    await pumpHost(tester);
    showPersonalNoteViewDialog(
      hostContext,
      _note(
        'g',
        bookId: PersonalNote.generalBookId,
        lineNumber: null,
        status: PersonalNoteStatus.book,
        content: 'לזכור',
      ),
      onEdit: (_) {},
      onOpenInBook: (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.text('הערה כללית'), findsOneWidget);
    expect(find.text('פתח בספר'), findsNothing);
    expect(find.text('עריכה'), findsOneWidget);
  });

  testWidgets('קישור להערה מחליף את התצוגה בהערת היעד', (tester) async {
    await pumpHost(tester);
    final target = _note('b', content: 'תוכן היעד');
    final lookups = <String>[];

    showPersonalNoteViewDialog(
      hostContext,
      _linkingNote(personalNoteLinkUrl('b')),
      findNote: (id) async {
        lookups.add(id);
        return id == 'b' ? target : null;
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'יעד'));
    await tester.pumpAndSettle();

    expect(lookups, ['b']);
    expect(find.byType(PersonalNoteViewDialog), findsOneWidget);
    expect(find.text('תוכן היעד'), findsOneWidget);
    expect(find.text('כותרת b'), findsOneWidget);
  });

  testWidgets('תוצאת קישור מאוחר אינה סוגרת את המסך שמאחורי העיון', (
    tester,
  ) async {
    await pumpHost(tester);
    final navigator = Navigator.of(hostContext);
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('מסך קודם')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final result = Completer<PersonalNote?>();
    unawaited(
      showPersonalNoteViewDialog(
        hostContext,
        _linkingNote(personalNoteLinkUrl('b')),
        findNote: (_) => result.future,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'יעד'));
    await tester.tap(find.text('סגור'));
    await tester.pump();
    result.complete(_note('b', content: 'תוכן היעד'));
    await tester.pumpAndSettle();

    expect(find.text('מסך קודם'), findsOneWidget);
    expect(find.byType(PersonalNoteViewDialog), findsNothing);
  });

  testWidgets('קישור להערה שנמחקה מודיע ונשאר בהערה הנוכחית', (tester) async {
    await pumpHost(tester);
    showPersonalNoteViewDialog(
      hostContext,
      _linkingNote(personalNoteLinkUrl('deleted')),
      findNote: (_) async => null,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'יעד'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(NotesMessages.linkedNoteDeleted), findsOneWidget);
    expect(find.byType(PersonalNoteViewDialog), findsOneWidget);
    expect(find.text('כותרת a'), findsOneWidget);
    await _dismissSnack(tester);
  });

  testWidgets('קישור שאינו להערה עובר למטפל עם ההערה שבה נלחץ', (
    tester,
  ) async {
    await pumpHost(tester);
    PersonalNote? source;
    String? url;
    final note = _linkingNote('https://example.com/x');

    showPersonalNoteViewDialog(
      hostContext,
      note,
      onLinkTap: (s, u) {
        source = s;
        url = u;
      },
      findNote: (_) async => fail('not a note link'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'יעד'));
    await tester.pumpAndSettle();

    expect(source, note);
    expect(url, 'https://example.com/x');
  });

  testWidgets('openLinkedPersonalNote מודיע כשהיעד נמחק', (tester) async {
    await pumpHost(tester);
    openLinkedPersonalNote(hostContext, 'gone', findNote: (_) async => null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(NotesMessages.linkedNoteDeleted), findsOneWidget);
    expect(find.byType(PersonalNoteViewDialog), findsNothing);
    await _dismissSnack(tester);
  });

  testWidgets('בהערה כללית אין לשונית קישור לספר', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PersonalNoteLinkDialog(
            notes: [],
            bookId: PersonalNote.generalBookId,
          ),
        ),
      ),
    );

    expect(find.text('קישור לספר'), findsNothing);
    expect(find.text('קישור להערה'), findsOneWidget);
    expect(find.text('חיפוש הערה'), findsOneWidget);
  });
}
