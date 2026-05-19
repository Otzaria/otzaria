import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ItemsListView(
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
        ),
      ),
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
}
