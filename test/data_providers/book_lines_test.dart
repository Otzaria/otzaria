import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:path/path.dart' as path;

/// A provider that only knows a book as one text (the old shape).
class _TextProvider extends Fake implements LibraryProvider {
  _TextProvider(this.text);

  final String text;

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => text;
}

/// A provider that reads a book straight into lines (a database source).
class _LinesProvider extends Fake
    implements LibraryProvider, BookLinesProvider {
  _LinesProvider(this.lines);

  final List<String> lines;
  var textReads = 0;

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    textReads++;
    return lines.join('\n');
  }

  @override
  Future<List<String>?> getBookLines(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => lines;
}

void main() {
  const text = '<h1>title</h1>\nfirst line\n\nlast line';

  group('splitBookText', () {
    test('an empty text has no lines', () async {
      expect(await splitBookText(''), isEmpty);
    });

    test('splits once on newline', () async {
      expect(await splitBookText(text), text.split('\n'));
    });
  });

  test('rowsToBookLines: one line per row, a row with a newline splits '
      'as the joined rows would', () {
    final rows = ['a', '', 'b\nc', 'd'];
    expect(rowsToBookLines(rows), rows.join('\n').split('\n'));
    expect(rowsToBookLines(const []), isEmpty);
  });

  test('bookLinesHaveText matches a non-empty joined text', () {
    expect(bookLinesHaveText(null), isFalse);
    expect(bookLinesHaveText(const []), isFalse);
    expect(bookLinesHaveText(const ['']), isFalse);
    expect(bookLinesHaveText(const ['', '']), isTrue);
    expect(bookLinesHaveText(const ['a']), isTrue);
  });

  group('LibraryProviderManager.getBookLines', () {
    final manager = LibraryProviderManager.instance;
    final key = BookCompositeKey.create(
      title: 'book',
      categoryId: 1,
      fileType: 'txt',
    );

    tearDown(manager.resetForTesting);

    test('a text-only provider: its text split once', () async {
      manager.seedMappingsForTesting(
        mapping: {key: _TextProvider(text)},
        providers: [],
      );
      final lines = await manager.getBookLines(
        'book',
        categoryId: 1,
        fileType: 'txt',
      );
      expect(lines, text.split('\n'));
    });

    test('a lines provider: its lines as they are, no text read', () async {
      final provider = _LinesProvider(['row 0', '', 'row 2']);
      manager.seedMappingsForTesting(mapping: {key: provider}, providers: []);
      final lines = await manager.getBookLines(
        'book',
        categoryId: 1,
        fileType: 'txt',
      );
      expect(lines, same(provider.lines));
      expect(provider.textReads, 0);
      expect(
        await manager.getBookText('book', categoryId: 1, fileType: 'txt'),
        lines!.join('\n'),
      );
    });
  });

  group('FileSystemLibraryProvider text-file book', () {
    late Directory tempDir;
    final provider = FileSystemLibraryProvider.instance;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_book_lines');
    });

    tearDown(() async {
      provider.resetForTesting();
      await tempDir.delete(recursive: true);
    });

    test('its lines equal its text split on newline', () async {
      final file = File(path.join(tempDir.path, 'book.txt'));
      await file.writeAsString(text);
      provider.seedKeyToPathForTesting(
        keyToPath: {
          BookCompositeKey.create(
            title: 'book',
            categoryId: 1,
            fileType: 'txt',
          ).toStorageKey(): file.path,
        },
      );

      final bookText = await provider.getBookText('book', 1, 'txt');
      expect(bookText, text);
      expect(
        await provider.getBookLines('book', 1, 'txt'),
        bookText!.split('\n'),
      );
      expect(await provider.getBookLines('missing', 1, 'txt'), isNull);
    });
  });
}
