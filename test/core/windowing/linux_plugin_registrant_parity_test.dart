import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// שומר על התאמה בין טבלת התוספים של חלון משני ב-Linux
/// (`kSecondaryWindowPlugins` ב-`linux/runner/multi_window.cc`) לקובץ
/// המיוצר `linux/flutter/generated_plugin_registrant.cc`.
///
/// אותה סיבה כמו ב-`plugin_registrant_parity_test.dart` של Windows: תוסף
/// חדש נכנס לקובץ המיוצר בלבד, והחלון המשני יקבל `MissingPluginException`
/// בלי שום שגיאת קומפילציה. הרשימה מותרת להכיל `nullptr` (תוסף שמדולג
/// במכוון), אבל **השם** חייב להופיע — כך הדילוג הוא החלטה גלויה.
void main() {
  List<String> namesInGenerated(String source) => RegExp(
    r'fl_plugin_registry_get_registrar_for_plugin\(registry, "([^"]+)"\)',
  ).allMatches(source).map((m) => m.group(1)!).toList();

  List<String> namesInRunnerTable(String source) {
    final table = RegExp(
      r'kSecondaryWindowPlugins\[\] = \{(.*?)\n\};',
      dotAll: true,
    ).firstMatch(source);
    expect(
      table,
      isNotNull,
      reason:
          'לא נמצאה הטבלה kSecondaryWindowPlugins ב-multi_window.cc — אם '
          'שונתה או הוסרה, יש לעדכן את השומר הזה יחד איתה.',
    );
    return RegExp(
      r'\{"([^"]+)"',
    ).allMatches(table!.group(1)!).map((m) => m.group(1)!).toList();
  }

  final generatedFile = File('linux/flutter/generated_plugin_registrant.cc');
  final runnerFile = File('linux/runner/multi_window.cc');

  test('אותם תוספים, באותו סדר', () {
    if (!generatedFile.existsSync()) {
      // הקובץ נוצר ב-`flutter pub get` ואינו במאגר; עץ בלעדיו — אין מה לבדוק.
      return;
    }
    final generated = namesInGenerated(generatedFile.readAsStringSync());
    final runner = namesInRunnerTable(runnerFile.readAsStringSync());
    // בלי הבדיקה הזאת, regex שנשבר היה הופך את השומר לירוק-תמיד.
    expect(generated, isNotEmpty);
    expect(runner, isNotEmpty);
    expect(
      runner,
      generated,
      reason:
          'טבלת התוספים של חלון משני ב-Linux אינה תואמת לקובץ המיוצר. יש '
          'לעדכן את kSecondaryWindowPlugins ב-linux/runner/multi_window.cc.',
    );
  });

  test('printing מדולג בחלון משני', () {
    // ⚠️ `printing_plugin.cc` מחזיק ערוץ יחיד ב-namespace scope; רישום שני
    // דורס אותו וכל קולבק הדפסה של החלון הראשון מנותב למנוע האחרון.
    final source = runnerFile.readAsStringSync();
    expect(source, contains('{"PrintingPlugin", nullptr}'));
  });
}
