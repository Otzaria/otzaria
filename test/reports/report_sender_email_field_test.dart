import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/reports/view/report_sender_email_field.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsTextScope(
          language: SettingsLanguage.hebrew,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder emailInput() => find.descendant(
    of: find.byKey(const ValueKey('report-sender-email-field')),
    matching: find.byType(TextField),
  );

  group('ReportSenderEmailField', () {
    testWidgets('כתובת לא תקינה מציגה שגיאה', (tester) async {
      final key = GlobalKey<ReportSenderEmailFieldState>();
      await pump(tester, ReportSenderEmailField(key: key));

      await tester.enterText(emailInput(), 'not-an-email');
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('נדרשת כתובת תקינה'), findsOneWidget);
    });

    testWidgets('ריקה מותרת רק כשהשדה אינו חובה', (tester) async {
      final optional = GlobalKey<ReportSenderEmailFieldState>();
      await pump(tester, ReportSenderEmailField(key: optional));
      expect(optional.currentState!.validate(), isTrue);

      final required = GlobalKey<ReportSenderEmailFieldState>();
      await pump(
        tester,
        ReportSenderEmailField(key: required, isRequired: true),
      );
      expect(required.currentState!.validate(), isFalse);
    });
  });

  group('טופס דיווח על טעות בספר', () {
    Future<List<ErrorReportAction>> pumpForm(WidgetTester tester) async {
      final actions = <ErrorReportAction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsTextScope(
            language: SettingsLanguage.hebrew,
            child: Scaffold(
              body: SizedBox(
                height: 700,
                child: RegularReportTab(
                  selectedText: 'קטע.',
                  fontSize: 18,
                  directReportTargetLabel: 'אוצריא',
                  onActionSelected: (action, _) => actions.add(action),
                  onCancel: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('report-details-field')),
          matching: find.byType(TextField),
        ),
        'פירוט',
      );
      await tester.pumpAndSettle();
      return actions;
    }

    testWidgets('השדה ממולא מראש בכתובת השמורה', (tester) async {
      await Settings.setValue(
        SettingsRepository.keyErrorReportSenderEmail,
        'me@example.com',
      );
      await pumpForm(tester);

      expect(find.text('דואר אלקטרוני לחזרה אליך'), findsOneWidget);
      expect(
        tester.widget<TextField>(emailInput()).controller!.text,
        'me@example.com',
      );
    });

    testWidgets('שמירה לשליחה מאוחרת שומרת את הכתובת שהוקלדה', (tester) async {
      await Settings.setValue(SettingsRepository.keyErrorReportSenderEmail, '');
      final actions = await pumpForm(tester);

      final save = find.text('שמור לשליחה מאוחרת');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(actions, isEmpty, reason: 'בלי כתובת אין שליחה ואין תור');
      expect(find.text('נדרשת כתובת תקינה'), findsOneWidget);

      await tester.enterText(emailInput(), 'new@example.com');
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(actions, [ErrorReportAction.saveForLater]);
      expect(
        Settings.getValue<String>(SettingsRepository.keyErrorReportSenderEmail),
        'new@example.com',
      );
    });
  });
}
