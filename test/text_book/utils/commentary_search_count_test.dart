import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

import '../../support/search_engine_test_init.dart';

/// issue #1055 — מונה התאמות החיפוש במפרשים ספר מילים שלמות בעוד ההדגשה
/// חלקית: "אמר" נצבע בתוך "ויאמר" אך לא נספר. המונה חייב לקבל את אותו
/// דגל [partialWordMatch] שמגיע ל-RenderSettings.partialWordHighlight.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('countMatches — partialWordMatch (issue #1055)', () {
    test(
      'ברירת המחדל נשארת מילים שלמות — ההתנהגות הקיימת לא השתנתה',
      () {
        expect(utils.countMatches('ויאמר משה', 'אמר'), 0);
        expect(utils.countMatches('אמר רבי', 'אמר'), 1);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'עם הדגל — הופעה בתוך מילה נספרת, כמו שהיא נצבעת',
      () {
        expect(
          utils.countMatches('ויאמר משה', 'אמר', partialWordMatch: true),
          1,
        );
        expect(
          utils.countMatches('אמר ויאמר ונאמר', 'אמר', partialWordMatch: true),
          3,
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });

  group('countCommentarySearchMatches — תואם את ההדגשה', () {
    test(
      'מפרש שמרונדר בהתאמה חלקית — המונה סופר גם הופעות בתוך מילה',
      () {
        expect(
          countCommentarySearchMatches(
            content: 'וַיֹּאמֶר משה אמר',
            query: 'אמר',
            displayProfile: TextDisplayProfile.defaults,
            partialWordMatch: true,
          ),
          2,
        );
        // אותו תוכן בספירת מילים-שלמות — רק ההופעה העצמאית.
        expect(
          countCommentarySearchMatches(
            content: 'וַיֹּאמֶר משה אמר',
            query: 'אמר',
            displayProfile: TextDisplayProfile.defaults,
            partialWordMatch: false,
          ),
          1,
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });

  final cases = [
    (
      name: 'מאפיין HTML אינו יעד',
      content: '<span title="אמר" style="color:red">אמר</span>',
      query: 'אמר',
      needle: 'אמר',
      index: 0,
    ),
    (
      name: 'ניקוד ותוכן עשיר',
      content:
          'אמר ${List.filled(80, 'מִילָה &amp;').join(' ')} <b><i>אמר</i></b> סוף',
      query: 'אמר',
      needle: 'אמר',
      index: 1,
    ),
    (
      name: 'ביטוי של כמה מילים',
      content: 'אמר רבי ${List.filled(80, 'מילה').join(' ')} אמר רבי סוף',
      query: 'אמר רבי',
      needle: 'אמר רבי',
      index: 1,
    ),
    (
      name: 'regex מנוע',
      content: 'משה ${List.filled(80, 'מילה').join(' ')} מושה',
      query: '/מו?שה/',
      needle: 'מושה',
      index: 1,
    ),
  ];
  for (final data in cases) {
    testWidgets('יעד מדוד בגוף בלבד: ${data.name}', (tester) async {
      final itemKey = GlobalKey();
      final bodyKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                key: itemKey,
                children: [
                  const Text('אמר רבי בכותרת שאינה חלק מגוף החיפוש'),
                  SizedBox(
                    key: bodyKey,
                    width: 100,
                    child: SmartTextWidget(
                      text: data.content,
                      settings: RenderSettings.fromProfile(
                        TextDisplayProfile.defaults,
                        searchText: data.query,
                        currentSearchIndex: data.index,
                        fontSize: 18,
                        partialWordHighlight: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final item = tester.renderObject<RenderBox>(find.byKey(itemKey));
      final body = tester.renderObject<RenderBox>(find.byKey(bodyKey));
      final paragraph = tester
          .renderObjectList<RenderParagraph>(
            find.descendant(
              of: find.byKey(bodyKey),
              matching: find.byType(RichText),
            ),
          )
          .firstWhere((p) => p.text.toPlainText().contains(data.needle));
      final text = paragraph.text.toPlainText();
      final offset = text.lastIndexOf(data.needle);
      final glyph = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: offset,
              extentOffset: offset + data.needle.length,
            ),
          )
          .first
          .toRect();
      final expected = paragraph
          .localToGlobal(glyph.topLeft, ancestor: item)
          .dy;
      final target = commentarySearchMatchTarget(
        content: data.content,
        query: data.query,
        displayProfile: TextDisplayProfile.defaults,
        matchIndex: data.index,
        renderedBody: () => body,
      );
      expect(target?.call(0, item)?.top, closeTo(expected, 0.001));
    }, skip: !engineReady);
  }

  testWidgets('WidgetSpan שאינו ניתן למיפוי נשאר בראש הפריט', (tester) async {
    final key = GlobalKey();
    const content = 'אמר <sup class="custom">אמר</sup>';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(
          body: SizedBox(
            key: key,
            child: const SmartTextWidget(
              text: content,
              settings: RenderSettings(fontSize: 18),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    final target = commentarySearchMatchTarget(
      content: content,
      query: 'אמר',
      displayProfile: TextDisplayProfile.defaults,
      matchIndex: 1,
    );
    expect(target, isNotNull);
    expect(target?.call(0, box), isNull);
  }, skip: !engineReady);

  test('בלי מיפוי מרונדר או אינדקס תקף אין יעד משוער', () {
    final item = RenderConstrainedBox(
      additionalConstraints: BoxConstraints.tight(const Size(100, 2100)),
    )..layout(const BoxConstraints());
    target(String? content, int index) => commentarySearchMatchTarget(
      content: content,
      query: 'אמר',
      displayProfile: TextDisplayProfile.defaults,
      matchIndex: index,
    );
    expect(target('אמר', 0)?.call(0, item), isNull);
    expect(target('אמר', 1), isNull);
    expect(target('אמר', -1), isNull);
    expect(target(null, 0), isNull);
  }, skip: !engineReady);

  test('טווחי ביטוי נספרים לפי תוצאות ולא לפי מילים', () {
    const text = 'אמר רבי ובסוף אמר רבי';
    expect(utils.searchMatchRangeAt(text, 'אמר רבי', 1), (
      start: text.lastIndexOf('אמר רבי'),
      end: text.length,
      totalCount: 2,
    ));
    expect(utils.searchMatchRangeAt('אמר בני רבי סוף', '/אמר .* רבי/', 0), (
      start: 0,
      end: 11,
      totalCount: 1,
    ));
  }, skip: !engineReady);
}
