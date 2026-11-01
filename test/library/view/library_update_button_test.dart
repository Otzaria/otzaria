import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';

void main() {
  group('libraryUpdateButtonIcon', () {
    test('מצב מנותק מקבל סמל משלו — סימון שקט שהעדכון לא רץ', () {
      expect(
        libraryUpdateButtonIcon(LibraryUpdateStatus.disconnected),
        FluentIcons.cloud_off_24_regular,
      );
    });

    test('סמל המנותק שונה מסמל העדכון הרגיל ומסמל הסיום', () {
      final offline = libraryUpdateButtonIcon(LibraryUpdateStatus.disconnected);

      expect(offline, isNot(libraryUpdateButtonIcon(LibraryUpdateStatus.idle)));
      expect(
        offline,
        isNot(libraryUpdateButtonIcon(LibraryUpdateStatus.completed)),
      );
    });

    test('כשל מקבל סמל שגיאה — העוגן לניסיון חוזר אחרי שהחיווי נסגר מעצמו', () {
      expect(
        libraryUpdateButtonIcon(LibraryUpdateStatus.error),
        FluentIcons.error_circle_24_regular,
      );
    });

    test('שאר המצבים שומרים על הסמלים הקיימים', () {
      expect(
        libraryUpdateButtonIcon(LibraryUpdateStatus.completed),
        FluentIcons.checkmark_circle_24_regular,
      );
      for (final status in [
        LibraryUpdateStatus.idle,
        LibraryUpdateStatus.checking,
        LibraryUpdateStatus.downloading,
        LibraryUpdateStatus.applying,
        LibraryUpdateStatus.refreshing,
        LibraryUpdateStatus.needsFullConfirmation,
        LibraryUpdateStatus.blocked,
      ]) {
        expect(
          libraryUpdateButtonIcon(status),
          FluentIcons.arrow_sync_24_regular,
          reason: '$status',
        );
      }
    });
  });

  group('libraryUpdateButtonTooltip', () {
    test('עדכון ספרייה שאינו נתמך אינו מוצג גם בריחוף', () {
      const state = LibraryUpdateState(
        status: LibraryUpdateStatus.blocked,
        message: 'נדרש עדכון תוכנה כדי לעדכן את הספרייה',
        errorMessage: 'נדרש עדכון תוכנה כדי לעדכן את הספרייה',
      );

      expect(libraryUpdateButtonTooltip(state), 'עדכון ספרייה');
      expect(
        libraryUpdateButtonIcon(state.status),
        libraryUpdateButtonIcon(LibraryUpdateStatus.idle),
      );
    });

    test('מנותק מסביר את המצב ומזמין ניסיון חוזר', () {
      const state = LibraryUpdateState(
        status: LibraryUpdateStatus.disconnected,
        message: 'אין חיבור לאינטרנט',
      );

      expect(
        libraryUpdateButtonTooltip(state),
        'אין חיבור לאינטרנט - לחץ לנסות שוב',
      );
    });

    // ברשת מסוננת יש אינטרנט אך שרת העדכונים חסום — התיאור חייב לשקף זאת
    // ולא לטעון שאין חיבור (issue #1027).
    test('שרת עדכונים חסום — התיאור מציג את הסיבה שנקבעה ב-state', () {
      const state = LibraryUpdateState(
        status: LibraryUpdateStatus.disconnected,
        message: LibraryMessages.updateSourceUnreachable,
      );

      expect(
        libraryUpdateButtonTooltip(state),
        '${LibraryMessages.updateSourceUnreachable} - לחץ לנסות שוב',
      );
    });

    test('מנותק אינו מוצג כשגיאה', () {
      const offline = LibraryUpdateState(
        status: LibraryUpdateStatus.disconnected,
      );
      const error = LibraryUpdateState(status: LibraryUpdateStatus.error);

      expect(libraryUpdateButtonTooltip(offline), isNot(contains('שגיאה')));
      expect(libraryUpdateButtonTooltip(error), contains('שגיאה'));
    });

    test('מצבי הסיום והעבודה לא השתנו', () {
      expect(
        libraryUpdateButtonTooltip(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.completed,
            hasUpdate: true,
          ),
        ),
        'העדכון הושלם',
      );
      expect(
        libraryUpdateButtonTooltip(
          const LibraryUpdateState(status: LibraryUpdateStatus.completed),
        ),
        'הספרייה מעודכנת',
      );
      expect(
        libraryUpdateButtonTooltip(
          const LibraryUpdateState(
            status: LibraryUpdateStatus.downloading,
            message: 'מוריד ספרייה מלאה',
          ),
        ),
        'מוריד ספרייה מלאה',
      );
      expect(
        libraryUpdateButtonTooltip(const LibraryUpdateState()),
        'עדכון ספרייה',
      );
    });
  });

  group('libraryUpdateButtonResets', () {
    test('לחיצה במצב מנותק מתחילה ניסיון חדש ולא מאפסת', () {
      expect(
        libraryUpdateButtonResets(LibraryUpdateStatus.disconnected),
        isFalse,
      );
    });

    test('מצבי סיום/כשל/חסימה עדיין מתאפסים בלחיצה', () {
      expect(libraryUpdateButtonResets(LibraryUpdateStatus.completed), isTrue);
      expect(libraryUpdateButtonResets(LibraryUpdateStatus.error), isTrue);
      expect(libraryUpdateButtonResets(LibraryUpdateStatus.blocked), isTrue);
    });

    test('מצב מנוחה מתחיל עדכון', () {
      expect(libraryUpdateButtonResets(LibraryUpdateStatus.idle), isFalse);
    });
  });
}
