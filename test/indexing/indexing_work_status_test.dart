import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/indexing_work_status.dart';

void main() {
  group('indexingWorkStatusItem', () {
    const running = IndexingInProgress(
      booksProcessed: 25,
      totalBooks: 100,
      isCreatingIndex: true,
    );

    test('ריצה רגילה: הודעה, התקדמות ושני לחצנים', () {
      final item = indexingWorkStatusItem(
        running,
        onTogglePause: () {},
        onToggleEconomy: () {},
      );

      expect(item.id, kIndexingWorkStatusId);
      expect(item.message, 'התוכנה בתהליך אינדוקס');
      expect(item.detail, 'התקדמות: 25/100');
      expect(item.progress, 0.25);
      expect(item.actions.map((a) => a.label), ['השהה', 'מצב חסכוני']);
      expect(item.actions.every((a) => !a.emphasized), isTrue);
    });

    test('במצב מושהה: הודעת השהיה ולחצן "המשך"', () {
      final item = indexingWorkStatusItem(
        const IndexingInProgress(
          booksProcessed: 25,
          totalBooks: 100,
          isCreatingIndex: true,
          isPaused: true,
        ),
        onTogglePause: () {},
        onToggleEconomy: () {},
      );

      expect(item.message, 'האינדוקס מושהה');
      expect(item.actions.first.label, 'המשך');
    });

    test('מצב חסכוני פעיל מודגש (tonal)', () {
      final item = indexingWorkStatusItem(
        const IndexingInProgress(
          booksProcessed: 25,
          totalBooks: 100,
          isCreatingIndex: true,
          isEconomy: true,
        ),
        onTogglePause: () {},
        onToggleEconomy: () {},
      );

      expect(item.actions.last.emphasized, isTrue);
    });

    test('הלחצנים מפעילים את ה-callbacks שסופקו', () {
      var pauseTaps = 0;
      var economyTaps = 0;
      final item = indexingWorkStatusItem(
        running,
        onTogglePause: () => pauseTaps++,
        onToggleEconomy: () => economyTaps++,
      );

      item.actions.first.onPressed();
      item.actions.last.onPressed();
      expect(pauseTaps, 1);
      expect(economyTaps, 1);
    });

    test('שלב האיחוד: הודעה נפרדת, בלי מונה ובלי לחצנים', () {
      final item = indexingWorkStatusItem(
        const IndexingInProgress(
          booksProcessed: 100,
          totalBooks: 100,
          isCreatingIndex: true,
          isFinalizing: true,
        ),
        onTogglePause: () {},
        onToggleEconomy: () {},
      );

      expect(item.message, 'מסיים ומאחד את קבצי האינדקס');
      expect(item.detail, isNot(contains('100/100')));
      expect(item.progress, isNull);
      expect(item.actions, isEmpty);
    });

    test('שלב האיחוד עם התקדמות: אחוז בפירוט ומד מוגדר', () {
      final item = indexingWorkStatusItem(
        const IndexingInProgress(
          booksProcessed: 100,
          totalBooks: 100,
          isFinalizing: true,
          finalizingProgress: 0.427,
        ),
        onTogglePause: () {},
        onToggleEconomy: () {},
      );

      expect(item.message, 'מסיים ומאחד את קבצי האינדקס');
      expect(item.detail, contains('42%'));
      expect(item.progress, 0.427);
      expect(item.actions, isEmpty);
    });

    test('שלב הסריקה: הודעת בדיקה, התקדמות, ובלי לחצני השהיה/חיסכון', () {
      final item = indexingWorkStatusItem(
        const IndexingInProgress(
          booksProcessed: 40,
          totalBooks: 80,
          isScanning: true,
        ),
        onTogglePause: () {},
        onToggleEconomy: () {},
      );

      expect(item.message, 'בודק אילו ספרים דורשים עדכון באינדקס');
      expect(item.detail, 'התקדמות: 40/80');
      expect(item.progress, 0.5);
      expect(item.actions, isEmpty);
    });

    test('סה"כ אפס: אין progress דטרמיניסטי', () {
      final item = indexingWorkStatusItem(
        const IndexingInProgress(isCreatingIndex: true),
        onTogglePause: () {},
        onToggleEconomy: () {},
      );

      expect(item.progress, isNull);
    });
  });
}
