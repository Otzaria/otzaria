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
