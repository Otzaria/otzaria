import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/error_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/screens/book_detail_screen.dart';
import 'package:otzaria/tools/shamor_zachor/screens/shamor_zachor_main_screen.dart';
import 'package:otzaria/tools/shamor_zachor/shamor_zachor_widget.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/book_card_widget.dart';
import 'package:otzaria/tools/shamor_zachor/widgets/category_books_grid.dart';
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('Shamor Zachor focus controller', () {
    late SettingsBloc settingsBloc;
    late FocusNode outsideFocusNode;

    setUp(() {
      settingsBloc = SettingsBloc(repository: SettingsRepository())
        ..add(LoadSettings());
      outsideFocusNode = FocusNode(debugLabel: 'outside-focus');
    });

    tearDown(() {
      outsideFocusNode.dispose();
      settingsBloc.close();
    });

    testWidgets('keyboard shortcut works again after focus is restored', (
      tester,
    ) async {
      final focusController = ShamorZachorFocusController();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorDataProvider>(
              create: (_) => _FakeShamorZachorDataProvider(),
            ),
            ChangeNotifierProvider<ShamorZachorProgressProvider>(
              create: (_) => _FakeShamorZachorProgressProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: settingsBloc,
                child: Column(
                  children: [
                    Expanded(
                      child: ShamorZachorMainScreen(
                        focusController: focusController,
                      ),
                    ),
                    Focus(
                      focusNode: outsideFocusNode,
                      child: const SizedBox(width: 1, height: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // ברירת המחדל היא "בתהליך" - מוצג רק הספר הפעיל
      expect(find.text('ספר פעיל'), findsOneWidget);
      expect(find.text('ספר הושלם'), findsNothing);

      outsideFocusNode.requestFocus();
      await tester.pump();

      // המוקד מחוץ למסך - הקיצור לא אמור לפעול, התצוגה נשארת זהה
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.text('ספר פעיל'), findsOneWidget);
      expect(find.text('ספר הושלם'), findsNothing);

      focusController.requestKeyboardFocus();
      await tester.pump();

      // המוקד חזר למסך - הקיצור פועל ומחזר ל"הושלם"
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.text('ספר פעיל'), findsNothing);
      expect(find.text('ספר הושלם'), findsOneWidget);
    });

    testWidgets('book card stays stable with long category path', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorProgressProvider>(
              create: (_) => _FakeShamorZachorProgressProvider(),
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: SizedBox(
                  width: 320,
                  child: BookCardWidget(
                    topLevelCategoryKey: 'בדיקה',
                    categoryName:
                        'נתיב קטגוריה ארוך מאוד עם הרבה מילים כדי לבדוק יציבות במסך צר במיוחד',
                    bookName: 'ספר בדיקה',
                    bookDetails: BookDetails(
                      id: 1,
                      contentType: 'text',
                      parts: const [
                        BookPart(name: 'ראשי', startPage: 1, endPage: 1),
                      ],
                      categoryPath:
                          'נתיב קטגוריה ארוך מאוד עם הרבה מילים כדי לבדוק יציבות במסך צר במיוחד',
                    ),
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ספר בדיקה'), findsOneWidget);
    });

    testWidgets('search keeps duplicate book names from different categories', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorDataProvider>(
              create: (_) => _FakeShamorZachorDataProvider(),
            ),
            ChangeNotifierProvider<ShamorZachorProgressProvider>(
              create: (_) => _FakeShamorZachorProgressProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: settingsBloc,
                child: const ShamorZachorMainScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // ברירת המחדל היא "בתהליך" - נעבור ל"הכל" כדי לחפש בכל הספרים
      await tester.tap(find.text('הכל'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).first, 'ספר כפול');
      await tester.pumpAndSettle();

      expect(find.byType(BookCardWidget), findsNWidgets(2));
      expect(find.text('קטגוריה א'), findsWidgets);
      expect(find.text('קטגוריה ב'), findsWidgets);
    });

    testWidgets('space key is not swallowed while typing in search field', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorDataProvider>(
              create: (_) => _FakeShamorZachorDataProvider(),
            ),
            ChangeNotifierProvider<ShamorZachorProgressProvider>(
              create: (_) => _FakeShamorZachorProgressProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: settingsBloc,
                child: const ShamorZachorMainScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // מיקוד שדה החיפוש
      await tester.tap(find.byType(EditableText).first);
      await tester.pumpAndSettle();

      // הקלדת רווח אסור שתיתפס על-ידי מטפל המקלדת של החלון (גלילת תוכן),
      // אחרת המנוע מבטל את הוספת תו הרווח לשדה.
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(handled, isFalse);
    });

    testWidgets(
      'PageDown, PageUp ו-Ctrl+חצים גוללים את התוכן כשהסרגל פתוח',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ShamorZachorDataProvider>(
                create: (_) => _ManyBooksDataProvider(),
              ),
              ChangeNotifierProvider<ShamorZachorProgressProvider>(
                create: (_) => _FakeShamorZachorProgressProvider(),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: BlocProvider.value(
                  value: settingsBloc,
                  child: const ShamorZachorMainScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        ScrollPosition scrollIn(Type view) => tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(view),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        // Ctrl+חצים (Cmd ב-macOS) הם קיצורי הגלילה המובנים של Flutter.
        final modifier = defaultTargetPlatform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        Future<void> press(
          LogicalKeyboardKey key, {
          bool modified = false,
        }) async {
          if (modified) await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(key);
          if (modified) await tester.sendKeyUpEvent(modifier);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        Future<void> expectKeysScroll(ScrollPosition position) async {
          await press(LogicalKeyboardKey.pageDown);
          expect(position.pixels, greaterThan(0));
          await press(LogicalKeyboardKey.pageUp);
          expect(position.pixels, 0);
          await press(LogicalKeyboardKey.arrowDown, modified: true);
          expect(position.pixels, greaterThan(0));
          await press(LogicalKeyboardKey.arrowUp, modified: true);
          expect(position.pixels, 0);
        }

        await expectKeysScroll(scrollIn(CategoryBooksGrid));

        // גם בפרטי ספר פתוח המקשים גוללים את רשימת העמודים
        await tester.tap(find.text('ספר 0'));
        await tester.pumpAndSettle();
        await expectKeysScroll(scrollIn(BookDetailScreen));

        // ובתוצאות חיפוש, אחרי ש-Enter מחזיר את המוקד לחלון
        await tester.enterText(find.byType(EditableText).first, 'ספר');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await expectKeysScroll(scrollIn(CategoryBooksGrid));
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.android,
      }),
    );

    testWidgets('retry reloads progress error state', (tester) async {
      final progressProvider = _RetryableShamorZachorProgressProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorDataProvider>(
              create: (_) => _FakeShamorZachorDataProvider(),
            ),
            ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
              value: progressProvider,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: settingsBloc,
                child: const ShamorZachorMainScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('שגיאה בטעינת הנתונים'), findsOneWidget);

      await tester.tap(find.text('נסה שוב'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(progressProvider.retryCallCount, 1);
      expect(find.text('שגיאה בטעינת הנתונים'), findsNothing);
      expect(find.text('ספר פעיל'), findsOneWidget);
    });

    testWidgets('book card recomputes state for a different book widget', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorProgressProvider>(
              create: (_) => _FakeShamorZachorProgressProvider(),
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: SizedBox(
                  width: 320,
                  child: BookCardWidget(
                    topLevelCategoryKey: 'בדיקה',
                    categoryName: 'בדיקה',
                    bookName: 'ספר פעיל',
                    bookDetails: _FakeShamorZachorDataProvider._activeBook,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('הושלם'), findsNothing);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ShamorZachorProgressProvider>(
              create: (_) => _FakeShamorZachorProgressProvider(),
            ),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: SizedBox(
                  width: 320,
                  child: BookCardWidget(
                    topLevelCategoryKey: 'בדיקה',
                    categoryName: 'בדיקה',
                    bookName: 'ספר הושלם',
                    bookDetails: _FakeShamorZachorDataProvider._completedBook,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('הושלם'), findsOneWidget);
    });
  });
}

class _FakeShamorZachorDataProvider extends ShamorZachorDataProvider {
  static final BookDetails _activeBook = BookDetails(
    id: 1,
    contentType: 'text',
    parts: const [
      BookPart(name: 'ראשי', startPage: 1, endPage: 1),
    ],
    categoryPath: 'בדיקה',
  );

  static final BookDetails _completedBook = BookDetails(
    id: 2,
    contentType: 'text',
    parts: const [
      BookPart(name: 'ראשי', startPage: 1, endPage: 1),
    ],
    categoryPath: 'בדיקה',
  );

  static final BookDetails _duplicateBookA = BookDetails(
    id: 3,
    contentType: 'text',
    parts: const [
      BookPart(name: 'ראשי', startPage: 1, endPage: 1),
    ],
    categoryPath: 'קטגוריה א',
  );

  static final BookDetails _duplicateBookB = BookDetails(
    id: 4,
    contentType: 'text',
    parts: const [
      BookPart(name: 'ראשי', startPage: 1, endPage: 1),
    ],
    categoryPath: 'קטגוריה ב',
  );

  static final Map<String, BookCategory> _categories = {
    'בדיקה': BookCategory(
      name: 'בדיקה',
      contentType: 'text',
      books: {
        'ספר פעיל': _activeBook,
        'ספר הושלם': _completedBook,
      },
      defaultStartPage: 1,
      isCustom: false,
      sourceFile: 'test',
      schemaVersion: 1,
    ),
    'כפולים': BookCategory(
      name: 'כפולים',
      contentType: 'text',
      books: const {},
      subcategories: [
        BookCategory(
          name: 'קטגוריה א',
          contentType: 'text',
          books: {
            'ספר כפול': _duplicateBookA,
          },
          defaultStartPage: 1,
          isCustom: false,
          sourceFile: 'test',
          schemaVersion: 1,
        ),
        BookCategory(
          name: 'קטגוריה ב',
          contentType: 'text',
          books: {
            'ספר כפול': _duplicateBookB,
          },
          defaultStartPage: 1,
          isCustom: false,
          sourceFile: 'test',
          schemaVersion: 1,
        ),
      ],
      defaultStartPage: 1,
      isCustom: false,
      sourceFile: 'test',
      schemaVersion: 1,
    ),
  };

  @override
  Map<String, BookCategory> get allBookData => _categories;

  @override
  bool get isLoading => false;

  @override
  ShamorZachorError? get error => null;

  @override
  Future<void> ensureLoaded() async {}

  @override
  BookDetails? getBookDetails(String categoryName, String bookName) {
    return _categories[categoryName]?.books[bookName];
  }

  @override
  List<BookSearchResult> searchBooks(String query) {
    if (query.isEmpty) return const [];

    final results = <BookSearchResult>[];
    for (final entry in allBookData.entries) {
      _collectSearchResults(entry.value, query, results, entry.key);
    }
    return results;
  }

  void _collectSearchResults(
    BookCategory category,
    String query,
    List<BookSearchResult> results,
    String topLevelCategoryName,
  ) {
    for (final book in category.books.entries) {
      if (book.key.contains(query)) {
        results.add(
          BookSearchResult(
            book.value,
            category.name,
            category,
            book.key,
            topLevelCategoryName,
          ),
        );
      }
    }

    for (final subcategory
        in category.subcategories ?? const <BookCategory>[]) {
      _collectSearchResults(
        subcategory,
        query,
        results,
        topLevelCategoryName,
      );
    }
  }
}

/// קטגוריה אחת עם מספיק ספרים במעקב כדי שיהיה מה לגלול בתוכן.
class _ManyBooksDataProvider extends _FakeShamorZachorDataProvider {
  @override
  final Map<String, BookCategory> allBookData = {
    'רבים': BookCategory(
      name: 'רבים',
      contentType: 'text',
      books: {
        for (var i = 0; i < 30; i++)
          'ספר $i': BookDetails(
            id: 100 + i,
            contentType: 'text',
            parts: [
              BookPart(name: 'ראשי', startPage: 1, endPage: i == 0 ? 100 : 1),
            ],
            categoryPath: 'רבים',
          ),
      },
      defaultStartPage: 1,
      isCustom: false,
      sourceFile: 'test',
      schemaVersion: 1,
    ),
  };

  @override
  bool isBookTrackedById(int bookId) => true;
}

class _FakeShamorZachorProgressProvider extends ShamorZachorProgressProvider {
  static final Map<int, Map<String, PageProgress>> _progressByBookId = {
    1: {
      '0': PageProgress(learn: true),
    },
    2: {
      '0': PageProgress(
        learn: true,
        review1: true,
        review2: true,
        review3: true,
      ),
    },
    3: {
      '0': PageProgress(),
    },
    4: {
      '0': PageProgress(),
    },
  };

  _FakeShamorZachorProgressProvider() : super();
  @override
  bool get isLoading => false;

  @override
  ShamorZachorError? get error => null;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Map<String, PageProgress> getProgressForBookById(int bookId) {
    return _progressByBookId[bookId] ?? const {};
  }

  @override
  PageProgress getProgressForItemById(int bookId, int absoluteIndex) {
    return _progressByBookId[bookId]?[absoluteIndex.toString()] ??
        PageProgress();
  }

  @override
  double getLearnProgressPercentageById(int bookId, BookDetails bookDetails) {
    final progress = _progressByBookId[bookId] ?? const {};
    if (progress.isEmpty || bookDetails.totalLearnableItems == 0) {
      return 0.0;
    }

    final learned = progress.values.where((item) => item.learn).length;
    return learned / bookDetails.totalLearnableItems;
  }

  @override
  bool isBookCompletedById(int bookId, BookDetails bookDetails) {
    final progress = _progressByBookId[bookId] ?? const {};
    if (progress.isEmpty) return false;
    return progress.values.every(
      (item) => item.isCompleteFor(['learn', 'review1', 'review2', 'review3']),
    );
  }

  @override
  bool isBookConsideredInProgressById(int bookId, BookDetails bookDetails) {
    final progress = _progressByBookId[bookId] ?? const {};
    if (progress.isEmpty) return false;
    return progress.values.any((item) => !item.isEmpty) &&
        !isBookCompletedById(bookId, bookDetails);
  }

  @override
  String? getCompletionDateSyncById(int bookId) {
    return bookId == 2 ? 'א׳ ניסן תשפ"ו' : null;
  }
}

class _RetryableShamorZachorProgressProvider
    extends _FakeShamorZachorProgressProvider {
  ShamorZachorError? _currentError = ShamorZachorError(
    type: ShamorZachorErrorType.storageUnavailable,
    message: 'progress load failed',
  );
  int retryCallCount = 0;

  @override
  ShamorZachorError? get error => _currentError;

  @override
  Future<void> retry() async {
    retryCallCount++;
    _currentError = null;
    notifyListeners();
  }
}
