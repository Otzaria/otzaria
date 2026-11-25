import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../helpers/memory_settings_cache.dart';

/// פתיחת סימניה מדגישה את השורה שלה רק כשהשורה גלויה בפועל בטאב הפעיל,
/// ומשם נמדד זמן ההדגשה (issue #4455, סיבת הסגירה של #5692).
///
/// [ReadingPosition] הוא החוזה של `LineScrollController`: יעד (`isTarget`)
/// מפורסם עם בקשת הגלילה, ומיקום נמדד רק אחרי שהשורה נפרסה ונחתה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('יעד שלא נמדד 2.2 שניות: ההדגשה מתחילה כשהשורה מופיעה '
      'ונשארת אחרי ההופעה (סיבת הסגירה של #5692)', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);

    // הגלילה התבקשה: היעד פורסם, השורה עוד לא נמדדה ולא הוצגה.
    position.value = ReadingPosition.target(30);
    bloc.add(const HighlightLineWhenVisible(30));
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(_loaded(bloc).highlightedLine, isNull);

    // השורה נפרסה ונמדדה על המסך.
    _show(position, [30, 31, 32]);
    await _waitFor(
      () => _loaded(bloc).highlightedLine == 30,
      description: 'השורה מודגשת כשהיא מופיעה',
    );

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(
      _loaded(bloc).highlightedLine,
      30,
      reason: 'זמן ההדגשה נספר מההופעה, לא מבקשת הגלילה',
    );
    await _waitFor(
      () => _loaded(bloc).highlightedLine == null,
      description: 'ההדגשה רגעית ונעלמת',
    );
  });

  test('בטאב שאינו פעיל ההדגשה ממתינה עד שהוא מקבל מיקוד', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);

    bloc.add(const SetTabVisibility(false));
    bloc.add(const HighlightLineWhenVisible(30));
    _show(position, [30, 31, 32]);
    await _settle();
    expect(_loaded(bloc).highlightedLine, isNull);

    bloc.add(const SetTabVisibility(true));
    await _waitFor(
      () => _loaded(bloc).highlightedLine == 30,
      description: 'השורה מודגשת כשהטאב מקבל מיקוד',
    );
  });

  test('קבוצת סימניות: הדגשת הספר הראשון אינה פגה בזמן שנפתחים '
      'שאר הספרים (סיבת הסגירה של #5692)', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);

    _show(position, [30, 31, 32]);
    bloc.add(const HighlightLineWhenVisible(30));
    await _waitFor(
      () => _loaded(bloc).highlightedLine == 30,
      description: 'הספר הראשון מודגש',
    );

    // שאר ספרי הקבוצה נפתחים ומקבלים מיקוד; הטאב הראשון מוסתר.
    bloc.add(const SetTabVisibility(false));
    await Future<void>.delayed(const Duration(milliseconds: 2200));

    // המיקוד חוזר לספר הראשון.
    bloc.add(const SetTabVisibility(true));
    await _waitFor(
      () => _loaded(bloc).highlightedLine == 30,
      description: 'ההדגשה מוצגת כשהספר חוזר למיקוד',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(_loaded(bloc).highlightedLine, 30);
  });

  test('גלילה למקום אחר לפני הנחיתה לא משאירה הדגשה מאוחרת', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);

    position.value = ReadingPosition.target(30);
    bloc.add(const HighlightLineWhenVisible(30));
    await _settle();

    // המשתמש קטע את הגלילה; המיקום הנמדד אינו כולל את השורה.
    _show(position, [10, 11, 12]);
    await _settle();
    _show(position, [30, 31, 32]);
    await _settle();

    expect(_loaded(bloc).highlightedLine, isNull);
  });

  test('הסתרת הטאב בזמן ניווט לסימניה חדשה משאירה את היעד החדש', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);

    _show(position, [10, 11, 12]);
    bloc.add(const HighlightLineWhenVisible(10));
    await _settle();
    expect(_loaded(bloc).highlightedLine, 10);

    position.value = ReadingPosition.target(30);
    bloc.add(const HighlightLineWhenVisible(30));
    bloc.add(const SetTabVisibility(false));
    await _settle();
    _show(position, [30, 31, 32]);
    bloc.add(const SetTabVisibility(true));
    await _settle();

    expect(_loaded(bloc).highlightedLine, 30);
  });

  test('מעבר בין טאבים אינו מפעיל מחדש הדגשה מיידית רגילה', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);

    _show(position, [10, 11, 12]);
    bloc.add(const HighlightLine(10));
    await _settle();
    expect(_loaded(bloc).highlightedLine, 10);

    bloc.add(const SetTabVisibility(false));
    await Future<void>.delayed(const Duration(milliseconds: 2050));
    bloc.add(const SetTabVisibility(true));
    await _settle();

    expect(_loaded(bloc).highlightedLine, isNull);
  });

  test('ניווט חדש מבטל הדגשת סימניה גם אם היעד הקודם נשאר בחלון', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final navigationEpoch = ValueNotifier<int>(1);
    final bloc = await _loadedBloc(position, navigationEpoch: navigationEpoch);
    addTearDown(bloc.close);

    bloc.add(const SetTabVisibility(false));
    position.value = ReadingPosition.target(30);
    bloc.add(const HighlightLineWhenVisible(30, navigationEpoch: 1));
    await _settle();
    expect(bloc.pendingHighlightLineForTesting, 30);

    navigationEpoch.value++;
    position.value = ReadingPosition.target(29);
    _show(position, [29, 30, 31]);
    bloc.add(const SetTabVisibility(true));
    await _settle();

    expect(bloc.pendingHighlightLineForTesting, isNull);
    expect(_loaded(bloc).highlightedLine, isNull);
  });

  test('טעינת תוכן מלא מתחילה הדגשה בלי פרסום חוזר של המיקום', () async {
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);
    final title = _loaded(bloc).book.title;
    bloc.add(
      ApplyBookContentRange(
        bookTitle: title,
        startLine: 60,
        totalLines: 61,
        lines: const ['שורה 60'],
      ),
    );
    await _waitFor(() => _loaded(bloc).content.length == 61);
    expect(_loaded(bloc).isContentLineLoaded(50), isFalse);

    _show(position, [50, 51, 52]);
    final measured = position.value;
    bloc.add(const HighlightLineWhenVisible(50));
    await _settle();
    expect(_loaded(bloc).highlightedLine, isNull);
    expect(bloc.pendingHighlightLineForTesting, 50);

    bloc.add(
      ApplyFullBookContent(
        bookTitle: title,
        content: List.generate(61, (line) => 'שורה $line'),
      ),
    );
    await _waitFor(() => _loaded(bloc).highlightedLine == 50);
    expect(position.value, same(measured));
  });

  test('שורת סימנייה טעונה בפסקה חלקית ממתינה לכל שורות הפסקה', () async {
    await Settings.setValue<bool>('key-continuous-reading-mode', true);
    final position = ValueNotifier<ReadingPosition?>(null);
    final bloc = await _loadedBloc(position);
    addTearDown(bloc.close);
    const target = 60;
    final title = _loaded(bloc).book.title;
    bloc.add(
      ApplyBookContentRange(
        bookTitle: title,
        startLine: target,
        totalLines: 61,
        lines: const ['שורה 60'],
      ),
    );
    await _waitFor(() => _loaded(bloc).content.length == 61);

    final partial = _loaded(bloc);
    expect(partial.continuousReadingMode, isTrue);
    expect(partial.isContentLineLoaded(target), isTrue);
    final segments = readingSegmentsOf(partial);
    final item = segments.layout.itemForLine(target);
    expect(segments[item].isLoaded, isFalse);
    // הקורא מדווח מיקום משוער של שורות בתוך מציין מקום רב-שורתי.
    final measured = readingPositionFromItems(segments, [
      ItemPosition(index: item, itemLeadingEdge: -5, itemTrailingEdge: 0.05),
    ]);
    expect(measured?.isTarget, isFalse);
    expect(measured?.visibleLines, contains(target));
    position.value = measured;

    bloc.add(const HighlightLineWhenVisible(target));
    await Future<void>.delayed(Duration.zero);
    expect(_loaded(bloc).highlightedLine, isNull);
    expect(bloc.pendingHighlightLineForTesting, target);

    bloc.add(
      ApplyBookContentRange(
        bookTitle: title,
        startLine: 40,
        totalLines: 61,
        lines: List.generate(20, (offset) => 'שורה ${40 + offset}'),
      ),
    );
    await _waitFor(() => _loaded(bloc).highlightedLine == target);
    expect(readingSegmentsOf(_loaded(bloc))[item].isLoaded, isTrue);
    expect(position.value, same(measured));
  });

  test('הטאב מעביר את הבקשה ל-bloc שהוא יוצר', () {
    final tab = TextBookTab(book: TextBook(title: 'ספר בדיקה'), index: 7);
    addTearDown(tab.dispose);

    tab.highlightLineWhenVisible(7);

    expect(tab.highlightWhenVisibleLine, 7);
    expect(tab.bloc.pendingHighlightLineForTesting, 7);
  });
}

TextBookLoaded _loaded(TextBookBloc bloc) => bloc.state as TextBookLoaded;

void _show(ValueNotifier<ReadingPosition?> position, List<int> lines) {
  position.value = ReadingPosition(topLine: lines.first, visibleLines: lines);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

Future<TextBookBloc> _loadedBloc(
  ValueNotifier<ReadingPosition?> position, {
  ValueListenable<int>? navigationEpoch,
}) async {
  final bloc = TextBookBloc(
    repository: _FortyLineRepository(),
    initialState: TextBookInitial.named(
      TextBook(title: 'ספר בדיקה'),
      10,
      false,
      const [],
      searchMode: SearchMode.exact,
      showPageShapeView: false,
    ),
    readingPosition: position,
    readingNavigationEpoch: navigationEpoch,
  );

  bloc.add(
    const LoadContent(
      fontSize: 20,
      showSplitView: false,
      removeNikud: false,
      loadCommentators: false,
    ),
  );

  await _waitFor(() => bloc.state is TextBookLoaded, description: 'loaded');
  return bloc;
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$description not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FortyLineRepository extends TextBookRepository {
  _FortyLineRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<bool> supportsContinuousReadingMode(TextBook book) async => true;

  static final _lines = List.generate(40, (i) => 'שורה $i');

  @override
  Future<String> getBookContent(TextBook book) async => _lines.join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async {
    final start = startLine.clamp(0, _lines.length - 1);
    final end = endLine.clamp(start, _lines.length - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: _lines.length,
      lines: _lines.sublist(start, end + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => [
    TocEntry(text: 'סעיף א', index: 5, level: 1),
  ];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}
