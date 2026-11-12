import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/external_link_core.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../tool/src/personal_db_validator.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('validate_db_'));
  tearDown(() => temp.deleteSync(recursive: true));

  String build(String name, String sql) {
    final path = p.join(temp.path, name);
    sqlite3.open(path)
      ..execute(sql)
      ..close();
    return path;
  }

  Set<String> codes(PersonalDbReport r) => {for (final i in r.issues) i.code};

  group('parity with lib', () {
    test('allowlist and limits', () {
      expect(kValidatorKnownTables, kKnownSeforimTables);
      expect(kValidatorMaxExternalLinkRows, kMaxExternalLinkRows);
      expect(kValidatorMaxExternalTextLength, kMaxExternalTextLength);
    });

    test('slug derivation', () {
      final longName = 'a' * 80;
      for (final raw in [
        'My Library',
        '..lead.trail..',
        longName,
        'a/b:c',
        'ספר א',
        '---',
      ]) {
        expect(
          validatorSanitizeSlug(raw),
          AttachedLibraryProbe.sanitizeSlug(raw),
          reason: raw,
        );
        expect(
          validatorSlugFor(libraryId: raw, fileName: 'file name'),
          AttachedLibraryProbe.slugFor(libraryId: raw, fileName: 'file name'),
        );
      }
    });

    test('capability flags match DbCapabilities', () {
      final path = build('caps.db', '''
        CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT, categoryId INTEGER);
        CREATE TABLE category(id INTEGER, parentId INTEGER, title TEXT, level INTEGER);
        CREATE TABLE line(id INTEGER, bookId INTEGER, lineIndex INTEGER, content TEXT);
        CREATE TABLE tocText(id INTEGER, text TEXT);
        CREATE TABLE tocEntry(id INTEGER, bookId INTEGER);
        CREATE TABLE link(id INTEGER);
        CREATE TABLE link_range(id INTEGER);
        CREATE TABLE author(id INTEGER);
        CREATE TABLE book_version(id INTEGER);
        CREATE TABLE book_version_link(versionBookId INTEGER, primaryTitle TEXT);
        CREATE TABLE line_dh(bookId INTEGER, dhDisplay TEXT);
        CREATE TABLE line_note(lineId INTEGER, noteIndex INTEGER, charPos INTEGER, hasMarker INTEGER NOT NULL, body TEXT);
        CREATE TABLE line_note_divine_name(lineId INTEGER, noteIndex INTEGER, charStart INTEGER, span INTEGER);
        CREATE VIEW connection_type AS SELECT 1 AS id;
        CREATE TABLE external_link(sourceBookId INTEGER, sourceLineIndex INTEGER, targetTitle TEXT);
        CREATE TABLE banner(id INTEGER PRIMARY KEY, text TEXT);
        CREATE TABLE book_banner(bookId INTEGER PRIMARY KEY, bannerId INTEGER);
        CREATE TABLE book_protection(bookId INTEGER PRIMARY KEY, level INTEGER);
        CREATE INDEX idx_line_book_index ON line(bookId, lineIndex);
      ''');
      final report = validatePersonalDb(path);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      final caps = DbCapabilities.probe(db);
      db.close();
      final expected = <String, bool>{
        'hasBooks': caps.hasBooks,
        'hasLines': caps.hasLines,
        'hasCategories': caps.hasCategories,
        'hasBookCategories': caps.hasBookCategories,
        'hasToc': caps.hasToc,
        'hasLineToc': caps.hasLineToc,
        'hasAltTocStructures': caps.hasAltTocStructures,
        'hasAltToc': caps.hasAltToc,
        'hasLineAltToc': caps.hasLineAltToc,
        'hasLinks': caps.hasLinks,
        'hasLinkAnchors': caps.hasLinkAnchors,
        'hasLinkRanges': caps.hasLinkRanges,
        'hasLinkSuppressedSide': caps.hasLinkSuppressedSide,
        'hasBookVersions': caps.hasBookVersions,
        'hasBookVersionLinks': caps.hasBookVersionLinks,
        'hasLineRef': caps.hasLineRef,
        'hasLineDhDisplay': caps.hasLineDhDisplay,
        'hasDivineNames': caps.hasDivineNames,
        'hasBookNotes': caps.hasBookNotes,
        'hasBookNoteDivineNames': caps.hasBookNoteDivineNames,
        'hasLineBookIndex': caps.hasLineBookIndex,
        'hasAuthors': caps.hasAuthors,
        'hasTopics': caps.hasTopics,
        'hasPubPlaces': caps.hasPubPlaces,
        'hasPubDates': caps.hasPubDates,
        'hasGenerations': caps.hasGenerations,
        'hasAcronyms': caps.hasAcronyms,
        'hasDefaultCommentators': caps.hasDefaultCommentators,
        'hasDefaultTargums': caps.hasDefaultTargums,
        'hasCategoryClosure': caps.hasCategoryClosure,
        'hasBookBanners': caps.hasBookBanners,
        'hasBookProtection': caps.hasBookProtection,
        'hasExternalLinks': caps.hasExternalLinks,
      };
      expect(caps.hasBookNotes, isTrue);
      expect(caps.hasBookBanners, isTrue);
      expect(caps.hasBookProtection, isTrue);
      expect(caps.hasBookNoteDivineNames, isTrue);
      expect(caps.hasBookVersionLinks, isTrue);
      expect(report.capabilities, expected);
      expect(report.impostors, {'connection_type'});
    });
  });

  test('minimal database passes and takes its slug from library_id', () {
    final path = build('file-name.db', '''
      CREATE TABLE schema_meta(key TEXT PRIMARY KEY, value TEXT);
      INSERT INTO schema_meta VALUES ('library_id', 'my-lib'),
        ('library_name', 'Lib A'), ('db_version', '3');
      CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT NOT NULL);
      INSERT INTO book VALUES (1, 'Book A');
      CREATE TABLE line(id INTEGER PRIMARY KEY, bookId INTEGER,
        lineIndex INTEGER, content TEXT);
      CREATE INDEX idx_line_book_index ON line(bookId, lineIndex);
      INSERT INTO line VALUES (1, 1, 0, 'x');
    ''');
    final report = validatePersonalDb(path);
    expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    expect(report.slug, 'my-lib');
    expect(report.displayName, 'Lib A');
    expect(report.bookCount, 1);
    expect(report.capabilities['hasLines'], isTrue);
  });

  test('split line content (schema 6) is not reported as missing', () {
    final path = build('split.db', '''
      CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT NOT NULL);
      INSERT INTO book VALUES (1, 'Book A');
      CREATE TABLE line(id INTEGER PRIMARY KEY, bookId INTEGER,
        lineIndex INTEGER);
      CREATE TABLE line_content(id INTEGER PRIMARY KEY, content TEXT);
      CREATE INDEX idx_line_book_index ON line(bookId, lineIndex);
      INSERT INTO line VALUES (1, 1, 0);
      INSERT INTO line_content VALUES (1, 'x');
    ''');
    final report = validatePersonalDb(path);
    expect(codes(report), isNot(contains('missing_columns')));
    expect(report.capabilities['hasLines'], isTrue);
  });

  test('banners in the old shape or without banner get a warning', () {
    const disabled = 'Feature "book banners" is disabled';
    for (final (name, sql, message) in [
      (
        'old.db',
        'CREATE TABLE book_banner(bookId INTEGER PRIMARY KEY, text TEXT);',
        '$disabled: missing banner.',
      ),
      (
        'old_with_banner.db',
        'CREATE TABLE banner(id INTEGER PRIMARY KEY, text TEXT);'
            'CREATE TABLE book_banner(bookId INTEGER PRIMARY KEY, text TEXT);',
        '$disabled.',
      ),
      (
        'partial.db',
        'CREATE TABLE book_banner(bookId INTEGER PRIMARY KEY, bannerId INTEGER);',
        '$disabled: missing banner.',
      ),
    ]) {
      final path = build(name, '''
        CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT NOT NULL);
        $sql
      ''');
      final report = validatePersonalDb(path);
      expect(report.capabilities['hasBookBanners'], isFalse, reason: name);
      expect(
        report.issues.map((i) => i.message),
        contains(message),
        reason: name,
      );
    }
  });

  test('no book table is fatal', () {
    final report = validatePersonalDb(
      build('none.db', 'CREATE TABLE plugin_data(x);'),
    );
    expect(codes(report), contains('no_books'));
    expect(report.ignoredTables, {'plugin_data'});
    expect(report.hasErrors, isTrue);
  });

  test('a non-empty -wal next to the file is fatal', () {
    final path = build('j.db', 'CREATE TABLE book(id INTEGER, title TEXT);');
    File('$path-wal').writeAsStringSync('pending');
    final report = validatePersonalDb(path);
    expect(codes(report), contains('pending_journal'));
    expect(report.hasErrors, isTrue);
  });

  test('file paths outside the database folder are rejected', () {
    Directory(p.join(temp.path, 'files')).createSync();
    File(p.join(temp.path, 'files', 'ok.pdf')).writeAsStringSync('x');
    final path = build('paths.db', r'''
      CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT, filePath TEXT);
      INSERT INTO book VALUES (1, 'A', 'files/ok.pdf'), (2, 'B', '../x.pdf'),
        (3, 'C', 'C:\x.pdf'), (4, 'D', 'files/missing.pdf');
    ''');
    final report = validatePersonalDb(path);
    final rejected = report.issues.firstWhere(
      (i) => i.code == 'file_path_rejected',
    );
    expect(rejected.message, contains('2 book(s)'));
    expect(codes(report), contains('file_missing'));
    expect(report.hasErrors, isTrue);
  });

  test('book_version_link: bad rows and primarySource values are reported', () {
    final path = build('versions.db', '''
      CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT);
      INSERT INTO book VALUES (1, 'A');
      CREATE TABLE book_version_link(versionBookId INTEGER,
        primarySource TEXT, primaryTitle TEXT, versionTitle TEXT);
      INSERT INTO book_version_link VALUES (1, 'official', 'B', 'x'),
        (1, 'db:other-db', 'B', NULL), (1, NULL, 'B', NULL),
        (9, 'user', 'B', NULL), (1, 'somewhere', 'B', NULL);
    ''');
    final report = validatePersonalDb(path);
    expect(report.capabilities['hasBookVersionLinks'], isTrue);
    expect(codes(report), contains('book_version_link_invalid_rows'));
    final bad = report.issues.singleWhere(
      (i) => i.code == 'book_version_link_bad_primary_source',
    );
    expect(bad.message, contains('somewhere'));
    expect(bad.message, isNot(contains('other-db')));
    expect(report.hasErrors, isFalse);
  });

  test('book_version_link without primaryTitle is ignored with a warning', () {
    final path = build('versions_bad.db', '''
      CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT);
      CREATE TABLE book_version_link(versionBookId INTEGER);
    ''');
    final report = validatePersonalDb(path);
    expect(report.capabilities['hasBookVersionLinks'], isFalse);
    expect(
      report.issues.where((i) => i.message.contains('book_version_link')),
      isNotEmpty,
    );
  });

  test('external_link over the row limit is fatal', () {
    final path = build('big.db', '''
      CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT);
      INSERT INTO book VALUES (1, 'A');
      CREATE TABLE external_link(sourceBookId INTEGER,
        sourceLineIndex INTEGER, targetTitle TEXT);
      WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n
        WHERE i <= $kValidatorMaxExternalLinkRows)
      INSERT INTO external_link SELECT 1, i, 'T' FROM n;
    ''');
    final report = validatePersonalDb(path);
    expect(codes(report), contains('external_link_too_large'));
    expect(report.externalLinkRows, kValidatorMaxExternalLinkRows + 1);
  });

  test('external_link without the source index gets a recommendation', () {
    final path = build('ext.db', '''
      CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT);
      INSERT INTO book VALUES (1, 'A');
      CREATE TABLE external_link(sourceBookId INTEGER, sourceLineIndex INTEGER,
        targetSource TEXT, targetTitle TEXT, connectionType TEXT);
      INSERT INTO external_link VALUES (1, 0, 'official', 'B', 'SOURCE'),
        (9, 0, NULL, 'B', NULL);
    ''');
    final report = validatePersonalDb(path);
    expect(codes(report), contains('external_link_no_index'));
    expect(codes(report), contains('external_link_invalid_rows'));
    expect(report.hasErrors, isFalse);
  });
}
