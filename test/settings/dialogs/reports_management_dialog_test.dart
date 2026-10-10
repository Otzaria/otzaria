import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/plugins/models/plugin_report_record.dart';
import 'package:otzaria/settings/panels/reports_card.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';
import 'package:otzaria/settings/tabs/system_settings_tab.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/settings/dialogs/reports_management_dialog.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/panels/app_reports_panel.dart';
import 'package:otzaria/settings/panels/error_reports_panel.dart';
import 'package:otzaria/settings/panels/plugin_reports_panel.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial());
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) =>
      _values[key] as T? ?? defaultValue;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('otzaria_reports_dialog_');
    UserStateDatabase.instance.overridePath('${tmp.path}/state.db');
    addTearDown(() {
      UserStateDatabase.instance.close();
      tmp.deleteSync(recursive: true);
    });
  });

  Future<void> settleReports(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  Future<void> addReport(
    WidgetTester tester,
    ReportsTab tab, {
    bool sent = false,
  }) async {
    final (kind, payload) = switch (tab) {
      ReportsTab.books => (
        sent
            ? DirectErrorReportService.sentKind
            : DirectErrorReportService.pendingKind,
        DirectErrorReport.fromJson({
          'id': 'book-1',
          'subject': 'בדיקה',
          'senderEmail': 'test@example.com',
          'bookTitle': 'ספר בדיקה',
          'currentRef': 'פרק א',
          'lineNumber': 1,
          'createdAt': '2026-03-16T10:15:00Z',
          'errorDetails': 'טעות לבדיקה',
        }).toJson(),
      ),
      ReportsTab.app => (
        sent ? AppReportService.sentKind : AppReportService.pendingKind,
        AppReport(
          reportId: 'app-1',
          type: AppReportType.bug,
          trigger: AppReportTrigger.manual,
          title: 'תקלה לבדיקה',
          appVersion: '1.0',
          platform: 'macos',
          createdAt: DateTime.utc(2026),
        ).toJson(),
      ),
      ReportsTab.plugins => (
        sent ? PluginReportService.sentKind : PluginReportService.pendingKind,
        PluginReportRecord(
          reportId: 'plugin-1',
          pluginUid: 'plugin-test',
          pluginName: 'תוסף בדיקה',
          pluginVersion: '1.0',
          reportType: 'bug',
          details: 'תקלה לבדיקה',
          platform: 'macos',
          createdAt: DateTime.utc(2026),
        ).toJson(),
      ),
    };
    await tester.runAsync(() => PendingReportStore.instance.add(kind, payload));
  }

  Future<void> tapVisible(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await settleReports(tester);
  }

  Future<void> pumpDialog(WidgetTester tester, ReportsTab tab) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bloc = _FakeSettingsBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: bloc,
        child: MaterialApp(
          locale: const Locale('he', 'IL'),
          home: Scaffold(body: ReportsManagementDialog(initialTab: tab)),
        ),
      ),
    );
    await settleReports(tester);
  }

  testWidgets('opens on the requested tab, with one panel per tab', (
    tester,
  ) async {
    await pumpDialog(tester, ReportsTab.app);
    expect(find.text('הדיווחים שלך'), findsOneWidget);
    expect(find.byType(AppReportsPanel), findsOneWidget);
    expect(find.byType(ErrorReportsPanel), findsNothing);

    await tester.tap(find.text('תוספים'));
    await tester.pumpAndSettle();
    expect(find.byType(PluginReportsPanel), findsOneWidget);

    await tester.tap(find.text('טעויות בספרים'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorReportsPanel), findsOneWidget);
  });

  for (final tab in ReportsTab.values) {
    final label = switch (tab) {
      ReportsTab.books => 'טעויות בספרים',
      ReportsTab.app => 'התוכנה',
      ReportsTab.plugins => 'תוספים',
    };
    for (final action in [
      'delete',
      'clear',
      if (tab != ReportsTab.plugins) 'mark',
    ]) {
      testWidgets(
        '$action ${tab.name} updates the tab badge without switching tabs',
        (tester) async {
          await addReport(tester, tab);
          await pumpDialog(tester, tab);
          expect(find.text('$label (1)'), findsOneWidget);
          final tabView = tester.widget<TabBarView>(find.byType(TabBarView));
          await tapVisible(tester, 'ניהול דיווחים שמורים');
          switch (action) {
            case 'delete':
              await tapVisible(tester, 'מחק');
            case 'clear':
              await tapVisible(tester, 'נקה דיווחים');
              await tapVisible(tester, 'מחק');
            case 'mark':
              await tapVisible(tester, 'סמן כנשלח');
              await tapVisible(tester, 'סמן כנשלח');
          }
          final counts = await tester.runAsync(() => ReportCounts.load());
          expect(counts!.pendingOf(tab), 0);
          expect(counts.sent, action == 'mark' ? 1 : 0);
          expect(find.text('$label (1)'), findsNothing);
          expect(find.text(label), findsOneWidget);
          expect(
            tester.widget<TabBarView>(find.byType(TabBarView)),
            same(tabView),
          );
          expect(
            tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
            tab.index,
          );
        },
      );
    }
  }

  testWidgets('returning from the app report form refreshes its tab badge', (
    tester,
  ) async {
    await pumpDialog(tester, ReportsTab.app);
    expect(find.text('התוכנה (1)'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('app-reports-open-dialog')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppReportDialog), findsOneWidget);
    await addReport(tester, ReportsTab.app);
    final report = (await tester.runAsync(
      () => AppReportService().getPendingReports(),
    ))!.single;
    Navigator.of(tester.element(find.byType(AppReportDialog))).pop(
      AppReportDeliveryResult(
        status: AppReportDeliveryStatus.queued,
        report: report,
      ),
    );
    await settleReports(tester);
    expect(find.text('התוכנה (1)'), findsOneWidget);
    expect(find.text('יש כרגע 1 דיווחים שמורים בתור'), findsOneWidget);
  });

  testWidgets('cancelling the app report form leaves the tab counters alone', (
    tester,
  ) async {
    await pumpDialog(tester, ReportsTab.app);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    await tester.tap(find.byKey(const ValueKey('app-reports-open-dialog')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    Navigator.of(tester.element(find.byType(AppReportDialog))).pop();
    await settleReports(tester);
    expect(tester.widget<TabBar>(find.byType(TabBar)), same(tabBar));
  });

  testWidgets('closing the reports while the app form is open is safe', (
    tester,
  ) async {
    await pumpDialog(tester, ReportsTab.app);
    await tester.tap(find.byKey(const ValueKey('app-reports-open-dialog')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await settleReports(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sent book search opens books despite a pending app report', (
    tester,
  ) async {
    await addReport(tester, ReportsTab.books, sent: true);
    await addReport(tester, ReportsTab.app);
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bloc = _FakeSettingsBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: bloc,
        child: MaterialApp(
          locale: const Locale('he', 'IL'),
          home: const Scaffold(
            body: SingleChildScrollView(child: ReportsCard()),
          ),
        ),
      ),
    );
    await settleReports(tester);
    final entry = SystemSettingsTab.searchEntries.singleWhere(
      (entry) => entry.id == 'system.reports.sent',
    );
    await tester.runAsync(
      () => SettingsSearchRegistry.instance.scrollAndHighlight(
        entry.cardId!,
        section: entry.expandSection,
      ),
    );
    await settleReports(tester);
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
      ReportsTab.books.index,
    );
    expect(find.byType(ErrorReportsPanel), findsOneWidget);
    await tapVisible(tester, 'דיווחים שנשלחו');
    expect(find.text('ספר בדיקה'), findsOneWidget);
  });

  test('ReportCounts.load sums saved reports per kind', () async {
    final tmp = Directory.systemTemp.createTempSync('otzaria_report_counts_');
    final db = UserStateDatabase.openAt(
      '${tmp.path}${Platform.pathSeparator}user_state.db',
    );
    addTearDown(() {
      db.close();
      tmp.deleteSync(recursive: true);
    });
    final store = PendingReportStore(database: db);
    await store.add(DirectErrorReportService.pendingKind, const {});
    await store.add(DirectErrorReportService.pendingKind, const {});
    await store.add(PluginReportService.pendingKind, const {});
    await store.add(AppReportService.sentKind, const {});
    await store.add(DirectErrorReportService.sentKind, const {});

    final counts = await ReportCounts.load(reportStore: store);
    expect(counts.books, 2);
    expect(counts.app, 0);
    expect(counts.plugins, 1);
    expect(counts.sent, 2);
  });
}
