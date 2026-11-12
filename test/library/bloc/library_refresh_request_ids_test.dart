import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_state.dart';

void main() {
  group('LibraryState.completedRefreshRequestIds', () {
    test('מדווח רק ב-copyWith שהעביר אותו במפורש, ומתאפס בכל copyWith אחר', () {
      const state = LibraryState();
      final completed = state.copyWith(completedRefreshRequestIds: {7, 8});
      expect(completed.completedRefreshRequestIds, {7, 8});

      // copyWith עוקב (למשל עדכון חיפוש) לא גורר את המזהים הלאה — אחרת
      // ה-listener היה מפעיל אינדוקס נוסף על state שאינו סיום רענון.
      final next = completed.copyWith(isSearching: true);
      expect(next.completedRefreshRequestIds, isNull);
    });

    test('משתתף בשוויון ה-state — emit עם מזהים שונה מ-emit בלעדיהם', () {
      const state = LibraryState();
      expect(
        state.copyWith(completedRefreshRequestIds: {1}),
        isNot(equals(state.copyWith())),
      );
    });
  });

  group('LibraryState.refreshRequestSettled', () {
    test('רענון אחר שהסתיים קודם אינו מסיים את המתנת עדכון הספרייה', () {
      const requestId = 7;
      const otherRefresh = LibraryState(completedRefreshRequestIds: {3});
      expect(
        LibraryState.refreshRequestSettled(otherRefresh, requestId),
        isFalse,
      );
      const updateRefresh = LibraryState(completedRefreshRequestIds: {7, 8});
      expect(
        LibraryState.refreshRequestSettled(updateRefresh, requestId),
        isTrue,
      );
    });

    test('כשל של בקשת העדכון מסיים המתנה בלי לדווח הצלחה', () {
      const failed = LibraryState(failedRefreshRequestIds: {7});
      expect(LibraryState.refreshRequestSettled(failed, 7), isTrue);
      expect(failed.completedRefreshRequestIds, isNull);
      expect(LibraryState.refreshRequestSettled(failed, 8), isFalse);
    });

    test('מזהי כשל לא נגררים ל-state הבא', () {
      const failed = LibraryState(failedRefreshRequestIds: {7});
      final next = failed.copyWith(isSearching: true);
      expect(next.failedRefreshRequestIds, isNull);
      expect(next, isNot(equals(failed)));
    });
  });
}
