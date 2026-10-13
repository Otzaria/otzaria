import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/panels/app_reports_panel.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

void main() {
  AppReport report({AppReportTrigger trigger = AppReportTrigger.manual}) =>
      AppReport(
        reportId: 'r1',
        type: AppReportType.bug,
        trigger: trigger,
        title: 'כותרת ישנה',
        description: 'תיאור',
        reporterEmail: 'a@b.co',
        appVersion: '0.9.98',
        platform: 'windows',
        createdAt: DateTime.utc(2026, 9, 17),
        diagnostics: const {'k': 'v'},
        errorLog: 'log',
      );

  Future<AppReport?> pumpAndEdit(
    WidgetTester tester,
    AppReport initial,
    Future<void> Function() edit,
  ) async {
    AppReport? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AppReportEditFields(
              key: ValueKey(initial.trigger),
              report: initial,
              typeLabel: (type) => type.name,
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );
    await edit();
    await tester.pump();
    return changed;
  }

  testWidgets('עריכת שדות מחזירה דיווח מעודכן ושומרת את הצרופות', (
    tester,
  ) async {
    final changed = await pumpAndEdit(tester, report(), () async {
      await tester.enterText(
        find.byKey(const ValueKey('app-report-edit-title')),
        'כותרת חדשה',
      );
      await tester.enterText(
        find.byKey(const ValueKey('app-report-edit-email')),
        ' new@mail.co ',
      );
      await tester.tap(find.text('crash'));
    });

    expect(changed, isNotNull);
    expect(changed!.title, 'כותרת חדשה');
    expect(changed.reporterEmail, 'new@mail.co');
    expect(changed.type, AppReportType.crash);
    expect(changed.reportId, 'r1');
    expect(changed.trigger, AppReportTrigger.manual);
    expect(changed.diagnostics, {'k': 'v'});
    expect(changed.errorLog, 'log');
  });

  testWidgets('בדיווח ידני מחיקת המייל נכשלת בבדיקה; בקריסה מותרת', (
    tester,
  ) async {
    final manual = await pumpAndEdit(tester, report(), () async {
      await tester.enterText(
        find.byKey(const ValueKey('app-report-edit-email')),
        '',
      );
    });
    expect(manual!.validate(), 'reporterEmail');

    final crash = await pumpAndEdit(
      tester,
      report(trigger: AppReportTrigger.crashPrompt),
      () async {
        await tester.enterText(
          find.byKey(const ValueKey('app-report-edit-email')),
          '',
        );
      },
    );
    expect(crash!.validate(), isNull);
  });

  testWidgets('הסרת תמונה בעריכה מחזירה דיווח בלי התמונה', (tester) async {
    final withImage = report().copyWith(
      images: [
        AppReportImage(
          bytes: Uint8List(3),
          fileName: 'shot.png',
          mimeType: 'image/png',
        ),
      ],
    );
    final changed = await pumpAndEdit(tester, withImage, () async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('app-report-image-remove')),
      );
      await tester.tap(find.byKey(const ValueKey('app-report-image-remove')));
    });

    expect(changed, isNotNull);
    expect(changed!.images, isEmpty);
    expect(changed.title, 'כותרת ישנה');
  });
}
