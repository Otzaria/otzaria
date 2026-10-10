import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/screens/book_detail_screen.dart';
import 'package:otzaria/tools/shamor_zachor/services/progress_service.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MemoryProgressService extends ProgressService {
  ProgressMapById saved = {};

  @override
  Future<ProgressMapById> loadProgressDataById() async => saved;

  @override
  Future<CompletionDatesByIdMap> loadCompletionDatesById() async => {};

  @override
  Future<Map<int, List<ProgressColumn>>> loadColumnsByBookId() async => {};

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
                categoryName: 'הלכה',
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
                    categoryName: 'הלכה',
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
}
