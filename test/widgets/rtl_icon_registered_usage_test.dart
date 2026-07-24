import 'dart:io';

import 'package:test/test.dart';

/// בדיקה סטטית: כל ליטרל אייקון שמועבר ישירות ל-RtlIcon() חייב להיות רשום
/// ב-lib/widgets/misc/rtl_icon.dart (ב-_fluentMirrorMap, _materialMirrorMap,
/// או _flippableIcons).
///
/// שימוש עם משתנה (למשל RtlIcon(rtlIcon)) — לא נבדק כאן, זו אחריות הקורא.
void main() {
  test('כל ליטרל אייקון ב-RtlIcon() רשום ב-rtl_icon.dart', () {
    final registered = _extractRegisteredIcons();
    expect(
      registered,
      isNotEmpty,
      reason: 'לא נמצאו אייקונים רשומים ב-rtl_icon.dart — בדוק את הנתיב',
    );

    final violations = _findViolations(registered);

    expect(
      violations,
      isEmpty,
      reason:
          'שימושי RtlIcon עם אייקונים לא רשומים:\n${violations.join('\n')}'
          '\n\nאפשרויות:\n'
          '  1. אייקון סימטרי? השתמש ב-Icon(...) רגיל.\n'
          '  2. אייקון כיווני? הוסף אותו ל-rtl_icon.dart ואז השתמש ב-RtlIcon.',
    );
  });
}

/// חולץ את כל שמות האייקונים הרשומים מתוך הגדרות המפות/הסט ב-rtl_icon.dart.
/// קורא רק את החלק שלפני ה-build() כדי לא לכלול את השימוש בתוך הלוגיקה.
Set<String> _extractRegisteredIcons() {
  final file = File('lib/widgets/misc/rtl_icon.dart');
  final content = file.readAsStringSync();

  final buildIdx = content.indexOf('@override\n  Widget build');
  final definitions = buildIdx > 0 ? content.substring(0, buildIdx) : content;

  return RegExp(
    r'((?:FluentIcons|Icons)\.\w+)',
  ).allMatches(definitions).map((m) => m.group(1)!).toSet();
}

/// סורק את כל קבצי lib/ ומחפש ליטרלי אייקון שמועברים ישירות ל-RtlIcon().
/// משתנים כמו RtlIcon(rtlIcon) או RtlIcon(icon) — לא נתפסים ולא נבדקים.
List<String> _findViolations(Set<String> registered) {
  final violations = <String>[];

  // תופס: RtlIcon( ואז ליטרל FluentIcons.xxx או Icons.xxx (עם רווחים/שורות חדשות)
  final pattern = RegExp(
    r'RtlIcon\(\s*((?:FluentIcons|Icons)\.\w+)',
    multiLine: true,
  );

  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('rtl_icon.dart')) continue;

    final content = entity.readAsStringSync();
    final lines = content.split('\n');

    for (final match in pattern.allMatches(content)) {
      final iconName = match.group(1)!;
      if (registered.contains(iconName)) continue;

      // חשב מספר שורה מתוך ה-offset
      final lineNumber =
          '\n'.allMatches(content.substring(0, match.start)).length + 1;
      final relativePath = entity.path
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^.*/lib/'), 'lib/');

      // הצג גם את השורה עצמה להקשר
      final lineContent = lineNumber <= lines.length
          ? lines[lineNumber - 1].trim()
          : '';

      violations.add(
        '  $relativePath:$lineNumber\n'
        '    → RtlIcon($iconName)\n'
        '    שורה: $lineContent',
      );
    }
  }

  return violations;
}
