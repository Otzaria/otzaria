import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

const _name = '\u05d9\u05d4\u05d5\u05d4';
const _query = '"ידוד טוב" מסלול';
const _line = '$_name טוב מסלולם';

List<String> _paintedWords(TextBookInitial state) => [
  for (final range in utils.computeHighlightRanges(
    _line,
    state.searchText,
    isFuzzy: state.searchMode == SearchMode.fuzzy,
    searchDistance: state.searchDistance,
    matchPolicy: state.matchPolicy,
  ))
    _line.substring(range[0], range[1]),
];

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ready = await tryInitSearchEngine();

  test(
    'LoadContent בטאב משוחזר מכין הדגשה חכמה מבוססת אינדקס בלי חיפוש חדש',
    () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      final temporary = await Directory.systemTemp.createTemp('smart-restore-');
      AppPaths.debugOverrideDataRootPath(temporary.path);
      addTearDown(() async {
        AppPaths.debugOverrideDataRootPath(null);
        if (Platform.isWindows) return;
        // תהליכוני המיזוג של המנוע עשויים עוד לכתוב לתיקייה.
        try {
          await temporary.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });
      await Directory('${temporary.path}/index').create();
      final engine = await SearchEngine.newInstance(
        path: '${temporary.path}/index',
      );
      await engine.addDocument(
        ordinal: 0,
        title: 'ספר משוחזר',
        reference: 'שורה 0',
        topics: '/restored',
        text: _line,
        segment: BigInt.zero,
        isPdf: false,
        filePath: 'restored',
      );
      await engine.commit();
      final previousProvider = TantivyDataProvider.instance;
      final provider = TantivyDataProvider.forTesting(Future.value(engine));
      TantivyDataProvider.instance = provider;
      addTearDown(() async {
        TantivyDataProvider.instance = previousProvider;
        await provider.dispose();
      });

      final original = TextBookTab(
        book: TextBook(title: 'ספר משוחזר'),
        index: 0,
        searchText: _query,
        searchMode: SearchMode.fuzzy,
        searchDistance: 1,
        matchPolicy: SearchMatchPolicy.smart,
        splitedView: false,
        showPageShapeView: false,
      );
      addTearDown(original.dispose);
      final restored = TextBookTab.fromJson(original.toJson());
      addTearDown(restored.dispose);
      final initial = restored.blocState as TextBookInitial;
      expect(initial.searchText, _query);
      expect(initial.searchMode, SearchMode.fuzzy);
      expect(initial.searchDistance, 1);
      expect(initial.matchPolicy, SearchMatchPolicy.smart);

      // הכינוי עצמו מוכר גם ל-fallback. רק תבנית מהאינדקס מכירה את
      // "מסלולם" כחלופה המקורבת של המילה שמחוץ לציטוט.
      expect(_paintedWords(initial), isEmpty);
      final bloc = TextBookBloc(
        repository: _Repository(),
        initialState: initial,
        protectionLoader: (_) async => BookProtection.none,
        bookNotesLoader: (_) async => BookNotes.empty,
      );
      addTearDown(bloc.close);
      final prepared = Completer<void>();
      void onPrepared() {
        if (!prepared.isCompleted) prepared.complete();
      }

      utils.highlightPatternRevision.addListener(onPrepared);
      addTearDown(
        () => utils.highlightPatternRevision.removeListener(onPrepared),
      );
      final loaded = bloc.stream.firstWhere(
        (state) => state is TextBookLoaded || state is TextBookError,
      );
      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );
      final state = await loaded.timeout(const Duration(seconds: 30));
      expect(state, isA<TextBookLoaded>());
      await prepared.future.timeout(const Duration(seconds: 30));
      final content = state as TextBookLoaded;
      expect(content.searchText, _query);
      expect(content.matchPolicy, SearchMatchPolicy.smart);
      expect(content.content, [_line]);
      expect(_paintedWords(initial), [_name, 'טוב', 'מסלולם']);
      expect(
        utils.highLight(
          content.content.single,
          content.searchText,
          isFuzzy: content.searchMode == SearchMode.fuzzy,
          searchDistance: content.searchDistance,
          matchPolicy: content.matchPolicy,
        ),
        contains('color: otzaria-search-hit'),
      );
    },
    skip: ready ? false : searchEngineSkipReason,
  );
}

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<bool> supportsContinuousReadingMode(TextBook book) async => false;

  @override
  Future<String> getBookContent(TextBook book) async => _line;

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
  }) async => const BookContentRange(
    startLine: 0,
    endLine: 0,
    totalLines: 1,
    lines: [_line],
  );

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
