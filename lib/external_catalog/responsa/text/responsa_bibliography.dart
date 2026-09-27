import 'dart:typed_data';

import 'package:otzaria/external_catalog/responsa/text/responsa_hebrew.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_names.dart';

/// רשומת ביבליוגרפיה אחת — מה שפרויקט השו"ת עצמו אומר על חיבור.
class ResponsaBibliographyEntry {
  /// שם החיבור כפי שהוא בכותרת העמוד.
  final String title;

  /// `null` ברוב המקרים ואינו תקלה: המאגר נוקב בשם המחבר רק כששם החיבור
  /// אינו כינויו.
  final String? author;

  /// שורת המהדורה המלאה, כפי שהיא — `בני ברק תש"מ, ד"צ ניו יורק תש"ג`.
  final String edition;

  /// מקום ההדפסה שנקרא משורת המהדורה, או `null` כשלא ניתן לקרוא אותו.
  final String? pubPlace;

  /// שנת ההדפסה שנקראה משורת המהדורה, או `null`.
  final String? pubDate;

  const ResponsaBibliographyEntry({
    required this.title,
    required this.author,
    required this.edition,
    required this.pubPlace,
    required this.pubDate,
  });

  bool get isEmpty =>
      author == null && pubPlace == null && pubDate == null && edition.isEmpty;
}

/// "רשימת הספרים והמהדורות" שבקובץ העזרה (`HELP/*.chm`). שם מחבר מופיע בה
/// רק כששם החיבור אינו כינויו - כמעט רק בשו"ת.
class ResponsaBibliography {
  /// חלק העמודים שחייב לשבת תחת תיקייה אחת כדי שתיחשב תיקיית הביבליוגרפיה
  /// (ב-CD25 כ-93% תחת `html/Bblgrphy`).
  static const double _folderMajority = 0.8;

  final Map<String, List<ResponsaBibliographyEntry>> _byKey;

  const ResponsaBibliography._(this._byKey);

  static const ResponsaBibliography empty = ResponsaBibliography._({});

  bool get isEmpty => _byKey.isEmpty;

  /// כמה רשומות נקראו — לדיווח בבנייה.
  int get entryCount =>
      _byKey.values.expand((entries) => entries).toSet().length;

  /// עמודי הדרכה עוברים את [parsePage] ומייצרים שטות, ורק המיקום מבדיל. התיקייה
  /// נבחרת לפי רוב ולא לפי שם, ובלי רוב מוחזר ריק.
  static Map<String, Uint8List> onlyBibliographyFolder(
    Map<String, Uint8List> pages,
  ) {
    final keys = [
      for (final entry in pages.entries)
        if (_isHtml(entry.key) && parsePage(decodeCp1255(entry.value)) != null)
          entry.key,
    ];
    if (keys.isEmpty) return const {};

    // כמה עמודים תחת כל תחילית-נתיב אפשרית.
    final counts = <String, int>{};
    for (final key in keys) {
      final parts = key.replaceAll('\\', '/').split('/');
      for (var depth = 1; depth < parts.length; depth++) {
        final prefix = parts.take(depth).join('/').toLowerCase();
        counts[prefix] = (counts[prefix] ?? 0) + 1;
      }
    }
    final needed = keys.length * _folderMajority;
    String? chosen;
    for (final entry in counts.entries) {
      if (entry.value < needed) continue;
      if (chosen == null || entry.key.length > chosen.length) {
        chosen = entry.key;
      }
    }
    if (chosen == null) return const {};

    final prefix = '$chosen/';
    return {
      for (final entry in pages.entries)
        if (entry.key.replaceAll('\\', '/').toLowerCase().startsWith(prefix))
          entry.key: entry.value,
    };
  }

  static bool _isHtml(String key) {
    final lower = key.toLowerCase();
    return lower.endsWith('.htm') || lower.endsWith('.html');
  }

  /// בונה אינדקס מעמודי ה-CHM הגולמיים, כפי ש-[ResponsaChm] מחזיר אותם.
  static ResponsaBibliography parse(Map<String, Uint8List> pages) {
    final index = <String, List<ResponsaBibliographyEntry>>{};
    for (final entry in pages.entries) {
      if (!_isHtml(entry.key)) continue;
      final page = parsePage(decodeCp1255(entry.value));
      if (page == null) continue;
      for (final name in _keysFor(page.names)) {
        (index[name] ??= []).add(page.entry);
      }
    }
    return ResponsaBibliography._(index);
  }

  /// `null` גם כששם אחד מוליך לרשומות שאינן מסכימות (`חתם סופר` על הש"ס
  /// ועל השו"ע) - מהדורה של חיבור אחר גרועה מכלום.
  ResponsaBibliographyEntry? lookup(Iterable<String> candidates) {
    for (final candidate in candidates) {
      for (final key in _keysFor([candidate])) {
        final matches = _byKey[key];
        if (matches == null || matches.isEmpty) continue;
        final resolved = _agree(matches);
        if (resolved != null) return resolved;
      }
    }
    return null;
  }

  /// כשכמה רשומות נושאות את אותו שם — מה שמוסכם על כולן, ותו לא.
  static ResponsaBibliographyEntry? _agree(
    List<ResponsaBibliographyEntry> matches,
  ) {
    if (matches.length == 1) return matches.single;
    String? single(String? Function(ResponsaBibliographyEntry) field) {
      final values = {
        for (final match in matches)
          if (field(match) case final value? when value.isNotEmpty) value,
      };
      return values.length == 1 ? values.single : null;
    }

    final author = single((entry) => entry.author);
    final place = single((entry) => entry.pubPlace);
    final date = single((entry) => entry.pubDate);
    if (author == null && place == null && date == null) return null;
    return ResponsaBibliographyEntry(
      title: matches.first.title,
      author: author,
      edition: single((entry) => entry.edition) ?? '',
      pubPlace: place,
      pubDate: date,
    );
  }

  /// גם בלי תחילית `שו"ת`: בעץ הצומת הוא `כתב סופר` ובביבליוגרפיה
  /// `שו"ת כתב סופר`.
  static Iterable<String> _keysFor(Iterable<String> names) sync* {
    final seen = <String>{};
    for (final name in names) {
      for (final variant in [name, _withoutScopeWord(name)]) {
        if (variant.isEmpty) continue;
        final key = ResponsaHebrew.spellingKey(
          ResponsaNames.withoutQualifier(variant),
        );
        if (key.isNotEmpty && seen.add(key)) yield key;
      }
    }
  }

  static final RegExp _scopeWord = RegExp(
    r'''^(שו["״]?ת|שאלות ותשובות|תשובות)\s+''',
  );

  static String _withoutScopeWord(String name) =>
      name.replaceFirst(_scopeWord, '').trim();

  // ------------------------------------------------------ ניתוח עמוד יחיד

  /// שורת פתיחה של עמוד ריכוז, שמונה חיבורים במקום לתאר אחד.
  static const String _indexLead = 'רשימת ספרים ומהדורות';

  /// עמוד חיבור הוא מחבר ועד שלוש שורות מהדורה; בלי הסף, השם הראשון בעמוד
  /// ריכוז נרשם כמחבר של כל הרשומים בו.
  static const int _maxBodyLines = 4;

  static final RegExp _authorLead = RegExp(r'''^(רבי|ר['׳])\s''');

  static final RegExp _editionLead = RegExp(
    r'''^(מהדור|ד["״]צ|דפוס|על פי|עפ["״]י|נדפס|הוצאת|מכון|בתוך|מבוסס)''',
  );

  /// מנתח עמוד ביבליוגרפיה בודד. `null` לעמוד שאינו מתאר חיבור.
  static ({List<String> names, ResponsaBibliographyEntry entry})? parsePage(
    String html,
  ) {
    final title = _titleOf(html);
    final lines = _lines(html);
    if (lines.isEmpty) return null;
    if (lines.any((line) => line.startsWith(_indexLead))) return null;

    final heading = lines.first;
    final body = lines.sublist(1);
    if (body.length > _maxBodyLines) return null;

    String? author;
    final edition = <String>[];
    for (final line in body) {
      if (author == null && _isAuthorLine(line)) {
        author = line;
        continue;
      }
      edition.add(line);
    }

    final editionText = edition.join(' | ');
    final printed = _placeAndYear(editionText);
    final entry = ResponsaBibliographyEntry(
      title: title.isEmpty ? heading : title,
      author: author,
      edition: editionText,
      pubPlace: printed?.place,
      pubDate: printed?.year,
    );
    if (entry.isEmpty) return null;
    return (names: [if (title.isNotEmpty) title, heading], entry: entry);
  }

  /// המילים נספרות בלי הסוגריים, שבהם יושבים המקום והמאה.
  static const int _maxAuthorWords = 8;

  /// קצרה ובלי פיסוק של משפט - כדי לפסול מאמר שנפתח במקרה ב"רבי", שאחרת
  /// נרשם כמחבר של עשרות ספרים.
  static bool _isAuthorLine(String line) {
    if (!_authorLead.hasMatch(line)) return false;
    if (_editionLead.hasMatch(line)) return false;
    final bare = ResponsaNames.withoutQualifier(line);
    if (bare.contains(RegExp(r'[,.:;]'))) return false;
    return bare.split(RegExp(r'\s+')).length <= _maxAuthorWords;
  }

  // ------------------------------------------------ מקום ושנה משורת מהדורה

  /// כתובות בלי גרש וגרשיים, כי ההשוואה נעשית אחרי הסרתם - במאגר מופיעים
  /// שני התווים (`"` ו-`״`) באותו תפקיד.
  static const Set<String> _notPlace = {
    'מהדורת',
    'מהדורה',
    'הוצאת',
    'דפוס',
    'דצ',
    'בתוך',
    'נדפס',
    'מכון',
    'חלק',
    'כרך',
    'עמ',
    'עפי',
  };

  static final RegExp _marks = RegExp('''["'׳״]''');

  /// כל שם מקום רב-מילי במאגר בן שתי מילים (`בני ברק`, `פתח תקוה`).
  static const int _maxPlaceWords = 2;

  static final RegExp _yearToken = RegExp(r'''^[א-ת]{1,4}["״][א-ת]$''');

  /// מילה עברית, כולל מקף פנימי — `ניו-יורק` הוא שם מקום אחד.
  static final RegExp _hebrewWord = RegExp(r'^[א-ת][א-ת"״׳\x27\-–]*$');

  static final RegExp _hebrewLetters = RegExp(r'[א-ת]');
  static final RegExp _gershayim = RegExp('["״]');
  static final RegExp _dash = RegExp(r'[-–—]');

  /// גרשיים הם ראשי תיבות (`או"ח פרעמישלא`), ורכיבים בני אות אחת הם כרך
  /// (`א'-ד'`); גרש בסוף מילה אינו פוסל - `לודז'` היא עיר.
  static bool _canBePlace(String word) {
    if (!_hebrewWord.hasMatch(word)) return false;
    if (_gershayim.hasMatch(word)) return false;
    if (_notPlace.contains(word.replaceAll(_marks, ''))) return false;
    if (_yearOf(word) != null) return false;
    return word
        .split(_dash)
        .any((part) => _hebrewLetters.allMatches(part).length >= 2);
  }

  /// השנה חייבת לסגור קטע (`ש"ס` ב-`מהדורת ש"ס וילנא` אינו שנה). מקף בודד
  /// עוצר - הוא מפריד תווית מהמקום (`זרעים - ירושלים`), ואין לגשר מעליו.
  static ({String place, String year})? _placeAndYear(String edition) {
    for (final segment in edition.split(RegExp(r'[,|]'))) {
      final words = segment
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      if (words.length < 2) continue;

      final year = _yearOf(words.last);
      if (year == null) continue;

      final place = <String>[];
      for (var i = words.length - 2; i >= 0; i--) {
        final word = words[i];
        if (!_canBePlace(word)) break;
        place.insert(0, word);
        if (place.length == _maxPlaceWords) break;
      }
      if (place.isEmpty) continue;
      return (place: _joinPlace(place), year: year);
    }
    return null;
  }

  /// מילה שנגמרת במקף נדבקת לבאה: `ניו- יורק` ו-`ניו-יורק` הם אותה עיר.
  static String _joinPlace(List<String> words) {
    var joined = words.first;
    for (final word in words.skip(1)) {
      joined = _endsWithDash.hasMatch(joined)
          ? '$joined$word'
          : '$joined $word';
    }
    return joined;
  }

  static final RegExp _endsWithDash = RegExp(r'[-–—]$');

  /// שנה בלי האלפים. מתחת ל-400 יושבים ראשי תיבות שאינם שנים (`ש"ס` = 360),
  /// וכל ספרי המאגר נדפסו מ-`ת` ואילך.
  static const int _minYear = 400;
  static const int _maxYear = 1100;

  /// אסימון שהוא שנה עברית — או טווח שנים `תרמ"ד-תרנ"ג`.
  static String? _yearOf(String word) {
    final cleaned = word.replaceAll(RegExp(r'^[(\[]|[)\].,;]$'), '');
    final parts = cleaned.split(RegExp(r'\s*[-–—]\s*'));
    if (parts.isEmpty) return null;
    for (final part in parts) {
      if (!_yearToken.hasMatch(part)) return null;
      // הגימטריה נקראת בלי הגרשיים — `numeralToInt` דוחה כל תו שאינו אות.
      final value = ResponsaHebrew.numeralToInt(part.replaceAll(_marks, ''));
      if (value == null || value < _minYear || value > _maxYear) return null;
    }
    return cleaned;
  }

  // ------------------------------------------------------------ HTML ו-CP1255

  static final RegExp _titleTag = RegExp(
    r'<title>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _scriptOrStyle = RegExp(
    r'<(script|style)\b.*?</\1>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _lineBreakTag = RegExp(
    r'<br\s*/?>|</(p|div|h\d|tr|li|td)>',
    caseSensitive: false,
  );
  static final RegExp _anyTag = RegExp(r'<[^>]*>', dotAll: true);
  static final RegExp _spaces = RegExp(r'[\s ]+');

  static String _titleOf(String html) {
    final match = _titleTag.firstMatch(html);
    if (match == null) return '';
    return _text(match.group(1) ?? '').trim();
  }

  /// תו בקרה שאינו מופיע ב-HTML, ומסמן גבול שורה אחרי הסרת התגיות.
  static const String _lineMark = '\u0001';

  /// שורות הגוף — כל אחת פסקה או שורה שנשברה ב-`<br>`.
  static List<String> _lines(String html) {
    final start = html.toLowerCase().indexOf('<body');
    final body = start < 0 ? html : html.substring(start);
    final broken = body
        .replaceAll(_scriptOrStyle, ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll(_lineBreakTag, _lineMark);
    return [
      for (final piece in broken.split(_lineMark))
        if (_text(piece).trim().replaceAll(RegExp(r'^[>\s]+'), '')
            case final line when line.isNotEmpty)
          line,
    ];
  }

  static String _text(String html) => _unescape(
    html.replaceAll(_anyTag, ' '),
  ).replaceAll(_spaces, ' ').trim();

  static final RegExp _entity = RegExp(r'&(#\d+|#x[0-9a-fA-F]+|\w+);');

  static const Map<String, String> _namedEntities = {
    'quot': '"',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'nbsp': ' ',
    'apos': "'",
  };

  static String _unescape(String value) =>
      value.replaceAllMapped(_entity, (match) {
        final body = match.group(1)!;
        if (body.startsWith('#x') || body.startsWith('#X')) {
          final code = int.tryParse(body.substring(2), radix: 16);
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        if (body.startsWith('#')) {
          final code = int.tryParse(body.substring(1));
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        return _namedEntities[body.toLowerCase()] ?? match.group(0)!;
      });

  /// הקידוד של עמודי העזרה - אין לו מפענח ב-Dart.
  static String decodeCp1255(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte < 0x80) {
        buffer.writeCharCode(byte);
        continue;
      }
      final mapped = _cp1255High[byte - 0x80];
      // 0 מסמן נקודת קוד שאינה מוגדרת בקידוד. רווח, ולא תו החלפה:
      // המטרה היא טקסט קריא, לא שחזור מדויק של בתים פגומים.
      buffer.writeCharCode(mapped == 0 ? 0x20 : mapped);
    }
    return buffer.toString();
  }

  /// 0x80–0xFF של CP1255. אותיות עבריות ב-0xE0–0xFA, ניקוד ב-0xC0–0xD2.
  static const List<int> _cp1255High = [
    0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0, 0x2039, 0, 0, 0, 0,
    0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0, 0x203A, 0, 0, 0, 0,
    0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x20AA, 0x00A5, 0x00A6, 0x00A7,
    0x00A8, 0x00A9, 0x00D7, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
    0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
    0x00B8, 0x00B9, 0x00F7, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF,
    0x05B0, 0x05B1, 0x05B2, 0x05B3, 0x05B4, 0x05B5, 0x05B6, 0x05B7,
    0x05B8, 0x05B9, 0, 0x05BB, 0x05BC, 0x05BD, 0x05BE, 0x05BF,
    0x05C0, 0x05C1, 0x05C2, 0x05C3, 0x05F0, 0x05F1, 0x05F2, 0x05F3,
    0x05F4, 0, 0, 0, 0, 0, 0, 0,
    0x05D0, 0x05D1, 0x05D2, 0x05D3, 0x05D4, 0x05D5, 0x05D6, 0x05D7,
    0x05D8, 0x05D9, 0x05DA, 0x05DB, 0x05DC, 0x05DD, 0x05DE, 0x05DF,
    0x05E0, 0x05E1, 0x05E2, 0x05E3, 0x05E4, 0x05E5, 0x05E6, 0x05E7,
    0x05E8, 0x05E9, 0x05EA, 0, 0, 0x200E, 0x200F, 0,
  ];
}
