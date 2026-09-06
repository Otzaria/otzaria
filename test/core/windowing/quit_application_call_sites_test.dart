import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `AppWindowController.quitApplication` מסיים את **התוכנה**, לא את החלון:
/// ב-Windows הוא `PostQuitMessage(0)` בלבד, לולאת ההודעות של התהליך יוצאת,
/// ו-`~FlutterWindow` הורס את המנוע בעוד Dart רץ עליו.
///
/// קריאה שגויה אחת אליו — ב-hook סגירת החלון של מסלול העדכונים — הפילה את
/// התהליך בכל יציאה. היא שרדה את כל הסוויטה ואת כל ה-QA משום שהעוטף
/// שהתקין אותה מדולג תחת `kDebugMode`, כלומר הבאג היה נגיש ב-release בלבד.
///
/// הבדיקה סורקת מקור ולא מריצה קוד: המסלול עצמו מסתיים ביציאת התהליך ואינו
/// ניתן להרצה בבדיקה, ולכן נעילת אתרי הקריאה היא ההגנה היחידה שאפשרית.
void main() {
  late Map<String, List<String>> sources;

  setUpAll(() {
    sources = {
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart'))
          file.path.replaceAll(r'\', '/'): _codeLines(file),
    };
    expect(
      sources,
      isNotEmpty,
      reason: 'הסריקה חייבת לרוץ משורש החבילה, אחרת היא ירוקה על ריק',
    );
  });

  Set<String> filesCalling(String call) => {
    for (final entry in sources.entries)
      if (entry.value.any((line) => line.contains(call))) entry.key,
  };

  test('רק AppWindowListener קורא ל-quitApplication', () {
    expect(
      filesCalling('.quitApplication('),
      {'lib/core/window_listener.dart'},
      reason:
          'סגירת חלון בודד היא MultiWindowService.closeSelf, ויציאת התהליך '
          'ב-Windows היא forceTerminate של ה-runner',
    );
  });

  test('windowManager.destroy נעטף במקום אחד בלבד', () {
    expect(
      filesCalling('windowManager.destroy('),
      {'lib/core/windowing/window_manager_app_window_controller.dart'},
      reason:
          'קריאה ישירה לספרייה עוקפת את השם ואת האזהרה שב-AppWindowController',
    );
  });
}

/// שורות הקוד בלבד. השמות האלה מוזכרים בהערות במכוון — שם הם תיעוד, לא
/// קריאה — ולכן הערות שורה יוצאות מהסריקה.
List<String> _codeLines(File file) => file
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .toList();
