import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_json_write_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('כתיבת JSON שומרת את התוכן ואת אורך המחרוזת', () async {
    final data = <String, dynamic>{
      'settings': {'title': 'גיבוי 📚', 'enabled': true},
      'bookmarks': [1, 2, 3],
    };
    final path = p.join(tempDir.path, 'backup.json');

    final length = await BackupService.writeBackupJson(path, data);

    expect(length, json.encode(data).length);
    expect(await File(path).readAsBytes(), utf8.encode(json.encode(data)));
  });

  test('גיבוי גדול אינו חוסם את ה-isolate הקורא (issue #5059)', () async {
    // העברת המפה ל-Isolate.run מעתיקה אותה כולה ב-isolate הקורא, בבת אחת.
    final data = <String, dynamic>{
      'history': [
        for (var i = 0; i < 400000; i++)
          {
            'bookTitle': 'ספר $i',
            'index': i,
            'commentators': ['רש"י', 'תוספות'],
          },
      ],
    };
    final path = p.join(tempDir.path, 'backup.json');
    var longestGap = Duration.zero;
    final sinceTick = Stopwatch()..start();
    final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
      if (sinceTick.elapsed > longestGap) longestGap = sinceTick.elapsed;
      sinceTick.reset();
    });

    await BackupService.writeBackupJson(path, data);
    ticker.cancel();

    expect(longestGap, lessThan(const Duration(milliseconds: 250)));
  });

  test('מחרוזת ארוכה נכתבת זהה, גם כשתו כפול נופל על גבול מקטע', () async {
    final long = '${'א' * 65535}📚${'b' * 200000}';
    final data = <String, dynamic>{
      'userBooks': long,
      'notes': [
        {'text': long, 'tags': <String>[], 'meta': <String, dynamic>{}},
      ],
      'empty': <String, dynamic>{},
      'number': 1.5,
      'flag': null,
    };
    final path = p.join(tempDir.path, 'backup.json');

    final length = await BackupService.writeBackupJson(path, data);

    expect(length, json.encode(data).length);
    expect(await File(path).readAsBytes(), utf8.encode(json.encode(data)));
  });

  test('ערך שאינו ניתן לקידוד אינו משאיר קובץ קטוע', () async {
    final path = p.join(tempDir.path, 'backup.json');
    final data = <String, dynamic>{
      'history': [for (var i = 0; i < 200000; i++) 'ספר $i'],
      'bad': DateTime(2026),
    };

    await expectLater(
      BackupService.writeBackupJson(path, data),
      throwsA(anything),
    );
    expect(File(path).existsSync(), isFalse);
  });

  test('גיבוי מתפרסם רק לאחר גמר הכתיבה', () async {
    final file = File(p.join(tempDir.path, 'backup.json'));
    bool? visibleBeforePublish;
    final data = {
      'head': _JsonValue(() {
        sleep(const Duration(milliseconds: 12));
        return 'ראש';
      }),
      'tail': _JsonValue(() {
        visibleBeforePublish = file.existsSync();
        return 'סוף';
      }),
    };

    await BackupService.writeBackupJson(file.path, data);

    expect(visibleBeforePublish, isFalse);
    expect(await file.readAsString(), '{"head":"ראש","tail":"סוף"}');
    expect(await tempDir.list().map((entity) => entity.path).toList(), [
      file.path,
    ]);
  });

  test('כשל קידוד משאיר את הגיבוי הקודם', () async {
    final file = File(p.join(tempDir.path, 'backup.json'));
    const previous = '{"title":"הגיבוי הקודם"}';
    await file.writeAsString(previous);

    await expectLater(
      BackupService.writeBackupJson(file.path, {'bad': DateTime(2026)}),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );

    expect(await file.readAsString(), previous);
    expect(await tempDir.list().map((entity) => entity.path).toList(), [
      file.path,
    ]);
  });

  test('שגיאת כתיבה מוחזרת למי שממתין לגיבוי', () async {
    await expectLater(
      BackupService.writeBackupJson(
        p.join(tempDir.path, 'missing', 'backup.json'),
        {'title': 'גיבוי'},
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}

class _JsonValue {
  const _JsonValue(this._encode);

  final String Function() _encode;

  String toJson() => _encode();
}
