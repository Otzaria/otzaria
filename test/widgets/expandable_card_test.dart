import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// SizeTransition מסתיר ילדים דרך gizmo גודל (sizeFactor=0), לא מסיר מה-tree.
/// לכן בודקים את ה-sizeFactor ולא findsNothing.
double _sizeTransitionFactor(WidgetTester tester) {
  final st = tester.widget<SizeTransition>(find.byType(SizeTransition));
  return st.sizeFactor.value;
}

void main() {
  // ── ExpandableCard ────────────────────────────────────────────────────────

  group('ExpandableCard', () {
    testWidgets('מציג את ה-header תמיד', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            header: const Text('כותרת'),
            isExpanded: false,
          ),
        ),
      );
      expect(find.text('כותרת'), findsOneWidget);
    });

    testWidgets('כשסגור — sizeFactor הוא 0 (ילדים מוסתרים)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            header: const SizedBox(),
            isExpanded: false,
            children: const [Text('ילד')],
          ),
        ),
      );
      await tester.pump();
      expect(_sizeTransitionFactor(tester), 0.0);
    });

    testWidgets('כשפתוח — sizeFactor הוא 1 (ילדים גלויים)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            header: const SizedBox(),
            isExpanded: true,
            children: const [Text('ילד')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_sizeTransitionFactor(tester), 1.0);
      expect(find.text('ילד'), findsOneWidget);
    });

    testWidgets('מציג כמה ילדים בו-זמנית', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            header: const SizedBox(),
            isExpanded: true,
            children: const [Text('א'), Text('ב'), Text('ג')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('א'), findsOneWidget);
      expect(find.text('ב'), findsOneWidget);
      expect(find.text('ג'), findsOneWidget);
    });

    testWidgets('כשisExpanded משתנה ל-true, sizeFactor מגיע ל-1 אחרי אנימציה', (
      tester,
    ) async {
      bool expanded = false;
      late StateSetter setter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, s) {
                setter = s;
                return ExpandableCard(
                  header: const SizedBox(),
                  isExpanded: expanded,
                  children: const [Text('תוכן')],
                );
              },
            ),
          ),
        ),
      );

      expect(_sizeTransitionFactor(tester), 0.0);

      setter(() => expanded = true);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(_sizeTransitionFactor(tester), 1.0);
      expect(find.text('תוכן'), findsOneWidget);
    });

    testWidgets(
      'כשisExpanded משתנה ל-false, sizeFactor חוזר ל-0 אחרי אנימציה',
      (tester) async {
        bool expanded = true;
        late StateSetter setter;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (_, s) {
                  setter = s;
                  return ExpandableCard(
                    header: const SizedBox(),
                    isExpanded: expanded,
                    children: const [Text('תוכן')],
                  );
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(_sizeTransitionFactor(tester), 1.0);

        setter(() => expanded = false);
        await tester.pumpAndSettle();

        expect(_sizeTransitionFactor(tester), 0.0);
      },
    );

    testWidgets('כשchildren ריק — SizeTransition קיים', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            header: const Text('ריק'),
            isExpanded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SizeTransition), findsOneWidget);
    });

    testWidgets('margin מוחל כ-Padding סביב הכרטיס', (tester) async {
      const testMargin = EdgeInsets.symmetric(vertical: 8);
      final key = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            key: key,
            header: const SizedBox(),
            isExpanded: false,
            margin: testMargin,
          ),
        ),
      );
      final padding = tester
          .widgetList<Padding>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(Padding),
            ),
          )
          .firstWhere(
            (p) => p.padding == testMargin,
            orElse: () => throw 'לא נמצא Padding עם margin',
          );
      expect(padding.padding, testMargin);
    });

    testWidgets('ללא margin — אין Padding עם הגדרת המרג\'ן', (tester) async {
      const unexpectedMargin = EdgeInsets.symmetric(vertical: 8);
      final key = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            key: key,
            header: const SizedBox(),
            isExpanded: false,
          ),
        ),
      );
      final matchingPaddings = tester
          .widgetList<Padding>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(Padding),
            ),
          )
          .where((p) => p.padding == unexpectedMargin)
          .toList();
      expect(matchingPaddings, isEmpty);
    });

    testWidgets('מכיל SizeTransition לאנימציה', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            header: const SizedBox(),
            isExpanded: false,
            children: const [Text('x')],
          ),
        ),
      );
      expect(find.byType(SizeTransition), findsOneWidget);
    });

    testWidgets('wrapInCard:true — עוטף ב-Material עם ClipBehavior', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            key: key,
            header: const SizedBox(),
            isExpanded: false,
          ),
        ),
      );
      final materials = tester
          .widgetList<Material>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(Material),
            ),
          )
          .toList();
      expect(
        materials.any((m) => m.clipBehavior == Clip.antiAlias),
        isTrue,
      );
    });

    testWidgets('wrapInCard:false — אין Material חיצוני עם clipBehavior', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            key: key,
            header: const SizedBox(),
            isExpanded: false,
            wrapInCard: false,
          ),
        ),
      );
      final materials = tester
          .widgetList<Material>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(Material),
            ),
          )
          .toList();
      expect(
        materials.any((m) => m.clipBehavior == Clip.antiAlias),
        isFalse,
      );
    });

    testWidgets('N-1 מפרידים בין N ילדים כשפתוח', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExpandableCard(
            header: const SizedBox(),
            isExpanded: true,
            children: const [Text('א'), Text('ב'), Text('ג')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 3 ילדים → 2 מפרידים (Divider) בין הילדים + 1 מפריד ראשוני = 3 סה"כ
      expect(find.byType(Divider), findsNWidgets(3));
    });
  });
}
