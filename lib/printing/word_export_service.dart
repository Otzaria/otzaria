import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:pdf/pdf.dart';

class WordExportService {
  static Uint8List createWordDocument({
    required String title,
    required List<PrintBlock> blocks,
    required PdfPageFormat format,
    required bool isLandscape,
    required double pageMargin,
  }) {
    ArchiveFile xmlFile(String path, String content) {
      final bytes = utf8.encode(content);
      return ArchiveFile(path, bytes.length, bytes);
    }

    final footnotes = <_WordFootnote>[];

    final archive = Archive()
      ..addFile(xmlFile('[Content_Types].xml', _contentTypesXml))
      ..addFile(xmlFile('_rels/.rels', _rootRelsXml))
      ..addFile(xmlFile('docProps/app.xml', _appXml))
      ..addFile(xmlFile('docProps/core.xml', _buildCoreXml(title)))
      ..addFile(
        xmlFile(
          'word/document.xml',
          _buildDocumentXml(
            title: title,
            blocks: blocks,
            footnotes: footnotes,
            format: format,
            isLandscape: isLandscape,
            pageMargin: pageMargin,
          ),
        ),
      )
      ..addFile(xmlFile('word/styles.xml', _stylesXml))
      ..addFile(xmlFile('word/numbering.xml', _numberingXml))
      ..addFile(xmlFile('word/footnotes.xml', _buildFootnotesXml(footnotes)))
      ..addFile(xmlFile('word/header1.xml', _buildHeaderXml(title)))
      ..addFile(xmlFile('word/footer1.xml', _footerXml))
      ..addFile(xmlFile('word/_rels/document.xml.rels', _documentRelsXml));

    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes);
  }

  static String _buildDocumentXml({
    required String title,
    required List<PrintBlock> blocks,
    required List<_WordFootnote> footnotes,
    required PdfPageFormat format,
    required bool isLandscape,
    required double pageMargin,
  }) {
    final pageWidth = isLandscape ? format.height : format.width;
    final pageHeight = isLandscape ? format.width : format.height;
    final widthTwips = (pageWidth * 20).round();
    final heightTwips = (pageHeight * 20).round();
    final marginTwips = (pageMargin * 20).round();
    final orient = isLandscape ? ' w:orient="landscape"' : '';

    final body = StringBuffer()
      ..write(_paragraphXml(title, 'Title'))
      ..write(_paragraphXml('', 'BodyRtl'));

    for (final block in blocks) {
      body.write(_paragraphForBlock(block, footnotes));
    }

    body.write('''
<w:sectPr>
  <w:headerReference w:type="default" r:id="rId2"/>
  <w:footerReference w:type="default" r:id="rId3"/>
  <w:pgSz w:w="$widthTwips" w:h="$heightTwips"$orient/>
  <w:pgMar w:top="$marginTwips" w:right="$marginTwips" w:bottom="$marginTwips" w:left="$marginTwips" w:header="720" w:footer="720" w:gutter="0"/>
  <w:bidi/>
</w:sectPr>''');

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
 xmlns:v="urn:schemas-microsoft-com:vml"
 xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:w10="urn:schemas-microsoft-com:office:word"
 xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
 xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
 xmlns:wpi="http://schemas.microsoft.com/office/word/2010/wordprocessingInk"
 xmlns:wne="http://schemas.microsoft.com/office/2006/wordml"
 xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
 mc:Ignorable="w14 wp14">
  <w:body>
    ${body.toString()}
  </w:body>
</w:document>''';
  }

  static String _paragraphForBlock(
    PrintBlock block,
    List<_WordFootnote> footnotes,
  ) {
    final text = block.text.trimRight();
    if (text.isEmpty) {
      return _paragraphXml('', 'BodyRtl');
    }

    switch (block.kind) {
      case PrintBlockKind.heading:
        final level = (block.headingLevel ?? 1).clamp(1, 4);
        return _paragraphXml(
          text,
          'Heading$level',
          footnotes: block.footnotes,
          registry: footnotes,
        );
      case PrintBlockKind.text:
        return _paragraphXml(
          text,
          'BodyRtl',
          footnotes: block.footnotes,
          registry: footnotes,
        );
      case PrintBlockKind.commentaryTitle:
        return _paragraphXml(_rtlPrefix(text), 'CommentaryHeading');
      case PrintBlockKind.commentaryGroupTitle:
        return _paragraphXml(_rtlPrefix(text), 'CommentarySubheading');
      case PrintBlockKind.commentary:
        return _paragraphXml(text, 'CommentaryBody');
    }
  }

  static String _paragraphXml(
    String text,
    String styleId, {
    List<PrintFootnote> footnotes = const [],
    List<_WordFootnote>? registry,
  }) {
    if (text.isEmpty) {
      return '''
<w:p>
  <w:pPr>
    <w:pStyle w:val="$styleId"/>
    ${_paragraphPropertiesXml(styleId)}
  </w:pPr>
</w:p>''';
    }

    final buffer = StringBuffer()..write('''
<w:p>
  <w:pPr>
    <w:pStyle w:val="$styleId"/>
    ${_paragraphPropertiesXml(styleId)}
  </w:pPr>''');

    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final part = _escapeXml(parts[i]);
      if (part.isNotEmpty) {
        buffer.write('''
<w:r>
  <w:rPr><w:rtl/></w:rPr>
  <w:t xml:space="preserve">$part</w:t>
</w:r>''');
      }
      if (i < parts.length - 1) {
        buffer.write('<w:r><w:rPr><w:rtl/></w:rPr><w:br/></w:r>');
      }
    }

    for (final footnote in footnotes) {
      if (registry == null) continue;
      final id = registry.length + 2;
      registry.add(_WordFootnote(id: id, text: footnote.text));
      buffer.write('''
<w:r>
  <w:rPr><w:rtl/><w:vertAlign w:val="superscript"/></w:rPr>
  <w:footnoteReference w:id="$id"/>
</w:r>''');
    }

    buffer.write('</w:p>');
    return buffer.toString();
  }

  static String _paragraphPropertiesXml(String styleId) {
    final jc = switch (styleId) {
      'Title' || 'Header' || 'Footer' => '<w:jc w:val="center"/>',
      'BodyRtl' || 'CommentaryBody' => '<w:jc w:val="both"/>',
      _ => '',
    };

    return '<w:bidi/>$jc<w:rPr><w:rtl/></w:rPr>';
  }

  static String _rtlPrefix(String text) => '\u200F$text';

  static String _buildFootnotesXml(List<_WordFootnote> footnotes) {
    final buffer =
        StringBuffer('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:footnote w:id="-1" w:type="separator">
    <w:p><w:r><w:separator/></w:r></w:p>
  </w:footnote>
  <w:footnote w:id="0" w:type="continuationSeparator">
    <w:p><w:r><w:continuationSeparator/></w:r></w:p>
  </w:footnote>''');

    for (final footnote in footnotes) {
      buffer.write('''
  <w:footnote w:id="${footnote.id}">
    <w:p>
      <w:pPr><w:pStyle w:val="FootnoteText"/></w:pPr>
      <w:r><w:rPr><w:rtl/><w:vertAlign w:val="superscript"/></w:rPr><w:footnoteRef/></w:r>
      <w:r><w:rPr><w:rtl/></w:rPr><w:t xml:space="preserve"> ${_escapeXml(footnote.text)}</w:t></w:r>
    </w:p>
  </w:footnote>''');
    }

    buffer.write('\n</w:footnotes>');
    return buffer.toString();
  }

  static String _buildCoreXml(String title) {
    final escapedTitle = _escapeXml(title);
    final now = DateTime.now().toUtc().toIso8601String();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
 xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:dcterms="http://purl.org/dc/terms/"
 xmlns:dcmitype="http://purl.org/dc/dcmitype/"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>$escapedTitle</dc:title>
  <dc:creator>Otzaria</dc:creator>
  <cp:lastModifiedBy>Otzaria</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>''';
  }

  static String _buildHeaderXml(String title) {
    final escapedTitle = _escapeXml(title);
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr>
      <w:pStyle w:val="Header"/>
    </w:pPr>
    <w:r>
      <w:t xml:space="preserve">$escapedTitle</w:t>
    </w:r>
  </w:p>
</w:hdr>''';
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

const String _contentTypesXml =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
  <Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
  <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
  <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';

const String _rootRelsXml =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

const String _documentRelsXml =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
  <Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>
</Relationships>''';

const String _appXml =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
 xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Otzaria</Application>
</Properties>''';

const String _footerXml =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:p>
    <w:pPr>
      <w:pStyle w:val="Footer"/>
    </w:pPr>
    <w:r><w:t xml:space="preserve">עמוד </w:t></w:r>
    <w:r><w:fldChar w:fldCharType="begin"/></w:r>
    <w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
    <w:r><w:fldChar w:fldCharType="separate"/></w:r>
    <w:r><w:t>1</w:t></w:r>
    <w:r><w:fldChar w:fldCharType="end"/></w:r>
    <w:r><w:t xml:space="preserve"> מתוך </w:t></w:r>
    <w:r><w:fldChar w:fldCharType="begin"/></w:r>
    <w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r>
    <w:r><w:fldChar w:fldCharType="separate"/></w:r>
    <w:r><w:t>1</w:t></w:r>
    <w:r><w:fldChar w:fldCharType="end"/></w:r>
    <w:r><w:t xml:space="preserve">  |  הודפס מתוך אוצריא</w:t></w:r>
  </w:p>
</w:ftr>''';

const String _numberingXml =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:multiLevelType w:val="hybridMultilevel"/>
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="decimal"/>
      <w:lvlText w:val="%1."/>
      <w:lvlJc w:val="right"/>
      <w:pPr><w:ind w:left="360" w:hanging="360"/><w:bidi/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
</w:numbering>''';

const String _stylesXml =
    '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
        <w:lang w:bidi="he-IL"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:bidi/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:bidi/>
      <w:spacing w:after="140" w:line="300" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>
      <w:sz w:val="26"/>
      <w:szCs w:val="26"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:bidi/>
      <w:jc w:val="center"/>
      <w:spacing w:before="120" w:after="240"/>
    </w:pPr>
    <w:rPr>
      <w:b/>
      <w:sz w:val="34"/>
      <w:szCs w:val="34"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="Heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:bidi/><w:spacing w:before="220" w:after="120"/></w:pPr>
    <w:rPr><w:b/><w:color w:val="1F3B6D"/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="Heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:bidi/><w:spacing w:before="180" w:after="100"/></w:pPr>
    <w:rPr><w:b/><w:color w:val="365F91"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="Heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:bidi/><w:spacing w:before="160" w:after="80"/></w:pPr>
    <w:rPr><w:b/><w:color w:val="5A5A5A"/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading4">
    <w:name w:val="Heading 4"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr><w:bidi/><w:spacing w:before="140" w:after="70"/></w:pPr>
    <w:rPr><w:b/><w:i/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="BodyRtl">
    <w:name w:val="Body RTL"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:bidi/>
      <w:jc w:val="both"/>
      <w:spacing w:after="140" w:line="320" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:sz w:val="26"/>
      <w:szCs w:val="26"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="CommentaryHeading">
    <w:name w:val="Commentary Heading"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:bidi/><w:spacing w:before="180" w:after="80"/></w:pPr>
    <w:rPr><w:b/><w:color w:val="6A4C1F"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="CommentarySubheading">
    <w:name w:val="Commentary Subheading"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:bidi/><w:ind w:left="240"/><w:spacing w:before="80" w:after="60"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="CommentaryBody">
    <w:name w:val="Commentary Body"/>
    <w:basedOn w:val="BodyRtl"/>
    <w:pPr><w:bidi/><w:jc w:val="both"/><w:ind w:left="360"/><w:spacing w:after="100" w:line="300" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:color w:val="444444"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="FootnoteText">
    <w:name w:val="Footnote Text"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:bidi/><w:spacing w:after="80" w:line="260" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Header">
    <w:name w:val="Header"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr>
    <w:rPr><w:color w:val="6E6E6E"/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Footer">
    <w:name w:val="Footer"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr>
    <w:rPr><w:color w:val="6E6E6E"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>
  </w:style>
</w:styles>''';

class _WordFootnote {
  final int id;
  final String text;

  const _WordFootnote({
    required this.id,
    required this.text,
  });
}
