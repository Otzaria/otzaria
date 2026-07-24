import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';

/// בודק את ה-predicate ש-main_window_screen.dart מעביר ל-listenWhen של מאזין
/// הריענון — קוד הייצור עצמו, לא שכפול שלו.
const _shouldRefresh = LibraryUpdateState.hasRefreshRelevantChange;

void main() {
  group('library_update refresh listener predicate', () {
    test('מגיב לסיום עדכון רגיל (checking -> completed)', () {
      const previous = LibraryUpdateState(status: LibraryUpdateStatus.checking);
      const current = LibraryUpdateState(
        status: LibraryUpdateStatus.completed,
        hasUpdate: true,
      );

      expect(_shouldRefresh(previous, current), isTrue);
    });

    test('רגרסיה: מגיב כש-hasUpdate מתהפך בעוד status נשאר completed '
        '(ריצה שבוטלה פולטת completed אחרי ריצה חדשה)', () {
      const previous = LibraryUpdateState(
        status: LibraryUpdateStatus.completed,
        hasUpdate: false,
      );
      const current = LibraryUpdateState(
        status: LibraryUpdateStatus.completed,
        hasUpdate: true,
      );

      expect(
        _shouldRefresh(previous, current),
        isTrue,
        reason: 'התהפכות hasUpdate ב-completed חייבת להפעיל ריענון',
      );
    });

    test(
      'לא מגיב כששום דבר רלוונטי לא השתנה (אותו status, אותו hasUpdate)',
      () {
        const previous = LibraryUpdateState(
          status: LibraryUpdateStatus.completed,
          hasUpdate: true,
          message: 'הספרייה עודכנה',
        );
        // רק message השתנה — לא רלוונטי למאזין הריענון.
        const current = LibraryUpdateState(
          status: LibraryUpdateStatus.completed,
          hasUpdate: true,
          message: 'הספרייה מעודכנת',
        );

        expect(_shouldRefresh(previous, current), isFalse);
      },
    );
  });
}
