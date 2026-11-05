import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_export_dialog.dart';

PersonalNote _note(String id, String bookId, {String? displayTitle}) =>
    PersonalNote(
      id: id,
      bookId: bookId,
      lineNumber: 69,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      displayTitle: displayTitle,
      content: 'בהמשך הגמרא',
      contentPlain: 'בהמשך הגמרא',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<void> _open(
  WidgetTester tester,
  List<PersonalNote> notes, {
  ValueChanged<NotesExportSelection?>? onExport,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await showDialog<NotesExportSelection>(
              context: context,
              builder: (_) => PersonalNotesExportDialog(allNotes: notes),
            );
            onExport?.call(result);
          },
          child: const Text('פתח ייצוא'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח ייצוא'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('בחירה ידנית'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'manual export distinguishes the same page in different books',
    (tester) async {
      NotesExportSelection? selection;
      await _open(
        tester,
        [
          _note('berakhot', 'ברכות|user', displayTitle: 'דף סט:'),
          _note('shabbat', 'שבת|db:fixture', displayTitle: 'דף סט:'),
        ],
        onExport: (result) => selection = result,
      );

      expect(find.text('ברכות — דף סט:'), findsOneWidget);
      expect(find.text('שבת — דף סט:'), findsOneWidget);
      expect(find.textContaining('|user'), findsNothing);
      expect(find.textContaining('|db:'), findsNothing);
      await tester.tap(find.text('שבת — דף סט:'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ברכות');
      await tester.pumpAndSettle();
      expect(find.text('ברכות — דף סט:'), findsOneWidget);
      expect(find.text('שבת — דף סט:'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      final selected = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'שבת — דף סט:'),
      );
      expect(selected.value, isTrue);

      await tester.tap(find.text('ייצא'));
      await tester.pumpAndSettle();
      expect(selection!.notes.map((note) => note.id), ['shabbat']);
    },
  );

  testWidgets('manual export shows a readable book without a location title', (
    tester,
  ) async {
    await _open(tester, [
      _note('empty', 'ברכות|user', displayTitle: '   '),
      _note('same-title', 'שבת|db:fixture', displayTitle: 'שבת'),
    ]);

    expect(find.text('ברכות'), findsOneWidget);
    expect(find.text('שבת'), findsOneWidget);
    expect(find.textContaining('|user'), findsNothing);
    expect(find.textContaining('|db:'), findsNothing);
    expect(find.text('שבת — שבת'), findsNothing);
  });
}
