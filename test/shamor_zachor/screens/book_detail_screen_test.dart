import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/screens/book_detail_screen.dart';
import 'package:otzaria/tools/shamor_zachor/services/progress_service.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/hebrew_utils.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MemoryProgressService extends ProgressService {
  ProgressMapById saved = {};
  CompletionDatesByIdMap completionDates = {};
  ColumnCompletionDatesMap columnDates = {};
  Map<int, List<ProgressColumn>> columns = {};

  @override
  Future<ProgressMapById> loadProgressDataById() async => saved;

  @override
  Future<CompletionDatesByIdMap> loadCompletionDatesById() async =>
      completionDates;

  @override
  Future<Map<int, List<ProgressColumn>>> loadColumnsByBookId() async => columns;

  @override
  Future<ColumnCompletionDatesMap> loadColumnCompletionDates() async =>
      columnDates;

  @override
  Future<void> saveColumnCompletionDates(
    ColumnCompletionDatesMap dates,
  ) async => columnDates = dates;

  @override
  Future<void> saveCompletionDateById(int bookId, String date) async =>
      completionDates[bookId] = date;

  @override
  Future<void> saveProgressDataById(ProgressMapById data) async => saved = data;
}

class _ReadyDataProvider extends ShamorZachorDataProvider {
  @override
  bool get isLoading => false;
}

/// ספר בצורת בן איש חי: כותרת-על אחת = שם הספר, שנים, פרשיות והלכות.
BookDetails _manyHeadingsBook() {
  var id = 0;
  BookSection node(String title, int level, List<BookSection> children) =>
      BookSection(
        id: '${id++}',
        title: title,
        level: level,
        startPage: 0,
        endPage: 0,
        children: children,
      );
  return BookDetails(
    id: 7,
    contentType: 'text',
    parts: const [],
    sections: [
      node('בן איש חי', 1, [
        for (var y = 0; y < 2; y++)
          node('שנה $y', 2, [
            for (var p = 0; p < 50; p++)
              node('פרשה $y-$p', 3, [
                for (var h = 0; h < 20; h++) node('הלכה $y-$p-$h', 4, const []),
              ]),
          ]),
      ]),
    ],
  );
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets(
    'ספר מרובה כותרות בונה רק את השורות הנראות (issue #2068)',
    (tester) async {
      final service = _MemoryProgressService();
      final progress = ShamorZachorProgressProvider(progressService: service);
      await progress.ensureLoaded();
      final book = _manyHeadingsBook();
      expect(book.learnableItems, hasLength(2000));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorDataProvider>(
              create: (_) => _ReadyDataProvider(),
            ),
            ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
              value: progress,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BookDetailScreen(
                topLevelCategoryKey: 'הלכה',
                bookName: 'בן איש חי',
                bookId: 7,
                bookDetails: book,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final built = find.byType(Checkbox, skipOffstage: false);
      expect(built.evaluate().length, lessThan(300));

      await tester.tap(find.byType(Checkbox).at(8));
      await tester.pumpAndSettle();
      expect(service.saved[7], isNotEmpty);

      await tester.tap(find.text('שנה 0'));
      await tester.pumpAndSettle();
      expect(find.text('פרשה 0-0'), findsNothing);
      expect(find.text('שנה 1'), findsOneWidget);
    },
  );

  for (final hideBookHeading in [false, true]) {
    testWidgets(
      'שורות משנה שומרות על צפיפותן (כותרת ספר מוסתרת: $hideBookHeading)',
      (tester) async {
        BookSection section(
          String title,
          int level, [
          List<BookSection> children = const [],
        ]) => BookSection(
          id: title,
          title: title,
          level: level,
          startPage: 0,
          endPage: 0,
          children: children,
        );
        final sections = [
          section('הקדמה', 1),
          section('פרק', 1, [section('הלכה', 2)]),
        ];
        final book = BookDetails(
          id: 7,
          contentType: 'text',
          parts: const [],
          sections: hideBookHeading ? [section('ספר', 0, sections)] : sections,
        );
        final progress = ShamorZachorProgressProvider(
          progressService: _MemoryProgressService(),
        );
        addTearDown(progress.dispose);
        await progress.ensureLoaded();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ShamorZachorDataProvider>(
                create: (_) => _ReadyDataProvider(),
              ),
              ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
                value: progress,
              ),
            ],
            child: MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: BookDetailScreen(
                    topLevelCategoryKey: 'הלכה',
                    bookName: 'ספר',
                    bookId: 7,
                    bookDetails: book,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Finder leafRow(String title) => find
            .ancestor(of: find.text(title), matching: find.byType(Row))
            .first;
        expect(tester.getSize(leafRow('הקדמה')).height, 40);
        expect(tester.getSize(leafRow('הלכה')).height, 32);
      },
    );
  }

  for (final completed in [true, false]) {
    testWidgets('תאריך השלמה בטבלה מוצג רק כשהלימוד הושלם ($completed)', (
      tester,
    ) async {
      final service = _MemoryProgressService();
      if (completed) service.completionDates = {7: '2025-03-10T09:00:00'};
      final progress = ShamorZachorProgressProvider(progressService: service);
      addTearDown(progress.dispose);
      await progress.ensureLoaded();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorDataProvider>(
              create: (_) => _ReadyDataProvider(),
            ),
            ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
              value: progress,
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: BookDetailScreen(
                  topLevelCategoryKey: 'הלכה',
                  bookName: 'ספר',
                  bookId: 7,
                  bookDetails: BookDetails(
                    id: 7,
                    contentType: 'text',
                    parts: const [],
                    sections: [
                      BookSection(
                        id: 'a',
                        title: 'הקדמה',
                        level: 1,
                        startPage: 0,
                        endPage: 0,
                        children: const [],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('הושלם'),
        completed ? findsOneWidget : findsNothing,
      );
      if (completed) expect(find.textContaining('10.03.2025'), findsOneWidget);
    });
  }

  testWidgets('שורת ההשלמה בתחתית הטבלה לא גולשת ברוחב צר', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(300, 600);
    addTearDown(tester.view.reset);
    final service = _MemoryProgressService()
      ..completionDates = {7: '2025-03-10T09:00:00'};
    final progress = ShamorZachorProgressProvider(progressService: service);
    addTearDown(progress.dispose);
    await progress.ensureLoaded();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShamorZachorDataProvider>(
            create: (_) => _ReadyDataProvider(),
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: progress,
          ),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: BookDetailScreen(
                topLevelCategoryKey: 'הלכה',
                bookName: 'ספר',
                bookId: 7,
                bookDetails: BookDetails(
                  id: 7,
                  contentType: 'text',
                  parts: const [],
                  sections: [
                    BookSection(
                      id: 'a',
                      title: 'הקדמה',
                      level: 1,
                      startPage: 0,
                      endPage: 0,
                      children: const [],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final footer = find.textContaining('הושלם');
    expect(footer, findsOneWidget);
    expect(tester.getRect(footer).right, lessThanOrEqualTo(300));
    expect(tester.getRect(footer).left, greaterThanOrEqualTo(0));
  });
  group('column completion dates in the header', () {
    String hebrew(String iso) => HebrewUtils.hebrewDate(DateTime.parse(iso));

    BookDetails oneItemBook() => BookDetails(
      id: 7,
      contentType: 'text',
      parts: const [],
      sections: [
        BookSection(
          id: 'a',
          title: 'הקדמה',
          level: 1,
          startPage: 0,
          endPage: 0,
          children: const [],
        ),
      ],
    );

    Future<void> pumpScreen(
      WidgetTester tester,
      _MemoryProgressService service,
    ) async {
      final progress = ShamorZachorProgressProvider(progressService: service);
      addTearDown(progress.dispose);
      await progress.ensureLoaded();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorDataProvider>(
              create: (_) => _ReadyDataProvider(),
            ),
            ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
              value: progress,
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: BookDetailScreen(
                  topLevelCategoryKey: 'הלכה',
                  bookName: 'ספר',
                  bookId: 7,
                  bookDetails: oneItemBook(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('every complete column shows its own date under its label', (
      tester,
    ) async {
      final service = _MemoryProgressService()
        ..saved = {
          7: {
            '0': PageProgress(
              learn: true,
              review1: true,
              review2: true,
              review3: true,
            ),
          },
        }
        ..columnDates = {
          7: {
            'learn': '2025-03-10T09:00:00',
            'review1': '2025-04-11T09:00:00',
            'review2': '2025-05-12T09:00:00',
            'review3': '2025-06-13T09:00:00',
          },
        };
      await pumpScreen(tester, service);

      for (final date in [
        hebrew('2025-03-10'),
        hebrew('2025-04-11'),
        hebrew('2025-05-12'),
        hebrew('2025-06-13'),
      ]) {
        expect(find.text(date), findsOneWidget);
      }
      // Each date sits below its own column label (the label's chevron
      // shifts the label's centre by a few pixels).
      expect(
        tester.getCenter(find.text(hebrew('2025-03-10'))).dx,
        closeTo(tester.getCenter(find.text('לימוד')).dx, 10),
      );
      expect(
        tester.getCenter(find.text(hebrew('2025-06-13'))).dy,
        greaterThan(tester.getCenter(find.text('חזרה 3')).dy),
      );
    });

    testWidgets('the whole-book footer shows below the per-column dates', (
      tester,
    ) async {
      final service = _MemoryProgressService()
        ..completionDates = {7: '2025-06-13T09:00:00'}
        ..saved = {
          7: {
            '0': PageProgress(
              learn: true,
              review1: true,
              review2: true,
              review3: true,
            ),
          },
        }
        ..columnDates = {
          7: {
            'learn': '2025-03-10T09:00:00',
            'review3': '2025-06-13T09:00:00',
          },
        };
      await pumpScreen(tester, service);

      expect(find.textContaining('הושלם'), findsOneWidget);
      expect(find.text(hebrew('2025-06-13')), findsOneWidget);
    });

    testWidgets('only complete columns show a date', (tester) async {
      final service = _MemoryProgressService()
        ..saved = {
          7: {'0': PageProgress(learn: true, review1: true)},
        }
        ..columnDates = {
          7: {
            'learn': '2025-03-10T09:00:00',
            'review1': '2025-04-11T09:00:00',
            // Stale entry for a column that is not complete: never shown.
            'review2': '2025-05-12T09:00:00',
          },
        };
      await pumpScreen(tester, service);

      expect(find.text(hebrew('2025-03-10')), findsOneWidget);
      expect(find.text(hebrew('2025-04-11')), findsOneWidget);
      expect(find.text(hebrew('2025-05-12')), findsNothing);
    });

    testWidgets('no complete column shows no date line', (tester) async {
      final service = _MemoryProgressService();
      await pumpScreen(tester, service);

      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').startsWith('הושלם'),
        ),
        findsNothing,
      );
    });

    testWidgets('a complete column with no saved date shows none', (
      tester,
    ) async {
      final service = _MemoryProgressService()
        ..saved = {
          7: {'0': PageProgress(learn: true)},
        };
      await pumpScreen(tester, service);

      expect(tester.takeException(), isNull);
      expect(find.text('לימוד'), findsOneWidget);
    });

    testWidgets('marking the last item stamps the date shown in the header', (
      tester,
    ) async {
      final service = _MemoryProgressService();
      await pumpScreen(tester, service);

      // First row checkbox of the "learn" column (header checkbox is at 0).
      await tester.tap(find.byType(Checkbox).at(4));
      await tester.pumpAndSettle();

      expect(
        find.text(HebrewUtils.hebrewDate(DateTime.now())),
        findsOneWidget,
      );
    });

    testWidgets('eight dated columns fit a narrow screen', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 600);
      addTearDown(tester.view.reset);
      final columns = [
        for (var i = 0; i < 8; i++)
          ProgressColumn(id: 'c$i', label: i == 0 ? 'לימוד' : 'חזרה $i'),
      ];
      final service = _MemoryProgressService()
        ..columns = {7: columns}
        ..saved = {
          7: {
            '0': PageProgress.fromJson({for (final c in columns) c.id: true}),
          },
        }
        ..columnDates = {
          7: {for (final c in columns) c.id: '2025-10-28T09:00:00'},
        };
      await pumpScreen(tester, service);

      expect(tester.takeException(), isNull);
      final label = hebrew('2025-10-28');
      expect(find.text(label), findsNWidgets(8));
      for (final f in find.text(label).evaluate()) {
        final rect = tester.getRect(find.byWidget(f.widget));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
    });
  });
}
