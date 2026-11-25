import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../app_report_test_fakes.dart';

/// שירות שהשליחה בו נתקעת עד שהבדיקה משחררת אותה.
class _SlowAppReportService extends FakeAppReportService {
  final release = Completer<void>();

  @override
  Future<AppReportDeliveryResult> send(AppReport report) async {
    sent.add(report);
    await release.future;
    return AppReportDeliveryResult(
      status: AppReportDeliveryStatus.sent,
      report: report.copyWith(issueNumber: 42),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    ShortcutHelper.isMacForTesting = false;
    await Settings.setValue<String>(
      SettingsRepository.keySettingsLanguage,
      'he',
    );
    await Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      '',
    );
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
  });

  tearDown(() async {
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
    ShortcutHelper.isMacForTesting = null;
  });

  late FakeAppReportService service;

  Future<void> pumpDialog(
    WidgetTester tester, {
    FakeAppReportService? withService,
  }) async {
    service = withService ?? FakeAppReportService();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SettingsTextScope(
          language: SettingsLanguage.hebrew,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAppReportDialog(
                    context,
                    createBloc: () => AppReportBloc(
                      trigger: AppReportTrigger.manual,
                      service: service,
                      collector: FakeAppReportCollector(),
                      redactor: AppReportRedactor(environment: const {}),
                      appVersion: '0.9.98',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// ממלא את שדות החובה ומשאיר את הפוקוס בשדה התיאור הרב־שורתי.
  Future<void> fillAndFocusDescription(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('app-report-title')),
      'כותרת',
    );
    await tester.enterText(
      find.byKey(const ValueKey('app-report-email')),
      'me@x.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('app-report-description')),
      'תיאור',
    );
    await tester.pump();
  }

  Future<void> ctrlEnter(WidgetTester tester) async {
    ShortcutHelper.isMacForTesting = false;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> cleanUp(WidgetTester tester) async {
    UiSnack.hide();
    await tester.pump(const Duration(seconds: 5));
  }

  group('Ctrl+Enter sends the app report (issue #4439)', () {
    testWidgets('Ctrl+Enter בשדה התיאור שולח את הדיווח', (tester) async {
      await pumpDialog(tester);
      await fillAndFocusDescription(tester);

      await ctrlEnter(tester);

      expect(service.sent, hasLength(1));
      expect(service.queued, isEmpty);
      expect(service.sent.single.title, 'כותרת');
      expect(find.byType(AppReportDialog), findsNothing);
      await cleanUp(tester);
    });

    testWidgets('ב-macOS Cmd+Enter שולח את הדיווח', (tester) async {
      ShortcutHelper.isMacForTesting = true;
      await pumpDialog(tester);
      await fillAndFocusDescription(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.sent, hasLength(1));
      expect(service.queued, isEmpty);
      await cleanUp(tester);
    });

    testWidgets('במצב מנותק Ctrl+Enter שומר בתור, כמו הכפתור', (
      tester,
    ) async {
      await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
      await pumpDialog(tester);
      await fillAndFocusDescription(tester);

      await ctrlEnter(tester);

      expect(service.sent, isEmpty);
      expect(service.queued, hasLength(1));
      await cleanUp(tester);
    });

    testWidgets('בזמן שליחה Ctrl+Enter נוסף לא שולח שוב', (tester) async {
      final slow = _SlowAppReportService();
      await pumpDialog(tester, withService: slow);
      await fillAndFocusDescription(tester);

      await ctrlEnter(tester);
      expect(slow.sent, hasLength(1));
      await ctrlEnter(tester);
      expect(slow.sent, hasLength(1));

      slow.release.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await cleanUp(tester);
    });

    testWidgets('Enter רגיל בשדה התיאור לא שולח (DD-08)', (tester) async {
      await pumpDialog(tester);
      await fillAndFocusDescription(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(service.sent, isEmpty);
      expect(service.queued, isEmpty);
      expect(find.byType(AppReportDialog), findsOneWidget);
    });

    testWidgets('כפתור השליחה מציג את הקיצור ב-tooltip', (tester) async {
      await pumpDialog(tester);
      final button = tester.widget<ActionButton>(
        find.byKey(const ValueKey('app-report-send')),
      );
      expect(
        button.tooltip,
        ShortcutHelper.formatShortcutForDisplay('ctrl+enter'),
      );
    });
  });
}
