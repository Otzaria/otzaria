import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../test_helpers/stub_personal_notes_bloc.dart';
import '../../test_helpers/stub_text_book_bloc.dart';
import '../../unit/mocks/mock_settings_repository.mocks.dart';

/// bloc של כרטיסיית המפרשים: נטען רק ב-LoadContent, כמו ה-bloc האמיתי.
class _LoadingTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _LoadingTextBookBloc(super.initialState, TextBookLoaded loaded) {
    on<TextBookEvent>((event, emit) {
      if (event is LoadContent) emit(loaded);
      if (event is LoadAllLinksForIndices) linkLoads.add(event.indices);
    });
  }

  final linkLoads = <List<int>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// ספר → פרק (שורה 0) → פסוקים בני שורה אחת (שורות 1–10).
List<TocEntry> _toc() {
  final root = TocEntry(text: 'ספר', index: 0);
  final chapter = TocEntry(text: 'פרק א', index: 0, level: 2, parent: root);
  root.children.add(chapter);
  for (var i = 1; i <= 10; i++) {
    chapter.children.add(
      TocEntry(text: 'פסוק $i', index: i, level: 3, parent: chapter),
    );
  }
  return [root];
}

TextBookLoaded _loaded(
  TextBook book, {
  int? selectedIndex,
  Set<int> selectedIndices = const {},
  List<int> visibleIndices = const [0],
  List<TocEntry>? toc,
}) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: List.generate(12, (i) => 'שורה $i'),
  fontSize: 25,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: toc ?? _toc(),
  removeNikud: false,
  visibleIndices: visibleIndices,
  selectedIndex: selectedIndex,
  selectedIndices: selectedIndices,
  pinLeftPane: false,
  searchText: '',
);

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  /// מציג את [tab] ומחזיר את השורות שעליהן מוצגים המפרשים.
  Future<List<int>?> shownIndexes(
    WidgetTester tester,
    CommentatorsTab tab,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final settings = SettingsBloc(repository: MockSettingsRepository());
    final notes = StubPersonalNotesBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settings.close();
      await notes.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
          ],
          child: Scaffold(
            body: CommentatorsTabScreen(tab: tab, openBookCallback: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return tester
        .widget<CommentaryListBase>(find.byType(CommentaryListBase))
        .indexes;
  }

  /// טאב ספר שבו נבחרו [selected] (Ctrl+לחיצה), והאחרונה היא העוגן.
  TextBookTab sourceWith(TextBook book, Set<int> selected) {
    final source = TextBookTab(
      book: book,
      index: selected.last,
      blocOverride: StubTextBookBloc(
        _loaded(
          book,
          selectedIndex: selected.last,
          selectedIndices: selected,
          visibleIndices: [selected.last],
        ),
      ),
    );
    addTearDown(source.dispose);
    return source;
  }

  CommentatorsTab openOn(
    TextBookTab source,
    TextBook book, {
    List<TocEntry>? toc,
  }) {
    final tabBloc = _LoadingTextBookBloc(
      TextBookInitial.named(book, source.index, false, const []),
      _loaded(book, visibleIndices: [source.index], toc: toc),
    );
    final tab = CommentatorsTab(sourceTab: source, blocOverride: tabBloc);
    addTearDown(tab.dispose);
    return tab;
  }

  testWidgets('שלושה קטעים שנבחרו ב-Ctrl נפתחים כולם בכרטיסיית המפרשים '
      '(issue #5210)', (tester) async {
    final book = TextBook(title: 'בראשית');
    final tab = openOn(sourceWith(book, {3, 5, 7}), book);

    expect(await shownIndexes(tester, tab), [3, 5, 7]);
  });

  testWidgets(
    'הכרטיסייה מציגה בדיוק את השורות שנבחרו כשהעוגן בתוך פסוק רב-שורות',
    (
      tester,
    ) async {
      final book = TextBook(title: 'בראשית');
      final toc = _toc();
      final verses = toc.single.children.single.children;
      verses.removeWhere((verse) => verse.index == 8 || verse.index == 9);
      final tab = openOn(sourceWith(book, {3, 5, 7}), book, toc: toc);

      expect(await shownIndexes(tester, tab), [3, 5, 7]);
      final bloc = tab.bloc as _LoadingTextBookBloc;
      expect(bloc.linkLoads, [
        [3, 5, 7],
      ]);

      await tester.tap(find.byTooltip('הקטע הבא').first);
      await tester.pump();
      expect(
        tester
            .widget<CommentaryListBase>(find.byType(CommentaryListBase))
            .indexes,
        [10],
      );
    },
  );

  testWidgets('Ctrl בכרטיסייה משנה את בחירת השורות ושומר על העוגן', (
    tester,
  ) async {
    final book = TextBook(title: 'בראשית');
    final tab = openOn(sourceWith(book, {3, 5, 7}), book);
    expect(await shownIndexes(tester, tab), [3, 5, 7]);

    await tester.tap(find.byTooltip('הצג ניווט').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    for (final line in ['שורה 7', 'שורה 5']) {
      final row = find.text(line);
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row.hitTestable());
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      tester
          .widget<CommentaryListBase>(find.byType(CommentaryListBase))
          .indexes,
      [3, 7],
    );
  });

  testWidgets('ספר בלי תוכן עניינים מציג את כל השורות שנבחרו', (tester) async {
    final book = TextBook(title: 'ספר ללא תוכן עניינים');
    final tab = openOn(sourceWith(book, {3, 5, 7}), book, toc: []);

    expect(await shownIndexes(tester, tab), [3, 5, 7]);
  });

  testWidgets('בחירה יחידה נפתחת כמו קודם — על הקטע הנבחר בלבד', (
    tester,
  ) async {
    final book = TextBook(title: 'בראשית');
    final tab = openOn(sourceWith(book, {7}), book);

    expect(await shownIndexes(tester, tab), [7]);
  });

  testWidgets('קיצורי הקטע והפרק בכרטיסייה פועלים כמו חיצי הסרגל '
      '(issue #5796)', (tester) async {
    final book = TextBook(title: 'בראשית');
    final root = TocEntry(text: 'ספר', index: 0);
    for (final (name, start) in [('פרק א', 0), ('פרק ב', 6)]) {
      final chapter = TocEntry(
        text: name,
        index: start,
        level: 2,
        parent: root,
      );
      root.children.add(chapter);
      for (var i = start + 1; i < start + 6; i++) {
        chapter.children.add(
          TocEntry(text: 'פסוק $i', index: i, level: 3, parent: chapter),
        );
      }
    }
    final tab = openOn(sourceWith(book, {3}), book, toc: [root]);
    expect(await shownIndexes(tester, tab), [3]);
    List<int>? shown() => tester
        .widget<CommentaryListBase>(find.byType(CommentaryListBase))
        .indexes;
    Future<void> altPress(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }

    await altPress(LogicalKeyboardKey.arrowDown);
    expect(shown(), [4]);
    await altPress(LogicalKeyboardKey.arrowUp);
    expect(shown(), [3]);
    await altPress(LogicalKeyboardKey.pageDown);
    final nextChapter = shown();
    await altPress(LogicalKeyboardKey.pageUp);
    final prevChapter = shown();

    await tester.tap(find.byTooltip('הפרק הבא').first);
    await tester.pump();
    expect(shown(), nextChapter);
    expect(nextChapter, contains(6));
    await tester.tap(find.byTooltip('הפרק הקודם').first);
    await tester.pump();
    expect(shown(), prevChapter);
    expect(prevChapter, isNot(contains(6)));
  });

  test('פתיחת הכרטיסייה מעתיקה בחירה בלי לשנות את נתוני הסשן', () {
    final book = TextBook(title: 'בראשית');
    final selected = {3, 5, 7};
    final tab = openOn(sourceWith(book, selected), book);
    selected.add(9);

    expect(tab.openingSelection, [3, 5, 7]);
    expect(tab.toJson().containsKey('selectedIndices'), isFalse);
  });
}
