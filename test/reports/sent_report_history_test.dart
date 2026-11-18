import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/reports/repository/sent_report_history.dart';
import 'package:otzaria/services/sent_reports_counter.dart';

void main() {
  test('היסטוריה מוגבלת שומרת דחיות בלי לספור אותן', () async {
    final temp = await Directory.systemTemp.createTemp('sent_report_history_');
    final db = UserStateDatabase.openAt('${temp.path}/user_state.db');
    addTearDown(() async {
      db.close();
      await temp.delete(recursive: true);
    });
    const kind = 'error_reports_queue/sent_reports';
    final store = PendingReportStore(database: db);
    final history = SentReportHistory<Map<String, dynamic>>(
      store: store,
      counter: SentReportsCounter.inMemory(),
      boxName: 'error_reports_queue',
      kind: kind,
      idField: 'id',
      limit: 2,
      fromJson: (json) => json,
      rejectionField: 'rejectionReason',
    );

    await store.add(kind, {'id': 'legacy'});
    await store.add(kind, {'id': 'legacy-rejected', 'rejectionReason': '422'});
    expect(await history.total(), 1);

    await history.save('accepted', {'id': 'accepted'});
    expect((await history.list()).map((row) => row['id']), [
      'accepted',
      'legacy-rejected',
    ]);
    expect(await history.total(), 2);

    await history.save('accepted', {'id': 'accepted', 'subject': 'updated'});
    expect(await history.find('accepted'), {
      'id': 'accepted',
      'subject': 'updated',
    });
    expect(await history.total(), 2);

    await history.save('rejected', {
      'id': 'rejected',
      'rejectionReason': '400',
    }, countAsSent: false);
    expect(await history.contains('rejected'), isTrue);
    expect(await history.total(), 2);

    await history.delete('accepted');
    expect(await history.contains('accepted'), isFalse);
    expect(await history.total(), 2);

    await history.clear();
    expect(await history.list(), isEmpty);
    expect(await history.total(), 0);
  });
}
