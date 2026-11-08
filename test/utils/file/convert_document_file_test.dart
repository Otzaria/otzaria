import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/services/external_book_import.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:path/path.dart' as p;

import 'docx_golden_fixtures.dart';

/// [convertDocumentFile] קורא את הקובץ באופן אסינכרוני (#4532); הפלט, זיהוי
/// הפורמט והשגיאות חייבים להישאר זהים להמרת אותם בייטים ישירות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('convert-document-file-');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // נעילת קובץ ב-Windows אינה מעניינה של הבדיקה.
    }
  });

  final docx = buildDocx(
    document: documentXml(
      '${styledPara('Heading1', 'פרק ראשון')}'
      '${para('פסקת פתיחה')}'
      '<w:p>${drawingImage('rId1')}</w:p>',
    ),
    rels: relsXml({'rId1': 'media/image1.png'}),
    media: {'image1.png': kTinyPng},
  );

  Future<File> write(String name, List<int> bytes) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  final cases = <String, List<int>>{
    'ספר.txt': utf8.encode('<h1>כותרת</h1>\nשורה'),
    'ספר.html': utf8.encode(
      '<html><body><h2>פרק</h2><p>טקסט</p></body></html>',
    ),
    'ספר.md': utf8.encode('# פרק\n\nטקסט'),
    'ספר.docx': docx,
    'גיבוי.wbk': docx,
  };

  for (final MapEntry(key: name, value: bytes) in cases.entries) {
    for (final embedImages in [true, false]) {
      test('$name (embedImages: $embedImages) זהה להמרת הבייטים', () async {
        final file = await write(name, bytes);
        final expected = convertDocumentBytesSync(
          await file.readAsBytes(),
          p.basenameWithoutExtension(name),
          format: documentFormatFromExtension(name)!,
          embedImages: embedImages,
          path: file.path,
        );

        final actual = await Isolate.run(
          () => convertDocumentFile(file.path, embedImages: embedImages),
        );

        expect(actual, expected);
      });
    }
  }

  test('פורמט מוצהר גובר על הסיומת', () async {
    final file = await write('ספר.bin', docx);
    final text = await convertDocumentFile(
      file.path,
      format: DocumentFormat.docx,
    );
    expect(text, contains('<h1>פרק ראשון</h1>'));
  });

  test('WBK שתוכנו אינו Word נכשל עם הפורמט המוצהר', () async {
    final file = await write('גיבוי.wbk', utf8.encode('לא מסמך'));
    await expectLater(
      convertDocumentFile(file.path),
      throwsA(
        isA<UnsupportedDocumentFormatException>().having(
          (e) => e.format,
          'format',
          DocumentFormat.wbk,
        ),
      ),
    );
  });

  test('קובץ חסר זורק FileSystemException', () async {
    await expectLater(
      convertDocumentFile(p.join(tempDir.path, 'חסר.txt')),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('PreparedExternalBook.prepare בונה TOC מהקובץ המומר', () async {
    final file = await write('ספר.docx', docx);
    final book = await prepareExternalBookInIsolate(
      file.path,
      await file.stat(),
      DocumentFormat.docx,
    );
    expect(book.title, 'ספר');
    expect(book.fileType, 'docx');
    expect(book.tocEntries!.map((e) => e.text), ['ספר', 'פרק ראשון']);
  });

  test('PreparedExternalBook.prepare ל-PDF אינו קורא את הקובץ', () async {
    final file = await write('ספר.pdf', const [0x25, 0x50, 0x44, 0x46]);
    final stat = await file.stat();
    await file.delete();
    final book = await PreparedExternalBook.prepare(
      file.path,
      stat,
      DocumentFormat.pdf,
    );
    expect(book.tocEntries, isNull);
  });
}
