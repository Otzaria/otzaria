import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ניסוחי דיאלוגים (הכרעת הבעלים, 18.11): כותרת של מחיקה או הסרה היא שאלה
/// ("למחוק את X?"), ו"סגור" בדיאלוג שיש בו רק סגירה הוא כפתור שקט.
void main() {
  final sources = [
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ];

  test('אין כותרת דיאלוג בשם פעולה: "מחיקת X" או "הסרת X"', () {
    // `title:` ולא `subtitle:`/`tooltip:`; כותרת שפותחת בשם הפעולה.
    final actionName = RegExp(
      "(?<![A-Za-z])title:[^\\n]*['\"](מחיקת|הסרת|מחיקה|הסרה) ",
    );
    final offenders = <String>[];
    for (final file in sources) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (actionName.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('"סגור" בדיאלוג אינו כפתור recommended', () {
    final recommendedClose = RegExp(
      "ActionButton\\.recommended\\((?:(?!ActionButton)[\\s\\S]){0,160}?['\"]סגור['\"]",
    );
    final offenders = [
      for (final file in sources)
        if (recommendedClose.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('כותרת המידע על האפליקציה: "סגור" ולא "סגירה"', () {
    final source = File(
      'lib/core/info/view/app_info_dialog.dart',
    ).readAsStringSync();
    expect(source, isNot(contains("confirmText: 'סגירה'")));
    expect(source, contains("confirmText: 'סגור'"));
  });
}
