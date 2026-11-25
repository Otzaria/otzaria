import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_result_rank_badge.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchResult, TextStatus;

/// מספר התוצאה יושב בשורת הכותרת של הכרטיס ולא בעמודה משלו: הקטע והכותרת
/// המשנית נפרשים לכל רוחב הכרטיס.
SearchResult _result({String title = 'בראשית'}) => SearchResult(
  id: BigInt.one,
  title: title,
  reference: 'בראשית, א',
  text: 'טקסט',
  segment: BigInt.one,
  isPdf: false,
  filePath: 'book.txt',
  mergedCount: 1,
  merged: const [],
  textStatus: TextStatus.ok,
  continuesToNextLine: false,
);

const _snippet = 'ויאמר משה אל העם אל תיראו התיצבו וראו את ישועת השם';

Widget _host({
  int rank = 7,
  String wrapped = 'תורה / בראשית',
  bool withSourceTag = false,
  double width = 600,
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: EngineResultCard(
            key: const Key('card'),
            result: _result(),
            rank: rank,
            titleText: 'בראשית',
            wrappedTitleText: wrapped,
            snippetSpans: const [TextSpan(text: _snippet)],
            externalSearchStatus: ValueNotifier(
              withSourceTag
                  ? const ExternalSearchStatus(
                      sourceTitle: 'היברובוקס',
                      loading: false,
                      books: 1,
                      hits: 1,
                    )
                  : null,
            ),
            groupingMode: ResultGroupingMode.none,
            onCopy: () {},
            onOpenSibling: (_) {},
            onOpenSiblingInBackground: (_) {},
            onPreviewSibling: null,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final width in [600.0, 320.0]) {
    testWidgets('המספר בשורת הכותרת והקטע לרוחב הכרטיס (רוחב $width)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(width: width));

      final card = tester.getRect(find.byKey(const Key('card')));
      final badge = tester.getRect(find.byType(SearchResultRankBadge));
      final title = tester.getRect(find.text('בראשית'));
      final wrapped = tester.getRect(find.text('תורה / בראשית'));
      final snippet = tester.getRect(
        find.textContaining('ויאמר', findRichText: true),
      );
      final padding = AppTokens.cardPadding.resolve(TextDirection.rtl);

      // המספר באותה שורה של הכותרת: אמצעו בתוך הרצועה האנכית שלה, ולא מתחת.
      expect(badge.center.dy, inInclusiveRange(title.top, title.bottom));
      expect(badge.bottom, lessThanOrEqualTo(wrapped.top));

      // אין עמודת מספר: הכותרת המשנית והקטע מתחילים בקצה אזור התוכן.
      expect(wrapped.right, closeTo(card.right - padding.right, 0.5));
      expect(snippet.right, closeTo(card.right - padding.right, 0.5));
      // והמספר עצמו בתחילת השורה, לפני הכותרת.
      expect(badge.right, closeTo(card.right - padding.right, 0.5));
      expect(title.right, lessThan(badge.left));
    });
  }

  testWidgets('מספר של שלוש ספרות ותגית מקור לא דוחקים את הכותרת מחוץ לשורה', (
    tester,
  ) async {
    await tester.pumpWidget(_host(rank: 128, withSourceTag: true, width: 320));

    expect(tester.takeException(), isNull);
    final badge = tester.getRect(find.byType(SearchResultRankBadge));
    expect(badge.height, lessThanOrEqualTo(AppTokens.iconLG));
    expect(find.text('128'), findsOneWidget);
  });

  testWidgets('בהגדלת טקסט התגית גדלה עם הספרה ולא גולשת', (tester) async {
    await tester.pumpWidget(_host(rank: 7, width: 600, textScale: 2));

    final badge = tester.getRect(find.byType(SearchResultRankBadge));
    final digitHeight = tester
        .renderObject<RenderParagraph>(find.text('7'))
        .getMaxIntrinsicHeight(double.infinity);
    expect(badge.height, greaterThanOrEqualTo(digitHeight));
    expect(tester.takeException(), isNull);
  });
}
