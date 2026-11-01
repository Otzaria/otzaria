import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

TextBook _textBook({
  String fileType = 'txt',
  String? path,
  BookSource source = BookSource.official,
}) => TextBook(
  title: 'ספר',
  categoryId: 1,
  filePath: path,
  fileType: fileType,
  source: source,
);

void main() {
  group('bookFormatIconFor', () {
    test('ספר רשמי הוא תמיד המסמך הגנרי, ו-PDF הוא ספר PDF', () {
      expect(
        bookFormatIconFor(fileType: 'txt', isPersonal: false),
        FluentIcons.document_text_24_regular,
      );
      expect(
        bookFormatIconFor(fileType: 'pdf', isPersonal: false, isPdf: true),
        OtzariaIcons.book_pdf_24_regular,
      );
    });

    test('ספר אישי: הפורמט קובע את האייקון', () {
      final expected = {
        'txt': OtzariaIcons.document_alef_24_regular,
        'docx': OtzariaIcons.document_word_24_regular,
        'html': OtzariaIcons.document_html_24_regular,
        'md': OtzariaIcons.document_md_24_regular,
        'pdf': OtzariaIcons.book_pdf_24_regular,
      };
      expected.forEach((type, icon) {
        expect(
          bookFormatIconFor(fileType: type, isPersonal: true),
          icon,
          reason: type,
        );
      });
    });

    test('Markdown בספר רשמי נשאר המסמך הגנרי', () {
      expect(
        bookFormatIconFor(fileType: 'md', isPersonal: false),
        FluentIcons.document_text_24_regular,
      );
    });

    test('הסיומת קודמת ל-fileType: ספר מסמך שנשמר כ-PdfBook אינו PDF', () {
      expect(
        bookFormatIconFor(
          path: 'C:/docs/a.docx',
          fileType: 'pdf',
          isPersonal: true,
          isPdf: true,
        ),
        OtzariaIcons.document_word_24_regular,
      );
    });

    test('פורמט לא מוכר — ההחלטה נשארת למחלקת הספר', () {
      expect(
        bookFormatIconFor(fileType: 'xyz', isPersonal: true, isPdf: true),
        OtzariaIcons.book_pdf_24_regular,
      );
      expect(
        bookFormatIconFor(fileType: 'xyz', isPersonal: true),
        OtzariaIcons.document_alef_24_regular,
      );
    });
  });

  group('מטריצת פורמטים — המקור היחיד לספרייה, לאיתור ולרשימת הספרים', () {
    const generic = FluentIcons.document_text_24_regular;
    // סדר: (סיומת, אייקון לספר אישי, אייקון לספר רשמי).
    final matrix = <(String, IconData, IconData)>[
      for (final e in ['html', 'htm', 'xhtml'])
        (
          e,
          OtzariaIcons.document_html_24_regular,
          OtzariaIcons.document_html_24_regular,
        ),
      for (final e in ['md', 'markdown'])
        (e, OtzariaIcons.document_md_24_regular, generic),
      for (final e in ['docx', 'docm', 'doc', 'dot', 'odt', 'rtf'])
        (
          e,
          OtzariaIcons.document_word_24_regular,
          OtzariaIcons.document_word_24_regular,
        ),
      for (final e in ['pdf', 'epub'])
        (
          e,
          OtzariaIcons.book_pdf_24_regular,
          OtzariaIcons.book_pdf_24_regular,
        ),
      // טקסט גנרי, וב"אישי" ה-alef.
      for (final e in ['txt', 'text'])
        (e, OtzariaIcons.document_alef_24_regular, generic),
    ];

    for (final (ext, personal, official) in matrix) {
      test(ext, () {
        IconData byBook(BookSource source) => bookFormatIcon(
          _textBook(fileType: ext, path: 'C:/docs/a.$ext', source: source),
        );
        expect(byBook(BookSource.user), personal);
        expect(byBook(BookSource.attached('lib')), personal);
        expect(byBook(BookSource.official), official);
        // נתיב בלי סיומת: fileType לבדו מכריע.
        expect(
          bookFormatIconFor(fileType: ext, isPersonal: true),
          personal,
        );
        expect(
          bookFormatIconFor(fileType: ext, isPersonal: false),
          official,
        );
      });
    }
  });

  group('bookFormatIcon', () {
    test('נותן אותו אייקון כמו bookFormatIconFor לאותם נתונים', () {
      final word = _textBook(
        fileType: 'docx',
        path: 'C:/docs/a.docx',
        source: BookSource.user,
      );
      expect(
        bookFormatIcon(word),
        bookFormatIconFor(
          path: word.filePath,
          fileType: word.fileType,
          isPersonal: true,
        ),
      );
      expect(bookFormatIcon(word), OtzariaIcons.document_word_24_regular);
    });

    test('ספר PDF מהקבצים מקבל את אייקון ה-PDF', () {
      expect(
        bookFormatIcon(PdfBook(title: 'ספר', path: 'C:/a.pdf')),
        OtzariaIcons.book_pdf_24_regular,
      );
    });

    test('ספר ממסד אישי מצורף מוצג כספר אישי', () {
      expect(
        bookFormatIcon(_textBook(source: BookSource.attached('lib'))),
        OtzariaIcons.document_alef_24_regular,
      );
    });

    test('documentFormatIcon: רק Word, HTML ו-Markdown אישי', () {
      expect(
        documentFormatIcon(
          _textBook(fileType: 'docx', source: BookSource.user),
        ),
        OtzariaIcons.document_word_24_regular,
      );
      expect(documentFormatIcon(_textBook()), isNull);
      expect(
        documentFormatIcon(_textBook(fileType: 'md', source: BookSource.user)),
        OtzariaIcons.document_md_24_regular,
      );
    });
  });
}
