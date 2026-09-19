import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/utils/attached_file_path.dart';
import 'package:otzaria/migration/database/journal_mode.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  group('resolveAttachedBookFilePath', () {
    final db = p.join(Directory.systemTemp.path, 'libs', 'my.db');
    final folder = p.dirname(db);

    test('נתיב יחסי נפתר בתוך תיקיית המסד', () {
      expect(
        resolveAttachedBookFilePath(db, 'pdf/ספר.pdf'),
        p.join(folder, 'pdf', 'ספר.pdf'),
      );
      expect(
        resolveAttachedBookFilePath(db, r'pdf\ספר.pdf'),
        p.join(folder, 'pdf', 'ספר.pdf'),
      );
      expect(
        resolveAttachedBookFilePath(db, './a.pdf'),
        p.join(folder, 'a.pdf'),
      );
    });

    for (final rejected in [
      null,
      '',
      '   ',
      '../a.pdf',
      'pdf/../../a.pdf',
      r'..\a.pdf',
      '/etc/passwd',
      r'C:\Windows\a.pdf',
      'C:a.pdf',
      r'\\server\share\a.pdf',
      '//server/share/a.pdf',
      '.',
      'a\u0000.pdf',
      r'\\?\C:\a.pdf',
      r'pdf\../../a.pdf',
      '.. /a.pdf',
      '../../a.pdf',
      '.../a.pdf',
      'pdf/ .. /a.pdf',
      'a.pdf:stream',
    ]) {
      test('נדחה: $rejected', () {
        expect(resolveAttachedBookFilePath(db, rejected), isNull);
      });
    }
  });

  test('החלת יומן על עותק מיובא רצה על חיבור מוקשח ועדיין מנרמלת', () async {
    final dir = await Directory.systemTemp.createTemp('otzaria_copy_journal');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'copy.db');
    final db = sqlite3.sqlite3.open(path)
      ..execute('PRAGMA journal_mode=WAL')
      ..execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)')
      ..execute("INSERT INTO book VALUES (1, 'x')");
    db.close();

    await normalizeJournalModeForReadOnly(path, untrusted: true);

    final check = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    addTearDown(check.close);
    expect(check.select('PRAGMA journal_mode').first.values.first, 'delete');
    expect(check.select('SELECT title FROM book').single['title'], 'x');
  });
}
