import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
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
      expect(ErrorReportHelper.resolveReportContent(state: null), isEmpty);
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

    test('email recipients mirror the website routing', () {
      expect(
        ErrorReportHelper.emailRecipientsFor('SefariaToOtzaria'),
        'corrections@sefaria.org,jewishoffice@gmail.com',
      );
      expect(
        ErrorReportHelper.emailRecipientsFor('wikiSource'),
        'otzaria.200@gmail.com,novartza@gmail.com',
      );
      // שם המקור ב-seforim.db הוא wikiJewishBooksToOtzaria. ההתאמה היא
      // contains בלי הסרת מפרידים, ולכן מפתח עם קווים תחתונים לא היה מתאים
      // אף פעם — והדיווח לא היה מגיע לבעלי הטקסטים.
      expect(
        ErrorReportHelper.emailRecipientsFor('wikiJewishBooksToOtzaria'),
        'otzaria.200@gmail.com,WikiJewishBooks@gmail.com',
      );
      expect(
        ErrorReportHelper.emailRecipientsFor('DictaToOtzaria'),
        'otzaria.200@gmail.com,jewishoffice@gmail.com',
      );
      expect(
        ErrorReportHelper.emailRecipientsFor('yam-HaHachmaToOtzaria'),
        'otzaria.200@gmail.com,y025837086@gmail.com',
      );
      expect(
        ErrorReportHelper.emailRecipientsFor('local'),
        'otzaria.200@gmail.com',
      );
      expect(
        ErrorReportHelper.emailRecipientsFor(null),
        'otzaria.200@gmail.com',
      );
    });

    test('Sefaria link uses the exact heRef of the line', () {
      expect(
        Uri.decodeComponent(
          ErrorReportHelper.sefariaUrlFor('בית יוסף, אורח חיים,  שיח, טו, א')!,
        ),
        'https://www.sefaria.org/בית יוסף, אורח חיים, שיח, טו, א',
      );
      expect(ErrorReportHelper.sefariaUrlFor(null), isNull);
      expect(ErrorReportHelper.sefariaUrlFor('  '), isNull);
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

    group('ספר גדול (#3727)', () {
      late String bigText;

      setUpAll(() {
        final buffer = StringBuffer();
        for (var i = 0; i < 1500000; i++) {
          if (i > 0) buffer.write(i % 50 == 0 ? '\n' : ' ');
          buffer.write('מילה$i');
        }
        bigText = buffer.toString();
      });

      void expectSameAsFullScan(int start, int end) {
        expect(
          ErrorReportHelper.buildContextAroundSelection(bigText, start, end),
          equals(_fullScanContext(bigText, start, end)),
        );
      }

      test('בחירה באמצע הספר זהה לסריקה המלאה', () {
        final start = bigText.indexOf('מילה750000 ');
        expectSameAsFullScan(start, start + 'מילה750000 מילה750001'.length);
        expect(
          ErrorReportHelper.buildContextAroundSelection(
            bigText,
            start,
            start + 'מילה750000'.length,
          ),
          equals(
            'מילה749996 מילה749997 מילה749998 מילה749999\nמילה750000 '
            'מילה750001 מילה750002 מילה750003 מילה750004',
          ),
        );
      });

      test('בחירה בתחילת הספר ובסופו זהה לסריקה המלאה', () {
        expectSameAsFullScan(0, 'מילה0'.length);
        expectSameAsFullScan(2, 9);
        final last = bigText.lastIndexOf('מילה1499999');
        expectSameAsFullScan(last, bigText.length);
        expectSameAsFullScan(last - 3, last + 4);
        expectSameAsFullScan(bigText.length - 1, bigText.length);
      });

      test('לא סורק את כל הספר', () {
        final start = bigText.indexOf('מילה750000 ');
        final end = start + 'מילה750000'.length;
        final fullScan = Stopwatch()..start();
        _fullScanContext(bigText, start, end);
        fullScan.stop();
        final windowed = Stopwatch()..start();
        for (var i = 0; i < 10; i++) {
          ErrorReportHelper.buildContextAroundSelection(bigText, start, end);
        }
        windowed.stop();
        // עשר קריאות צריכות לעלות פחות מסריקה מלאה אחת.
        expect(
          windowed.elapsedMicroseconds,
          lessThan(fullScan.elapsedMicroseconds),
        );
      });
    });

    test('בחירת רווח אחרי מילה, כשהמילה הקודמת מחוץ לחלון', () {
      final text = 'x${' ' * 2000}ab cd ef gh ij';
      final start = text.indexOf('ab') + 2;
      for (var wordsAfter = 0; wordsAfter <= 4; wordsAfter++) {
        expect(
          ErrorReportHelper.buildContextAroundSelection(
            text,
            start,
            start + 1,
            wordsBefore: 0,
            wordsAfter: wordsAfter,
          ),
          equals(
            _fullScanContext(
              text,
              start,
              start + 1,
              wordsBefore: 0,
              wordsAfter: wordsAfter,
            ),
          ),
          reason: 'wordsAfter=$wordsAfter',
        );
      }
    });

    test('זהה לסריקה המלאה גם כשמילים ארוכות חוצות את קצה החלון', () {
      var seed = 3727;
      int next(int max) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed % max;
      }

      final separators = [' ', '  ', '\n', '\t', ' ', ' \n ', ' ' * 2500];
      for (var round = 0; round < 300; round++) {
        final buffer = StringBuffer();
        if (next(3) == 0) buffer.write(separators[next(separators.length)]);
        final wordCount = 1 + next(30);
        for (var w = 0; w < wordCount; w++) {
          if (w > 0) buffer.write(separators[next(separators.length)]);
          // מילים של עד אלפי תווים, כדי שקצה החלון ייפול באמצע מילה.
          buffer.write('א' * (1 + next(next(2) == 0 ? 8 : 3000)));
        }
        if (next(3) == 0) buffer.write(separators[next(separators.length)]);
        final text = buffer.toString();
        final start = next(text.length + 1);
        final end = start + next(text.length - start + 2);
        final wordsBefore = next(6);
        final wordsAfter = next(6);
        expect(
          ErrorReportHelper.buildContextAroundSelection(
            text,
            start,
            end,
            wordsBefore: wordsBefore,
            wordsAfter: wordsAfter,
          ),
          equals(
            _fullScanContext(
              text,
              start,
              end,
              wordsBefore: wordsBefore,
              wordsAfter: wordsAfter,
            ),
          ),
          reason: 'round $round: start=$start end=$end len=${text.length}',
        );
      }
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
      final params = {'test': 'value with spaces & special = chars'};

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

  group('ErrorReportHelper.correctionSnippets', () {
    const line =
        '<b>ומ"ש</b> בכרמלית הסמוך לו וכתב כרא"ש הרמב"ם בפי"ז השוה יחד ועוד שתי מילים';
    final start = line.indexOf('כרא"ש');
    TextCorrection correction(String? proposed) => TextCorrection.selection(
      originalLine: line,
      start: start,
      end: start + 'כרא"ש'.length,
      proposedText: proposed,
    );

    test('ארבע מילים לפני ואחרי השינוי, והשינוי מסומן', () {
      final snippets = ErrorReportHelper.correctionSnippets(
        correction('הרא"ש'),
      )!;
      expect(
        snippets.wrong,
        'בכרמלית הסמוך לו וכתב כרא"ש הרמב"ם בפי"ז השוה יחד',
      );
      expect(
        snippets.fixed,
        'בכרמלית הסמוך לו וכתב *הרא"ש* הרמב"ם בפי"ז השוה יחד',
      );
    });

    test('מחיקה, בלי הצעה ובלי שינוי נראה', () {
      expect(
        ErrorReportHelper.correctionSnippets(correction(''))!.fixed,
        'בכרמלית הסמוך לו וכתב *(נמחק: כרא"ש)* הרמב"ם בפי"ז השוה יחד',
      );
      expect(ErrorReportHelper.correctionSnippets(correction(null)), isNull);
      expect(
        ErrorReportHelper.correctionSnippets(
          const TextCorrection.wholeLine(
            originalLine: 'א <b>ב</b>',
            proposedText: 'א ב',
          ),
        ),
        isNull,
      );
    });

    test('הטקסט כפי שהוא מוצג: <br> מפריד מילים וישויות מפוענחות', () {
      final snippets = ErrorReportHelper.correctionSnippets(
        const TextCorrection.wholeLine(
          originalLine: 'זאת<br>יהי &quot;רצון&quot;&thinsp;שגוי',
          proposedText: 'זאת<br/>יהי &quot;רצון&quot;&thinsp;נכון',
        ),
      )!;
      expect(snippets.wrong, 'זאת יהי "רצון" שגוי');
      expect(snippets.fixed, 'זאת יהי "רצון" *נכון*');
    });

    test('גוף המייל: טקסט שגוי ומתוקן במקום בלוק ההצעה', () {
      final details = ErrorReportHelper.emailErrorDetails(
        ReportedErrorData(
          selectedText: 'כרא"ש',
          errorDetails: 'טעות הקלדה',
          correction: correction('הרא"ש'),
        ),
      );
      expect(
        details,
        'טעות הקלדה\n\nהטקסט השגוי:\n'
        'בכרמלית הסמוך לו וכתב כרא"ש הרמב"ם בפי"ז השוה יחד\n\n'
        'הטקסט המתוקן:\n'
        'בכרמלית הסמוך לו וכתב *הרא"ש* הרמב"ם בפי"ז השוה יחד',
      );
    });
  });

  test('מייל למקור שאינו ספריא: טקסט שגוי ומתוקן, ואחריהם ההצעה המלאה', () {
    final details = ErrorReportHelper.emailErrorDetails(
      ReportedErrorData(
        selectedText: 'ב',
        errorDetails: '',
        correction: TextCorrection.selection(
          originalLine: 'א ב ג',
          start: 2,
          end: 3,
          proposedText: 'נ',
        ),
      ),
      withFullProposal: true,
    );
    expect(
      details,
      startsWith('הטקסט השגוי:\nא ב ג\n\nהטקסט המתוקן:\nא *נ* ג'),
    );
    expect(details, endsWith('--- הצעת תיקון ---\nמקור: ב\nמוצע: נ'));
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
        final content = ['אחת טעות שתיים טעות שלוש', 'שורה נוספת לבדיקה'];

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
      final content = ['שורה עם טקסט', 'שורה עם טקסט'];

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
        final content = ['אמר שלום ואז שלום ושוב שלום'];

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
      final content = ['שורה ראשונה', 'שורה שנייה'];

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
      final content = ['שורה ללא התאמה', 'שורה עם מילה מיוחדת'];

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

      expect(
        tester
            .widget<ActionButton>(
              find.widgetWithText(ActionButton, 'שלח ישירות לאוצריא'),
            )
            .onPressed,
        isNull,
      );

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
          'לחיצה על שלח דיווח תשלח את השגיאה ישירות לספריא. יש לבדוק את תקינות הדיווח לפני השליחה.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ספריא: הנחיות דיווח ובלי דיווח חופשי כשיש עורך תיקון', (
      tester,
    ) async {
      Widget tab({
        required bool isSefariaSource,
        String line = 'שורה לבדיקה',
      }) => MaterialApp(
        home: Scaffold(
          body: RegularReportTab(
            selectedText: 'לבדיקה',
            fontSize: 18,
            directReportTargetLabel: isSefariaSource ? 'ספריא' : 'אוצריא',
            isSefariaSource: isSefariaSource,
            correctionTemplate: buildCorrectionTemplate(line, 'לבדיקה'),
            onActionSelected: (_, _) {},
            onCancel: () {},
          ),
        ),
      );

      await tester.pumpWidget(tab(isSefariaSource: true));
      await tester.pumpAndSettle();
      expect(find.textContaining('הדיווח יישלח לספריא'), findsOneWidget);
      expect(find.text('דיווח חופשי'), findsNothing);

      await tester.pumpWidget(tab(isSefariaSource: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('הדיווח יישלח לספריא'), findsNothing);
      expect(find.text('דיווח חופשי'), findsOneWidget);

      await tester.tap(find.text('דיווח חופשי'));
      await tester.pumpAndSettle();
      expect(
        find.text('העתיקו כמה מילים כפי שהן בספר, ושוב כשהן מתוקנות'),
        findsOneWidget,
      );

      // שורה ארוכה מהתקרה חוסמת הצעת תיקון; בלי דיווח חופשי לא היה מסלול שליחה.
      final longLine = '${'א' * TextCorrection.maxTextLength} לבדיקה';
      await tester.pumpWidget(tab(isSefariaSource: true, line: longLine));
      await tester.pumpAndSettle();
      expect(find.text('דיווח חופשי'), findsOneWidget);
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

  group('RegularReportTab — Ctrl+Enter שולח (#1537)', () {
    const confirmTitle = 'אישור שליחת דיווח';

    Future<List<ErrorReportAction>> pumpTab(WidgetTester tester) async {
      final actions = <ErrorReportAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RegularReportTab(
              selectedText: 'טקסט לבדיקה',
              fontSize: 18,
              directReportTargetLabel: 'אוצריא',
              onActionSelected: (action, _) => actions.add(action),
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return actions;
    }

    Future<void> pressWith(
      WidgetTester tester,
      LogicalKeyboardKey modifier,
    ) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+Enter מפעיל את השליחה הישירה', (tester) async {
      ShortcutHelper.isMacForTesting = false;
      addTearDown(() => ShortcutHelper.isMacForTesting = null);
      final actions = await pumpTab(tester);

      await tester.enterText(find.byType(TextField), 'פירוט הטעות');
      await tester.pumpAndSettle();
      await pressWith(tester, LogicalKeyboardKey.controlLeft);

      expect(find.text(confirmTitle), findsOneWidget);
      await tester.tap(find.text('שלח דיווח'));
      await tester.pumpAndSettle();
      expect(actions, [ErrorReportAction.sendDirect]);
    });

    testWidgets('ב-Mac Cmd+Enter מפעיל את השליחה', (tester) async {
      ShortcutHelper.isMacForTesting = true;
      addTearDown(() => ShortcutHelper.isMacForTesting = null);
      await pumpTab(tester);

      await tester.enterText(find.byType(TextField), 'פירוט הטעות');
      await tester.pumpAndSettle();
      await pressWith(tester, LogicalKeyboardKey.metaLeft);

      expect(find.text(confirmTitle), findsOneWidget);
    });

    testWidgets('בלי פירוט חובה Ctrl+Enter לא עושה כלום', (tester) async {
      ShortcutHelper.isMacForTesting = false;
      addTearDown(() => ShortcutHelper.isMacForTesting = null);
      final actions = await pumpTab(tester);

      await pressWith(tester, LogicalKeyboardKey.controlLeft);

      expect(find.text(confirmTitle), findsNothing);
      expect(actions, isEmpty);
    });

    testWidgets('Enter רגיל בשדה הפירוט לא שולח', (tester) async {
      ShortcutHelper.isMacForTesting = false;
      addTearDown(() => ShortcutHelper.isMacForTesting = null);
      final actions = await pumpTab(tester);

      await tester.enterText(find.byType(TextField), 'פירוט הטעות');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text(confirmTitle), findsNothing);
      expect(actions, isEmpty);
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
            'minWidth ≤ maxWidth.',
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

    Future<double> dialogHeightOn(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
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
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => TabbedReportDialog(
                    selectedText: 'טקסט',
                    fontSize: 18,
                    bookTitle: 'ספר בדיקה',
                    currentLineNumber: 0,
                    directReportTargetLabel: 'אוצריא',
                    correctionTemplate: buildCorrectionTemplate(
                      'שורה לבדיקה',
                      'לבדיקה',
                    ),
                  ),
                ),
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return tester
          .getSize(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .height;
    }

    testWidgets('במסך נמוך הדיאלוג לא נחתך ל-70% מהגובה', (tester) async {
      final height = await dialogHeightOn(tester, const Size(1200, 700));
      expect(height, greaterThan(700 * 0.7));
      expect(height, lessThanOrEqualTo(700));
    });

    testWidgets('במסך גבוה הדיאלוג נשאר 70% מהגובה', (tester) async {
      final height = await dialogHeightOn(tester, const Size(1200, 1200));
      expect(height, closeTo(1200 * 0.7, 1));
    });
  });

  test('surrogate בודד בשדות החופשיים מוחלף ב-U+FFFD, וה-digest מחושב', () {
    final report = ErrorReportHelper.buildDirectReport(
      senderEmail: 'user@example.com',
      reportData: const ReportedErrorData(
        selectedText: 'א\uD83D',
        errorDetails: 'פירוט \uDE00',
      ),
      bookTitle: 'ספר',
      currentRef: 'א',
      bookDetails: const {},
      lineNumber: 1,
      contextText: 'הקשר\uD83D',
      libraryVersion: '27',
    );

    expect(report.selectedText, 'א�');
    expect(report.errorDetails, 'פירוט �');
    expect(report.contextText, 'הקשר�');
    expect(report.contentDigest, hasLength(64));
  });

  test('הצעת תיקון בלי הצעה (null) נשלחת כדיווח חופשי', () {
    const line = 'א ב ג';
    final report = ErrorReportHelper.buildDirectReport(
      senderEmail: 'user@example.com',
      reportData: ReportedErrorData(
        selectedText: 'ב',
        errorDetails: 'יש כאן טעות',
        correction: TextCorrection.wholeLine(
          originalLine: line,
          proposedText: null,
        ),
      ),
      bookTitle: 'ספר',
      currentRef: 'א',
      bookDetails: const {},
      lineNumber: 1,
      contextText: line,
      libraryVersion: '27',
      source: ReportSourceSnapshot(
        bookId: 1,
        lineIndex: 0,
        heRef: null,
        originalLine: line,
      ),
    );

    expect(report.reportKind, DirectErrorReportKind.freeText);
    expect(report.correction, isNull);
    expect(report.toApiPayload()['report_kind'], 'free_text');
  });

  test('created_at של דיווח חדש נשלח ב-UTC עם Z', () {
    final report = ErrorReportHelper.buildDirectReport(
      senderEmail: 'user@example.com',
      reportData: const ReportedErrorData(selectedText: 'א', errorDetails: 'ב'),
      bookTitle: 'ספר',
      currentRef: 'א',
      bookDetails: const {},
      lineNumber: 1,
      contextText: '',
      libraryVersion: '27',
    );

    final createdAt = report.toApiPayload()['created_at'] as String;
    expect(createdAt, endsWith('Z'));
    expect(DateTime.parse(createdAt).isUtc, isTrue);
  });
  group('שדות תצוגה ארוכים — מקוצרים לתקרות האתר, שדות מדויקים לא', () {
    ReportSourceSnapshot source(String line) => ReportSourceSnapshot(
      bookId: 1,
      lineIndex: 0,
      heRef: null,
      originalLine: line,
    );

    test('selected/context/title/ref/subject מקוצרים; correction שלם', () {
      final line = 'א' * 15000;
      final report = ErrorReportHelper.buildDirectReport(
        senderEmail: 'user@example.com',
        reportData: ReportedErrorData(
          selectedText: line,
          errorDetails: 'פירוט',
          correction: TextCorrection.wholeLine(
            originalLine: line,
            proposedText: 'ב' * 15000,
          ),
        ),
        bookTitle: 'ס' * 400,
        currentRef: 'ר' * 400,
        bookDetails: const {},
        lineNumber: 1,
        contextText: 'ה' * 25000,
        libraryVersion: '27',
        source: source(line),
      );

      final payload = report.toApiPayload();
      expect((payload['selected_text'] as String).length, 10000);
      expect(payload['selected_text'], endsWith('…'));
      expect((payload['context_text'] as String).length, 20000);
      expect((payload['book_title'] as String).length, 300);
      expect((payload['current_ref'] as String).length, 300);
      expect((payload['subject'] as String).length, lessThanOrEqualTo(500));
      expect(payload['error_details'], startsWith('פירוט'));
      final correction = payload['correction'] as Map<String, dynamic>;
      expect(correction['original_line'], line);
      expect(correction['proposed_text'], 'ב' * 15000);
      expect(payload['content_digest'], report.contentDigest);
    });

    test('קיצור לא חוצה זוג surrogate', () {
      final report = ErrorReportHelper.buildDirectReport(
        senderEmail: 'user@example.com',
        reportData: ReportedErrorData(
          selectedText: '${'א' * 9998}😀😀',
          errorDetails: '',
        ),
        bookTitle: 'ספר',
        currentRef: 'א',
        bookDetails: const {},
        lineNumber: 1,
        contextText: '',
        libraryVersion: '27',
      );

      expect(report.selectedText, '${'א' * 9998}…');
      expect(hasLoneSurrogate(report.selectedText), isFalse);
    });

    test('ערך בתוך התקרה נשאר כלשונו', () {
      final text = 'א' * 10000;
      final report = ErrorReportHelper.buildDirectReport(
        senderEmail: 'user@example.com',
        reportData: ReportedErrorData(selectedText: text, errorDetails: ''),
        bookTitle: 'ספר',
        currentRef: 'א',
        bookDetails: const {},
        lineNumber: 1,
        contextText: '',
        libraryVersion: '27',
      );
      expect(report.selectedText, text);
    });
  });

  // בספר שהדיווח עליו לא מגיע לתיבת אוצריא (ספריא) אין עורך תיקון, והטופס קצר;
  // בגובה המלא רוב הדיאלוג נשאר ריק (issue #1599).
  group('גובה דיאלוג הדיווח', () {
    Future<double> dialogHeight(
      WidgetTester tester, {
      TextCorrection? correctionTemplate,
    }) async {
      tester.view.physicalSize = const Size(1920, 1020);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => TabbedReportDialog(
                    selectedText: List.filled(60, 'מילה ארוכה').join(' '),
                    fontSize: 18,
                    bookTitle: 'ספר בדיקה',
                    currentLineNumber: 0,
                    directReportTargetLabel: 'ספריא',
                    correctionTemplate: correctionTemplate,
                  ),
                ),
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(RegularReportTab)).height;
    }

    ScrollPosition formScroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(RegularReportTab),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                ),
              )
              .first,
        )
        .position;

    testWidgets('אין לשונית דיווח דרך קו אוצריא (issue #3615)', (tester) async {
      await dialogHeight(tester);

      expect(find.byType(TabBar), findsNothing);
      expect(find.textContaining('קו אוצריא'), findsNothing);
      expect(find.byType(RegularReportTab), findsOneWidget);
    });

    testWidgets('טופס חופשי נשאר קצר ויציב, והשדות והפעולות נגישים בגלילה', (
      tester,
    ) async {
      final initial = await dialogHeight(tester);

      expect(initial, lessThan(500), reason: 'לא בגובה של טופס עם עורך');
      expect(
        tester.getSize(find.byType(RegularReportTab)).width,
        closeTo(720, 1),
        reason: 'הטופס משתמש ברוחב large גם בחלון רחב',
      );
      await tester.enterText(
        find.byKey(const ValueKey('report-details-field')),
        List.filled(12, 'שורה').join('\n'),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(RegularReportTab)).height,
        initial,
        reason: 'הגובה אינו משתנה בזמן ההקלדה',
      );
      // ההוראות וסימון המיקום נגללים בטופס הקצר; הפעולות נשארות מחוץ לגלילה.
      final scroll = formScroll(tester);
      expect(scroll.maxScrollExtent, greaterThan(0));
      await tester.ensureVisible(
        find.byKey(const ValueKey('report-details-field')),
      );
      await tester.pumpAndSettle();
      expect(scroll.pixels, greaterThan(0));
      expect(find.text('שמור לשליחה מאוחרת').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('book-report-save-draft')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('טופס עם עורך תיקון נשאר בגובה הנוח', (tester) async {
      final height = await dialogHeight(
        tester,
        correctionTemplate: buildCorrectionTemplate('שורה לבדיקה', 'לבדיקה'),
      );

      expect(height, greaterThan(560));
    });
  });

  group('TabbedReportDialog — סגירה (DD-08)', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => const TabbedReportDialog(
                    selectedText: 'קטע',
                    fontSize: 18,
                    bookTitle: 'ספר בדיקה',
                    currentLineNumber: 1,
                    directReportTargetLabel: 'אוצריא',
                  ),
                ),
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    }

    final details = find.byKey(const ValueKey('report-details-field'));

    testWidgets('Escape סוגר טופס ריק', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TabbedReportDialog), findsNothing);
    });

    testWidgets('עם טקסט Escape שואל ו"המשך לערוך" שומר את הטקסט', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(details, 'פירוט הטעות');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
      await tester.tap(find.text('המשך לערוך'));
      await tester.pumpAndSettle();
      expect(find.byType(TabbedReportDialog), findsOneWidget);
      expect(find.text('פירוט הטעות'), findsOneWidget);
    });

    testWidgets('עם טקסט X וכפתור היציאה שואלים לפני הסגירה', (tester) async {
      await open(tester);
      await tester.enterText(details, 'פירוט הטעות');
      await tester.pump();
      await tester.tap(find.byTooltip('סגור'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('המשך לערוך'));
      await tester.pumpAndSettle();
      final close = find.byKey(const ValueKey('book-report-save-draft'));
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
      await tester.tap(find.text('סגור בלי לשמור'));
      await tester.pumpAndSettle();
      expect(find.byType(TabbedReportDialog), findsNothing);
    });

    testWidgets('מעבר לתיקון עצמי בדיקטה סוגר בלי לשאול, גם עם טקסט', (
      tester,
    ) async {
      final previousLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = _SucceedingUrlLauncher();
      addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => const TabbedReportDialog(
                    selectedText: 'קטע',
                    fontSize: 18,
                    bookTitle: 'ספר בדיקה',
                    currentLineNumber: 1,
                    directReportTargetLabel: 'אוצריא',
                    isDictaSource: true,
                  ),
                ),
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
      await tester.enterText(details, 'פירוט הטעות');
      await tester.pump();

      await tester.tap(find.text('לחץ כאן על מנת לתקן את הספר בעצמך'));
      await tester.pumpAndSettle();

      expect(find.text('לסגור בלי לשמור?'), findsNothing);
      expect(find.byType(TabbedReportDialog), findsNothing);
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
  );
}

/// העתק של האלגוריתם שסורק את כל הטקסט, כמקור אמת להשוואה.
String _fullScanContext(
  String fullText,
  int selectionStart,
  int selectionEnd, {
  int wordsBefore = 4,
  int wordsAfter = 4,
}) {
  if (selectionStart < 0 || selectionEnd <= selectionStart) return fullText;
  final matches = RegExp(r'\S+').allMatches(fullText).toList();
  if (matches.isEmpty) return fullText;

  var startWordIndex = 0;
  var endWordIndex = matches.length - 1;
  for (var i = 0; i < matches.length; i++) {
    if (selectionStart < matches[i].end) {
      startWordIndex = i;
      break;
    }
  }
  final selEndMinusOne = selectionEnd - 1;
  for (var i = matches.length - 1; i >= 0; i--) {
    final m = matches[i];
    if ((selEndMinusOne >= m.start && selEndMinusOne < m.end) ||
        selEndMinusOne > m.end) {
      endWordIndex = i;
      break;
    }
  }

  final ctxStart = startWordIndex - wordsBefore < 0
      ? 0
      : startWordIndex - wordsBefore;
  final ctxEnd = endWordIndex + wordsAfter >= matches.length
      ? matches.length - 1
      : endWordIndex + wordsAfter;
  final from = matches[ctxStart].start;
  final to = matches[ctxEnd].end;
  if (from < 0 || to <= from || to > fullText.length) return fullText;
  return fullText.substring(from, to);
}
