import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

import '../../support/search_engine_test_init.dart';

/// שמות הקודש שסומנו במסד, דרך צינור הרינדור המלא: ההחלפה אחרי הדגשת
/// החיפוש, מפתח המטמון, והאיחוד עם ה-regex של שם הוי"ה.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  setUp(TextRendererService.clearRenderCacheForTesting);

  // וַיֹּאמֶר לֵאלֹהִים — "אלהים" בתווים 7..13 (הניקוד נספר).
  const line = 'ויאמר לֵאלֹהִים שלום';
  final nameStart = line.indexOf('א', 6);
  final nameEnd = line.indexOf(' ', nameStart);
  final marked = wrapDivineNameSpans(line, [
    (start: nameStart, end: nameEnd, kind: DivineNameKind.elohim),
  ]);

  const substitute = RenderSettings(substituteDivineNames: true);

  test('ההגדרה כבויה — הטקסט ככתבו, בלי סמנים', () {
    expect(
      TextRendererService.processText(marked, const RenderSettings()),
      line,
    );
  });

  test('ההגדרה פעילה — השם מוצג בכינוי, הניקוד נשמר', () {
    expect(
      TextRendererService.processText(marked, substitute),
      'ויאמר לֵאלֹקִים שלום',
    );
  });

  test('בלי ניקוד — ההחלפה על האותיות שנותרו', () {
    expect(
      TextRendererService.processText(
        marked,
        substitute.copyWith(removeNikud: true),
      ),
      'ויאמר לאלקים שלום',
    );
  });

  test('החלפת ההגדרה משנה את מפתח המטמון', () {
    final off = TextRendererService.processText(marked, const RenderSettings());
    final on = TextRendererService.processText(marked, substitute);
    final offAgain = TextRendererService.processText(
      marked,
      const RenderSettings(),
    );
    expect(on, isNot(off));
    expect(offAgain, off);
    expect(
      const RenderSettings(substituteDivineNames: true),
      isNot(const RenderSettings()),
    );
  });

  test('פרופיל התצוגה מעביר את ההגדרה לרינדור', () {
    const profile = TextDisplayProfile(
      divineNames: DivineNamesDisplay.substitute,
    );
    expect(RenderSettings.fromProfile(profile).substituteDivineNames, isTrue);
    expect(
      RenderSettings.fromProfile(
        TextDisplayProfile.defaults,
      ).substituteDivineNames,
      isFalse,
    );
  });

  test('שם הוי"ה — איחוד הטבלה וה-regex, בלי החלפה כפולה', () {
    const text = 'יהוה אמר';
    final withTable = wrapDivineNameSpans(text, [
      (start: 0, end: 4, kind: DivineNameKind.hvyh),
    ]);
    const settings = RenderSettings(replaceHolyNames: true);
    expect(TextRendererService.processText(withTable, settings), 'יקוק אמר');
    // regex בלבד, בלי טבלה — אותה תוצאה.
    expect(TextRendererService.processText(text, settings), 'יקוק אמר');

    // ה-regex מדלג כשלפני השם 3 אותיות; כשהן אותיות שימוש והמופע מאומת
    // בטבלה — מוחלף בכל זאת.
    const exception = 'ושליהוה';
    expect(TextRendererService.processText(exception, settings), exception);
    final forced = wrapDivineNameSpans(exception, [
      (start: 3, end: 7, kind: DivineNameKind.hvyh),
    ]);
    expect(TextRendererService.processText(forced, settings), 'ושליקוק');
  });

  test('שם בתוך sup — הסמן אינו משנה את מסלול ה-sup', () {
    const supLine = 'שלום<sup>אלהים</sup> שלום';
    final supMarked = wrapDivineNameSpans(supLine, [
      (start: 4, end: 9, kind: DivineNameKind.elohim),
    ]);
    final plain = TextRendererService.processText(
      supLine,
      const RenderSettings(),
    );
    expect(
      TextRendererService.processText(supMarked, const RenderSettings()),
      plain,
    );
    expect(
      TextRendererService.processText(supMarked, substitute),
      plain.replaceFirst('אלהים', 'אלקים'),
    );
  });

  test('ציוני מפרשים אחרי הסמן אינם מזיזים את המופע', () {
    // השמות נעטפים לפני הזרקות שמוסיפות תוכן גלוי — כאן מדומה סדר זה.
    final withAnchor = '$marked<span class="link-anchor">(א)</span>';
    expect(
      TextRendererService.processText(withAnchor, substitute),
      'ויאמר לֵאלֹקִים שלום<span class="link-anchor">(א)</span>',
    );
  });

  group('הדגשת חיפוש ומילה עם סמן', () {
    test('שאילתה עם אות שימוש מודגשת, והשם מוחלף בתוך ההדגשה', () {
      final out = TextRendererService.processText(
        marked,
        substitute.copyWith(searchText: 'לאלהים'),
      );
      expect(out, contains('<span style="color: red">לֵ</span>'));
      expect(out, contains('<span style="color: red">אלֹקִים</span>'));
      expect(out, isNot(contains('divine-name')));
    });

    test('ביטוי של כמה מילים עובר את גבול הסמן', () {
      final out = TextRendererService.processText(
        marked,
        substitute.copyWith(searchText: 'ויאמר לאלהים שלום'),
      );
      expect(out, contains('<span style="color: red">ויאמר</span>'));
      expect(out, contains('<span style="color: red">אלֹקִים</span>'));
      expect(out, contains('<span style="color: red">שלום</span>'));
    });

    test('אדנות — ההדגשה על הכתיב שבשאילתה, המקף נוסף אחריה', () {
      final adnut = wrapDivineNameSpans('אמר אדני', [
        (start: 4, end: 8, kind: DivineNameKind.adnut),
      ]);
      final out = TextRendererService.processText(
        adnut,
        substitute.copyWith(searchText: 'אדני'),
      );
      expect(out, 'אמר <span style="color: red">אד-ני</span>');
      expect(stripHtmlIfNeeded(out), 'אמר אד-ני');
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}
