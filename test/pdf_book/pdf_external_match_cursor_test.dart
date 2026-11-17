import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/view/pdf_external_matches_bar.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

import '../helpers/memory_settings_cache.dart';

class _CountingPages extends ListBase<int> {
  final List<int> _pages;
  int reads = 0;

  _CountingPages(int count) : _pages = List.generate(count, (i) => i * 2 + 1);

  @override
  int get length => _pages.length;

  @override
  set length(int value) => throw UnsupportedError('Read-only list');

  @override
  int operator [](int index) {
    reads++;
    return _pages[index];
  }

  @override
  void operator []=(int index, int value) {
    throw UnsupportedError('Read-only list');
  }
}

class _CountingMatches extends ExternalBookMatches {
  final _CountingPages _countingPages;

  _CountingMatches(this._countingPages) : super(pages: const []);

  @override
  _CountingPages get pages => _countingPages;
}

/// "הבא"/"הקודם" בסרגל ההתאמות ממשיכים מהעמוד שבקורא, גם אחרי גלילה ידנית.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  const pages = [3, 8, 15];

  test('על עמוד התאמה — היא עצמה, והשכנות משני צדיה', () {
    expect(externalMatchCursor(pages, 8), (exact: 1, previous: 0, next: 2));
  });

  test('בין התאמות — הקרובה לפני ואחרי', () {
    expect(
      externalMatchCursor(pages, 10),
      (exact: null, previous: 1, next: 2),
    );
  });

  test('לפני הראשונה ואחרי האחרונה', () {
    expect(
      externalMatchCursor(pages, 1),
      (exact: null, previous: null, next: 0),
    );
    expect(
      externalMatchCursor(pages, 20),
      (exact: null, previous: 2, next: null),
    );
    expect(externalMatchCursor(pages, 15), (exact: 2, previous: 1, next: null));
  });

  test('רשימה ריקה או התאמה יחידה', () {
    expect(externalMatchCursor([], 1), (exact: null, previous: null, next: null));
    expect(externalMatchCursor([3], 3), (exact: 0, previous: null, next: null));
  });

  test('חיפוש בקצה רשימה גדולה קורא רק מספר לוגריתמי של דפים', () {
    final large = _CountingPages(50000);

    expect(
      externalMatchCursor(large, 99998),
      (exact: null, previous: 49998, next: 49999),
    );
    expect(large.reads, lessThanOrEqualTo(17));
  });

  testWidgets('תפריט ההתאמות קורא את הדפים רק בפתיחה וניווט עובד', (
    tester,
  ) async {
    final matches = _CountingMatches(_CountingPages(32));
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: '/test.pdf'),
      pageNumber: 1,
      externalMatches: matches,
    );
    addTearDown(tab.dispose);
    final visited = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfExternalMatchesBar(
            tab: tab,
            onNavigateToPage: (page) async => visited.add(page),
          ),
        ),
      ),
    );

    final counter = find.text('עמוד 1 · 1/32');
    expect(counter, findsOneWidget);
    expect(matches.pages.reads, lessThan(16));

    await tester.tap(counter);
    await tester.pumpAndSettle();
    expect(matches.pages.reads, greaterThanOrEqualTo(32));
    await tester.tap(find.text('עמוד 3'));
    await tester.pumpAndSettle();

    expect(visited, [3]);
    expect(find.text('עמוד 3 · 2/32'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
