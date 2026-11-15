import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_chapter_outline.dart';
import 'package:pdfrx/pdfrx.dart';

PdfOutlineNode _node(
  String title,
  int? page, [
  List<PdfOutlineNode> children = const [],
]) => PdfOutlineNode(
  title: title,
  dest: page == null ? null : PdfDest(page, PdfDestCommand.fit, null),
  children: children,
);

List<String> _shape(List<PdfOutlineNode> nodes) => [
  for (final n in nodes)
    n.children.isEmpty
        ? '${n.title}@${n.dest?.pageNumber}'
        : '${n.title}@${n.dest?.pageNumber}[${_shape(n.children).join(',')}]',
];

void main() {
  // כמו ב-PDF הש"ס: שורש בשם המסכת ודף בכל עמוד.
  final bavli = [
    _node('ברכות', 1, [
      _node('דף ב.', 1),
      _node('דף ב:', 2),
      _node('דף ג.', 3),
      _node('דף ג:', 4),
      _node('דף ד.', 5),
    ]),
  ];

  test('groups the dafim under chapters inside the tractate root', () {
    final grouped = groupPdfOutlineByChapters(bavli, [
      (title: 'מאימתי', page: 1),
      (title: 'היה קורא', page: 4),
    ]);
    expect(_shape(grouped), [
      'ברכות@1[מאימתי@1[דף ב.@1,דף ב:@2,דף ג.@3],היה קורא@4[דף ג:@4,דף ד.@5]]',
    ]);
  });

  test('keeps entries before the first chapter outside it', () {
    final grouped = groupPdfOutlineByChapters(
      [_node('שער', 1), _node('דף ב.', 2), _node('דף ב:', 3)],
      [(title: 'מאימתי', page: 2)],
    );
    expect(_shape(grouped), ['שער@1', 'מאימתי@2[דף ב.@2,דף ב:@3]']);
  });

  test('chapters that start on the same page keep their order', () {
    final grouped = groupPdfOutlineByChapters(
      [_node('דף ב.', 1), _node('דף ב:', 2)],
      [(title: 'א', page: 1), (title: 'ב', page: 2), (title: 'ג', page: 2)],
    );
    expect(_shape(grouped), ['א@1[דף ב.@1]', 'ב@2', 'ג@2[דף ב:@2]']);
  });

  test('a chapter maps through the daf heading it starts under', () {
    // ברכות "מי שמתו": שורה 873, בין "דף יז:" (861) ל"דף יח." (879).
    const tocLines = [0, 1, 16, 861, 879];
    expect(tocLineAtOrBefore(tocLines, 873), 861);
    expect(tocLineAtOrBefore(tocLines, 879), 879);
    expect(tocLineAtOrBefore(const [5, 9], 2), 2);
  });

  test('returns the outline unchanged when grouping does not apply', () {
    const chapters = [(title: 'מאימתי', page: 1), (title: 'היה קורא', page: 4)];
    expect(groupPdfOutlineByChapters(bavli, const []), same(bavli));

    final nested = [
      _node('פרק א', 1, [_node('דף ב.', 1)]),
      _node('פרק ב', 4, [_node('דף ג:', 4)]),
    ];
    expect(groupPdfOutlineByChapters(nested, chapters), same(nested));

    final withoutDest = [_node('דף ב.', 1), _node('הערות', null)];
    expect(groupPdfOutlineByChapters(withoutDest, chapters), same(withoutDest));

    final unsorted = [_node('דף ג:', 4), _node('דף ב.', 1)];
    expect(groupPdfOutlineByChapters(unsorted, chapters), same(unsorted));

    expect(
      groupPdfOutlineByChapters(bavli, [
        (title: 'ב', page: 4),
        (title: 'א', page: 1),
      ]),
      same(bavli),
    );
  });
}
