import 'package:flutter/material.dart';
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
    });
  }

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
  tableOfContents: _toc(),
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

  CommentatorsTab openOn(TextBookTab source, TextBook book) {
    final tabBloc = _LoadingTextBookBloc(
      TextBookInitial.named(book, source.index, false, const []),
      _loaded(book, visibleIndices: [source.index]),
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

  testWidgets('בחירה יחידה נפתחת כמו קודם — על הקטע הנבחר בלבד', (
    tester,
  ) async {
    final book = TextBook(title: 'בראשית');
    final tab = openOn(sourceWith(book, {7}), book);

    expect(await shownIndexes(tester, tab), [7]);
  });

  test('הבחירה המרובה נשמרת לדיסק ומשוחזרת, ו-JSON ישן נטען בלעדיה', () {
    final book = TextBook(title: 'בראשית');
    final tab = openOn(sourceWith(book, {3, 5, 7}), book);

    final json = tab.toJson();
    expect(json['selectedIndices'], [3, 5, 7]);
    final restored = CommentatorsTab.fromJson(json);
    addTearDown(restored.dispose);
    expect(restored.toJson()['selectedIndices'], [3, 5, 7]);

    final legacy = CommentatorsTab.fromJson(
      Map<String, dynamic>.from(json)..remove('selectedIndices'),
    );
    addTearDown(legacy.dispose);
    expect(legacy.toJson()['selectedIndices'], isEmpty);
  });
}
