import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/services/external_update_notice.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String dbPath;
  late File marker;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('external_update_notice');
    dbPath = p.join(tmp.path, 'seforim.db');
    marker = File(p.join(tmp.path, ExternalUpdateNotice.fileName));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void writeMarker(Map<String, Object?> json) =>
      marker.writeAsStringSync(jsonEncode(json));

  test('אין סימון — null', () async {
    expect(await ExternalUpdateNotice.read(dbPath), isNull);
  });

  test('מסלול דלתא — רשימת הספרים שהשתנו בלי השוואה מלאה', () async {
    writeMarker({
      'formatVersion': 1,
      'source': 'otzaria-launcher',
      'route': 'delta',
      'booksTouched': [4, 11],
    });

    final notice = (await ExternalUpdateNotice.read(dbPath))!;

    expect(notice.booksTouched, {4, 11});
    expect(notice.needsFullReconcile, isFalse);
  });

  test('דלתא שלא שינתה ספרים — אין אינדוקס', () async {
    writeMarker({'formatVersion': 1, 'route': 'delta', 'booksTouched': []});
    final notice = (await ExternalUpdateNotice.read(dbPath))!;
    expect(notice.needsFullReconcile, isFalse);
    expect(notice.needsIndexing, isFalse);
  });

  test('מסלול מלא, רשימה חסרה או סימון פגום — השוואה מלאה', () async {
    writeMarker({'formatVersion': 1, 'route': 'full', 'fullReconcile': true});
    expect((await ExternalUpdateNotice.read(dbPath))!.needsFullReconcile, true);

    writeMarker({'formatVersion': 1, 'route': 'delta'});
    expect((await ExternalUpdateNotice.read(dbPath))!.needsFullReconcile, true);

    marker.writeAsStringSync('{not json');
    expect((await ExternalUpdateNotice.read(dbPath))!.needsFullReconcile, true);

    writeMarker({
      'formatVersion': 2,
      'route': 'delta',
      'booksTouched': [1],
    });
    expect((await ExternalUpdateNotice.read(dbPath))!.needsFullReconcile, true);
  });

  test(
    'סימון שאינו UTF-8 — השוואה מלאה, ונמחק כדי לא לחזור בכל עלייה',
    () async {
      marker.writeAsBytesSync([0x7b, 0xff, 0xfe, 0x7d]);

      final notice = (await ExternalUpdateNotice.read(dbPath))!;
      expect(notice.needsFullReconcile, isTrue);

      await notice.delete();
      expect(marker.existsSync(), isFalse);
    },
  );

  test('delete מוחק את הסימון שנקרא', () async {
    writeMarker({
      'formatVersion': 1,
      'route': 'delta',
      'booksTouched': [1],
    });
    final notice = (await ExternalUpdateNotice.read(dbPath))!;

    await notice.delete();

    expect(marker.existsSync(), isFalse);
  });

  test('delete משאיר סימון חדש שהמעדכן כתב אחרי הקריאה', () async {
    writeMarker({
      'formatVersion': 1,
      'route': 'delta',
      'booksTouched': [1],
    });
    final notice = (await ExternalUpdateNotice.read(dbPath))!;
    writeMarker({
      'formatVersion': 1,
      'route': 'delta',
      'booksTouched': [1, 2],
    });

    await notice.delete();

    expect(marker.existsSync(), isTrue);
  });
}
