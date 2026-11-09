import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

class _Book {
  final String title;
  const _Book(this.title);
}

class _Item {
  final String ref;
  final String? workspaceName;
  final String? title;
  const _Item(this.ref, {this.workspaceName, this.title});
  _Book get book => _Book(title ?? ref);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const items = [
    _Item('שבת עד:', workspaceName: 'גמרא'),
    _Item('ברכות ב.', workspaceName: 'גמרא'),
    _Item('הלכות שבת', workspaceName: 'הלכה'),
  ];

  Widget buildWidget({
    List<dynamic> testItems = items,
    bool Function(dynamic)? additionalFilter,
    String Function(dynamic)? searchKeyBuilder,
    void Function(BuildContext, dynamic, int)? onItemTap,
    String? Function(dynamic)? subtitleBuilder,
    double? width,
  }) {
    Widget child = ItemsListView(
      items: testItems,
      onItemTap: onItemTap ?? (_, _, _) {},
      onDelete: (_, _) {},
      onClearAll: (_) {},
      hintText: 'חיפוש...',
      emptyText: 'ריק',
      notFoundText: 'לא נמצא',
      clearAllText: 'נקה',
      additionalFilter: additionalFilter,
      searchKeyBuilder: searchKeyBuilder,
      subtitleBuilder: subtitleBuilder,
    );
    if (width != null) {
      child = Center(
        child: SizedBox(width: width, child: child),
      );
    }
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  /// שורת "תחילת קבוצה" — ClipRRect עם פינות עליונות מעוגלות שעוטף Material
  /// של שורת כרטיס. שקול לספירת כרטיסי קבוצה במבנה הווירטואלי.
  Finder groupStarts() => find.byWidgetPredicate(
    (w) =>
        w is ClipRRect &&
        w.borderRadius is BorderRadius &&
        (w.borderRadius as BorderRadius).topLeft != Radius.zero &&
        (w.child is Material || w.child is ValueListenableBuilder<int>),
  );

  group('ItemsListView', () {
    testWidgets('מציג את כל הפריטים כשאין additionalFilter', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsOneWidget);
    });

    testWidgets('additionalFilter מסנן פריטים לפי תנאי', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildWidget(
          additionalFilter: (item) => item.workspaceName == 'גמרא',
        ),
      );
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsNothing);
    });

    testWidgets(
      'additionalFilter שמחזיר false לכל הפריטים מציג את הודעת המצב הריק '
      '(לא "לא נמצא")',
      (tester) async {
        // הסינון לא מטעמי חיפוש המשתמש, אלא בגלל שאין פריטים תואמים. לכן צריך
        // להציג את emptyText (למשל "אין סימניות בספר זה") ולא את notFoundText
        // שמיועד לחיפוש שלא הניב תוצאות.
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildWidget(
            additionalFilter: (_) => false,
          ),
        );
        await tester.pump();

        expect(find.text('ריק'), findsOneWidget);
        expect(find.text('לא נמצא'), findsNothing);
        expect(find.text('שבת עד:'), findsNothing);
        // ב-empty state אין שדה חיפוש או כפתור "נקה"
        expect(find.byType(TextField), findsNothing);
        expect(find.text('נקה'), findsNothing);
      },
    );

    testWidgets(
      'additionalFilter משאיר פריטים אבל חיפוש לא מניב תוצאות - מציג "לא נמצא"',
      (tester) async {
        // וידוא ש-notFoundText עדיין מופיע כשהמשתמש מקליד חיפוש שאינו תואם, גם
        // בנוכחות additionalFilter.
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildWidget(
            additionalFilter: (item) => item.workspaceName == 'גמרא',
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextField).first, 'אין-כזה-טקסט');
        await tester.pump();

        expect(find.text('לא נמצא'), findsOneWidget);
        expect(find.text('ריק'), findsNothing);
      },
    );

    testWidgets('searchKeyBuilder מאפשר חיפוש לפי workspaceName', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildWidget(
          searchKeyBuilder: (item) =>
              '${item.ref as String} ${item.workspaceName as String? ?? ''}',
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'הלכה');
      await tester.pump();

      expect(find.text('הלכות שבת'), findsOneWidget);
      expect(find.text('שבת עד:'), findsNothing);
      expect(find.text('ברכות ב.'), findsNothing);
    });

    testWidgets('ללא searchKeyBuilder - workspaceName לא נכלל בחיפוש', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      // 'גמרא' מופיע רק ב-workspaceName, לא ב-ref
      await tester.enterText(find.byType(TextField).first, 'גמרא');
      await tester.pump();

      expect(find.text('לא נמצא'), findsOneWidget);
      expect(find.text('שבת עד:'), findsNothing);
      expect(find.text('ברכות ב.'), findsNothing);
    });

    testWidgets('additionalFilter ו-searchKeyBuilder פועלים יחדיו', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildWidget(
          additionalFilter: (item) => item.workspaceName == 'גמרא',
          searchKeyBuilder: (item) =>
              '${item.ref as String} ${item.workspaceName as String? ?? ''}',
        ),
      );
      await tester.pump();

      // additionalFilter לגמרא בלבד
      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsNothing);

      // חיפוש טקסט על גבי הסינון
      await tester.enterText(find.byType(TextField).first, 'שבת');
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsNothing);
      expect(find.text('הלכות שבת'), findsNothing);
    });

    group('groupKeyBuilder ו-groupTitleBuilder', () {
      Widget buildGrouped({
        required List<_Item> testItems,
        String? Function(dynamic)? groupKeyBuilder,
        String? Function(dynamic)? groupTitleBuilder,
        Comparator<dynamic>? itemSortComparator,
        void Function(BuildContext, dynamic, int)? onItemTap,
      }) {
        return MaterialApp(
          home: Scaffold(
            body: ItemsListView(
              items: testItems,
              onItemTap: onItemTap ?? (_, _, _) {},
              onDelete: (_, _) {},
              onClearAll: (_) {},
              hintText: 'חיפוש',
              emptyText: 'ריק',
              notFoundText: 'לא נמצא',
              clearAllText: 'נקה',
              groupKeyBuilder: groupKeyBuilder,
              groupTitleBuilder: groupTitleBuilder,
              itemSortComparator: itemSortComparator,
            ),
          ),
        );
      }

      testWidgets('groupKeyBuilder מקבץ פריטים בכרטיסים נפרדים לפי מפתח', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildGrouped(
            testItems: items,
            groupKeyBuilder: (item) => (item as _Item).workspaceName,
          ),
        );
        await tester.pump();

        // גמרא + הלכה = 2 קבוצות → 2 תחילות-כרטיס
        expect(groupStarts(), findsNWidgets(2));
        expect(find.text('שבת עד:'), findsOneWidget);
        expect(find.text('ברכות ב.'), findsOneWidget);
        expect(find.text('הלכות שבת'), findsOneWidget);
      });

      testWidgets('groupTitleBuilder מציג כותרת מעל כל קבוצה', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildGrouped(
            testItems: items,
            groupKeyBuilder: (item) => (item as _Item).workspaceName,
            groupTitleBuilder: (item) => (item as _Item).workspaceName,
          ),
        );
        await tester.pump();

        expect(find.text('גמרא'), findsOneWidget);
        expect(find.text('הלכה'), findsOneWidget);
      });

      testWidgets('groupTitleBuilder שמחזיר null לא מציג כותרת', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildGrouped(
            testItems: items,
            groupKeyBuilder: (item) => (item as _Item).workspaceName,
            groupTitleBuilder: (_) => null,
          ),
        );
        await tester.pump();

        expect(groupStarts(), findsNWidgets(2));
        expect(find.text('גמרא'), findsNothing);
        expect(find.text('הלכה'), findsNothing);
      });

      testWidgets('פריטים עם אותו groupKey מקובצים לכרטיס אחד', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // 3 פריטים לאותה קבוצה → כרטיס אחד
        const allGemara = [
          _Item('שבת עד:', workspaceName: 'גמרא'),
          _Item('ברכות ב.', workspaceName: 'גמרא'),
          _Item('ברכות ג.', workspaceName: 'גמרא'),
        ];

        await tester.pumpWidget(
          buildGrouped(
            testItems: allGemara,
            groupKeyBuilder: (item) => (item as _Item).workspaceName,
          ),
        );
        await tester.pump();

        expect(groupStarts(), findsOneWidget);
      });

      // q12 שאלה 9 C (DD-11): כרטיס בהיר לכל קבוצה, כמו ב-upstream. השורות על
      // רקע AppSurfaces.card, והרווח ביניהן מראה את המשטח שמתחת (בלי קו).
      testWidgets('כל שורה על רקע הכרטיס, בלי קו בין השורות', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildGrouped(
            testItems: items,
            groupKeyBuilder: (item) => (item as _Item).workspaceName,
          ),
        );
        await tester.pump();

        final card = AppSurfaces.card(
          tester.element(find.byType(ItemsListView)),
        );
        for (final title in ['שבת עד:', 'ברכות ב.', 'הלכות שבת']) {
          final row = tester.widget<Material>(
            find
                .ancestor(of: find.text(title), matching: find.byType(Material))
                .first,
          );
          expect(row.color, card, reason: title);
        }
        expect(find.byType(Divider), findsNothing);
      });

      // הכרטיס בהיר מגוף דיאלוג ההיסטוריה והסימניות בשתי הערכות, כמו ב-upstream
      // (הערת בעל הפרויקט 4.11).
      for (final brightness in Brightness.values) {
        testWidgets('הכרטיס בהיר מגוף הדיאלוג: ${brightness.name}', (
          tester,
        ) async {
          late Color card;
          late Color body;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.brown,
                  brightness: brightness,
                ),
              ),
              home: Builder(
                builder: (context) {
                  card = AppSurfaces.card(context);
                  body = AppSurfaces.cardDialogBackground(context);
                  return const SizedBox();
                },
              ),
            ),
          );
          expect(
            card.computeLuminance(),
            greaterThan(body.computeLuminance()),
          );
        });
      }
    });

    group('itemSortComparator', () {
      testWidgets('ממיין פריטים לפי הקריטריון לפני הצגה', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const unsorted = [
          _Item('ג-שלישי'),
          _Item('א-ראשון'),
          _Item('ב-שני'),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ItemsListView(
                items: unsorted,
                onItemTap: (_, _, _) {},
                onDelete: (_, _) {},
                onClearAll: (_) {},
                hintText: 'חיפוש',
                emptyText: 'ריק',
                notFoundText: 'לא נמצא',
                clearAllText: 'נקה',
                itemSortComparator: (a, b) =>
                    (a.ref as String).compareTo(b.ref as String),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('א-ראשון'), findsOneWidget);
        expect(find.text('ב-שני'), findsOneWidget);
        expect(find.text('ג-שלישי'), findsOneWidget);
      });

      testWidgets('שומר את originalIndex אחרי מיון', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // לפני מיון: index 0='ג', 1='א', 2='ב'
        const unsorted = [
          _Item('ג-שלישי'),
          _Item('א-ראשון'),
          _Item('ב-שני'),
        ];

        int? tappedIndex;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ItemsListView(
                items: unsorted,
                onItemTap: (_, _, i) => tappedIndex = i,
                onDelete: (_, _) {},
                onClearAll: (_) {},
                hintText: 'חיפוש',
                emptyText: 'ריק',
                notFoundText: 'לא נמצא',
                clearAllText: 'נקה',
                itemSortComparator: (a, b) =>
                    (a.ref as String).compareTo(b.ref as String),
              ),
            ),
          ),
        );
        await tester.pump();

        // אחרי מיון: א-ראשון (originalIndex=1) מופיע ראשון
        await tester.tap(find.text('א-ראשון'));
        await tester.pump();

        expect(
          tappedIndex,
          1,
          reason: 'originalIndex צריך להיות 1 (מיקום לפני מיון), לא 0',
        );
      });
    });

    testWidgets(
      'onItemTap מקבל את originalIndex הנכון גם כשאותו אובייקט מופיע פעמיים',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final duplicate = _Item('כפול', workspaceName: 'בדיקה');
        int? tappedIndex;

        await tester.pumpWidget(
          buildWidget(
            testItems: [duplicate, duplicate, const _Item('אחר')],
            onItemTap: (_, _, originalIndex) => tappedIndex = originalIndex,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('כפול').last);
        await tester.pump();

        expect(
          tappedIndex,
          1,
          reason:
              'כאשר אותו מופע מופיע יותר מפעם אחת, indexOf(item) תמיד מחזיר את ההופעה הראשונה. '
              'הווידג׳ט צריך לשמר את האינדקס המקורי של הרשומה שסוננה.',
        );
      },
    );
  });

  group('ItemsListView — פריסת ref ו-subtitle', () {
    // ref ו-subtitle מוצגים זה מתחת לזה (Column) בכל גודל מסך — בלי זה,
    // ב-Row(ref|subtitle|delete) ה-subtitle בלי הגבלת רוחב חוטף את כל המקום
    // של ref וטקסט ארוך מתקפל לתו-לשורה.
    const longRef = 'חזון איש, יורה דעה, סימן יב, סעיף ג';
    const subtitleText = 'שולחן עבודה 1';

    testWidgets('מסך רחב: subtitle מתחת ל-ref (Column)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildWidget(
          testItems: [const _Item(longRef)],
          subtitleBuilder: (_) => subtitleText,
        ),
      );
      await tester.pump();

      final refBottom = tester.getBottomLeft(find.text(longRef)).dy;
      final subtitleTop = tester.getTopLeft(find.text(subtitleText)).dy;
      expect(
        subtitleTop,
        greaterThanOrEqualTo(refBottom),
        reason:
            'גם במסך רחב subtitle מוצג מתחת ל-ref כדי שלא ייאסף לרוחב '
            'ויקצץ את ref לכמה שורות',
      );
    });

    testWidgets('מסך צר: subtitle מתחת ל-ref (y גדול יותר)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildWidget(
          testItems: [const _Item(longRef)],
          subtitleBuilder: (_) => subtitleText,
          width: 360,
        ),
      );
      await tester.pump();

      final refBottom = tester.getBottomLeft(find.text(longRef)).dy;
      final subtitleTop = tester.getTopLeft(find.text(subtitleText)).dy;
      expect(
        subtitleTop,
        greaterThanOrEqualTo(refBottom),
        reason: 'subtitle צריך להופיע מתחת ל-ref בפריסת מסך צר',
      );
    });

    testWidgets('מסך צר: ref ארוך תופס רוחב מלא ולא מתקפל לתו-לשורה', (
      tester,
    ) async {
      // בלי 2 השורות, מקום ה-Expanded של ref מצטמצם ל~30 פיקסל ועלול לקרוס.
      // אנו מוודאים שהוא מקבל לפחות 200 פיקסל רוחב.
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildWidget(
          testItems: [const _Item(longRef)],
          subtitleBuilder: (_) => subtitleText,
          width: 360,
        ),
      );
      await tester.pump();

      final refWidth = tester.getSize(find.text(longRef)).width;
      expect(
        refWidth,
        greaterThan(200),
        reason:
            'במסך צר ל-ref צריך להיות רוחב סביר; בלי הפריסה הדו-שורתית '
            'ה-Row היה דוחס אותו לרוחב של תו אחד.',
      );
    });

    testWidgets('מסך צר ללא subtitle: ref ממשיך להיות מוצג בשורה אחת', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildWidget(
          testItems: [const _Item(longRef)],
          // ללא subtitleBuilder אין שורה שנייה כלל
          width: 360,
        ),
      );
      await tester.pump();

      expect(find.text(longRef), findsOneWidget);
      expect(find.text(subtitleText), findsNothing);
    });
  });

  group('ItemsListView — חיפוש גמיש ודירוג', () {
    Widget buildSearchable(
      List<dynamic> testItems, {
      bool grouped = false,
      bool groupWhileSearching = true,
      List<String>? Function(dynamic)? aliases,
      void Function(int originalIndex)? onTap,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ItemsListView(
            items: testItems,
            onItemTap: (_, _, index) => onTap?.call(index),
            onDelete: (_, _) {},
            onClearAll: (_) {},
            hintText: 'חיפוש...',
            emptyText: 'ריק',
            notFoundText: 'לא נמצא',
            clearAllText: 'נקה',
            groupKeyBuilder: grouped
                ? (item) => (item as _Item).workspaceName
                : null,
            groupTitleBuilder: grouped
                ? (item) => 'קבוצה ${(item as _Item).workspaceName}'
                : null,
            groupWhileSearching: groupWhileSearching,
            searchAliasesBuilder: aliases,
            searchTitleBuilder: (item) => (item as _Item).book.title,
          ),
        ),
      );
    }

    double y(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    Future<void> search(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
    }

    const ranked = [
      _Item('משנה ברכות א', workspaceName: 'א'),
      _Item('ברכות ב', workspaceName: 'ב'),
      _Item('שבת ב', workspaceName: 'א'),
    ];

    testWidgets('כתיב חלופי בכותרת בלבד ומילולי לפניו', (tester) async {
      await tester.pumpWidget(
        buildSearchable(const [
          _Item('שורש א'),
          _Item('ספר השרש א'),
          _Item('משנה תורה הלכות שורש', title: 'משנה תורה'),
        ]),
      );
      await search(tester, 'שרש');
      expect(find.text('משנה תורה הלכות שורש'), findsNothing);
      expect(y(tester, 'ספר השרש א'), lessThan(y(tester, 'שורש א')));
    });

    testWidgets('מפתחות מתעדכנים כשה-builder משתנה עם אותה רשימה', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget(searchKeyBuilder: (_) => 'ראשון'));
      await search(tester, 'ראשון');
      expect(find.text('שבת עד:'), findsOneWidget);
      await tester.pumpWidget(buildWidget(searchKeyBuilder: (_) => 'שני'));
      await tester.pump();
      expect(find.text('שבת עד:'), findsNothing);
      await search(tester, 'שני');
      expect(find.text('שבת עד:'), findsOneWidget);
    });

    testWidgets('כינויים שנוספו והוסרו מתעדכנים בלי להחליף items', (
      tester,
    ) async {
      List<String>? aliases;
      Widget build() => buildSearchable(ranked, aliases: (_) => aliases);
      await tester.pumpWidget(build());
      await search(tester, 'כינוי');
      expect(find.text('ברכות ב'), findsNothing);
      aliases = ['כינוי'];
      await tester.pumpWidget(build());
      await tester.pump();
      expect(find.text('ברכות ב'), findsOneWidget);
      aliases.clear();
      await tester.pumpWidget(build());
      await tester.pump();
      expect(find.text('ברכות ב'), findsNothing);
    });

    testWidgets('שאילתה ריקה — סדר הקלט וכותרות הקבוצות', (tester) async {
      await tester.pumpWidget(buildSearchable(ranked, grouped: true));
      await tester.pump();

      expect(y(tester, 'משנה ברכות א'), lessThan(y(tester, 'ברכות ב')));
      expect(find.text('קבוצה א'), findsOneWidget);
      expect(find.text('קבוצה ב'), findsOneWidget);
    });

    testWidgets('התאמה מתחילת המפתח מעל פריט חדש יותר', (tester) async {
      await tester.pumpWidget(buildSearchable(ranked));
      await search(tester, 'ברכות');

      expect(y(tester, 'ברכות ב'), lessThan(y(tester, 'משנה ברכות א')));
      expect(find.text('שבת ב'), findsNothing);
    });

    testWidgets('שוויון בדרגה — הסדר המקורי נשמר', (tester) async {
      await tester.pumpWidget(
        buildSearchable(const [_Item('ברכות ג'), _Item('ברכות ב')]),
      );
      await search(tester, 'ברכות');

      expect(y(tester, 'ברכות ג'), lessThan(y(tester, 'ברכות ב')));
    });

    testWidgets('groupWhileSearching: false מסתיר כותרות בזמן חיפוש בלבד', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSearchable(ranked, grouped: true, groupWhileSearching: false),
      );
      await tester.pump();
      expect(find.text('קבוצה א'), findsOneWidget);

      await search(tester, 'ברכות');
      expect(find.text('קבוצה א'), findsNothing);
      expect(find.text('קבוצה ב'), findsNothing);
      expect(y(tester, 'ברכות ב'), lessThan(y(tester, 'משנה ברכות א')));

      await search(tester, '');
      expect(find.text('קבוצה א'), findsOneWidget);
      expect(y(tester, 'משנה ברכות א'), lessThan(y(tester, 'ברכות ב')));
    });

    testWidgets('חצים ו-Enter עוברים לפי הסדר החזותי', (tester) async {
      int? tapped;
      // הדירוג: 0, 1, 2; הקיבוץ מציג 0, 2 (קבוצה א) ואז 1.
      await tester.pumpWidget(
        buildSearchable(
          const [
            _Item('ברכות ב', workspaceName: 'א'),
            _Item('ברכות ג', workspaceName: 'ב'),
            _Item('משנה ברכות', workspaceName: 'א'),
          ],
          grouped: true,
          onTap: (index) => tapped = index,
        ),
      );
      await tester.pump();
      await search(tester, 'ברכות');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, 2);
    });

    testWidgets('Down באחרונה מחזיר אותה לתצוגה גם כשהמסך במנוחה', (
      tester,
    ) async {
      EditableText.debugDeterministicCursor = true;
      addTearDown(() => EditableText.debugDeterministicCursor = false);
      int? tapped;
      await tester.pumpWidget(
        buildSearchable(
          List.generate(20, (index) => _Item('ספר $index')),
          onTap: (index) => tapped = index,
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 20; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tapped, 19);

      // גלילה בלי שינוי הבחירה או איבוד המיקוד בשדה החיפוש.
      final list = tester.widget<ScrollablePositionedList>(
        find.byType(ScrollablePositionedList),
      );
      list.itemScrollController!.jumpTo(index: 0);
      await tester.pumpAndSettle();
      // ממתינים לסיום הבהוב הסמן, כדי שרק הניווט יוכל לתזמן פריים
      // שיריץ את בדיקת הנראות.
      for (var tick = 0; tick < 20; tick++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(find.text('ספר 19').hitTestable(), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('ספר 19').hitTestable(), findsOneWidget);
      tapped = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tapped, 19);
    });

    testWidgets('סינון שמסיר את הבחירה מאפס אותה ומאפשר ניווט מחדש', (
      tester,
    ) async {
      int? tapped;
      Widget build({bool filtered = false}) => buildWidget(
        additionalFilter: filtered ? (item) => item.ref != 'הלכות שבת' : null,
        onItemTap: (_, _, index) => tapped = index,
      );
      await tester.pumpWidget(build());
      await tester.pump();
      for (var index = 0; index < 3; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tapped, 2);

      await tester.pumpWidget(build(filtered: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      tapped = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tapped, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(tapped, 0);
    });

    testWidgets('חצי מקלדת לא מריצים מחדש סינון ומפתחות חיפוש', (
      tester,
    ) async {
      var filterCalls = 0;
      var searchKeyCalls = 0;
      var subtitleCalls = 0;
      final manyItems = List<dynamic>.generate(
        80,
        (index) => _Item('ספר $index', workspaceName: 'קבוצה'),
      );

      await tester.pumpWidget(
        buildWidget(
          testItems: manyItems,
          additionalFilter: (_) {
            filterCalls++;
            return true;
          },
          searchKeyBuilder: (item) {
            searchKeyCalls++;
            return (item as _Item).ref;
          },
          subtitleBuilder: (_) {
            subtitleCalls++;
            return 'תיאור';
          },
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'ספר');
      await tester.pump();

      final filterCallsBeforeArrows = filterCalls;
      final searchKeyCallsBeforeArrows = searchKeyCalls;
      final subtitleCallsBeforeArrows = subtitleCalls;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(filterCalls, filterCallsBeforeArrows);
      expect(searchKeyCalls, searchKeyCallsBeforeArrows);
      expect(subtitleCalls, subtitleCallsBeforeArrows);
    });

    testWidgets('Enter אחרי חץ ראשון פותח את התוצאה העליונה', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        buildSearchable(
          ranked,
          grouped: true,
          groupWhileSearching: false,
          onTap: (index) => tapped = index,
        ),
      );
      await tester.pump();
      await search(tester, 'ברכות');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('פריט נמצא לפי כינוי, מתחת להתאמה מילולית', (tester) async {
      await tester.pumpWidget(
        buildSearchable(
          const [_Item('משנה תורה הלכות שבת'), _Item('רמבם על המשנה')],
          aliases: (item) =>
              (item as _Item).ref.startsWith('משנה תורה') ? ['רמבם'] : null,
        ),
      );
      await search(tester, 'רמבם');

      expect(find.text('משנה תורה הלכות שבת'), findsOneWidget);
      expect(
        y(tester, 'רמבם על המשנה'),
        lessThan(y(tester, 'משנה תורה הלכות שבת')),
      );
    });
  });
}
