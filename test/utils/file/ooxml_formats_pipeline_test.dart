import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:path/path.dart' as p;

import 'docx_golden_fixtures.dart';

/// מוודא שכל פורמטי Word המודרניים עוברים את השרשרת המלאה (§98):
/// זיהוי → סריקה → המרה → TOC → אינדוקס.
///
/// זו הבדיקה שמצדיקה את הכנסתם ל-registry: לא נכתב עבורם ממיר חדש, ולכן מה
/// שחייב להיבדק הוא שהניתוב מגיע למנוע הנכון בכל שלב.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ooxmlFormats = ['docx', 'docm', 'dotx', 'dotm'];

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ooxml-pipeline-');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // נעילת קובץ ב-Windows אינה מעניינה של הבדיקה.
    }
  });

  /// מסמך עם כותרות, רשימה, טבלה, הערת שוליים ותמונה — חתך מייצג.
  final document = buildDocx(
    document: documentXml(
      '${styledPara('Heading1', 'פרק ראשון')}'
      '${para('פסקת פתיחה')}'
      '${styledPara('Heading2', 'סימן א')}'
      '${listItem(0, 'פריט ראשון')}'
      '<w:p><w:r><w:t>עם הערה</w:t></w:r>'
      '<w:r><w:footnoteReference w:id="2"/></w:r></w:p>'
      '<w:p>${drawingImage('rId1')}</w:p>'
      '${table([
        [para('תא')],
      ])}',
    ),
    footnotes: footnotesXml({'2': 'גוף ההערה'}),
    rels: relsXml({'rId1': 'media/image1.png'}),
    media: {'image1.png': kTinyPng},
  );

  Future<File> writeAs(String extension) async {
    final file = File(p.join(tempDir.path, 'ספר.$extension'));
    await file.writeAsBytes(document);
    return file;
  }

  for (final extension in ooxmlFormats) {
    group(extension.toUpperCase(), () {
      test('הפורמט פעיל ב-registry ונסרק כספר', () {
        final format = documentFormatFromFileType(extension)!;
        expect(format.isProductionSupported, isTrue);
        expect(format.isOoxmlWord, isTrue);
        expect(isSupportedBookFile('ספר.$extension'), isTrue);
        expect(isSupportedBookFile('ספר.${extension.toUpperCase()}'), isTrue);
      });

      test('fileType נשמר כשלעצמו ואינו ממופה ל-docx', () {
        expect(documentFormatFromFileType(extension)!.extension, extension);
      });

      test('נקרא ומומר לטקסט מלא', () async {
        final file = await writeAs(extension);

        final text = await readFileBackedBookText(file, extension, 'ספר');

        expect(text, isNotNull);
        expect(text, contains('<h1>ספר</h1>'));
        expect(text, contains('<h1>פרק ראשון</h1>'));
        expect(text, contains('<h2>סימן א</h2>'));
        expect(text, contains('פסקת פתיחה'));
        expect(text, contains('גוף ההערה'));
        expect(text, contains('<table'));
        expect(text, contains('data:image/png;base64,'));
      });

      test('תוכן עניינים נבנה מהתוכן המומר', () async {
        final file = await writeAs(extension);
        final format = documentFormatFromFileType(extension)!;

        final content = await convertDocumentForIndex(file, 'ספר', format);
        final toc = TocParser.parseEntriesFromContent(content);

        expect(toc.map((e) => e.text), contains('פרק ראשון'));
        expect(
          toc.expand((e) => e.children).map((e) => e.text),
          contains('סימן א'),
        );
      });

      test('המרת אינדוקס חוסכת base64 ושומרת על אינדקסי השורות', () async {
        final file = await writeAs(extension);
        final format = documentFormatFromFileType(extension)!;

        final forIndex = await convertDocumentForIndex(file, 'ספר', format);
        final forReading = (await readFileBackedBookText(
          file,
          extension,
          'ספר',
        ))!;

        expect(forIndex, isNot(contains('base64')));
        expect(forIndex.split('\n').length, forReading.split('\n').length);
      });

      test('הכותרת מוזרקת מהקטלוג ולא משם הקובץ', () async {
        final file = await writeAs(extension);

        final text = await readFileBackedBookText(
          file,
          extension,
          'שם מהקטלוג',
        );

        expect(text, contains('<h1>שם מהקטלוג</h1>'));
      });

      test('סיומת לבדה מספיקה כש-fileType חסר', () async {
        final file = await writeAs(extension);

        final text = await readFileBackedBookText(file, null, 'ספר');

        expect(text, contains('פסקת פתיחה'));
      });

      test('עריכת הקובץ מייצרת המרה מחדש (תוקף המטמון)', () async {
        final file = await writeAs(extension);
        expect(
          await readFileBackedBookText(file, extension, 'ספר'),
          contains('פסקת פתיחה'),
        );

        await file.writeAsBytes(
          buildDocx(document: documentXml(para('גרסה שנייה'))),
        );

        final updated = await readFileBackedBookText(file, extension, 'ספר');
        expect(updated, contains('גרסה שנייה'));
        expect(updated, isNot(contains('פסקת פתיחה')));
      });
    });
  }

  test('כל ארבעת הפורמטים מפיקים תוכן זהה מאותם בייטים', () async {
    final outputs = <String>{};
    for (final extension in ooxmlFormats) {
      final file = await writeAs(extension);
      outputs.add((await readFileBackedBookText(file, extension, 'ספר'))!);
    }
    expect(outputs, hasLength(1));
  });

  test('WBK שתוכנו OOXML מנותב למנוע Word ונקרא במלואו', () async {
    final file = File(p.join(tempDir.path, 'גיבוי.wbk'));
    await file.writeAsBytes(document);

    expect(
      resolveDocumentFormat(DocumentFormat.wbk, document),
      DocumentFormat.docx,
    );

    // הסיומת wbk אינה מסגירה את המנוע — רק התוכן.
    final text = await readFileBackedBookText(file, 'wbk', 'גיבוי');
    expect(text, contains('פסקת פתיחה'));
    expect(text, contains('<h1>פרק ראשון</h1>'));
  });

  // issue #3320: הערה בכותרת של קובץ אישי נכנסה לתוכן העניינים ולשורת המיקום.
  test('הערת שוליים בכותרת אינה נכנסת לתוכן העניינים (issue #3320)', () async {
    final file = File(p.join(tempDir.path, 'הערה בכותרת.docx'));
    await file.writeAsBytes(
      buildDocx(
        document: documentXml(
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
          '<w:r><w:t>פרק ראשון</w:t></w:r>'
          '<w:r><w:footnoteReference w:id="2"/></w:r></w:p>'
          '${para('פסקת פתיחה')}',
        ),
        footnotes: footnotesXml({'2': 'גוף ההערה'}),
      ),
    );

    final content = await convertDocumentForIndex(
      file,
      'ספר',
      DocumentFormat.docx,
    );
    final toc = TocParser.parseEntriesFromContent(content);

    expect(content, contains('גוף ההערה'));
    expect(toc.map((e) => e.text), ['ספר', 'פרק ראשון']);
  });
}
