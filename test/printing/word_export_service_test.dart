import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:pdf/pdf.dart';

void main() {
  group('WordExportService', () {
    test('creates a valid docx package with required OpenXML files', () {
      final bytes = WordExportService.createWordDocument(
        title: 'ספר בדיקה',
        blocks: const [
          PrintBlock(kind: PrintBlockKind.text, text: 'פסקה ראשונה'),
        ],
        format: PdfPageFormat.a4,
        isLandscape: false,
        pageMargin: 20,
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      final fileNames = archive.files.map((file) => file.name).toSet();

      expect(fileNames, contains('[Content_Types].xml'));
      expect(fileNames, contains('_rels/.rels'));
      expect(fileNames, contains('word/document.xml'));
      expect(fileNames, contains('word/styles.xml'));
      expect(fileNames, contains('word/numbering.xml'));
      expect(fileNames, contains('word/footnotes.xml'));
      expect(fileNames, contains('word/header1.xml'));
      expect(fileNames, contains('word/footer1.xml'));
      for (final file in archive.files) {
        expect(
          file.size,
          greaterThan(0),
          reason: '${file.name} should not be empty',
        );
      }
    });

    test('writes styled RTL content with footnotes', () {
      final bytes = WordExportService.createWordDocument(
        title: 'ספר מעוצב',
        blocks: const [
          PrintBlock(
            kind: PrintBlockKind.heading,
            text: 'פרק א',
            headingLevel: 1,
          ),
          PrintBlock(
            kind: PrintBlockKind.text,
            text: 'טקסט גוף רגיל',
            footnotes: [
              PrintFootnote(text: 'הערה שנשמרה למסמך'),
            ],
          ),
          PrintBlock(
            kind: PrintBlockKind.commentaryTitle,
            text: 'מפרשים',
          ),
          PrintBlock(
            kind: PrintBlockKind.commentaryGroupTitle,
            text: 'רש"י',
          ),
          PrintBlock(
            kind: PrintBlockKind.commentary,
            text: 'פירוש על הקטע',
          ),
        ],
        format: PdfPageFormat.a4,
        isLandscape: true,
        pageMargin: 24,
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      final documentXml = _readArchiveFile(archive, 'word/document.xml');
      final stylesXml = _readArchiveFile(archive, 'word/styles.xml');
      final footerXml = _readArchiveFile(archive, 'word/footer1.xml');
      final footnotesXml = _readArchiveFile(archive, 'word/footnotes.xml');

      expect(documentXml, contains('<w:pStyle w:val="Title"/>'));
      expect(documentXml, contains('<w:pStyle w:val="Heading1"/>'));
      expect(documentXml, contains('פרק א'));
      expect(documentXml, contains('<w:pStyle w:val="CommentaryHeading"/>'));
      expect(documentXml, contains('<w:pStyle w:val="CommentarySubheading"/>'));
      expect(documentXml, contains('<w:pStyle w:val="CommentaryBody"/>'));
      expect(documentXml, contains('\u200F'));
      expect(documentXml, contains('<w:footnoteReference w:id="2"/>'));
      expect(documentXml, contains('w:orient="landscape"'));
      expect(documentXml, contains('<w:bidi/>'));
      expect(documentXml, contains('<w:jc w:val="both"/>'));
      expect(documentXml, contains('<w:jc w:val="right"/>'));
      expect(documentXml, contains('<w:rPr><w:rtl/></w:rPr>'));
      expect(stylesXml, contains('w:bidi'));
      expect(stylesXml, contains('Footnote Text'));
      expect(footerXml, contains('NUMPAGES'));
      expect(footnotesXml, contains('הערה שנשמרה למסמך'));
    });
  });
}

String _readArchiveFile(Archive archive, String name) {
  final file = archive.findFile(name);
  expect(file, isNotNull, reason: 'Archive should contain $name');
  return utf8.decode(file!.content as List<int>);
}
