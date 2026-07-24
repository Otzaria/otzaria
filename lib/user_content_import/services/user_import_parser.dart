import 'dart:convert';

import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show getTitleFromPath;

/// מפענח קבצי CSV שהוכנו מראש לייבוא דורות וקישורי-משתמש.
///
/// פענוח ה-CSV סלחני: גרש כפול (") נחשב תו-ציטוט רק בתחילת שדה, אחרת הוא תו
/// ספרותי — כך כותרת עם גרשיים (שו"ת) נקראת נכון, וגם שדה מצוטט "רטו, א" עובד.
class UserImportParser {
  /// מפענח קובץ דורות (עמודות: ספר, דור, [מחבר], [קטגוריה]).
  static ParseResult<ParsedBookGeneration> parseGenerations(String content) {
    final rows = <ParsedBookGeneration>[];
    final errors = <ImportRowError>[];
    final records = _parseCsv(content);
    if (records.isEmpty) return ParseResult(rows, errors);

    final header = _indexHeader(records.first.cells, const {
      'title': ['ספר', 'כותרת'],
      'era': ['דור', 'תקופה'],
      'author': ['מחבר'],
      'categoryId': ['קטגוריה', 'קטגוריית_מקור'],
    });
    final titleCol = header['title'];
    final eraCol = header['era'];
    if (titleCol == null || eraCol == null) {
      errors.add(
        const ImportRowError(
          1,
          'כותרת הקובץ חייבת לכלול את העמודות "ספר" ו-"דור"',
        ),
      );
      return ParseResult(rows, errors);
    }

    for (final record in records.skip(1)) {
      final cells = record.cells;
      final title = _at(cells, titleCol);
      final eraRaw = _at(cells, eraCol);
      if (title.isEmpty && eraRaw.isEmpty) continue;
      if (title.isEmpty) {
        errors.add(ImportRowError(record.lineNumber, 'חסר שם ספר'));
        continue;
      }
      final era = _canonicalEra(eraRaw);
      if (era == null) {
        errors.add(ImportRowError(record.lineNumber, 'דור לא חוקי: "$eraRaw"'));
        continue;
      }
      rows.add(
        ParsedBookGeneration(
          bookTitle: title,
          eraName: era,
          author: _nullable(_at(cells, header['author'])),
          categoryId: _parseIntOrNull(_at(cells, header['categoryId'])),
        ),
      );
    }
    return ParseResult(rows, errors);
  }

  /// מפענח קובץ קישורים (עמודות: מקור, ספר_יעד, [מיקום_יעד], סוג,
  /// [יעד_אישי], [ספר_מקור], [מקור_אישי], [קטגוריית_מקור], [קטגוריית_יעד]).
  static ParseResult<ParsedUserLink> parseLinks(String content) {
    final rows = <ParsedUserLink>[];
    final errors = <ImportRowError>[];
    final records = _parseCsv(content);
    if (records.isEmpty) return ParseResult(rows, errors);

    final header = _indexHeader(records.first.cells, const {
      'source': ['מקור', 'שורה'],
      'targetTitle': ['ספר_יעד', 'יעד'],
      'targetRef': ['מיקום_יעד', 'מיקום'],
      'type': ['סוג'],
      'targetIsUser': ['יעד_אישי'],
      'sourceBook': ['ספר_מקור'],
      'sourceIsUser': ['מקור_אישי'],
      'sourceCategoryId': ['קטגוריית_מקור'],
      'targetCategoryId': ['קטגוריית_יעד'],
    });
    final sourceCol = header['source'];
    final targetCol = header['targetTitle'];
    final typeCol = header['type'];
    if (sourceCol == null || targetCol == null || typeCol == null) {
      errors.add(
        const ImportRowError(
          1,
          'כותרת הקובץ חייבת לכלול את העמודות "מקור", "ספר_יעד" ו-"סוג"',
        ),
      );
      return ParseResult(rows, errors);
    }

    for (final record in records.skip(1)) {
      final cells = record.cells;
      final sourceRaw = _at(cells, sourceCol);
      final targetTitle = _at(cells, targetCol);
      if (sourceRaw.isEmpty && targetTitle.isEmpty) continue;

      final sourceLine = _parseIntOrNull(sourceRaw);
      if (sourceLine == null || sourceLine < 1) {
        errors.add(
          ImportRowError(
            record.lineNumber,
            'מספר שורת מקור לא חוקי: "$sourceRaw"',
          ),
        );
        continue;
      }
      if (targetTitle.isEmpty) {
        errors.add(ImportRowError(record.lineNumber, 'חסר שם ספר יעד'));
        continue;
      }
      final type = _connectionType(_at(cells, typeCol));
      if (type == null) {
        errors.add(
          ImportRowError(
            record.lineNumber,
            'סוג קישור לא מוכר: "${_at(cells, typeCol)}"',
          ),
        );
        continue;
      }
      rows.add(
        ParsedUserLink(
          sourceBookTitle: _nullable(_at(cells, header['sourceBook'])),
          sourceIsUserBook: _parseSourceIsUser(
            _at(cells, header['sourceIsUser']),
          ),
          sourceCategoryId: _parseIntOrNull(
            _at(cells, header['sourceCategoryId']),
          ),
          sourceLineNumber: sourceLine,
          targetTitle: targetTitle,
          targetRef: _nullable(_at(cells, header['targetRef'])),
          connectionType: type,
          targetIsUserBook: _parseBool(_at(cells, header['targetIsUser'])),
          targetCategoryId: _parseIntOrNull(
            _at(cells, header['targetCategoryId']),
          ),
        ),
      );
    }
    return ParseResult(rows, errors);
  }

  /// מפענח קובץ JSON של קישורים — מערך אובייקטים באותה סמנטיקה כמו ה-CSV.
  /// מפתחות גמישים (עברית + aliases): מקור/source, ספר_יעד/targetTitle,
  /// מיקום_יעד/ref, סוג/type, יעד_אישי/isUserBook, ספר_מקור/sourceBook,
  /// קטגוריית_יעד/targetCategoryId.
  static ParseResult<ParsedUserLink> parseLinksJson(String content) {
    final rows = <ParsedUserLink>[];
    final errors = <ImportRowError>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      errors.add(ImportRowError(0, 'JSON לא תקין: $e'));
      return ParseResult(rows, errors);
    }
    if (decoded is! List) {
      errors.add(
        const ImportRowError(0, 'הקובץ חייב להיות מערך JSON של קישורים'),
      );
      return ParseResult(rows, errors);
    }

    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      final n = i + 1;
      if (item is! Map) {
        errors.add(ImportRowError(n, 'פריט אינו אובייקט'));
        continue;
      }
      final sourceLine = _toInt(_pick(item, const ['מקור', 'source', 'line']));
      if (sourceLine == null || sourceLine < 1) {
        errors.add(ImportRowError(n, 'מספר שורת מקור לא חוקי'));
        continue;
      }
      final targetTitle = _str(
        _pick(item, const ['ספר_יעד', 'targetTitle', 'target']),
      );
      if (targetTitle == null) {
        errors.add(ImportRowError(n, 'חסר שם ספר יעד'));
        continue;
      }
      final type = _connectionType(
        _pick(item, const ['סוג', 'type', 'connectionType'])?.toString() ?? '',
      );
      if (type == null) {
        errors.add(ImportRowError(n, 'סוג קישור לא מוכר'));
        continue;
      }
      final srcFlag = _pick(item, const [
        'מקור_אישי',
        'sourceIsUserBook',
        'sourceIsUser',
      ]);
      rows.add(
        ParsedUserLink(
          sourceBookTitle: _str(_pick(item, const ['ספר_מקור', 'sourceBook'])),
          sourceIsUserBook: srcFlag == null ? true : _toBool(srcFlag),
          sourceCategoryId: _toInt(
            _pick(item, const ['קטגוריית_מקור', 'sourceCategoryId']),
          ),
          sourceLineNumber: sourceLine,
          targetTitle: targetTitle,
          targetRef: _str(_pick(item, const ['מיקום_יעד', 'מיקום', 'ref'])),
          connectionType: type,
          targetIsUserBook: _toBool(
            _pick(item, const ['יעד_אישי', 'targetIsUserBook', 'isUserBook']),
          ),
          targetCategoryId: _toInt(
            _pick(item, const ['קטגוריית_יעד', 'targetCategoryId']),
          ),
        ),
      );
    }
    return ParseResult(rows, errors);
  }

  /// מפענח קובץ קישורים בפורמט ה-native של אוצריא (`<ספר>_links.json`):
  /// מערך אובייקטים עם line_index_1/2, path_2, heRef_2, "Conection Type".
  /// אינדקסי השורות הם 1-based (כמו במודל [Link]).
  static ParseResult<ParsedNativeLink> parseNativeLinksJson(String content) {
    final rows = <ParsedNativeLink>[];
    final errors = <ImportRowError>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      errors.add(ImportRowError(0, 'JSON לא תקין: $e'));
      return ParseResult(rows, errors);
    }
    if (decoded is! List) {
      errors.add(
        const ImportRowError(0, 'הקובץ חייב להיות מערך JSON של קישורים'),
      );
      return ParseResult(rows, errors);
    }

    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      final n = i + 1;
      if (item is! Map) {
        errors.add(ImportRowError(n, 'פריט אינו אובייקט'));
        continue;
      }
      final sourceLine = _toInt(item['line_index_1']);
      final targetLine = _toInt(item['line_index_2']);
      if (sourceLine == null || sourceLine < 1) {
        errors.add(ImportRowError(n, 'line_index_1 לא חוקי'));
        continue;
      }
      if (targetLine == null || targetLine < 1) {
        errors.add(ImportRowError(n, 'line_index_2 לא חוקי'));
        continue;
      }
      final targetTitle = _str(item['path_2']);
      if (targetTitle == null) {
        errors.add(ImportRowError(n, 'חסר path_2'));
        continue;
      }
      // בפורמט ה-native סוג ריק משמעו commentary (כמו Link.fromJson).
      final rawType = _str(item['Conection Type']) ?? 'commentary';
      final type = _connectionType(rawType);
      if (type == null) {
        errors.add(ImportRowError(n, 'סוג קישור לא מוכר: "$rawType"'));
        continue;
      }
      rows.add(
        ParsedNativeLink(
          sourceLineNumber: sourceLine,
          // path_2 הוא נתיב — חילוץ כותרת בדיוק כמו בשאר הקוד (Link.path2).
          targetTitle: getTitleFromPath(targetTitle).trim(),
          targetLineNumber: targetLine,
          targetRef: _str(item['heRef_2']),
          connectionType: type,
        ),
      );
    }
    return ParseResult(rows, errors);
  }

  // ---- עזרי מיפוי ----

  static Object? _pick(Map map, List<String> keys) {
    for (final k in keys) {
      if (map.containsKey(k) && map[k] != null) return map[k];
    }
    return null;
  }

  static int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static bool _toBool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    return v != null && _parseBool(v.toString());
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// מחזיר את שם הדור הקנוני התואם, או null אם לא מוכר (התאמה חסרת-גרשיים).
  static String? _canonicalEra(String raw) {
    final normalized = _stripGershayim(raw);
    for (final name in kCanonicalEraNames) {
      if (_stripGershayim(name) == normalized) return name;
    }
    return null;
  }

  /// מחזיר שם connection_type לפי תווית עברית או שם אנגלי ישיר.
  static String? _connectionType(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final hebrew = kHebrewConnectionTypes[trimmed];
    if (hebrew != null) return hebrew;
    final upper = trimmed.toUpperCase();
    if (kHebrewConnectionTypes.values.contains(upper)) return upper;
    return null;
  }

  static bool _parseBool(String raw) {
    final v = raw.trim().toLowerCase();
    return v == 'כן' || v == 'true' || v == '1' || v == 'yes';
  }

  /// דגל "מקור אישי" עם ברירת מחדל true — עמודה חסרה/ריקה משמעה מקור אישי,
  /// לשמירת תאימות לקבצי קישורים קיימים (שבהם המקור תמיד היה ספר אישי).
  static bool _parseSourceIsUser(String raw) =>
      raw.trim().isEmpty ? true : _parseBool(raw);

  static int? _parseIntOrNull(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    return int.tryParse(v);
  }

  static String? _nullable(String raw) => raw.isEmpty ? null : raw;

  static String _stripGershayim(String s) => s
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '')
      .trim();

  // ---- פענוח CSV ----

  static String _at(List<String> cells, int? col) =>
      (col != null && col >= 0 && col < cells.length) ? cells[col] : '';

  /// ממפה שם-עמודה → אינדקס, לפי מילון של מפתח→שמות-נרדפים אפשריים.
  static Map<String, int> _indexHeader(
    List<String> headerCells,
    Map<String, List<String>> spec,
  ) {
    final normalized = [for (final c in headerCells) c.trim()];
    final result = <String, int>{};
    for (final entry in spec.entries) {
      for (var i = 0; i < normalized.length; i++) {
        if (entry.value.contains(normalized[i])) {
          result[entry.key] = i;
          break;
        }
      }
    }
    return result;
  }

  static List<_CsvRecord> _parseCsv(String content) {
    final clean = content.replaceFirst('\uFEFF', '');
    final records = <_CsvRecord>[];
    var lineNumber = 0;
    for (final rawLine in const LineSplitter().convert(clean)) {
      lineNumber++;
      if (rawLine.trim().isEmpty) continue;
      if (rawLine.trimLeft().startsWith('#')) continue;
      records.add(_CsvRecord(lineNumber, _parseLine(rawLine)));
    }
    return records;
  }

  static List<String> _parseLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    var i = 0;
    var atFieldStart = true;
    while (i < line.length) {
      final c = line[i];
      if (atFieldStart && c == '"') {
        i++;
        while (i < line.length) {
          if (line[i] == '"') {
            if (i + 1 < line.length && line[i + 1] == '"') {
              buf.write('"');
              i += 2;
              continue;
            }
            i++;
            break;
          }
          buf.write(line[i]);
          i++;
        }
        while (i < line.length && line[i] != ',') {
          i++;
        }
        atFieldStart = false;
        continue;
      }
      if (c == ',') {
        fields.add(buf.toString().trim());
        buf.clear();
        atFieldStart = true;
        i++;
        continue;
      }
      buf.write(c);
      atFieldStart = false;
      i++;
    }
    fields.add(buf.toString().trim());
    return fields;
  }
}

class _CsvRecord {
  final int lineNumber;
  final List<String> cells;
  const _CsvRecord(this.lineNumber, this.cells);
}
