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
}
