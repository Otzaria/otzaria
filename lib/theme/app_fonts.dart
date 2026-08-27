import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        compute,
        defaultTargetPlatform,
        kIsWeb,
        visibleForTesting;
import 'package:flutter/services.dart' show FontLoader;
import 'package:path/path.dart' as p;
import 'package:system_fonts/system_fonts.dart' show SystemFonts;
import 'package:otzaria/utils/file/font_file_reader.dart';
import 'package:otzaria/utils/file/sfnt_metadata_reader.dart';
import 'package:otzaria/utils/file/system_font_locator.dart';

/// סיווג גופן לפי סגנון: עם תגיות (serif) או חלק (sans-serif).
enum FontCategory { serif, sansSerif, unknown }

/// רשימת הגופנים הזמינים באפליקציה
class AppFonts {
  AppFonts._();

  /// גופן ברירת מחדל לטקסט ראשי
  static const String defaultFont = 'FrankRuhlCLM';

  /// גופן ברירת מחדל למפרשים
  static const String defaultCommentatorsFont = 'NotoRashiHebrew';

  /// גופן לעריכת טקסט עם טעמים
  static const String editorFont = 'TaameyAshkenaz';

  /// גופנים משתנים (Variable Fonts) עם ציר wght. Flutter לא ממפה
  /// FontWeight.bold לציר הזה אוטומטית — בלי FontVariation מפורש הבולד יוצא
  /// מלאכותי (faux). ראו [boldFontVariations].
  static const Set<String> variableWeightFonts = {
    'Rubik',
    'NotoRashiHebrew',
    'NotoSerifHebrew',
  };

  /// גופני מערכת שזוהו כ-Variable Fonts עם ציר wght בזמן טעינה.
  /// מאוכלס ב-[ensureFontLoaded]; נצרך ל-[boldFontVariations].
  static final Set<String> _variableSystemFonts = {};

  /// מחזיר את ה-[FontVariation] הנדרש כדי לקבל בולד אמיתי בגופן משתנה,
  /// או null כשאין צורך (גופן לא-משתנה, או משקל לא-מודגש — אז בחירת ה-face
  /// הרגילה של Flutter מטפלת). מוחזר רק ממשקל w600 ומעלה.
  static List<FontVariation>? boldFontVariations(
    String? fontFamily, [
    FontWeight weight = FontWeight.bold,
  ]) {
    if (fontFamily == null) return null;
    final isVariable =
        variableWeightFonts.contains(fontFamily) ||
        _variableSystemFonts.contains(fontFamily);
    if (!isVariable) return null;
    if (weight.value < FontWeight.w600.value) return null;
    return [FontVariation('wght', weight.value.toDouble())];
  }

  /// גופנים מובנים שנרשמו ב-pubspec עם קובץ בולד נפרד. ב-face נפרד ציור האות
  /// שונה מה-regular, ולכן כותרת מודגשת נראית כגופן אחר מהגוף.
  static const Set<String> _separateBoldFaceFonts = {'FrankRuhlCLM'};

  /// גופני מערכת שנטען עבורם קובץ בולד אחי ב-[_augmentSystemFontWeights].
  /// מאוכלס בזמן ריצה — אצל משתמש אחד לגופן יש קובץ בולד מותקן ואצל אחר לא.
  static final Set<String> _separateBoldSystemFonts = {};

  /// האם הבולד של [fontFamily] מגיע מקובץ נפרד (ולא מעיבוי/ציר של אותו קובץ).
  /// גופן משתנה מחזיר false — הבולד שלו הוא אותו ציור אות על ציר wght.
  static bool hasSeparateBoldFace(String? fontFamily) =>
      fontFamily != null &&
      (_separateBoldFaceFonts.contains(fontFamily) ||
          _separateBoldSystemFonts.contains(fontFamily));

  static const Set<String> headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

  /// משקל הכותרת ל-`customStylesBuilder` של fwfh, או null כשאין מה לשנות.
  /// fwfh מדגיש כל `<h1>`-`<h6>` אוטומטית; במשפחה עם face בולד נפרד הכותרת
  /// נשלפת מקובץ אחר מהגוף — שני ציורי אות באותו מסך.
  /// '400' ולא 'normal' — fontWeightTryParse של fwfh מזהה רק מספר או 'bold'.
  static String? headingFontWeightOverride(
    String? elementTag,
    String? fontFamily,
  ) {
    if (elementTag == null || !headingTags.contains(elementTag)) return null;
    return hasSeparateBoldFace(fontFamily) ? '400' : null;
  }

  static bool get _supportsSystemFonts {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// רשימת הגופנים המובנים (מוטמעים באפליקציה / רשימת ברירת מחדל)
  /// הערה: לא כוללת גופני מערכת כלל; בדסקטופ הם נטענים/מסוננים אוטומטית.
  static const List<FontInfo> _bundledFonts = [
    FontInfo(
      value: 'TaameyDavidCLM',
      label: 'דוד',
      category: FontCategory.serif,
    ),
    FontInfo(
      value: 'FrankRuhlCLM',
      label: 'פרנק-רוהל',
      category: FontCategory.serif,
    ),
    FontInfo(
      value: 'TaameyAshkenaz',
      label: 'טעמי אשכנז',
      category: FontCategory.serif,
    ),
    FontInfo(value: 'KeterYG', label: 'כתר', category: FontCategory.serif),
    FontInfo(value: 'Shofar', label: 'שופר', category: FontCategory.sansSerif),
    FontInfo(
      value: 'NotoSerifHebrew',
      label: 'נוטו',
      category: FontCategory.serif,
    ),
    FontInfo(value: 'Tinos', label: 'טינוס', category: FontCategory.serif),
    FontInfo(
      value: 'NotoRashiHebrew',
      label: 'רש"י',
      category: FontCategory.serif,
    ),
    FontInfo(value: 'Rubik', label: 'רוביק', category: FontCategory.sansSerif),
  ];

  static List<FontInfo>? _systemFontsHebrewCache;
  static Map<String, SystemFontFamilyFaces>? _systemFamiliesCache;
  static Map<String, String>? _systemFontAliasCache;
  static Future<void>? _warmUpFuture;

  /// רשימת כל הגופנים הזמינים לבחירה ב-UI.
  /// בדסקטופ: מתווספים גם גופנים שמותקנים במערכת (באמצעות system_fonts).
  /// בשאר הפלטפורמות: נשארים עם הרשימה המובנית.
  static List<FontInfo> get availableFonts {
    final fonts = <FontInfo>[..._bundledFonts];

    if (_supportsSystemFonts) {
      fonts.addAll(_getSystemFontsHebrewOnly());
    }

    return fonts;
  }

  /// טוען מראש לקאש את גופני המערכת התומכים בעברית, ברקע (compute isolate).
  /// נועד למניעת קפיאת UI בכניסה הראשונה לטאב הגדרות "כתב",
  /// שבו `availableFonts` נקרא ומריץ סריקת בינארי על מאות קבצי גופן.
  /// בטוח לקריאה מרובה — אם הקאש כבר חם או שכבר רצה משימת חימום, חוזר מיידית.
  static Future<void> warmUpSystemFontsCache() {
    if (_systemFontsHebrewCache != null) return Future.value();
    if (!_supportsSystemFonts) return Future.value();
    return _warmUpFuture ??= _runWarmUp();
  }

  static Future<void> _runWarmUp() async {
    try {
      final result = await compute(_computeSystemFontScan, 0);
      _storeScan(result);
    } catch (_) {
      // אם החימום ב-isolate נכשל מסיבה כלשהי - לא מאתחלים את הקאש,
      // והנתיב הסינכרוני ב-_getSystemFontsHebrewOnly ירוץ בפעם הראשונה.
    }
  }

  /// פונקציה שרצה ב-isolate נפרד דרך `compute`.
  /// חייבת להיות סטטית/top-level וללא תלות במצב של isolate הראשי.
  static SystemFontScanResult _computeSystemFontScan(int _) {
    return _scanSystemFonts();
  }

  static void _storeScan(SystemFontScanResult scan) {
    if (_systemFontsHebrewCache != null) return;
    _systemFontsHebrewCache = scan.fonts;
    _systemFamiliesCache = scan.families;
    _systemFontAliasCache = scan.aliases;
  }

  static List<FontInfo> _getSystemFontsHebrewOnly() {
    if (_systemFontsHebrewCache != null) {
      return _systemFontsHebrewCache!;
    }

    _storeScan(_scanSystemFonts());
    return _systemFontsHebrewCache!;
  }

  static SystemFontScanResult _scanSystemFonts() {
    try {
      return _buildScan(_installedFacesLazily());
    } catch (_) {
      // אם אין גישה לגופני מערכת מסיבה כלשהי, נחזיר תוצאה ריקה.
      return const SystemFontScanResult.empty();
    }
  }

  /// עצל בכוונה: הבייטים של כל גופן משתחררים לפני קריאת הבא, במקום להחזיק
  /// את כל הגופנים המותקנים בזיכרון בבת אחת (מאות MB במחשב עם Office).
  static Iterable<MapEntry<String, Uint8List>> _installedFacesLazily() sync* {
    for (final path in SystemFontLocator.installedFontPaths()) {
      final bytes = SfntMetadataReader.readSync(path);
      if (bytes == null) continue;
      yield MapEntry(path, bytes);
    }
  }

  /// מקבץ קבצי גופן למשפחות לפי שם המשפחה מטבלת ה-name (לא לפי שם הקובץ —
  /// התקנה פר-משתמש שומרת שמות קבצים שרירותיים שהמשתמש אינו מזהה).
  static SystemFontScanResult _buildScan(
    Iterable<MapEntry<String, Uint8List>> faces,
  ) {
    final builders = <String, _FamilyAccumulator>{};
    final aliases = <String, String>{};
    for (final face in faces) {
      final bytes = face.value;
      if (!_sfntSupportsHebrew(bytes)) continue;
      final info = _sfntFaceInfo(bytes);
      if (info == null || info.italic) continue;
      // p.windows מפרק גם נתיבי \ וגם / — נתיבי ה-registry של Windows מגיעים
      // עם \ גם כשהקוד (ובדיקותיו) רץ על פלטפורמה אחרת.
      final family = info.family.trim().isNotEmpty
          ? info.family.trim()
          : p.windows.basenameWithoutExtension(face.key);
      final acc = builders.putIfAbsent(
        family.toLowerCase(),
        () => _FamilyAccumulator(family),
      );
      acc.addFace(path: face.key, info: info, category: _sfntCategory(bytes));
      aliases[p.windows.basenameWithoutExtension(face.key).toLowerCase()] =
          family;
    }

    final fonts = <FontInfo>[];
    final families = <String, SystemFontFamilyFaces>{};
    for (final acc in builders.values) {
      final familyFaces = acc.build();
      families[familyFaces.family] = familyFaces;
      fonts.add(
        FontInfo(
          value: familyFaces.family,
          label: familyFaces.family,
          category: familyFaces.category,
        ),
      );
    }
    fonts.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return SystemFontScanResult(
      fonts: fonts,
      families: families,
      aliases: aliases,
    );
  }

  /// שם המשפחה עבור ערך שמור ישן (שם קובץ מהסריקה הקודמת), או null.
  static String? legacySystemFontDisplayName(String value) =>
      _systemFontAliasCache?[value.toLowerCase()];

  static Uint8List? _readFontBytesSync(String path) {
    try {
      return Uint8List.fromList(FontFileReader.readBytesSync(path));
    } catch (_) {
      return null;
    }
  }

  /// [base] = היסט תחילת ה-Offset Table של הגופן. ב-TTC ה-offsets בטבלאות
  /// מוחלטים (יחסית לקובץ), לכן נשמר על כל ה-data ומקדמים רק את ה-base.
  static bool _sfntSupportsHebrew(Uint8List data, [int base = 0]) {
    // TTC (TrueType Collection): magic "ttcf" at offset 0.
    // numFonts at offset 8; font offsets start at offset 12.
    if (base == 0 &&
        data.length >= 16 &&
        data[0] == 0x74 &&
        data[1] == 0x74 &&
        data[2] == 0x63 &&
        data[3] == 0x66) {
      final numFonts =
          (data[8] << 24) | (data[9] << 16) | (data[10] << 8) | data[11];
      for (int i = 0; i < numFonts; i++) {
        final offsetPos = 12 + i * 4;
        if (offsetPos + 4 > data.length) break;
        final fontOffset =
            (data[offsetPos] << 24) |
            (data[offsetPos + 1] << 16) |
            (data[offsetPos + 2] << 8) |
            data[offsetPos + 3];
        if (fontOffset <= 0 || fontOffset >= data.length) continue;
        if (_sfntSupportsHebrew(data, fontOffset)) {
          return true;
        }
      }
      return false;
    }

    // Hebrew blocks to detect:
    // - U+0590..U+05FF (Hebrew)
    // - U+FB1D..U+FB4F (Hebrew Presentation Forms)
    const hebrewStart = 0x0590;
    const hebrewEnd = 0x05FF;
    const hebrewPresStart = 0xFB1D;
    const hebrewPresEnd = 0xFB4F;

    bool overlapsHebrew(int start, int end) {
      if (end < start) return false;
      final overlapsMain = end >= hebrewStart && start <= hebrewEnd;
      if (overlapsMain) return true;
      final overlapsPres = end >= hebrewPresStart && start <= hebrewPresEnd;
      return overlapsPres;
    }

    int u16(int offset) {
      if (offset + 2 > data.length) return -1;
      return (data[offset] << 8) | data[offset + 1];
    }

    int u32(int offset) {
      if (offset + 4 > data.length) return -1;
      return (data[offset] << 24) |
          (data[offset + 1] << 16) |
          (data[offset + 2] << 8) |
          data[offset + 3];
    }

    String tag4(int offset) {
      if (offset + 4 > data.length) return '';
      return String.fromCharCodes(data.sublist(offset, offset + 4));
    }

    // Offset table (ב-base; היסטי הטבלאות מוחלטים בתוך data).
    if (base + 12 > data.length) return false;
    final numTables = u16(base + 4);
    if (numTables <= 0) return false;

    // Table records
    int cmapOffset = -1;
    int cmapLength = -1;
    final tableDirOffset = base + 12;
    final recordSize = 16;
    final dirSize = tableDirOffset + numTables * recordSize;
    if (dirSize > data.length) return false;

    for (int i = 0; i < numTables; i++) {
      final rec = tableDirOffset + i * recordSize;
      final tag = tag4(rec);
      if (tag == 'cmap') {
        cmapOffset = u32(rec + 8);
        cmapLength = u32(rec + 12);
        break;
      }
    }
    if (cmapOffset < 0 || cmapLength <= 0) return false;
    if (cmapOffset + cmapLength > data.length) return false;

    // cmap header
    if (cmapOffset + 4 > data.length) return false;
    final cmapNumTables = u16(cmapOffset + 2);
    if (cmapNumTables <= 0) return false;

    // Choose best subtable.
    // Prefer: (platform 0) then (platform 3, enc 10) then (platform 3, enc 1)
    final encodingRecordsOffset = cmapOffset + 4;
    final encodingRecordSize = 8;
    final encDirSize =
        encodingRecordsOffset + cmapNumTables * encodingRecordSize;
    if (encDirSize > data.length) return false;

    int? bestSubtableOffset;
    int bestRank = 999;
    for (int i = 0; i < cmapNumTables; i++) {
      final rec = encodingRecordsOffset + i * encodingRecordSize;
      final platformId = u16(rec);
      final encodingId = u16(rec + 2);
      final subOffset = u32(rec + 4);
      if (subOffset < 0) continue;
      final abs = cmapOffset + subOffset;
      if (abs < 0 || abs + 2 > data.length) continue;

      int rank = 999;
      if (platformId == 0) {
        rank = 0;
      } else if (platformId == 3 && encodingId == 10) {
        rank = 1;
      } else if (platformId == 3 && encodingId == 1) {
        rank = 2;
      }

      if (rank < bestRank) {
        bestRank = rank;
        bestSubtableOffset = abs;
      }
    }

    if (bestSubtableOffset == null) return false;
    final format = u16(bestSubtableOffset);
    if (format < 0) return false;

    if (format == 4) {
      // Format 4 (BMP)
      final length = u16(bestSubtableOffset + 2);
      if (length <= 0) return false;
      if (bestSubtableOffset + length > data.length) return false;

      final segCountX2 = u16(bestSubtableOffset + 6);
      if (segCountX2 <= 0 || (segCountX2 % 2) != 0) return false;
      final segCount = segCountX2 ~/ 2;

      final endCodesOffset = bestSubtableOffset + 14;
      final reservedPadOffset = endCodesOffset + segCount * 2;
      final startCodesOffset = reservedPadOffset + 2;
      final idDeltasOffset = startCodesOffset + segCount * 2;
      final idRangeOffsetOffset = idDeltasOffset + segCount * 2;
      if (idRangeOffsetOffset + segCount * 2 > data.length) return false;

      for (int i = 0; i < segCount; i++) {
        final endCode = u16(endCodesOffset + i * 2);
        final startCode = u16(startCodesOffset + i * 2);
        if (endCode < 0 || startCode < 0) continue;

        // End sentinel often uses 0xFFFF.
        if (endCode == 0xFFFF && startCode == 0xFFFF) continue;
        if (overlapsHebrew(startCode, endCode)) return true;
      }
      return false;
    }

    if (format == 12) {
      // Format 12 (full Unicode)
      // u16 format, u16 reserved, u32 length, u32 language, u32 nGroups
      final length = u32(bestSubtableOffset + 4);
      if (length <= 0) return false;
      if (bestSubtableOffset + length > data.length) return false;

      final nGroups = u32(bestSubtableOffset + 12);
      if (nGroups <= 0) return false;
      final groupsOffset = bestSubtableOffset + 16;
      const groupSize = 12;
      if (groupsOffset + nGroups * groupSize > data.length) return false;

      for (int i = 0; i < nGroups; i++) {
        final off = groupsOffset + i * groupSize;
        final startChar = u32(off);
        final endChar = u32(off + 4);
        if (startChar < 0 || endChar < 0) continue;
        if (overlapsHebrew(startChar, endChar)) return true;
      }
      return false;
    }

    // Unsupported cmap format (0, 6, 10, 13, 14...).
    return false;
  }

  /// מזהה סגנון גופן (serif / sans-serif) מטבלת OS/2.
  /// מסתמך על sFamilyClass, ונופל ל-PANOSE כגיבוי. אצל גופנים עבריים
  /// רבים השדות ריקים — ואז מוחזר [FontCategory.unknown].
  static FontCategory _sfntCategory(Uint8List data, [int base = 0]) {
    // TTC: נבדק את הגופן הראשון בלבד לצורך הסיווג.
    if (base == 0 &&
        data.length >= 16 &&
        data[0] == 0x74 &&
        data[1] == 0x74 &&
        data[2] == 0x63 &&
        data[3] == 0x66) {
      final numFonts =
          (data[8] << 24) | (data[9] << 16) | (data[10] << 8) | data[11];
      for (int i = 0; i < numFonts; i++) {
        final offsetPos = 12 + i * 4;
        if (offsetPos + 4 > data.length) break;
        final fontOffset =
            (data[offsetPos] << 24) |
            (data[offsetPos + 1] << 16) |
            (data[offsetPos + 2] << 8) |
            data[offsetPos + 3];
        if (fontOffset <= 0 || fontOffset >= data.length) continue;
        final cat = _sfntCategory(data, fontOffset);
        if (cat != FontCategory.unknown) return cat;
      }
      return FontCategory.unknown;
    }

    int u16(int offset) {
      if (offset + 2 > data.length) return -1;
      return (data[offset] << 8) | data[offset + 1];
    }

    int u32(int offset) {
      if (offset + 4 > data.length) return -1;
      return (data[offset] << 24) |
          (data[offset + 1] << 16) |
          (data[offset + 2] << 8) |
          data[offset + 3];
    }

    // Offset table (ב-base; היסטי הטבלאות מוחלטים בתוך data).
    if (base + 12 > data.length) return FontCategory.unknown;
    final numTables = u16(base + 4);
    if (numTables <= 0) return FontCategory.unknown;

    final tableDirOffset = base + 12;
    const recordSize = 16;
    if (tableDirOffset + numTables * recordSize > data.length) {
      return FontCategory.unknown;
    }

    int os2Offset = -1;
    for (int i = 0; i < numTables; i++) {
      final rec = tableDirOffset + i * recordSize;
      if (rec + 4 > data.length) break;
      if (data[rec] == 0x4F && // 'O'
          data[rec + 1] == 0x53 && // 'S'
          data[rec + 2] == 0x2F && // '/'
          data[rec + 3] == 0x32) {
        // '2'
        os2Offset = u32(rec + 8);
        break;
      }
    }
    if (os2Offset < 0 || os2Offset + 42 > data.length) {
      return FontCategory.unknown;
    }

    // sFamilyClass (int16 @ 30) — הבייט הגבוה הוא מזהה המחלקה.
    final familyClass = u16(os2Offset + 30);
    if (familyClass >= 0) {
      final classId = (familyClass >> 8) & 0xFF;
      switch (classId) {
        case 1: // Oldstyle Serifs
        case 2: // Transitional Serifs
        case 3: // Modern Serifs
        case 4: // Clarendon Serifs
        case 5: // Slab Serifs
        case 7: // Freeform Serifs
          return FontCategory.serif;
        case 8: // Sans Serif
          return FontCategory.sansSerif;
      }
    }

    // גיבוי: PANOSE (@ 32). bFamilyType==2 (Latin Text) → bSerifStyle מבחין.
    final familyType = data[os2Offset + 32];
    final serifStyle = data[os2Offset + 33];
    if (familyType == 2) {
      if (serifStyle >= 2 && serifStyle <= 10) return FontCategory.serif;
      if (serifStyle >= 11 && serifStyle <= 13) return FontCategory.sansSerif;
    }

    return FontCategory.unknown;
  }

  /// מיפוי גופנים לנתיבי קבצים (לשימוש בהדפסה)
  /// הערה: רק גופנים עם קבצים בתיקיית fonts נתמכים בהדפסה
  static const Map<String, String> fontPaths = {
    'TaameyDavidCLM': 'fonts/TaameyDavidCLM-Medium.ttf',
    'FrankRuhlCLM': 'fonts/FrankRuehlCLM-Medium.ttf',
    'TaameyAshkenaz': 'fonts/TaameyAshkenaz-Medium.ttf',
    'KeterYG': 'fonts/KeterYG-Medium.ttf',
    'Shofar': 'fonts/ShofarRegular.ttf',
    'NotoSerifHebrew': 'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
    'Tinos': 'fonts/Tinos-Regular.ttf',
    'NotoRashiHebrew': 'fonts/NotoRashiHebrew-VariableFont_wght.ttf',
    'Rubik': 'fonts/Rubik-VariableFont_wght.ttf',
  };

  /// קובץ ה-face הבולד של גופן מובנה, למשפחות שנרשמו ב-pubspec עם קובץ נפרד.
  /// צרכן חיצוני שמקבל רק את ה-regular (WebView של תוסף) מסנתז בולד מרוח.
  static const Map<String, String> boldFontPaths = {
    'FrankRuhlCLM': 'fonts/FrankRuehlCLM-Bold.ttf',
  };

  /// ה-faces של גופן מערכת שאותר בסריקה, או null כשאינו מוכר.
  /// דורש שהקאש יהיה חם — ראו [warmUpSystemFontsCache].
  static SystemFontFamilyFaces? systemFamilyFaces(String fontFamily) =>
      _systemFamiliesCache?[fontFamily];

  /// בייטים של קובץ גופן מהדיסק, או null כשאינו קריא.
  static Uint8List? readFontBytes(String path) => _readFontBytesSync(path);

  /// מיפוי גופנים לשמות בעברית (לשימוש בהדפסה)
  /// מחושב אוטומטית מ-availableFonts, רק עבור גופנים עם קבצים
  static Map<String, String> get fontLabels => {
    for (final font in availableFonts)
      if (fontPaths.containsKey(font.value)) font.value: font.label,
  };

  /// יצירת רשימת DropdownMenuItem לבחירת גופן
  static List<DropdownMenuItem<String>> buildDropdownItems({
    String? selectedValue,
    TextStyle? itemTextStyle,
  }) {
    final fonts = [...availableFonts];
    final hasSelectedValue =
        selectedValue == null ||
        selectedValue.isEmpty ||
        fonts.any((font) => font.value == selectedValue);

    if (!hasSelectedValue) {
      final legacyName = legacySystemFontDisplayName(selectedValue);
      fonts.insert(
        0,
        FontInfo(
          value: selectedValue,
          label: legacyName ?? '$selectedValue (לא זמין במחשב זה)',
        ),
      );
    }

    return fonts.map((font) {
      final previewStyle = fontPaths.containsKey(font.value)
          ? TextStyle(fontFamily: font.value)
          : const TextStyle();
      return DropdownMenuItem<String>(
        value: font.value,
        child: Text(
          font.label,
          style: previewStyle.merge(itemTextStyle),
        ),
      );
    }).toList();
  }

  /// גופני מערכת שכבר נטענו (או בתהליך טעינה) — מונע טעינה כפולה ברשימה גדולה.
  static final Map<String, Future<void>> _loadingSystemFonts = {};

  /// טוען גופן מערכת (אם קיים) כדי שניתן יהיה להשתמש בו ב-TextStyle.
  /// אם הגופן כבר מוטמע באפליקציה או שאין תמיכה בגופני מערכת - לא עושה כלום.
  /// הטעינה ממוזכרת: קריאות חוזרות לאותו גופן חולקות את אותו Future.
  static Future<void> ensureFontLoaded(String fontFamily) {
    if (fontFamily.isEmpty) return Future.value();
    if (fontPaths.containsKey(fontFamily)) return Future.value();
    if (!_supportsSystemFonts) return Future.value();

    return _loadingSystemFonts.putIfAbsent(fontFamily, () async {
      try {
        if (_systemFamiliesCache == null) await warmUpSystemFontsCache();
        final family = _systemFamiliesCache?[fontFamily];
        if (family != null) {
          await _loadFamilyFaces(fontFamily, family);
          return;
        }
        // תאימות לאחור: ערך שמור מגרסה קודמת הוא שם קובץ במפת system_fonts.
        await SystemFonts().loadFont(fontFamily);
      } catch (_) {
        // אם הטעינה נכשלה, מסירים מהקאש כדי לאפשר ניסיון חוזר בעתיד.
        _loadingSystemFonts.remove(fontFamily);
        return;
      }
      await _augmentSystemFontWeights(fontFamily);
    });
  }

  /// טוען את ה-face הרגיל של המשפחה, ואם קיים face בולד — גם אותו תחת אותו
  /// שם, כך שהמנוע יבחר בו אוטומטית למשקלים מודגשים.
  static Future<void> _loadFamilyFaces(
    String name,
    SystemFontFamilyFaces family,
  ) async {
    final regular = _readFontBytesSync(family.regularPath);
    if (regular == null) {
      throw StateError('font file unreadable: ${family.regularPath}');
    }
    final loader = FontLoader(name)
      ..addFont(Future.value(ByteData.sublistView(regular)));
    Uint8List? bold;
    final boldPath = family.boldPath;
    if (boldPath != null) {
      bold = _readFontBytesSync(boldPath);
      if (bold != null) {
        loader.addFont(Future.value(ByteData.sublistView(bold)));
      }
    }
    await loader.load();
    if (family.hasWeightAxis) _variableSystemFonts.add(name);
    if (bold != null) _separateBoldSystemFonts.add(name);
  }

  /// אחרי טעינת ה-face הרגיל של גופן מערכת, מנסה להעשיר את המשפחה בבולד אמיתי:
  /// גופן משתנה עם ציר wght → מסומן ל-[boldFontVariations]; אחרת נטען קובץ
  /// בולד נפרד (למשל "arialbd") תחת אותו שם משפחה, כדי שהמנוע יבחר בו לבולד.
  /// לעולם לא זורק — כישלון כאן אינו משפיע על טעינת ה-face הרגיל.
  static Future<void> _augmentSystemFontWeights(String fontFamily) async {
    try {
      final map = SystemFonts().getFontMap();
      final selfPath = map[fontFamily];
      if (selfPath == null) return;
      final selfBytes = SfntMetadataReader.readSync(selfPath);
      if (selfBytes == null) return;
      final selfInfo = _sfntFaceInfo(selfBytes);
      if (selfInfo == null) return;

      // גופן משתנה: אין קובץ בולד נפרד — הבולד מגיע דרך FontVariation('wght').
      if (selfInfo.hasWeightAxis) {
        _variableSystemFonts.add(fontFamily);
        return;
      }

      for (final entry in map.entries) {
        if (entry.key == fontFamily) continue;
        if (!_isPlausibleBoldBasename(fontFamily, entry.key)) continue;
        final bytes = _readFontBytesSync(entry.value);
        if (bytes == null) continue;
        final info = _sfntFaceInfo(bytes);
        if (info == null || !_isBoldSibling(selfInfo, info)) continue;
        await (FontLoader(
          fontFamily,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        _separateBoldSystemFonts.add(fontFamily);
        return;
      }
    } catch (_) {
      // איתור/טעינת הבולד נכשל — משאירים את הגופן הרגיל כפי שנטען.
    }
  }

  /// סיומות בסיס-שם נפוצות ל-face בולד ב-Windows (אחרי נרמול): arial→arialbd,
  /// segoeui→segoeuib, times→timesbd.
  static const List<String> _boldBasenameSuffixes = ['bold', 'bd', 'b'];

  static String _normalizeFontName(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// סינון מוקדם (מחרוזות בלבד, ללא קריאת קבצים): האם [candidate] נראה כמו
  /// שם קובץ הבולד של [selected]. האימות הסופי נעשה מול טבלאות ה-SFNT.
  static bool _isPlausibleBoldBasename(String selected, String candidate) {
    final s = _normalizeFontName(selected);
    final c = _normalizeFontName(candidate);
    if (s.isEmpty || c == s) return false;
    for (final suffix in _boldBasenameSuffixes) {
      if (c == '$s$suffix') return true;
    }
    return false;
  }

  /// האם [candidate] הוא ה-face הבולד (הלא-נטוי) של אותה משפחה כמו [regular].
  static bool _isBoldSibling(_FontFaceInfo regular, _FontFaceInfo candidate) {
    if (candidate.italic || !candidate.isBoldStyle) return false;
    final rf = regular.family.toLowerCase().trim();
    final cf = candidate.family.toLowerCase().trim();
    if (rf.isEmpty || cf.isEmpty) return false;
    return rf == cf;
  }

  /// קורא מטבלאות ה-SFNT את שם המשפחה, מחלקת המשקל וסימוני בולד/נטוי/ציר-wght.
  /// מחזיר null אם המבנה פגום. אינו תומך ב-TTC (system_fonts מחזיר ttf/otf בלבד).
  static _FontFaceInfo? _sfntFaceInfo(Uint8List data) {
    int u16(int o) => (o + 2 > data.length) ? -1 : (data[o] << 8) | data[o + 1];
    int u32(int o) => (o + 4 > data.length)
        ? -1
        : (data[o] << 24) |
              (data[o + 1] << 16) |
              (data[o + 2] << 8) |
              data[o + 3];
    String tag4(int o) => (o + 4 > data.length)
        ? ''
        : String.fromCharCodes(data.sublist(o, o + 4));

    if (data.length < 12) return null;
    final numTables = u16(4);
    if (numTables <= 0) return null;
    const dir = 12;
    if (dir + numTables * 16 > data.length) return null;

    int os2 = -1, head = -1, name = -1, fvar = -1;
    for (int i = 0; i < numTables; i++) {
      final rec = dir + i * 16;
      switch (tag4(rec)) {
        case 'OS/2':
          os2 = u32(rec + 8);
        case 'head':
          head = u32(rec + 8);
        case 'name':
          name = u32(rec + 8);
        case 'fvar':
          fvar = u32(rec + 8);
      }
    }

    int weightClass = 0;
    bool bold = false;
    bool italic = false;
    if (os2 >= 0 && os2 + 64 <= data.length) {
      final w = u16(os2 + 4);
      if (w > 0) weightClass = w;
      final fsSel = u16(os2 + 62);
      if (fsSel >= 0) {
        italic = (fsSel & 0x01) != 0;
        bold = (fsSel & 0x20) != 0;
      }
    }
    if (head >= 0 && head + 46 <= data.length) {
      final macStyle = u16(head + 44);
      if (macStyle >= 0) {
        bold = bold || (macStyle & 0x01) != 0;
        italic = italic || (macStyle & 0x02) != 0;
      }
    }

    final family = _readSfntFamilyName(data, name, u16);

    bool hasWeightAxis = false;
    if (fvar >= 0 && fvar + 16 <= data.length) {
      final axesOffset = u16(fvar + 4);
      final axisCount = u16(fvar + 8);
      final axisSize = u16(fvar + 10);
      if (axesOffset > 0 && axisCount > 0 && axisSize >= 4) {
        final axesBase = fvar + axesOffset;
        for (int i = 0; i < axisCount; i++) {
          if (tag4(axesBase + i * axisSize) == 'wght') {
            hasWeightAxis = true;
            break;
          }
        }
      }
    }

    return _FontFaceInfo(
      family: family,
      weightClass: weightClass,
      bold: bold,
      italic: italic,
      hasWeightAxis: hasWeightAxis,
    );
  }

  /// שם המשפחה מטבלת ה-name. מעדיף typographic family (nameID 16) על-פני
  /// שם המשפחה הבסיסי (nameID 1), כך ש-Regular ו-Bold מקבלים שם זהה.
  /// בכל nameID מועדפת רשומת Windows (platform 3) — Windows מקבץ לפיה, ובגופני
  /// Medium רבים רשומות פלטפורמה 0/1 נושאות את שם הבסיס וממזגות משפחות שונות.
  static String _readSfntFamilyName(
    Uint8List data,
    int nameOffset,
    int Function(int) u16,
  ) {
    if (nameOffset < 0 || nameOffset + 6 > data.length) return '';
    final count = u16(nameOffset + 2);
    final storageOffset = nameOffset + u16(nameOffset + 4);
    if (count <= 0) return '';
    final recordsBase = nameOffset + 6;
    if (recordsBase + count * 12 > data.length) return '';

    String? typographicWindows;
    String? typographic;
    String? basicWindows;
    String? basic;
    for (int i = 0; i < count; i++) {
      final rec = recordsBase + i * 12;
      final nameId = u16(rec + 6);
      if (nameId != 1 && nameId != 16) continue;
      final platformId = u16(rec);
      final length = u16(rec + 8);
      final strOffset = storageOffset + u16(rec + 10);
      if (length <= 0 || strOffset + length > data.length) continue;

      final String decoded;
      if (platformId == 1) {
        decoded = String.fromCharCodes(
          data.sublist(strOffset, strOffset + length),
        );
      } else {
        // platform 0/3: UTF-16BE.
        final units = <int>[];
        for (int j = 0; j + 1 < length; j += 2) {
          units.add((data[strOffset + j] << 8) | data[strOffset + j + 1]);
        }
        decoded = String.fromCharCodes(units);
      }
      if (decoded.trim().isEmpty) continue;
      if (nameId == 16) {
        if (platformId == 3) {
          typographicWindows ??= decoded;
        } else {
          typographic ??= decoded;
        }
      } else {
        if (platformId == 3) {
          basicWindows ??= decoded;
        } else {
          basic ??= decoded;
        }
      }
    }
    return (typographicWindows ?? typographic ?? basicWindows ?? basic ?? '')
        .trim();
  }

  @visibleForTesting
  static bool debugSfntSupportsHebrew(Uint8List data) =>
      _sfntSupportsHebrew(data);

  @visibleForTesting
  static FontCategory debugSfntCategory(Uint8List data) => _sfntCategory(data);

  @visibleForTesting
  static List<FontInfo>? get debugSystemFontsHebrewCache =>
      _systemFontsHebrewCache;

  @visibleForTesting
  static set debugSystemFontsHebrewCache(List<FontInfo>? cache) {
    _systemFontsHebrewCache = cache;
  }

  @visibleForTesting
  static Future<void>? get debugWarmUpFuture => _warmUpFuture;

  /// מדמה גופן מערכת שנטען לו קובץ בולד אחי, בלי תלות בגופנים מותקנים.
  @visibleForTesting
  static void debugMarkSeparateBoldSystemFont(String fontFamily) {
    _separateBoldSystemFonts.add(fontFamily);
  }

  @visibleForTesting
  static void debugResetSystemFontsCache() {
    _systemFontsHebrewCache = null;
    _systemFamiliesCache = null;
    _systemFontAliasCache = null;
    _warmUpFuture = null;
    _variableSystemFonts.clear();
    _separateBoldSystemFonts.clear();
  }

  /// מריץ את קיבוץ ה-faces על נתונים סינתטיים, בלי תלות בגופנים מותקנים.
  @visibleForTesting
  static SystemFontScanResult debugBuildScan(
    List<MapEntry<String, Uint8List>> faces,
  ) => _buildScan(faces);

  /// מאחסן תוצאת סריקה כאילו הגיעה מחימום הקאש (לבדיקת מסלולי התצוגה).
  @visibleForTesting
  static void debugStoreScan(SystemFontScanResult scan) => _storeScan(scan);

  @visibleForTesting
  static int debugFontWeightClass(Uint8List data) =>
      _sfntFaceInfo(data)?.weightClass ?? 0;

  @visibleForTesting
  static bool debugFontIsBoldStyle(Uint8List data) =>
      _sfntFaceInfo(data)?.isBoldStyle ?? false;

  @visibleForTesting
  static bool debugFontIsItalic(Uint8List data) =>
      _sfntFaceInfo(data)?.italic ?? false;

  @visibleForTesting
  static String debugFontFamilyName(Uint8List data) =>
      _sfntFaceInfo(data)?.family ?? '';

  @visibleForTesting
  static bool debugFontHasWeightAxis(Uint8List data) =>
      _sfntFaceInfo(data)?.hasWeightAxis ?? false;

  @visibleForTesting
  static bool debugIsPlausibleBoldBasename(String selected, String candidate) =>
      _isPlausibleBoldBasename(selected, candidate);

  /// מפענח את שני הקבצים ומחזיר האם [candidate] הוא ה-face הבולד של [regular].
  @visibleForTesting
  static bool debugIsBoldSibling(Uint8List regular, Uint8List candidate) {
    final r = _sfntFaceInfo(regular);
    final c = _sfntFaceInfo(candidate);
    if (r == null || c == null) return false;
    return _isBoldSibling(r, c);
  }
}

/// מידע סגנוני של face גופן, נקרא מטבלאות ה-SFNT לצורך התאמת בולד.
class _FontFaceInfo {
  final String family;
  final int weightClass;
  final bool bold;
  final bool italic;
  final bool hasWeightAxis;

  const _FontFaceInfo({
    required this.family,
    required this.weightClass,
    required this.bold,
    required this.italic,
    required this.hasWeightAxis,
  });

  /// בולד לפי דגל מפורש (fsSelection/macStyle) או usWeightClass ≥ 600.
  bool get isBoldStyle => bold || weightClass >= 600;
}

/// תוצאת סריקת גופני המערכת: הרשימה ל-UI, מפת המשפחות לטעינה,
/// ומפת כינויים (שם קובץ ← משפחה) לתאימות עם ערכים שמורים ישנים.
class SystemFontScanResult {
  final List<FontInfo> fonts;
  final Map<String, SystemFontFamilyFaces> families;
  final Map<String, String> aliases;

  const SystemFontScanResult({
    required this.fonts,
    required this.families,
    required this.aliases,
  });

  const SystemFontScanResult.empty()
    : fonts = const [],
      families = const {},
      aliases = const {};
}

/// נתיבי ה-faces של משפחת גופן מערכת אחת, כפי שנבחרו בסריקה.
class SystemFontFamilyFaces {
  final String family;
  final String regularPath;
  final String? boldPath;
  final bool hasWeightAxis;
  final FontCategory category;

  const SystemFontFamilyFaces({
    required this.family,
    required this.regularPath,
    this.boldPath,
    this.hasWeightAxis = false,
    this.category = FontCategory.unknown,
  });
}

/// צובר את ה-faces של משפחה במהלך הסריקה ובוחר את הרגיל והבולד המתאימים.
class _FamilyAccumulator {
  final String family;
  String? _regularPath;
  int _regularDistance = 1 << 30;
  bool _regularHasWeightAxis = false;
  String? _boldPath;
  int _boldDistance = 1 << 30;
  FontCategory _category = FontCategory.unknown;

  _FamilyAccumulator(this.family);

  void addFace({
    required String path,
    required _FontFaceInfo info,
    required FontCategory category,
  }) {
    final weight = info.weightClass > 0 ? info.weightClass : 400;
    if (info.isBoldStyle) {
      final distance = (weight - 700).abs();
      if (distance < _boldDistance) {
        _boldDistance = distance;
        _boldPath = path;
      }
    } else {
      final distance = (weight - 400).abs();
      if (distance < _regularDistance) {
        _regularDistance = distance;
        _regularPath = path;
        _regularHasWeightAxis = info.hasWeightAxis;
      }
    }
    if (_category == FontCategory.unknown) _category = category;
  }

  SystemFontFamilyFaces build() {
    // משפחה שקיימת רק בבולד (כמו רוב גופני גוטמן בהתקנות מסוימות) עדיין מוצגת.
    final regular = _regularPath ?? _boldPath!;
    // בגופן משתנה הבולד מגיע מציר ה-wght, לא מקובץ נפרד.
    final useBoldFace = _regularPath != null && !_regularHasWeightAxis;
    return SystemFontFamilyFaces(
      family: family,
      regularPath: regular,
      boldPath: useBoldFace ? _boldPath : null,
      hasWeightAxis: _regularHasWeightAxis,
      category: _category,
    );
  }
}

/// מידע על גופן
class FontInfo {
  final String value;
  final String label;
  final FontCategory category;

  const FontInfo({
    required this.value,
    required this.label,
    this.category = FontCategory.unknown,
  });
}
