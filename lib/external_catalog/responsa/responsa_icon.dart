import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// חילוץ האייקון של בר אילן מקובץ ההרצה שבהתקנה של המשתמש.
///
/// **למה לא נכס בחבילה.** הלוגו של פרויקט השו"ת הוא סימן של צד שלישי,
/// ואין לצרף אותו לקוד של אוצריא. האייקון שמוצג הוא זה שבהתקנה שעל
/// המחשב — כלומר בדיוק האייקון שהמשתמש רואה בתפריט ההתחלה — והוא גם
/// מתעדכן מאליו עם כל מהדורה.
///
/// **למה קריאת PE ולא `ExtractIconEx`.** הקריאה הזו היא ניתוח קובץ
/// טהור: אין GDI, אין ידיות, אפשר להריץ אותה בכל איזולט ואפשר לבדוק
/// אותה בלי Windows. ‏`ExtractIconEx` היה מחייב `GetIconInfo`,
/// `GetDIBits` ושחרור ידיות, ואת כל אלה רק על מכונת Windows חיה.
///
/// התוצאה נשמרת כקובץ `.ico` בתיקיית הקטלוג. Skia מפענח ICO, ולכן
/// `Image.memory` מציג אותו ישירות.
class ResponsaIcon {
  ResponsaIcon._();

  static const int _rtIcon = 3;
  static const int _rtGroupIcon = 14;

  /// האייקון, מהמטמון או מחילוץ חדש. `null` כשאי אפשר לחלץ.
  ///
  /// [cachePath] הוא קובץ ה-`.ico` שליד הקטלוג — ראה `ResponsaPaths`.
  ///
  /// כל כשל כאן הוא ערך ולא חריג: אייקון חסר הוא עניין קוסמטי, ואסור
  /// שיפיל את מסך הספרייה.
  static Future<Uint8List?> load({
    required String? installPath,
    required String? cachePath,
  }) async {
    final cached = cachePath == null ? null : File(cachePath);
    try {
      if (cached != null && await cached.exists()) {
        final bytes = await cached.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
      if (installPath == null || installPath.isEmpty) return null;
      final executable = File(path.join(installPath, 'RESPONSA.exe'));
      if (!await executable.exists()) return null;

      // הקריאה והניתוח שניהם מחוץ לאיזולט ה-UI: קובץ ההרצה הוא כ-4.5MB,
      // וקריאה סינכרונית שלו על ה-platform thread מקפיאה פריימים.
      final bytes = await compute(_extract, await executable.readAsBytes());
      if (bytes == null) return null;
      if (cached != null) {
        await cached.parent.create(recursive: true);
        await cached.writeAsBytes(bytes);
      }
      return bytes;
    } catch (error) {
      debugPrint('ResponsaIcon: extraction failed: $error');
      return null;
    }
  }

  /// בונה `.ico` בעל תמונה אחת — הגדולה שבמשאבי האייקון של הקובץ.
  @visibleForTesting
  static Uint8List? extractFrom(Uint8List image) => _extract(image);

  static Uint8List? _extract(Uint8List image) {
    final resources = _resources(image);
    if (resources == null) return null;

    // מעדיפים אייקון שמופיע בקבוצה — כלומר כזה שהמערכת מציגה — ובתוכה
    // את הגדול ביותר. בלי קבוצה, פשוט הגדול ביותר שיש.
    final groups = resources.where((r) => r.type == _rtGroupIcon);
    final wanted = <int>{};
    for (final group in groups) {
      final data = ByteData.sublistView(image, group.offset, group.end);
      if (data.lengthInBytes < 6) continue;
      final count = data.getUint16(4, Endian.little);
      for (var i = 0; i < count; i++) {
        final entry = 6 + i * 14;
        if (entry + 14 > data.lengthInBytes) break;
        wanted.add(data.getUint16(entry + 12, Endian.little));
      }
    }

    final icons = resources
        .where((r) => r.type == _rtIcon)
        .where((r) => wanted.isEmpty || wanted.contains(r.id))
        .toList();
    if (icons.isEmpty) return null;
    icons.sort((a, b) => (b.end - b.offset).compareTo(a.end - a.offset));
    final chosen = icons.first;
    final body = Uint8List.sublistView(image, chosen.offset, chosen.end);

    // מידות: מ-DIB, או מכותרת PNG כשהמשאב דחוס (Vista ומעלה).
    var width = 0;
    var height = 0;
    var planes = 1;
    var bits = 32;
    if (body.length > 24 &&
        body[0] == 0x89 &&
        body[1] == 0x50 &&
        body[2] == 0x4E &&
        body[3] == 0x47) {
      final png = ByteData.sublistView(body);
      width = png.getUint32(16, Endian.big);
      height = png.getUint32(20, Endian.big);
    } else if (body.length >= 16) {
      final dib = ByteData.sublistView(body);
      width = dib.getInt32(4, Endian.little);
      // ב-DIB של אייקון הגובה כולל את מסכת השקיפות, ולכן הוא כפול.
      height = dib.getInt32(8, Endian.little) ~/ 2;
      planes = dib.getUint16(12, Endian.little);
      bits = dib.getUint16(14, Endian.little);
    }

    final out = BytesBuilder();
    final header = ByteData(22)
      ..setUint16(0, 0, Endian.little)
      ..setUint16(2, 1, Endian.little) // סוג: אייקון
      ..setUint16(4, 1, Endian.little) // תמונה אחת
      ..setUint8(6, width >= 256 ? 0 : width)
      ..setUint8(7, height >= 256 ? 0 : height)
      ..setUint8(8, 0)
      ..setUint8(9, 0)
      ..setUint16(10, planes, Endian.little)
      ..setUint16(12, bits, Endian.little)
      ..setUint32(14, body.length, Endian.little)
      ..setUint32(18, 22, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(body);
    return out.toBytes();
  }

  // ------------------------------------------------- קריאת מדור המשאבים

  static List<({int type, int id, int offset, int end})>? _resources(
    Uint8List image,
  ) {
    final data = ByteData.sublistView(image);
    if (image.length < 0x40) return null;
    final peOffset = data.getUint32(0x3C, Endian.little);
    if (peOffset + 24 > image.length) return null;
    if (data.getUint32(peOffset, Endian.little) != 0x00004550) return null;

    final sectionCount = data.getUint16(peOffset + 6, Endian.little);
    final optionalSize = data.getUint16(peOffset + 20, Endian.little);
    final optional = peOffset + 24;
    final magic = data.getUint16(optional, Endian.little);
    // 0x10b = PE32, 0x20b = PE32+. ההפרש הוא גודל השדות שלפני הספרייה.
    final directories = optional + (magic == 0x10b ? 96 : 112);
    if (directories + 24 > image.length) return null;
    final resourceRva = data.getUint32(directories + 16, Endian.little);
    if (resourceRva == 0) return null;

    final sections = <({int rva, int size, int rawSize, int rawOffset})>[];
    final table = optional + optionalSize;
    for (var i = 0; i < sectionCount; i++) {
      final entry = table + i * 40;
      if (entry + 40 > image.length) return null;
      sections.add((
        rva: data.getUint32(entry + 12, Endian.little),
        size: data.getUint32(entry + 8, Endian.little),
        rawSize: data.getUint32(entry + 16, Endian.little),
        rawOffset: data.getUint32(entry + 20, Endian.little),
      ));
    }

    int? toOffset(int rva) {
      for (final section in sections) {
        final span = section.size > section.rawSize
            ? section.size
            : section.rawSize;
        if (rva >= section.rva && rva < section.rva + span) {
          return section.rawOffset + (rva - section.rva);
        }
      }
      return null;
    }

    final base = toOffset(resourceRva);
    if (base == null) return null;

    final found = <({int type, int id, int offset, int end})>[];

    void walk(int directory, List<int> ids, int depth) {
      if (depth > 3 || directory + 16 > image.length) return;
      final named = data.getUint16(directory + 12, Endian.little);
      final numbered = data.getUint16(directory + 14, Endian.little);
      for (var i = 0; i < named + numbered; i++) {
        final entry = directory + 16 + i * 8;
        if (entry + 8 > image.length) return;
        final name = data.getUint32(entry, Endian.little);
        final target = data.getUint32(entry + 4, Endian.little);
        final id = name & 0x7FFFFFFF;
        if (target & 0x80000000 != 0) {
          walk(base + (target & 0x7FFFFFFF), [...ids, id], depth + 1);
          continue;
        }
        final leaf = base + target;
        if (leaf + 8 > image.length) continue;
        final dataRva = data.getUint32(leaf, Endian.little);
        final size = data.getUint32(leaf + 4, Endian.little);
        final offset = toOffset(dataRva);
        if (offset == null || offset + size > image.length) continue;
        if (ids.isEmpty) continue;
        found.add((
          type: ids.first,
          id: ids.length > 1 ? ids[1] : 0,
          offset: offset,
          end: offset + size,
        ));
      }
    }

    walk(base, const [], 0);
    return found;
  }
}
