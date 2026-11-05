import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/book_note_report.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));

  test('line_note content is reported without the parent text', () {
    final notes = BookNotesBuilder()
      ..add(3, 0, 'א', 'תחילת הערה <b>המילה השגויה</b> וסיום');
    final target = bookNoteReportTarget(
      content: const ['א', 'ב', 'ג', 'טקסט האב שאינו ההערה'],
      bookNotes: notes.build(),
      lineIndexes: [3],
      selectedText: 'המילה השגויה',
    );
    expect(target!.lineIndex, 3);
    expect(target.contextText, contains('הערת שוליים 1 (שורה 4)'));
    expect(target.contextText, contains('תחילת הערה המילה השגויה וסיום'));
    expect(target.contextText, isNot(contains('טקסט האב')));
  });

  test('selection in another displayed line keeps the correct parent', () {
    final notes = BookNotesBuilder()
      ..add(1, 0, 'א', 'ראשונה')
      ..add(4, 0, 'ב', 'שנייה')
      ..add(4, 1, 'ג', 'שלישית');
    final target = bookNoteReportTarget(
      content: const [],
      bookNotes: notes.build(),
      lineIndexes: [1, 4],
      selectedText: 'שלישית',
    );
    expect(target!.lineIndex, 4);
    expect(target.contextText, contains('הערת שוליים 2 (שורה 5)'));
    expect(target.contextText, isNot(contains('ראשונה')));
  });

  test('ambiguous repeated words keep each note and its location', () {
    final notes = BookNotesBuilder()
      ..add(1, 0, null, 'מילה חוזרת בהערה הראשונה')
      ..add(4, 0, null, 'מילה חוזרת בהערה השנייה');
    final target = bookNoteReportTarget(
      content: const [],
      bookNotes: notes.build(),
      lineIndexes: [1, 4],
      selectedText: 'מילה חוזרת',
    );
    expect(target!.contextText, contains('(שורה 2)'));
    expect(target.contextText, contains('(שורה 5)'));
    expect(target.contextText, contains('הראשונה'));
    expect(target.contextText, contains('השנייה'));
  });

  test(
    'page-shape row identifies one note even when the selection repeats',
    () {
      final notes = BookNotesBuilder()
        ..add(4, 0, null, 'מילה ראשונה')
        ..add(4, 1, null, 'מילה שנייה');
      final target = bookNoteReportTarget(
        content: const [],
        bookNotes: notes.build(),
        lineIndexes: [4],
        selectedText: 'מילה',
        noteHtml: 'מילה שנייה',
      );
      expect(target!.contextText, contains('הערת שוליים 2'));
      expect(target.contextText, isNot(contains('ראשונה')));
    },
  );

  test(
    'inline HTML, entities, line breaks and hidden vowels remain readable',
    () {
      final target = bookNoteReportTarget(
        content: const [
          'אב <sup class="footnote-marker">2</sup>'
              '<i class="footnote">שָׁלוֹם &amp; <b>טקסט</b><br>נוסף</i>',
        ],
        bookNotes: BookNotes.empty,
        lineIndexes: [0],
        selectedText: 'שלום & טקסט',
      );
      expect(target!.contextText, contains('שָׁלוֹם & טקסט\nנוסף'));
      expect(target.contextText, isNot(contains('<')));
      expect(target.contextText, isNot(contains('אב ')));
    },
  );

  test('missing notes never silently use parent content', () {
    expect(
      bookNoteReportTarget(
        content: const ['parent'],
        bookNotes: BookNotes.empty,
        lineIndexes: [0],
        selectedText: 'selection',
      ),
      isNull,
    );
  });

  test('literal angle brackets from entities remain note text', () {
    final notes = BookNotesBuilder()
      ..add(0, 0, null, 'הטקסט &lt;b&gt; הוא חלק מההערה &amp; נשמר');
    final target = bookNoteReportTarget(
      content: const ['אב'],
      bookNotes: notes.build(),
      lineIndexes: [0],
      selectedText: 'חלק מההערה',
    );
    expect(target!.contextText, contains('הטקסט <b> הוא חלק מההערה & נשמר'));
  });

  test(
    'literal selected markup identifies its note without a second parse',
    () {
      final notes = BookNotesBuilder()
        ..add(0, 0, null, 'הטקסט &lt;b&gt; בהערה הראשונה')
        ..add(0, 1, null, 'הטקסט בהערה השנייה');
      final target = bookNoteReportTarget(
        content: const ['אב'],
        bookNotes: notes.build(),
        lineIndexes: [0],
        selectedText: '<b>',
      );
      expect(target!.contextText, contains('הראשונה'));
      expect(target.contextText, isNot(contains('השנייה')));
      expect(
        bookNoteReportText('<b>מקור</b><br>&lt;b&gt; &amp;amp;'),
        'מקור\n<b> &amp;',
      );
    },
  );

  const source = ReportSourceSnapshot(
    bookId: 7,
    lineIndex: 3,
    heRef: 'מיקום הבדיקה',
    originalLine: 'טקסט האב',
  );

  test('a note cannot create a correction against its parent', () {
    expect(
      ErrorReportHelper.correctionForReport(
        source: source,
        selectedText: 'טעות בהערה',
        reportNote: 'הערת שוליים: טעות בהערה',
      ),
      isNull,
    );
    expect(
      ErrorReportHelper.correctionForReport(
        source: source,
        selectedText: 'טקסט האב',
      )!.originalLine,
      source.originalLine,
    );
  });

  testWidgets(
    'note form displays the selected note and offers free reporting',
    (tester) async {
      final template = ErrorReportHelper.correctionForReport(
        source: source,
        selectedText: 'טעות בהערה',
        reportNote: 'הערת שוליים: טעות בהערה',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabbedReportDialog(
              selectedText: 'טעות בהערה',
              fontSize: 16,
              bookTitle: 'ספר בדיקה',
              currentLineNumber: 4,
              directReportTargetLabel: 'אוצריא',
              correctionTemplate: template,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TextCorrectionEditor), findsNothing);
      expect(find.text('טעות בהערה'), findsOneWidget);
      expect(find.text('טקסט האב'), findsNothing);
      expect(
        find.byKey(const ValueKey('report-details-field')),
        findsOneWidget,
      );
    },
  );
}
