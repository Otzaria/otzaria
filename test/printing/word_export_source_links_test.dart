import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_import_export_service.dart';
import 'package:otzaria/personal_notes/utils/personal_note_source_link.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:pdf/pdf.dart';
import 'package:xml/xml.dart';

const _wordNamespace =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _relationshipNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

PersonalNote _note(
  String id, {
  String bookId = 'ספר בדיקה',
  int? lineNumber = 1,
  PersonalNoteStatus status = PersonalNoteStatus.located,
  PdfNoteAnchor? pdfAnchor,
}) => PersonalNote(
  id: id,
  bookId: bookId,
  lineNumber: lineNumber,
  lastKnownLineNumber: null,
  status: status,
  pdfAnchor: pdfAnchor,
  content: 'תוכן $id',
  contentPlain: 'תוכן $id',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Archive _document(List<PrintBlock> blocks) => ZipDecoder().decodeBytes(
  WordExportService.createWordDocument(
    title: 'בדיקת קישורים',
    blocks: blocks,
    format: PdfPageFormat.a4,
    isLandscape: false,
    pageMargin: 20,
  ),
);

XmlDocument _xml(Archive archive, String path) {
  final file = archive.findFile(path);
  expect(file, isNotNull, reason: path);
  return XmlDocument.parse(utf8.decode(file!.content as List<int>));
}

List<XmlElement> _hyperlinks(XmlDocument document) => document
    .findAllElements('hyperlink', namespaceUri: _wordNamespace)
    .toList();

Map<String, XmlElement> _relationships(Archive archive) => {
  for (final relationship in _xml(
    archive,
    'word/_rels/document.xml.rels',
  ).rootElement.childElements)
    relationship.getAttribute('Id')!: relationship,
};

String? _target(XmlElement hyperlink, Map<String, XmlElement> relationships) {
  final id = hyperlink.getAttribute('id', namespaceUri: _relationshipNamespace);
  expect(id, isNotNull);
  expect(relationships, contains(id));
  final relationship = relationships[id]!;
  expect(
    relationship.getAttribute('Type'),
    '$_relationshipNamespace/hyperlink',
  );
  expect(relationship.getAttribute('TargetMode'), 'External');
  return relationship.getAttribute('Target');
}

void main() {
  group('Word source-link metadata', () {
    test('old block JSON remains unlinked and new metadata survives JSON', () {
      final oldJson = <String, Object?>{
        'kind': 'heading',
        'text': 'מיקום ישן',
        'headingLevel': 2,
        'footnotes': [
          <String, Object?>{'text': 'הערת שוליים'},
        ],
      };
      final oldBlock = PrintBlock.fromJson(oldJson);
      expect(oldBlock.sourceLink, isNull);
      expect(oldBlock.toJson(), oldJson);

      final linkedJson = <String, Object?>{
        ...oldJson,
        'sourceLink': 'otzaria://open/book/12?source=user&index=2',
      };
      final roundTrip = PrintBlock.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(linkedJson)) as Map),
      );
      expect(roundTrip.toJson(), linkedJson);
      expect(roundTrip.footnotes.single.text, 'הערת שוליים');
    });

    test('DOCX links retain heading, inline styles, RTL, and footnotes', () {
      const source = 'otzaria://open/book/12?source=user&index=2';
      final archive = _document(const [
        PrintBlock(
          kind: PrintBlockKind.heading,
          headingLevel: 2,
          text: 'מיקום <b>מודגש</b> <i>נטוי</i> &amp; טקסט',
          sourceLink: source,
          footnotes: [PrintFootnote(text: 'הערת שוליים נפרדת')],
        ),
        PrintBlock(kind: PrintBlockKind.text, text: 'תוכן הערה'),
      ]);
      final document = _xml(archive, 'word/document.xml');
      final link = _hyperlinks(document).single;
      expect(_target(link, _relationships(archive)), source);
      expect(link.innerText, 'מיקום מודגש נטוי & טקסט');
      final paragraph = link.parent as XmlElement;
      expect(paragraph.name.local, 'p');
      expect(paragraph.childElements.first.name.local, 'pPr');
      expect(
        paragraph
            .findAllElements('pStyle', namespaceUri: _wordNamespace)
            .single
            .getAttribute('val', namespaceUri: _wordNamespace),
        'Heading2',
      );
      for (final run in link.childElements) {
        expect(
          run.findAllElements('rtl', namespaceUri: _wordNamespace),
          hasLength(1),
        );
        expect(
          run
              .findAllElements('rStyle', namespaceUri: _wordNamespace)
              .single
              .getAttribute('val', namespaceUri: _wordNamespace),
          'Hyperlink',
        );
      }
      expect(
        link.findAllElements('b', namespaceUri: _wordNamespace),
        hasLength(1),
      );
      expect(
        link.findAllElements('bCs', namespaceUri: _wordNamespace),
        hasLength(1),
      );
      expect(
        link.findAllElements('i', namespaceUri: _wordNamespace),
        hasLength(1),
      );
      expect(
        link.findAllElements('iCs', namespaceUri: _wordNamespace),
        hasLength(1),
      );
      expect(
        link.findAllElements('footnoteReference', namespaceUri: _wordNamespace),
        isEmpty,
      );
      expect(
        paragraph.findAllElements(
          'footnoteReference',
          namespaceUri: _wordNamespace,
        ),
        hasLength(1),
      );
      final styles = _xml(archive, 'word/styles.xml');
      final hyperlinkStyle = styles
          .findAllElements('style', namespaceUri: _wordNamespace)
          .singleWhere(
            (style) =>
                style.getAttribute('styleId', namespaceUri: _wordNamespace) ==
                'Hyperlink',
          );
      expect(
        hyperlinkStyle.getAttribute('type', namespaceUri: _wordNamespace),
        'character',
      );
      expect(
        hyperlinkStyle.findAllElements('u', namespaceUri: _wordNamespace),
        hasLength(1),
      );
      expect(
        _xml(archive, 'word/footnotes.xml').innerText,
        contains('הערת שוליים נפרדת'),
      );
    });

    test(
      'relationship IDs are unique, reused, escaped, and local to export',
      () {
        const firstTarget = 'otzaria://open/book/7?index=2&label="A<B>\'';
        const secondTarget = 'otzaria://open/pdf/8?source=db%3Ademo&index=5';
        final archive = _document(const [
          PrintBlock(
            kind: PrintBlockKind.heading,
            text: 'א',
            sourceLink: firstTarget,
          ),
          PrintBlock(
            kind: PrintBlockKind.heading,
            text: 'ב',
            sourceLink: secondTarget,
          ),
          PrintBlock(
            kind: PrintBlockKind.heading,
            text: 'ג',
            sourceLink: firstTarget,
          ),
        ]);
        final relationships = _relationships(archive);
        final allRelationships = _xml(
          archive,
          'word/_rels/document.xml.rels',
        ).rootElement.childElements;
        expect(relationships.length, allRelationships.length);
        expect(
          relationships.keys,
          containsAll(['rId1', 'rId2', 'rId3', 'rId4', 'rId5']),
        );
        final links = _hyperlinks(_xml(archive, 'word/document.xml'));
        expect(
          links.map((link) => _target(link, relationships)),
          [firstTarget, secondTarget, firstTarget],
        );
        expect(
          links.map(
            (link) =>
                link.getAttribute('id', namespaceUri: _relationshipNamespace),
          ),
          ['rId6', 'rId7', 'rId6'],
        );
        expect(relationships.length, 7);

        final next = _document(const [
          PrintBlock(
            kind: PrintBlockKind.heading,
            text: 'אחר',
            sourceLink: secondTarget,
          ),
        ]);
        expect(_relationships(next).length, 6);
        expect(
          _relationships(next)['rId6']!.getAttribute('Target'),
          secondTarget,
        );
      },
    );

    test('unlinked and empty blocks create no hyperlink relationships', () {
      final archive = _document(const [
        PrintBlock(kind: PrintBlockKind.heading, text: 'כותרת ללא קישור'),
        PrintBlock(kind: PrintBlockKind.text, text: '<b>תוכן</b> ללא קישור'),
        PrintBlock(
          kind: PrintBlockKind.heading,
          text: 'קישור ריק',
          sourceLink: '',
        ),
        PrintBlock(
          kind: PrintBlockKind.heading,
          text: ' ',
          sourceLink: 'otzaria://open/book/1?index=0',
        ),
      ]);
      expect(_hyperlinks(_xml(archive, 'word/document.xml')), isEmpty);
      expect(_relationships(archive).length, 5);
    });
  });

    test('selection punctuation survives all the way to document.xml', () {
      final note = _note('quoted').copyWith(
        displayTitle: 'אב״ג',
        anchorText: 'אבג',
      );
      final blocks = PersonalNotesImportExportService().buildWordExportBlocks(
        notes: [note],
        locationRef: (_) => null,
      );
      final archive = _document(blocks);
      final document = _xml(archive, 'word/document.xml');

      expect(document.innerText, contains('אב״ג.'));
      expect(document.innerText, isNot(contains('אבג.')));
    });

  group('Personal-note export grouping', () {
    test('identical labels group only notes at the same linked location', () {
      final notes = [
        _note('c', lineNumber: 3),
        _note('a', lineNumber: 2),
        _note('b', lineNumber: 2),
        _note('missing', lineNumber: null, status: PersonalNoteStatus.missing),
      ];
      final blocks = PersonalNotesImportExportService().buildWordExportBlocks(
        notes: notes,
        locationRef: (_) => 'פרק & בדיקה',
        sourceLink: (note) {
          expect(note.hasLocation, isTrue);
          return 'otzaria://open/book/7?index=${note.lineNumber! - 1}';
        },
      );
      final locations = blocks
          .where((block) => block.headingLevel == 2)
          .toList();
      expect(locations.map((block) => block.text), [
        'פרק &amp; בדיקה',
        'פרק &amp; בדיקה',
        'הערות ללא מיקום',
      ]);
      expect(locations.map((block) => block.sourceLink), [
        'otzaria://open/book/7?index=1',
        'otzaria://open/book/7?index=2',
        null,
      ]);
      expect(
        blocks
            .where((block) => block.headingLevel != 2)
            .every(
              (block) => block.sourceLink == null,
            ),
        isTrue,
      );
      final archive = _document(blocks);
      expect(
        _hyperlinks(_xml(archive, 'word/document.xml')).map(
          (link) => _target(link, _relationships(archive)),
        ),
        ['otzaria://open/book/7?index=1', 'otzaria://open/book/7?index=2'],
      );
    });

    test('legacy export callback preserves label grouping without links', () {
      final blocks = PersonalNotesImportExportService().buildWordExportBlocks(
        notes: [_note('a'), _note('b', lineNumber: 2)],
        locationRef: (_) => 'פרק משותף',
      );
      expect(blocks.where((block) => block.headingLevel == 2), hasLength(1));
      expect(blocks.every((block) => block.sourceLink == null), isTrue);
    });
  });

  group('Personal-note source routing', () {
    test(
      'PDF document identity chooses the correct edition and rejects ambiguity',
      () {
        final first = PdfBook(id: 31, title: 'ספר בדיקה', path: '/first.pdf');
        final second = PdfBook(id: 32, title: 'ספר בדיקה', path: '/second.pdf');
        final library = Library(categories: [])
          ..books.addAll([first, second, TextBook(id: 33, title: 'ספר בדיקה')]);
        final notes = [
          _note(
            'first',
            pdfAnchor: PdfNoteAnchor(
              pageNumber: 4,
              x: 0.2,
              y: 0.6,
              documentId: pdfPersonalNoteDocumentId(first),
            ),
          ),
          _note(
            'second',
            lineNumber: 2,
            pdfAnchor: PdfNoteAnchor(
              pageNumber: 7,
              x: 0.2,
              y: 0.6,
              documentId: pdfPersonalNoteDocumentId(second),
            ),
          ),
          _note(
            'ambiguous',
            lineNumber: 3,
            pdfAnchor: const PdfNoteAnchor(pageNumber: 3, x: 0.2, y: 0.6),
          ),
          _note(
            'unavailable',
            lineNumber: 4,
            pdfAnchor: const PdfNoteAnchor(
              pageNumber: 3,
              x: 0.2,
              y: 0.6,
              documentId: 'unavailable-document',
            ),
          ),
        ];
        expect(personalNoteSourceBook(library, notes[0]), same(first));
        expect(personalNoteSourceBook(library, notes[1]), same(second));
        expect(
          personalNoteSourceLink(
            first,
            notes[1],
            pdfLinkCandidates: [first, second],
          ),
          isNull,
        );
        expect(personalNoteSourceBook(library, notes[2]), isNull);
        expect(personalNoteSourceBook(library, notes[3]), isNull);
        final blocks = PersonalNotesImportExportService().buildWordExportBlocks(
          notes: notes,
          locationRef: (note) => note.id,
          sourceLink: (note) => personalNoteSourceLink(
            personalNoteSourceBook(library, note),
            note,
            pdfLinkCandidates: [first, second],
          ),
        );
        final archive = _document(blocks);
        expect(
          _hyperlinks(_xml(archive, 'word/document.xml')).map(
            (link) => _target(link, _relationships(archive)),
          ),
          ['otzaria://open/pdf/31?index=4', 'otzaria://open/pdf/32?index=7'],
        );
      },
    );

    test('borrowed PDF IDs cannot link two different documents to one URI', () {
      final first = PdfBook(id: 40, title: 'ספר בדיקה', path: '/first.pdf');
      final second = PdfBook(id: 40, title: 'ספר בדיקה', path: '/second.pdf');
      final note = _note(
        'borrowed-id',
        pdfAnchor: PdfNoteAnchor(
          pageNumber: 5,
          x: 0.2,
          y: 0.6,
          documentId: pdfPersonalNoteDocumentId(first),
        ),
      );
      final library = Library(categories: [])..books.addAll([first, second]);
      expect(personalNoteSourceBook(library, note), same(first));
      expect(personalNoteSourceLink(first, note), isNull);
      for (final candidates in <List<PdfBook>>[
        [],
        [second],
        [first, second],
      ]) {
        expect(
          personalNoteSourceLink(first, note, pdfLinkCandidates: candidates),
          isNull,
        );
      }
      expect(
        personalNoteSourceLink(first, note, pdfLinkCandidates: [first, first]),
        'otzaria://open/pdf/40?index=5',
      );
      expect(
        personalNoteSourceLink(
          first,
          note,
          pdfLinkCandidates: [
            first,
            PdfBook(id: 41, title: 'ספר בדיקה', path: '/second.pdf'),
            PdfBook(
              id: 40,
              title: 'ספר בדיקה',
              path: '/second.pdf',
              source: BookSource.user,
            ),
          ],
        ),
        'otzaria://open/pdf/40?index=5',
      );
    });

    for (final source in [
      BookSource.official,
      BookSource.user,
      BookSource.attached('fixture-db'),
    ]) {
      test('DOCX keeps exact text and PDF locations for ${source.wireKey}', () {
        final text = TextBook(id: 21, title: 'ספר בדיקה', source: source);
        final pdf = PdfBook(
          id: 22,
          title: 'ספר בדיקה',
          path: '/fixture.pdf',
          source: source,
        );
        final library = Library(categories: [])..books.addAll([pdf, text]);
        final textNote = _note('text', bookId: personalNotesBookKey(text));
        final pdfNote = _note(
          'pdf',
          bookId: personalNotesBookKey(pdf),
          lineNumber: 80,
          pdfAnchor: const PdfNoteAnchor(pageNumber: 4, x: 0.2, y: 0.6),
        );
        expect(personalNoteSourceBook(library, textNote), same(text));
        expect(personalNoteSourceBook(library, pdfNote), same(pdf));
        final sourceParameter = switch (source) {
          OfficialBookSource() => '',
          UserBookSource() => 'source=user&',
          AttachedBookSource(:final slug) => 'source=db%3A$slug&',
        };
        final expected = [
          'otzaria://open/book/21?${sourceParameter}index=0',
          'otzaria://open/pdf/22?${sourceParameter}index=4',
        ];
        final blocks = PersonalNotesImportExportService().buildWordExportBlocks(
          notes: [textNote, pdfNote],
          locationRef: (note) => 'מיקום ${note.id}',
          sourceLink: (note) => personalNoteSourceLink(
            personalNoteSourceBook(library, note),
            note,
            pdfLinkCandidates: [pdf],
          ),
        );
        final archive = _document(blocks);
        expect(
          _hyperlinks(_xml(archive, 'word/document.xml')).map(
            (link) => _target(link, _relationships(archive)),
          ),
          expected,
        );
        expect(
          personalNoteSourceLink(
            pdf,
            _note(
              'legacy-pdf',
              bookId: personalNotesBookKey(pdf),
              lineNumber: 7,
            ),
            pdfLinkCandidates: [pdf],
          ),
          'otzaria://open/pdf/22?${sourceParameter}index=7',
        );
      });
    }

    test('same title in another source never supplies a target', () {
      final official = TextBook(id: 1, title: 'ספר בדיקה');
      final user = TextBook(id: 1, title: 'ספר בדיקה', source: BookSource.user);
      final attached = TextBook(
        id: 1,
        title: 'ספר בדיקה',
        source: BookSource.attached('fixture-db'),
      );
      final library = Library(categories: [])
        ..books.addAll([user, attached, official]);
      for (final book in [official, user, attached]) {
        final note = _note('source', bookId: personalNotesBookKey(book));
        expect(personalNoteSourceBook(library, note), same(book));
        for (final other in [
          official,
          user,
          attached,
        ].where((b) => b != book)) {
          expect(personalNoteSourceLink(other, note), isNull);
        }
      }
      expect(
        personalNoteSourceBook(Library(categories: []), _note('unknown')),
        isNull,
      );
      expect(personalNoteSourceLink(null, _note('unknown')), isNull);
    });

    test('unresolved or invalid locations do not become first-line links', () {
      final text = TextBook(id: 4, title: 'ספר בדיקה');
      final anchored = _note(
        'pdf-only',
        pdfAnchor: const PdfNoteAnchor(pageNumber: 3, x: 0.5, y: 0.5),
      );
      final textOnly = Library(categories: [])..books.add(text);
      expect(personalNoteSourceBook(textOnly, anchored), isNull);
      expect(personalNoteSourceLink(text, anchored), isNull);
      expect(
        personalNoteSourceLink(text, _note('other', bookId: 'ספר אחר')),
        isNull,
      );
      for (final id in <int?>[null, 0, -1]) {
        expect(
          personalNoteSourceLink(
            TextBook(id: id, title: 'ספר בדיקה'),
            _note('id'),
          ),
          isNull,
        );
      }
      for (final line in <int?>[null, 0, -1]) {
        expect(
          personalNoteSourceLink(text, _note('line', lineNumber: line)),
          isNull,
        );
      }
      expect(
        personalNoteSourceLink(
          text,
          _note('missing', status: PersonalNoteStatus.missing),
        ),
        isNull,
      );
    });
  });
}
