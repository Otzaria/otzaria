import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

import '../../support/search_engine_test_init.dart';

/// issue #1248: תוצאת חיפוש שבה מופיע שם הוי"ה לא הודגשה בספר (תצוגה
/// מקדימה ופתיחה מלאה), בעוד רשימת התוצאות כן הדגישה אותה. הרנדור החליף
/// את השם ב"יקוק" לפני ההדגשה, ותבנית ההדגשה מכירה רק את הכתיב שבשאילתה.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  // תהילים קז, ח — כפי שהשורה שמורה במסד (ניקוד + טעמים).
  const verse =
      '(ח) יוֹד֣וּ לַיהֹוָ֣ה חַסְדּ֑וֹ וְ֝נִפְלְאוֹתָ֗יו לִבְנֵ֥י אָדָֽם׃';
  const query = 'יודו ליהוה חסדו';

  group('הדגשת חיפוש עם שם הוי"ה מוחלף', () {
    test('בלי החלפה — הביטוי מודגש (בקרה)', () {
      final out = TextRendererService.processText(
        verse,
        const RenderSettings(searchText: query),
      );
      expect(
        out,
        contains('<span style="color: otzaria-search-hit">יוֹד֣וּ</span>'),
      );
      expect(
        out,
        contains('<span style="color: otzaria-search-hit">חַסְדּ֑וֹ</span>'),
      );
    });

    for (final style in HolyNameStyle.values) {
      test('עם החלפה ($style) — הביטוי מודגש והשם מוחלף', () {
        final out = TextRendererService.processText(
          verse,
          RenderSettings(
            searchText: query,
            replaceHolyNames: true,
            holyNameStyle: style,
          ),
        );
        expect(
          out,
          isNot(contains('יהֹוָ֣ה')),
          reason: 'השם חייב להישאר מוחלף',
        );
        expect(
          out,
          contains('<span style="color: otzaria-search-hit">יוֹד֣וּ</span>'),
          reason: 'מילות החיפוש סביב השם חייבות להיות מודגשות',
        );
        expect(
          out,
          contains('<span style="color: otzaria-search-hit">חַסְדּ֑וֹ</span>'),
        );
      });
    }
  }, skip: engineReady ? false : searchEngineSkipReason);
}
