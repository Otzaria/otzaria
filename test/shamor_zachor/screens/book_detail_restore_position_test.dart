import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/screens/book_detail_screen.dart';
import 'package:otzaria/tools/shamor_zachor/services/progress_service.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// שומר את ההתקדמות בזיכרון; המקום האחרון עובר דרך Settings (בזיכרון).
class _MemoryProgressService extends ProgressService {
  ProgressMapById saved = {};

  @override
  Future<ProgressMapById> loadProgressDataById() async => saved;

  @override
  Future<CompletionDatesByIdMap> loadCompletionDatesById() async => {};

  @override
  Future<Map<int, List<ProgressColumn>>> loadColumnsByBookId() async => {};

  @override
  Future<ColumnCompletionDatesMap> loadColumnCompletionDates() async => {};

  @override
  Future<void> saveColumnCompletionDates(ColumnCompletionDatesMap d) async {}

  @override
  Future<void> saveCompletionDateById(int bookId, String date) async {}

  @override
  Future<void> saveProgressDataById(ProgressMapById data) async => saved = data;
}

class _ReadyDataProvider extends ShamorZachorDataProvider {
  final List<BookDetails> books;

  _ReadyDataProvider(this.books);

  void replaceNestedBook(BookDetails book) {
    books[1] = book;
    notifyListeners();
  }

  @override
  (BookDetails, String, String)? getBookById(int bookId) {
    for (final book in books) {
      if (book.id == bookId) return (book, 'ספר', 'הלכה');
    }
    return null;
  }

  @override
  bool get isLoading => false;
}

BookSection _leaf(String id, String title) => BookSection(
  id: id,
  title: title,
  level: 2,
  startPage: 0,
  endPage: 0,
  children: const [],
);

/// ספר שטוח של 100 פרקים ("פרק 0" … "פרק 99").
BookDetails _flatBook({int id = 7}) => BookDetails(
  id: id,
  contentType: 'פרק',
  parts: const [],
  sections: [for (var i = 0; i < 100; i++) _leaf('$i', 'פרק $i')],
);

/// ספר היררכי: 20 סימנים, בכל אחד 10 סעיפים ("סעיף s-i").
BookDetails _nestedBook() => BookDetails(
  id: 8,
  contentType: 'סעיף',
  parts: const [],
  sections: [
    for (var s = 0; s < 20; s++)
      BookSection(
        id: 's$s',
        title: 'סימן $s',
        level: 1,
        startPage: 0,
        endPage: 0,
        children: [for (var i = 0; i < 10; i++) _leaf('$s-$i', 'סעיף $s-$i')],
      ),
  ],
);

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('shamor zachor reopens at last touched item (issue #2541)', () {
    late _MemoryProgressService service;
    late ShamorZachorProgressProvider progress;
    late _ReadyDataProvider data;

    setUp(() async {
      service = _MemoryProgressService();
      progress = ShamorZachorProgressProvider(progressService: service);
      data = _ReadyDataProvider([_flatBook(), _nestedBook()]);
      addTearDown(progress.dispose);
      addTearDown(data.dispose);
      await progress.ensureLoaded();
    });

    Future<void> openBook(WidgetTester tester, BookDetails book) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorDataProvider>.value(value: data),
            ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
              value: progress,
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: BookDetailScreen(
                  // מפתח חדש לכל פתיחה, כמו במסך הראשי.
                  key: UniqueKey(),
                  topLevelCategoryKey: 'הלכה',
                  bookName: 'ספר',
                  bookId: book.id,
                  bookDetails: book,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> closeBook(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }

    /// השורה בנויה וגלויה בתוך שטח הגלילה.
    void expectRowVisible(WidgetTester tester, String label) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: '"$label" should be built');
      final rect = tester.getRect(finder);
      final viewport = tester.getRect(find.byType(CustomScrollView));
      expect(
        rect.top >= viewport.top && rect.bottom <= viewport.bottom,
        isTrue,
        reason: '"$label" at $rect should be inside $viewport',
      );
    }

    Future<void> mark(BookDetails book, int index, {bool value = true}) =>
        progress.updateProgressById(book.id!, index, 'learn', value, book);

    testWidgets('reopens at the item marked last', (tester) async {
      final book = data.books[0];
      await openBook(tester, book);
      expect(find.text('פרק 40'), findsNothing);
      await mark(book, 40);
      await closeBook(tester);

      await openBook(tester, book);
      expectRowVisible(tester, 'פרק 40');
      expect(find.text('פרק 0'), findsNothing);
    });

    testWidgets('last in time wins, not the highest marked index', (
      tester,
    ) async {
      final book = data.books[0];
      await mark(book, 70);
      await mark(book, 30);
      await openBook(tester, book);
      expectRowVisible(tester, 'פרק 30');
    });

    testWidgets('un-marking also counts as touching the item', (tester) async {
      final book = data.books[0];
      await mark(book, 20);
      await mark(book, 60);
      await mark(book, 60, value: false);
      await mark(book, 85, value: false);
      await openBook(tester, book);
      expectRowVisible(tester, 'פרק 85');
    });

    testWidgets('range marking remembers the end of the range', (
      tester,
    ) async {
      final book = data.books[0];
      await progress.toggleRangeForColumnById(
        book.id!,
        book,
        'learn',
        50,
        65,
        true,
      );
      await openBook(tester, book);
      expectRowVisible(tester, 'פרק 65');
    });

    testWidgets('hierarchical book reopens inside its section', (
      tester,
    ) async {
      final book = data.books[1];
      await mark(book, 157); // סימן 15, סעיף 7
      await openBook(tester, book);
      expectRowVisible(tester, 'סעיף 15-7');
    });

    testWidgets('each book keeps its own position', (tester) async {
      final flat = data.books[0];
      final nested = data.books[1];
      await mark(flat, 45);
      await mark(nested, 120);
      await openBook(tester, flat);
      expectRowVisible(tester, 'פרק 45');
      await closeBook(tester);
      await openBook(tester, nested);
      expectRowVisible(tester, 'סעיף 12-0');
    });

    testWidgets('a stored item that no longer exists opens at the top', (
      tester,
    ) async {
      final longBook = BookDetails(
        id: 7,
        contentType: 'פרק',
        parts: const [],
        sections: [for (var i = 0; i < 300; i++) _leaf('$i', 'פרק $i')],
      );
      await mark(longBook, 250);
      // תוכן העניינים קוצר ל-100 פרקים.
      await openBook(tester, data.books[0]);
      expectRowVisible(tester, 'פרק 0');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a book never touched opens at the top', (tester) async {
      await openBook(tester, data.books[0]);
      expectRowVisible(tester, 'פרק 0');
      await closeBook(tester);
      await openBook(tester, data.books[1]);
      expectRowVisible(tester, 'סעיף 0-0');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'refreshing an open nested book after its sections shrink is safe',
      (tester) async {
        final book = data.books[1];
        await mark(book, 157);
        await openBook(tester, book);
        expectRowVisible(tester, 'סעיף 15-7');
        data.replaceNestedBook(
          BookDetails(
            id: book.id,
            contentType: book.contentType,
            parts: book.parts,
            sections: book.sections!.take(3).toList(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a negative stored position opens a nested book at the top', (
      tester,
    ) async {
      final book = data.books[1];
      await ProgressService().saveLastTouchedIndex(book.id!, -1);
      await openBook(tester, book);
      expect(tester.takeException(), isNull);
      expectRowVisible(tester, 'סעיף 0-0');
    });

    testWidgets(
      'restores the saved row when earlier rows have taller headings',
      (tester) async {
        final longHeading = List.filled(40, 'כותרת משנה').join(' ');
        final book = BookDetails(
          id: 7,
          contentType: 'פרק',
          parts: const [],
          sections: [
            for (var i = 0; i < 300; i++)
              _leaf('$i', i < 60 ? 'פרק $i $longHeading' : 'פרק $i'),
          ],
        );
        data.books[0] = book;
        await mark(book, 80);
        await openBook(tester, book);
        expectRowVisible(tester, 'פרק 80');
      },
    );

    test('position survives a new provider (app restart)', () async {
      final book = data.books[0];
      await mark(book, 33);
      final restarted = ShamorZachorProgressProvider(
        progressService: _MemoryProgressService(),
      );
      addTearDown(restarted.dispose);
      await restarted.ensureLoaded();
      expect(restarted.lastTouchedIndexById(book.id!), 33);
      expect(restarted.lastTouchedIndexById(999), isNull);
    });
  });
}
