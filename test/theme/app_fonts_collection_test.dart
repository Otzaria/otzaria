import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/utils/file/sfnt_metadata_reader.dart';
import 'package:otzaria/utils/file/system_font_locator_io.dart';

import '../test_helpers/ttc_fixture.dart';

Uint8List _font(String name) => File('fonts/$name').readAsBytesSync();

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('otzaria-ttc-'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('סורק הגופנים מזהה גם קובצי אוסף (.ttc/.otc) ולא קבצים אחרים', () {
    for (final name in [
      'a.ttf',
      'b.otf',
      'c.ttc',
      'd.OTC',
      'e.txt',
      'f.dfont',
    ]) {
      File('${directory.path}/$name').writeAsBytesSync([0]);
    }
    final names = [
      for (final path in fontPathsInDirectories([directory.path]))
        p.basename(path),
    ]..sort();
    expect(names, ['a.ttf', 'b.otf', 'c.ttc', 'd.OTC']);
  });

  group('סריקה של אוסף: כל face הוא משפחה בפני עצמה', () {
    late String path;
    late SystemFontScanResult scan;
    final tinos = _font('Tinos-Regular.ttf');
    final shofar = _font('ShofarRegular.ttf');

    setUp(() {
      path = '${directory.path}/two.ttc';
      File(path).writeAsBytesSync(buildCollection([tinos, shofar]));
      final metadata = SfntMetadataReader.readSync(path)!;
      scan = AppFonts.debugBuildScan(
        AppFonts.debugExpandCollection(path, metadata),
      );
    });

    test('שני ה-faces מופיעים ברשימה, גם זה שאינו הראשון באוסף', () {
      expect(scan.fonts.map((f) => f.value).toSet(), {
        AppFonts.debugFontFamilyName(tinos),
        AppFonts.debugFontFamilyName(shofar),
      });
    });

    test('נתיב ה-face הוא קובץ גופן עצמאי של אותו face ולא האוסף', () {
      for (final font in [tinos, shofar]) {
        final family = AppFonts.debugFontFamilyName(font);
        final faces = scan.families[family]!;
        expect(faces.regularPath, isNot(path));
        final bytes = File(faces.regularPath).readAsBytesSync();
        expect(AppFonts.debugFontFamilyName(bytes), family);
        expect(AppFonts.debugSfntSupportsHebrew(bytes), isTrue);
        expect(
          bytes.length,
          lessThan(font.length + 4 * 16 * 2),
          reason: 'רק הטבלאות של ה-face, לא האוסף כולו',
        );
      }
    });

    test('הפקת הנתיב חוזרת על עצמה: אותו קובץ, בלי כתיבה מחדש', () {
      final family = AppFonts.debugFontFamilyName(shofar);
      final first = scan.families[family]!.regularPath;
      final stamp = File(first).lastModifiedSync();
      expect(scan.families[family]!.regularPath, first);
      expect(File(first).lastModifiedSync(), stamp);
    });

    test('גם משפחות התוספים מקבלות נתיב לקובץ עצמאי', () {
      final family = AppFonts.debugFontFamilyName(tinos);
      final faces = scan.allFamilies[family]!;
      expect(
        AppFonts.debugFontFamilyName(File(faces.regularPath).readAsBytesSync()),
        family,
      );
    });
  });

  test('נתיב קובץ רגיל לא משתנה: בלי חילוץ ובלי כתיבה', () {
    final tinos = _font('Tinos-Regular.ttf');
    final scan = AppFonts.debugBuildScan([MapEntry('plain.ttf', tinos)]);
    expect(scan.families.values.single.regularPath, 'plain.ttf');
  });

  test('אוסף ללא face עברי לא מוסיף משפחות, וקובץ פגום לא זורק', () {
    final broken = Uint8List.fromList(
      buildCollection([_font('Tinos-Regular.ttf')]),
    )..fillRange(12, 16, 0);
    expect(
      () => AppFonts.debugBuildScan(
        AppFonts.debugExpandCollection('broken.ttc', broken),
      ),
      returnsNormally,
    );
  });
}
