import 'dart:typed_data';

import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';

/// מחבר לפי מזהה החיבור מתוך `DB\FILE00` - המקור הראשי; הביבליוגרפיה מותאמת
/// לפי שם (`ר"ש` על זרעים קיבל את רש"י) והיא רק נסיגה.
class ResponsaAuthorTable {
  final Map<int, String> _authors;
  final Set<int> _known;

  const ResponsaAuthorTable._(this._authors, this._known);

  static const ResponsaAuthorTable empty = ResponsaAuthorTable._({}, {});

  bool get isEmpty => _known.isEmpty;

  /// כמה חיבורים יש להם מחבר.
  int get authorCount => _authors.length;

  /// האם הטבלה מכירה את החיבור. חיבור מוכר בלי מחבר הוא הצהרה של בר
  /// אילן שאין לו מחבר יחיד — תנ"ך, משנה, מדרש — ולא חוסר מידע.
  bool knows(int bookId) => _known.contains(bookId);

  /// המחבר של החיבור, או `null`.
  String? authorOf(int bookId) => _authors[bookId];

  /// מילת שם משותפת אחת מספיקה: השוואת שם משפחה בלבד פוסלת את אותו אדם
  /// בכתיב אחר (`הלברשטאם` מול `הלברשטם`).
  static bool mayBeSamePerson(String a, String b) =>
      _nameWords(a).intersection(_nameWords(b)).isNotEmpty;

  static Set<String> _nameWords(String name) {
    final words = <String>{};
    var father = false;
    for (final word in ResponsaHebrew.tokens(
      ResponsaNames.withoutQualifier(name),
    )) {
      if (father) {
        father = false;
      } else if (_fatherWords.contains(word)) {
        father = true;
      } else if (!_titleWords.contains(word)) {
        words.add(word);
      }
    }
    return words;
  }

  /// `בן` ו-`בר`: המילה שאחריהן היא שם האב — `רבי שלמה בן יצחק` אינו
  /// אותו אדם כמו `ר' יצחק אלפסי`.
  static const Set<String> _fatherWords = {'בנ', 'בר'};

  /// תארים ומילות יחוס, אחרי [ResponsaHebrew.spellingKey] — `רבי` הוא
  /// `רב`, `הלוי` הוא `הל`. שני אנשים שונים חולקים אותן תמיד.
  static const Set<String> _titleWords = {
    'ר',
    'רב',
    'הרב',
    'רבנ',
    'הכהנ',
    'הל',
    'אבנ',
    'ד',
    'דה',
  };

  /// גודל רשומה, בשתי הטבלאות.
  static const int recordSize = 73;

  /// גודל רשומה בספריית המכל.
  static const int directoryEntrySize = 28;

  static const String _titlesMember = 'FILE25';
  static const String _authorsMember = 'FILE65';

  /// הבית הנמוך של `lParam` בסדר בתים הפוך: `0x6109` בעץ הוא `2401` בטבלה.
  static int bookIdOf(int param) =>
      ((param & 0xFF) << 8) | ((param >> 8) & 0xFF);

  /// האם [name] הוא אחד מהקבצים שהטבלה נבנית מהם.
  static bool isTableMember(String name) {
    final base = name.split('.').first.toUpperCase();
    return base == _titlesMember || base == _authorsMember;
  }

  /// `u16` מספר רשומות, ולכל קובץ שם של 20 בתים, `u32` היסט ו-`u32` גודל.
  /// `null` כשהמבנה אינו מוכר.
  static List<({String name, int offset, int size})>? parseDirectory(
    Uint8List header,
    int archiveLength,
  ) {
    if (header.length < 2) return null;
    final bytes = ByteData.sublistView(header);
    final count = bytes.getUint16(0, Endian.little);
    if (count == 0 || header.length < 2 + count * directoryEntrySize) {
      return null;
    }
    final entries = <({String name, int offset, int size})>[];
    for (var i = 0; i < count; i++) {
      final at = 2 + i * directoryEntrySize;
      final nameBytes = header.sublist(at, at + 20);
      final end = nameBytes.indexOf(0);
      final name = String.fromCharCodes(
        nameBytes.sublist(0, end < 0 ? 20 : end),
      );
      final offset = bytes.getUint32(at + 20, Endian.little);
      final size = bytes.getUint32(at + 24, Endian.little);
      // רשומה שמצביעה מחוץ לקובץ פירושה שהמבנה אינו מה שחשבנו.
      if (name.isEmpty || offset + size > archiveLength) return null;
      entries.add((name: name, offset: offset, size: size));
    }
    return entries;
  }

  /// מחבר רק עם כותרת באותו מדור, רק אדם (`ר' `), ובלי מחבר כשיש שניים.
  /// קובץ במבנה לא צפוי מדולג כולו - מחבר שגוי גרוע מהיעדר מחבר.
  static ResponsaAuthorTable parse(Map<String, Uint8List> members) {
    final titles = <String, Set<int>>{};
    final authors = <String, Map<int, String>>{};
    for (final entry in members.entries) {
      final parts = entry.key.toUpperCase().split('.');
      if (parts.length != 2) continue;
      final records = _records(entry.value);
      if (records == null) continue;
      switch (parts.first) {
        case _titlesMember:
          titles[parts.last] = {for (final record in records) record.id};
        case _authorsMember:
          authors[parts.last] = {
            for (final record in records) record.id: record.text,
          };
      }
    }

    final known = {for (final ids in titles.values) ...ids};
    final found = <int, Set<String>>{};
    for (final MapEntry(key: section, value: byId) in authors.entries) {
      final sectionTitles = titles[section] ?? const <int>{};
      for (final MapEntry(key: id, value: name) in byId.entries) {
        if (!sectionTitles.contains(id)) continue;
        if (!name.startsWith(_personLead)) continue;
        (found[id] ??= {}).add(name);
      }
    }
    return ResponsaAuthorTable._({
      for (final MapEntry(key: id, value: names) in found.entries)
        if (names.length == 1) id: names.single,
    }, known);
  }

  static const String _personLead = "ר' ";

  static List<({int id, String text})>? _records(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length % recordSize != 0) return null;
    final records = <({int id, String text})>[];
    for (var at = 0; at < bytes.length; at += recordSize) {
      final id = (bytes[at] << 8) | bytes[at + 1];
      final text = decodeCp862(bytes.sublist(at + 2, at + recordSize));
      if (text == null) return null;
      records.add((id: id, text: text));
    }
    return records;
  }

  /// `null` כשיש תו שאינו אות עברית או ASCII מודפס. הסוגריים הפוכים, כי
  /// טקסט DOS נכתב בסדר ויזואלי.
  static String? decodeCp862(Uint8List bytes) {
    final end = bytes.indexOf(0);
    final units = <int>[];
    for (final byte in end < 0 ? bytes : bytes.sublist(0, end)) {
      if (byte >= 0x80 && byte <= 0x9A) {
        units.add(0x05D0 + byte - 0x80);
      } else if (byte >= 0x20 && byte < 0x7F) {
        units.add(_mirrored[byte] ?? byte);
      } else {
        return null;
      }
    }
    return String.fromCharCodes(units).trim();
  }

  static const Map<int, int> _mirrored = {
    0x28: 0x29, // (
    0x29: 0x28, // )
    0x5B: 0x5D, // [
    0x5D: 0x5B, // ]
    0x7B: 0x7D, // {
    0x7D: 0x7B, // }
  };
}
