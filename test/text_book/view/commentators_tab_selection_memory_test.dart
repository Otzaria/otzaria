import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
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

const _all = ['רש"י', 'רמב"ן', 'אבן עזרא'];

TextBookLoaded _loaded(TextBook book) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: List.generate(3, (i) => 'שורה $i'),
  fontSize: 25,
  showSplitView: false,
  activeCommentators: const ['רש"י'],
  commentatorGroups: const [],
  availableCommentators: _all,
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  searchText: '',
);

void main() {
  late Directory dataRoot;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() async {
    dataRoot = await Directory.systemTemp.createTemp('commentators_tab_5810_');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
  });

  tearDown(() async {
    await PerBookSettings.settle();
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });

  TextBookTab sourceFor(TextBook book) {
    final source = TextBookTab(
      book: book,
      index: 0,
      blocOverride: StubTextBookBloc(_loaded(book)),
    );
    addTearDown(source.dispose);
    return source;
  }

  CommentatorsTab openTab(TextBook book) => CommentatorsTab(
    sourceTab: sourceFor(book),
    blocOverride: _LoadingTextBookBloc(
      TextBookInitial.named(book, 0, false, const []),
      _loaded(book),
    ),
  );

  /// קריאת הקבצים וכתיבתם יוצאות לדרך מתוך ה-fake async של הטסט, ולכן
  /// מקדמים לסירוגין זמן אמיתי ומיקרו-משימות.
  Future<void> flushFiles(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  /// מציג את [tab], ממתין לקריאות הקבצים ומחזיר את רשימת המפרשים.
  Future<CommentaryListBase> show(
    WidgetTester tester,
    CommentatorsTab tab,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final settings = SettingsBloc(repository: MockSettingsRepository());
    final notes = StubPersonalNotesBloc();
    addTearDown(() async {
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
            body: CommentatorsTabScreen(
              key: ObjectKey(tab),
              tab: tab,
              openBookCallback: (_) {},
            ),
          ),
        ),
      ),
    );
    await flushFiles(tester);
    return tester.widget<CommentaryListBase>(find.byType(CommentaryListBase));
  }

  testWidgets('זיכרון בחירת המפרשים בכרטיסיית מפרשים (issue #5810)', (
    tester,
  ) async {
    final book = TextBook(title: 'בראשית');
    final other = TextBook(title: 'שמות');

    final first = openTab(book);
    final list = await show(tester, first);
    expect(list.selectedCommentatorsOverride, ['רש"י']);
    // "הצג את כל המפרשים" בפאנל הבחירה.
    list.onSelectedCommentatorsOverrideChanged!(_all);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await flushFiles(tester);
    first.dispose();

    final second = openTab(book);
    addTearDown(second.dispose);
    expect((await show(tester, second)).selectedCommentatorsOverride, _all);
    expect(second.selectedCommentators, _all);

    // בחירת החלונית הצדדית של הספר לא השתנתה, וספר אחר לא הושפע.
    final saved = await tester.runAsync(
      () => TextBookPerBookSettings.load(book),
    );
    expect(saved?.activeCommentators, isNull);
    final otherTab = openTab(other);
    addTearDown(otherTab.dispose);
    expect((await show(tester, otherTab)).selectedCommentatorsOverride, [
      'רש"י',
    ]);
  });

  testWidgets('כרטיסייה משוחזרת שומרת על הבחירה שלה (issue #5810)', (
    tester,
  ) async {
    final book = TextBook(title: 'בראשית');
    await tester.runAsync(
      () => TextBookPerBookSettings.mutate(
        book,
        (existing) => TextBookPerBookSettings(commentatorsTabSelection: _all),
      ),
    );

    final restored = openTab(book)
      ..applyBookSelection = false
      ..selectedCommentators = ['רמב"ן'];
    addTearDown(restored.dispose);
    expect((await show(tester, restored)).selectedCommentatorsOverride, [
      'רמב"ן',
    ]);
  });
  testWidgets('היסטוריית מפרשי טקסט משמרת בחירה ריקה מפורשת', (tester) async {
    final tab = openTab(TextBook(title: 'בראשית'))..selectedCommentators = [];
    addTearDown(tab.dispose);
    await show(tester, tab);

    final bookmark = await bookmarkFromReadingTab(tab);
    expect(bookmark?.commentatorsToShow, isEmpty);
    final restored = tabFromBookmark(bookmark!) as CommentatorsTab;
    addTearDown(restored.sourceTab.dispose);
    addTearDown(restored.dispose);
    expect(restored.applyBookSelection, isFalse);
    expect(restored.selectedCommentators, isEmpty);
  });

  test(
    'קביעת קטגוריה אינה מנקה את המסך האחר או בחירת כרטיסייה מאוחרת',
    () async {
      final book = TextBook(title: 'בראשית');
      await TextBookPerBookSettings.mutate(
        book,
        (_) => TextBookPerBookSettings(
          activeCommentators: const ['רש"י'],
          commentatorsTabSelection: const ['רמב"ן'],
        ),
      );
      await TextBookPerBookSettings.clearActiveCommentators(
        book,
        expected: ['רש"י'],
      );
      var saved = await TextBookPerBookSettings.load(book);
      expect(saved?.activeCommentators, isNull);
      expect(saved?.commentatorsTabSelection, ['רמב"ן']);

      await TextBookPerBookSettings.saveCommentatorsTabSelection(book, _all);
      await TextBookPerBookSettings.clearCommentatorsTabSelection(book, [
        'רמב"ן',
      ]);
      saved = await TextBookPerBookSettings.load(book);
      expect(saved?.commentatorsTabSelection, _all);
    },
  );
}
