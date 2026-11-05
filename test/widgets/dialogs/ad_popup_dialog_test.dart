import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/support_organization.dart';
import 'package:otzaria/services/support_organizations_service.dart';
import 'package:otzaria/widgets/dialogs/ad_popup_dialog.dart';

void main() {
  // Future שנוצר ב-zone של טסט אחד לא מריץ קולבקים ב-zone של הטסט הבא.
  // גם rootBundle ממטמן את ה-Future שלו, ולכן שניהם מאופסים.
  setUp(() {
    SupportOrganizationsService.resetCache();
    rootBundle.clear();
  });

  final listFinder = find.ancestor(
    of: find.text('קווי חירום'),
    matching: find.byType(SingleChildScrollView),
  );

  /// מרכיב את הדיאלוג ומחכה לרשימה. מטמון השירות משנה מתי ה-FutureBuilder
  /// מתעדכן, ולכן ממתינים לתנאי ולא למספר פעימות קבוע.
  Future<void> pumpUntilListReady(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AdPopupDialog(title: 'כותרת')),
    );
    for (var i = 0; i < 20 && listFinder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(listFinder, findsOneWidget);
  }

  /// מריץ את רצף האנימציות עד הסוף. הרצף משלב Future.delayed עם בקרי
  /// אנימציה, ולכן נדרשות פעימות קצובות — pumpAndSettle לבדו חוזר מיד
  /// בהמתנות שבין האנימציות ומשאיר טיימר תלוי.
  Future<void> finishAnimations(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  // UI-047, q10 שאלה 7.7: הכפתור נראה פעיל, ולחיצה עליו פותחת את התפריט.
  testWidgets('"אל תציג שוב" הוא כפתור פעיל שפותח את תפריט ההשהיה', (
    tester,
  ) async {
    await pumpUntilListReady(tester);
    await finishAnimations(tester);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('אל תציג שוב'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('אל תציג שוב'));
    await tester.pumpAndSettle();
    expect(find.text('למשך שבוע'), findsOneWidget);
    expect(find.text('למשך חודש'), findsOneWidget);
    expect(find.text('לעולם'), findsOneWidget);
  });

  group('תצוגה מקובץ הנתונים', () {
    testWidgets('כל הארגונים שבקובץ מוצגים עם שם וטלפון', (tester) async {
      await pumpUntilListReady(tester);

      final organizations = await SupportOrganizationsService.load();
      final all = [
        ...organizations.emergencyLines,
        ...organizations.supportOrgs,
      ];
      expect(all, isNotEmpty);

      for (final org in all) {
        expect(
          find.text(org.name),
          findsOneWidget,
          reason: 'הארגון "${org.name}" לא מוצג',
        );
        expect(
          find.text(org.phone),
          findsOneWidget,
          reason: 'הטלפון של "${org.name}" לא מוצג',
        );
      }

      await finishAnimations(tester);
    });

    testWidgets('שגיאת טעינה מוצגת למשתמש במקום רשימה ריקה', (tester) async {
      final completer = Completer<SupportOrganizations>();
      SupportOrganizationsService.setCacheForTesting(completer.future);

      await tester.pumpWidget(
        const MaterialApp(home: AdPopupDialog(title: 'כותרת')),
      );
      completer.completeError(StateError('asset failed'));
      await tester.pump();

      expect(find.text('לא ניתן לטעון את פרטי הארגונים'), findsOneWidget);
      await finishAnimations(tester);
    });

    testWidgets('פתיחת כרטיס מציגה את אפשרויות הקו', (tester) async {
      await pumpUntilListReady(tester);
      await finishAnimations(tester);

      final organizations = await SupportOrganizationsService.load();
      final org = organizations.supportOrgs.last;
      expect(find.text('אפשרויות הקו:'), findsNothing);

      await tester.ensureVisible(find.text(org.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(org.name));
      await tester.pumpAndSettle();

      expect(find.text('אפשרויות הקו:'), findsOneWidget);
      expect(find.textContaining(org.details.split('\n').first), findsWidgets);
    });
  });

  group('ביצועים', () {
    testWidgets('לוגואי הארגונים מפוענחים בגודל מוקטן ולא ברזולוציית המקור', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpUntilListReady(tester);

      final logos = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .whereType<ResizeImage>()
          .where((provider) {
            final source = provider.imageProvider;
            return source is AssetImage &&
                source.assetName.startsWith('assets/logos/');
          })
          .toList();

      final organizations = await SupportOrganizationsService.load();
      expect(
        logos,
        hasLength(
          organizations.emergencyLines.length +
              organizations.supportOrgs.length,
        ),
      );
      for (final logo in logos) {
        expect(logo.width, 300);
        expect(logo.height, 300);
        expect(logo.policy, ResizeImagePolicy.fit);
      }

      await finishAnimations(tester);
    });

    testWidgets('סגירה משמרת את הנתונים לפתיחה חוזרת בלי טעינה נוספת', (
      tester,
    ) async {
      await pumpUntilListReady(tester);
      await finishAnimations(tester);

      final whileOpen = SupportOrganizationsService.load();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      expect(
        identical(SupportOrganizationsService.load(), whileOpen),
        isTrue,
        reason: 'סגירת הפופאפ גרמה לטעינה חוזרת של אותם נתונים',
      );
    });

    testWidgets('רשימת הארגונים לא נבנית מחדש בכל פריים של האנימציה', (
      tester,
    ) async {
      await pumpUntilListReady(tester);

      // דגימה לאורך כל רצף האנימציות — בנייה מחדש בכל פריים הייתה מייצרת
      // מופע ווידג'ט חדש בכל דגימה
      final instances = <SingleChildScrollView>{};
      for (var i = 0; i < 40; i++) {
        instances.add(tester.widget<SingleChildScrollView>(listFinder));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await finishAnimations(tester);

      expect(
        instances,
        hasLength(1),
        reason:
            'הרשימה נבנתה מחדש ${instances.length} פעמים — היא חייבת לעבור '
            'דרך child של AnimatedBuilder',
      );
    });
  });
}
