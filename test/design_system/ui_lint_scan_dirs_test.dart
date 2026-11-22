import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/ui_lint/ui_lint.dart';

/// חבילת תפריט ההקשר נסרקת בכללי העיצוב (הכרעת בעל הפרויקט 18.11, סעיף 54 Q3),
/// בלי רשומות baseline: היא צריכה לעבור את הכללים, או לקבל החרגת נתיב מנומקת.
const _package = 'packages/otzaria_context_menu';

final _config = UiLintConfig.load('.');

void main() {
  test('תיקיות הסריקה כוללות את lib ואת חבילת תפריט ההקשר, וכולן קיימות', () {
    expect(uiLintScanDirs, containsAll(['lib', '$_package/lib']));
    for (final dir in uiLintScanDirs) {
      expect(Directory(dir).existsSync(), isTrue, reason: dir);
    }
  });

  test('אין חריגה בחבילה שאינה מכוסה בהחרגת נתיב או בהערת allow', () {
    final result = runUiLint('.', config: _config);
    final inPackage = [
      for (final finding in result.findings)
        if (finding.path.startsWith('$_package/'))
          '${finding.rule} ${finding.path}:${finding.line}',
    ];
    expect(
      inPackage,
      isEmpty,
      reason:
          'החבילה נסרקת. לתקן בקוד, או להחריג נתיב ב-tool/ui_lint/config.yaml '
          'עם נימוק',
    );
  });

  test('baseline לא מחזיק רשומות של החבילה (הוא לא יכול לגדול)', () {
    final baseline =
        jsonDecode(File('tool/ui_lint/baseline.json').readAsStringSync())
            as Map<String, dynamic>;
    final rules = baseline['rules'] as Map<String, dynamic>;
    final packageFiles = [
      for (final files in rules.values)
        for (final path in (files as Map<String, dynamic>).keys)
          if (path.startsWith('$_package/')) path,
    ];
    expect(packageFiles, isEmpty);
  });

  test('כלל שאין לו החרגה לחבילה נאכף בה: רדיוס ליטרלי בקובץ של החבילה', () {
    final result = lintSource(
      "import 'package:flutter/material.dart';\n"
          'final r = BorderRadius.circular(6);\n',
      '$_package/lib/src/sample.dart',
      config: _config,
    );
    expect(result.findings.map((f) => f.rule), contains('UIL-019'));
  });

  test('החבילה היא מודול בשם שלה בטבלת המצב לפי מודול', () {
    expect(
      moduleOf('$_package/lib/src/menu_rows.dart'),
      'otzaria_context_menu',
    );
    expect(moduleOf('lib/widgets/a.dart'), 'widgets');
  });

  test('תיקיית סריקה שאינה קיימת בשורש מדלגים עליה (מאגר זמני)', () {
    final repo = Directory.systemTemp.createTempSync('ui_lint_scan_dirs_');
    try {
      File('${repo.path}/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('const x = 1;\n');
      final result = runUiLint(
        repo.path,
        config: UiLintConfig.parse('rules: {}\n'),
      );
      expect(result.findings, isEmpty);
    } finally {
      repo.deleteSync(recursive: true);
    }
  });
}
