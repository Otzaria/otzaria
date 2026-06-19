import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/category_books_grid.dart';

class _FakeDataProvider extends ShamorZachorDataProvider {
  _FakeDataProvider(this.removeCompleter, {this.trackedIds = const {}});

  final Completer<void> removeCompleter;
  final Set<int> trackedIds;
  int? removedBookId;

  @override
  bool isBookTrackedById(int bookId) => trackedIds.contains(bookId);

  @override
  Future<void> removeBookFromTracking(int bookId) async {
    removedBookId = bookId;
    await removeCompleter.future;
  }
}

class _FakeProgressProvider extends ShamorZachorProgressProvider {
  _FakeProgressProvider(this.clearCompleter, {this.progressById = const {}});

  final Completer<void> clearCompleter;
  final Map<int, Map<String, PageProgress>> progressById;
  int? clearedBookId;

  @override
  Map<String, PageProgress> getProgressForBookById(int bookId) => {};

  @override
  PageProgress getProgressForItemById(int bookId, int absoluteIndex) {
    return progressById[bookId]?[absoluteIndex.toString()] ?? PageProgress();
  }

  @override
  double getLearnProgressPercentageById(int bookId, BookDetails bookDetails) {
    final progress = progressById[bookId] ?? const <String, PageProgress>{};
    if (bookDetails.totalLearnableItems == 0) {
      return 0.0;
    }

    final completed = progress.values.where((item) => item.learn).length;
    return completed / bookDetails.totalLearnableItems;
  }

  @override
  int getNumberOfCompletedCyclesById(int bookId, BookDetails bookDetails) {
    final progress = progressById[bookId] ?? const <String, PageProgress>{};
    if (progress.isEmpty) {
      return 0;
    }

    int cycles = 0;
    final items = progress.values.toList();
    if (items.every((item) => item.learn)) cycles++;
    if (items.every((item) => item.review1)) cycles++;
    if (items.every((item) => item.review2)) cycles++;
    if (items.every((item) => item.review3)) cycles++;
    return cycles;
  }

  @override
  String? getCompletionDateSyncById(int bookId) => null;

  @override
  bool isBookCompletedById(int bookId, BookDetails bookDetails) =>
      getNumberOfCompletedCyclesById(bookId, bookDetails) == 4;

  @override
  bool isBookConsideredInProgressById(int bookId, BookDetails bookDetails) =>
      progressById[bookId]?.isNotEmpty ?? false;

  @override
  Future<void> clearBookProgressById(
    int bookId, {
    String? categoryName,
    String? bookName,
    BookDetails? bookDetails,
  }) async {
    clearedBookId = bookId;
    await clearCompleter.future;
  }
}

void main() {
  testWidgets('removes book locally before async providers finish',
      (tester) async {
    final removeCompleter = Completer<void>();
    final clearCompleter = Completer<void>();
    final dataProvider = _FakeDataProvider(removeCompleter);
    final progressProvider = _FakeProgressProvider(clearCompleter);

    final category = BookCategory(
      name: 'תלמוד בבלי',
      contentType: 'text',
      books: {
        'ברכות': BookDetails(
          contentType: 'text',
          isCustom: true,
          id: 42,
          categoryPath: 'תלמוד בבלי',
          parts: const [
            BookPart(name: 'ראשי', startPage: 1, endPage: 1),
          ],
        ),
      },
      defaultStartPage: 1,
      isCustom: false,
      sourceFile: 'test',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: dataProvider,
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: progressProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CategoryBooksGrid(
              categoryName: 'תלמוד בבלי',
              topLevelName: 'תלמוד בבלי',
              category: category,
              onBookSelected: (_, __, ___) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ברכות'), findsOneWidget);

    await tester.tap(find.byTooltip('הסר ספר'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('הסר'));
    await tester.pumpAndSettle();

    expect(find.text('ברכות'), findsNothing);
    expect(progressProvider.clearedBookId, 42);

    clearCompleter.complete();
    removeCompleter.complete();
    await tester.pumpAndSettle();

    expect(dataProvider.removedBookId, 42);
  });

  testWidgets('renders book card without overflow for completed progress',
      (tester) async {
    final removeCompleter = Completer<void>();
    final clearCompleter = Completer<void>();
    final dataProvider = _FakeDataProvider(removeCompleter);
    final progressProvider = _FakeProgressProvider(
      clearCompleter,
      progressById: {
        42: {
          '0': PageProgress(
            learn: true,
            review1: true,
            review2: true,
            review3: true,
          ),
        },
      },
    );

    final category = BookCategory(
      name: 'תלמוד בבלי',
      contentType: 'text',
      books: {
        'שפה לנאמנים': BookDetails(
          contentType: 'text',
          isCustom: true,
          id: 42,
          categoryPath: 'תלמוד בבלי',
          parts: const [
            BookPart(name: 'ראשי', startPage: 1, endPage: 1),
          ],
        ),
      },
      defaultStartPage: 1,
      isCustom: false,
      sourceFile: 'test',
    );

    await tester.binding.setSurfaceSize(const Size(900, 700));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: dataProvider,
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: progressProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CategoryBooksGrid(
              categoryName: 'תלמוד בבלי',
              topLevelName: 'תלמוד בבלי',
              category: category,
              onBookSelected: (_, __, ___) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('שפה לנאמנים'), findsOneWidget);
    expect(tester.takeException(), isNull);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('tracked book appears under "in progress" without any progress',
      (tester) async {
    final dataProvider = _FakeDataProvider(Completer<void>(), trackedIds: {42});
    final progressProvider = _FakeProgressProvider(Completer<void>());

    final category = BookCategory(
      name: 'תלמוד בבלי',
      contentType: 'text',
      books: {
        'ברכות': BookDetails(
          contentType: 'text',
          isCustom: true,
          id: 42,
          categoryPath: 'תלמוד בבלי',
          parts: const [
            BookPart(name: 'ראשי', startPage: 1, endPage: 1),
          ],
        ),
      },
      defaultStartPage: 1,
      isCustom: false,
      sourceFile: 'test',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: dataProvider,
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: progressProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CategoryBooksGrid(
              categoryName: 'תלמוד בבלי',
              topLevelName: 'תלמוד בבלי',
              category: category,
              selectedFilter: 'in_progress',
              onBookSelected: (_, __, ___) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ברכות'), findsOneWidget);
  });

  testWidgets('shows in-progress empty state with add hint when no books match',
      (tester) async {
    final dataProvider = _FakeDataProvider(Completer<void>());
    final progressProvider = _FakeProgressProvider(Completer<void>());

    final category = BookCategory(
      name: 'תלמוד בבלי',
      contentType: 'text',
      books: {
        'ברכות': BookDetails(
          contentType: 'text',
          isCustom: false,
          id: 42,
          categoryPath: 'תלמוד בבלי',
          parts: const [
            BookPart(name: 'ראשי', startPage: 1, endPage: 1),
          ],
        ),
      },
      defaultStartPage: 1,
      isCustom: false,
      sourceFile: 'test',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(
            value: dataProvider,
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: progressProvider,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CategoryBooksGrid(
              categoryName: 'תלמוד בבלי',
              topLevelName: 'תלמוד בבלי',
              category: category,
              selectedFilter: 'in_progress',
              onBookSelected: (_, __, ___) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ברכות'), findsNothing);
    expect(find.text('אין ספרים בתהליך'), findsOneWidget);
    expect(find.textContaining('לחצן ההוספה'), findsOneWidget);
  });
}
