import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

void main() {
  testWidgets('דיאלוג רגיל אינו יורש את שפת ההגדרות ואת כיווניותן', (
    tester,
  ) async {
    late BuildContext dialogContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SettingsTextScope(
            language: SettingsLanguage.english,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) {
                    dialogContext = ctx;
                    return const SizedBox();
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // מתעד את ההתנהגות שבגללה נדרשת עטיפה ייעודית לדיאלוגים.
    expect(
      SettingsTextScope.languageOf(dialogContext),
      SettingsLanguage.hebrew,
      reason: 'הדיאלוג נבנה ב-Overlay ולכן נופל לברירת המחדל',
    );
  });

  testWidgets('settingsDialogBuilder מעביר לדיאלוג שפה וכיווניות', (
    tester,
  ) async {
    late BuildContext dialogContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SettingsTextScope(
            language: SettingsLanguage.english,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: settingsDialogBuilder(context, (ctx) {
                    dialogContext = ctx;
                    return const SizedBox();
                  }),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      SettingsTextScope.languageOf(dialogContext),
      SettingsLanguage.english,
    );
    expect(Directionality.of(dialogContext), TextDirection.ltr);
  });

  test('כל showDialog תחת lib/settings עטוף ב-settingsDialogBuilder', () {
    // דיאלוג נבנה ב-Overlay ולכן לא יורש את השפה; בלי העטיפה הוא מוצג
    // עברית גם כשההגדרות באנגלית — כך קרה בדיאלוג בחירת הצבע.
    final offenders = <String>[];
    final dir = Directory('lib/settings');
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      if (entity.path.endsWith('settings_dialog_scope.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('showDialog')) continue;
        // ה-builder מופיע בתוך קריאת showDialog, בשורות הסמוכות.
        final window = lines
            .sublist(i, (i + 8).clamp(0, lines.length))
            .join('\n');
        if (!window.contains('builder:')) continue;
        if (window.contains('settingsDialogBuilder')) continue;
        offenders.add('${entity.path}:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'showDialog ללא settingsDialogBuilder — הדיאלוג לא יקבל את שפת '
          'ההגדרות:\n${offenders.join('\n')}',
    );
  });

  testWidgets('מחוץ להגדרות העטיפה משאירה עברית ו-RTL', (tester) async {
    late BuildContext dialogContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: settingsDialogBuilder(context, (ctx) {
                  dialogContext = ctx;
                  return const SizedBox();
                }),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      SettingsTextScope.languageOf(dialogContext),
      SettingsLanguage.hebrew,
    );
    expect(Directionality.of(dialogContext), TextDirection.rtl);
  });
}
