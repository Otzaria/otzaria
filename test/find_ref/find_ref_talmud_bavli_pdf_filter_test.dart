import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

DbReferenceResult _ref({
  bool isPdf = false,
  String bookPath = '',
  String filePath = '',
}) => DbReferenceResult(
  title: 'ברכות',
  reference: 'ברכות דף ב',
  segment: 2,
  isPdf: isPdf,
  bookPath: bookPath,
  filePath: filePath,
);

void main() {
  group('FindRefRepository.isTalmudBavliPdfRef', () {
    test('תוצאת PDF עם נתיב קטגוריה של תלמוד בבלי — מסוננת', () {
      expect(
        FindRefRepository.isTalmudBavliPdfRef(
          _ref(isPdf: true, bookPath: 'תלמוד בבלי, סדר זרעים'),
        ),
        isTrue,
      );
    });

    test('תוצאת טקסט של תלמוד בבלי — אינה מסוננת', () {
      expect(
        FindRefRepository.isTalmudBavliPdfRef(
          _ref(bookPath: 'תלמוד בבלי, סדר זרעים'),
        ),
        isFalse,
      );
    });

    test('תוצאת PDF שאינה תלמוד בבלי — אינה מסוננת', () {
      expect(
        FindRefRepository.isTalmudBavliPdfRef(
          _ref(isPdf: true, bookPath: 'תלמוד ירושלמי, סדר זרעים'),
        ),
        isFalse,
      );
      expect(
        FindRefRepository.isTalmudBavliPdfRef(
          _ref(isPdf: true, bookPath: 'משנה, סדר זרעים'),
        ),
        isFalse,
      );
    });

    test('PDF ממערכת הקבצים (ללא bookPath) — זיהוי לפי תיקיית הקובץ', () {
      expect(
        FindRefRepository.isTalmudBavliPdfRef(
          _ref(isPdf: true, filePath: r'C:\books\תלמוד בבלי\ברכות.pdf'),
        ),
        isTrue,
      );
      expect(
        FindRefRepository.isTalmudBavliPdfRef(
          _ref(isPdf: true, filePath: '/books/תלמוד בבלי/ברכות.pdf'),
        ),
        isTrue,
      );
      expect(
        FindRefRepository.isTalmudBavliPdfRef(
          _ref(isPdf: true, filePath: '/books/הלכה/ברכות.pdf'),
        ),
        isFalse,
      );
    });

    test('קטגוריה שרק מכילה את המחרוזת — אינה מסוננת (התאמת שורש בלבד)', () {
      expect(
        FindRefRepository.isTalmudBavliPdfRef(
          _ref(isPdf: true, bookPath: 'מפרשים, מפרשים על תלמוד בבלי'),
        ),
        isFalse,
      );
    });
  });
}
