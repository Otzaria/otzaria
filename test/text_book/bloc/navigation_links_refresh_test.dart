import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _LinksRepository extends TextBookRepository {
  _LinksRepository() : super(fileSystem: FileSystemData.instance);
  int loads = 0;
  @override
  Future<String> getBookContent(TextBook book) async =>
      List.generate(100, (i) => 'שורה $i').join('\n');
  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];
  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    loads++;
    return [_link(21, 2), ...List.generate(300, (i) => _link(1, 10 + i))];
  }

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
  }) async => BookContentRange(
    startLine: 0,
    endLine: 99,
    totalLines: 100,
    lines: List.generate(100, (i) => 'שורה $i'),
  );
}

Link _link(int source, int target) => Link(
  heRef: 'מקור $source',
  index1: source,
  path2: 'יעד $target.txt',
  index2: target,
  connectionType: 'reference',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('פתיחת הניווט מרעננת קישורים לאחר מרוץ טעינה וגלילה', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final book = TextBook(title: 'ספר בדיקה');
    final repository = _LinksRepository();
    final bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 0, false, const []),
    );
    addTearDown(bloc.close);
    final initiallyLoaded = bloc.stream.firstWhere(
      (s) => s is TextBookLoaded && s.links.length == 301,
    );
    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    await initiallyLoaded.timeout(const Duration(seconds: 10));
    expect(repository.loads, 1);
    final incoming = List.generate(300, (i) => _link(1, 1010 + i));
    final loaded = bloc.stream.firstWhere(
      (s) => s is TextBookLoaded && s.links.length == 601,
    );
    bloc.add(UpdateLinks(incoming));
    bloc.add(const UpdateVisibleIndecies([20]));
    await loaded.timeout(const Duration(seconds: 10));
    final raced = bloc.state as TextBookLoaded;
    expect(raced.visibleIndices, [20]);
    expect(raced.selectedIndices, isEmpty);
    final opened = bloc.stream.firstWhere(
      (s) => s is TextBookLoaded && s.showLeftPane,
    );
    bloc.add(const ToggleLeftPane(true));
    await opened.timeout(const Duration(seconds: 10));
    final after = bloc.state as TextBookLoaded;
    expect(after.visibleIndices, [20]);
    expect(repository.loads, 1, reason: 'החלון נשמר במטמון ולא טוען שוב');
    expect(after.visibleLinks.map((l) => l.index1).toSet(), {21});
  });
}
