import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'seforim_fixture_db.dart';

void main() {
  for (final variant in SeforimFixtureVariant.values) {
    test('${variant.name} נוצר במלואו בעסקה אחת', () {
      final directory = Directory.systemTemp.createTempSync('seforim_fixture_');
      addTearDown(() => directory.deleteSync(recursive: true));

      final path = SeforimFixtureDb.create(directory, variant);
      final bytes = File(path).readAsBytesSync();
      // במצב rollback journal מונה השינויים גדל פעם בכל עסקת כתיבה.
      // https://sqlite.org/fileformat.html#file_change_counter
      expect(bytes.sublist(18, 20), [1, 1]);
      expect(ByteData.sublistView(bytes).getUint32(24, Endian.big), 1);

      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA integrity_check').single.values, ['ok']);
        expect(db.select('SELECT COUNT(*) FROM book').single.values, [2]);
        expect(db.select('SELECT COUNT(*) FROM line').single.values, [5]);
      } finally {
        db.close();
      }
    });
  }
}
