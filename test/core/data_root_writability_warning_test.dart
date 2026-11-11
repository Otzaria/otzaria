import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/data_root_writability_warning.dart';
import 'package:otzaria/core/directory_writability.dart';
import 'package:path/path.dart' as p;

void main() {
  group('isDirectoryWritable', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('otzaria_writable'));
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('תיקייה שאינה קיימת נוצרת ונחשבת כתיבה', () async {
      final nested = p.join(root.path, 'a', 'b');

      expect(await isDirectoryWritable(nested), isTrue);
      expect(Directory(nested).existsSync(), isTrue);
    });

    test('קובץ הבדיקה אינו נשאר מאחור', () async {
      await isDirectoryWritable(root.path);

      expect(root.listSync(), isEmpty);
    });

    test(
      'בדיקות במקביל באותה תיקייה אינן מוחקות זו לזו את קובץ הבדיקה',
      () async {
        final checks = List.generate(4, (_) => isDirectoryWritable(root.path));

        expect(await Future.wait(checks), everyElement(isTrue));
        expect(root.listSync(), isEmpty);
      },
    );

    test('נתיב שתפוס ע"י קובץ אינו כתיב', () async {
      final path = p.join(root.path, 'busy');
      File(path).writeAsStringSync('');

      expect(await isDirectoryWritable(path), isFalse);
    });
  });

  group('DataRootWritabilityWarning', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('otzaria_dataroot');
      DataRootWritabilityWarning.debugReset();
    });
    tearDown(() {
      AppPaths.debugOverrideDataRootPath(null);
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('שורש כתיב — אין ממצא', () async {
      AppPaths.debugOverrideDataRootPath(root.path);

      expect(await DataRootWritabilityWarning.check(), isNull);
    });

    test('שורש חסום — מוחזר הנתיב', () async {
      final blocked = p.join(root.path, 'blocked');
      File(blocked).writeAsStringSync('');
      AppPaths.debugOverrideDataRootPath(blocked);

      expect(await DataRootWritabilityWarning.check(), blocked);
    });

    test('ההודעה מכילה את הנתיב ומסבירה מה לא יישמר', () {
      final message = DataRootWritabilityWarning.buildMessage(r'C:\blocked');

      expect(message, contains(r'C:\blocked'));
      expect(message, contains('לא יישמרו'));
    });
  });
}
