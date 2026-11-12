import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_zman_alert_dialog.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';

void main() {
  for (final initialMinutesBefore in [1505, -60]) {
    for (final editHours in [false, true]) {
      testWidgets('התראה שמורה $initialMinutesBefore דקות נשמרת ($editHours)', (
        tester,
      ) async {
        final preference = ZmanAlertPreference.fromJson({
          'minutesBefore': initialMinutesBefore,
          'displayName': 'זמן',
        })!;
        ZmanAlertDialogResult? result;
        await _openDialog(
          tester,
          (value) => result = value,
          initialMinutesBefore: preference.minutesBefore,
        );
        expect(
          tester.widget<TextField>(_field(0)).controller!.text,
          '${initialMinutesBefore ~/ 60}',
        );
        expect(
          tester.widget<TextField>(_field(1)).controller!.text,
          '${initialMinutesBefore % 60}',
        );
        if (editHours) {
          await tester.enterText(
            _field(0),
            initialMinutesBefore > 0 ? '23' : '0',
          );
          await tester.pump();
        }
        await tester.tap(find.text('הפעל'));
        await tester.pumpAndSettle();

        expect(
          result!.minutesBefore,
          editHours
              ? (initialMinutesBefore > 0 ? 1385 : 0)
              : initialMinutesBefore,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'editing an alert spinbox does not rebuild its sibling or dialog',
    (tester) async {
      await _openDialog(tester, (_) {});

      final boxes = find.byType(SpinBox);
      expect(boxes, findsNWidgets(2));
      final dialog = tester.widget<AppDialogFrame>(find.byType(AppDialogFrame));
      final minutes = tester.widget<SpinBox>(boxes.last);

      await tester.enterText(_field(0), '2');
      await tester.pump();

      expect(tester.widget<SpinBox>(boxes.last), same(minutes));
      expect(
        tester.widget<AppDialogFrame>(find.byType(AppDialogFrame)),
        same(dialog),
      );

      final hours = tester.widget<SpinBox>(boxes.first);
      await tester.enterText(_field(1), '7');
      await tester.pump();

      expect(tester.widget<SpinBox>(boxes.first), same(hours));
      expect(
        tester.widget<AppDialogFrame>(find.byType(AppDialogFrame)),
        same(dialog),
      );
    },
  );

  testWidgets('alert dialog submits the latest hours and minutes', (
    tester,
  ) async {
    ZmanAlertDialogResult? result;
    await _openDialog(tester, (value) => result = value);

    await tester.enterText(_field(0), '2');
    await tester.pump();
    await tester.enterText(_field(1), '7');
    await tester.pump();
    await tester.tap(find.text('הפעל'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.minutesBefore, 127);
    expect(result!.cancelAlert, isFalse);
  });

  for (final (name, index, expectedMinutes) in [
    ('hours', 0, 5),
    ('minutes', 1, 60),
  ]) {
    testWidgets('clearing $name stays zero after tabbing away and saving', (
      tester,
    ) async {
      ZmanAlertDialogResult? result;
      await _openDialog(tester, (value) => result = value);

      final field = _field(index);
      await tester.enterText(field, '');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(field);
      expect(textField.focusNode!.hasFocus, isFalse);
      final textAfterBlur = textField.controller!.text;

      await tester.tap(find.text('הפעל'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.minutesBefore, expectedMinutes);
      expect(result!.cancelAlert, isFalse);
      expect(textAfterBlur, '0');
    });

    testWidgets('clearing $name is saved without first moving focus', (
      tester,
    ) async {
      ZmanAlertDialogResult? result;
      await _openDialog(tester, (value) => result = value);

      await tester.enterText(_field(index), '');
      await tester.tap(find.text('הפעל'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.minutesBefore, expectedMinutes);
      expect(result!.cancelAlert, isFalse);
    });

    testWidgets('clearing and replacing $name saves the new number', (
      tester,
    ) async {
      ZmanAlertDialogResult? result;
      await _openDialog(tester, (value) => result = value);

      await tester.enterText(_field(index), '');
      await tester.pump();
      final editing = tester.widget<TextField>(_field(index)).controller!.value;
      final caret = editing.selection.start;
      tester.testTextInput.updateEditingValue(
        editing.copyWith(
          text: editing.text.replaceRange(caret, editing.selection.end, '2'),
          selection: TextSelection.collapsed(offset: caret + 1),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.tap(find.text('הפעל'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.minutesBefore, index == 0 ? 125 : 62);
    });
  }
}

Finder _field(int index) => find.descendant(
  of: find.byType(SpinBox).at(index),
  matching: find.byType(TextField),
);

Future<void> _openDialog(
  WidgetTester tester,
  ValueChanged<ZmanAlertDialogResult?> onResult, {
  int initialMinutesBefore = 65,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              onResult(
                await showZmanAlertDialog(
                  context,
                  zmanName: 'זמן',
                  timeLabel: '12:00',
                  initialMinutesBefore: initialMinutesBefore,
                  isEnabled: false,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
