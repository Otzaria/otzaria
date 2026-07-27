import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';

/// בדיקות למנגנון שחזור הפוקוס (מערכת שתי-שכבות: מסך + dialog stack).
///
/// משתמשות ב-[FocusRepository.restoreNowForTesting] שמריץ את לוגיקת
/// הבחירה סינכרונית, ולכן לא דורשות pump() לבדיקות הלוגיקה הבסיסית.
///
/// בדיקת ה-snapshot נבחנת עם pumpWidget כדי לאפשר postFrameCallback.
void main() {
  late FocusRepository repo;

  setUp(() {
    repo = FocusRepository();
    repo.resetForTesting();
  });

  group('setScreenRestorer', () {
    test('ניווט מחליף owner: רק Owner החדש משחזר', () {
      int old = 0, fresh = 0;

      repo.setScreenRestorer(restore: () => old++, canRestore: () => true);
      repo.setScreenRestorer(restore: () => fresh++, canRestore: () => true);

      repo.restoreNowForTesting();

      expect(fresh, 1, reason: 'Owner חדש של מסך אמור לשחזר');
      expect(old, 0, reason: 'Owner ישן לא אמור להיקרא');
    });

    test('canRestore=false — restore לא נקרא', () {
      int calls = 0;

      repo.setScreenRestorer(restore: () => calls++, canRestore: () => false);
      repo.restoreNowForTesting();

      expect(calls, 0);
    });
  });

  group('dialog stack restore', () {
    test('dialog מעל המסך — הוא מקבל שחזור', () {
      int screenCalls = 0, dialogCalls = 0;

      repo.setScreenRestorer(
        restore: () => screenCalls++,
        canRestore: () => true,
      );
      repo.registerActiveRestorer(
        restore: () => dialogCalls++,
        canRestore: () => true,
      );

      repo.restoreNowForTesting();

      expect(dialogCalls, 1, reason: 'Dialog פתוח — dialog משחזר');
      expect(screenCalls, 0);
    });

    test('סגירת dialog מחזירה פוקוס למסך', () {
      int screenCalls = 0, dialogCalls = 0;

      repo.setScreenRestorer(
        restore: () => screenCalls++,
        canRestore: () => true,
      );

      final token = repo.registerActiveRestorer(
        restore: () => dialogCalls++,
        canRestore: () => true,
      );

      // סגירת dialog
      repo.unregisterActiveRestorer(token);
      repo.restoreNowForTesting();

      expect(screenCalls, 1, reason: 'Dialog נסגר — מסך משחזר');
      expect(dialogCalls, 0, reason: 'Dialog לא אמור להיקרא לאחר ביטול');
    });

    test('שני dialogs — ביטול עליון חוזר לדיאלוג שמתחתיו', () {
      int d1 = 0, d2 = 0;

      final t1 = repo.registerActiveRestorer(
        restore: () => d1++,
        canRestore: () => true,
      );
      final t2 = repo.registerActiveRestorer(
        restore: () => d2++,
        canRestore: () => true,
      );

      repo.unregisterActiveRestorer(t2);
      repo.restoreNowForTesting();
      expect(d1, 1, reason: 'Dialog ראשון מחזיר לאחר ביטול השני');
      expect(d2, 0);

      repo.unregisterActiveRestorer(t1);
      repo.restoreNowForTesting();
      expect(d1, 1, reason: 'אין שינוי — אין owner תקף');
    });

    test('ביטול dialog שאינו העליון לא פוגע בעליון', () {
      int d1 = 0, d2 = 0;

      final t1 = repo.registerActiveRestorer(
        restore: () => d1++,
        canRestore: () => true,
      );
      final t2 = repo.registerActiveRestorer(
        restore: () => d2++,
        canRestore: () => true,
      );

      repo.unregisterActiveRestorer(t1);
      repo.restoreNowForTesting();

      expect(d2, 1, reason: 't2 עדיין פעיל');
      expect(d1, 0);

      repo.unregisterActiveRestorer(t2);
    });

    test('dialog עם canRestore=false — נפול לscreen', () {
      int screenCalls = 0;

      repo.setScreenRestorer(
        restore: () => screenCalls++,
        canRestore: () => true,
      );
      repo.registerActiveRestorer(
        restore: () {},
        canRestore: () => false,
      );

      repo.restoreNowForTesting();

      expect(screenCalls, 1, reason: 'מסך ממלא מקום dialog לא-תקף');
    });
  });

  group('scheduleRestore — ללא snapshot', () {
    testWidgets('owner שמוחלף לפני fire — owner החדש משחזר', (tester) async {
      int old = 0, fresh = 0;

      repo.setScreenRestorer(restore: () => old++, canRestore: () => true);

      // מתזמנים שחזור
      repo.scheduleRestore();

      // לפני שה-callback רץ — מחליפים owner
      repo.setScreenRestorer(restore: () => fresh++, canRestore: () => true);

      // pump עם widget כדי שה-addPostFrameCallback יורה
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(fresh, 1, reason: 'Owner חדש אמור לשחזר, לא הישן');
      expect(old, 0, reason: 'Snapshot ישן לא אמור לשמש');
    });

    testWidgets('dialog שנסגר לפני fire — screen owner משחזר', (tester) async {
      int screenCalls = 0, dialogCalls = 0;

      repo.setScreenRestorer(
        restore: () => screenCalls++,
        canRestore: () => true,
      );
      final token = repo.registerActiveRestorer(
        restore: () => dialogCalls++,
        canRestore: () => true,
      );

      repo.scheduleRestore();

      // dialog נסגר לפני שה-callback ירה
      repo.unregisterActiveRestorer(token);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(screenCalls, 1, reason: 'מסך שחזר כי dialog נסגר לפני ה-callback');
      expect(dialogCalls, 0, reason: 'Dialog לא אמור לשחזר לאחר ביטול');
    });
  });

  // ── בדיקות layout-aware restorer ──────────────────────────────────────────
  // מאמתות שהתנהגות canRestore תלויה בחיבור ה-FocusNode לעץ (enclosingScope).
  // זה מייצג את ההבדל בין Settings/More בdesktop-mode לmobile-mode:
  // בdesktop, ה-contentFocusNode מחובר ↠ canRestore=true.
  // במobile, ה-node לא מחובר ↠ canRestore=false.
  group('layout-aware restorer', () {
    testWidgets('Settings narrow: node לא מחובר → canRestore=false', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      // מדמה את מה ש-_requestSettingsFocus עושה — restorer עם enclosingScope check
      repo.setScreenRestorer(
        restore: () {
          if (node.enclosingScope != null) node.requestFocus();
        },
        canRestore: () => node.enclosingScope != null,
      );

      // node לא מחובר לעץ (מצב mobile) → canRestore אמור להיות false
      expect(
        repo.screenCanRestoreForTesting(),
        false,
        reason: 'Mobile layout: node לא מחובר → canRestore=false',
      );

      // מחבר את ה-node לעץ (מדמה מעבר לdesktop layout)
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (_, _) => Focus(focusNode: node, child: const SizedBox()),
        ),
      );

      // עכשיו node מחובר → canRestore אמור להיות true
      expect(
        repo.screenCanRestoreForTesting(),
        true,
        reason: 'Desktop layout: node מחובר → canRestore=true',
      );
    });

    testWidgets('More: canRestore תלוי בחיבור node לעץ, לא ב-showMobileMenu', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      // מדמה את _registerMoreRestorer — canRestore נקבע לפי enclosingScope בלבד
      repo.setScreenRestorer(
        restore: () {
          if (node.enclosingScope != null) node.requestFocus();
        },
        canRestore: () => node.enclosingScope != null,
      );

      // node לא מחובר לעץ (mobile menu פתוח, contentFocusNode לא בעץ)
      expect(
        repo.screenCanRestoreForTesting(),
        false,
        reason: 'Node לא מחובר → canRestore=false',
      );

      // מחבר את ה-node לעץ — מדמה desktop layout (contentFocusNode תמיד בעץ בdesktop)
      // גם כאשר _showMobileMenu==true ב-state הפנימי, ב-desktop הnode מחובר
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (_, _) => Focus(focusNode: node, child: const SizedBox()),
        ),
      );

      // node מחובר → canRestore=true, ללא קשר לערך _showMobileMenu
      expect(
        repo.screenCanRestoreForTesting(),
        true,
        reason:
            'Node מחובר לעץ → canRestore=true (גם אם showMobileMenu==true כ-state ישן)',
      );
    });
  });

  group('pending tab content focus', () {
    testWidgets('בקשה לפני רישום — מתבצעת ברגע שהתוכן נרשם', (tester) async {
      final tab = Object();
      int calls = 0;

      expect(repo.requestTabContentFocus(tab), false);

      repo.registerTabContentFocusRequester(tab, () => calls++);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(calls, 1, reason: 'בקשה ממתינה צריכה לירות עם רישום התוכן');
    });

    testWidgets('מעבר לטאב אחר לפני טעינה — רק האחרון מקבל פוקוס', (
      tester,
    ) async {
      final tabA = Object();
      final tabB = Object();
      int aCalls = 0, bCalls = 0;

      repo.requestTabContentFocus(tabA);
      repo.requestTabContentFocus(tabB);

      repo.registerTabContentFocusRequester(tabA, () => aCalls++);
      repo.registerTabContentFocusRequester(tabB, () => bCalls++);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(aCalls, 0, reason: 'הטאב הקודם לא אמור לחטוף פוקוס');
      expect(bCalls, 1, reason: 'רק הטאב האחרון שביקש מקבל פוקוס');
    });

    test('תוכן רשום — מתבצע מיד ללא המתנה', () {
      final tab = Object();
      int calls = 0;
      repo.registerTabContentFocusRequester(tab, () => calls++);

      expect(repo.requestTabContentFocus(tab), true);
      expect(calls, 1);
    });

    testWidgets('ביטול רישום של הטאב הממתין מנקה את הבקשה', (tester) async {
      final tab = Object();
      int calls = 0;

      repo.requestTabContentFocus(tab);
      repo.unregisterTabContentFocusRequester(tab);

      repo.registerTabContentFocusRequester(tab, () => calls++);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(calls, 0);
    });

    testWidgets('הטאב הוסר בין התזמון להרצה — לא נקרא requester ישן', (
      tester,
    ) async {
      final tab = Object();
      int calls = 0;

      repo.requestTabContentFocus(tab);
      repo.registerTabContentFocusRequester(tab, () => calls++);
      repo.unregisterTabContentFocusRequester(tab);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(calls, 0, reason: 'requester של widget שב-dispose לא אמור לרוץ');
    });

    /// רגרסיה: בקשה ממתינה שרדה עזיבת מסך העיון, וירתה כשאזור הקריאה נרשם —
    /// בזמן שהמשתמש כבר הקליד בשדה של תוסף, שם הפוקוס נחטף.
    testWidgets('בוטלה בעזיבת מסך העיון — לא חוטפת פוקוס במסך אחר', (
      tester,
    ) async {
      final tab = Object();
      int calls = 0;

      repo.requestTabContentFocus(tab);
      repo.cancelPendingTabContentFocus();

      repo.registerTabContentFocusRequester(tab, () => calls++);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(calls, 0, reason: 'בקשה שבוטלה לא אמורה לירות עם רישום מאוחר');
    });
  });
}
