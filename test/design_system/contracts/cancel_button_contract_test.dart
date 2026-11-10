import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DD-09 A: כפתור "ביטול" הוא ActionButton.neutral, לא ghost, בכל מקום.
void main() {
  test('אין ActionButton.ghost עם הטקסט "ביטול" ב-lib', () {
    final ghostCancel = RegExp(
      r"ActionButton\.ghost\(\s*(?:key:[^\n]*\n\s*)?text:[^\n]*'ביטול'",
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (ghostCancel.hasMatch(file.readAsStringSync())) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
