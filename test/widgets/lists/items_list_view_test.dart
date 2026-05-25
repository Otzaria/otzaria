import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';

class _Book {
  final String title;
  const _Book(this.title);
}

class _Item {
  final String ref;
  final String? workspaceName;
  const _Item(this.ref, {this.workspaceName});
  _Book get book => _Book(ref);
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
      onItemTap: onItemTap ?? (_, __, ___) {},
      onDelete: (_, __) {},
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
      child = Center(child: SizedBox(width: width, child: child));
    }
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

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

      await tester.pumpWidget(buildWidget(
        additionalFilter: (item) => item.workspaceName == 'גמרא',
      ));
      await tester.pump();

      expect(find.text('שבת עד:'), findsOneWidget);
      expect(find.text('ברכות ב.'), findsOneWidget);
      expect(find.text('הלכות שבת'), findsNothing);
    });

    testWidgets(
        'additionalFilter שמחזיר false לכל הפריטים מציג את הודעת המצב הריק '
        '(לא "לא נמצא")', (tester) async {
      // הסינון לא מטעמי חיפוש המשתמש, אלא בגלל שאין פריטים תואמים. לכן צריך
      // להציג את emptyText (למשל "אין סימניות בספר זה") ולא את notFoundText
      // שמיועד לחיפוש שלא הניב תוצאות.
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget(
        additionalFilter: (_) => false,
      ));
      await tester.pump();

      expect(find.text('ריק'), findsOneWidget);
      expect(find.text('לא נמצא'), findsNothing);
      expect(find.text('שבת עד:'), findsNothing);
      // ב-empty state אין שדה חיפוש או כפתור "נקה"
      expect(find.byType(TextField), findsNothing);
      expect(find.text('נקה'), findsNothing);
    });

    testWidgets(
        'additionalFilter משאיר פריטים אבל חיפוש לא מניב תוצאות - מציג "לא נמצא"',
        (tester) async {
      // וידוא ש-notFoundText עדיין מופיע כשהמשתמש מקליד חיפוש שאינו תואם, גם
      // בנוכחות additionalFilter.
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget(
        additionalFilter: (item) => item.workspaceName == 'גמרא',
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'אין-כזה-טקסט');
      await tester.pump();

      expect(find.text('לא נמצא'), findsOneWidget);
      expect(find.text('ריק'), findsNothing);
    });

    testWidgets('searchKeyBuilder מאפשר חיפוש לפי workspaceName',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget(
        searchKeyBuilder: (item) =>
            '${item.ref as String} ${item.workspaceName as String? ?? ''}',
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'הלכה');
      await tester.pump();

      expect(find.text('הלכות שבת'), findsOneWidget);
      expect(find.text('שבת עד:'), findsNothing);
      expect(find.text('ברכות ב.'), findsNothing);
    });

    testWidgets('ללא searchKeyBuilder - workspaceName לא נכלל בחיפוש',
        (tester) async {
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

    testWidgets('additionalFilter ו-searchKeyBuilder פועלים יחדיו',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget(
        additionalFilter: (item) => item.workspaceName == 'גמרא',
        searchKeyBuilder: (item) =>
            '${item.ref as String} ${item.workspaceName as String? ?? ''}',
      ));
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
              onItemTap: onItemTap ?? (_, __, ___) {},
              onDelete: (_, __) {},
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

      testWidgets('groupKeyBuilder מקבץ פריטים בכרטיסים נפרדים לפי מפתח',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildGrouped(
          testItems: items,
          groupKeyBuilder: (item) => (item as _Item).workspaceName,
        ));
        await tester.pump();

        // גמרא + הלכה = 2 קבוצות → 2 Card widgets
        expect(find.byType(AppCard), findsNWidgets(2));
        expect(find.text('שבת עד:'), findsOneWidget);
        expect(find.text('ברכות ב.'), findsOneWidget);
        expect(find.text('הלכות שבת'), findsOneWidget);
      });

      testWidgets('groupTitleBuilder מציג כותרת מעל כל קבוצה', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildGrouped(
          testItems: items,
          groupKeyBuilder: (item) => (item as _Item).workspaceName,
          groupTitleBuilder: (item) => (item as _Item).workspaceName,
        ));
        await tester.pump();

        expect(find.text('גמרא'), findsOneWidget);
        expect(find.text('הלכה'), findsOneWidget);
      });

      testWidgets('groupTitleBuilder שמחזיר null לא מציג כותרת',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildGrouped(
          testItems: items,
          groupKeyBuilder: (item) => (item as _Item).workspaceName,
          groupTitleBuilder: (_) => null,
        ));
        await tester.pump();

        expect(find.byType(AppCard), findsNWidgets(2));
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

        await tester.pumpWidget(buildGrouped(
          testItems: allGemara,
          groupKeyBuilder: (item) => (item as _Item).workspaceName,
        ));
        await tester.pump();

        expect(find.byType(AppCard), findsOneWidget);
      });
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

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ItemsListView(
              items: unsorted,
              onItemTap: (_, __, ___) {},
              onDelete: (_, __) {},
              onClearAll: (_) {},
              hintText: 'חיפוש',
              emptyText: 'ריק',
              notFoundText: 'לא נמצא',
              clearAllText: 'נקה',
              itemSortComparator: (a, b) =>
                  (a.ref as String).compareTo(b.ref as String),
            ),
          ),
        ));
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
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ItemsListView(
              items: unsorted,
              onItemTap: (_, __, i) => tappedIndex = i,
              onDelete: (_, __) {},
              onClearAll: (_) {},
              hintText: 'חיפוש',
              emptyText: 'ריק',
              notFoundText: 'לא נמצא',
              clearAllText: 'נקה',
              itemSortComparator: (a, b) =>
                  (a.ref as String).compareTo(b.ref as String),
            ),
          ),
        ));
        await tester.pump();

        // אחרי מיון: א-ראשון (originalIndex=1) מופיע ראשון
        await tester.tap(find.text('א-ראשון'));
        await tester.pump();

        expect(tappedIndex, 1,
            reason: 'originalIndex צריך להיות 1 (מיקום לפני מיון), לא 0');
      });
    });

    testWidgets(
        'onItemTap מקבל את originalIndex הנכון גם כשאותו אובייקט מופיע פעמיים',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final duplicate = _Item('כפול', workspaceName: 'בדיקה');
      int? tappedIndex;

      await tester.pumpWidget(buildWidget(
        testItems: [duplicate, duplicate, const _Item('אחר')],
        onItemTap: (_, __, originalIndex) => tappedIndex = originalIndex,
      ));
      await tester.pump();

      await tester.tap(find.text('כפול').last);
      await tester.pump();

      expect(tappedIndex, 1,
          reason:
              'כאשר אותו מופע מופיע יותר מפעם אחת, indexOf(item) תמיד מחזיר את ההופעה הראשונה. '
              'הווידג׳ט צריך לשמר את האינדקס המקורי של הרשומה שסוננה.');
    });
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

      await tester.pumpWidget(buildWidget(
        testItems: [const _Item(longRef)],
        subtitleBuilder: (_) => subtitleText,
      ));
      await tester.pump();

      final refBottom = tester.getBottomLeft(find.text(longRef)).dy;
      final subtitleTop = tester.getTopLeft(find.text(subtitleText)).dy;
      expect(subtitleTop, greaterThanOrEqualTo(refBottom),
          reason: 'גם במסך רחב subtitle מוצג מתחת ל-ref כדי שלא ייאסף לרוחב '
              'ויקצץ את ref לכמה שורות');
    });

    testWidgets('מסך צר: subtitle מתחת ל-ref (y גדול יותר)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget(
        testItems: [const _Item(longRef)],
        subtitleBuilder: (_) => subtitleText,
        width: 360,
      ));
      await tester.pump();

      final refBottom = tester.getBottomLeft(find.text(longRef)).dy;
      final subtitleTop = tester.getTopLeft(find.text(subtitleText)).dy;
      expect(subtitleTop, greaterThanOrEqualTo(refBottom),
          reason: 'subtitle צריך להופיע מתחת ל-ref בפריסת מסך צר');
    });

    testWidgets('מסך צר: ref ארוך תופס רוחב מלא ולא מתקפל לתו-לשורה',
        (tester) async {
      // בלי 2 השורות, מקום ה-Expanded של ref מצטמצם ל~30 פיקסל ועלול לקרוס.
      // אנו מוודאים שהוא מקבל לפחות 200 פיקסל רוחב.
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget(
        testItems: [const _Item(longRef)],
        subtitleBuilder: (_) => subtitleText,
        width: 360,
      ));
      await tester.pump();

      final refWidth = tester.getSize(find.text(longRef)).width;
      expect(refWidth, greaterThan(200),
          reason: 'במסך צר ל-ref צריך להיות רוחב סביר; בלי הפריסה הדו-שורתית '
              'ה-Row היה דוחס אותו לרוחב של תו אחד.');
    });

    testWidgets('מסך צר ללא subtitle: ref ממשיך להיות מוצג בשורה אחת',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildWidget(
        testItems: [const _Item(longRef)],
        // ללא subtitleBuilder אין שורה שנייה כלל
        width: 360,
      ));
      await tester.pump();

      expect(find.text(longRef), findsOneWidget);
      expect(find.text(subtitleText), findsNothing);
    });
  });
}
