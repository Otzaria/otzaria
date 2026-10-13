import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// שירות מזויף: רושם את הדיווח שנשלח ומחזיר תוצאה קבועה.
class FakeAppReportService implements AppReportService {
  FakeAppReportService({this.respond, this.draft});

  final AppReportDeliveryResult Function(AppReport)? respond;
  final List<AppReport> sent = [];
  AppReportDraft? draft;

  @override
  Future<AppReportDraft?> loadDraft() async => draft;

  @override
  Future<void> saveDraft(AppReportDraft value) async => draft = value;

  @override
  Future<void> deleteDraft() async => draft = null;

  @override
  Future<AppReportDeliveryResult> send(AppReport report) async {
    sent.add(report);
    return respond?.call(report) ??
        AppReportDeliveryResult(
          status: AppReportDeliveryStatus.sent,
          report: report.copyWith(issueNumber: 42),
        );
  }

  @override
  Future<List<AppReport>> getPendingReports() async => const [];

  @override
  Future<List<AppReport>> getSentReports() async => const [];

  @override
  Future<int> getSentReportsTotal() async => 0;

  @override
  Future<int> getPendingReportsCount() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// אוסף מזויף: מחזיר צרופות קבועות, או זורק כשמבקשים לדמות כשל.
class FakeAppReportCollector implements AppReportCollector {
  FakeAppReportCollector({
    this.diagnostics = const {'appInfo': 'x'},
    this.errorLog = '=== Error 2026-09-17T00:00:00Z ===\nException: boom',
    this.fail = false,
  });

  final Map<String, dynamic> diagnostics;
  final String errorLog;
  final bool fail;

  @override
  Future<AppReportAttachments> collect() async {
    if (fail) throw StateError('collect failed');
    return AppReportAttachments(diagnostics: diagnostics, errorLog: errorLog);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
