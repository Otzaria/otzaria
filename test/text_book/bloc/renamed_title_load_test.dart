import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _Provider implements LibraryProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingRepository extends TextBookRepository {
  _RecordingRepository() : super(fileSystem: FileSystemData.instance);

  final titles = <String>[];

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
    int? maxChars,
    bool budgetFromEnd = false,
  }) async {
    titles.add(book.title);
    throw StateError('stop');
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDataRoot;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    tempDataRoot = Directory.systemTemp.createTempSync('renamed-title-test-');
    AppPaths.debugOverrideDataRootPath(tempDataRoot.path);
  });

  tearDown(() {
    LibraryProviderManager.instance.resetForTesting();
    AppPaths.debugOverrideDataRootPath(null);
    if (tempDataRoot.existsSync()) tempDataRoot.deleteSync(recursive: true);
  });

  test('ספר שנשמר בכותרת בלי גרשיים נטען בכותרת הקטלוגית (#2766)', () async {
    final provider = _Provider();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(title: 'שו״ת באר מרדכי', categoryId: 7):
            provider,
      },
      providers: [provider],
    );
    final repository = _RecordingRepository();
    final bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(
        TextBook(title: 'שות באר מרדכי', categoryId: 7),
        0,
        false,
        const [],
      ),
    );
    addTearDown(bloc.close);

    bloc.add(
      const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    await bloc.stream
        .firstWhere((s) => s is TextBookError)
        .timeout(const Duration(seconds: 10));

    expect(repository.titles, isNotEmpty);
    expect(repository.titles.toSet(), {'שו״ת באר מרדכי'});
  });
}
