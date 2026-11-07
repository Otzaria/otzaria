import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:otzaria/reports/book_report_selection.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';

void main() {
  test(
    'repeated words require an explicit range and preserve the selected occurrence',
    () {
      const source = 'אחד מילה שני מילה שלישי';
      expect(BookReportSelection.unique(source, 'מילה'), isNull);
      final start = source.lastIndexOf('מילה');
      final selection = BookReportSelection(start, start + 4);
      expect(selection.isValidFor(source), isTrue);
      expect(selection.selectedText(source), 'מילה');
      expect(selection.contextText(source), contains('$start–${start + 4}'));
      expect(selection.contextText(source), contains(source));
    },
  );

  test(
    'free reports use the full displayed line without an official source',
    () {
      final source = ErrorReportHelper.resolveReportSelectionSource(
        content: ['<b>מילה</b> פעם מילה שוב'],
        lineIndex: 0,
        selectedText: 'מילה',
      );
      expect(source, 'מילה פעם מילה שוב');
      expect(BookReportSelection.unique(source, 'מילה'), isNull);
    },
  );

  test(
    'repeated correction snippets include occurrence location and complete result',
    () {
      const sentence = 'אחד שני שלישי רביעי טעות שישי שביעי שמיני תשיעי';
      const original = '$sentence $sentence $sentence';
      final first = original.indexOf('טעות');
      final second = original.indexOf('טעות', first + 1);
      final details = [first, second]
          .map(
            (start) => ErrorReportHelper.emailErrorDetails(
              ReportedErrorData(
                selectedText: 'טעות',
                errorDetails: '',
                correction: TextCorrection.selection(
                  originalLine: original,
                  start: start,
                  end: start + 4,
                  proposedText: 'תיקון',
                ),
              ),
            ),
          )
          .toList();
      expect(details[0], isNot(details[1]));
      for (final email in details) {
        expect(email, contains('הקטע מופיע יותר מפעם אחת בשורה'));
        expect(email, contains('השורה המקורית המלאה'));
        expect(email, contains(original));
        expect(email, contains('השורה המתוקנת המלאה'));
      }
    },
  );

  test('UTF16 ranges reject split surrogate pairs', () {
    const text = 'א😀ב';
    expect(const BookReportSelection(1, 2).isValidFor(text), isFalse);
    expect(const BookReportSelection(2, 3).isValidFor(text), isFalse);
    expect(const BookReportSelection(1, 3).selectedText(text), '😀');
    expect(const BookReportSelection(-1, 3).isValidFor(text), isFalse);
    expect(const BookReportSelection(0, 8).isValidFor(text), isFalse);
  });

  test(
    'a long source retains exact range before the bounded context field',
    () {
      final source = 'מילה ' * 5000;
      const selection = BookReportSelection(22000, 22004);
      final context = selection.contextText(source);
      expect(
        context,
        startsWith('מיקום מסומן בציטוט המוצג: תווים 22000–22004'),
      );
      expect(context.length, lessThan(20000));
      final report = ErrorReportHelper.buildDirectReport(
        senderEmail: 'a@b.com',
        reportData: ReportedErrorData(
          selectedText: 'מילה',
          errorDetails: 'typo',
          selection: selection,
          selectionContext: context,
        ),
        bookTitle: 'book',
        currentRef: 'reference',
        bookDetails: const {},
        lineNumber: 7,
        contextText: '$source\n$context',
        libraryVersion: 'build1',
      );
      expect(report.contextText, startsWith(context));
      final email = ErrorReportHelper.buildEmailBody(
        'book',
        'reference',
        {},
        'מילה',
        'typo',
        7,
        context,
        'build1',
        null,
      );
      expect(email, contains('22000–22004'));
    },
  );

  test('footnote visible literal markup is never parsed as HTML again', () {
    expect(
      ErrorReportHelper.resolveReportTargetText(
        content: ['parent'],
        selectedText: '<b> &amp; literal',
        reportNote: 'note <b> &amp; literal',
      ),
      '<b> &amp; literal',
    );
    expect(
      ErrorReportHelper.resolveReportTargetText(
        content: ['parent'],
        selectedText: '',
        reportNote: 'note <b> &amp; literal',
      ),
      'note <b> &amp; literal',
    );
  });

  for (final original in [
    '<span title="a > מילה">&#1502;ילה</span>',
    '<!-- a > מילה -->&#1502;ילה',
    "<span title='a > מילה'>&#1502;ילה</span>",
  ]) {
    test(
      'markup occurrence never becomes a text correction selection: $original',
      () {
        final correction = buildCorrectionTemplate(original, 'מילה');
        expect(correction.hasSelection, isFalse);
        expect(correction.originalLine, original);
      },
    );
  }

  for (final (original, selected) in const [
    ('&amp;amp;', '&amp;'),
    ('&#1488; &#35;1488;', '#1488;'),
    ('&#x05D0; &#35;x05D0;', '#x05D0;'),
    ('<b>&amp;amp;</b>', '&amp;'),
  ]) {
    test('encoded text never selects a partial entity: $original', () {
      final correction = buildCorrectionTemplate(original, selected);
      expect(correction.hasSelection, isFalse);
      expect(correction.originalLine, original);
      expect(correction.target, original);
      final proposal = correction.withProposedText('תקין');
      final restored = TextCorrection.fromJson(proposal.toJson())!;
      expect(restored.originalLine, original);
      expect(restored.target, original);
      expect(restored.hasSelection, isFalse);
      expect(restored.proposedText, 'תקין');
    });
  }
}
