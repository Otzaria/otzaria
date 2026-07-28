import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// משבית פתיחת קישורים — canLaunch מחזיר false כדי לדמות כשל בפתיחת הדפדפן.
class _FailingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<bool> canLaunch(String url) async => false;

  @override
  LinkDelegate? get linkDelegate => null;
}

/// מדמה פתיחת קישור מוצלחת.
class _SucceedingUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async => true;

  @override
  LinkDelegate? get linkDelegate => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
    await Settings.setValue<String>(
      SettingsRepository.keyFontFamily,
      'candara',
    );
  });

  group('ErrorReportHelper.resolveReportTargetText', () {
    test('uses override content when provided', () {
      final result = ErrorReportHelper.resolveReportContent(
        state: _loadedState(),
        reportContent: const ['פסקת מפרש ראשונה', 'פסקת מפרש שניה'],
      );

      expect(result, equals(const ['פסקת מפרש ראשונה', 'פסקת מפרש שניה']));
    });

    test('uses override book when provided', () {
      final result = ErrorReportHelper.resolveReportBook(
        state: _loadedState(),
        reportBook: TextBook(title: 'מפרש בדיקה'),
      );

      expect(result!.title, equals('מפרש בדיקה'));
    });

    // חלונית ה-PDF מדווחת בלי TextBookBloc: ה-override הוא מקור האמת היחיד.
    test('ללא state — התוכן וספר היעד נלקחים מה-override', () {
      expect(
        ErrorReportHelper.resolveReportContent(
          state: null,
          reportContent: const ['פסקת מפרש'],
        ),
        equals(const ['פסקת מפרש']),
      );
      expect(
        ErrorReportHelper.resolveReportBook(
          state: null,
          reportBook: TextBook(title: 'רש"י על שבת'),
        )!.title,
        equals('רש"י על שבת'),
      );
    });

    test('ללא state וללא override — תוכן ריק וספר null, בלי לזרוק', () {
      expect(
        ErrorReportHelper.resolveReportContent(state: null),
        isEmpty,
      );
      expect(ErrorReportHelper.resolveReportBook(state: null), isNull);
    });

    test('עם state וללא override — נלקחים מה-state', () {
      final state = _loadedState();
      expect(
        ErrorReportHelper.resolveReportContent(state: state),
        equals(state.content),
      );
      expect(
        ErrorReportHelper.resolveReportBook(state: state)!.title,
        equals(state.book.title),
      );
    });

    test('returns selected text when selection exists', () {
      final result = ErrorReportHelper.resolveReportTargetText(
        content: const ['פסקה ראשונה', 'פסקה שניה'],
        selectedText: 'טקסט מסומן',
        preferredLineNumber: 1,
      );

      expect(result, equals('טקסט מסומן'));
    });

    test('falls back to current paragraph when selection is empty', () {
      final result = ErrorReportHelper.resolveReportTargetText(
        content: const ['פסקה ראשונה', '  פסקה שניה  '],
        selectedText: '',
        preferredLineNumber: 1,
      );

      expect(result, equals('פסקה שניה'));
    });

    test('strips html tags when fallback paragraph contains html', () {
      final result = ErrorReportHelper.resolveReportTargetText(
        content: const ['<span>פסקה <b>ראשונה</b></span>'],
        selectedText: '',
        preferredLineNumber: 0,
      );

      expect(result, equals('פסקה ראשונה'));
    });

    test('keeps empty text when current paragraph is unavailable', () {
      final result = ErrorReportHelper.resolveReportTargetText(
        content: const ['פסקה ראשונה'],
        selectedText: '',
        preferredLineNumber: 5,
      );

      expect(result, isEmpty);
    });

    test('decodes html entities including hexadecimal entities', () {
      final result = ErrorReportHelper.sanitizeReportText(
        'שלום &#x27;עולם&#x27; &amp; בדיקה',
      );

      expect(result, equals("שלום 'עולם' & בדיקה"));
    });

    test('resolves direct report target as sefaria for sefaria source', () {
      final result = ErrorReportHelper.resolveDirectReportTargetLabel(
        'sefariaToOtzaria',
      );

      expect(result, equals('ספריא'));
    });

    test('resolves direct report target as otzaria for non-sefaria source', () {
      final result = ErrorReportHelper.resolveDirectReportTargetLabel('local');

      expect(result, equals('אוצריא'));
    });

    test('identifies dicta source folder', () {
      expect(ErrorReportHelper.isDictaSourceFolder('DictaToOtzaria'), isTrue);
      expect(ErrorReportHelper.isDictaSourceFolder('dicta'), isTrue);
      expect(ErrorReportHelper.isDictaSourceFolder('sefaria'), isFalse);
      expect(ErrorReportHelper.isDictaSourceFolder(null), isFalse);
    });

    test('builds dicta edit deep link with title parameter', () {
      final url = ErrorReportHelper.dictaEditUrlFor('ספר הזוהר');

      final uri = Uri.parse(url);
      expect(uri.path, equals('/library/dicta-edit/goto'));
      expect(uri.queryParameters['title'], equals('ספר הזוהר'));
      expect(uri.queryParameters.containsKey('text'), isFalse);
    });

    test('includes selected text in the deep link', () {
      final url = ErrorReportHelper.dictaEditUrlFor(
        'ספר הזוהר',
        selectedText: 'קטע עם טעות',
      );

      final uri = Uri.parse(url);
      expect(uri.queryParameters['title'], equals('ספר הזוהר'));
      expect(uri.queryParameters['text'], equals('קטע עם טעות'));
    });

    test('truncates long selected text at a word boundary', () {
      final longText = List.generate(100, (i) => 'מילה$i').join(' ');
      final url = ErrorReportHelper.dictaEditUrlFor(
        'ספר הזוהר',
        selectedText: longText,
      );

      final text = Uri.parse(url).queryParameters['text']!;
      expect(text.length, lessThanOrEqualTo(300));
      // נחתך בגבול מילה — הקטע החלקי הוא תחילת המקור, בלי מילה קטועה בסוף
      expect(longText.startsWith('$text '), isTrue);
    });

    test('builds plain dicta edit url for empty title', () {
      expect(
        ErrorReportHelper.dictaEditUrlFor('   '),
        equals(ErrorReportHelper.dictaEditUrl),
      );
    });
  });

  group('ErrorReportHelper.buildContextAroundSelection', () {
    test(
      'should build context around selection with 4 words before and after',
      () {
        const fullText = 'אחת שתיים שלוש ארבע חמש שש שבע שמונה תשע עשר';
        const selectedText = 'חמש שש שבע';
        final selectionStart = fullText.indexOf(selectedText);
        final selectionEnd = selectionStart + selectedText.length;

        final context = ErrorReportHelper.buildContextAroundSelection(
          fullText,
          selectionStart,
          selectionEnd,
          wordsBefore: 4,
          wordsAfter: 4,
        );

        // צריך לכלול 4 מילים לפני (אחת שתיים שלוש ארבע) + הבחירה (חמש שש שבע) + 4 מילים אחרי (שמונה תשע עשר)
        // אבל יש רק 3 מילים אחרי, אז נקבל את כולן
        expect(context, equals('אחת שתיים שלוש ארבע חמש שש שבע שמונה תשע עשר'));
      },
    );

    test('should handle selection at the beginning of text', () {
      const fullText = 'אחת שתיים שלוש ארבע חמש שש שבע שמונה';
      const selectedText = 'אחת שתיים';
      final selectionStart = fullText.indexOf(selectedText);
      final selectionEnd = selectionStart + selectedText.length;

      final context = ErrorReportHelper.buildContextAroundSelection(
        fullText,
        selectionStart,
        selectionEnd,
        wordsBefore: 4,
        wordsAfter: 4,
      );

      // אין מילים לפני, אז נקבל רק את הבחירה + 4 מילים אחרי
      expect(context, equals('אחת שתיים שלוש ארבע חמש שש'));
    });

    test('should handle selection at the end of text', () {
      const fullText = 'אחת שתיים שלוש ארבע חמש שש שבע שמונה';
      const selectedText = 'שבע שמונה';
      final selectionStart = fullText.indexOf(selectedText);
      final selectionEnd = selectionStart + selectedText.length;

      final context = ErrorReportHelper.buildContextAroundSelection(
        fullText,
        selectionStart,
        selectionEnd,
        wordsBefore: 4,
        wordsAfter: 4,
      );

      // אין מילים אחרי, אז נקבל 4 מילים לפני + הבחירה
      expect(context, equals('שלוש ארבע חמש שש שבע שמונה'));
    });

    test('should handle duplicate words - first occurrence', () {
      const fullText = 'אחת שתיים שלוש ארבע חמש שש שלוש שמונה תשע עשר';
      const selectedText = 'שלוש';
      // מופע ראשון
      final selectionStart = fullText.indexOf(selectedText);
      final selectionEnd = selectionStart + selectedText.length;

      final context = ErrorReportHelper.buildContextAroundSelection(
        fullText,
        selectionStart,
        selectionEnd,
        wordsBefore: 2,
        wordsAfter: 2,
      );

      // צריך לכלול 2 מילים לפני + הבחירה + 2 מילים אחרי
      expect(context, equals('אחת שתיים שלוש ארבע חמש'));
    });

    test('should handle duplicate words - second occurrence', () {
      const fullText = 'אחת שתיים שלוש ארבע חמש שש שלוש שמונה תשע עשר';
      const selectedText = 'שלוש';
      // מופע שני - נחפש החל מאחרי המופע הראשון
      final firstOccurrence = fullText.indexOf(selectedText);
      final selectionStart = fullText.indexOf(
        selectedText,
        firstOccurrence + 1,
      );
      final selectionEnd = selectionStart + selectedText.length;

      final context = ErrorReportHelper.buildContextAroundSelection(
        fullText,
        selectionStart,
        selectionEnd,
        wordsBefore: 2,
        wordsAfter: 2,
      );

      // צריך לכלול 2 מילים לפני + הבחירה + 2 מילים אחרי
      expect(context, equals('חמש שש שלוש שמונה תשע'));
    });

    test('should handle invalid selection range', () {
      const fullText = 'אחת שתיים שלוש ארבע חמש';
      const selectionStart = -1;
      const selectionEnd = -1;

      final context = ErrorReportHelper.buildContextAroundSelection(
        fullText,
        selectionStart,
        selectionEnd,
        wordsBefore: 4,
        wordsAfter: 4,
      );

      // במקרה של טווח לא תקין, צריך להחזיר את כל הטקסט
      expect(context, equals(fullText));
    });

    test('should handle empty text', () {
      const fullText = '';
      const selectionStart = 0;
      const selectionEnd = 0;

      final context = ErrorReportHelper.buildContextAroundSelection(
        fullText,
        selectionStart,
        selectionEnd,
        wordsBefore: 4,
        wordsAfter: 4,
      );

      expect(context, equals(''));
    });

    test('should handle text with multiple spaces', () {
      const fullText = 'אחת  שתיים   שלוש    ארבע חמש';
      const selectedText = 'שלוש';
      final selectionStart = fullText.indexOf(selectedText);
      final selectionEnd = selectionStart + selectedText.length;

      final context = ErrorReportHelper.buildContextAroundSelection(
        fullText,
        selectionStart,
        selectionEnd,
        wordsBefore: 2,
        wordsAfter: 2,
      );

      // צריך לטפל נכון ברווחים מרובים
      expect(context, contains('שלוש'));
      expect(context, contains('שתיים'));
      expect(context, contains('ארבע'));
    });

    test('should handle text with newlines', () {
      const fullText = 'אחת\nשתיים\nשלוש\nארבע\nחמש\nשש\nשבע';
      const selectedText = 'ארבע';
      final selectionStart = fullText.indexOf(selectedText);
      final selectionEnd = selectionStart + selectedText.length;

      final context = ErrorReportHelper.buildContextAroundSelection(
        fullText,
        selectionStart,
        selectionEnd,
        wordsBefore: 2,
        wordsAfter: 2,
      );

      // צריך לכלול 2 מילים לפני + הבחירה + 2 מילים אחרי
      expect(context, contains('ארבע'));
      expect(context, contains('שלוש'));
      expect(context, contains('חמש'));
    });
  });

  group('ErrorReportHelper email encoding', () {
    test('should encode query parameters correctly', () {
      final params = {
        'subject': 'דיווח על טעות: ספר הזוהר',
        'body': 'שלום\nזו טעות',
      };

      final encoded = ErrorReportHelper.encodeQueryParameters(params);

      expect(encoded, isNotNull);
      expect(encoded, contains('subject='));
      expect(encoded, contains('body='));
      // צריך להיות מקודד (לא להכיל תווים עבריים ישירות)
      expect(encoded, isNot(contains('דיווח')));
    });

    test('should handle empty parameters', () {
      final params = <String, String>{};

      final encoded = ErrorReportHelper.encodeQueryParameters(params);

      expect(encoded, equals(''));
    });

    test('should handle special characters', () {
      final params = {
        'test': 'value with spaces & special = chars',
      };

      final encoded = ErrorReportHelper.encodeQueryParameters(params);

      expect(encoded, isNotNull);
      expect(encoded, contains('test='));
      // צריך להיות מקודד
      expect(encoded, isNot(contains(' ')));
      expect(encoded, isNot(contains('&')));
    });
  });

  group('ErrorReportHelper email body building', () {
    test('should build complete email body', () {
      const bookTitle = 'ספר הזוהר';
      const currentRef = 'פרק א, דף ב';
      final bookDetails = {
        'שם הקובץ': 'zohar.txt',
        'נתיב הקובץ': '/books/zohar.txt',
        'תיקיית המקור': 'sefaria',
      };
      const selectedText = 'טקסט עם טעות';
      const errorDetails = 'צריך להיות "טקסט ללא טעות"';
      const lineNumber = 42;
      const contextText = 'הקשר לפני טקסט עם טעות הקשר אחרי';

      final body = ErrorReportHelper.buildEmailBody(
        bookTitle,
        currentRef,
        bookDetails,
        selectedText,
        errorDetails,
        lineNumber,
        contextText,
        '2026.03',
        null,
      );

      expect(body, contains(bookTitle));
      expect(body, contains(currentRef));
      expect(body, contains('zohar.txt'));
      expect(body, contains(selectedText));
      expect(body, contains(errorDetails));
      expect(body, contains('42'));
      expect(body, contains(contextText));
      expect(body, contains('גרסת ספרייה: 2026.03'));
    });

    test('should handle empty error details', () {
      const bookTitle = 'ספר הזוהר';
      const currentRef = 'פרק א';
      final bookDetails = {
        'שם הקובץ': 'zohar.txt',
        'נתיב הקובץ': '/books/zohar.txt',
        'תיקיית המקור': 'sefaria',
      };
      const selectedText = 'טקסט';
      const errorDetails = '';
      const lineNumber = 1;
      const contextText = 'הקשר';

      final body = ErrorReportHelper.buildEmailBody(
        bookTitle,
        currentRef,
        bookDetails,
        selectedText,
        errorDetails,
        lineNumber,
        contextText,
        'unknown',
        null,
      );

      expect(body, contains(bookTitle));
      expect(body, contains(selectedText));
      expect(body, contains('1'));
    });
  });

  group('ErrorReportHelper.resolveSelectionContext', () {
    test('should resolve to preferred line occurrence when unique in line', () {
      final content = [
        'שורה ראשונה עם המילה טעות כאן',
        'שורה שנייה ללא הבעיה',
        'שורה שלישית עם המילה טעות שוב',
      ];

      final result = ErrorReportHelper.resolveSelectionContext(
        content: content,
        selectedText: 'טעות',
        preferredLineNumber: 2,
      );

      final linesBefore = '\n'
          .allMatches(content.join('\n').substring(0, result.selectionStart))
          .length;

      expect(linesBefore, equals(2));
      expect(result.usedLineFallback, isFalse);
      expect(result.contextText, contains('שלישית עם המילה טעות שוב'));
    });

    test(
      'should use line fallback when selection is ambiguous in same line',
      () {
        final content = [
          'אחת טעות שתיים טעות שלוש',
          'שורה נוספת לבדיקה',
        ];

        final result = ErrorReportHelper.resolveSelectionContext(
          content: content,
          selectedText: 'טעות',
          preferredLineNumber: 0,
        );

        // כשמילה מופיעה כמה פעמים באותה שורה, אי אפשר לדעת איזה מופע
        // המשתמש בחר (SelectionArea לא חושף offset). לכן:
        // 1. ההקשר חייב לכלול את כל השורה (שני המופעים)
        // 2. usedLineFallback == true מסמן שהייתה עמימות
        // 3. selectionStart/End מצביעים על כל השורה (לא על מופע בודד)
        expect(result.usedLineFallback, isTrue);
        expect(result.selectionStart, equals(0)); // תחילת השורה
        expect(result.selectionEnd, equals(content.first.length)); // סוף השורה
        expect(result.contextText, contains('אחת טעות שתיים טעות שלוש'));
      },
    );

    test(
      'should include full line context with both occurrences when ambiguous',
      () {
        final content = [
          'מילה ראשונה',
          'הפתיחה עם שלום ואז עוד שלום בסוף',
          'מילה אחרונה',
        ];

        final result = ErrorReportHelper.resolveSelectionContext(
          content: content,
          selectedText: 'שלום',
          preferredLineNumber: 1,
        );

        // ההקשר חייב לכלול את שני המופעים של "שלום" כך שמי שקורא
        // את הדיווח יוכל להבין איזה מופע מדובר
        expect(result.usedLineFallback, isTrue);
        expect(result.contextText, contains('שלום ואז עוד שלום'));
      },
    );

    test('should fallback to global search when preferred line is invalid', () {
      final content = [
        'שורה עם טקסט',
        'שורה עם טקסט',
      ];

      final result = ErrorReportHelper.resolveSelectionContext(
        content: content,
        selectedText: 'טקסט',
        preferredLineNumber: 99,
      );

      expect(result.selectionStart, greaterThan(-1));
      expect(result.usedLineFallback, isFalse);
    });

    test('should find unique word in correct paragraph across duplicates', () {
      // מילה מופיעה בפסקה 0 ובפסקה 2, המשתמש בחר בפסקה 2
      final content = [
        'שורה עם טעות כאן',
        'שורה נקייה בלי בעיות',
        'שורה אחרת עם טעות שונה',
      ];

      final result = ErrorReportHelper.resolveSelectionContext(
        content: content,
        selectedText: 'טעות',
        preferredLineNumber: 2,
      );

      // חייב למצוא את המופע בשורה 2, לא בשורה 0
      final allText = content.join('\n');
      final textAtResult = allText.substring(
        result.selectionStart,
        result.selectionEnd,
      );
      expect(textAtResult, equals('טעות'));

      final linesBefore = '\n'
          .allMatches(allText.substring(0, result.selectionStart))
          .length;
      expect(linesBefore, equals(2)); // שורה 2 (0-based)
      expect(result.usedLineFallback, isFalse);
    });

    test(
      'should handle three occurrences in same line by returning full line context',
      () {
        final content = [
          'אמר שלום ואז שלום ושוב שלום',
        ];

        final result = ErrorReportHelper.resolveSelectionContext(
          content: content,
          selectedText: 'שלום',
          preferredLineNumber: 0,
        );

        expect(result.usedLineFallback, isTrue);
        expect(result.contextText, contains('שלום ואז שלום ושוב שלום'));
      },
    );

    test('should handle empty selected text gracefully', () {
      final content = [
        'שורה ראשונה',
        'שורה שנייה',
      ];

      final result = ErrorReportHelper.resolveSelectionContext(
        content: content,
        selectedText: '',
        preferredLineNumber: 0,
      );

      // טקסט ריק — fallback לכל הטקסט
      expect(result.selectionStart, equals(0));
    });

    test('should handle text not found in expected line', () {
      // המילה לא נמצאת בשורה 0 אבל כן נמצאת בשורה 1
      final content = [
        'שורה ללא התאמה',
        'שורה עם מילה מיוחדת',
      ];

      final result = ErrorReportHelper.resolveSelectionContext(
        content: content,
        selectedText: 'מיוחדת',
        preferredLineNumber: 0,
      );

      // אמור לחפש מהשורה ואילך (indexOf עם startIndex)
      // ולמצוא את המילה בשורה 1
      expect(result.selectionStart, greaterThan(-1));
      expect(result.contextText, contains('מיוחדת'));
      expect(result.usedLineFallback, isFalse);
    });
  });

  group('RegularReportTab', () {
    testWidgets('allows submitting direct report without selected text', (
      tester,
    ) async {
      ErrorReportAction? submittedAction;
      ReportedErrorData? submittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegularReportTab(
              selectedText: '',
              fontSize: 18,
              directReportTargetLabel: 'אוצריא',
              onActionSelected: (action, data) {
                submittedAction = action;
                submittedData = data;
              },
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('שלח ישירות לאוצריא'), findsNothing);

      await tester.enterText(find.byType(TextField), 'זו טעות בפסקה הנוכחית');
      await tester.pumpAndSettle();

      expect(find.text('שלח ישירות לאוצריא'), findsOneWidget);

      await tester.tap(find.text('שלח ישירות לאוצריא'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('שלח דיווח'));
      await tester.pumpAndSettle();

      expect(submittedAction, equals(ErrorReportAction.sendDirect));
      expect(submittedData, isNotNull);
      expect(submittedData!.selectedText, isEmpty);
      expect(submittedData!.errorDetails, equals('זו טעות בפסקה הנוכחית'));
    });

    testWidgets('shows sefaria label for sefaria sourced books', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegularReportTab(
              selectedText: '',
              fontSize: 18,
              directReportTargetLabel: 'ספריא',
              onActionSelected: (_, _) {},
              onCancel: () {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'זו טעות שמקורה בספריא');
      await tester.pumpAndSettle();

      expect(find.text('שלח ישירות לספריא'), findsOneWidget);

      await tester.tap(find.text('שלח ישירות לספריא'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'לחיצה על שלח דיווח תשלח את השגיאה ישירות לספריא, יש לשים לב לתקינות הדיווח לפני השליחה',
        ),
        findsOneWidget,
      );
    });

    testWidgets('details field receives focus automatically on open', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegularReportTab(
              selectedText: 'טקסט לבדיקה',
              fontSize: 18,
              directReportTargetLabel: 'אוצריא',
              onActionSelected: (_, _) {},
              onCancel: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.focusNode?.hasFocus ?? textField.autofocus, isTrue);
    });
  });

  group('RegularReportTab — באנר תיקון עצמי לספרי דיקטה', () {
    const bannerText = 'לחץ כאן על מנת לתקן את הספר בעצמך';

    Future<bool> pumpTab(
      WidgetTester tester, {
      required bool isDictaSource,
    }) async {
      bool cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegularReportTab(
              selectedText: 'קטע עם טעות',
              fontSize: 18,
              directReportTargetLabel: 'אוצריא',
              bookTitle: 'ספר בדיקה',
              isDictaSource: isDictaSource,
              onActionSelected: (_, _) {},
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return cancelled;
    }

    testWidgets('shows the banner for dicta books in online mode', (
      tester,
    ) async {
      await pumpTab(tester, isDictaSource: true);

      expect(find.text(bannerText), findsOneWidget);
    });

    testWidgets('hides the banner for non-dicta books', (tester) async {
      await pumpTab(tester, isDictaSource: false);

      expect(find.text(bannerText), findsNothing);
    });

    testWidgets('hides the banner in offline mode', (tester) async {
      await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
      addTearDown(
        () => Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false),
      );

      await pumpTab(tester, isDictaSource: true);

      expect(find.text(bannerText), findsNothing);
    });

    testWidgets('closes the report form when the edit page opens', (
      tester,
    ) async {
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = _SucceedingUrlLauncher();
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      bool cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegularReportTab(
              selectedText: 'קטע עם טעות',
              fontSize: 18,
              directReportTargetLabel: 'אוצריא',
              bookTitle: 'ספר בדיקה',
              isDictaSource: true,
              onActionSelected: (_, _) {},
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(bannerText));
      await tester.pumpAndSettle();

      // עמוד העריכה נפתח — הטופס נסגר דרך onCancel
      expect(cancelled, isTrue);
    });

    testWidgets('keeps the form open when the edit page fails to open', (
      tester,
    ) async {
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = _FailingUrlLauncher();
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);

      await pumpTab(tester, isDictaSource: true);
      await tester.tap(find.text(bannerText));
      await tester.pumpAndSettle();

      // הפתיחה נכשלה — הבאנר עדיין מוצג והטופס נשאר פתוח
      expect(find.text(bannerText), findsOneWidget);
    });
  });

  group('TabbedReportDialog — מסך צר', () {
    // רגרסיה: ב-405×800 (פלאפון בלנדסקייפ) הצירוף minWidth=400 + maxWidth=screen*0.6
    // יצר BoxConstraints לא-נורמליזיים (400<=w<=243) וזרק חריגה.
    testWidgets('לא קורס במסך צר (405 רוחב)', (tester) async {
      tester.view.physicalSize = const Size(405, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: ctx,
                    builder: (_) => TabbedReportDialog(
                      selectedText: 'טקסט',
                      fontSize: 18,
                      bookTitle: 'ספר בדיקה',
                      currentLineNumber: 0,
                      directReportTargetLabel: 'אוצריא',
                    ),
                  );
                },
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'במסך צר (405px) הקונסטריינטים חייבים להישאר נורמליזיים: '
            'minWidth ≤ maxWidth, ו-maxWidth מותאם ל-95% מהרוחב במסך צר.',
      );
      expect(find.text('דיווח על טעות בספר'), findsOneWidget);
    });

    testWidgets('במסך רחב נשארת ההתנהגות המקורית (~60% מהרוחב)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: ctx,
                    builder: (_) => TabbedReportDialog(
                      selectedText: 'טקסט',
                      fontSize: 18,
                      bookTitle: 'ספר בדיקה',
                      currentLineNumber: 0,
                      directReportTargetLabel: 'אוצריא',
                    ),
                  );
                },
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('דיווח על טעות בספר'), findsOneWidget);
    });
  });
}

TextBookLoaded _loadedState() {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['פסקה ראשונה', 'פסקה שניה'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}
