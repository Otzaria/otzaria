import 'dart:convert';
import 'dart:typed_data';

import '../../../tool/src/document_fixtures/ooxml_builder.dart';

/// Fixtures ל-golden regression של ממיר ה-Word (§23).
///
/// כל תרחיש נבנה כאן כ-DOCX מלא בזיכרון, כדי שהבדיקות לא יידרשו לקבצים
/// בינאריים בריפו וכדי שאפשר יהיה להריץ את *אותם* מסמכים גם דרך DOCM/DOTX
/// ולוודא פלט סמנטי זהה (§82).
const String kW =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
const String kR =
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
const String kA =
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
const String kWp =
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"';
const String kV = 'xmlns:v="urn:schemas-microsoft-com:vml"';
const String kMc =
    'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"';
const String kWps =
    'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"';

const String _allNs = '$kW $kR $kA $kWp $kV $kMc $kWps';

/// PNG 1x1 שקוף — התוכן הקטן ביותר ש-`imageMimeForPath` מזהה כתמונה.
final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// עוטף גוף מסמך ב-`w:document` עם כל מרחבי-השמות שהתרחישים משתמשים בהם.
String documentXml(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_allNs><w:body>$body</w:body></w:document>';

/// פסקה פשוטה עם run אחד.
String para(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

/// פסקה עם סגנון.
String styledPara(String styleId, String text) =>
    '<w:p><w:pPr><w:pStyle w:val="$styleId"/></w:pPr>'
    '<w:r><w:t>$text</w:t></w:r></w:p>';

/// פריט רשימה ממוספרת.
String listItem(int ilvl, String text, {String numId = '1'}) =>
    '<w:p><w:pPr><w:numPr><w:ilvl w:val="$ilvl"/>'
    '<w:numId w:val="$numId"/></w:numPr></w:pPr>'
    '<w:r><w:t>$text</w:t></w:r></w:p>';

/// styles.xml עם רשימת הגדרות סגנון גולמיות.
String stylesXml(String styles) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles $kW>$styles</w:styles>';

/// הגדרת סגנון פסקה בודדת.
String styleDef(
  String id, {
  String? name,
  String? basedOn,
  String? outlineLvl,
  String type = 'paragraph',
}) {
  final buffer = StringBuffer('<w:style w:type="$type" w:styleId="$id">');
  if (name != null) buffer.write('<w:name w:val="$name"/>');
  if (basedOn != null) buffer.write('<w:basedOn w:val="$basedOn"/>');
  if (outlineLvl != null) {
    buffer.write('<w:pPr><w:outlineLvl w:val="$outlineLvl"/></w:pPr>');
  }
  buffer.write('</w:style>');
  return buffer.toString();
}

/// numbering.xml עם רמות `[numFmt, lvlText]` תחת numId=1.
String numberingXml(List<List<String>> levels, {String start = '1'}) {
  final lvls = <String>[];
  for (var i = 0; i < levels.length; i++) {
    lvls.add(
      '<w:lvl w:ilvl="$i"><w:start w:val="$start"/>'
      '<w:numFmt w:val="${levels[i][0]}"/>'
      '<w:lvlText w:val="${levels[i][1]}"/></w:lvl>',
    );
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:numbering $kW><w:abstractNum w:abstractNumId="0">'
      '${lvls.join()}</w:abstractNum>'
      '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
      '</w:numbering>';
}

/// footnotes.xml עם מיפוי id → טקסט.
String footnotesXml(Map<String, String> notes) {
  final entries = notes.entries
      .map(
        (e) =>
            '<w:footnote w:id="${e.key}"><w:p><w:r><w:t>${e.value}</w:t>'
            '</w:r></w:p></w:footnote>',
      )
      .join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:footnotes $kW>$entries</w:footnotes>';
}

/// document.xml.rels הממפה rId → קובץ מדיה.
String relsXml(Map<String, String> targets) {
  final entries = targets.entries
      .map(
        (e) =>
            '<Relationship Id="${e.key}" Target="${e.value}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            'relationships/image"/>',
      )
      .join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">$entries</Relationships>';
}

/// document.xml.rels הממפה rId → יעד קישור חיצוני (`w:hyperlink r:id`).
String hyperlinkRelsXml(Map<String, String> targets) {
  final entries = targets.entries
      .map(
        (e) =>
            '<Relationship Id="${e.key}" Target="${e.value}" '
            'TargetMode="External" Type="http://schemas.openxmlformats.org/'
            'officeDocument/2006/relationships/hyperlink"/>',
      )
      .join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
      'relationships">$entries</Relationships>';
}

/// פסקה עם קישור חיצוני (`r:id`) עוטף run יחיד.
String hyperlinkExternal(String relId, String text) =>
    '<w:p><w:hyperlink r:id="$relId"><w:r><w:t>$text</w:t></w:r>'
    '</w:hyperlink></w:p>';

/// פסקה עם קישור פנימי (`w:anchor`) עוטף run יחיד.
String hyperlinkInternal(String anchor, String text) =>
    '<w:p><w:hyperlink w:anchor="$anchor"><w:r><w:t>$text</w:t></w:r>'
    '</w:hyperlink></w:p>';

/// כותרת עם סימניה (`w:bookmarkStart`/`w:bookmarkEnd`) — היעד של קישור פנימי,
/// בדיוק כפי שתוכן-עניינים אוטומטי של Word ("Insert TOC") בונה.
String headingWithBookmark(String styleId, String anchor, String text) =>
    '<w:p><w:pPr><w:pStyle w:val="$styleId"/></w:pPr>'
    '<w:bookmarkStart w:id="1" w:name="$anchor"/>'
    '<w:r><w:t>$text</w:t></w:r>'
    '<w:bookmarkEnd w:id="1"/></w:p>';

/// גרפיקת DrawingML inline המפנה ל-[relId].
String drawingImage(String relId) =>
    '<w:r><w:drawing><wp:inline><a:graphic><a:graphicData>'
    '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/'
    'picture"><pic:blipFill><a:blip r:embed="$relId"/></pic:blipFill></pic:pic>'
    '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

/// גרפיקת VML ישנה (`v:imagedata`) המפנה ל-[relId].
String vmlImage(String relId) =>
    '<w:r><w:pict><v:shape><v:imagedata r:id="$relId"/></v:shape></w:pict>'
    '</w:r>';

/// תיבת-טקסט. [backgroundRelId] מוסיף תמונת-רקע לשייפ,
/// ו-[behindDoc] הופך אותה למסגרת דקורטיבית שמאחורי הטקסט.
String textBox(
  String innerXml, {
  String? backgroundRelId,
  bool behindDoc = false,
}) {
  final background = backgroundRelId == null
      ? ''
      : '<a:graphic><a:graphicData><pic:pic xmlns:pic="http://schemas.'
            'openxmlformats.org/drawingml/2006/picture"><pic:blipFill>'
            '<a:blip r:embed="$backgroundRelId"/></pic:blipFill></pic:pic>'
            '</a:graphicData></a:graphic>';
  final body =
      '<wps:wsp><wps:txbx><w:txbxContent>$innerXml</w:txbxContent></wps:txbx>'
      '</wps:wsp>$background';
  final wrapper = behindDoc
      ? '<wp:anchor behindDoc="1">$body</wp:anchor>'
      : '<wp:inline>$body</wp:inline>';
  return '<w:r><w:drawing>$wrapper</w:drawing></w:r>';
}

/// תמונה צפה מאחורי הטקסט (סימן-מים) — ללא טקסט בתיבה.
String behindDocImage(String relId) =>
    '<w:r><w:drawing><wp:anchor behindDoc="1"><a:graphic><a:graphicData>'
    '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/'
    'picture"><pic:blipFill><a:blip r:embed="$relId"/></pic:blipFill></pic:pic>'
    '</a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>';

/// טבלה מתאים גולמיים (כל שורה = רשימת XML של תאים).
String table(List<List<String>> rows) {
  final xml = rows
      .map(
        (row) =>
            '<w:tr>${row.map((cell) => '<w:tc>$cell</w:tc>').join()}'
            '</w:tr>',
      )
      .join();
  return '<w:tbl>$xml</w:tbl>';
}

/// בונה קובץ DOCX שלם. עוטף את הבונה המשותף כדי לשמר את שם ה-API שהבדיקות
/// כבר משתמשות בו.
Uint8List buildDocx({
  required String document,
  String? styles,
  String? numbering,
  String? footnotes,
  String? rels,
  Map<String, Uint8List> media = const {},
}) => buildOoxmlPackage(
  document: document,
  styles: styles,
  numbering: numbering,
  footnotes: footnotes,
  rels: rels,
  media: media,
);

/// data URI של [kTinyPng] — הפלט הצפוי לכל תרחיש תמונה.
final String kTinyPngDataUri =
    'data:image/png;base64,${base64Encode(kTinyPng)}';

/// כל תרחישי §23, שם → בייטים של DOCX.
///
/// המפה משמשת גם את בדיקות ה-cross-format (§82): אותם בייטים נטענים כ-DOCM /
/// DOTX / DOTM ומצופים לייצר פלט זהה.
Map<String, Uint8List> buildGoldenScenarios() {
  final media = {'image1.png': kTinyPng};
  final rels = relsXml({'rId1': 'media/image1.png'});

  return {
    'plain text': buildDocx(
      document: documentXml('${para('שורה ראשונה')}${para('שורה שנייה')}'),
    ),

    'headings': buildDocx(
      document: documentXml(
        '${styledPara('Heading1', 'פרק א')}'
        '${styledPara('Heading2', 'סימן ב')}'
        '${para('גוף')}',
      ),
    ),

    'basedOn heading': buildDocx(
      document: documentXml(styledPara('5', 'כותרת יורשת')),
      styles: stylesXml(
        '${styleDef('2', name: 'heading 2')}'
        '${styleDef('5', name: 'סגנון שלי', basedOn: '2')}',
      ),
    ),

    'basedOn cycle': buildDocx(
      document: documentXml(styledPara('a', 'מעגל')),
      styles: stylesXml(
        '${styleDef('a', name: 'alpha', basedOn: 'b')}'
        '${styleDef('b', name: 'beta', basedOn: 'a')}',
      ),
    ),

    'outlineLvl=9': buildDocx(
      document: documentXml(styledPara('BodyText', 'גוף ולא כותרת')),
      styles: stylesXml(
        styleDef('BodyText', name: 'heading 1', outlineLvl: '9'),
      ),
    ),

    'numbered list': buildDocx(
      document: documentXml(
        '${listItem(0, 'ראשון')}${listItem(0, 'שני')}${listItem(0, 'שלישי')}',
      ),
      numbering: numberingXml([
        ['decimal', '%1.'],
      ]),
    ),

    'multilevel list': buildDocx(
      document: documentXml(
        '${listItem(0, 'א')}${listItem(1, 'ב')}'
        '${listItem(2, 'ג')}${listItem(1, 'ד')}',
      ),
      numbering: numberingXml([
        ['decimal', '%1.'],
        ['decimal', '%1.%2.'],
        ['decimal', '%1.%2.%3.'],
      ]),
    ),

    'Hebrew numbering': buildDocx(
      document: documentXml(
        '${listItem(0, 'אלף')}${listItem(0, 'בית')}${listItem(0, 'גימל')}',
      ),
      numbering: numberingXml([
        ['hebrew1', '%1.'],
      ]),
    ),

    'footnote': buildDocx(
      document: documentXml(
        '<w:p><w:r><w:t>טקסט עם הערה</w:t></w:r>'
        '<w:r><w:footnoteReference w:id="2"/></w:r></w:p>',
      ),
      footnotes: footnotesXml({'2': 'גוף ההערה'}),
    ),

    'table': buildDocx(
      document: documentXml(
        table([
          [para('א1'), para('ב1')],
          [para('א2'), para('ב2')],
        ]),
      ),
    ),

    'nested table': buildDocx(
      document: documentXml(
        table([
          [
            para('חיצוני') +
                table([
                  [para('פנימי')],
                ]),
          ],
        ]),
      ),
    ),

    'DrawingML image': buildDocx(
      document: documentXml('<w:p>${drawingImage('rId1')}</w:p>'),
      rels: rels,
      media: media,
    ),

    'VML image': buildDocx(
      document: documentXml('<w:p>${vmlImage('rId1')}</w:p>'),
      rels: rels,
      media: media,
    ),

    'text box': buildDocx(
      document: documentXml('<w:p>${textBox(para('בתוך התיבה'))}</w:p>'),
    ),

    'text box + background image': buildDocx(
      document: documentXml(
        '<w:p>${textBox(para('על הרקע'), backgroundRelId: 'rId1')}</w:p>',
      ),
      rels: rels,
      media: media,
    ),

    'behindDoc': buildDocx(
      document: documentXml(
        '<w:p>${behindDocImage('rId1')}</w:p>${para('טקסט אחרי הסימן')}',
      ),
      rels: rels,
      media: media,
    ),

    'w:sdt': buildDocx(
      document: documentXml(
        '<w:sdt><w:sdtContent>${para('בתוך בקרת תוכן')}'
        '${table([
          [para('תא בבקרה')],
        ])}</w:sdtContent></w:sdt>',
      ),
    ),

    'hyperlink external': buildDocx(
      document: documentXml(hyperlinkExternal('rId2', 'לאתר')),
      rels: hyperlinkRelsXml({'rId2': 'https://otzaria.org'}),
    ),

    'hyperlink internal': buildDocx(
      document: documentXml(
        '${headingWithBookmark('Heading1', '_Toc1', 'כותרת יעד')}'
        '${hyperlinkInternal('_Toc1', 'לכותרת')}',
      ),
    ),
  };
}
