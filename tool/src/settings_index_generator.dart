// ignore_for_file: avoid_print
//
// לוגיקה משותפת לחילול אינדקס החיפוש בהגדרות.
// משמשת את `hook/build.dart` (אוטומטית בכל בנייה) ואת
// `tool/generate_search_index.dart` (ידנית / CI).
//
// סורק את כל קבצי ה-Dart תחת `lib/settings/`, אוסף הצהרות
// `static const List<SettingsSearchEntry> searchEntries`, ומחולל
// אינדקס מאוחד אל `lib/settings/search/settings_search_index.g.dart`.

import 'dart:io';

const String settingsRootRelativePath = 'lib/settings';
const String outputRelativePath =
    'lib/settings/search/settings_search_index.g.dart';
const String pubspecRelativePath = 'pubspec.yaml';

/// תוצאת החילול.
class GenerateResult {
  /// האם הקובץ נכתב מחדש (false = היה זהה ולא נדרש שינוי).
  final bool changed;

  /// מספר ההצהרות שנמצאו.
  final int declarationsCount;

  /// נתיב הקובץ שנכתב.
  final String outputPath;

  const GenerateResult({
    required this.changed,
    required this.declarationsCount,
    required this.outputPath,
  });
}

/// מחולל את אינדקס החיפוש בהגדרות. מחזיר תוצאה עם פרטי החילול.
/// אם תיקיית ההגדרות לא קיימת — מחזיר תוצאה ריקה ללא כתיבה.
GenerateResult generateSettingsSearchIndex(Directory packageRoot) {
  final settingsRoot = Directory.fromUri(
    packageRoot.uri.resolve('$settingsRootRelativePath/'),
  );
  if (!settingsRoot.existsSync()) {
    return GenerateResult(
      changed: false,
      declarationsCount: 0,
      outputPath: outputRelativePath,
    );
  }

  final packageName = _readPackageName(packageRoot);

  final declarations = <_FoundDecl>[];
  for (final entity
      in settingsRoot.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;

    final content = entity.readAsStringSync();
    final relPath = _relativeToPackage(entity, packageRoot);
    declarations.addAll(_findDeclarations(content, relPath, packageName));
  }

  // גם כשהרשימה ריקה — נכתוב אינדקס ריק (במקום לוותר). אחרת ה-.g.dart
  // הישן יישאר עם imports/entries שלא קיימים יותר ויגרום לשגיאות
  // קומפילציה או לתוצאות חיפוש פנטומיות.

  declarations.sort((a, b) {
    final tabCmp = a.tabValue.compareTo(b.tabValue);
    if (tabCmp != 0) return tabCmp;
    return a.className.compareTo(b.className);
  });

  final imports = <String>{};
  final spreads = <String>[];
  for (final decl in declarations) {
    imports.add(decl.importPath);
    spreads.add('  ...${decl.className}.searchEntries,');
  }
  final sortedImports = imports.toList()..sort();

  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE — DO NOT MODIFY BY HAND.')
    ..writeln('//')
    ..writeln('// אינדקס חיפוש מאוחד של ההגדרות. נוצר אוטומטית מתוך')
    ..writeln('// הצהרות `static const searchEntries` בקבצים תחת lib/settings/.')
    ..writeln('')
    ..writeln(
        "import 'package:$packageName/settings/search/settings_search_models.dart';");
  for (final imp in sortedImports) {
    buffer.writeln("import '$imp';");
  }
  buffer
    ..writeln('')
    ..writeln('/// כל פריטי החיפוש שנאספו מהטאבים והפנלים.')
    ..writeln(
        'const List<SettingsSearchEntry> kGeneratedSettingsSearchEntries = [');
  for (final line in spreads) {
    buffer.writeln(line);
  }
  buffer.writeln('];');

  final outputFile = File.fromUri(packageRoot.uri.resolve(outputRelativePath));
  final newContent = buffer.toString();

  // כתוב רק אם השתנה — מונע מודיפיקציות מיותרות שיגרמו ל-rebuild.
  if (outputFile.existsSync()) {
    final existing = outputFile.readAsStringSync();
    if (existing == newContent) {
      return GenerateResult(
        changed: false,
        declarationsCount: declarations.length,
        outputPath: outputFile.path,
      );
    }
  }
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(newContent);
  return GenerateResult(
    changed: true,
    declarationsCount: declarations.length,
    outputPath: outputFile.path,
  );
}

/// קורא את שם החבילה מתוך `pubspec.yaml` כדי לבנות נתיבי `package:` נכונים
/// במקום לקודד שם קשיח. נכשל בקול אם השדה לא נמצא — עדיף שגיאה ברורה
/// מאשר אינדקס שגוי בשקט.
String _readPackageName(Directory packageRoot) {
  final pubspec =
      File.fromUri(packageRoot.uri.resolve(pubspecRelativePath));
  if (!pubspec.existsSync()) {
    throw StateError('pubspec.yaml not found at: ${pubspec.path}');
  }
  final match = RegExp(r'^name:\s*([A-Za-z_][A-Za-z0-9_]*)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync());
  if (match == null) {
    throw StateError('Could not parse package name from ${pubspec.path}');
  }
  return match.group(1)!;
}

String _relativeToPackage(File file, Directory packageRoot) {
  final rootPath = packageRoot.path.replaceAll('\\', '/');
  final filePath = file.path.replaceAll('\\', '/');
  if (filePath.startsWith(rootPath)) {
    var rel = filePath.substring(rootPath.length);
    if (rel.startsWith('/')) rel = rel.substring(1);
    return rel;
  }
  return filePath;
}

List<_FoundDecl> _findDeclarations(
    String content, String relPath, String packageName) {
  // הסר מחרוזות והערות לפני סריקה, כדי שאיזון הסוגריים יהיה מהימן
  // ולא יוטעה על-ידי `}` או `{` בתוך מחרוזת/הערה.
  final cleaned = _stripStringsAndComments(content);

  final results = <_FoundDecl>[];
  // מזהה כל הצהרת מחלקה (לרבות final/base/sealed/abstract/interface/mixin
  // ו-generics, גם בלי extends).
  final classMatches = RegExp(
    r'(?:abstract\s+|base\s+|final\s+|sealed\s+|interface\s+|mixin\s+)?'
    r'class\s+(\w+)\s*(?:<[^{>]+>)?\s*'
    r'(?:extends\s+[^{]+|with\s+[^{]+|implements\s+[^{]+)*\s*\{',
  ).allMatches(cleaned);

  for (final classMatch in classMatches) {
    final className = classMatch.group(1)!;
    final classBody = _extractBalanced(cleaned, classMatch.end - 1, '{', '}');
    if (classBody == null) continue;
    if (!classBody.contains('searchEntries')) continue;

    final entriesDecl = RegExp(
      r'static\s+const\s+List<SettingsSearchEntry>\s+searchEntries\s*=\s*\[',
    ).firstMatch(classBody);
    if (entriesDecl == null) continue;

    final tabMatch =
        RegExp(r'tab:\s*SettingsTab\.(\w+)').firstMatch(classBody);
    final tabValue = tabMatch?.group(1) ?? 'zzz';

    final libIndex = relPath.indexOf('lib/');
    final libRelPath = libIndex >= 0
        ? relPath.substring(libIndex + 'lib/'.length)
        : relPath;

    results.add(_FoundDecl(
      className: className,
      importPath: 'package:$packageName/$libRelPath',
      tabValue: tabValue,
    ));
  }

  return results;
}

/// מחליף מחרוזות והערות ברווחים שווי-אורך, כך שאינדקסי תווים נשארים
/// תקפים אבל אין סיכוי שתוכן בתוך string/comment יזהם את הסריקה.
String _stripStringsAndComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    final c2 = (i + 1 < src.length) ? src[i + 1] : '';

    // הערה חד-שורתית //
    if (c == '/' && c2 == '/') {
      while (i < src.length && src[i] != '\n') {
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    // הערה רב-שורתית /* ... */
    if (c == '/' && c2 == '*') {
      while (i < src.length) {
        if (i + 1 < src.length && src[i] == '*' && src[i + 1] == '/') {
          out.write('  ');
          i += 2;
          break;
        }
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    // מחרוזת raw או רגילה, single/double, single/triple quoted
    if (c == "'" || c == '"' || (c == 'r' && (c2 == '"' || c2 == "'"))) {
      var idx = (c == 'r') ? i + 1 : i;
      final quote = src[idx];
      final isTriple = idx + 2 < src.length &&
          src[idx + 1] == quote &&
          src[idx + 2] == quote;
      // העתק את התווים שלפני המרכאות (במקרה raw — 'r')
      while (i <= idx) {
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (isTriple) {
        out.write('  ');
        i += 2;
        while (i + 2 < src.length) {
          if (src[i] == quote && src[i + 1] == quote && src[i + 2] == quote) {
            out.write('   ');
            i += 3;
            break;
          }
          out.write(src[i] == '\n' ? '\n' : ' ');
          i++;
        }
      } else {
        final isRaw = (c == 'r');
        while (i < src.length) {
          if (!isRaw && src[i] == '\\' && i + 1 < src.length) {
            out.write(src[i + 1] == '\n' ? ' \n' : '  ');
            i += 2;
            continue;
          }
          if (src[i] == quote) {
            out.write(' ');
            i++;
            break;
          }
          out.write(src[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

String? _extractBalanced(String src, int openIdx, String open, String close) {
  if (openIdx < 0 || openIdx >= src.length || src[openIdx] != open) return null;
  var depth = 0;
  for (var i = openIdx; i < src.length; i++) {
    final c = src[i];
    if (c == open) depth++;
    if (c == close) {
      depth--;
      if (depth == 0) return src.substring(openIdx + 1, i);
    }
  }
  return null;
}

class _FoundDecl {
  final String className;
  final String importPath;
  final String tabValue;
  _FoundDecl({
    required this.className,
    required this.importPath,
    required this.tabValue,
  });
}
