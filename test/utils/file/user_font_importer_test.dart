import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/user_font_importer.dart';
import 'package:path/path.dart' as p;

import '../../test_helpers/ttc_fixture.dart';

Uint8List _font(String name) => File('fonts/$name').readAsBytesSync();

void main() {
  late Directory root;
  late Directory target;
  late Directory picked;
  late List<String> inspected;
  late int changes;
  List<String> hebrew = ['Tinos'];

  UserFontImporter importer({int? maxBytes}) => UserFontImporter(
    directory: target.path,
    inspect: (path) async {
      inspected.add(path);
      return hebrew;
    },
    onChanged: () async => changes++,
    maxBytes: maxBytes ?? UserFontImporter.defaultMaxBytes,
  );

  String pick(String name, List<int> bytes) {
    final file = File(p.join(picked.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  List<String> stored() => target.existsSync()
      ? (target.listSync().map((e) => p.basename(e.path)).toList()..sort())
      : const [];

  setUp(() {
    root = Directory.systemTemp.createTempSync('otzaria-userfont-');
    target = Directory(p.join(root.path, 'user_fonts'));
    picked = Directory(p.join(root.path, 'picked'))..createSync();
    inspected = [];
    changes = 0;
    hebrew = ['Tinos'];
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'גופן ttf תקין מועתק לתיקיית האפליקציה והרשימה מתרעננת פעם אחת',
    () async {
      final source = pick('Tinos.ttf', _font('Tinos-Regular.ttf'));
      final result = await importer().importFile(source);

      expect(result.status, UserFontImportStatus.imported);
      expect(result.families, ['Tinos']);
      expect(stored(), ['Tinos.ttf']);
      expect(
        File(p.join(target.path, 'Tinos.ttf')).readAsBytesSync(),
        _font('Tinos-Regular.ttf'),
      );
      expect(changes, 1);
      expect(File(source).existsSync(), isTrue, reason: 'המקור לא נמחק');
    },
  );

  test('אוסף ttc מועתק כמו גופן רגיל (אותו מנגנון קבצים)', () async {
    final bytes = buildCollection([
      _font('Tinos-Regular.ttf'),
      _font('ShofarRegular.ttf'),
    ]);
    hebrew = ['Tinos', 'Shofar'];
    final result = await importer().importFile(pick('Pair.ttc', bytes));
    expect(result.status, UserFontImportStatus.imported);
    expect(result.families, ['Tinos', 'Shofar']);
    expect(stored(), ['Pair.ttc']);
  });

  test('otf עם חתימת OTTO מתקבל', () async {
    final bytes = Uint8List.fromList([
      ...'OTTO'.codeUnits,
      ...List.filled(60, 0),
    ]);
    final result = await importer().importFile(pick('Cff.otf', bytes));
    expect(result.status, UserFontImportStatus.imported);
  });

  test('קובץ שאינו גופן נדחה לפי התוכן, גם אם הסיומת ttf', () async {
    final result = await importer().importFile(
      pick('fake.ttf', List.filled(200, 65)),
    );
    expect(result.status, UserFontImportStatus.notAFont);
    expect(stored(), isEmpty);
    expect(inspected, isEmpty, reason: 'לא מנתחים קובץ שאינו גופן');
    expect(changes, 0);
  });

  test('גופן תקין עם סיומת שאינה נתמכת נדחה (woff, pdf וכו\')', () async {
    final result = await importer().importFile(
      pick('Tinos.woff', _font('Tinos-Regular.ttf')),
    );
    expect(result.status, UserFontImportStatus.notAFont);
    expect(stored(), isEmpty);
  });

  test('גופן בלי אותיות עבריות לא מועתק', () async {
    hebrew = [];
    final result = await importer().importFile(
      pick('Latin.ttf', _font('Tinos-Regular.ttf')),
    );
    expect(result.status, UserFontImportStatus.noHebrew);
    expect(stored(), isEmpty);
    expect(changes, 0);
  });

  test('קובץ גדול מהמגבלה נדחה לפני שקוראים אותו', () async {
    final result = await importer(
      maxBytes: 100,
    ).importFile(pick('Big.ttf', _font('Tinos-Regular.ttf')));
    expect(result.status, UserFontImportStatus.tooLarge);
    expect(stored(), isEmpty);
    expect(inspected, isEmpty);
  });

  test('ייבוא חוזר של אותו קובץ לא יוצר עותק ולא מרענן שוב', () async {
    final source = pick('Tinos.ttf', _font('Tinos-Regular.ttf'));
    await importer().importFile(source);
    final again = await importer().importFile(source);

    expect(again.status, UserFontImportStatus.alreadyImported);
    expect(again.families, ['Tinos']);
    expect(stored(), ['Tinos.ttf']);
    expect(changes, 1);
  });

  test('אותו שם קובץ עם תוכן אחר לא דורס: נשמר בשם נפרד', () async {
    final first = pick('Font.ttf', _font('Tinos-Regular.ttf'));
    await importer().importFile(first);
    File(first).deleteSync();
    final second = pick('Font.ttf', _font('ShofarRegular.ttf'));
    hebrew = ['Shofar'];
    final result = await importer().importFile(second);

    expect(result.status, UserFontImportStatus.imported);
    expect(stored(), ['Font.ttf', 'Font_2.ttf']);
    expect(
      File(p.join(target.path, 'Font.ttf')).readAsBytesSync(),
      _font('Tinos-Regular.ttf'),
    );
    expect(
      File(p.join(target.path, 'Font_2.ttf')).readAsBytesSync(),
      _font('ShofarRegular.ttf'),
    );
  });

  test('שם הקובץ מנוקה מתווים שאינם בטוחים בנתיב', () async {
    final source = pick('גופן יפה (1).ttf', _font('Tinos-Regular.ttf'));
    final result = await importer().importFile(source);
    expect(result.status, UserFontImportStatus.imported);
    final name = stored().single;
    expect(name, endsWith('.ttf'));
    expect(name, matches(RegExp(r'^[A-Za-z0-9._-]+$')));
  });

  test('נתיב מקור שאינו קיים: כשל נקי', () async {
    final result = await importer().importFile(p.join(picked.path, 'nope.ttf'));
    expect(result.status, UserFontImportStatus.failed);
    expect(stored(), isEmpty);
    expect(changes, 0);
  });

  test(
    'כשל בכתיבה (התיקייה היא קובץ): failed, בלי שאריות ובלי רענון',
    () async {
      File(target.path).writeAsStringSync('blocker');
      final result = await importer().importFile(
        pick('Tinos.ttf', _font('Tinos-Regular.ttf')),
      );
      expect(result.status, UserFontImportStatus.failed);
      expect(changes, 0);
    },
  );

  test('אין קבצי tmp אחרי ייבוא מוצלח', () async {
    await importer().importFile(pick('Tinos.ttf', _font('Tinos-Regular.ttf')));
    expect(stored().where((n) => n.endsWith('.tmp')), isEmpty);
  });
}
