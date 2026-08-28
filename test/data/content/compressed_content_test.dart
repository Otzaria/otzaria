import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/content/compressed_content.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/line.dart';
import 'package:path/path.dart' as path;
import 'package:zstandard/zstandard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('book payload preserves empty lines and embedded newlines', () {
    final payload = _bookPayload(const ['first\ncontinued', '', 'last']);

    expect(
      decodeBookContentPayload(payload, expectedLines: 3),
      const ['first\ncontinued', '', 'last'],
    );
    expect(
      () => decodeBookContentPayload(payload, expectedLines: 2),
      throwsFormatException,
    );
  });

  test('version payload is keyed by stable line id', () {
    final payload = _versionPayload(const {42: 'edition\ntext', 77: ''});

    expect(decodeVersionContentPayload(payload), const {
      42: 'edition\ntext',
      77: '',
    });
  });

  test('compressed content rejects a bad checksum', () async {
    final payload = _bookPayload(const ['text']);
    final packed = await Zstandard().compress(payload, 3);

    await expectLater(
      decompressVerifiedContent(
        compressed: packed!,
        uncompressedSize: payload.length,
        contentHash: Uint8List(32),
      ),
      throwsFormatException,
    );
  });

  test('LineDao reads compressed content and keeps legacy fallback', () async {
    final temp = await Directory.systemTemp.createTemp('otzaria-zstd-lines-');
    final database = MyDatabase.withPath(path.join(temp.path, 'test.db'));
    final repository = SeforimRepository(database);
    try {
      await repository.ensureInitialized();
      final categoryId = await repository.insertCategory(
        const Category(title: 'root'),
      );
      final compressedBookId = await _insertBook(
        repository,
        categoryId,
        'compressed',
        const ['', '', ''],
      );
      final legacyBookId = await _insertBook(
        repository,
        categoryId,
        'legacy',
        const ['old one', 'old two'],
      );

      final payload = _bookPayload(const ['new one', 'new\ntwo', '']);
      final packed = await Zstandard().compress(payload, 3);
      expect(packed, isNotNull);
      final db = await database.database;
      db.execute('''
        CREATE TABLE book_content (
          bookId INTEGER PRIMARY KEY,
          format INTEGER NOT NULL DEFAULT 1,
          contentZstd BLOB NOT NULL,
          uncompressedSize INTEGER NOT NULL,
          contentHash BLOB NOT NULL
        )
      ''');
      db.execute(
        'INSERT INTO book_content VALUES (?, 1, ?, ?, ?)',
        [
          compressedBookId,
          packed!,
          payload.length,
          Uint8List.fromList(sha256.convert(payload).bytes),
        ],
      );

      expect(
        await repository.getLineContents(compressedBookId),
        const ['new one', 'new\ntwo', ''],
      );
      expect(
        await repository.getLineContents(legacyBookId),
        const ['old one', 'old two'],
      );
      expect(
        await repository.getLineContentBytes(compressedBookId),
        packed,
      );
    } finally {
      database.close();
      await temp.delete(recursive: true);
    }
  });

  test('compressed edition overlays content on the base line skeleton', () async {
    final temp = await Directory.systemTemp.createTemp('otzaria-zstd-version-');
    final database = MyDatabase.withPath(path.join(temp.path, 'test.db'));
    try {
      final db = await database.database;
      db.execute(
        'INSERT INTO category (id, title) VALUES (1, ?)',
        ['root'],
      );
      db.execute(
        'INSERT INTO source (id, name) VALUES (1, ?)',
        ['source'],
      );
      db.execute(
        'INSERT INTO book (id, categoryId, sourceId, title, totalLines) VALUES (1, 1, 1, ?, 3)',
        ['book'],
      );
      db.execute("INSERT INTO line VALUES (10, 1, 0, '', NULL, NULL)");
      db.execute("INSERT INTO line VALUES (11, 1, 1, '', 'ref 1', NULL)");
      db.execute("INSERT INTO line VALUES (12, 1, 2, '', 'ref 2', NULL)");
      db.execute('''
        CREATE TABLE book_version (
          id INTEGER PRIMARY KEY, bookId INTEGER, versionTitle TEXT,
          hasContent INTEGER
        )
      ''');
      db.execute('''
        CREATE TABLE version_line (
          versionId INTEGER, lineId INTEGER, content TEXT,
          PRIMARY KEY (versionId, lineId)
        )
      ''');
      db.execute("INSERT INTO book_version VALUES (7, 1, 'edition', 1)");
      db.execute("INSERT INTO version_line VALUES (7, 11, '')");

      final basePayload = _bookPayload(const ['<h1>heading</h1>', 'base 1', 'base 2']);
      final versionPayload = _versionPayload(const {11: 'edition 1'});
      final basePacked = await Zstandard().compress(basePayload, 3);
      final versionPacked = await Zstandard().compress(versionPayload, 3);
      db.execute('''
        CREATE TABLE book_content (
          bookId INTEGER PRIMARY KEY, format INTEGER, contentZstd BLOB,
          uncompressedSize INTEGER, contentHash BLOB
        )
      ''');
      db.execute('''
        CREATE TABLE version_content (
          versionId INTEGER PRIMARY KEY, format INTEGER, contentZstd BLOB,
          uncompressedSize INTEGER, contentHash BLOB
        )
      ''');
      db.execute('INSERT INTO book_content VALUES (1, 1, ?, ?, ?)', [
        basePacked!,
        basePayload.length,
        Uint8List.fromList(sha256.convert(basePayload).bytes),
      ]);
      db.execute('INSERT INTO version_content VALUES (7, 1, ?, ?, ?)', [
        versionPacked!,
        versionPayload.length,
        Uint8List.fromList(sha256.convert(versionPayload).bytes),
      ]);

      final range =
          await DatabaseLibraryProvider.loadBookTextRangeRowsForTesting(
            dbPath: database.path,
            title: 'book',
            categoryId: 1,
            fileType: 'txt',
            startLine: 0,
            endLine: 2,
            versionTitle: 'edition',
          );

      expect(range?.lines, const ['<h1>heading</h1>', 'edition 1', '']);
    } finally {
      database.close();
      await temp.delete(recursive: true);
    }
  });
}

Future<int> _insertBook(
  SeforimRepository repository,
  int categoryId,
  String title,
  List<String> contents,
) async {
  final sourceId = await repository.insertSource('test::$title', -1);
  final bookId = await repository.insertBook(
    Book(
      categoryId: categoryId,
      sourceId: sourceId,
      title: title,
      fileType: 'txt',
      totalLines: contents.length,
    ),
  );
  await repository.insertLinesBatch([
    for (var i = 0; i < contents.length; i++)
      Line(bookId: bookId, lineIndex: i, content: contents[i]),
  ]);
  return bookId;
}

Uint8List _bookPayload(List<String> lines) {
  final output = BytesBuilder(copy: false);
  for (final line in lines) {
    final bytes = utf8.encode(line);
    final length = ByteData(4)..setUint32(0, bytes.length, Endian.little);
    output
      ..add(length.buffer.asUint8List())
      ..add(bytes);
  }
  return output.takeBytes();
}

Uint8List _versionPayload(Map<int, String> lines) {
  final output = BytesBuilder(copy: false);
  for (final entry in lines.entries) {
    final bytes = utf8.encode(entry.value);
    final header = ByteData(12)
      ..setInt64(0, entry.key, Endian.little)
      ..setUint32(8, bytes.length, Endian.little);
    output
      ..add(header.buffer.asUint8List())
      ..add(bytes);
  }
  return output.takeBytes();
}
