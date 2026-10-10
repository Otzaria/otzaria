import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/attached_libraries/view/external_link_index_tile.dart';
import 'package:otzaria/core/windowing/window_role.dart';

class _FakeLinks extends ExternalLinkRepository {
  final calls = <String>[];

  @override
  void cancelBuild() => calls.add('cancel');

  @override
  void requestResume(String slug) => calls.add('resume:$slug');

  @override
  void requestRebuild(String slug) => calls.add('rebuild:$slug');
}

AttachedLibrary _library({
  AttachedLibraryStatus status = AttachedLibraryStatus.ok,
  Set<AttachedLibraryCapability> capabilities = const {
    AttachedLibraryCapability.externalLinks,
  },
}) => AttachedLibrary(
  slug: 'dbA',
  displayName: 'dbA',
  path: 'C:/dbs/dbA.db',
  mode: AttachedLibraryMode.link,
  status: status,
  hidden: false,
  bookCount: 1,
  capabilities: capabilities,
  addedAt: DateTime(2026),
);

void main() {
  late _FakeLinks links;

  setUp(() => links = _FakeLinks());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: ExternalLinkIndexTile(slugs: const ['dbA'], links: links),
        ),
      ),
    ),
  );

  test('השורה מוצגת רק למסד תקין עם קישורים חיצוניים', () {
    expect(externalLinkLibraries([_library()]), hasLength(1));
    expect(externalLinkLibraries(const []), isEmpty);
    expect(
      externalLinkLibraries([_library(status: AttachedLibraryStatus.invalid)]),
      isEmpty,
    );
    expect(
      externalLinkLibraries([
        _library(capabilities: const {AttachedLibraryCapability.toc}),
      ]),
      isEmpty,
    );
  });

  testWidgets('חלון משני אינו מציג פקדי בניית אינדקס', (tester) async {
    final previousRole = WindowRole.isSecondary;
    addTearDown(() => WindowRole.isSecondary = previousRole);
    WindowRole.isSecondary = true;
    await pump(tester);
    expect(find.text('אינדקס קישורים'), findsNothing);
    expect(find.text('איפוס'), findsNothing);
    links.incompleteSlugs.value = {'dbA'};
    await tester.pump();
    expect(find.text('המשך בנייה'), findsNothing);
    expect(find.text('בנה מחדש'), findsNothing);
    expect(links.calls, isEmpty);
  });

  testWidgets('מעודכן כשאין בנייה', (tester) async {
    await pump(tester);
    expect(find.text('אינדקס קישורים'), findsOneWidget);
    expect(find.text('האינדקס מעודכן'), findsOneWidget);
    expect(find.text('עצור'), findsNothing);
  });

  testWidgets('איפוס במצב מוכן: ביטול אינו קורא ל-API, אישור בונה מחדש', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('איפוס'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(links.calls, isEmpty);

    await tester.tap(find.text('איפוס'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('בנה מחדש'));
    await tester.pumpAndSettle();
    expect(links.calls, ['rebuild:dbA']);
  });

  testWidgets('בזמן בנייה: התקדמות עם מפרידי אלפים וכפתור עצור', (
    tester,
  ) async {
    await pump(tester);
    links.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1520000, total: 2167384),
    };
    await tester.pump();
    expect(find.text('התקדמות האינדקס: 1,520,000/2,167,384'), findsOneWidget);
    expect(find.text('האינדקס מעודכן'), findsNothing);
    expect(find.text('עצור'), findsOneWidget);
  });

  testWidgets('עצירה: ביטול בדיאלוג אינו קורא ל-API, אישור כן', (tester) async {
    await pump(tester);
    links.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1, total: 2),
    };
    await tester.pump();

    await tester.tap(find.text('עצור'));
    await tester.pumpAndSettle();
    expect(find.text('האם לעצור את תהליך עדכון האינדקס?'), findsOneWidget);
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(links.calls, isEmpty);

    await tester.tap(find.text('עצור'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('עצור').last);
    await tester.pumpAndSettle();
    expect(links.calls, ['cancel']);
  });

  testWidgets('מסד שעבר את התקרה: הודעה בלי איפוס', (tester) async {
    links.tooLargeSlugs.value = {'dbA'};
    await pump(tester);
    expect(
      find.text('הקישורים החיצוניים לא נטענו — יותר מדי שורות'),
      findsOneWidget,
    );
    expect(find.text('האינדקס מעודכן'), findsNothing);
    expect(find.text('איפוס'), findsNothing);
  });

  testWidgets('לחיצה כפולה על איפוס שולחת בקשה אחת עד שהמצב משתנה', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('איפוס'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('בנה מחדש'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('איפוס'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('בנה מחדש'), findsNothing);
    expect(links.calls, ['rebuild:dbA']);

    links.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1, total: 2),
    };
    await tester.pump();
    expect(find.text('עצור'), findsOneWidget);
  });

  group('לא הושלם', () {
    setUp(() => links.incompleteSlugs.value = {'dbA', 'dbB'});

    testWidgets('המשך בנייה קורא ל-API בלי דיאלוג', (tester) async {
      await pump(tester);
      expect(find.text('אינדקס הקישורים לא הושלם'), findsOneWidget);
      await tester.tap(find.text('המשך בנייה'));
      await tester.pumpAndSettle();
      expect(links.calls, ['resume:dbA', 'resume:dbB']);
    });

    testWidgets('לחיצה כפולה על המשך בנייה שולחת בקשה אחת', (tester) async {
      await pump(tester);
      await tester.tap(find.text('המשך בנייה'));
      await tester.pump();
      await tester.tap(find.text('המשך בנייה'), warnIfMissed: false);
      await tester.pump();
      expect(links.calls, ['resume:dbA', 'resume:dbB']);
    });

    testWidgets('בנה מחדש: ביטול אינו קורא ל-API, אישור כן', (tester) async {
      await pump(tester);
      await tester.tap(find.text('בנה מחדש'));
      await tester.pumpAndSettle();
      expect(find.textContaining('בנייה מחדש מוחקת'), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(links.calls, isEmpty);

      await tester.tap(find.text('בנה מחדש'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('בנה מחדש').last);
      await tester.pumpAndSettle();
      expect(links.calls, ['rebuild:dbA', 'rebuild:dbB']);
    });
  });
}
