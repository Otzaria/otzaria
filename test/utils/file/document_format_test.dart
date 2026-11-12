import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/utils/file/document_format.dart';

/// בונה ארכיון ZIP בזיכרון עם הרשומות הנתונות — כדי שבדיקות זיהוי-התוכן לא
/// יידרשו לקבצים בינאריים בריפו.
Uint8List _zip(Map<String, String> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  group('documentFormatFromExtension', () {
    test('מזהה את כל הסיומות המוכרות', () {
      const cases = {
        'a.txt': DocumentFormat.txt,
        'a.text': DocumentFormat.text,
        'a.pdf': DocumentFormat.pdf,
        'a.epub': DocumentFormat.epub,
        'a.md': DocumentFormat.md,
        'a.markdown': DocumentFormat.markdown,
        'a.docx': DocumentFormat.docx,
        'a.docm': DocumentFormat.docm,
        'a.dotx': DocumentFormat.dotx,
        'a.dotm': DocumentFormat.dotm,
        'a.doc': DocumentFormat.doc,
        'a.dot': DocumentFormat.dot,
        'a.wbk': DocumentFormat.wbk,
        'a.rtf': DocumentFormat.rtf,
        'a.odt': DocumentFormat.odt,
        'a.xhtml': DocumentFormat.xhtml,
      };
      cases.forEach((path, expected) {
        expect(documentFormatFromExtension(path), expected, reason: path);
      });
    });

    test('אינו רגיש לרישיות', () {
      for (final path in ['a.DOCX', 'a.DocX', 'a.dOcX', 'a.ODT', 'a.Rtf']) {
        expect(documentFormatFromExtension(path), isNotNull, reason: path);
      }
      expect(documentFormatFromExtension('a.DOCX'), DocumentFormat.docx);
      expect(documentFormatFromExtension('a.DocX'), DocumentFormat.docx);
    });

    test('נתיב עם כמה נקודות — נלקחת האחרונה', () {
      expect(
        documentFormatFromExtension('multiple.dots.file.docx'),
        DocumentFormat.docx,
      );
      expect(
        documentFormatFromExtension(r'C:\ספרים\ר. יוסף\א.docx'),
        DocumentFormat.docx,
      );
    });

    test('ללא סיומת / סיומת לא מוכרת → null', () {
      expect(documentFormatFromExtension('noextension'), isNull);
      expect(documentFormatFromExtension('a.xyz'), isNull);
      expect(documentFormatFromExtension('a.'), isNull);
      expect(documentFormatFromExtension(''), isNull);
    });

    test('נקודה בשם התיקייה בלבד אינה נחשבת לסיומת', () {
      expect(documentFormatFromExtension('/home/user.v2/book'), isNull);
      expect(documentFormatFromExtension(r'C:\dir.v2\book'), isNull);
    });
  });

  group('documentFormatFromFileType', () {
    test('משתמש בנרמול היחיד של BookCompositeKey', () {
      for (final value in ['docx', 'DOCX', ' DocX ', 'DocX']) {
        expect(
          documentFormatFromFileType(value),
          DocumentFormat.docx,
          reason: value,
        );
      }
    });

    test('null/ריק → txt, בהתאם לנרמול הקיים', () {
      expect(BookCompositeKey.normalizeFileType(null), 'txt');
      expect(documentFormatFromFileType(null), DocumentFormat.txt);
      expect(documentFormatFromFileType(''), DocumentFormat.txt);
      expect(documentFormatFromFileType('   '), DocumentFormat.txt);
    });

    test('fileType לא מוכר → null (ולא נפילה שקטה ל-txt)', () {
      expect(documentFormatFromFileType('xyz'), isNull);
    });

    test('documentFormatOf מעדיף fileType ונופל לסיומת', () {
      expect(
        documentFormatOf(fileType: 'epub', path: 'a.docx'),
        DocumentFormat.epub,
      );
      expect(
        documentFormatOf(fileType: null, path: 'a.docx'),
        DocumentFormat.docx,
      );
      expect(
        documentFormatOf(fileType: 'xyz', path: 'a.odt'),
        DocumentFormat.odt,
      );
      expect(documentFormatOf(fileType: 'xyz', path: 'a.xyz'), isNull);
    });
  });

  group('invariant של fileType (§15)', () {
    test('כל פורמט חוזר לעצמו דרך fileType — אין מיפוי למשפחה', () {
      for (final format in DocumentFormat.values) {
        expect(
          documentFormatFromFileType(format.extension),
          format,
          reason: '${format.extension} חייב לחזור לעצמו',
        );
      }
    });

    test('docm/dotx/dotm אינם ממופים ל-docx למרות אותו מנוע', () {
      expect(DocumentFormat.docm.extension, 'docm');
      expect(DocumentFormat.dotx.extension, 'dotx');
      expect(DocumentFormat.dotm.extension, 'dotm');
      expect(DocumentFormat.docm.isOoxmlWord, isTrue);
      expect(DocumentFormat.docm, isNot(DocumentFormat.docx));
    });

    test('הנרמול של BookCompositeKey שומר את הסיומת כפי שהיא', () {
      for (final format in DocumentFormat.values) {
        expect(
          BookCompositeKey.normalizeFileType(format.extension.toUpperCase()),
          format.extension,
        );
      }
    });
  });

  group('registry (§10, §80)', () {
    test('כל סיומת ברשימה הנתמכת ניתנת למיפוי ל-DocumentFormat', () {
      for (final ext in kSupportedBookExtensions) {
        expect(documentFormatFromFileType(ext), isNotNull, reason: ext);
      }
    });

    test('isSupportedBookFile — רישיות אינה משנה', () {
      for (final path in ['ספר.docx', 'ספר.DOCX', 'ספר.DocX']) {
        expect(isSupportedBookFile(path), isTrue, reason: path);
      }
      expect(isSupportedBookFile('ספר.text'), isTrue);
    });

    test('isSupportedBookFile דוחה סיומת שאינה ב-registry', () {
      expect(isSupportedBookFile('ספר.xyz'), isFalse);
      expect(isSupportedBookFile('ספר.xls'), isFalse);
      expect(isSupportedBookFile('ספר'), isFalse);
    });

    test('כל פורמט ב-enum פעיל — ולכל אחד יש ממיר', () {
      // ברגע שכל הפורמטים נכנסו ל-production, ה-registry וה-enum זהים.
      // אם ייווסף ערך חדש בלי ממיר — יש להוציאו מ-kProductionBookFormats,
      // והבדיקה כאן תיכשל ותזכיר לעדכן גם את הבדיקות שמסתמכות על כך.
      expect(kProductionBookFormats, DocumentFormat.values.toSet());
    });
  });

  group('זיהוי לפי תוכן (§12, §79)', () {
    test('OOXML אמיתי מזוהה גם בלי הסיומת', () {
      final bytes = _zip({
        '[Content_Types].xml': '<Types/>',
        'word/document.xml': '<w:document/>',
      });
      expect(detectDocumentFormatFromContentSync(bytes), DocumentFormat.docx);
    });

    test('ODT מזוהה לפי ה-mimetype והמניפסט', () {
      final bytes = _zip({
        'mimetype': 'application/vnd.oasis.opendocument.text',
        'content.xml': '<office:document-content/>',
        'META-INF/manifest.xml': '<manifest/>',
      });
      expect(detectDocumentFormatFromContentSync(bytes), DocumentFormat.odt);
    });

    test('EPUB אינו מזוהה בטעות כ-ODT', () {
      final bytes = _zip({
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': '<container/>',
      });
      expect(detectDocumentFormatFromContentSync(bytes), DocumentFormat.epub);
    });

    test('OLE ישן מזוהה כ-Word בינארי', () {
      final bytes = _bytes([
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
        0, 0, 0, 0, 0, 0, 0, 0,
      ]);
      expect(detectDocumentFormatFromContentSync(bytes), DocumentFormat.doc);
    });

    test('RTF ו-PDF מזוהים לפי החתימה', () {
      expect(
        detectDocumentFormatFromContentSync(
          Uint8List.fromList(utf8.encode(r'{\rtf1\ansi hello}')),
        ),
        DocumentFormat.rtf,
      );
      expect(
        detectDocumentFormatFromContentSync(
          Uint8List.fromList(utf8.encode('%PDF-1.7\n')),
        ),
        DocumentFormat.pdf,
      );
    });

    test('טקסט רגיל → null (אין חתימה בינארית)', () {
      expect(
        detectDocumentFormatFromContentSync(
          Uint8List.fromList(utf8.encode('שלום עולם')),
        ),
        isNull,
      );
      expect(detectDocumentFormatFromContentSync(Uint8List(0)), isNull);
    });

    test('ZIP שאינו אף חבילה מוכרת → null', () {
      expect(
        detectDocumentFormatFromContentSync(_zip({'a.txt': 'hi'})),
        isNull,
      );
    });
  });

  group('resolveDocumentFormat — הסיומת מול התוכן', () {
    test('docm נשאר docm אף שהתוכן מזוהה כ-OOXML גנרי', () {
      final bytes = _zip({'word/document.xml': '<w:document/>'});
      expect(
        resolveDocumentFormat(DocumentFormat.docm, bytes),
        DocumentFormat.docm,
      );
      expect(
        resolveDocumentFormat(DocumentFormat.dotx, bytes),
        DocumentFormat.dotx,
      );
    });

    test('WBK שהוא OOXML מנותב למנוע OOXML', () {
      final bytes = _zip({'word/document.xml': '<w:document/>'});
      expect(
        resolveDocumentFormat(DocumentFormat.wbk, bytes),
        DocumentFormat.docx,
      );
    });

    test('WBK שהוא Word בינארי מנותב למנוע הישן', () {
      final bytes = _bytes([
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0, 0, 0, //
      ]);
      expect(
        resolveDocumentFormat(DocumentFormat.wbk, bytes),
        DocumentFormat.doc,
      );
    });

    test('קובץ ששמו .docx אך תוכנו טקסט רגיל → null, לא docx', () {
      final bytes = Uint8List.fromList(utf8.encode('סתם טקסט'));
      expect(resolveDocumentFormat(DocumentFormat.docx, bytes), isNull);
    });

    test('קובץ ששמו .odt אך תוכנו OOXML מנותב ל-OOXML', () {
      final bytes = _zip({'word/document.xml': '<w:document/>'});
      expect(
        resolveDocumentFormat(DocumentFormat.odt, bytes),
        DocumentFormat.docx,
      );
    });

    test('TXT/MD אינם נפסלים בהיעדר חתימה בינארית', () {
      final bytes = Uint8List.fromList(utf8.encode('# כותרת'));
      expect(
        resolveDocumentFormat(DocumentFormat.md, bytes),
        DocumentFormat.md,
      );
      expect(
        resolveDocumentFormat(DocumentFormat.txt, bytes),
        DocumentFormat.txt,
      );
    });
  });
}
