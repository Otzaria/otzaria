import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';

/// בנצ'מרק ביצועים *וזיכרון* ל-docxToText על היקף של "אלפי דפים".
///
/// אינו טסט תקינות — מודד זמן, תפוקה וצריכת זיכרון (RSS) ומדפיס דו"ח.
/// מסומן `skip` כדי לא להאט את החבילה הרגילה. להרצה ידנית:
///   flutter test test/utils/file/docx_to_otzaria_benchmark.dart --run-skipped
///
/// אומדן היקף: דף ≈ 30 שורות, כך ש-30,000 פסקאות ≈ ~1,000 עמודים.
void main() {
  const ns =
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
  const imgNs =
      '$ns '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';

  // פסקת גוף "רגילה": 4 runs, עיצוב פשוט.
  String simplePara(int i) =>
      '<w:p><w:pPr><w:jc w:val="both"/></w:pPr>'
      '<w:r><w:rPr><w:bCs/></w:rPr><w:t>מילה מודגשת </w:t></w:r>'
      '<w:r><w:rPr><w:iCs/></w:rPr><w:t>ונטויה </w:t></w:r>'
      '<w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>וקו תחתי </w:t></w:r>'
      '<w:r><w:t>וטקסט רגיל בשורה זו לבדיקת אורך פסקה סביר. </w:t></w:r></w:p>';

  // פסקת גוף "מורכבת": ~16 runs, כל אחד עם 2–3 שכבות עיצוב מקוננות + צבע.
  String complexPara(int i) {
    final b = StringBuffer('<w:p><w:pPr><w:jc w:val="both"/></w:pPr>');
    for (var k = 0; k < 16; k++) {
      b.write(
        '<w:r><w:rPr><w:bCs/><w:iCs/>'
        '<w:u w:val="wave" w:color="FF0000"/>'
        '<w:color w:val="1F3B6D"/><w:vertAlign w:val="superscript"/>'
        '<w:highlight w:val="yellow"/></w:rPr>'
        '<w:t>מקטע$k </w:t></w:r>',
      );
    }
    b.write('</w:p>');
    return b.toString();
  }

  // פסקת "עשירה": רשימה ממוספרת מקוננת + טבלה 2x3 מדי 5 פסקאות.
  String richPara(int i) {
    final lvl = i % 3;
    final item =
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="$lvl"/>'
        '<w:numId w:val="1"/></w:numPr></w:pPr>'
        '<w:r><w:t>פריט רשימה ברמה $lvl בפסקה $i</w:t></w:r></w:p>';
    if (i % 5 != 0) return item;
    final cells = StringBuffer();
    for (var r = 0; r < 2; r++) {
      cells.write('<w:tr>');
      for (var c = 0; c < 3; c++) {
        cells.write(
          '<w:tc><w:tcPr><w:shd w:fill="EEEEEE"/></w:tcPr>'
          '<w:p><w:r><w:t>תא $r,$c</w:t></w:r></w:p></w:tc>',
        );
      }
      cells.write('</w:tr>');
    }
    return '$item<w:tbl><w:tblPr><w:bidiVisual/></w:tblPr>$cells</w:tbl>';
  }

  String numberingXml() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:numbering $ns><w:abstractNum w:abstractNumId="0">'
      '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>'
      '<w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="hebrew1"/><w:lvlText w:val="%2."/></w:lvl>'
      '<w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="lowerRoman"/><w:lvlText w:val="%3."/></w:lvl>'
      '</w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
      '</w:numbering>';

  Uint8List buildDocx(int paragraphs, {required String mode}) {
    final useImgNs = mode == 'images';
    final doc = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<w:document ${useImgNs ? imgNs : ns}><w:body>');

    for (var i = 0; i < paragraphs; i++) {
      if (i % 30 == 0) {
        doc.write(
          '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
          '<w:r><w:t>פרק מספר $i</w:t></w:r></w:p>',
        );
        continue;
      }
      switch (mode) {
        case 'simple':
          doc.write(simplePara(i));
        case 'complex':
          doc.write(complexPara(i));
        case 'rich':
          doc.write(richPara(i));
        case 'images':
          doc.write(simplePara(i));
          if (i % 20 == 0) {
            doc.write(
              '<w:p><w:r><w:drawing>'
              '<a:blip r:embed="rId1"/></w:drawing></w:r></w:p>',
            );
          }
      }
    }
    doc.write('</w:body></w:document>');

    final archive = Archive();
    final docBytes = utf8.encode(doc.toString());
    archive.addFile(
      ArchiveFile('word/document.xml', docBytes.length, docBytes),
    );

    if (mode == 'rich') {
      final n = utf8.encode(numberingXml());
      archive.addFile(ArchiveFile('word/numbering.xml', n.length, n));
    }
    if (mode == 'images') {
      // תמונת PNG אחת (~3KB) משותפת לכל ההפניות.
      final png = List<int>.generate(3000, (k) => k % 256);
      final rels = utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/i.png"/></Relationships>',
      );
      archive.addFile(
        ArchiveFile('word/_rels/document.xml.rels', rels.length, rels),
      );
      archive.addFile(ArchiveFile('word/media/i.png', png.length, png));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  int mb(int bytes) => (bytes / (1024 * 1024)).round();

  void runCase(int paragraphs, String mode) {
    final xmlBytes = buildDocx(paragraphs, mode: mode);
    final rssBefore = ProcessInfo.currentRss;
    final sw = Stopwatch()..start();
    final out = docxToText(xmlBytes, 'בנצ\'מרק');
    sw.stop();
    final rssAfter = ProcessInfo.currentRss;
    // ignore: avoid_print
    print(
      '━━ ${mode.padRight(8)}| פסקאות=$paragraphs '
      '(~${(paragraphs / 30).round()} עמ\') '
      '| המרה=${sw.elapsedMilliseconds}ms '
      '| פלט=${mb(out.length * 2)}MB '
      '| RSS Δ=${mb(rssAfter - rssBefore)}MB '
      '| RSS peak=${mb(ProcessInfo.maxRss)}MB',
    );
    expect(out, contains('<h1>'));
  }

  group('docxToText benchmark', () {
    test(
      'זמן + זיכרון: כל סוגי התוכן, עד ~2000 עמ\'',
      () {
        // ignore: avoid_print
        print('\n=== ביצועים (debug/JIT, isolate) — פלט/RSS ב-MB ===');
        runCase(30000, 'simple'); // ~1000 עמ' טקסט רגיל
        runCase(60000, 'simple'); // ~2000 עמ'
        runCase(30000, 'rich'); // ~1000 עמ' רשימות+טבלאות
        runCase(30000, 'images'); // ~1000 עמ' עם תמונות מוטמעות
        runCase(30000, 'complex'); // ~1000 עמ' עיצוב כבד
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }, skip: 'בנצ\'מרק ידני — הרץ עם --run-skipped');
}
