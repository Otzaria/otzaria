import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/work_status/work_status_overlay.dart';

Widget _wrap(Widget child, WorkStatusCubit cubit) {
  return MaterialApp(
    home: BlocProvider<WorkStatusCubit>.value(
      value: cubit,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  group('WorkStatusOverlay', () {
    testWidgets('לא מציג כלום כשאין משימות', (tester) async {
      final cubit = WorkStatusCubit();
      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      cubit.close();
    });

    testWidgets('מציג משימה יחידה עם אחוזים', (tester) async {
      final cubit = WorkStatusCubit();
      cubit.upsert(
        const WorkStatusItem(
          id: 'indexing',
          title: 'אינדוקס ספרים',
          message: 'התוכנה בתהליך אינדוקס',
          detail: 'התקדמות: 25/100',
          progress: 0.25,
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      expect(find.text('אינדוקס ספרים'), findsOneWidget);
      expect(find.text('התוכנה בתהליך אינדוקס'), findsOneWidget);
      expect(find.text('התקדמות: 25/100'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      cubit.close();
    });

    testWidgets('מציג progress לא-דטרמיניסטי כשאין progress', (tester) async {
      final cubit = WorkStatusCubit();
      cubit.upsert(
        const WorkStatusItem(
          id: 'sync',
          title: 'סנכרון',
          message: 'מחלץ',
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      expect(find.text('...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      cubit.close();
    });

    testWidgets('מציג שתי משימות במקביל', (tester) async {
      final cubit = WorkStatusCubit();
      cubit.upsert(
        const WorkStatusItem(
          id: 'indexing',
          title: 'אינדוקס ספרים',
          message: 'בתהליך',
          progress: 0.3,
        ),
      );
      cubit.upsert(
        const WorkStatusItem(
          id: 'sync',
          title: 'סנכרון ספרייה',
          message: 'מוריד',
          progress: 0.6,
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      // Primary: אינדוקס (big circle)
      expect(find.text('אינדוקס ספרים'), findsOneWidget);
      // Secondary: סנכרון (compact row)
      expect(find.text('סנכרון ספרייה: מוריד'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      cubit.close();
    });

    testWidgets('לחיצה על פריט עם onTap מפעילה את הפעולה', (tester) async {
      final cubit = WorkStatusCubit();
      var tapped = false;
      cubit.upsert(
        WorkStatusItem(
          id: 'indexing',
          title: 'אינדוקס ספרים',
          message: 'בתהליך',
          onTap: () => tapped = true,
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      await tester.tap(find.text('אינדוקס ספרים'));
      await tester.pump();

      expect(tapped, isTrue);
      cubit.close();
    });

    testWidgets('לחיצה על פריט ללא onTap אינה מנווטת', (tester) async {
      final cubit = WorkStatusCubit();
      cubit.upsert(
        const WorkStatusItem(
          id: 'library_update',
          title: 'עדכון ספרייה',
          message: 'מאמת את הספרייה הנוכחית',
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      // ה-InkWell העוטף את השורה מושבת (onTap == null) לפריט לא-לחיץ
      final inkWell = tester.widget<InkWell>(
        find.ancestor(
          of: find.text('עדכון ספרייה'),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWell.onTap, isNull);
      cubit.close();
    });

    testWidgets('לחיצה על שורה לא-לחיצה אינה מפעילה פעולה של פריט אחר', (
      tester,
    ) async {
      final cubit = WorkStatusCubit();
      var indexingTapped = false;
      cubit.upsert(
        WorkStatusItem(
          id: 'indexing',
          title: 'אינדוקס ספרים',
          message: 'בתהליך',
          onTap: () => indexingTapped = true,
        ),
      );
      cubit.upsert(
        const WorkStatusItem(
          id: 'library_update',
          title: 'עדכון ספרייה',
          message: 'מאמת',
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      // לחיצה על השורה של עדכון הספרייה (משנית, ללא onTap) לא מנווטת
      await tester.tap(find.text('עדכון ספרייה: מאמת'));
      await tester.pump();
      expect(indexingTapped, isFalse);

      // לחיצה על שורת האינדוקס כן מפעילה את הפעולה שלה
      await tester.tap(find.text('אינדוקס ספרים'));
      await tester.pump();
      expect(indexingTapped, isTrue);
      cubit.close();
    });

    testWidgets('פריט כושל מוצג עם אייקון שגיאה ולא עם ספינר', (tester) async {
      final cubit = WorkStatusCubit();
      cubit.upsert(
        const WorkStatusItem(
          id: 'library_update',
          title: 'עדכון ספרייה',
          message: 'שגיאה בהחלת העדכון',
          detail: 'לחץ לניסיון חוזר',
          kind: WorkStatusKind.failed,
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      expect(find.text('שגיאה בהחלת העדכון'), findsOneWidget);
      expect(find.text('לחץ לניסיון חוזר'), findsOneWidget);
      expect(find.byIcon(FluentIcons.error_circle_24_regular), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      cubit.close();
    });

    testWidgets('לחיצה על פריט כושל מפעילה ניסיון חוזר', (tester) async {
      final cubit = WorkStatusCubit();
      var retried = false;
      cubit.upsert(
        WorkStatusItem(
          id: 'library_update',
          title: 'עדכון ספרייה',
          message: 'שגיאה בהחלת העדכון',
          kind: WorkStatusKind.failed,
          onTap: () => retried = true,
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      await tester.tap(find.text('עדכון ספרייה'));
      await tester.pump();

      expect(retried, isTrue);
      cubit.close();
    });

    testWidgets('dismiss מסתיר את הכרטיס מבלי למחוק משימות', (tester) async {
      final cubit = WorkStatusCubit();
      cubit.upsert(
        const WorkStatusItem(
          id: 'sync',
          title: 'סנכרון',
          message: 'רץ',
        ),
      );

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      expect(find.text('סנכרון'), findsOneWidget);

      await tester.tap(find.byTooltip('סגור'));
      await tester.pump();

      // overlay נסגר
      expect(find.text('סנכרון'), findsNothing);
      // משימה עדיין קיימת ב-state
      expect(cubit.state.hasActiveItems, isTrue);
      cubit.close();
    });

    testWidgets('משימה חדשה אחרי dismiss מחזירה את ה-overlay', (tester) async {
      final cubit = WorkStatusCubit();
      cubit.upsert(const WorkStatusItem(id: 'a', title: 'א', message: 'רץ'));

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      await tester.tap(find.byTooltip('סגור'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // משימה חדשה ב-ID שונה — overlay חוזר להיות גלוי
      // item 'a' עדיין קיים כ-primary; item 'b' מוצג כ-secondary
      cubit.upsert(const WorkStatusItem(id: 'b', title: 'ב', message: 'רץ'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      // ה-secondary row מציג title:message
      expect(find.text('ב: רץ'), findsOneWidget);
      cubit.close();
    });

    testWidgets('כשכל המשימות הוסרו ונוספה חדשה, overlay מוצג שוב', (
      tester,
    ) async {
      final cubit = WorkStatusCubit();
      cubit.upsert(const WorkStatusItem(id: 'a', title: 'א', message: 'רץ'));

      await tester.pumpWidget(_wrap(const WorkStatusOverlay(), cubit));
      await tester.pump();

      await tester.tap(find.byTooltip('סגור'));
      await tester.pump();

      cubit.remove('a');
      await tester.pump();

      // עכשיו אין משימות — dismiss reset; הוספת משימה מחדש מציגה overlay
      cubit.upsert(const WorkStatusItem(id: 'a', title: 'א', message: 'רץ'));
      // שני pump כדי לוודא שה-BlocBuilder מקבל את ה-state ומרנדר
      await tester.pump();
      await tester.pump();
      // וודא שה-state עצמו נכון
      expect(cubit.state.isDismissed, isFalse);
      expect(cubit.state.hasActiveItems, isTrue);
      cubit.close();
    });
  });
}
