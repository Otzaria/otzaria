import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/view/toc_filter.dart';

import '../support/search_engine_test_init.dart';

TocEntry _entry({
  required String text,
  required int index,
  required int level,
  TocEntry? parent,
  List<TocEntry> children = const [],
}) {
  final entry = TocEntry(
    text: text,
    index: index,
    level: level,
    parent: parent,
  );
  entry.children = children;
  return entry;
}

Future<void> main() async {
  // הקוד הנבדק קורא ל-sanitizeQuery/splitQueryWords שמאצילים למנוע ה-Rust;
  // הטסטים המסומנים מדולגים כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  test('filterTocEntriesForSearch keeps only matching branches', () {
    final root = _entry(text: 'Book', index: 0, level: 1);
    final chapterA =
        _entry(text: 'Chapter A', index: 1, level: 2, parent: root);
    final chapterB =
        _entry(text: 'Chapter B', index: 2, level: 2, parent: root);
    root.children = [chapterA, chapterB];

    final appendixRoot = _entry(text: 'Appendix', index: 3, level: 1);
    final appendixA =
        _entry(text: 'Appendix A', index: 4, level: 2, parent: appendixRoot);
    appendixRoot.children = [appendixA];

    final entries = [root, appendixRoot];

    final filtered = filterTocEntriesForSearch(entries, 'Chapter');

    expect(filtered.length, 1);
    expect(filtered.first.text, 'Book');
    expect(filtered.first.children.length, 2);
    expect(filtered.first.children[0].text, 'Chapter A');
    expect(filtered.first.children[1].text, 'Chapter B');
  }, skip: engineReady ? false : searchEngineSkipReason);

  test('filterTocEntriesForSearch returns empty list for empty query', () {
    final root = _entry(text: 'Book', index: 0, level: 1);
    final entries = [root];

    final filtered = filterTocEntriesForSearch(entries, '   ');

    expect(filtered, isEmpty);
  }, skip: engineReady ? false : searchEngineSkipReason);

  test('shouldExpandInSearch defaults to true when no state is stored', () {
    expect(shouldExpandInSearch(null), isTrue);
    expect(shouldExpandInSearch(true), isTrue);
    expect(shouldExpandInSearch(false), isFalse);
  });

  test('search results prefer more relevant exact entries first', () {
    final root = _entry(text: 'ספר', index: 0, level: 1);
    final commentaryMatch =
        _entry(text: 'מאירי על שבת דף ע', index: 2, level: 2, parent: root);
    final exactMatch =
        _entry(text: 'שבת דף ע', index: 1, level: 2, parent: root);
    root.children = [commentaryMatch, exactMatch];

    final filtered = filterTocEntriesForSearch([root], 'שבת דף ע');

    expect(filtered.single.children.map((entry) => entry.text).toList(), [
      'שבת דף ע',
      'מאירי על שבת דף ע',
    ]);
  }, skip: engineReady ? false : searchEngineSkipReason);

  test('container parents keep book order when only descendants match', () {
    TocEntry section(String title, int index, String childTitle) {
      final parent = _entry(text: title, index: index, level: 1);
      parent.children = [
        _entry(text: childTitle, index: index + 1, level: 2, parent: parent),
      ];
      return parent;
    }

    final entries = [
      section('אורח חיים', 0, 'סימן א'),
      section('יורה דעה', 2, 'סימן א'),
      section('אבן העזר', 4, 'סימן א'),
      section('חושן משפט', 6, 'סימן א'),
    ];

    final filtered = filterTocEntriesForSearch(entries, 'סימן א');

    expect(filtered.map((entry) => entry.text).toList(), [
      'אורח חיים',
      'יורה דעה',
      'אבן העזר',
      'חושן משפט',
    ]);
  }, skip: engineReady ? false : searchEngineSkipReason);
}
