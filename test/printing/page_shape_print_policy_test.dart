import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/page_shape_print_policy.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_plugin_api.dart';

void main() {
  PageShapeLayoutSnapshot layout({bool visible = true}) =>
      PageShapeLayoutSnapshot(
        available: ['מוגן', 'חופשי'],
        left: PageShapeCommentatorState(commentator: 'מוגן', visible: visible),
        right: const [],
        bottom: null,
        bottomRight: null,
      );
  final target = Link(
    heRef: 'ref',
    index1: 1,
    path2: 'מוגן.txt',
    index2: 1,
    targetBookId: 7,
    targetSource: BookSource.attached('extra'),
    connectionType: 'COMMENTARY',
  );

  test('ספר ראשי ברמה 2 עובר להדפסת מקור', () async {
    final policy = await resolvePageShapePrintPolicy(
      mainProtection: const BookProtection(level: 2),
      layout: layout(visible: false),
      availableCommentators: [],
      links: [],
    );
    expect(policy.useScreenshot, isFalse);
  });

  test('המפרש שמוצג בפועל נבדק במקור היעד שלו ומבטל צילום ברמה 2', () async {
    final policy = await resolvePageShapePrintPolicy(
      mainProtection: BookProtection.none,
      layout: layout(),
      availableCommentators: ['חופשי'],
      links: [target, target],
      titleProtectionResolver: (_) async =>
          throw StateError('must resolve the true linked target'),
      protectionResolver: (link) async {
        expect(link.targetSource, target.targetSource);
        expect(link.targetBookId, 7);
        return const BookProtection(level: 2);
      },
    );
    expect(policy.commentators, ['מוגן']);
    expect(policy.useScreenshot, isFalse);
  });

  test('מפרש מוסתר אינו מגביל צילום', () async {
    final policy = await resolvePageShapePrintPolicy(
      mainProtection: BookProtection.none,
      layout: layout(visible: false),
      availableCommentators: ['מוגן'],
      links: [target],
      protectionResolver: (_) async => throw StateError('hidden target'),
    );
    expect(policy.commentators, isEmpty);
    expect(policy.useScreenshot, isTrue);
  });

  test('רמה 1 מאפשרת צילום ושומרת את מגבלת הייצוא', () async {
    final policy = await resolvePageShapePrintPolicy(
      mainProtection: BookProtection.none,
      layout: layout(),
      availableCommentators: [],
      links: [target],
      protectionResolver: (_) async => const BookProtection(level: 1),
    );
    expect(policy.useScreenshot, isTrue);
    expect(policy.protection.allowsEditableExport, isFalse);
  });

  test('פריסה שטרם נטענה משתמשת במסלול שורות המקור', () async {
    final policy = await resolvePageShapePrintPolicy(
      mainProtection: BookProtection.none,
      layout: null,
      availableCommentators: [],
      links: [],
    );
    expect(policy.useScreenshot, isFalse);
  });
}
