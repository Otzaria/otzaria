import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:system_fonts/system_fonts.dart' show SystemFonts;
import 'package:otzaria/utils/file/font_file_reader.dart';

/// רשימת הגופנים הזמינים באפליקציה
class AppFonts {
  AppFonts._();

  /// גופן ברירת מחדל לטקסט ראשי
  static const String defaultFont = 'FrankRuhlCLM';

  /// גופן ברירת מחדל למפרשים
  static const String defaultCommentatorsFont = 'NotoRashiHebrew';

  /// גופן לעריכת טקסט עם טעמים
  static const String editorFont = 'TaameyAshkenaz';

  static bool get _supportsSystemFonts {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// רשימת הגופנים המובנים (מוטמעים באפליקציה / רשימת ברירת מחדל)
  /// הערה: לא כוללת גופני מערכת כלל; בדסקטופ הם נטענים/מסוננים אוטומטית.
  static const List<FontInfo> _bundledFonts = [
    FontInfo(value: 'TaameyDavidCLM', label: 'דוד'),
    FontInfo(value: 'FrankRuhlCLM', label: 'פרנק-רוהל'),
    FontInfo(value: 'TaameyAshkenaz', label: 'טעמי אשכנז'),
    FontInfo(value: 'KeterYG', label: 'כתר'),
    FontInfo(value: 'Shofar', label: 'שופר'),
    FontInfo(value: 'NotoSerifHebrew', label: 'נוטו'),
    FontInfo(value: 'Tinos', label: 'טינוס'),
    FontInfo(value: 'NotoRashiHebrew', label: 'רש"י'),
    FontInfo(value: 'Rubik', label: 'רוביק'),
  ];

  static List<FontInfo>? _systemFontsHebrewCache;

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

  static List<FontInfo> _getSystemFontsHebrewOnly() {
    if (_systemFontsHebrewCache != null) {
      return _systemFontsHebrewCache!;
    }

    final result = <FontInfo>[];
    try {
      final map = SystemFonts().getFontMap(); // name -> path
      final names = map.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      for (final name in names) {
        final path = map[name];
        if (path == null || path.isEmpty) continue;
        if (_fontFileSupportsHebrewSync(path)) {
          result.add(FontInfo(value: name, label: name));
        }
      }
    } catch (_) {
      // אם אין גישה לגופני מערכת מסיבה כלשהי, נחזיר רשימה ריקה.
    }

    _systemFontsHebrewCache = result;
    return result;
  }

  static bool _fontFileSupportsHebrewSync(String path) {
    try {
      final bytes = Uint8List.fromList(FontFileReader.readBytesSync(path));
      return _sfntSupportsHebrew(bytes);
    } catch (_) {
      return false;
    }
  }

  static bool _sfntSupportsHebrew(Uint8List data) {
    // TTC (TrueType Collection): magic "ttcf" at offset 0.
    // numFonts at offset 8; font offsets start at offset 12.
    if (data.length >= 16 &&
        data[0] == 0x74 && data[1] == 0x74 &&
        data[2] == 0x63 && data[3] == 0x66) {
      final numFonts =
          (data[8] << 24) | (data[9] << 16) | (data[10] << 8) | data[11];
      for (int i = 0; i < numFonts; i++) {
        final offsetPos = 12 + i * 4;
        if (offsetPos + 4 > data.length) break;
        final fontOffset = (data[offsetPos] << 24) |
            (data[offsetPos + 1] << 16) |
            (data[offsetPos + 2] << 8) |
            data[offsetPos + 3];
        if (fontOffset <= 0 || fontOffset >= data.length) continue;
        if (_sfntSupportsHebrew(Uint8List.sublistView(data, fontOffset))) {
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

    // Offset table
    if (data.length < 12) return false;
    final numTables = u16(4);
    if (numTables <= 0) return false;

    // Table records
    int cmapOffset = -1;
    int cmapLength = -1;
    final tableDirOffset = 12;
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

  /// מיפוי גופנים לשמות בעברית (לשימוש בהדפסה)
  /// מחושב אוטומטית מ-availableFonts, רק עבור גופנים עם קבצים
  static Map<String, String> get fontLabels => {
        for (final font in availableFonts)
          if (fontPaths.containsKey(font.value)) font.value: font.label
      };

  /// יצירת רשימת DropdownMenuItem לבחירת גופן
  static List<DropdownMenuItem<String>> buildDropdownItems({
    String? selectedValue,
    TextStyle? itemTextStyle,
  }) {
    final fonts = [...availableFonts];
    final hasSelectedValue = selectedValue == null ||
        selectedValue.isEmpty ||
        fonts.any((font) => font.value == selectedValue);

    if (!hasSelectedValue) {
      fonts.insert(
        0,
        FontInfo(
          value: selectedValue,
          label: '$selectedValue (לא זמין במחשב זה)',
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

  /// טוען גופן מערכת (אם קיים) כדי שניתן יהיה להשתמש בו ב-TextStyle.
  /// אם הגופן כבר מוטמע באפליקציה או שאין תמיכה בגופני מערכת - לא עושה כלום.
  static Future<void> ensureFontLoaded(String fontFamily) async {
    if (fontFamily.isEmpty) return;
    if (fontPaths.containsKey(fontFamily)) return;
    if (!_supportsSystemFonts) return;

    try {
      await SystemFonts().loadFont(fontFamily);
    } catch (_) {
      // אם לא ניתן לטעון, נשאיר את fallback של Flutter לעשות את שלו.
    }
  }

  @visibleForTesting
  static bool debugSfntSupportsHebrew(Uint8List data) =>
      _sfntSupportsHebrew(data);
}

/// מידע על גופן
class FontInfo {
  final String value;
  final String label;

  const FontInfo({required this.value, required this.label});
}
