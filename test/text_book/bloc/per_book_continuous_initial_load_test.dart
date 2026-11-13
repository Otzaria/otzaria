import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDataRoot;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDataRoot = await Directory.systemTemp.createTemp('per_book_continuous');
    AppPaths.debugOverrideDataRootPath(tempDataRoot.path);
    await Settings.setValue<bool>(
      SettingsRepository.keyEnablePerBookSettings,
      true,
    );
  });

  tearDown(() async {
    await PerBookSettings.settle();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDataRoot.exists()) {
      await tempDataRoot.delete(recursive: true);
    }
  });

  for (final perBook in [true, false]) {
    test('הגדרת הספר continuous=$perBook חלה כבר על ה-Loaded הראשון', () async {
      await Settings.setValue<bool>('key-continuous-reading-mode', !perBook);
      final book = TextBook(title: 'ספר בדיקה');
      await TextBookPerBookSettings.mutate(
        book,
        (_) => TextBookPerBookSettings(continuousReadingMode: perBook),
      );

      final bloc = TextBookBloc(
        repository: _Repository(),
        initialState: TextBookInitial.named(book, 0, false, const []),
      );
      addTearDown(bloc.close);
      final loaded = <bool>[];
      final sub = bloc.stream.listen((state) {
        if (state is TextBookLoaded) loaded.add(state.continuousReadingMode);
      });
      addTearDown(sub.cancel);

      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (loaded.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(loaded, isNotEmpty);
      expect(loaded.toSet(), {perBook});
    });
  }
}

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  static final _lines = List.generate(20, (i) => 'שורה $i');

  @override
  Future<bool> supportsContinuousReadingMode(TextBook book) async => true;

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
    TocEntry(text: 'סעיף', index: 5, level: 1),
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
