import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'design_guide_support.dart';

/// חוזה בין מדריך העיצוב (`DESIGN_GUIDE.md`) והמתכונים (`COOKBOOK.md`) לבין מה
/// שהמארח והוולידטור באמת עושים. מי שמעתיק דוגמה מהמדריך אמור לעבור את שער
/// "מראה תואם לאוצריא" בחנות, וקריאה לשיטה שאינה קיימת היא באג במסמך.
const List<String> kDesignDocs = [
  '$kSdkDocsDir/DESIGN_GUIDE.md',
  '$kSdkDocsDir/COOKBOOK.md',
];

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria_design_docs_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('דוגמאות CSS/HTML במדריכים עוברות את בדיקת העיצוב של הוולידטור', () {
    for (final doc in kDesignDocs) {
      test(doc, () {
        final failures = <String>[];
        var checked = 0;
        for (final block in fencedBlocks(doc)) {
          if (block.language != 'css' && block.language != 'html') continue;
          checked++;
          final violations = designViolationsOf(
            block.language,
            block.body,
            tempDir,
          );
          if (violations.isNotEmpty) {
            failures.add('${block.where}: ${violations.join(' | ')}');
          }
        }
        expect(checked, greaterThan(0), reason: 'לא נמצאו דוגמאות ב-$doc');
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  });

  group('כל Otzaria.call/on בדוגמאות קיימים ב-spec.json', () {
    final spec = loadSpec();
    final methods = knownApiMethods(spec);
    final events = (spec['events'] as List).cast<String>().toSet();

    for (final doc in kDesignDocs) {
      test(doc, () {
        final unknown = <String>[];
        for (final block in fencedBlocks(doc)) {
          if (!{'js', 'javascript', 'html'}.contains(block.language)) continue;
          for (final m in calledMethods(block.body)) {
            if (!methods.contains(m)) unknown.add('${block.where}: call $m');
          }
          for (final e in subscribedEvents(block.body)) {
            if (!events.contains(e)) unknown.add('${block.where}: on $e');
          }
        }
        expect(unknown, isEmpty, reason: unknown.join('\n'));
      });
    }
  });

  group('שמות API בטקסט של המדריך קיימים', () {
    // `reader.addToolbarItem`, `ui.setFullscreen` וכד' בתוך backticks: שם שייך
    // למרחב של API אמיתי חייב להיות method, אירוע או הרשאה שקיימים.
    test('DESIGN_GUIDE.md', () {
      final spec = loadSpec();
      final methods = knownApiMethods(spec);
      final events = (spec['events'] as List).cast<String>().toSet();
      final permissions = (spec['permissions'] as List).cast<String>().toSet();
      final namespaces = {for (final m in methods) m.split('.').first};
      final unknown = <String>{};
      final text = File('$kSdkDocsDir/DESIGN_GUIDE.md').readAsStringSync();
      for (final m in RegExp(r'`([a-z]+\.[A-Za-z_.]+)`').allMatches(text)) {
        final name = m.group(1)!;
        if (!namespaces.contains(name.split('.').first)) continue;
        if (methods.contains(name) ||
            events.contains(name) ||
            permissions.contains(name)) {
          continue;
        }
        unknown.add(name);
      }
      expect(unknown, isEmpty, reason: unknown.join('\n'));
    });
  });

  group('הרשאות בסיס אינן מוצגות כנדרשות להצהרה', () {
    // המדריך הורה בעבר להצהיר על events.subscribe:theme.changed, שהיא הרשאת
    // בסיס (מ-0.9.97) והוולידטור מזהיר על הצהרה עליה.
    test('אין "דורש הרשאה" ליד הרשאת בסיס', () {
      final baseline = (loadSpec()['baselinePermissions'] as List)
          .cast<String>();
      final offenders = <String>[];
      for (final doc in [
        ...kDesignDocs,
        '$kSdkDocsDir/README.md',
        '$kSdkDocsDir/API_REFERENCE.md',
      ]) {
        final lines = File(doc).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!baseline.any(line.contains)) continue;
          if (RegExp(
            r'(?<!אינו\s)(?<!אינה\s)דורש(ת)?\s+(את\s+)?הרשאה|⚠️\s*דורש',
          ).hasMatch(line)) {
            offenders.add('$doc:${i + 1}: $line');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });

  group('קישורים יחסיים במדריכים', () {
    final linkRe = RegExp(r'\]\(([^)\s]+)\)');

    /// עוגן בסגנון GitHub: אותיות קטנות, בלי פיסוק, רווח למקף.
    String slug(String heading) {
      final cleaned = heading
          .replaceAll(RegExp(r'[`*]'), '')
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
          .replaceAll(RegExp(r'\s'), '-');
      return cleaned;
    }

    String decode(String s) {
      try {
        return Uri.decodeFull(s);
      } on ArgumentError {
        return s;
      }
    }

    Set<String> anchorsOf(String path) => {
      for (final line in File(path).readAsLinesSync())
        if (RegExp(r'^#{1,6}\s').hasMatch(line))
          slug(line.replaceFirst(RegExp(r'^#{1,6}\s+'), '')),
    };

    for (final doc in kDesignDocs) {
      test(doc, () {
        final broken = <String>[];
        final lines = File(doc).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final m in linkRe.allMatches(lines[i])) {
            final target = m.group(1)!;
            if (target.startsWith('http') || target.startsWith('mailto:')) {
              continue;
            }
            final hash = target.indexOf('#');
            final pathPart = hash < 0 ? target : target.substring(0, hash);
            final anchor = hash < 0 ? '' : target.substring(hash + 1);
            final file = pathPart.isEmpty
                ? doc
                : '$kSdkDocsDir/${decode(pathPart)}';
            final exists =
                File(file).existsSync() || Directory(file).existsSync();
            if (!exists) {
              broken.add('$doc:${i + 1}: $target (הקובץ לא קיים)');
              continue;
            }
            if (anchor.isNotEmpty &&
                file.endsWith('.md') &&
                !anchorsOf(file).contains(decode(anchor))) {
              broken.add('$doc:${i + 1}: $target (העוגן לא קיים)');
            }
          }
        }
        expect(broken, isEmpty, reason: broken.join('\n'));
      });
    }
  });
}
