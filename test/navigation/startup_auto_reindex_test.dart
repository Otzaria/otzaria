// Regression test for the startup auto-reindex flow.
// Verifies the pure decision function used by main_window_screen._resolveStartupIndexing
// (see lib/navigation/startup_indexing_decision.dart). This is the actual function
// production calls, not a copy.

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/startup_indexing_decision.dart';

void main() {
  group('decideStartupIndexing', () {
    test(
      'regression: נדרש איפוס + עדכון אוטומטי דלוק -> איפוס אוטומטי ואינדוקס',
      () {
        final decision = decideStartupIndexing(
          requiresManualReindex: true,
          autoUpdateIndex: true,
          hasUnindexedBooks: true,
        );

        expect(decision, StartupIndexingDecision.autoReindexThenStart);
      },
    );

    test('נדרש איפוס + עדכון אוטומטי כבוי -> דיאלוג אישור משתמש', () {
      final decision = decideStartupIndexing(
        requiresManualReindex: true,
        autoUpdateIndex: false,
        hasUnindexedBooks: false,
      );

      expect(decision, StartupIndexingDecision.promptManualReindex);
    });

    test('נדרש איפוס -> איפוס גם כשכל הספרים מאונדקסים (סכמה ישנה)', () {
      final decision = decideStartupIndexing(
        requiresManualReindex: true,
        autoUpdateIndex: true,
        hasUnindexedBooks: false,
      );

      expect(decision, StartupIndexingDecision.autoReindexThenStart);
    });

    test('עדכון אוטומטי דלוק + יש ספרים לא מאונדקסים -> אינדוקס רגיל', () {
      final decision = decideStartupIndexing(
        requiresManualReindex: false,
        autoUpdateIndex: true,
        hasUnindexedBooks: true,
      );

      expect(decision, StartupIndexingDecision.startIndexing);
    });

    test(
      'עדכון אוטומטי דלוק אך הכל מאונדקס -> בדיקת סטטוס בלבד (לא אינדוקס בכל עלייה)',
      () {
        final decision = decideStartupIndexing(
          requiresManualReindex: false,
          autoUpdateIndex: true,
          hasUnindexedBooks: false,
        );

        expect(decision, StartupIndexingDecision.checkIndexStatus);
      },
    );

    test('עדכון אוטומטי כבוי -> בדיקת סטטוס בלבד, גם כשיש ספרים חסרים', () {
      final decision = decideStartupIndexing(
        requiresManualReindex: false,
        autoUpdateIndex: false,
        hasUnindexedBooks: true,
      );

      expect(decision, StartupIndexingDecision.checkIndexStatus);
    });
  });
}
