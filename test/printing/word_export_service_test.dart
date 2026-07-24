import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:pdf/pdf.dart';

// ─── helpers ─────────────────────────────────────────────────────────────────

String _readArchiveFile(Archive archive, String name) {
  final file = archive.findFile(name);
  expect(file, isNotNull, reason: 'Archive should contain $name');
  return utf8.decode(file!.content as List<int>);
}

Archive _buildArchive(
  List<PrintBlock> blocks, {
  String title = 'ספר בדיקה',
  PdfPageFormat format = PdfPageFormat.a4,
  bool isLandscape = false,
  double pageMargin = 20,
  String? fontFamily,
  double? fontSize,
}) {
  final bytes = WordExportService.createWordDocument(
    title: title,
    blocks: blocks,
    format: format,
    isLandscape: isLandscape,
    pageMargin: pageMargin,
    fontFamily: fontFamily,
    fontSize: fontSize,
  );
  return ZipDecoder().decodeBytes(bytes);
}

void main() {
  // ─── מבנה קובץ ─────────────────────────────────────────────────────────────
  group('WordExportService - מבנה קובץ docx', () {
    test('יוצר חבילת docx עם כל קבצי OpenXML הנדרשים', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'פסקה ראשונה'),
      ]);
      final fileNames = archive.files.map((f) => f.name).toSet();

      expect(fileNames, contains('[Content_Types].xml'));
      expect(fileNames, contains('_rels/.rels'));
      expect(fileNames, contains('word/document.xml'));
      expect(fileNames, contains('word/styles.xml'));
      expect(fileNames, contains('word/numbering.xml'));
      expect(fileNames, contains('word/footnotes.xml'));
      expect(fileNames, contains('word/header1.xml'));
      expect(fileNames, contains('word/footer1.xml'));
      for (final file in archive.files) {
        expect(file.size, greaterThan(0), reason: '${file.name} ריק');
      }
    });

    test('document.xml הוא XML תקני', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'בדיקה'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, startsWith('<?xml version="1.0"'));
      expect(xml, contains('<w:document'));
      expect(xml, contains('<w:body>'));
    });
  });

  // ─── escapeXml ──────────────────────────────────────────────────────────────
  group('WordExportService - XML escaping', () {
    test('& בתוכן מוחלף ב-&amp;', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'ש"ס & תנ"ך'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('&amp;'));
      expect(xml, isNot(contains('ש"ס & תנ"ך')));
    });

    test('< בתוכן מוחלף ב-&lt;', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'a < b'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('&lt;'));
    });

    test('> בתוכן מוחלף ב-&gt;', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'a > b'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('&gt;'));
    });

    test('" בתוכן מוחלף ב-&quot;', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'הוא אמר "שלום"'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('&quot;'));
    });

    test("' בתוכן מוחלף ב-&apos;", () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: "it's fine"),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('&apos;'));
    });

    test('כותרת הספר עם תווים מיוחדים מוחלפת ב-header ובcore', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'x')],
        title: 'ספר <ה"גדול">',
      );
      final header = _readArchiveFile(archive, 'word/header1.xml');
      expect(header, contains('&lt;'));
      expect(header, contains('&gt;'));
      expect(header, contains('&quot;'));
    });

    test('escaping בהערת שוליים', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.text,
          text: 'טקסט',
          footnotes: [PrintFootnote(text: 'הערה עם & תו מיוחד')],
        ),
      ]);
      final footnotes = _readArchiveFile(archive, 'word/footnotes.xml');
      expect(footnotes, contains('&amp;'));
    });
  });

  // ─── רמות כותרת ─────────────────────────────────────────────────────────────
  group('WordExportService - רמות כותרת', () {
    test('headingLevel=1 → Heading1', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.heading,
          text: 'פרק א',
          headingLevel: 1,
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading1"/>'));
    });

    test('headingLevel=2 → Heading2', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.heading, text: 'סעיף', headingLevel: 2),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading2"/>'));
    });

    test('headingLevel=3 → Heading3', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.heading, text: 'פרק', headingLevel: 3),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading3"/>'));
    });

    test('headingLevel=4 → Heading4', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.heading, text: 'פרק', headingLevel: 4),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading4"/>'));
    });

    test('headingLevel=null → Heading1 (ברירת מחדל)', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.heading, text: 'כותרת'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading1"/>'));
    });

    test('headingLevel=0 → נצמד ל-Heading1 (clamp)', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.heading,
          text: 'כותרת',
          headingLevel: 0,
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading1"/>'));
      expect(xml, isNot(contains('<w:pStyle w:val="Heading0"/>')));
    });

    test('headingLevel=5 → נצמד ל-Heading4 (clamp)', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.heading,
          text: 'כותרת',
          headingLevel: 5,
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading4"/>'));
      expect(xml, isNot(contains('<w:pStyle w:val="Heading5"/>')));
    });

    test('headingLevel=-1 → נצמד ל-Heading1 (clamp)', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.heading,
          text: 'כותרת',
          headingLevel: -1,
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading1"/>'));
    });
  });

  // ─── סוגי בלוקים ─────────────────────────────────────────────────────────────
  group('WordExportService - כל סוגי PrintBlockKind', () {
    test('text → BodyRtl עם jc=both', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'גוף'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="BodyRtl"/>'));
      expect(xml, contains('<w:jc w:val="both"/>'));
    });

    test('commentaryTitle → CommentaryHeading', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.commentaryTitle, text: 'מפרשים'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="CommentaryHeading"/>'));
    });

    test('commentaryGroupTitle → CommentarySubheading', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.commentaryGroupTitle, text: 'רש"י'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="CommentarySubheading"/>'));
    });

    test('commentary → CommentaryBody עם jc=both', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.commentary, text: 'פירוש'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="CommentaryBody"/>'));
      expect(xml, contains('<w:jc w:val="both"/>'));
    });
  });

  // ─── בלוקים ריקים ────────────────────────────────────────────────────────────
  group('WordExportService - בלוקים ריקים', () {
    test('בלוק ריק לא קורס', () {
      expect(
        () => _buildArchive(const [
          PrintBlock(kind: PrintBlockKind.text, text: ''),
        ]),
        returnsNormally,
      );
    });

    test('בלוק ריק יוצר פסקה ריקה (BodyRtl)', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: ''),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="BodyRtl"/>'));
    });

    test('בלוק עם רווחים בלבד → מטופל כריק', () {
      expect(
        () => _buildArchive(const [
          PrintBlock(kind: PrintBlockKind.text, text: '   \t  '),
        ]),
        returnsNormally,
      );
    });

    test('רשימת בלוקים ריקה לא קורסת', () {
      expect(() => _buildArchive(const []), returnsNormally);
    });
  });

  // ─── הערות שוליים ────────────────────────────────────────────────────────────
  group('WordExportService - הערות שוליים', () {
    test('הערת שוליים אחת → id=2', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.text,
          text: 'טקסט',
          footnotes: [PrintFootnote(text: 'הערה ראשונה')],
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:footnoteReference w:id="2"/>'));
    });

    test('שתי הערות שוליים → id=2 ו-id=3', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.text,
          text: 'פסקה ראשונה',
          footnotes: [PrintFootnote(text: 'הערה 1')],
        ),
        PrintBlock(
          kind: PrintBlockKind.text,
          text: 'פסקה שנייה',
          footnotes: [PrintFootnote(text: 'הערה 2')],
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:footnoteReference w:id="2"/>'));
      expect(xml, contains('<w:footnoteReference w:id="3"/>'));
    });

    test('שלוש הערות שוליים → id=2,3,4', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.text,
          text: 'טקסט',
          footnotes: [
            PrintFootnote(text: 'א'),
            PrintFootnote(text: 'ב'),
            PrintFootnote(text: 'ג'),
          ],
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('w:id="2"'));
      expect(xml, contains('w:id="3"'));
      expect(xml, contains('w:id="4"'));
    });

    test('תוכן הערת שוליים מופיע ב-footnotes.xml', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.text,
          text: 'טקסט',
          footnotes: [PrintFootnote(text: 'הערת שוליים מיוחדת')],
        ),
      ]);
      final footnotes = _readArchiveFile(archive, 'word/footnotes.xml');
      expect(footnotes, contains('הערת שוליים מיוחדת'));
    });

    test(
      'ללא הערות שוליים → footnotes.xml מכיל רק separator ו-continuationSeparator',
      () {
        final archive = _buildArchive(const [
          PrintBlock(kind: PrintBlockKind.text, text: 'טקסט'),
        ]);
        final footnotes = _readArchiveFile(archive, 'word/footnotes.xml');
        expect(footnotes, contains('w:type="separator"'));
        expect(footnotes, contains('w:type="continuationSeparator"'));
        expect(footnotes, isNot(contains('w:id="2"')));
      },
    );
  });

  // ─── כיוון הדפסה ─────────────────────────────────────────────────────────────
  group('WordExportService - כיוון הדפסה', () {
    test('isLandscape=true → orient="landscape" ב-document.xml', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'טקסט')],
        isLandscape: true,
      );
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('w:orient="landscape"'));
    });

    test('isLandscape=false → אין orient="landscape"', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'טקסט')],
        isLandscape: false,
      );
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, isNot(contains('w:orient="landscape"')));
    });
  });

  // ─── פורמטים שונים ───────────────────────────────────────────────────────────
  group('WordExportService - פורמטים שונים', () {
    test('A4 portrait לא קורס', () {
      expect(
        () => _buildArchive(
          const [PrintBlock(kind: PrintBlockKind.text, text: 'x')],
          format: PdfPageFormat.a4,
          isLandscape: false,
        ),
        returnsNormally,
      );
    });

    test('A4 landscape לא קורס', () {
      expect(
        () => _buildArchive(
          const [PrintBlock(kind: PrintBlockKind.text, text: 'x')],
          format: PdfPageFormat.a4,
          isLandscape: true,
        ),
        returnsNormally,
      );
    });

    test('Letter לא קורס', () {
      expect(
        () => _buildArchive(
          const [PrintBlock(kind: PrintBlockKind.text, text: 'x')],
          format: PdfPageFormat.letter,
        ),
        returnsNormally,
      );
    });

    test('A3 לא קורס', () {
      expect(
        () => _buildArchive(
          const [PrintBlock(kind: PrintBlockKind.text, text: 'x')],
          format: PdfPageFormat.a3,
        ),
        returnsNormally,
      );
    });

    test('A4 landscape הופך רוחב וגובה', () {
      final portraitArchive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'x')],
        format: PdfPageFormat.a4,
        isLandscape: false,
      );
      final landscapeArchive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'x')],
        format: PdfPageFormat.a4,
        isLandscape: true,
      );
      final portraitXml = _readArchiveFile(
        portraitArchive,
        'word/document.xml',
      );
      final landscapeXml = _readArchiveFile(
        landscapeArchive,
        'word/document.xml',
      );
      // גדלי הדף ב-twips צריכים להיות שונים
      expect(portraitXml, isNot(equals(landscapeXml)));
    });
  });

  // ─── RTL ─────────────────────────────────────────────────────────────────────
  group('WordExportService - תמיכת RTL', () {
    test('document.xml מכיל bidi ו-rtl', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'עברית'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:bidi/>'));
      expect(xml, contains('<w:rtl/>'));
    });

    test('styles.xml מכיל הגדרות bidi', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'עברית'),
      ]);
      final styles = _readArchiveFile(archive, 'word/styles.xml');
      expect(styles, contains('w:bidi'));
      expect(styles, contains('he-IL'));
    });

    test('footer מכיל NUMPAGES', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'טקסט'),
      ]);
      final footer = _readArchiveFile(archive, 'word/footer1.xml');
      expect(footer, contains('NUMPAGES'));
    });
  });

  // ─── כותרת מסמך ──────────────────────────────────────────────────────────────
  group('WordExportService - כותרת מסמך', () {
    test('כותרת מופיעה ב-document.xml', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'גוף')],
        title: 'שולחן ערוך',
      );
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('שולחן ערוך'));
      expect(xml, contains('<w:pStyle w:val="Title"/>'));
    });

    test('כותרת מופיעה ב-header', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'גוף')],
        title: 'גמרא בבא קמא',
      );
      final header = _readArchiveFile(archive, 'word/header1.xml');
      expect(header, contains('גמרא בבא קמא'));
    });

    test('כותרת מופיעה ב-core.xml', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'גוף')],
        title: 'רמב"ם',
      );
      final core = _readArchiveFile(archive, 'docProps/core.xml');
      expect(core, contains('רמב&quot;ם'));
    });
  });

  // ─── טקסט רב-שורתי ───────────────────────────────────────────────────────────
  group('WordExportService - טקסט רב-שורתי', () {
    test('שבירת שורה מייצרת w:br', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'שורה ראשונה\nשורה שנייה'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:br/>'));
    });

    test('שורות מרובות לא קורסות', () {
      expect(
        () => _buildArchive(const [
          PrintBlock(
            kind: PrintBlockKind.text,
            text: 'א\nב\nג\nד\nה\nו\nז\nח\nט\nי',
          ),
        ]),
        returnsNormally,
      );
    });
  });

  // ─── מסמך מורכב ──────────────────────────────────────────────────────────────
  group('WordExportService - מסמך מורכב', () {
    test('כל סוגי הבלוקים בו-זמנית לא קורסים', () {
      expect(
        () => _buildArchive(const [
          PrintBlock(
            kind: PrintBlockKind.heading,
            text: 'פרק א',
            headingLevel: 1,
          ),
          PrintBlock(kind: PrintBlockKind.text, text: 'גוף'),
          PrintBlock(kind: PrintBlockKind.commentaryTitle, text: 'מפרשים'),
          PrintBlock(kind: PrintBlockKind.commentaryGroupTitle, text: 'רש"י'),
          PrintBlock(kind: PrintBlockKind.commentary, text: 'פירוש'),
        ]),
        returnsNormally,
      );
    });

    test('מסמך עם מאה בלוקים לא קורס', () {
      final blocks = List.generate(
        100,
        (i) => PrintBlock(kind: PrintBlockKind.text, text: 'פסקה $i'),
      );
      expect(() => _buildArchive(blocks), returnsNormally);
    });
  });

  // ─── עיצוב פנים-שורתי מ-HTML ─────────────────────────────────────────────────
  group('WordExportService - עיצוב פנים-שורתי מ-HTML', () {
    test('<b> → run מודגש, והתגית לא מודלפת לפלט', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'טקסט <b>מודגש</b> רגיל'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:b/><w:bCs/>'));
      expect(xml, contains('מודגש'));
      expect(xml, isNot(contains('&lt;b&gt;')));
    });

    test('טקסט מחוץ ל-<b> לא מקבל הדגשה', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'רגיל <b>מודגש</b>'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      final plainRun = RegExp(
        '<w:r><w:rPr><w:rtl/></w:rPr>'
        '<w:t xml:space="preserve">רגיל </w:t></w:r>',
      );
      expect(xml, matches(plainRun));
    });

    test('<strong> ו-<em> ממופים למודגש ונטוי', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.text,
          text: '<strong>חזק</strong> <em>נטוי</em>',
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:b/><w:bCs/>'));
      expect(xml, contains('<w:i/><w:iCs/>'));
    });

    test('<sup> → superscript', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'טקסט<sup>1</sup>'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:vertAlign w:val="superscript"/>'));
    });

    test('<u> → קו תחתון', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: '<u>מסומן</u>'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:u w:val="single"/>'));
    });

    test('<small> מקטין ו-<big> מגדיל יחסית לגודל הבסיס', () {
      final archive = _buildArchive(
        const [
          PrintBlock(
            kind: PrintBlockKind.text,
            text: '<small>קטן</small> <big>גדול</big>',
          ),
        ],
        fontSize: 10,
      );
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:sz w:val="16"/>')); // 10*0.8=8pt
      expect(xml, contains('<w:sz w:val="24"/>')); // 10*1.2=12pt
    });

    test('עיצוב מקונן: <b><i> → run עם שניהם', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: '<b><i>שניהם</i></b>'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:b/><w:bCs/><w:i/><w:iCs/>'));
    });

    test('תגית לא מוכרת מוסרת אך התוכן נשמר', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.text,
          text: '<span class="x">תוכן פנימי</span>',
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('תוכן פנימי'));
      expect(xml, isNot(contains('span')));
    });

    test('<br> מייצר w:br', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'שורה<br>שורה נוספת'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:br/>'));
    });

    test('ישות &nbsp; מפוענחת ולא מודלפת', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'מילה&nbsp;מילה'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, isNot(contains('nbsp')));
    });

    test('עיצוב פנים-שורתי בבלוק מפרש', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.commentary,
          text: '<b>ד"ה</b> פירוש',
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:b/><w:bCs/>'));
      expect(xml, contains('<w:pStyle w:val="CommentaryBody"/>'));
    });
  });

  // ─── זיהוי כותרות מתגיות HTML ────────────────────────────────────────────────
  group('WordExportService - זיהוי כותרות מ-HTML', () {
    test('בלוק text עטוף <h2> → Heading2 בלי התגית', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: '<h2>פרק שני</h2>'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading2"/>'));
      expect(xml, contains('פרק שני'));
    });

    test('<h6> נצמד ל-Heading4', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: '<h6>תת-סעיף</h6>'),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, contains('<w:pStyle w:val="Heading4"/>'));
    });

    test('שורה עם <h2> באמצע הטקסט אינה הופכת לכותרת', () {
      final archive = _buildArchive(const [
        PrintBlock(
          kind: PrintBlockKind.text,
          text: 'לפני <h2>כותרת</h2> אחרי',
        ),
      ]);
      final xml = _readArchiveFile(archive, 'word/document.xml');
      expect(xml, isNot(contains('<w:pStyle w:val="Heading2"/>')));
    });
  });

  // ─── גופן וגודל מותאמים ──────────────────────────────────────────────────────
  group('WordExportService - גופן וגודל מותאמים', () {
    test('ללא פרמטרים → Times New Roman וגודל 13 (תאימות לאחור)', () {
      final archive = _buildArchive(const [
        PrintBlock(kind: PrintBlockKind.text, text: 'טקסט'),
      ]);
      final styles = _readArchiveFile(archive, 'word/styles.xml');
      expect(styles, contains('Times New Roman'));
      expect(styles, contains('<w:sz w:val="26"/>'));
    });

    test('מזהה משפחה באפליקציה ממופה לשם הגופן במערכת', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'טקסט')],
        fontFamily: 'FrankRuhlCLM',
      );
      final styles = _readArchiveFile(archive, 'word/styles.xml');
      expect(styles, contains('Frank Ruehl CLM'));
      expect(styles, isNot(contains('Times New Roman')));
    });

    test('גופן שאינו במיפוי מועבר כמות שהוא', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'טקסט')],
        fontFamily: 'David',
      );
      final styles = _readArchiveFile(archive, 'word/styles.xml');
      expect(styles, contains('w:cs="David"'));
    });

    test('fontSize משנה את גודל הבסיס והכותרות נגזרות ממנו', () {
      final archive = _buildArchive(
        const [PrintBlock(kind: PrintBlockKind.text, text: 'טקסט')],
        fontSize: 15,
      );
      final styles = _readArchiveFile(archive, 'word/styles.xml');
      expect(styles, contains('<w:sz w:val="30"/>')); // Normal 15pt
      expect(styles, contains('<w:sz w:val="34"/>')); // H1 = base+2
    });
  });
}
