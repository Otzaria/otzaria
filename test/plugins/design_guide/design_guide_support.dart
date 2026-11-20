import 'dart:convert';
import 'dart:io';

import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:path/path.dart' as p;

/// תיקיית התיעוד של ה-SDK, יחסית לשורש הפרויקט (שם רצות הבדיקות).
const String kSdkDocsDir = 'docs/plugin-sdk';

/// תוסף הדוגמה שמדגים את כל רכיבי המדריך.
const String kGalleryDir = 'docs/plugin-sdk/examples/design-gallery';

/// בלוק קוד גדור (``` ... ```) ממסמך Markdown.
class FencedBlock {
  const FencedBlock({
    required this.file,
    required this.language,
    required this.body,
    required this.line,
  });

  final String file;
  final String language;
  final String body;

  /// השורה (1-based) שבה נפתח הבלוק, להודעות כשל שאפשר ללכת אליהן.
  final int line;

  String get where => '$file:$line';
}

/// כל הבלוקים הגדורים במסמך. שפה ריקה מוחזרת כמחרוזת ריקה.
List<FencedBlock> fencedBlocks(String relativePath) {
  final lines = File(relativePath).readAsLinesSync();
  final blocks = <FencedBlock>[];
  String? language;
  var start = 0;
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trimLeft();
    if (!trimmed.startsWith('```')) {
      if (language != null) buffer.writeln(lines[i]);
      continue;
    }
    if (language == null) {
      language = trimmed.substring(3).trim().toLowerCase();
      start = i + 1;
      buffer.clear();
    } else {
      blocks.add(
        FencedBlock(
          file: relativePath,
          language: language,
          body: buffer.toString(),
          line: start,
        ),
      );
      language = null;
    }
  }
  return blocks;
}

/// תוכן spec.json (הנגזר מהקוד האמיתי, ונבדק ב-plugin_spec_freshness_test).
Map<String, dynamic> loadSpec() =>
    jsonDecode(File('$kSdkDocsDir/spec.json').readAsStringSync())
        as Map<String, dynamic>;

/// כל ה-API methods שהמארח מכיר (מתועדים ושאינם).
Set<String> knownApiMethods(Map<String, dynamic> spec) => {
  ...(spec['apiMethods'] as List).cast<String>(),
  ...(spec['undocumentedApiMethods'] as List).cast<String>(),
};

final RegExp _callRe = RegExp(r'''Otzaria\s*\.\s*call\(\s*['"]([\w.]+)['"]''');
final RegExp _onRe = RegExp(r'''Otzaria\s*\.\s*on\(\s*['"]([\w.:]+)['"]''');

/// הקריאות `Otzaria.call('x')` שבטקסט.
Set<String> calledMethods(String source) => {
  for (final m in _callRe.allMatches(source)) m.group(1)!,
};

/// הרישומים `Otzaria.on('e')` שבטקסט.
Set<String> subscribedEvents(String source) => {
  for (final m in _onRe.allMatches(source)) m.group(1)!,
};

const String _guardCss = '.g { color: var(--color-on-surface); }\n';

/// מריץ את בדיקת העיצוב האמיתית של הוולידטור על בלוק css או html בודד.
/// מחזיר את ההפרות (ריק = תקין). שורת "חובה להשתמש ב-var(--color-*)" אינה
/// רלוונטית לקטע, ולכן נוסף לו כלל שימוש.
List<String> designViolationsOf(
  String language,
  String body,
  Directory tempDir,
) {
  final dir = Directory(p.join(tempDir.path, 'snippet'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  if (language == 'css') {
    File(
      p.join(dir.path, 'index.html'),
    ).writeAsStringSync('<html lang="he" dir="rtl"><body></body></html>');
    File(p.join(dir.path, 'styles.css')).writeAsStringSync(body);
  } else {
    File(p.join(dir.path, 'index.html')).writeAsStringSync(body);
  }
  File(p.join(dir.path, 'guard.css')).writeAsStringSync(_guardCss);

  final json = <String, dynamic>{
    'schemaVersion': 1,
    'id': 'docs.snippet',
    'name': 'Snippet',
    'version': '1.0.0',
    'description': '',
    'author': '',
    'homepage': '',
    'entrypoint': 'index.html',
    'minAppVersion': '0.9.99',
    'sdkVersion': '1.x',
    'permissions': const <String>[],
    'contributes': {
      'toolTab': {'title': 'Snippet', 'order': 900, 'defaultPinned': false},
    },
  };
  final report = PluginExtendedValidator.validate(
    manifest: PluginManifest.fromJson(json),
    manifestJson: json,
    directoryPath: dir.path,
  );
  return report.design.violations;
}
