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

  group('hasHiddenOrSystemWindowsAttributes', () {
    test('מזהה את מאפייני hidden ו-system', () {
      expect(hasHiddenOrSystemWindowsAttributes(0x2), isTrue);
      expect(hasHiddenOrSystemWindowsAttributes(0x4), isTrue);
      expect(hasHiddenOrSystemWindowsAttributes(0x6), isTrue);
    });

    test('דוחה מאפיינים רגילים וערך מאפיינים לא תקין', () {
      expect(hasHiddenOrSystemWindowsAttributes(0), isFalse);
      expect(hasHiddenOrSystemWindowsAttributes(0x20), isFalse);
      expect(hasHiddenOrSystemWindowsAttributes(0xFFFFFFFF), isFalse);
    });
  });
}
