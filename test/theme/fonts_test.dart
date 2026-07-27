import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';

Uint8List _bundledFont(String name) =>
    Uint8List.fromList(File('fonts/$name').readAsBytesSync());

// ---------------------------------------------------------------------------
// Helpers — build minimal valid OpenType/TrueType byte sequences
// ---------------------------------------------------------------------------

/// Builds a minimal SFNT with one cmap format-4 subtable, 2 segments.
/// [hebrewRange]: segment covers U+0590–05FF (Hebrew); otherwise U+0041–005A (Latin).
Uint8List _buildSfnt({required bool hebrewRange}) {
  final int sc = hebrewRange ? 0x0590 : 0x0041;
  final int ec = hebrewRange ? 0x05FF : 0x005A;

  // cmap format-4 subtable (2 segments = real + 0xFFFF terminator)
  // size = 14 header + 4 endCodes + 2 pad + 4 startCodes + 4 idDeltas + 4 idRangeOffsets = 32
  final sub = ByteData(32)
    ..setUint16(0, 4) // format
    ..setUint16(2, 32) // length
    ..setUint16(4, 0) // language
    ..setUint16(6, 4) // segCountX2
    ..setUint16(8, 4) // searchRange
    ..setUint16(10, 1) // entrySelector
    ..setUint16(12, 0) // rangeShift
    ..setUint16(14, ec) // endCode[0]
    ..setUint16(16, 0xFFFF) // endCode[1] terminator
    ..setUint16(18, 0) // reservedPad
    ..setUint16(20, sc) // startCode[0]
    ..setUint16(22, 0xFFFF) // startCode[1] terminator
    ..setUint16(24, 0) // idDelta[0]
    ..setUint16(26, 1) // idDelta[1]
    ..setUint16(28, 0) // idRangeOffset[0]
    ..setUint16(30, 0); // idRangeOffset[1]

  // cmap table: version(2) + numTables(2) + encoding record(8) + subtable(32) = 44
  // subtable offset relative to cmap start = 4 + 8 = 12
  final cmap = ByteData(44)
    ..setUint16(0, 0) // version
    ..setUint16(2, 1) // numTables
    ..setUint16(4, 3) // platformID = 3 (Windows)
    ..setUint16(6, 1) // encodingID = 1 (BMP)
    ..setUint32(8, 12); // subtable offset
  for (int i = 0; i < 32; i++) {
    cmap.setUint8(12 + i, sub.getUint8(i));
  }

  // SFNT offset table (12) + 1 table record (16) = 28; cmap starts at 28
  const int cmapOffset = 28;
  final sfnt = ByteData(cmapOffset + 44)
    ..setUint32(0, 0x00010000) // sfVersion (TrueType)
    ..setUint16(4, 1) // numTables
    ..setUint16(6, 16) // searchRange
    ..setUint16(8, 0) // entrySelector
    ..setUint16(10, 0) // rangeShift
    // table record: "cmap"
    ..setUint8(12, 0x63)
    ..setUint8(13, 0x6D)
    ..setUint8(14, 0x61)
    ..setUint8(15, 0x70)
    ..setUint32(16, 0) // checksum
    ..setUint32(20, cmapOffset) // offset
    ..setUint32(24, 44); // length
  for (int i = 0; i < 44; i++) {
    sfnt.setUint8(cmapOffset + i, cmap.getUint8(i));
  }
  return sfnt.buffer.asUint8List();
}

/// Wraps one or more SFNTs into a TTC file.
Uint8List _buildTtc(List<Uint8List> fonts) {
  final int headerSize = 12 + fonts.length * 4;
  final offsets = <int>[];
  int pos = headerSize;
  for (final f in fonts) {
    offsets.add(pos);
    pos += f.length;
  }
  final ttc = ByteData(pos)
    ..setUint8(0, 0x74)
    ..setUint8(1, 0x74)
    ..setUint8(2, 0x63)
    ..setUint8(3, 0x66) // "ttcf"
    ..setUint32(4, 0x00010000) // version
    ..setUint32(8, fonts.length); // numFonts
  for (int i = 0; i < fonts.length; i++) {
    ttc.setUint32(12 + i * 4, offsets[i]);
  }
  for (int i = 0; i < fonts.length; i++) {
    final f = fonts[i];
    for (int j = 0; j < f.length; j++) {
      ttc.setUint8(offsets[i] + j, f[j]);
    }
  }

  // Rebase: ב-TTC אמיתי היסטי הטבלאות מוחלטים בתוך הקובץ. לאחר שיבוץ כל SFNT
  // ב-offset שלו, מוסיפים את ה-offset לכל היסט-טבלה ב-Table Directory.
  for (int i = 0; i < fonts.length; i++) {
    final start = offsets[i];
    final numTables = ttc.getUint16(start + 4);
    for (int t = 0; t < numTables; t++) {
      final rec = start + 12 + t * 16;
      ttc.setUint32(rec + 8, ttc.getUint32(rec + 8) + start);
    }
  }
  return ttc.buffer.asUint8List();
}

/// Builds a minimal SFNT with a single OS/2 table.
/// [familyClassHi]: high byte of sFamilyClass (-1 to leave the field at 0).
/// [panoseFamily]/[panoseSerif]: PANOSE bFamilyType / bSerifStyle fallback.
Uint8List _buildSfntWithOs2({
  int familyClassHi = 0,
  int panoseFamily = 0,
  int panoseSerif = 0,
}) {
  const int os2Len = 78;
  final os2 = ByteData(os2Len)
    ..setUint16(0, 1) // version
    ..setUint16(30, (familyClassHi & 0xFF) << 8) // sFamilyClass
    ..setUint8(32, panoseFamily) // PANOSE bFamilyType
    ..setUint8(33, panoseSerif); // PANOSE bSerifStyle

  const int os2Offset = 28; // 12 offset table + 16 one record
  final sfnt = ByteData(os2Offset + os2Len)
    ..setUint32(0, 0x00010000) // sfVersion
    ..setUint16(4, 1) // numTables
    ..setUint16(6, 16)
    ..setUint16(8, 0)
    ..setUint16(10, 0)
    // table record: "OS/2"
    ..setUint8(12, 0x4F)
    ..setUint8(13, 0x53)
    ..setUint8(14, 0x2F)
    ..setUint8(15, 0x32)
    ..setUint32(16, 0) // checksum
    ..setUint32(20, os2Offset) // offset
    ..setUint32(24, os2Len); // length
  for (int i = 0; i < os2Len; i++) {
    sfnt.setUint8(os2Offset + i, os2.getUint8(i));
  }
  return sfnt.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  test('list fonts', () {
    try {
      for (final font in AppFonts.availableFonts) {
        debugPrint('Font: ${font.label}, family: ${font.value}');
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  });

  group('sfntSupportsHebrew — SFNT', () {
    test('Hebrew range → true', () {
      expect(
        AppFonts.debugSfntSupportsHebrew(_buildSfnt(hebrewRange: true)),
        isTrue,
      );
    });

    test('non-Hebrew range → false', () {
      expect(
        AppFonts.debugSfntSupportsHebrew(_buildSfnt(hebrewRange: false)),
        isFalse,
      );
    });

    test('empty data → false', () {
      expect(AppFonts.debugSfntSupportsHebrew(Uint8List(0)), isFalse);
    });

    test('too-short data → false', () {
      expect(AppFonts.debugSfntSupportsHebrew(Uint8List(4)), isFalse);
    });
  });

  group('sfntSupportsHebrew — TTC', () {
    test('TTC with Hebrew font → true', () {
      final ttc = _buildTtc([_buildSfnt(hebrewRange: true)]);
      expect(AppFonts.debugSfntSupportsHebrew(ttc), isTrue);
    });

    test('TTC with non-Hebrew font → false', () {
      final ttc = _buildTtc([_buildSfnt(hebrewRange: false)]);
      expect(AppFonts.debugSfntSupportsHebrew(ttc), isFalse);
    });

    test('TTC with Hebrew as second font → true', () {
      final ttc = _buildTtc([
        _buildSfnt(hebrewRange: false),
        _buildSfnt(hebrewRange: true),
      ]);
      expect(AppFonts.debugSfntSupportsHebrew(ttc), isTrue);
    });

    test('TTC with only non-Hebrew fonts → false', () {
      final ttc = _buildTtc([
        _buildSfnt(hebrewRange: false),
        _buildSfnt(hebrewRange: false),
      ]);
      expect(AppFonts.debugSfntSupportsHebrew(ttc), isFalse);
    });

    test('TTC header too short → false', () {
      // Only 8 bytes: enough for magic + version but not numFonts
      final bad = Uint8List.fromList([0x74, 0x74, 0x63, 0x66, 0, 1, 0, 0]);
      expect(AppFonts.debugSfntSupportsHebrew(bad), isFalse);
    });
  });

  group('sfntCategory — OS/2', () {
    test('sFamilyClass = serif classes → serif', () {
      for (final hi in [1, 2, 3, 4, 5, 7]) {
        expect(
          AppFonts.debugSfntCategory(_buildSfntWithOs2(familyClassHi: hi)),
          FontCategory.serif,
          reason: 'class $hi צריך להיות serif',
        );
      }
    });

    test('sFamilyClass = 8 → sans-serif', () {
      expect(
        AppFonts.debugSfntCategory(_buildSfntWithOs2(familyClassHi: 8)),
        FontCategory.sansSerif,
      );
    });

    test('sFamilyClass לא מסווג (0) ללא PANOSE → unknown', () {
      expect(
        AppFonts.debugSfntCategory(_buildSfntWithOs2(familyClassHi: 0)),
        FontCategory.unknown,
      );
    });

    test('PANOSE כגיבוי: Latin Text + serif style → serif', () {
      expect(
        AppFonts.debugSfntCategory(
          _buildSfntWithOs2(panoseFamily: 2, panoseSerif: 3),
        ),
        FontCategory.serif,
      );
    });

    test('PANOSE כגיבוי: Latin Text + sans style → sans-serif', () {
      expect(
        AppFonts.debugSfntCategory(
          _buildSfntWithOs2(panoseFamily: 2, panoseSerif: 11),
        ),
        FontCategory.sansSerif,
      );
    });

    test('ללא טבלת OS/2 → unknown', () {
      expect(
        AppFonts.debugSfntCategory(_buildSfnt(hebrewRange: true)),
        FontCategory.unknown,
      );
    });

    test('TTC עם OS/2 (היסטים מוחלטים) → serif', () {
      final ttc = _buildTtc([_buildSfntWithOs2(familyClassHi: 2)]);
      expect(AppFonts.debugSfntCategory(ttc), FontCategory.serif);
    });

    test('נתונים ריקים → unknown', () {
      expect(AppFonts.debugSfntCategory(Uint8List(0)), FontCategory.unknown);
    });
  });

  group('warmUpSystemFontsCache', () {
    tearDown(() {
      AppFonts.debugResetSystemFontsCache();
    });

    test('חוזר מיידית כשהקאש כבר חם, ולא מאתחל warm-up future', () async {
      AppFonts.debugSystemFontsHebrewCache = const [
        FontInfo(value: 'TestFont', label: 'TestFont'),
      ];

      final future = AppFonts.warmUpSystemFontsCache();

      // הסתיים מיידית, ולא נוצר _warmUpFuture (כי הוחזר Future.value).
      await future;
      expect(AppFonts.debugWarmUpFuture, isNull);
    });

    test('שומר על הקאש הקיים אחרי קריאה לחימום', () async {
      const existing = [
        FontInfo(value: 'PreloadedFont', label: 'PreloadedFont'),
      ];
      AppFonts.debugSystemFontsHebrewCache = existing;

      await AppFonts.warmUpSystemFontsCache();

      expect(AppFonts.debugSystemFontsHebrewCache, same(existing));
    });

    test('availableFonts מחזיר bundled + cache כשהקאש מאוכלס', () {
      const systemFont = FontInfo(
        value: 'MockSystemFont',
        label: 'MockSystemFont',
      );
      AppFonts.debugSystemFontsHebrewCache = const [systemFont];

      final fonts = AppFonts.availableFonts;

      // הגופנים המובנים תמיד נכללים
      expect(
        fonts.any((f) => f.value == AppFonts.defaultFont),
        isTrue,
        reason:
            'הגופן המובנה ${AppFonts.defaultFont} צריך להופיע ב-availableFonts',
      );
      expect(
        fonts.any((f) => f.value == AppFonts.defaultCommentatorsFont),
        isTrue,
        reason:
            'גופן המפרשים המובנה ${AppFonts.defaultCommentatorsFont} צריך להופיע',
      );

      // בדסקטופ - גם גופן הקאש המוזרק. במובייל/web - לא.
      final isDesktop =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.linux);
      if (isDesktop) {
        expect(
          fonts.any((f) => f.value == systemFont.value),
          isTrue,
          reason: 'גופן מערכת מהקאש צריך להופיע בתוצאה בדסקטופ',
        );
      }
    });

    test('availableFonts מחזיר את הרשימה המובנית גם בלי קאש מערכת', () {
      AppFonts.debugSystemFontsHebrewCache = const [];

      final fonts = AppFonts.availableFonts;

      expect(fonts, isNotEmpty);
      expect(fonts.any((f) => f.value == AppFonts.defaultFont), isTrue);
    });

    test('debugResetSystemFontsCache מנקה גם cache וגם warm-up future', () {
      AppFonts.debugSystemFontsHebrewCache = const [
        FontInfo(value: 'X', label: 'X'),
      ];

      AppFonts.debugResetSystemFontsCache();

      expect(AppFonts.debugSystemFontsHebrewCache, isNull);
      expect(AppFonts.debugWarmUpFuture, isNull);
    });
  });

  group('פרסור face — מטבלאות SFNT (גופנים מובנים)', () {
    test('גופן Medium: שם משפחה, משקל 500, לא בולד ולא נטוי', () {
      final b = _bundledFont('FrankRuehlCLM-Medium.ttf');
      expect(AppFonts.debugFontFamilyName(b), 'Frank Ruehl CLM');
      expect(AppFonts.debugFontWeightClass(b), 500);
      expect(AppFonts.debugFontIsBoldStyle(b), isFalse);
      expect(AppFonts.debugFontIsItalic(b), isFalse);
      expect(AppFonts.debugFontHasWeightAxis(b), isFalse);
    });

    test('גופן Bold: אותה משפחה, משקל 700, מסווג כבולד', () {
      final b = _bundledFont('FrankRuehlCLM-Bold.ttf');
      expect(AppFonts.debugFontFamilyName(b), 'Frank Ruehl CLM');
      expect(AppFonts.debugFontWeightClass(b), 700);
      expect(AppFonts.debugFontIsBoldStyle(b), isTrue);
      expect(AppFonts.debugFontIsItalic(b), isFalse);
    });

    // hasSeparateBoldFace מוקשח ברשימה; אם יירשם ב-pubspec קובץ בולד נוסף
    // למשפחה אחרת, הכותרות שלה יחזרו להישלף מקובץ אחר מהגוף.
    test('hasSeparateBoldFace תואם למשפחות עם יותר מ-face אחד ב-pubspec', () {
      final pubspec = File(
        'pubspec.yaml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final fontsBlock = pubspec.substring(pubspec.indexOf('\n  fonts:'));

      final multiFace = <String>{};
      for (final m in RegExp(
        r'- family: (\S+)\n((?:[ \t]+.*\n)+?)(?=\s*- family:|\s*\n|$)',
      ).allMatches(fontsBlock)) {
        final family = m.group(1)!;
        final assets = RegExp(r'- asset:').allMatches(m.group(2)!).length;
        if (assets > 1) multiFace.add(family);
      }

      expect(multiFace, isNotEmpty, reason: 'הפרסור של pubspec נכשל');
      for (final family in multiFace) {
        expect(
          AppFonts.hasSeparateBoldFace(family),
          isTrue,
          reason: '$family נרשם עם כמה faces אך אינו ב-hasSeparateBoldFace',
        );
      }
    });

    test('Medium ו-Bold חולקים שם משפחה זהה', () {
      expect(
        AppFonts.debugFontFamilyName(_bundledFont('FrankRuehlCLM-Medium.ttf')),
        AppFonts.debugFontFamilyName(_bundledFont('FrankRuehlCLM-Bold.ttf')),
      );
    });

    test('גופן משתנה (fvar עם ציר wght) מזוהה', () {
      for (final f in [
        'Rubik-VariableFont_wght.ttf',
        'NotoRashiHebrew-VariableFont_wght.ttf',
        'NotoSerifHebrew-VariableFont_wdth,wght.ttf',
      ]) {
        expect(
          AppFonts.debugFontHasWeightAxis(_bundledFont(f)),
          isTrue,
          reason: '$f צריך להכיל ציר wght',
        );
      }
    });

    test('גופן סטטי אינו מזוהה כמשתנה', () {
      expect(
        AppFonts.debugFontHasWeightAxis(_bundledFont('ShofarRegular.ttf')),
        isFalse,
      );
    });

    test('נתונים פגומים → ערכי ברירת מחדל', () {
      final bad = Uint8List(4);
      expect(AppFonts.debugFontFamilyName(bad), '');
      expect(AppFonts.debugFontWeightClass(bad), 0);
      expect(AppFonts.debugFontIsBoldStyle(bad), isFalse);
      expect(AppFonts.debugFontHasWeightAxis(bad), isFalse);
    });
  });

  group('התאמת bold sibling', () {
    test('Medium → Bold של אותה משפחה = sibling', () {
      expect(
        AppFonts.debugIsBoldSibling(
          _bundledFont('FrankRuehlCLM-Medium.ttf'),
          _bundledFont('FrankRuehlCLM-Bold.ttf'),
        ),
        isTrue,
      );
    });

    test('מועמד שאינו בולד אינו sibling', () {
      expect(
        AppFonts.debugIsBoldSibling(
          _bundledFont('FrankRuehlCLM-Medium.ttf'),
          _bundledFont('FrankRuehlCLM-Medium.ttf'),
        ),
        isFalse,
      );
    });

    test('משפחה שונה אינה sibling', () {
      expect(
        AppFonts.debugIsBoldSibling(
          _bundledFont('FrankRuehlCLM-Medium.ttf'),
          _bundledFont('ShofarRegular.ttf'),
        ),
        isFalse,
      );
    });
  });

  group('היוריסטיקת שם-קובץ לבולד', () {
    test('סיומות בולד נפוצות ב-Windows', () {
      expect(AppFonts.debugIsPlausibleBoldBasename('arial', 'arialbd'), isTrue);
      expect(AppFonts.debugIsPlausibleBoldBasename('times', 'timesbd'), isTrue);
      expect(AppFonts.debugIsPlausibleBoldBasename('david', 'davidbd'), isTrue);
      expect(
        AppFonts.debugIsPlausibleBoldBasename('segoeui', 'segoeuib'),
        isTrue,
      );
      expect(
        AppFonts.debugIsPlausibleBoldBasename('David Bold', 'davidbold') ||
            AppFonts.debugIsPlausibleBoldBasename('david', 'David-Bold'),
        isTrue,
      );
    });

    test('נטוי/משקל אחר/זהה אינם מתאימים', () {
      expect(
        AppFonts.debugIsPlausibleBoldBasename('arial', 'arialbi'),
        isFalse,
      );
      expect(AppFonts.debugIsPlausibleBoldBasename('arial', 'ariblk'), isFalse);
      expect(AppFonts.debugIsPlausibleBoldBasename('arial', 'arial'), isFalse);
      expect(AppFonts.debugIsPlausibleBoldBasename('', 'anything'), isFalse);
    });
  });

  group('AppFonts.boldFontVariations', () {
    test('גופן משתנה מקבל FontVariation wght לפי המשקל', () {
      expect(AppFonts.boldFontVariations('Rubik'), const [
        FontVariation('wght', 700),
      ]);
      expect(
        AppFonts.boldFontVariations('NotoRashiHebrew', FontWeight.w800),
        const [FontVariation('wght', 800)],
      );
    });

    test('גופן לא-משתנה או משקל רגיל מחזיר null', () {
      expect(AppFonts.boldFontVariations('FrankRuhlCLM'), isNull);
      expect(AppFonts.boldFontVariations(null), isNull);
      expect(AppFonts.boldFontVariations('Rubik', FontWeight.normal), isNull);
    });
  });
}
