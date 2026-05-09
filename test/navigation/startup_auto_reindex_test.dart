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
        );

        expect(decision, StartupIndexingDecision.autoReindexThenStart);
      },
    );

    test('נדרש איפוס + עדכון אוטומטי כבוי -> דיאלוג אישור משתמש', () {
      final decision = decideStartupIndexing(
        requiresManualReindex: true,
        autoUpdateIndex: false,
      );

      expect(decision, StartupIndexingDecision.promptManualReindex);
    });

    test('לא נדרש איפוס + עדכון אוטומטי דלוק -> אינדוקס רגיל', () {
      final decision = decideStartupIndexing(
        requiresManualReindex: false,
        autoUpdateIndex: true,
      );

      expect(decision, StartupIndexingDecision.startIndexing);
    });

    test('לא נדרש איפוס + עדכון אוטומטי כבוי -> בדיקת סטטוס בלבד', () {
      final decision = decideStartupIndexing(
        requiresManualReindex: false,
        autoUpdateIndex: false,
      );

      expect(decision, StartupIndexingDecision.checkIndexStatus);
    });
  });
}
