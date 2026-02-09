import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';

void main() {
  group('ErrorReportHelper.buildContextAroundSelection', () {
    test('should build context around selection with 4 words before and after',
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
    });

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
      final selectionStart =
          fullText.indexOf(selectedText, firstOccurrence + 1);
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
      );

      expect(body, contains(bookTitle));
      expect(body, contains(currentRef));
      expect(body, contains('zohar.txt'));
      expect(body, contains(selectedText));
      expect(body, contains(errorDetails));
      expect(body, contains('42'));
      expect(body, contains(contextText));
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

    test('should use line fallback when selection is ambiguous in same line',
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
      final expectedStart = content.first.lastIndexOf('טעות');

      expect(result.usedLineFallback, isTrue);
      expect(result.selectionStart, equals(expectedStart));
      expect(result.selectionEnd, equals(expectedStart + 'טעות'.length));
      expect(result.contextText, contains('אחת טעות שתיים טעות שלוש'));
    });

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
  });

  group('ErrorReportHelper.enrichBookDetailsFromStateBook', () {
    test('should fill missing file name and path from category path', () {
      final baseDetails = {
        'שם הקובץ': 'לא ניתן למצוא את הספר',
        'נתיב הקובץ': 'לא ניתן למצוא את הספר',
        'תיקיית המקור': 'לא ניתן למצוא את הספר',
      };

      final book = TextBook(
        title: 'ביאור הרד"ל על פרקי דרבי אליעזר',
        categoryPath: 'מחשבת ישראל, ספרים קדומים',
        fileType: 'txt',
      );

      final details = ErrorReportHelper.enrichBookDetailsFromStateBook(
        baseDetails: baseDetails,
        stateBook: book,
      );

      expect(details['שם הקובץ'], equals('ביאור הרד"ל על פרקי דרבי אליעזר.txt'));
      expect(
        details['נתיב הקובץ'],
        equals(
            'אוצריא/מחשבת ישראל/ספרים קדומים/ביאור הרד"ל על פרקי דרבי אליעזר.txt'),
      );
      expect(details['תיקיית המקור'], equals('לא ניתן למצוא את הספר'));
    });

    test('should prefer existing absolute file path from state book', () {
      final baseDetails = {
        'שם הקובץ': 'לא ניתן למצוא את הספר',
        'נתיב הקובץ': 'לא ניתן למצוא את הספר',
        'תיקיית המקור': 'מקור כלשהו',
      };

      final book = TextBook(
        title: 'ספר לדוגמה',
        filePath: '/library/אוצריא/בדיקות/ספר לדוגמה.txt',
        fileType: 'txt',
      );

      final details = ErrorReportHelper.enrichBookDetailsFromStateBook(
        baseDetails: baseDetails,
        stateBook: book,
      );

      expect(details['שם הקובץ'], equals('ספר לדוגמה.txt'));
      expect(
        details['נתיב הקובץ'],
        equals('/library/אוצריא/בדיקות/ספר לדוגמה.txt'),
      );
      expect(details['תיקיית המקור'], equals('מקור כלשהו'));
    });
  });
}
