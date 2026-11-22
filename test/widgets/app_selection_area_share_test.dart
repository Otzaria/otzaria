import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/core/share/text_share_service.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

class _FakeShareService implements TextShareService {
  final shared = <String>[];
  final origins = <Rect?>[];

  @override
  Future<void> shareText(String text, {Rect? origin}) async {
    shared.add(text);
    origins.add(origin);
  }
}

String _lines(int count) =>
    [for (var i = 1; i <= count; i++) 'שורה $i'].join('\n');

void main() {
  late _FakeShareService share;
  late TextShareService previous;

  setUp(() {
    previous = TextShareService.instance;
    share = _FakeShareService();
    TextShareService.instance = share;
  });

  tearDown(() => TextShareService.instance = previous);

  Future<void> pumpArea(
    WidgetTester tester, {
    required String text,
    TargetPlatform platform = TargetPlatform.android,
    Future<BookProtection> Function()? protection,
  }) async {
    // 40 שורות חייבות להיכנס למסך, אחרת סרגל הבחירה מחוץ לתצוגה.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: AppSelectionArea(protection: protection, child: Text(text)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectByLongPress(WidgetTester tester) async {
    await tester.longPress(find.byType(Text).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
  }

  testWidgets('ב-Android סרגל הבחירה מציג "שתף" והלחיצה משתפת את הטקסט הנבחר', (
    tester,
  ) async {
    await pumpArea(tester, text: 'טקסט לשיתוף');
    await selectByLongPress(tester);

    expect(find.text('שתף'), findsOneWidget);

    await tester.tap(find.text('שתף'));
    await tester.pumpAndSettle();

    expect(share.shared, ['טקסט לשיתוף']);
    expect(share.origins.single, isNotNull, reason: 'עוגן ל-iPad');
    expect(
      find.byType(AdaptiveTextSelectionToolbar),
      findsNothing,
      reason: 'הסרגל נסגר אחרי השיתוף',
    );
  });

  testWidgets(
    '"שתף" מוצג כבר בפתיחה הראשונה של הסרגל אחרי לחיצה ארוכה, וה-Share '
    'של Flutter (Android בלבד, עוקף את מגבלת ההעתקה) מוסר',
    (tester) async {
      await pumpArea(tester, text: 'טקסט לשיתוף');
      await tester.longPress(find.byType(Text).first);
      await tester.pumpAndSettle();

      expect(find.text('שתף'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
    },
  );

  testWidgets('ב-iOS גם מוצג "שתף"', (tester) async {
    await pumpArea(
      tester,
      text: 'טקסט לשיתוף',
      platform: TargetPlatform.iOS,
    );
    await tester.longPress(find.byType(Text).first);
    await tester.pumpAndSettle();

    expect(find.text('שתף'), findsOneWidget);
  });

  testWidgets('"שתף" לא מוצג בסרגל כשאין בחירה', (tester) async {
    await pumpArea(tester, text: 'טקסט');
    expect(find.text('שתף'), findsNothing);
  });

  testWidgets('ב-Windows אין "שתף" בתפריט ההקשר', (tester) async {
    await pumpArea(
      tester,
      text: 'טקסט לשיתוף',
      platform: TargetPlatform.windows,
    );
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll();
    await tester.pump();

    expect(find.text('שתף'), findsNothing);
    expect(share.shared, isEmpty);
  });

  testWidgets('בתוכן ספר מוגן שיתוף מעל המגבלה נחסם כמו העתקה', (tester) async {
    await pumpArea(
      tester,
      text: _lines(BookProtection.copySegmentLimit + 1),
      protection: () async => const BookProtection(level: 1),
    );
    await selectByLongPress(tester);

    expect(find.text('שתף'), findsOneWidget);
    await tester.tap(find.text('שתף'));
    await tester.pumpAndSettle();

    expect(share.shared, isEmpty);
  });

  testWidgets('בתוכן ספר מוגן שיתוף עד המגבלה מותר', (tester) async {
    final text = _lines(BookProtection.copySegmentLimit);
    await pumpArea(
      tester,
      text: text,
      protection: () async => const BookProtection(level: 1),
    );
    await selectByLongPress(tester);

    await tester.tap(find.text('שתף'));
    await tester.pumpAndSettle();

    expect(share.shared, [text]);
  });
}
