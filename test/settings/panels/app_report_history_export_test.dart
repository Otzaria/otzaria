import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/panels/app_reports_panel.dart'
    show serializeSentAppReportHistory;
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

void main() {
  test('export retains all rows but excludes private text by default (#4447)', () {
    final reports = List.generate(
      101,
      (index) => AppReport(
        reportId: 'report-$index',
        type: AppReportType.bug,
        trigger: AppReportTrigger.manual,
        title: 'Issue $index',
        description: 'PRIVATE_DESCRIPTION',
        stepsToReproduce: 'PRIVATE_STEPS',
        reporterEmail: 'private@example.com',
        errorLog: 'PRIVATE_LOG',
        diagnostics: const {'secret': 'PRIVATE_DIAGNOSTICS'},
        appVersion: 'test',
        platform: 'linux',
        createdAt: DateTime.utc(2026, 11, 18),
        issueNumber: index,
      ),
    );

    final safe = serializeSentAppReportHistory(reports, includeText: false);
    final decoded = jsonDecode(safe) as Map<String, dynamic>;
    final rows = decoded['reports'] as List<dynamic>;
    expect(rows, hasLength(101));
    expect((rows.last as Map<String, dynamic>)['issueNumber'], 100);
    for (final forbidden in [
      'PRIVATE_DESCRIPTION',
      'PRIVATE_STEPS',
      'private@example.com',
      'PRIVATE_LOG',
      'PRIVATE_DIAGNOSTICS',
    ]) {
      expect(safe, isNot(contains(forbidden)));
    }

    final full = serializeSentAppReportHistory(reports, includeText: true);
    expect(full, contains('PRIVATE_DESCRIPTION'));
    expect(full, contains('PRIVATE_STEPS'));
    expect(full, isNot(contains('private@example.com')));
    expect(full, isNot(contains('PRIVATE_DIAGNOSTICS')));
    expect(full, isNot(contains('PRIVATE_LOG')));
  });
}
