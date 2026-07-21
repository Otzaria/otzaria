import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/file_hidden_utils.dart';
import 'package:path/path.dart' as path;

void main() {
  group('isHiddenOrSystem - name-based detection', () {
    test('מזהה קובץ שמתחיל בנקודה כמוסתר', () {
      expect(
        isHiddenOrSystem(path.join('books', '.hidden_notes.txt')),
        isTrue,
      );
    });

    test(r'מזהה קובץ שמתחיל ב-$ כמוסתר', () {
      expect(
        isHiddenOrSystem(path.join('books', r'$RECYCLE.BIN')),
        isTrue,
      );
    });

    test('לא מזהה קובץ txt רגיל כמוסתר', () {
      expect(isHiddenOrSystem(path.join('books', 'my_book.txt')), isFalse);
    });

    test('לא מזהה קובץ pdf רגיל כמוסתר', () {
      expect(isHiddenOrSystem(path.join('books', 'my_book.pdf')), isFalse);
    });

    test('לא מזהה קובץ docx רגיל כמוסתר', () {
      expect(isHiddenOrSystem(path.join('books', 'my_book.docx')), isFalse);
    });
  });

  group('isHiddenOrSystem - Windows attribute-based detection', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('file_hidden_utils_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'מזהה קובץ גיבוי Word (~\$שם.docx) כמוסתר כשהמערכת מסמנת אותו hidden',
      () async {
        // שם הגיבוי של Word מתחיל ב-~$ ולא ב-$, לכן ההגנה נסמכת על
        // מאפיין ה-hidden של Windows ולא על בדיקת השם בלבד.
        final file = File(path.join(tempDir.path, '~\$document.docx'));
        file.writeAsStringSync('backup');
        await Process.run('attrib', ['+h', file.path]);

        expect(isHiddenOrSystem(file.path), isTrue);
      },
      skip: !Platform.isWindows ? 'רלוונטי רק ב-Windows' : null,
    );

    test(
      'קובץ רגיל ללא מאפיין hidden לא מזוהה כמוסתר',
      () {
        final file = File(path.join(tempDir.path, 'regular_book.txt'));
        file.writeAsStringSync('content');

        expect(isHiddenOrSystem(file.path), isFalse);
      },
      skip: !Platform.isWindows ? 'רלוונטי רק ב-Windows' : null,
    );
  });
}
