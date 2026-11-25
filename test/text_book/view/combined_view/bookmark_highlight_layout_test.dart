import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _target = 30;
final _content = [
  for (var i = 0; i < 80; i++)
    'פסוק $i: דברי הברית אשר צוה לכרת את בני ישראל בארץ מואב',
];

/// הקורא האמיתי: הטאב נפתח מסימניה, והקורא נפרס רק אחרי 2.2 שניות. עד אז
/// היעד לא נמדד ואסור שזמן ההדגשה יתחיל (סיבת הסגירה של #5692).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('שורת הסימניה מודגשת רק כשהקורא פרס ומדד אותה, '
      'וההדגשה נמשכת מרגע ההופעה (issue #4455)', (tester) async {
    final book = TextBook(title: 'ספר', filePath: '/books/ספר.txt');
    final tab = TextBookTab(
      book: book,
      index: _target,
      initialReadingAnchor: const ReadingAnchor(line: _target),
    )..highlightLineWhenVisible(_target);
    addTearDown(tab.dispose);
    final bloc = TextBookBloc(
      repository: _Repository(),
      initialState: TextBookInitial.named(
        book,
        _target,
        false,
        const [],
        searchMode: SearchMode.exact,
        showPageShapeView: false,
      ),
      readingPosition: tab.lines.position,
      readingNavigationEpoch: tab.lines.navigationEpoch,
      initialBookmarkHighlight: HighlightLineWhenVisible(
        tab.highlightWhenVisibleLine!,
        navigationEpoch: tab.lines.navigationEpoch.value,
      ),
    );
    addTearDown(bloc.close);
    bloc.add(
      const LoadContent(
        fontSize: 18,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    for (var i = 0; i < 50 && bloc.state is! TextBookLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(bloc.state, isA<TextBookLoaded>());

    // הספר נטען, אבל הקורא עוד לא נפרס: 2.2 שניות בלי מדידה.
    await tester.pump(const Duration(milliseconds: 2200));
    expect(tab.lines.position.value?.isTarget, isTrue);
    expect((bloc.state as TextBookLoaded).highlightedLine, isNull);

    await _pumpReader(tester, tab, bloc);
    expect(tab.lines.position.value?.isTarget, isFalse);
    expect(tab.lines.position.value?.visibleLines, contains(_target));
    expect((bloc.state as TextBookLoaded).highlightedLine, _target);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(
      (bloc.state as TextBookLoaded).highlightedLine,
      _target,
      reason: 'זמן ההדגשה נספר מההופעה',
    );
    await tester.pump(const Duration(seconds: 1));
    expect((bloc.state as TextBookLoaded).highlightedLine, isNull);
  });
}

Future<void> _pumpReader(
  WidgetTester tester,
  TextBookTab tab,
  TextBookBloc bloc,
) async {
  final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
  final settings = StubSettingsBloc(SettingsState.initial());
  addTearDown(notes.close);
  addTearDown(settings.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: Scaffold(
          body: CombinedView(
            data: _content,
            openBookCallback: (_) {},
            openLeftPaneTab: (_, {searchText}) {},
            textSize: 18,
            showCommentaryAsExpansionTiles: false,
            tab: tab,
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async => _content.join('\n');

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async {
    final start = startLine.clamp(0, _content.length - 1);
    final end = endLine.clamp(start, _content.length - 1);
    return BookContentRange(
      startLine: start,
      endLine: end,
      totalLines: _content.length,
      lines: _content.sublist(start, end + 1),
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

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
