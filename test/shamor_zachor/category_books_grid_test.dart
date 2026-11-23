import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/category_books_grid.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

import '../support/golden_fonts.dart';

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

  int _completedCycles(int bookId) {
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
      _completedCycles(bookId) == 4;

  @override
  bool isBookConsideredInProgressById(int bookId, BookDetails bookDetails) =>
      progressById[bookId]?.isNotEmpty ?? false;

  @override
  Future<void> clearBookProgressById(int bookId) async {
    clearedBookId = bookId;
    await clearCompleter.future;
  }
}

/// הגדלת טקסט לא-לינארית כמו באנדרואיד 14 ב-200%: גופן קטן מוכפל, גופן של
/// 100 ומעלה לא גדל (הטבלה של FontScaleConverterFactory).
class _AndroidNonlinearTextScaler extends TextScaler {
  const _AndroidNonlinearTextScaler();

  static const _sp = <double>[0, 8, 10, 12, 14, 18, 20, 24, 30, 100];
  static const _dp = <double>[0, 16, 20, 24, 26, 30, 34, 36, 38, 100];

  @override
  double scale(double fontSize) {
    for (var i = 1; i < _sp.length; i++) {
      if (fontSize <= _sp[i]) {
        final t = (fontSize - _sp[i - 1]) / (_sp[i] - _sp[i - 1]);
        return _dp[i - 1] + t * (_dp[i] - _dp[i - 1]);
      }
    }
    return fontSize;
  }

  @override
  double get textScaleFactor => 2.0;
}

void main() {
  testWidgets('removes book locally before async providers finish', (
    tester,
  ) async {
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
              onBookSelected: (_, _, _) {},
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

  testWidgets('renders book card without overflow for completed progress', (
    tester,
  ) async {
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
              onBookSelected: (_, _, _) {},
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

  for (final (name, textScaler) in [
    ('0.85', const TextScaler.linear(0.85)),
    ('1.0', const TextScaler.linear(1.0)),
    ('1.5', const TextScaler.linear(1.5)),
    ('Android 200%', const _AndroidNonlinearTextScaler()),
  ]) {
    testWidgets(
      'scrolling over a book card scrolls the page, and the card shows all '
      'its content (issue #5313, text scale $name)',
      (tester) async {
        await loadGoldenFonts();
        await tester.binding.setSurfaceSize(const Size(432, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const longName = 'ספר עם שם ארוך במיוחד שנפרש על פני שתי שורות בכרטיס';
        BookDetails details(int id) => BookDetails(
          contentType: 'text',
          isCustom: true,
          id: id,
          categoryPath: 'תלמוד בבלי',
          parts: const [BookPart(name: 'ראשי', startPage: 1, endPage: 1)],
        );
        final category = BookCategory(
          name: 'תלמוד בבלי',
          contentType: 'text',
          books: {
            longName: details(1),
            'שבת': details(2),
            for (int id = 3; id <= 12; id++) 'ספר $id': details(id),
          },
          defaultStartPage: 1,
          isCustom: false,
          sourceFile: 'test',
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ShamorZachorDataProvider>.value(
                value: _FakeDataProvider(Completer<void>()),
              ),
              ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
                value: _FakeProgressProvider(
                  Completer<void>(),
                  progressById: {
                    1: {
                      '0': PageProgress(
                        learn: true,
                        review1: true,
                        review2: true,
                        review3: true,
                      ),
                    },
                  },
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppThemeData.light(
                ColorScheme.fromSeed(seedColor: Colors.blue),
                compactMenuMode: false,
              ).copyWith(platform: goldenPlatform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: textScaler),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              ),
              home: Scaffold(
                body: CategoryBooksGrid(
                  categoryName: 'תלמוד בבלי',
                  topLevelName: 'תלמוד בבלי',
                  category: category,
                  onBookSelected: (_, _, _) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final grid = tester.widget<GridView>(find.byType(GridView));
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
        expect(delegate.mainAxisExtent, greaterThanOrEqualTo(264));
        expect(find.text('הושלם'), findsOneWidget);

        // הראשון הוא הדף; האחרים — הגלילה של כל כרטיס.
        final positions = tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .map((state) => state.position)
            .toList();
        final page = positions.first;
        final cards = positions.skip(1).toList();
        expect(cards, isNotEmpty);
        for (final card in cards) {
          expect(card.maxScrollExtent, 0, reason: 'card content is cut off');
        }

        final longCard = tester.getCenter(find.text(longName));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: longCard,
            scrollDelta: const Offset(0, 40),
          ),
        );
        await tester.pumpAndSettle();
        expect(page.pixels, 40);

        await tester.dragFrom(longCard, const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(page.pixels, greaterThan(40));
        for (final card in cards) {
          expect(card.pixels, 0);
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  testWidgets('tracked book appears under "in progress" without any progress', (
    tester,
  ) async {
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
              onBookSelected: (_, _, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ברכות'), findsOneWidget);
  });

  testWidgets(
    'shows in-progress empty state with add hint when no books match',
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
                onBookSelected: (_, _, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ברכות'), findsNothing);
      expect(find.text('אין ספרים בתהליך'), findsOneWidget);
      expect(
        find.byIcon(OtzariaIcons.book_progress_24_regular),
        findsOneWidget,
      );
      expect(find.textContaining('לחצן ההוספה'), findsOneWidget);
    },
  );
}
