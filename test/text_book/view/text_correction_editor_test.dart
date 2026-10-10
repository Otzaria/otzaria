import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _line = '(א) <big>בְּ</big>רֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('מיפוי הבחירה לשורה הגולמית', () {
    test('מופע יחיד ומדויק ממופה ל-offsets ב-UTF-16', () {
      final template = buildCorrectionTemplate(_line, 'אֱלֹהִ֑ים');
      expect(template.hasSelection, isTrue);
      expect(template.originalSelection, 'אֱלֹהִ֑ים');
      expect(
        _line.substring(template.selectionStart!, template.selectionEnd!),
        'אֱלֹהִ֑ים',
      );
    });

    test('טקסט מוצג בלי ניקוד אינו נמצא בגולמי — השורה כולה, בלי ניחוש', () {
      final template = buildCorrectionTemplate(_line, 'אלהים');
      expect(template.hasSelection, isFalse);
      expect(template.target, _line);
    });

    test('מופע חוזר בשורה — השורה כולה', () {
      final template = buildCorrectionTemplate('את ואת את', 'את');
      expect(template.hasSelection, isFalse);
    });

    test('מופע יחיד בגולמי אך כפול בתצוגה בלי ניקוד — השורה כולה', () {
      // בתצוגה בלי ניקוד שני המופעים נראים "אלהים"; אולי סומן הראשון.
      final template = buildCorrectionTemplate('אֱלֹהִים ברא אלהים', 'אלהים');
      expect(template.hasSelection, isFalse);
    });

    test('מופע יחיד בגולמי שנמצא בתוך תגית HTML — השורה כולה', () {
      final template = buildCorrectionTemplate(
        '<span title="אלהים">אֱלֹהִים</span>',
        'אלהים',
      );
      expect(template.hasSelection, isFalse);
    });

    test('בחירה שחוצה תגית HTML — השורה כולה', () {
      expect(
        buildCorrectionTemplate(_line, 'בְּרֵאשִׁ֖ית').hasSelection,
        isFalse,
      );
    });

    test('בחירה עם רווחים בקצוות נמצאת לפי הגרסה המקוצצת', () {
      final template = buildCorrectionTemplate(_line, ' בָּרָ֣א ');
      expect(template.originalSelection, anyOf(' בָּרָ֣א ', 'בָּרָ֣א'));
    });

    test('שורה מה-DB שאינה זהה לשורה המוצגת נפסלת', () {
      const snapshot = ReportSourceSnapshot(
        bookId: 1,
        lineIndex: 1,
        heRef: null,
        originalLine: 'גולמי',
      );
      expect(
        ErrorReportHelper.isSourceConsistentWithContent(snapshot, [
          'א',
          'גולמי',
        ]),
        isTrue,
      );
      expect(
        ErrorReportHelper.isSourceConsistentWithContent(snapshot, [
          'א',
          'מעובד',
        ]),
        isFalse,
      );
      expect(
        ErrorReportHelper.isSourceConsistentWithContent(snapshot, ['א']),
        isFalse,
      );
    });
  });

  group('computeTextDiff', () {
    test('שינוי ניקוד במילה אחת מסומן כמילה שלמה', () {
      expect(computeTextDiff('בָּרָא אֱלֹהִים את', 'בָּרָא אֱלֹקִים את'), [
        const TextDiffSegment(TextDiffOp.equal, 'בָּרָא '),
        const TextDiffSegment(TextDiffOp.removed, 'אֱלֹהִים'),
        const TextDiffSegment(TextDiffOp.added, 'אֱלֹקִים'),
        const TextDiffSegment(TextDiffOp.equal, ' את'),
      ]);
    });

    test('מחיקה מלאה', () {
      expect(computeTextDiff('מילה', ''), [
        const TextDiffSegment(TextDiffOp.removed, 'מילה'),
      ]);
    });

    test('הוספת רווח נגרר מוצגת', () {
      expect(computeTextDiff('טקסט', 'טקסט '), [
        const TextDiffSegment(TextDiffOp.equal, 'טקסט'),
        const TextDiffSegment(TextDiffOp.added, ' '),
      ]);
    });

    test('שחזור שני הצדדים מהסגמנטים', () {
      const before = 'א ב ג ד ה';
      const after = 'א ג ד ו ה ז';
      final segments = computeTextDiff(before, after);
      String join(TextDiffOp skip) =>
          segments.where((s) => s.op != skip).map((s) => s.text).join();
      expect(join(TextDiffOp.added), before);
      expect(join(TextDiffOp.removed), after);
    });
  });

  group('evaluateCorrectionDraft', () {
    final original = TextCorrection.selection(
      originalLine: 'א ב ג',
      start: 2,
      end: 3,
    );

    test('[T3] מחיקה = ""', () {
      expect(
        evaluateCorrectionDraft(
          original: original,
          mode: ProposalMode.delete,
          editedText: 'x',
        ).correction.proposedText,
        '',
      );
    });

    test('הצעה זהה למקור חסומה', () {
      final draft = evaluateCorrectionDraft(
        original: original,
        mode: ProposalMode.replace,
        editedText: 'ב',
      );
      expect(draft.isValid, isFalse);
      expect(draft.error, ReportMessages.proposalIdentical);
    });

    test('הצעה מעל התקרה חסומה ואינה נחתכת', () {
      final long = 'א' * (TextCorrection.maxTextLength + 1);
      final draft = evaluateCorrectionDraft(
        original: original,
        mode: ProposalMode.replace,
        editedText: long,
      );
      expect(draft.isValid, isFalse);
      expect(draft.correction.proposedText, long);
    });

    test('surrogate בודד בהצעה או במקור חוסם, בלי לשנות את הטקסט', () {
      final draft = evaluateCorrectionDraft(
        original: original,
        mode: ProposalMode.replace,
        editedText: 'ב\uD83D',
      );
      expect(draft.error, ReportMessages.invalidCharacters);
      expect(draft.correction.proposedText, 'ב\uD83D');

      final brokenLine = evaluateCorrectionDraft(
        original: TextCorrection.wholeLine(originalLine: 'א\uDE00'),
        mode: ProposalMode.replace,
        editedText: 'אב',
      );
      expect(brokenLine.error, ReportMessages.invalidCharacters);
    });
  });

  group('RegularReportTab — מסלול הצעת תיקון', () {
    Future<List<(ErrorReportAction, ReportedErrorData)>> pumpTab(
      WidgetTester tester, {
      TextCorrection? template,
      String selectedText = 'אֱלֹהִ֑ים',
      Future<String?> Function(ReportedErrorData)? validate,
    }) async {
      final submissions = <(ErrorReportAction, ReportedErrorData)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegularReportTab(
              selectedText: selectedText,
              fontSize: 18,
              directReportTargetLabel: 'אוצריא',
              correctionTemplate:
                  template ?? buildCorrectionTemplate(_line, 'אֱלֹהִ֑ים'),
              validateBeforeSubmit: validate,
              onActionSelected: (action, data) =>
                  submissions.add((action, data)),
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return submissions;
    }

    Finder proposalField() => find.descendant(
      of: find.byKey(const ValueKey('correction-proposal-field')),
      matching: find.byType(TextField),
    );

    Future<ReportedErrorData> saveForLater(
      WidgetTester tester,
      List<(ErrorReportAction, ReportedErrorData)> submissions,
    ) async {
      await tester.tap(find.text('שמור לשליחה מאוחרת'));
      await tester.pumpAndSettle();
      expect(submissions.last.$1, ErrorReportAction.saveForLater);
      return submissions.last.$2;
    }

    testWidgets('[T2] שדה העריכה טעון מראש, והמקור מוצג בנפרד', (tester) async {
      await pumpTab(tester);

      expect(find.text('הצעת תיקון'), findsOneWidget);
      expect(find.text('דיווח חופשי'), findsOneWidget);
      expect(
        tester.widget<TextField>(proposalField()).controller!.text,
        'אֱלֹהִ֑ים',
      );
      final original = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('correction-original')),
          matching: find.byType(Text),
        ),
      );
      expect(original.textSpan!.toPlainText(), _line);
    });

    testWidgets('[T2] עריכה אינה משנה את המקור, ומציגה diff', (tester) async {
      final submissions = await pumpTab(tester);

      await tester.enterText(proposalField(), 'אֱלֹקִ֑ים');
      await tester.pumpAndSettle();

      final original = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('correction-original')),
          matching: find.byType(Text),
        ),
      );
      expect(original.textSpan!.toPlainText(), _line);
      expect(find.byKey(const ValueKey('correction-diff')), findsOneWidget);

      final data = await saveForLater(tester, submissions);
      expect(data.correction!.originalLine, _line);
      expect(data.correction!.originalSelection, 'אֱלֹהִ֑ים');
      expect(data.correction!.proposedText, 'אֱלֹקִ֑ים');
    });

    testWidgets('הצעה זהה למקור חוסמת שליחה עם הודעה', (tester) async {
      await pumpTab(tester);

      expect(find.text(ReportMessages.proposalIdentical), findsOneWidget);
      expect(find.text('שמור לשליחה מאוחרת'), findsNothing);
      expect(find.text('שלח ישירות לאוצריא'), findsNothing);
    });

    testWidgets('[T3] "מחיקת הקטע" שולח ""; אין אפשרות "ללא הצעה"', (
      tester,
    ) async {
      final submissions = await pumpTab(tester);

      await tester.tap(find.text('מחיקת הקטע'));
      await tester.pumpAndSettle();
      expect(proposalField(), findsNothing);
      expect(
        (await saveForLater(tester, submissions)).correction!.proposedText,
        '',
      );

      // הצעת תיקון בלי הצעה היא דיווח חופשי — אין לה מצב נפרד.
      expect(find.text('ללא הצעה'), findsNothing);
    });

    testWidgets('חריגה מהתקרה מציגה הודעה וחוסמת, בלי לחתוך', (tester) async {
      await pumpTab(tester);
      final long = 'א' * (TextCorrection.maxTextLength + 1);

      await tester.enterText(proposalField(), long);
      await tester.pumpAndSettle();

      expect(
        find.text(ReportMessages.proposalTooLong(TextCorrection.maxTextLength)),
        findsOneWidget,
      );
      expect(find.text('שמור לשליחה מאוחרת'), findsNothing);
      expect(tester.widget<TextField>(proposalField()).controller!.text, long);
    });

    testWidgets('בחירה שלא אותרה — עריכת השורה כולה עם הסבר', (tester) async {
      final submissions = await pumpTab(
        tester,
        template: buildCorrectionTemplate(_line, 'אלהים'),
        selectedText: 'אלהים',
      );

      expect(
        find.text(ReportMessages.correctionWholeLineNotice),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(proposalField()).controller!.text, _line);

      await tester.enterText(proposalField(), '$_line.');
      await tester.pumpAndSettle();
      final data = await saveForLater(tester, submissions);
      expect(data.correction!.originalSelection, isNull);
      expect(data.correction!.proposedText, '$_line.');
    });

    testWidgets('מעבר לדיווח חופשי שולח בלי הצעה', (tester) async {
      final submissions = await pumpTab(tester);

      await tester.tap(find.text('דיווח חופשי'));
      await tester.pumpAndSettle();
      expect(proposalField(), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('report-details-field')),
          matching: find.byType(TextField),
        ),
        'הסבר חופשי',
      );
      await tester.pumpAndSettle();

      final data = await saveForLater(tester, submissions);
      expect(data.correction, isNull);
      expect(data.errorDetails, 'הסבר חופשי');
    });

    testWidgets('דיווח גדול מדי: הדיאלוג לא נסגר וההצעה נשארת בשדה', (
      tester,
    ) async {
      final submissions = await pumpTab(
        tester,
        validate: (_) async => ReportMessages.bodyTooLarge(256),
      );
      await tester.enterText(proposalField(), 'אֱלֹקִ֑ים');
      await tester.pumpAndSettle();

      await tester.tap(find.text('שמור לשליחה מאוחרת'));
      await tester.pumpAndSettle();

      expect(submissions, isEmpty);
      expect(
        tester.widget<TextField>(proposalField()).controller!.text,
        'אֱלֹקִ֑ים',
      );
    });
  });

  group('TextCorrectionEditor — עריכת דיווח שמור (#1767)', () {
    Future<List<TextCorrectionDraft>> pumpRestored(
      WidgetTester tester,
      String? proposedText,
    ) async {
      final drafts = <TextCorrectionDraft>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TextCorrectionEditor(
                original: buildCorrectionTemplate(
                  _line,
                  'אֱלֹהִ֑ים',
                ).withProposedText(proposedText),
                restoreProposal: true,
                fontSize: 18,
                onChanged: drafts.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return drafts;
    }

    Finder proposalField() => find.descendant(
      of: find.byKey(const ValueKey('correction-proposal-field')),
      matching: find.byType(TextField),
    );

    testWidgets('נטען מההצעה השמורה ומציג את ה-diff', (tester) async {
      final drafts = await pumpRestored(tester, 'אֱלֹקִ֑ים');

      expect(
        tester.widget<TextField>(proposalField()).controller!.text,
        'אֱלֹקִ֑ים',
      );
      expect(find.byKey(const ValueKey('correction-diff')), findsOneWidget);
      expect(drafts.last.correction.proposedText, 'אֱלֹקִ֑ים');
    });

    testWidgets('מחיקה שמורה נפתחת במצב מחיקה', (tester) async {
      final drafts = await pumpRestored(tester, '');

      expect(proposalField(), findsNothing);
      expect(drafts.last.correction.proposedText, '');
    });

    testWidgets('"ללא הצעה" שמור מגרסה קודמת נפתח בעריכת טקסט', (tester) async {
      final drafts = await pumpRestored(tester, null);

      expect(proposalField(), findsOneWidget);
      expect(drafts.last.hasProposal, isTrue);
      expect(drafts.last.isValid, isFalse, reason: 'זהה למקור עד שמשנים');
    });
  });
}
