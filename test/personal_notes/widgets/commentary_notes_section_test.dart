import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/commentary_notes_section.dart';

PersonalNote _note(String bookId, int? line, String text, {String? title}) {
  final now = DateTime(2026);
  return PersonalNote(
    id: '$bookId-$line-$text',
    bookId: bookId,
    lineNumber: line,
    displayTitle: title,
    lastKnownLineNumber: line,
    status: line == null
        ? PersonalNoteStatus.missing
        : PersonalNoteStatus.located,
    content: text,
    contentPlain: text,
    contentFormat: PersonalNoteContentFormat.plain,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Map<String, List<PersonalNote>> store;
  late ValueNotifier<int> revision;
  final opened = <(String, int)>[];

  setUp(() {
    store = {};
    revision = ValueNotifier(0);
    opened.clear();
  });

  Widget build(List<String> bookIds) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CommentaryNotesSection(
          bookIds: bookIds,
          revision: revision,
          loader: (bookId, {categoryId}) async => store[bookId] ?? const [],
          onOpenNote: (bookId, line) => opened.add((bookId, line)),
        ),
      ),
    ),
  );

  testWidgets('מציג רק מפרשים עם הערות ממוקמות, ולחיצה פותחת את ההערה', (
    tester,
  ) async {
    store = {
      'רש"י': [_note('רש"י', 4, 'הערה על רש"י', title: 'רש"י ד"ה אמר')],
      'תוספות': [_note('תוספות', null, 'הערה חסרת מיקום')],
    };

    await tester.pumpWidget(build(['רש"י', 'תוספות']));
    await tester.pumpAndSettle();

    expect(find.text('הערות על המפרשים המוצגים'), findsOneWidget);
    expect(find.text('רש"י ד"ה אמר'), findsOneWidget);
    expect(find.text('תוספות'), findsNothing);

    await tester.tap(find.text('הערה על רש"י'));
    expect(opened, [('רש"י', 4)]);
  });

  testWidgets('בלי הערות על המפרשים האזור לא מוצג', (tester) async {
    await tester.pumpWidget(build(['רש"י']));
    await tester.pumpAndSettle();

    expect(find.text('הערות על המפרשים המוצגים'), findsNothing);
  });

  testWidgets('נטען מחדש כשהערה נשמרת', (tester) async {
    await tester.pumpWidget(build(['רש"י']));
    await tester.pumpAndSettle();
    expect(find.text('הערות על המפרשים המוצגים'), findsNothing);

    store['רש"י'] = [_note('רש"י', 2, 'חדשה')];
    revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('שורה 2'), findsOneWidget);
    expect(find.text('חדשה'), findsOneWidget);
  });
}
