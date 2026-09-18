import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_db_caps');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  DbCapabilities probe(SeforimFixtureVariant variant) {
    final db = sqlite3.sqlite3.open(
      SeforimFixtureDb.create(tempDir, variant),
      mode: sqlite3.OpenMode.readOnly,
    );
    try {
      return DbCapabilities.probe(db);
    } finally {
      db.close();
    }
  }

  test('מסד מלא — כל היכולות קיימות', () {
    final c = probe(SeforimFixtureVariant.full);
    expect(c.hasBooks, isTrue);
    expect(c.hasBookCategories, isTrue);
    expect(c.hasToc, isTrue);
    expect(c.hasLineToc, isTrue);
    expect(c.hasAltToc, isTrue);
    expect(c.hasLineAltToc, isTrue);
    expect(c.hasLinks, isTrue);
    expect(c.hasLinkAnchors, isTrue);
    expect(c.hasLinkRanges, isTrue);
    expect(c.hasLinkSuppressedSide, isTrue);
    expect(c.hasLinkBaseProvenance, isTrue);
    expect(c.hasBookVersions, isTrue);
    expect(c.hasLineRef, isTrue);
    expect(c.hasLineDhDisplay, isTrue);
    expect(c.hasLineBookIndex, isTrue);
    expect(c.hasAuthors, isTrue);
    expect(c.hasGenerations, isTrue);
    expect(c.hasAcronyms, isTrue);
    expect(c.hasDefaultCommentators, isTrue);
    expect(c.hasBookHeDesc, isTrue);
    expect(c.hasTocEntryLineIndex, isFalse);
  });

  test('מסד מינימלי — רק ספרים ושורות', () {
    final c = probe(SeforimFixtureVariant.minimal);
    expect(c.hasBooks, isTrue);
    expect(c.hasLines, isTrue);
    expect(c.hasCategories, isFalse);
    expect(c.hasBookCategories, isFalse);
    expect(c.hasToc, isFalse);
    expect(c.hasLinks, isFalse);
    expect(c.hasAuthors, isFalse);
    expect(c.hasBookVersions, isFalse);
    expect(c.hasColumn('book', 'sourceId'), isFalse);
    expect(
      c.column('book', 'orderIndex', fallback: '999'),
      '999 AS orderIndex',
    );
    expect(c.column('book', 'title', qualifier: 'b'), 'b.title AS title');
  });

  test('שם מוכר שהוא VIEW או טבלה וירטואלית אינו נחשב טבלה', () {
    final c = probe(SeforimFixtureVariant.viewImpostor);
    expect(c.has('author'), isFalse);
    expect(c.has('link'), isFalse);
    expect(c.has('book_acronym'), isFalse);
    expect(c.hasAuthors, isFalse);
    expect(c.hasLinks, isFalse);
    expect(c.hasLinkAnchors, isFalse);
    expect(c.hasAcronyms, isFalse);
    expect(c.hasCategories, isTrue);
  });

  test('טבלאות של תוסף אינן חלק מהיכולות', () {
    final c = probe(SeforimFixtureVariant.pluginTables);
    expect(c.has('plugin_installation'), isFalse);
    expect(c.has('plugin_script'), isFalse);
    expect(c.hasBooks, isTrue);
  });

  group('כללי זוגות', () {
    DbCapabilities probeWith(void Function(sqlite3.Database db) edit) {
      final path = SeforimFixtureDb.create(tempDir, SeforimFixtureVariant.full);
      final db = sqlite3.sqlite3.open(path);
      try {
        edit(db);
        return DbCapabilities.probe(db);
      } finally {
        db.close();
      }
    }

    test('link_range בלי link_coverage — אין קישורי-טווח', () {
      final c = probeWith((db) => db.execute('DROP TABLE link_coverage'));
      expect(c.has('link_range'), isTrue);
      expect(c.hasLinkRanges, isFalse);
      expect(c.hasLinks, isTrue);
    });

    test('link_coverage בלי link_range — אין קישורי-טווח', () {
      final c = probeWith((db) => db.execute('DROP TABLE link_range'));
      expect(c.hasLinkRanges, isFalse);
    });

    test('book_version בלי version_line — אין מהדורות', () {
      final c = probeWith((db) => db.execute('DROP TABLE version_line'));
      expect(c.has('book_version'), isTrue);
      expect(c.hasBookVersions, isFalse);
    });

    test('link בלי connection_type — אין קישורים כלל', () {
      final c = probeWith((db) => db.execute('DROP TABLE connection_type'));
      expect(c.hasLinks, isFalse);
      expect(c.hasLinkRanges, isFalse);
      expect(c.hasLinkSuppressedSide, isFalse);
    });

    test('line_dh בלי dhDisplay — אין דיבורי-המתחיל', () {
      final c = probeWith((db) {
        db.execute('DROP TABLE line_dh');
        db.execute(
          'CREATE TABLE line_dh (bookId INTEGER, dhText TEXT, lineIndex INTEGER)',
        );
      });
      expect(c.has('line_dh'), isTrue);
      expect(c.hasLineDhDisplay, isFalse);
    });
  });

  test('forDatabase קולט טבלה שנוצרה אחרי הבדיקה, גם מחיבור אחר', () {
    final path = SeforimFixtureDb.create(
      tempDir,
      SeforimFixtureVariant.minimal,
    );
    final db = sqlite3.sqlite3.open(path);
    final writer = sqlite3.sqlite3.open(path);
    addTearDown(() {
      DbCapabilities.invalidate(path);
      writer.close();
      db.close();
    });

    final first = DbCapabilities.forDatabase(path, db);
    expect(first.hasCategories, isFalse);
    expect(identical(DbCapabilities.forDatabase(path, db), first), isTrue);

    db.execute('CREATE TABLE category (id INTEGER PRIMARY KEY, title TEXT)');
    expect(DbCapabilities.forDatabase(path, db).hasCategories, isTrue);

    writer.execute('CREATE TABLE book_acronym (bookId INTEGER, term TEXT)');
    expect(DbCapabilities.forDatabase(path, db).hasAcronyms, isTrue);
  });
}
