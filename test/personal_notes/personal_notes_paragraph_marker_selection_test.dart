import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/personal_notes/utils/personal_note_source_selection.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

class _NotesDb extends Fake implements PersonalNotesDatabase {
  final notes = <PersonalNote>[];
  @override
  Future<void> insertNote(PersonalNote note) async => notes.add(note);
  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async =>
      notes.where((note) => note.bookId == bookId).toList();
  @override
  Future<void> batchUpdateNotes(List<PersonalNote> updated) async {
    for (final note in updated) {
      final index = notes.indexWhere((existing) => existing.id == note.id);
      notes[index] = note;
    }
  }
}

void main() {
  const html =
      'פתיחה ארוכה שנשברת לכמה שורות ברוחב צר לבדיקה'
      '&nbsp;<span class="mam-spi-pe">{פ}</span><br>'
      'המשך הפסקה אחרי הסמן והרווח, ועוד מילים לסיום.';
  const settings = RenderSettings(fontSize: 20, lineHeight: 1.6);

  for (final forceHtml in [false, true]) {
    testWidgets(
      'בחירה אמיתית חוצה סמן ו-BR שומרת עוגן (HtmlWidget=$forceHtml)',
      (tester) async {
        SmartTextWidget.debugForceHtmlWidget = forceHtml;
        addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
        String? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 180,
                  child: SelectionArea(
                    onSelectionChanged: (content) =>
                        selected = content?.plainText,
                    child: const SmartTextWidget(
                      text: html,
                      settings: settings,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        tester
            .state<SelectableRegionState>(find.byType(SelectableRegion))
            .selectAll(SelectionChangedCause.keyboard);
        await tester.pump();
        expect(selected, isNotNull);
        expect(selected, contains('{פ}'));
        expect(selected, contains('המשך הפסקה'));

        final fullSelection = selected!;
        const partialEnding = 'אחרי הסמן';
        final partialSelection = fullSelection.substring(
          fullSelection.indexOf('לבדיקה'),
          fullSelection.indexOf(partialEnding) + partialEnding.length,
        );
        PersonalNote? fullNote;
        for (final (selection, isPartial) in [
          (fullSelection, false),
          (partialSelection, true),
        ]) {
          final source = mapPersonalNoteSourceSelection(
            bookId: 'ספר בדיקה',
            lineIndex: 0,
            rawLine: html,
            settings: settings,
            selectedText: selection,
          );
          expect(source, isNotNull, reason: 'partial=$isPartial');
          final database = _NotesDb();
          final service = PersonalNotesService(database: database);
          final saved = (await service.addNote(
            bookId: 'ספר בדיקה',
            bookContent: html,
            lineNumber: 1,
            selectedText: selection,
            sourceSelectedText: source?.text,
            sourceSelectionOffset: source?.offset,
            content: 'תוכן הערה',
            contentPlain: 'תוכן הערה',
            contentFormat: PersonalNoteContentFormat.plain,
          )).single;
          expect(saved.isWordAnchored, isTrue, reason: 'partial=$isPartial');
          expect(saved.anchorText, normalizeAnchorText(source!.text));
          if (isPartial) {
            expect(saved.anchorStart, greaterThan(0));
            expect(saved.anchorEnd, lessThan(fullNote!.anchorEnd!));
          } else {
            fullNote = saved;
          }
          database.notes[0] = PersonalNote.fromJson(saved.toJson());
          final reopened = (await service.loadNotes(
            bookId: 'ספר בדיקה',
            bookContent: html,
          )).single;
          expect(reopened.status, PersonalNoteStatus.located);
          expect(reopened.lineNumber, 1);
          expect(reopened.anchorText, saved.anchorText);
          final range = locateAnchor(
            rawLine: html,
            anchorText: reopened.anchorText!,
          );
          expect(range, isNotNull);
          expect(range!.start, saved.anchorStart);
          expect(range.end, saved.anchorEnd);
        }
      },
    );
  }
}
