import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/file/sfnt_bytes.dart';
import 'package:otzaria/utils/file/sfnt_metadata_reader.dart';
import 'package:otzaria/utils/file/ttc_face.dart';

import '../../test_helpers/ttc_fixture.dart';

Uint8List _font(String name) => File('fonts/$name').readAsBytesSync();

/// תוכן כל טבלה לפי תג.
Map<String, List<int>> _tables(Uint8List font) {
  final result = <String, List<int>>{};
  final numTables = font.sfntU16(4);
  for (var t = 0; t < numTables; t++) {
    final rec = 12 + t * 16;
    final offset = font.sfntU32(rec + 8);
    final length = font.sfntU32(rec + 12);
    result[font.sfntTag(rec)] = font.sublist(offset, offset + length);
  }
  return result;
}

void main() {
  final tinos = _font('Tinos-Regular.ttf');
  final shofar = _font('ShofarRegular.ttf');
  final rubik = _font('Rubik-VariableFont_wght.ttf');
  late Uint8List collection;

  setUp(() => collection = buildCollection([tinos, shofar, rubik]));

  test('מספר ה-faces נקרא מכותרת האוסף, וקובץ רגיל אינו אוסף', () {
    expect(collectionFaceCount(collection), 3);
    expect(collectionFaceCount(tinos), 0);
    expect(collectionFaceCount(Uint8List(4)), 0);
  });

  group('חילוץ face מאוסף לגופן עצמאי', () {
    final originals = {0: 'Tinos-Regular', 1: 'ShofarRegular', 2: 'Rubik'};
    for (final index in originals.keys) {
      test('face $index: אותן טבלאות ואותו שם משפחה כמו הגופן המקורי', () {
        final original = [tinos, shofar, rubik][index];
        final face = extractCollectionFaceFromBytes(collection, index)!;

        expect(face.sfntTag(0) == 'ttcf', isFalse);
        expect(
          AppFonts.debugFontFamilyName(face),
          AppFonts.debugFontFamilyName(original),
        );
        final extracted = _tables(face);
        final expected = _tables(original);
        expect(extracted.keys, expected.keys);
        for (final tag in expected.keys) {
          expect(extracted[tag], expected[tag], reason: tag);
        }
        expect(
          AppFonts.debugSfntSupportsHebrew(face),
          AppFonts.debugSfntSupportsHebrew(original),
        );
      });
    }

    test('הטבלאות בגופן המחולץ מיושרות ל-4 בתים, וה-faces שונים זה מזה', () {
      final first = extractCollectionFaceFromBytes(collection, 0)!;
      for (var t = 0; t < first.sfntU16(4); t++) {
        expect(first.sfntU32(12 + t * 16 + 8) % 4, 0);
      }
      expect(
        AppFonts.debugFontFamilyName(
          extractCollectionFaceFromBytes(collection, 0)!,
        ),
        isNot(
          AppFonts.debugFontFamilyName(
            extractCollectionFaceFromBytes(collection, 1)!,
          ),
        ),
      );
    });

    test('אינדקס מחוץ לטווח, או אוסף פגום: null', () {
      expect(extractCollectionFaceFromBytes(collection, 3), isNull);
      expect(extractCollectionFaceFromBytes(collection, -1), isNull);
      expect(extractCollectionFaceFromBytes(tinos, 0), isNull);
      final broken = Uint8List.fromList(collection);
      ByteData.sublistView(broken).setUint32(12, broken.length + 1);
      expect(extractCollectionFaceFromBytes(broken, 0), isNull);
      expect(extractCollectionFaceFromBytes(broken, 1), isNotNull);
    });

    test('מטא-דאטה קומפקטי: הטבלאות שלא נקראו מושמטות רק כשמבקשים זאת', () {
      final directory = Directory.systemTemp.createTempSync('otzaria-ttc-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/c.ttc')
        ..writeAsBytesSync(collection);
      final compact = SfntMetadataReader.readSync(file.path)!;

      expect(extractCollectionFaceFromBytes(compact, 0), isNull);
      final face = extractCollectionFaceFromBytes(
        compact,
        0,
        skipMissingTables: true,
      )!;
      final tables = _tables(face);
      expect(tables.keys, containsAll(['cmap', 'name']));
      expect(tables.keys, isNot(contains('glyf')));
      expect(
        AppFonts.debugFontFamilyName(face),
        AppFonts.debugFontFamilyName(tinos),
      );
      expect(AppFonts.debugSfntSupportsHebrew(face), isTrue);
      expect(face.sfntU16(4), tables.length);
    });

    test('טבלה שחורגת מסוף הקובץ נחתכת במקום לזרוק', () {
      final truncated = Uint8List.sublistView(
        collection,
        0,
        collection.length - 64,
      );
      expect(
        () => extractCollectionFaceFromBytes(truncated, 2),
        returnsNormally,
      );
    });
  });
}
