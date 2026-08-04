import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
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
        LibraryUpdateStatus.error,
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
