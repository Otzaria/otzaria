import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// תפריט ההקשר של מפרש/קישור מציג "מפרשים" ו"קישורים" של *קטע היעד* — מה
/// שיושב על אותה שורה בספר המפרש. הטסטים נועלים את חוט ההזרקה: בלי
/// `onNavigateToLink` התפריט חייב להישאר כשהיה (שלושת המשטחים חולקים אותו).
Link _link({
  String path2 = 'רש"י על שבת',
  int index2 = 5,
  String connectionType = LinkTypes.commentary,
}) {
  return Link(
    heRef: 'רש"י פסוק א',
    index1: 12,
    path2: path2,
    index2: index2,
    connectionType: connectionType,
    targetCategoryId: 3,
  );
}

class _MenuProbe extends StatelessWidget {
  const _MenuProbe({required this.onEntries, this.onNavigateToLink});

  final ValueChanged<List<AppContextMenuEntry>> onEntries;
  final void Function(Link)? onNavigateToLink;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onEntries(
        ContextMenuUtils.buildCommentaryContextMenu(
          context: context,
          link: _link(),
          openBookCallback: (_) {},
          fontSize: 16,
          removeNikud: false,
          removePunctuation: false,
          savedSelectedText: 'טקסט מסומן',
          onCopySelected: () {},
          onNavigateToLink: onNavigateToLink,
        ),
      ),
      child: const Text('פתח'),
    );
  }
}

void main() {
  tearDown(TargetLineLinksService.resetInstanceForTesting);

  Future<List<AppContextMenuEntry>> buildMenu(
    WidgetTester tester, {
    void Function(Link)? onNavigateToLink,
  }) async {
    List<AppContextMenuEntry>? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _MenuProbe(
            onEntries: (entries) => captured = entries,
            onNavigateToLink: onNavigateToLink,
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pump();
    return captured!;
  }

  group('הצגת הפריטים בתפריט', () {
    testWidgets('בלי onNavigateToLink התפריט נשאר כשהיה', (tester) async {
      final labels = (await buildMenu(tester)).map((e) => e.label);

      expect(labels, isNot(contains('מפרשים')));
      expect(labels, isNot(contains('קישורים')));
      expect(labels, contains('העתק'));
      expect(labels, contains('פתח ספר זה בחלון נפרד'));
    });

    testWidgets('עם onNavigateToLink נוספים שני הפריטים', (tester) async {
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [],
      );
      final labels = (await buildMenu(
        tester,
        onNavigateToLink: (_) {},
      )).map((e) => e.label).toList();

      expect(labels, contains('מפרשים'));
      expect(labels, contains('קישורים'));
    });

    testWidgets('הפריטים מופיעים אחרי ההעתקות ולפני פתיחת הספר', (
      tester,
    ) async {
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [],
      );
      final labels = (await buildMenu(
        tester,
        onNavigateToLink: (_) {},
      )).map((e) => e.label).toList();

      // indexOf מחזיר -1 לפריט חסר, ולכן קודם מוודאים שכולם קיימים — אחרת
      // ההשוואות היו עוברות דווקא כשהפריטים נעלמו.
      expect(labels, containsAll(<String>['מפרשים', 'קישורים']));
      expect(
        labels.indexOf('מפרשים'),
        greaterThan(labels.indexOf('העתק את כל הפסקה')),
      );
      expect(
        labels.indexOf('קישורים'),
        greaterThan(labels.indexOf('מפרשים')),
      );
      expect(
        labels.indexOf('קישורים'),
        lessThan(labels.indexOf('פתח ספר זה בחלון נפרד')),
      );
    });

    testWidgets('הפריטים הקיימים נשמרים לצד החדשים', (tester) async {
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [],
      );
      final labels = (await buildMenu(
        tester,
        onNavigateToLink: (_) {},
      )).map((e) => e.label);

      expect(labels, contains('העתק'));
      expect(labels, contains('העתק את כל הפסקה'));
      expect(labels, contains('פתח ספר זה בחלון נפרד'));
      expect(labels, contains('דווח על טעות בספר'));
    });
  });

  group('תוכן תתי-התפריטים', () {
    testWidgets('"מפרשים" מציג מפרשים על קטע היעד, "קישורים" את ההפניות', (
      tester,
    ) async {
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [
          _link(path2: 'מהרש"א', connectionType: LinkTypes.commentary),
          _link(path2: 'עין משפט', connectionType: LinkTypes.einMishpat),
        ],
      );
      TargetLineLinksService.instance.prefetch(_link());
      await tester.pumpAndSettle();

      final entries = await buildMenu(tester, onNavigateToLink: (_) {});
      final commentaries = entries.firstWhere((e) => e.label == 'מפרשים');
      final links = entries.firstWhere((e) => e.label == 'קישורים');

      expect(commentaries.childrenBuilder!().single.label, contains('מהרש"א'));
      expect(links.childrenBuilder!().single.label, contains('עין משפט'));
    });

    testWidgets('לחיצה על מפרש-של-מפרש מנווטת אליו', (tester) async {
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [
          _link(path2: 'מהרש"א', index2: 21),
        ],
      );
      TargetLineLinksService.instance.prefetch(_link());
      await tester.pumpAndSettle();

      Link? navigated;
      final entries = await buildMenu(
        tester,
        onNavigateToLink: (l) => navigated = l,
      );
      entries
          .firstWhere((e) => e.label == 'מפרשים')
          .childrenBuilder!()
          .single
          .onTap!();

      expect(navigated!.path2, 'מהרש"א');
      expect(navigated!.index2, 21);
    });

    testWidgets('לפריטי היעד יש תצוגה מקדימה ברפרוף', (tester) async {
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [_link(path2: 'מהרש"א')],
      );
      TargetLineLinksService.instance.prefetch(_link());
      await tester.pumpAndSettle();

      final entries = await buildMenu(tester, onNavigateToLink: (_) {});
      final child = entries
          .firstWhere((e) => e.label == 'מפרשים')
          .childrenBuilder!()
          .single;

      expect(child.hoverPreviewBuilder, isNotNull);
    });

    testWidgets('קטע בלי מפרשים מקבל פריט אפור', (tester) async {
      TargetLineLinksService.resetInstanceForTesting(
        loader: (_, _, _) async => [
          _link(path2: 'עין משפט', connectionType: LinkTypes.einMishpat),
        ],
      );
      TargetLineLinksService.instance.prefetch(_link());
      await tester.pumpAndSettle();

      final entries = await buildMenu(tester, onNavigateToLink: (_) {});

      expect(
        entries.firstWhere((e) => e.label == 'מפרשים').enabled,
        isFalse,
      );
      expect(
        entries.firstWhere((e) => e.label == 'קישורים').enabled,
        isTrue,
      );
    });
  });
}
