import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import 'contract_harness.dart';

/// כפתור הרסני: אדום מלא בדיאלוג, אדום רך על מסך הגדרות (DESIGN_SYSTEM.md,
/// כפתורים; הערת בעל הפרויקט, 4.11.2026).
void main() {
  (Color?, Color?) colorsOf(WidgetTester tester, String label) {
    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    final text = tester.widget<Text>(find.text(label));
    final style = DefaultTextStyle.of(tester.element(find.text(label))).style;
    return (material.color, text.style?.color ?? style.color);
  }

  for (final brightness in Brightness.values) {
    testWidgets('warningSoft: errorContainer ו-onErrorContainer, '
        '${brightness.name}', (tester) async {
      await pumpInApp(
        tester,
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ActionButton.warningSoft(text: 'נקה הכל', onPressed: () {}),
              ActionButton.warning(text: 'מחק הכל', onPressed: () {}),
            ],
          ),
        ),
        brightness: brightness,
      );
      final cs = Theme.of(tester.element(find.text('נקה הכל'))).colorScheme;
      expect(colorsOf(tester, 'נקה הכל'), (
        cs.errorContainer,
        cs.onErrorContainer,
      ));
      expect(colorsOf(tester, 'מחק הכל'), (cs.error, cs.onError));
    });
  }

  testWidgets('warningSoft בטעינה: מחוון בצבע onErrorContainer', (
    tester,
  ) async {
    await pumpInApp(
      tester,
      Center(
        child: ActionButton.warningSoft(
          text: 'בטל ייבוא',
          isLoading: true,
          onPressed: () {},
        ),
      ),
    );
    final cs = Theme.of(
      tester.element(find.byType(CircularProgressIndicator)),
    ).colorScheme;
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      cs.onErrorContainer,
    );
  });

  test('מסכי ההגדרות לא משתמשים ב-ActionButton.warning (רק בדיאלוגים)', () {
    final files = [
      for (final dir in ['lib/settings/tabs', 'lib/settings/panels'])
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      File('lib/text_book/view/page_shape/page_shape_settings_panel.dart'),
    ];
    expect(files, hasLength(greaterThan(10)), reason: 'הסורק לא מצא קבצים');
    final offenders = [
      for (final f in files)
        if (_usesFullWarning(f.readAsStringSync()))
          f.path.replaceAll(r'\', '/'),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'על מסך הגדרות כפתור הרסני הוא ActionButton.warningSoft. '
          'האדום המלא שמור לכפתור האישור בדיאלוג (lib/settings/dialogs).',
    );
  });

  test('הסורק: warning נתפס, warningSoft לא', () {
    expect(_usesFullWarning('ActionButton.warning(text: x)'), isTrue);
    expect(_usesFullWarning('const ActionButton.warning(text: x)'), isTrue);
    expect(_usesFullWarning('ActionButton.warningSoft(text: x)'), isFalse);
    // הכפתור המלא קיים בדיאלוגים של ההגדרות, ולכן הסורק מוצא בהם משהו.
    expect(
      _usesFullWarning(
        File(
          'lib/settings/dialogs/hidden_books_list_dialog.dart',
        ).readAsStringSync(),
      ),
      isTrue,
    );
  });
}

bool _usesFullWarning(String source) =>
    source.contains('ActionButton.warning(');
