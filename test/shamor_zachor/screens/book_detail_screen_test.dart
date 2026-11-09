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
  BookDetails? book;

  _ReadyDataProvider(this.book);

  void replaceBook(BookDetails? book) {
    this.book = book;
    notifyListeners();
  }

  @override
  (BookDetails, String, String)? getBookById(int bookId) =>
      book?.id == bookId ? (book!, 'ספר', 'הלכה') : null;

  @override
  BookDetails? getBookDetails(String categoryName, String bookName) =>
      categoryName == 'הלכה' && bookName == 'ספר' ? book : null;

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

BookDetails _oneItemBook({
  String title = 'הקדמה',
  int? id = 7,
  bool nested = false,
}) {
  final leaf = BookSection(
    id: 'a',
    title: title,
    level: 1,
    startPage: 0,
    endPage: 0,
    children: const [],
  );
  return BookDetails(
    id: id,
    contentType: 'text',
    parts: const [],
    sections: [
      if (nested)
        BookSection(
          id: 'root',
          title: 'ספר',
          level: 0,
          startPage: 0,
          endPage: 0,
          children: [leaf],
        )
      else
        leaf,
    ],
  );
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('פרטי ספר ללא מזהה נשארים זמינים לתצוגה', (tester) async {
    final data = _ReadyDataProvider(null);
    final progress = ShamorZachorProgressProvider(
      progressService: _MemoryProgressService(),
    );
    addTearDown(data.dispose);
    addTearDown(progress.dispose);
    await progress.ensureLoaded();
    expect(data.getBookDetails('הלכה', 'ספר'), isNull);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShamorZachorDataProvider>.value(value: data),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: progress,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BookDetailScreen(
              topLevelCategoryKey: 'הלכה',
              bookName: 'ספר',
              bookDetails: _oneItemBook(
                title: 'פריט ללא מזהה',
                id: null,
                nested: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('פריט ללא מזהה'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final sameNameBook = _oneItemBook(title: 'פריט מהמאגר', nested: true);
    data.replaceBook(sameNameBook);
    expect(data.getBookDetails('הלכה', 'ספר'), same(sameNameBook));
    await tester.pumpAndSettle();
    expect(find.text('פריט ללא מזהה'), findsOneWidget);
    expect(find.text('פריט מהמאגר'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ספר פתוח משתמש בפרטים החדשים ושומר את ההתקדמות', (tester) async {
    final oldBook = _oneItemBook(title: 'כותרת ישנה', nested: true);
    final data = _ReadyDataProvider(oldBook);
    final service = _MemoryProgressService()
      ..saved = {
        7: {'0': PageProgress(review1: true)},
      };
    final progress = ShamorZachorProgressProvider(progressService: service);
    addTearDown(data.dispose);
    addTearDown(progress.dispose);
    await progress.ensureLoaded();
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
                topLevelCategoryKey: 'הלכה',
                bookName: 'ספר',
                bookId: 7,
                bookDetails: oldBook,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder itemCheckbox(String title, String columnLabel) {
      final row = find
          .ancestor(of: find.text(title), matching: find.byType(Row))
          .first;
      final tooltip = find.descendant(
        of: row,
        matching: find.byTooltip(columnLabel),
      );
      return find.descendant(of: tooltip, matching: find.byType(Checkbox));
    }

    final oldLearn = itemCheckbox('כותרת ישנה', 'לימוד');
    expect(oldLearn, findsOneWidget);
    final oldCheckbox = tester.widget<Checkbox>(oldLearn);
    expect(oldCheckbox.value, isFalse);
    expect(
      tester.widget<Checkbox>(itemCheckbox('כותרת ישנה', 'חזרה 1')).value,
      isTrue,
    );
    data.replaceBook(_oneItemBook(title: 'כותרת חדשה', nested: true));
    oldCheckbox.onChanged!(true);
    await tester.pumpAndSettle();
    expect(service.saved[7]!['0']!.learn, isFalse);
    expect(find.text('כותרת ישנה'), findsNothing);
    expect(find.text('כותרת חדשה'), findsOneWidget);
    await tester.tap(itemCheckbox('כותרת חדשה', 'לימוד'));
    await tester.pump();
    expect(service.saved[7]!['0']!.learn, isTrue);
    expect(service.saved[7]!['0']!.review1, isTrue);
    data.replaceBook(null);
    await tester.pumpAndSettle();
    expect(find.text('פרטי הספר "ספר" לא נמצאו'), findsOneWidget);
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
              create: (_) => _ReadyDataProvider(book),
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
                create: (_) => _ReadyDataProvider(book),
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
              create: (_) => _ReadyDataProvider(_oneItemBook()),
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
            create: (_) => _ReadyDataProvider(_oneItemBook()),
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
    /// The header date of [iso]: the full Hebrew date, or day and month when
    /// the full one does not fit the column (the test font is wide).
    Finder dateText(String iso) {
      final date = DateTime.parse(iso);
      final forms = {
        HebrewUtils.hebrewDate(date),
        HebrewUtils.hebrewDayMonth(date),
      };
      return find.byWidgetPredicate((w) => w is Text && forms.contains(w.data));
    }

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
              create: (_) => _ReadyDataProvider(_oneItemBook()),
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
                  bookDetails: _oneItemBook(),
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
        '2025-03-10',
        '2025-04-11',
        '2025-05-12',
        '2025-06-13',
      ]) {
        expect(dateText(date), findsOneWidget);
      }
      // Each date sits below its own column label (the label's chevron
      // shifts the label's centre by a few pixels).
      expect(
        tester.getCenter(dateText('2025-03-10')).dx,
        closeTo(tester.getCenter(find.text('לימוד')).dx, 10),
      );
      expect(
        tester.getCenter(dateText('2025-06-13')).dy,
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
      expect(dateText('2025-06-13'), findsOneWidget);
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

      expect(dateText('2025-03-10'), findsOneWidget);
      expect(dateText('2025-04-11'), findsOneWidget);
      expect(dateText('2025-05-12'), findsNothing);
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
        dateText(DateTime.now().toIso8601String()),
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
      // Too narrow for the full date: day and month, the full date in the
      // tooltip.
      final date = DateTime.parse('2025-10-28');
      final label = HebrewUtils.hebrewDayMonth(date);
      expect(find.text(label), findsNWidgets(8));
      expect(
        find.byTooltip('הושלם ${HebrewUtils.fullDate(date)}'),
        findsNWidgets(8),
      );
      for (final f in find.text(label).evaluate()) {
        final rect = tester.getRect(find.byWidget(f.widget));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
    });
  });
}
