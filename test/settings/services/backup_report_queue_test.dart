import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/backup/backup_report_queue.dart';

void main() {
  group('BackupReportQueue.reportList', () {
    test('keeps maps and normalizes their keys', () {
      final result = BackupReportQueue.reportList([
        {'id': 'one', 'value': 1},
        'not a report',
        {'reportId': 'two'},
      ]);
      expect(result, [
        {'id': 'one', 'value': 1},
        {'reportId': 'two'},
      ]);
    });

    test('returns an empty list for non-list input', () {
      expect(BackupReportQueue.reportList(null), isEmpty);
      expect(BackupReportQueue.reportList({'id': 'one'}), isEmpty);
    });
  });

  group('BackupReportQueue identifiers and timestamps', () {
    test('accepts both report identifier fields', () {
      expect(BackupReportQueue.reportId({'id': 12}), '12');
      expect(BackupReportQueue.reportId({'reportId': 'plugin-1'}), 'plugin-1');
      expect(BackupReportQueue.reportId({}), isNull);
    });

    test('uses epoch for a missing or invalid timestamp', () {
      expect(
        BackupReportQueue.reportTime({}),
        DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(
        BackupReportQueue.reportTime({'createdAt': 'not-a-date'}),
        DateTime.fromMillisecondsSinceEpoch(0),
      );
    });

    test('reads valid timestamps', () {
      final timestamp = DateTime.utc(2026, 11, 18, 10);
      expect(
        BackupReportQueue.reportTime({
          'createdAt': timestamp.toIso8601String(),
        }),
        timestamp,
      );
    });

    test('accepts only integer sent totals', () {
      expect(BackupReportQueue.sentTotal(4), 4);
      expect(BackupReportQueue.sentTotal('4'), 0);
      expect(BackupReportQueue.sentTotal(null), 0);
    });
  });

  group('BackupReportQueue.merge', () {
    test('local version wins when IDs overlap', () {
      final local = [
        {'id': 'same', 'value': 'local'},
      ];
      final backedUp = [
        {'id': 'same', 'value': 'backup'},
        {'id': 'new', 'value': 'backup'},
      ];

      expect(BackupReportQueue.merge(local, backedUp), [
        {'id': 'same', 'value': 'local'},
        {'id': 'new', 'value': 'backup'},
      ]);
    });

    test('keeps reports without IDs because they cannot be deduplicated', () {
      final local = [
        {'message': 'local without id'},
      ];
      final backedUp = [
        {'message': 'backup without id'},
      ];

      expect(
        BackupReportQueue.merge(local, backedUp),
        [...local, ...backedUp],
      );
    });

    test('supports reportId used by plugin and app reports', () {
      expect(
        BackupReportQueue.merge(
          [
            {'reportId': 'same', 'value': 'local'},
          ],
          [
            {'reportId': 'same', 'value': 'backup'},
            {'reportId': 'new'},
          ],
        ),
        [
          {'reportId': 'same', 'value': 'local'},
          {'reportId': 'new'},
        ],
      );
    });
  });
}
