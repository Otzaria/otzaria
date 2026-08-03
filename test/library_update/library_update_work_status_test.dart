import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library_update/library_update_work_status.dart';
import 'package:otzaria/work_status/work_status_item.dart';

void main() {
  WorkStatusItem? item(LibraryUpdateState state, {VoidCallback? onRetry}) =>
      libraryUpdateWorkStatusItem(state, onRetry: onRetry ?? () {});

  group('libraryUpdateWorkStatusItem', () {
    test('מנותק אינו יוצר פריט חיווי כלל — זו הרגרסיה שהתלוננו עליה', () {
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.disconnected,
            message: 'אין חיבור לאינטרנט',
          ),
        ),
        isNull,
      );
    });

    test('שגיאה אמיתית עדיין מוצגת ככשל עם ניסיון חוזר', () {
      final result = item(
        const LibraryUpdateState(
          status: LibraryUpdateStatus.error,
          message: 'שגיאה בבדיקת עדכונים',
        ),
      )!;

      expect(result.kind, WorkStatusKind.failed);
      expect(result.message, 'שגיאה בבדיקת עדכונים');
      expect(result.detail, 'לחץ לניסיון חוזר');
      expect(result.onTap, isNotNull);
    });

    test('הלחיצה על הכשל מפעילה את הניסיון החוזר שהוזרק', () {
      var retries = 0;
      final result = item(
        const LibraryUpdateState(status: LibraryUpdateStatus.error),
        onRetry: () => retries++,
      )!;

      result.onTap!();

      expect(retries, 1);
    });

    test('מצבי עבודה יוצרים פריט רץ עם המזהה הקבוע', () {
      for (final status in [
        LibraryUpdateStatus.checking,
        LibraryUpdateStatus.downloading,
        LibraryUpdateStatus.applying,
        LibraryUpdateStatus.refreshing,
      ]) {
        final result = item(
          LibraryUpdateState(status: status, message: 'עובד'),
        )!;

        expect(result.kind, WorkStatusKind.running, reason: '$status');
        expect(result.id, kLibraryUpdateWorkStatusId);
      }
    });

    test('מצבי מנוחה אינם יוצרים פריט', () {
      for (final status in [
        LibraryUpdateStatus.idle,
        LibraryUpdateStatus.completed,
        LibraryUpdateStatus.needsFullConfirmation,
        LibraryUpdateStatus.blocked,
        LibraryUpdateStatus.disconnected,
      ]) {
        expect(
          item(LibraryUpdateState(status: status)),
          isNull,
          reason: '$status',
        );
      }
    });

    test('התקדמות ההורדה מחושבת מהבתים, ונחתכת לטווח חוקי', () {
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.downloading,
            bytesDownloaded: 50,
            bytesTotal: 200,
          ),
        )!.progress,
        0.25,
      );
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.downloading,
            bytesDownloaded: 300,
            bytesTotal: 200,
          ),
        )!.progress,
        1.0,
      );
    });

    test('בלי מדידת בתים אין אחוז — ולא חלוקה באפס', () {
      expect(
        item(
          const LibraryUpdateState(status: LibraryUpdateStatus.downloading),
        )!.progress,
        isNull,
      );
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.downloading,
            bytesDownloaded: 10,
            bytesTotal: 0,
          ),
        )!.progress,
        isNull,
      );
    });

    test('בשלב ה-apply המדד הוא applyProgress ולא שארית ההורדה', () {
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.applying,
            bytesDownloaded: 200,
            bytesTotal: 200,
            applyProgress: 0.4,
          ),
        )!.progress,
        0.4,
      );
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.applying,
            bytesDownloaded: 200,
            bytesTotal: 200,
          ),
        )!.progress,
        isNull,
      );
    });
  });
}
