import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/commentary_print_markers.dart';
import 'package:otzaria/text_book/models/book_notes.dart';

Link _link(String label, int at, {String title = 'מפרש', bool raw = false}) =>
    Link(
      heRef: 'מפרש, $label',
      index1: 1,
      path2: title,
      index2: 1,
      connectionType: 'commentary',
      anchorStart: at,
      anchorLabel: label,
      anchorOffsetsAreRaw: raw,
    );

String _prepare(
  String text,
  List<Link> links, {
  BookNotes notes = BookNotes.empty,
  DivineNameSpans? names,
}) => withPrintCommentaryMarkers(
  rawLine: text,
  lineIndex: 0,
  printedLinks: links,
  notes: notes,
  names: names ?? DivineNameSpans.empty,
);

void main() {
  test('ציונים באותה שורה משתמשים בווריאנט המפרש ובמיקומו', () {
    final first = _link('א', 0);
    final second = _link('ב', 5, title: 'מפרש אחר');
    final result = _prepare('ראשון שני', [first, second]);
    expect(result, contains('${anchorMarkerText(first)}</span>ראשון'));
    expect(result, contains('${anchorMarkerText(second)}</span> שני'));
    expect(result, isNot(contains('href=')));
  });

  test('עוגן בטווח שורות מוצג רק בשורת המקור שלו', () {
    final link = _link('א', 0).withTargetRange(1, 2);
    expect(
      withPrintCommentaryMarkers(
        rawLine: 'שורה שנייה',
        lineIndex: 1,
        printedLinks: [link],
        notes: BookNotes.empty,
        names: DivineNameSpans.empty,
      ),
      'שורה שנייה',
    );
  });

  test('שמות אינם מוחלפים לפני חישוב העוגנים', () {
    final names = (DivineNameSpansBuilder()..add(0, 0, 4, DivineNameKind.hvyh))
        .build();
    final link = _link('א', 5);
    final result = _prepare('יהוה שני', [link], names: names);
    expect(result, contains('${anchorMarkerText(link)}</span>שני'));
    expect(result, contains('class="divine-name"'));
  });

  test('עוגן בתוך גוף הערה ועוגן אחריה נשמרים לאחר השחזור', () {
    final notes = (BookNotesBuilder()..add(0, 0, '1', 'גוף הערה', charPos: 4))
        .build();
    final inside = _link('א', 7);
    final after = _link('ב', 13);
    final result = _prepare(
      'אחד<sup class="footnote-marker">1</sup> שני',
      [inside, after],
      notes: notes,
    );
    expect(result, contains('גוף${_marker(inside)} הערה'));
    expect(result, contains('${_marker(after)}שני'));
  });

  test('עוגן HTML גולמי מותאם לגופי הערות שנוספו לפניו', () {
    const raw = 'אחד<sup class="footnote-marker">1</sup> שני';
    final notes = (BookNotesBuilder()..add(0, 0, '1', 'גוף הערה', charPos: 4))
        .build();
    final link = _link('א', raw.indexOf('שני'), raw: true);
    final result = _prepare(raw, [link], notes: notes);
    expect(result, contains('${_marker(link)}שני'));
  });

  test('ללא עוגן או מיקום הערה ידוע אין ציונים במיקום משוער', () {
    final notes = (BookNotesBuilder()..add(0, 0, '1', 'הערה')).build();
    final result = _prepare('אחד', [_link('א', 1)], notes: notes);
    expect(result, isNot(contains('link-anchor')));
    expect(_prepare('אחד', const []), 'אחד');
  });
}

String _marker(Link link) =>
    '<span class="link-anchor link-anchor-${anchorStyleIndexByCommentator([link])[link.path2]}">${anchorMarkerText(link)}</span>';
