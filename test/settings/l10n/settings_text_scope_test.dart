import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

/// עוטף כמו מסך ההגדרות: כיווניות ושפה מקומיות בלבד.
Widget _settingsSubtree({
  required SettingsLanguage language,
  required Widget child,
}) => Directionality(
  textDirection: language.textDirection,
  child: SettingsTextScope(language: language, child: child),
);

void main() {
  testWidgets('בעברית מוצג המקור והכיוון RTL', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _settingsSubtree(
          language: SettingsLanguage.hebrew,
          child: Builder(
            builder: (context) => Text(context.settingsText('הגדרות')),
          ),
        ),
      ),
    );

    expect(find.text('הגדרות'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('הגדרות'))),
      TextDirection.rtl,
    );
  });

  testWidgets('באנגלית מוצג התרגום והכיוון LTR', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _settingsSubtree(
          language: SettingsLanguage.english,
          child: Builder(
            builder: (context) => Text(context.settingsText('הגדרות')),
          ),
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('הגדרות'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text('Settings'))),
      TextDirection.ltr,
    );
  });

  testWidgets('החלפת שפה מתעדכנת בלי בנייה מחדש של המסך', (tester) async {
    var language = SettingsLanguage.hebrew;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => _settingsSubtree(
            language: language,
            child: Builder(
              builder: (innerContext) => Column(
                children: [
                  Text(innerContext.settingsText('הגדרות')),
                  TextButton(
                    onPressed: () => setState(
                      () => language = SettingsLanguage.english,
                    ),
                    child: const Text('switch'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('הגדרות'), findsOneWidget);

    await tester.tap(find.text('switch'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('הגדרות'), findsNothing);
  });

  testWidgets('מחוץ ל-scope נשארת עברית — שאר האפליקציה אינה מושפעת', (
    tester,
  ) async {
    late BuildContext outsideContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              _settingsSubtree(
                language: SettingsLanguage.english,
                child: Builder(
                  builder: (context) => Text(context.settingsText('הגדרות')),
                ),
              ),
              Builder(
                builder: (context) {
                  outsideContext = context;
                  return Text(context.settingsText('הגדרות'));
                },
              ),
            ],
          ),
        ),
      ),
    );

    // בתוך ה-scope אנגלית, ומחוצה לו עברית ו-RTL באותו עץ.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('הגדרות'), findsOneWidget);
    expect(Directionality.of(outsideContext), TextDirection.rtl);
    expect(
      SettingsTextScope.languageOf(outsideContext),
      SettingsLanguage.hebrew,
    );
  });

  testWidgets('RtlIcon מתהפך לפי הכיווניות המקומית של ההגדרות', (tester) async {
    late TextDirection insideDirection;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: _settingsSubtree(
            language: SettingsLanguage.english,
            child: Builder(
              builder: (context) {
                insideDirection = Directionality.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    // RtlIcon נשען על Directionality.of, ולכן די לוודא שהכיווניות המקומית
    // גוברת על ה-RTL הגלובלי.
    expect(insideDirection, TextDirection.ltr);
  });
}
