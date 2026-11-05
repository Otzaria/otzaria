import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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
import 'package:provider/provider.dart';

import '../test_helpers/memory_cache_provider.dart';

/// הכלי כפי שהוא יושב באפליקציה: ב־Focus של לשונית הכלי (ToolTabScreen), ליד
/// חלונית צד של החלון, כך שמרכז הכלי אינו מרכז החלון.
const _windowSize = Size(1200, 800);
const _sidePanelWidth = 400.0;

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late SettingsBloc settingsBloc;
  late FocusNode contentFocusNode;
  late FocusNode outsideFocusNode;
  late _FakeProgressProvider progressProvider;

  setUp(() {
    settingsBloc = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
    contentFocusNode = FocusNode(
      debugLabel: 'tool-content',
      skipTraversal: true,
    );
    outsideFocusNode = FocusNode(debugLabel: 'outside');
    progressProvider = _FakeProgressProvider();
  });

  tearDown(() {
    contentFocusNode.dispose();
    outsideFocusNode.dispose();
    settingsBloc.close();
    progressProvider.closeEvents();
  });

  Future<void> pumpTool(WidgetTester tester, {bool showTool = true}) async {
    tester.view.physicalSize = _windowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ShamorZachorDataProvider>(
            create: (_) => _FakeDataProvider(),
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
            value: progressProvider,
          ),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: BlocProvider.value(
                value: settingsBloc,
                child: Row(
                  children: [
                    SizedBox(
                      width: _sidePanelWidth,
                      child: Focus(
                        focusNode: outsideFocusNode,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: Focus(
                        focusNode: contentFocusNode,
                        child: showTool
                            ? ShamorZachorWidget(onTitleChanged: (_) {})
                            : const SizedBox.expand(),
                      ),
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
  }

  Future<void> pressCycleFilter(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> openActiveBook(WidgetTester tester) async {
    await tester.tap(find.text('ספר פעיל'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
  }

  testWidgets('אין לכלי Navigator משלו (DD-29)', (tester) async {
    await pumpTool(tester);

    expect(
      find.descendant(
        of: find.byType(ShamorZachorWidget),
        matching: find.byType(Navigator),
      ),
      findsNothing,
    );
    // המסך הראשי יושב ישר ב־route של החלון.
    final mainContext = tester.element(find.byType(ShamorZachorMainScreen));
    expect(ModalRoute.of(mainContext)!.isFirst, isTrue);
    expect(
      Navigator.of(mainContext),
      same(Navigator.of(tester.element(find.byType(Scaffold).first))),
    );
  });

  testWidgets('חזרה מספר מחזירה לרשימה, ב־Escape ובכפתור החזרה', (
    tester,
  ) async {
    await pumpTool(tester);

    await openActiveBook(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsNothing);
    expect(find.text('ספר פעיל'), findsOneWidget);

    await openActiveBook(tester);
    await tester.tap(find.byTooltip('חזרה'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsNothing);
    expect(find.text('ספר פעיל'), findsOneWidget);
    // ה־route של החלון לא נסגר בדרך.
    expect(find.byType(ShamorZachorWidget), findsOneWidget);
  });

  testWidgets('Escape ברשימה לא סוגר את הכלי', (tester) async {
    await pumpTool(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(ShamorZachorWidget), findsOneWidget);
    expect(find.text('ספר פעיל'), findsOneWidget);
  });

  testWidgets('הקיצור פועל אחרי פתיחה, ואחרי שהלשונית מבקשת פוקוס לכלי', (
    tester,
  ) async {
    await pumpTool(tester);

    // בפתיחה הפוקוס בתוך הכלי.
    expect(contentFocusNode.hasFocus, isTrue);
    expect(find.text('ספר הושלם'), findsNothing);
    await pressCycleFilter(tester);
    expect(find.text('ספר הושלם'), findsOneWidget);

    // הפוקוס יוצא מהכלי — הקיצור לא פועל.
    outsideFocusNode.requestFocus();
    await tester.pump();
    await pressCycleFilter(tester);
    expect(find.text('ספר הושלם'), findsOneWidget);

    // בתוך הכלי, אחרי לחיצה על שדה החיפוש ויציאה ממנו ב־Enter, הקיצור חוזר.
    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await pressCycleFilter(tester);
    // הושלם -> הכל: שני הספרים.
    expect(find.text('ספר הושלם'), findsOneWidget);
    expect(find.text('ספר פעיל'), findsOneWidget);
  });

  // q10 שאלה 19 = C: במרכז הכלי, בלי רקע כהה ובלי חסימת לחיצות.
  testWidgets('אנימציית הסיום במרכז הכלי, בלי שכבה חוסמת', (tester) async {
    await pumpTool(tester);
    await openActiveBook(tester);
    final toolRect = tester.getRect(find.byType(ShamorZachorWidget));

    progressProvider.emit(
      const CompletionEvent(CompletionEventType.bookCompleted, bookId: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    final message = find.text('אשריך! תזכה ללמוד ספרים אחרים ולסיימם!');
    expect(message, findsOneWidget);
    final center = tester.getCenter(message);
    expect(center.dx, moreOrLessEquals(toolRect.center.dx, epsilon: 1));
    expect(center.dy, moreOrLessEquals(toolRect.center.dy, epsilon: 40));
    expect(toolRect.center.dx, isNot(moreOrLessEquals(_windowSize.width / 2)));

    // אין רקע צבוע מתחת להודעה.
    for (final material in tester.widgetList<Material>(
      find.ancestor(of: message, matching: find.byType(Material)),
    )) {
      expect(material.type, MaterialType.transparency);
    }

    // לחיצה בזמן האנימציה עוברת לכלי: "חזרה" סוגר את הספר.
    await tester.tap(find.byTooltip('חזרה'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(BookDetailScreen), findsNothing);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(message, findsNothing);
  });

  testWidgets('סגירת הכלי באמצע אנימציית הסיום', (tester) async {
    await pumpTool(tester);
    await openActiveBook(tester);
    progressProvider.emit(
      const CompletionEvent(
        CompletionEventType.reviewCycleCompleted,
        bookId: 1,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // הלשונית נסגרת: הכלי יוצא מהעץ.
    await pumpTool(tester, showTool: false);
    expect(find.byType(ShamorZachorWidget), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('מזל טוב! הלומד וחוזר כזורע וקוצר!'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakeDataProvider extends ShamorZachorDataProvider {
  static final BookDetails activeBook = BookDetails(
    id: 1,
    contentType: 'text',
    parts: const [BookPart(name: 'ראשי', startPage: 1, endPage: 1)],
    categoryPath: 'בדיקה',
  );

  static final BookDetails completedBook = BookDetails(
    id: 2,
    contentType: 'text',
    parts: const [BookPart(name: 'ראשי', startPage: 1, endPage: 1)],
    categoryPath: 'בדיקה',
  );

  static final Map<String, BookCategory> _categories = {
    'בדיקה': BookCategory(
      name: 'בדיקה',
      contentType: 'text',
      books: {'ספר פעיל': activeBook, 'ספר הושלם': completedBook},
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
  BookDetails? getBookDetails(String categoryName, String bookName) =>
      _categories[categoryName]?.books[bookName];

  /// כמו במקור: BookDetailScreen מאתר את הספר לפי המזהה (#3369).
  @override
  (BookDetails, String, String)? getBookById(int bookId) {
    (BookDetails, String)? find(BookCategory category) {
      for (final book in category.books.entries) {
        if (book.value.id == bookId) return (book.value, book.key);
      }
      for (final sub in category.subcategories ?? const <BookCategory>[]) {
        final found = find(sub);
        if (found != null) return found;
      }
      return null;
    }

    for (final entry in allBookData.entries) {
      final found = find(entry.value);
      if (found != null) return (found.$1, found.$2, entry.key);
    }
    return null;
  }

  @override
  List<BookSearchResult> searchBooks(String query) => const [];
}

class _FakeProgressProvider extends ShamorZachorProgressProvider {
  final _events = StreamController<CompletionEvent>.broadcast();

  static final Map<int, Map<String, PageProgress>> _progressByBookId = {
    1: {'0': PageProgress(learn: true)},
    2: {
      '0': PageProgress(
        learn: true,
        review1: true,
        review2: true,
        review3: true,
      ),
    },
  };

  void emit(CompletionEvent event) => _events.add(event);

  void closeEvents() => _events.close();

  @override
  Stream<CompletionEvent> get completionEvents => _events.stream;

  @override
  bool get isLoading => false;

  @override
  ShamorZachorError? get error => null;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Map<String, PageProgress> getProgressForBookById(int bookId) =>
      _progressByBookId[bookId] ?? const {};

  @override
  PageProgress getProgressForItemById(int bookId, int absoluteIndex) =>
      _progressByBookId[bookId]?[absoluteIndex.toString()] ?? PageProgress();

  @override
  double getLearnProgressPercentageById(int bookId, BookDetails bookDetails) {
    final progress = _progressByBookId[bookId] ?? const {};
    if (progress.isEmpty || bookDetails.totalLearnableItems == 0) return 0.0;
    return progress.values.where((item) => item.learn).length /
        bookDetails.totalLearnableItems;
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
  String? getCompletionDateSyncById(int bookId) =>
      bookId == 2 ? 'א׳ ניסן תשפ"ו' : null;
}
