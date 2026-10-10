import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_outlines_screen.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:pdfrx/pdfrx.dart';

PdfOutlineNode _node(String title, [List<PdfOutlineNode>? kids]) =>
    PdfOutlineNode(title: title, dest: null, children: kids ?? const []);

void main() {
  final outline = [
    _node('הַקְדָּמָה'),
    _node('מסכת ב"ב', [
      _node('בָּבָא בַּתְרָא דף ב'),
      _node('דף ג', [_node('תוס\' ד"ה בבא')]),
    ]),
    _node('מסכת חולין', [_node('דף קו')]),
  ];

  test('הסינון זהה לבדיקת כותרת בודדת, באותו סדר ועם אותן רמות', () {
    final entries = flattenPdfOutlineForSearch(outline);
    for (final query in [
      '',
      'בבא',
      'דף',
      'מסכת',
      'הקדמה',
      'חולין קו',
      'זבחים',
    ]) {
      final q = normalizeFindText(query);
      final expected = entries
          .where((e) => normalizeFindText(e.node.title).contains(q))
          .toList();
      expect(filterPdfOutline(entries, query), expected, reason: query);
    }
    expect(entries.map((e) => (e.node.title, e.level)).toList(), [
      ('הַקְדָּמָה', 0),
      ('מסכת ב"ב', 0),
      ('בָּבָא בַּתְרָא דף ב', 1),
      ('דף ג', 1),
      ('תוס\' ד"ה בבא', 2),
      ('מסכת חולין', 0),
      ('דף קו', 1),
    ]);
  });

  test('הכותרות מנורמלות פעם אחת, והסינון אינו מנרמל אותן שוב', () {
    final node = _node('כותרת גלויה');
    final entries = [(node: node, level: 0, normalizedTitle: 'מנורמל מראש')];
    expect(filterPdfOutline(entries, 'מנורמל'), entries);
    expect(filterPdfOutline(entries, 'גלויה'), isEmpty);
  });
}
