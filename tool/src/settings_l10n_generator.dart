// מחולל הקטלוג האנגלי של מסך ההגדרות: קורא את `settings_en.arb` ומחולל
// ממנו מפת Dart קבועה, כדי שהתרגום יהיה זמין מיידית בלי טעינה אסינכרונית.
//
// הלוגיקה משותפת ל-`tool/generate_settings_l10n.dart` (ידני / CI)
// ול-`hook/build.dart` (רץ אוטומטית בכל בנייה).

import 'dart:convert';
import 'dart:io';

const String l10nDirRelativePath = 'lib/settings/l10n';
const String l10nOutputRelativePath =
    'lib/settings/l10n/settings_catalogs.g.dart';

/// כל `lib/` ולא רק `lib/settings` — הקטלוג משרת גם את סרגל הניווט ופס
/// הכותרת, וקריאה ל-`settingsText` בכל מקום חייבת תרגום.
const String l10nScanRootRelativePath = 'lib';

/// שפת המקור: הטקסטים בקוד כתובים בה ומשמשים כמפתח, ולכן אין לה קובץ ARB.
const String sourceLanguageCode = 'he';

/// מוצא את קובצי הקטלוג, ממופים לפי קוד השפה שבשמם.
Map<String, File> findCatalogFiles(Directory packageRoot) {
  final dir = Directory.fromUri(
    packageRoot.uri.resolve('$l10nDirRelativePath/'),
  );
  if (!dir.existsSync()) return const {};

  final pattern = RegExp(r'settings_([a-z]{2}(?:_[A-Za-z]+)?)\.arb$');
  final files = <String, File>{};
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    final match = pattern.firstMatch(entity.uri.pathSegments.last);
    if (match != null) files[match.group(1)!] = entity;
  }
  return files;
}

/// שגיאת ולידציה בקטלוג התרגומים.
class SettingsL10nError implements Exception {
  SettingsL10nError(this.message);

  final String message;

  @override
  String toString() => message;
}

class GenerateL10nResult {
  const GenerateL10nResult({
    required this.changed,
    required this.outputPath,
    required this.entriesCount,
  });

  final bool changed;
  final String outputPath;
  final int entriesCount;
}

/// מחלץ שמות placeholders בפורמט `{name}`.
Set<String> extractPlaceholders(String text) =>
    RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

/// מחלץ את מפתחות ה-JSON ברמה העליונה לפי סדר הופעתם, כולל כפילויות.
/// `jsonDecode` בולע מפתח כפול בשקט, ולכן הזיהוי נעשה על הטקסט הגולמי.
List<String> extractRawKeys(String source) {
  final keys = <String>[];
  var depth = 0;
  var inString = false;
  var escaped = false;
  final buffer = StringBuffer();
  var stringStartDepth = 0;

  for (var i = 0; i < source.length; i++) {
    final ch = source[i];

    if (inString) {
      if (escaped) {
        buffer.write(ch);
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        buffer.write(ch);
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = false;
        // מפתח ברמה העליונה: מחרוזת בעומק 1 שאחריה נקודתיים.
        if (stringStartDepth == 1) {
          final rest = source.substring(i + 1);
          final colonIdx = rest.indexOf(RegExp(r'\S'));
          if (colonIdx >= 0 && rest[colonIdx] == ':') {
            keys.add(jsonDecode('"${buffer.toString()}"') as String);
          }
        }
        buffer.clear();
        continue;
      }
      buffer.write(ch);
      continue;
    }

    if (ch == '"') {
      inString = true;
      stringStartDepth = depth;
      buffer.clear();
    } else if (ch == '{' || ch == '[') {
      depth++;
    } else if (ch == '}' || ch == ']') {
      depth--;
    }
  }
  return keys;
}

/// קורא ומוודא את הקטלוג. זורק [SettingsL10nError] על מפתח כפול,
/// ערך שאינו מחרוזת, או אי-התאמה ב-placeholders בין המקור לתרגום.
Map<String, String> loadAndValidateCatalog(String source, String path) {
  final Map<String, dynamic> decoded;
  try {
    decoded = jsonDecode(source) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw SettingsL10nError('$path: JSON לא תקין — ${e.message}');
  }

  final rawKeys = extractRawKeys(source);
  final seen = <String>{};
  final duplicates = <String>{};
  for (final key in rawKeys) {
    if (!seen.add(key)) duplicates.add(key);
  }
  if (duplicates.isNotEmpty) {
    throw SettingsL10nError(
      '$path: מפתחות כפולים — ${duplicates.map((k) => '"$k"').join(', ')}',
    );
  }

  final catalog = <String, String>{};
  final errors = <String>[];
  for (final entry in decoded.entries) {
    // `@@locale` והערות `@key` הן מטא-דאטה של ARB ואינן נכנסות לקטלוג.
    if (entry.key.startsWith('@')) continue;

    final value = entry.value;
    if (value is! String) {
      errors.add('"${entry.key}": הערך חייב להיות מחרוזת');
      continue;
    }

    // המפתח נושא הקשר אחרי '|' — ה-placeholders נמדדים על החלק העברי בלבד.
    final hebrew = entry.key.split('|').first;
    final sourcePlaceholders = extractPlaceholders(hebrew);
    final targetPlaceholders = extractPlaceholders(value);
    if (sourcePlaceholders.length != targetPlaceholders.length ||
        !sourcePlaceholders.containsAll(targetPlaceholders)) {
      errors.add(
        '"${entry.key}": placeholders לא תואמים — '
        'מקור {${sourcePlaceholders.join(', ')}} '
        'מול תרגום {${targetPlaceholders.join(', ')}}',
      );
      continue;
    }

    catalog[entry.key] = value;
  }

  if (errors.isNotEmpty) {
    throw SettingsL10nError('$path:\n  ${errors.join('\n  ')}');
  }
  return catalog;
}

/// קורא ומוודא את כל קובצי הקטלוג, ממופים לפי קוד שפה.
Map<String, Map<String, String>> loadAllCatalogs(Directory packageRoot) {
  final files = findCatalogFiles(packageRoot);
  if (files.containsKey(sourceLanguageCode)) {
    throw SettingsL10nError(
      'lib/settings/l10n/settings_$sourceLanguageCode.arb: '
      'שפת המקור אינה זקוקה לקטלוג — הטקסט בקוד הוא המפתח',
    );
  }

  final catalogs = <String, Map<String, String>>{};
  for (final code in files.keys.toList()..sort()) {
    final file = files[code]!;
    catalogs[code] = loadAndValidateCatalog(
      file.readAsStringSync(),
      '$l10nDirRelativePath/settings_$code.arb',
    );
  }
  return catalogs;
}

/// מחולל את מפות ה-Dart מכל קובצי ה-ARB תחת [packageRoot].
GenerateL10nResult generateSettingsL10n(Directory packageRoot) {
  final catalogs = loadAllCatalogs(packageRoot);

  // `dart format off` — בלעדיו ה-pre-commit היה מגלל את השורות הארוכות,
  // והקובץ היה מופיע כשונה מהגיט אחרי כל בנייה.
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE — DO NOT MODIFY BY HAND.')
    ..writeln('// dart format off')
    ..writeln('//')
    ..writeln('// קטלוגי התרגום של מסך ההגדרות. נוצרים אוטומטית מקובצי')
    ..writeln('// $l10nDirRelativePath/settings_<code>.arb — ערוך שם, לא כאן.')
    ..writeln()
    ..writeln('/// תרגומי מסך ההגדרות לפי קוד שפה, ממופים מהמקור העברי.')
    ..writeln(
      'const Map<String, Map<String, String>> kSettingsCatalogs = {',
    );
  for (final code in catalogs.keys) {
    final catalog = catalogs[code]!;
    buffer.writeln('  ${_dartLiteral(code)}: {');
    for (final key in catalog.keys.toList()..sort()) {
      buffer.writeln(
        '    ${_dartLiteral(key)}: ${_dartLiteral(catalog[key]!)},',
      );
    }
    buffer.writeln('  },');
  }
  buffer.writeln('};');

  final newContent = buffer.toString();
  final outputFile = File.fromUri(
    packageRoot.uri.resolve(l10nOutputRelativePath),
  );
  final changed =
      !outputFile.existsSync() || outputFile.readAsStringSync() != newContent;
  if (changed) {
    outputFile.parent.createSync(recursive: true);
    outputFile.writeAsStringSync(newContent);
  }

  return GenerateL10nResult(
    changed: changed,
    outputPath: l10nOutputRelativePath,
    entriesCount: catalogs.values.fold(0, (sum, c) => sum + c.length),
  );
}

/// מפתח שנמצא בקריאה ל-`settingsText` בקוד.
class SettingsTextUsage {
  const SettingsTextUsage({
    required this.key,
    required this.hebrew,
    required this.file,
    this.context,
  });

  /// המפתח המלא בקטלוג, כולל סיומת הקשר אם יש.
  final String key;

  /// הטקסט העברי בלבד.
  final String hebrew;

  final String file;

  /// ההקשר שנמסר ל-`settingsText`, אם נמסר.
  final String? context;
}

/// סורק את `lib/settings/` ומחזיר את כל המפתחות שנמסרו ל-`settingsText`.
///
/// מחלץ כל מחרוזת קבועה בארגומנט הראשון, כך שגם ביטוי תנאי נתפס במלואו.
/// ארגומנט שהוא משתנה אינו ניתן לחילוץ סטטי ופשוט מדולג.
List<SettingsTextUsage> scanSettingsTextUsages(Directory packageRoot) {
  final root = Directory.fromUri(
    packageRoot.uri.resolve('$l10nScanRootRelativePath/'),
  );
  final usages = <SettingsTextUsage>[];

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;

    usages.addAll(
      _usagesIn(
        _stripComments(entity.readAsStringSync()),
        entity.path
            .replaceFirst(packageRoot.path, '')
            .replaceFirst(RegExp(r'^[/\\]'), ''),
      ),
    );
  }
  return usages;
}

/// סורק את `lib/settings/` ומחזיר את מפתחות התוויות של [SegmentOption].
///
/// תווית סגמנט מוצגת ב-`FittedBox`, ולכן תרגום ארוך מוקטן ונראה שונה משכניו.
List<SettingsTextUsage> scanSegmentOptionKeys(Directory packageRoot) {
  final root = Directory.fromUri(
    packageRoot.uri.resolve('$l10nScanRootRelativePath/'),
  );
  final usages = <SettingsTextUsage>[];

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;

    final source = _stripComments(entity.readAsStringSync());
    final relativePath = entity.path
        .replaceFirst(packageRoot.path, '')
        .replaceFirst(RegExp(r'^[/\\]'), '');

    for (final match in RegExp(
      r'SegmentOption(?:<[^>]*>)?\s*\(',
    ).allMatches(source)) {
      final argsText = _extractBalancedParens(source, match.end - 1);
      if (argsText == null) continue;
      for (final part in _splitTopLevelArgs(argsText)) {
        if (!part.trimLeft().startsWith('label:')) continue;
        usages.addAll(_usagesIn(part, relativePath));
      }
    }
  }
  return usages;
}

/// מחלץ את כל הקריאות ל-`settingsText` מתוך [source] שכבר נוקה מהערות.
List<SettingsTextUsage> _usagesIn(String source, String file) {
  final usages = <SettingsTextUsage>[];
  for (final match in RegExp(r'settingsText\s*\(').allMatches(source)) {
    final argsText = _extractBalancedParens(source, match.end - 1);
    if (argsText == null) continue;

    final parts = _splitTopLevelArgs(argsText);
    if (parts.isEmpty) continue;

    final contextValue = _namedArgLiteral(parts, 'context');
    for (final hebrew in _stringLiterals(parts.first)) {
      usages.add(
        SettingsTextUsage(
          key: contextValue == null ? hebrew : '$hebrew|$contextValue',
          hebrew: hebrew,
          file: file,
          context: contextValue,
        ),
      );
    }
  }
  return usages;
}

/// מחלץ את כל המחרוזות הקבועות תחת `lib/`, עם חיבור מחרוזות סמוכות.
///
/// משמש לזיהוי תרגום שאינו בשימוש. הסריקה רחבה מ-`lib/settings/` בכוונה:
/// מסך ההגדרות מציג גם טקסט שמוצהר במקום אחר — למשל שמות צבעי הבסיס
/// ב-`lib/theme/` — ומעביר אותו ל-`settingsText` דרך משתנה.
Set<String> scanAllStringLiterals(Directory packageRoot) {
  final root = Directory.fromUri(packageRoot.uri.resolve('lib/'));
  final literals = <String>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    literals.addAll(_stringLiterals(_stripComments(entity.readAsStringSync())));
  }
  return literals;
}

/// מסיר הערות מקוד Dart. בלי זה, אפוסטרוף בתוך הערה עברית (למשל "ווידג'ט")
/// נקרא כתחילת מחרוזת ובולע את הקוד שאחריו.
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  var inString = false;
  String? quote;
  var escaped = false;

  while (i < src.length) {
    final ch = src[i];
    if (inString) {
      out.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == quote || ch == '\n') {
        inString = false;
      }
      i++;
      continue;
    }
    if (ch == "'" || ch == '"') {
      inString = true;
      quote = ch;
      out.write(ch);
      i++;
      continue;
    }
    if (ch == '/' && i + 1 < src.length) {
      if (src[i + 1] == '/') {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
        continue;
      }
      if (src[i + 1] == '*') {
        final end = src.indexOf('*/', i + 2);
        i = end < 0 ? src.length : end + 2;
        continue;
      }
    }
    out.write(ch);
    i++;
  }
  return out.toString();
}

/// מחזיר את תוכן הסוגריים שנפתחות ב-[openIdx], ללא הסוגריים עצמן.
String? _extractBalancedParens(String src, int openIdx) {
  var depth = 0;
  var inString = false;
  String? quote;
  var escaped = false;

  for (var i = openIdx; i < src.length; i++) {
    final ch = src[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == quote) {
        inString = false;
      }
      continue;
    }
    if (ch == "'" || ch == '"') {
      inString = true;
      quote = ch;
    } else if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) return src.substring(openIdx + 1, i);
    }
  }
  return null;
}

/// מפצל רשימת ארגומנטים לפי פסיקים ברמה העליונה בלבד.
List<String> _splitTopLevelArgs(String args) {
  final parts = <String>[];
  var depth = 0;
  var inString = false;
  String? quote;
  var escaped = false;
  var start = 0;

  for (var i = 0; i < args.length; i++) {
    final ch = args[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == quote) {
        inString = false;
      }
      continue;
    }
    if (ch == "'" || ch == '"') {
      inString = true;
      quote = ch;
    } else if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    } else if (ch == ',' && depth == 0) {
      parts.add(args.substring(start, i));
      start = i + 1;
    }
  }
  final last = args.substring(start).trim();
  if (last.isNotEmpty) parts.add(last);
  return parts;
}

String? _namedArgLiteral(List<String> parts, String name) {
  for (final part in parts) {
    final trimmed = part.trim();
    if (!trimmed.startsWith('$name:')) continue;
    final literals = _stringLiterals(trimmed.substring(name.length + 1));
    if (literals.isNotEmpty) return literals.first;
  }
  return null;
}

/// מחלץ מחרוזות קבועות, ומחבר מחרוזות סמוכות כפי ש-Dart מחבר אותן.
List<String> _stringLiterals(String expression) {
  final results = <String>[];
  final buffer = StringBuffer();
  var i = 0;
  var lastEnd = -1;

  while (i < expression.length) {
    final ch = expression[i];
    if (ch != "'" && ch != '"') {
      i++;
      continue;
    }
    final quote = ch;
    final content = StringBuffer();
    var j = i + 1;
    var escaped = false;
    var closed = false;
    while (j < expression.length) {
      final c = expression[j];
      if (escaped) {
        content.write(_unescape(c));
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == quote) {
        closed = true;
        break;
      } else {
        content.write(c);
      }
      j++;
    }
    if (!closed) break;

    // מחרוזות מופרדות ברווח בלבד הן מחרוזת אחת מחוברת בזמן קומפילציה.
    final gap = lastEnd < 0 ? null : expression.substring(lastEnd, i).trim();
    if (gap != null && gap.isEmpty) {
      buffer.write(content);
    } else {
      if (buffer.isNotEmpty) results.add(buffer.toString());
      buffer
        ..clear()
        ..write(content);
    }
    lastEnd = j + 1;
    i = j + 1;
  }
  if (buffer.isNotEmpty) results.add(buffer.toString());
  return results;
}

String _unescape(String c) => switch (c) {
  'n' => '\n',
  't' => '\t',
  'r' => '\r',
  _ => c,
};

String _dartLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}
