import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// היפוך הצבעים של ה-PDF חייב להיגזר מבהירות התמה בפועל: הדגל השמור
/// `isDarkMode` נשאר על ערכו הישן במצב "מערכת", וה-PDF נתקע כהה (issue #1426).
void main() {
  final lines = File(
    'lib/pdf_book/view/pdf_book_screen.dart',
  ).readAsLinesSync();
  final code = lines
      .where((line) => !line.trimLeft().startsWith('//'))
      .toList();

  test('אין צרכן של SettingsState.isDarkMode במסך ה-PDF', () {
    expect(code.join('\n'), isNot(contains('.state.isDarkMode')));
  });

  // דרך ReaderPageTheme.of, שמחזיר את Theme.of(context) אלא אם "דף הספר בהיר
  // גם במצב כהה" דולק והממשק כהה (issue #2435).
  test('כל היפוך צבעים נגזר מתמת הדף בפועל', () {
    final source = code.join('\n');
    final calls = RegExp(r'pdfPageColor(?:Filter)?\(').allMatches(source);
    final themed = RegExp(
      r'pdfPageColor(?:Filter)?\(\s*(?:ReaderPageTheme\.of\(context\)\.brightness|page\.brightness|brightness)\s*[,)]',
    ).allMatches(source);
    expect(calls, isNotEmpty);
    expect(themed.length, calls.length);
    expect(
      source,
      contains('final brightness = ReaderPageTheme.of(context).brightness;'),
    );
    expect(source, contains('final page = ReaderPageTheme.of(context);'));
  });

  test('דף הספר הטקסטואלי עטוף ב-ReaderPageScope (issue #2435)', () {
    final textBook = File(
      'lib/text_book/view/text_book_screen.dart',
    ).readAsStringSync();
    expect(textBook, contains('mainContent: ReaderPageScope('));
    final app = File('lib/app.dart').readAsStringSync();
    expect(
      app,
      contains('light: state.lightReaderPageInDarkMode ? lightTheme : null'),
    );
  });
}
