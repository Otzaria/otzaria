import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/app_report/view/widgets/app_report_preview_section.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/panels/app_reports_panel.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../app_report_test_fakes.dart';

final _long = List.generate(
  30,
  (i) => 'שורה $i בתיאור ארוך של התקלה, כמו שמדביקים מהלוג',
).join('\n');

AppReport _report() => AppReport(
  reportId: 'r1',
  type: AppReportType.bug,
  trigger: AppReportTrigger.manual,
  title: 'כותרת',
  description: _long,
  stepsToReproduce: _long,
  reporterEmail: 'a@b.co',
  appVersion: '0.9.98',
  platform: 'windows',
  createdAt: DateTime.utc(2026, 9, 17),
  diagnostics: const {'k': 'v'},
  errorLog: 'log',
);

const _sizes = [Size(800, 500), Size(360, 640)];

/// הגלילה של גוף הדיאלוג: ה-Scrollable של [PanelScrollableContent].
ScrollPosition _bodyScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(PanelScrollableContent),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// גלגלת מעל החלק הגלוי של [over] (שדה ארוך גבוה מהמסך).
Future<void> _wheel(WidgetTester tester, Finder over) async {
  await tester.ensureVisible(over);
  await tester.pumpAndSettle();
  final visible = tester
      .getRect(over)
      .intersect(tester.getRect(find.byType(PanelScrollableContent)));
  expect(visible.isEmpty, isFalse);
  final body = _bodyScroll(tester);
  final beforeWheel = body.pixels;
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(visible.center));
  await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
  await tester.pumpAndSettle();
  expect(body.pixels, greaterThan(beforeWheel));
}

/// כל הכפתור בתוך המסך, וגם אחרי הגלילה הוא באותו מקום (קבוע בתחתית).
void _expectInsideScreen(WidgetTester tester, Finder button) {
  final screen = Offset.zero & tester.view.physicalSize;
  final rect = tester.getRect(button);
  expect(screen.contains(rect.topLeft), isTrue, reason: '$rect');
  expect(screen.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final size in _sizes) {
    testWidgets('טופס הדיווח בטקסט ארוך, $size: הגוף גולל והכפתורים קבועים '
        '(#3448)', (tester) async {
      await _setSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAppReportDialog(
                    context,
                    createBloc: () => AppReportBloc(
                      trigger: AppReportTrigger.manual,
                      service: FakeAppReportService(),
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
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final description = find.byKey(const ValueKey('app-report-description'));
      await tester.enterText(description, _long);
      await tester.enterText(
        find.byKey(const ValueKey('app-report-steps')),
        _long,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'בלי גלישה');

      // פס הגלילה גלוי מההתחלה, כי התוכן החתוך לא נראה לעין.
      expect(
        tester
            .widget<PanelScrollableContent>(
              find.byType(PanelScrollableContent),
            )
            .thumbVisibility,
        isTrue,
      );

      // השדות גדלים עם הטקסט ולא גוללים בעצמם, ולכן הגלגלת מעל שדה גוללת
      // את הטופס.
      final body = _bodyScroll(tester);
      body.jumpTo(0);
      await tester.pumpAndSettle();
      final send = find.byKey(const ValueKey('app-report-send'));
      _expectInsideScreen(tester, send);
      final sendRect = tester.getRect(send);
      await _wheel(tester, description);
      expect(body.pixels, greaterThan(0));

      // עד הסוף: מה שבתחתית הטופס מגיע לתצוגה, והכפתורים לא זזו.
      body.jumpTo(body.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(AppReportPreviewSection)).bottom,
        lessThan(sendRect.top),
        reason: 'סוף הטופס מעל הכפתורים',
      );
      expect(tester.getRect(send), sendRect);
      for (final key in [
        'app-report-discard',
        'app-report-save-draft',
        'app-report-queue',
        'app-report-send',
      ]) {
        _expectInsideScreen(tester, find.byKey(ValueKey(key)));
      }

      UiSnack.hide();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('עריכת דיווח שמור בטקסט ארוך, $size: הגוף גולל והכפתורים '
        'קבועים (#3448)', (tester) async {
      await _setSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAppReportEditDialog(
                    context,
                    _report(),
                    typeLabel: (type) => type.name,
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
      expect(tester.takeException(), isNull, reason: 'בלי גלישה');

      final body = _bodyScroll(tester);
      expect(body.maxScrollExtent, greaterThan(0));
      expect(
        tester
            .widget<PanelScrollableContent>(
              find.byType(PanelScrollableContent),
            )
            .thumbVisibility,
        isTrue,
      );
      final save = find.text('שמור');
      _expectInsideScreen(tester, save);
      final saveRect = tester.getRect(save);

      await _wheel(
        tester,
        find.byKey(const ValueKey('app-report-edit-description')),
      );
      expect(body.pixels, greaterThan(0));

      body.jumpTo(body.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('app-report-edit-email')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getRect(save), saveRect);
      _expectInsideScreen(tester, find.text('ביטול'));
    });
  }
}
