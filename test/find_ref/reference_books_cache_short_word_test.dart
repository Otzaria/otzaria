import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';

import 'support/seeded_reference_library.dart';

void main() {
  tearDown(resetSeededLibrary);

  test('מילה קצרה בשאילתה מקורבת חייבת להופיע כמילה שלמה', () {
    seedLibrary(const [
      (id: 1, title: 'שער ב משפט', acronyms: []),
      (id: 2, title: 'שער ברק משפט', acronyms: []),
      (id: 3, title: 'שער אב משפט', acronyms: []),
      (id: 4, title: 'שער אבד משפט', acronyms: []),
      (id: 5, title: 'ספר החמישי', acronyms: ['משפט ב']),
      (id: 6, title: 'ספר משפט', acronyms: ['שער ב']),
    ]);
    final cache = ReferenceBooksCache.instance;

    for (final query in ['משפטט ב', 'ב משפטט']) {
      final hits = cache.search(query);
      expect(hits.map((h) => h.bookId), unorderedEquals([1, 5]));
      expect(
        hits.map((h) => h.matchRank),
        everyElement(ReferenceBooksCache.fuzzyMatchRank),
      );
      expect(hits.singleWhere((h) => h.bookId == 5).matchedTerm, 'משפט ב');
    }
    expect(cache.search('משפטט אב').map((h) => h.bookId), [3]);
    expect(cache.search('משפטט ג'), isEmpty);
    expect(cache.search('משפטט ב אב'), isEmpty);

    seedLibrary(const [(id: 1, title: 'שער ג משפט', acronyms: [])]);
    expect(cache.search('משפטט ב'), isEmpty);
    expect(cache.search('משפטט ג').single.bookId, 1);
  });
}
