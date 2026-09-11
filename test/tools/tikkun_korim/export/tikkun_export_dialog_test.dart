import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_export_dialog.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';

void main() {
  /// פותח את הדיאלוג ומחזיר מחזיק לתוצאה שלו.
  Future<_Result> openDialog(
    WidgetTester tester, {
    int columnCount = 5,
    int currentColumn = 2,
    bool allowOriginalPages = true,
    Map<int, int>? verseDomain,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result.value = await showTikkunExportDialog(
                    context: context,
                    columnCount: columnCount,
                    currentColumn: currentColumn,
                    allowOriginalPages: allowOriginalPages,
                    verseDomain: verseDomain,
                  );
                  result.completed = true;
                },
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('ברירות המחדל — הטור הנוכחי, עמודים מקוריים, A4, שני הטורים', (
    tester,
  ) async {
    final result = await openDialog(tester);

    expect(find.text('ייצוא ל-PDF'), findsOneWidget);
    expect(find.text('מעמוד'), findsNothing);

    await tester.tap(find.text('ייצא'));
    await tester.pumpAndSettle();

    final options = result.value!;
    expect(options.scope, TikkunExportScope.currentColumn);
    expect(options.mode, TikkunExportMode.originalPages);
    expect(options.pageSize, TikkunExportPageSize.a4);
    expect(options.columns, TikkunExportColumns.both);
    expect(options.fromColumn, 2);
    expect(options.toColumn, 2);
  });

  testWidgets('בלי עמודי שיטה — אין בחירת עימוד והתוצאה בזרימה', (
    tester,
  ) async {
    final result = await openDialog(tester, allowOriginalPages: false);

    expect(find.text('עמודים מקוריים'), findsNothing);
    await tester.tap(find.text('ייצא'));
    await tester.pumpAndSettle();

    expect(result.value!.mode, TikkunExportMode.flow);
  });

  testWidgets('ביטול מחזיר null', (tester) async {
    final result = await openDialog(tester);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(result.completed, isTrue);
    expect(result.value, isNull);
  });

  testWidgets('בחירת מצב, גודל דף וטורים מוחזרת', (tester) async {
    final result = await openDialog(tester);

    await tester.tap(find.text('הכל'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('זרימה רציפה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('סת"ם בלבד'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ייצא'));
    await tester.pumpAndSettle();

    final options = result.value!;
    expect(options.scope, TikkunExportScope.all);
    expect(options.mode, TikkunExportMode.flow);
    expect(options.pageSize, TikkunExportPageSize.a5);
    expect(options.columns, TikkunExportColumns.stamOnly);
    expect(options.hideNikud, isTrue);
  });

  testWidgets('טווח עמודים — שדות הקלט נחתכים לגבולות', (tester) async {
    final result = await openDialog(tester);

    await tester.tap(find.text('טווח עמודים'));
    await tester.pumpAndSettle();
    expect(find.text('מתוך 5'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '2');
    await tester.enterText(find.byType(TextField).last, '99');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ייצא'));
    await tester.pumpAndSettle();

    final options = result.value!;
    expect(options.scope, TikkunExportScope.range);
    expect(options.fromColumn, 1);
    expect(options.toColumn, 4);
  });

  testWidgets('בלי תחום פסוקים אין אפשרות טווח פסוקים', (tester) async {
    await openDialog(tester);
    expect(find.text('טווח פסוקים'), findsNothing);
  });

  testWidgets('טווח פסוקים — ברירת המחדל מהפסוק הראשון עד האחרון', (
    tester,
  ) async {
    final result = await openDialog(tester, verseDomain: {1: 31, 2: 25});

    await tester.tap(find.text('טווח פסוקים'));
    await tester.pumpAndSettle();
    expect(find.text('מפרק'), findsOneWidget);
    expect(find.text('עד פרק'), findsOneWidget);

    await tester.tap(find.text('ייצא'));
    await tester.pumpAndSettle();

    final options = result.value!;
    expect(options.scope, TikkunExportScope.verseRange);
    expect((options.fromChapter, options.fromVerse), (1, 1));
    expect((options.toChapter, options.toVerse), (2, 25));
  });

  testWidgets('טור יחיד בלי פסוקים — אין בחירת היקף והתוצאה "הכל"', (
    tester,
  ) async {
    final result = await openDialog(tester, columnCount: 1);

    expect(find.text('היקף'), findsNothing);
    await tester.tap(find.text('ייצא'));
    await tester.pumpAndSettle();

    expect(result.value!.scope, TikkunExportScope.all);
  });
}

class _Result {
  TikkunExportOptions? value;
  bool completed = false;
}
