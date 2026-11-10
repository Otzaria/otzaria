import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library_update/library_update_work_status.dart';
import 'package:otzaria/work_status/work_status_item.dart';

void main() {
  WorkStatusItem? item(
    LibraryUpdateState state, {
    VoidCallback? onRetry,
    VoidCallback? onChooseDelta,
    VoidCallback? onChooseFullDownload,
    bool collapsible = false,
  }) => libraryUpdateWorkStatusItem(
    state,
    collapsible: collapsible,
    onRetry: onRetry ?? () {},
    onChooseDelta: onChooseDelta ?? () {},
    onChooseFullDownload: onChooseFullDownload ?? () {},
  );

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

    test('הורדה שנעצרה עם קובץ חלקי מציעה המשך', () {
      final result = item(
        const LibraryUpdateState(
          status: LibraryUpdateStatus.error,
          message: LibraryMessages.downloadPausedResumable,
          canResumeDownload: true,
        ),
      )!;

      expect(result.detail, LibraryMessages.tapToResumeDownload);
      expect(result.onTap, isNotNull);
    });

    test('סיבת הכשל מצורפת להודעה — המשתמש לא נשאר עם "שגיאה" סתמית', () {
      final result = item(
        const LibraryUpdateState(
          status: LibraryUpdateStatus.error,
          message: 'שגיאה בהורדה המלאה',
          errorMessage: 'אין מספיק מקום פנוי בכונן',
        ),
      )!;

      expect(result.message, 'שגיאה בהורדה המלאה\nאין מספיק מקום פנוי בכונן');
      expect(result.detail, 'לחץ לניסיון חוזר');
    });

    test('סיבת כשל ארוכה נחתכת כדי שהחיווי לא יתנפח', () {
      final longError = 'א' * 500;
      final result = item(
        LibraryUpdateState(
          status: LibraryUpdateStatus.error,
          message: 'שגיאה בהורדה המלאה',
          errorMessage: longError,
        ),
      )!;

      expect(result.message.length, lessThan(250));
      expect(result.message, endsWith('…'));
    });

    test('סיבה זהה להודעה או ריקה אינה מוכפלת', () {
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.error,
            message: 'שגיאה בבדיקת עדכונים',
            errorMessage: 'שגיאה בבדיקת עדכונים',
          ),
        )!.message,
        'שגיאה בבדיקת עדכונים',
      );
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.error,
            message: 'שגיאה בבדיקת עדכונים',
            errorMessage: '  ',
          ),
        )!.message,
        'שגיאה בבדיקת עדכונים',
      );
    });

    test('כשל בבדיקת עדכונים נסגר מעצמו — הכפתור נשאר כעוגן לניסיון חוזר', () {
      final result = item(
        const LibraryUpdateState(
          status: LibraryUpdateStatus.error,
          message: 'שגיאה בבדיקת עדכונים',
          isCheckFailure: true,
        ),
      )!;

      expect(result.autoDismissAfter, kCheckFailureAutoDismiss);
      expect(result.onTap, isNotNull);
    });

    test(
      'כשל בהורדה/החלה נשאר עד סגירה ידנית — שם החיווי הוא הניסיון החוזר',
      () {
        final result = item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.error,
            message: 'שגיאה בהורדה המלאה',
          ),
        )!;

        expect(result.autoDismissAfter, isNull);
      },
    );

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

    test('בדיקת העדכון עצמה שקטה — אחרת החיווי קופץ בכל פתיחה', () {
      expect(
        item(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.checking,
            message: 'בודק עדכוני ספרייה',
          ),
        ),
        isNull,
      );
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

    test('בחירת מסלול מציגה את שתי האפשרויות כשוות ערך', () {
      var delta = 0;
      var full = 0;
      final result = item(
        const LibraryUpdateState(
          status: LibraryUpdateStatus.needsRouteChoice,
          message: 'עדכון דלתא: ... הורדה מלאה: ...',
        ),
        onChooseDelta: () => delta++,
        onChooseFullDownload: () => full++,
      )!;

      expect(result.actions, hasLength(2));
      expect(result.actions.map((a) => a.label), ['עדכון דלתא', 'הורדה מלאה']);
      expect(
        result.kind,
        WorkStatusKind.awaitingInput,
        reason: 'טבעת 0% נראית כמו עבודה שנתקעה — כאן אין עבודה, יש שאלה',
      );
      expect(result.progress, isNull);
      expect(
        result.actions.every((a) => !a.emphasized),
        isTrue,
        reason: 'אין המלצה — הבחירה תלויה במהירות הרשת של המשתמש',
      );
      expect(result.message, 'עדכון דלתא: ... הורדה מלאה: ...');

      result.actions[0].onPressed();
      result.actions[1].onPressed();
      expect(delta, 1);
      expect(full, 1);
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

  group('כיווץ לגלולה בשורת הכותרת', () {
    const running = LibraryUpdateState(
      status: LibraryUpdateStatus.downloading,
      bytesDownloaded: 42,
      bytesTotal: 100,
    );
    const choice = LibraryUpdateState(
      status: LibraryUpdateStatus.needsRouteChoice,
    );
    const failed = LibraryUpdateState(status: LibraryUpdateStatus.error);

    test('בלי שורת כותרת (מובייל) הפריט לא מצטמצם לעולם', () {
      for (final state in [running, choice, failed]) {
        final result = item(state)!;
        expect(result.chipLabel, isNull);
        expect(result.collapseAfter, isNull);
      }
    });

    test('עבודה רצה מצטמצמת אחרי kLibraryCardCollapseAfter', () {
      final result = item(running, collapsible: true)!;
      expect(result.chipLabel, 'ספרייה');
      expect(result.collapseAfter, kLibraryCardCollapseAfter);
    });

    test('בחירת מסלול וכשל נשארים כרטיס פתוח (אין כיווץ אוטומטי)', () {
      for (final state in [choice, failed]) {
        final result = item(state, collapsible: true)!;
        expect(result.chipLabel, 'ספרייה');
        expect(result.collapseAfter, isNull);
      }
    });
  });
}
