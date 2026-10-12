import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/text_book/utils/text_book_export_utils.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

/// ייצוא ספר שלם עם מופעי השמות: המופעים עוברים ל-isolate כנתונים, וה-regex
/// של שם הוי"ה ממשיך לפעול כמו היום.
void main() {
  const content = 'בראשית\nבראשית ברא <b>אלהים</b>\nויאמר יהוה';
  // שורה 1: "אלהים" בתווים הגלויים 11..16.
  final spans =
      (DivineNameSpansBuilder()..add(1, 11, 16, DivineNameKind.elohim)).build();

  TextBookExportRequest request({
    bool substitute = true,
    bool replaceHolyNames = true,
  }) => TextBookExportRequest(
    rawContent: content,
    profile: TextDisplayProfile(
      holyName: replaceHolyNames
          ? HolyNameDisplay.kufKuf
          : HolyNameDisplay.asIs,
      divineNames: substitute
          ? DivineNamesDisplay.substitute
          : DivineNamesDisplay.asIs,
    ),
    divineNames: spans,
  );

  test(
    'ייצוא טקסט ב-isolate — המופעים מוחלפים, ושם הוי"ה דרך ה-regex',
    () async {
      final text = await compute(createTextBookTextExport, request());
      expect(text, 'בראשית\nבראשית ברא אלקים\nויאמר יקוק');
    },
  );

  test('ההגדרה כבויה — השם ככתבו; שם הוי"ה לפי הגדרתו בנפרד', () async {
    final text = await compute(
      createTextBookTextExport,
      request(substitute: false),
    );
    expect(text, 'בראשית\nבראשית ברא אלהים\nויאמר יקוק');

    final asIs = await compute(
      createTextBookTextExport,
      request(substitute: false, replaceHolyNames: false),
    );
    expect(asIs, 'בראשית\nבראשית ברא אלהים\nויאמר יהוה');
  });

  test('ייצוא Word שומר את ה-HTML, בלי סמני השמות', () {
    final lines = textBookExportLines(request(), stripHtml: false);
    expect(lines[1], 'בראשית ברא <b>אלקים</b>');
    expect(lines.join(), isNot(contains('divine-name')));
  });

  test('בלי מופעים (מסד ישן) — כמו קודם', () {
    final old = TextBookExportRequest(
      rawContent: content,
      profile: const TextDisplayProfile(
        holyName: HolyNameDisplay.asIs,
        divineNames: DivineNamesDisplay.substitute,
      ),
    );
    expect(
      createTextBookTextExport(old),
      'בראשית\nבראשית ברא אלהים\nויאמר יהוה',
    );
  });

  test('צורת מקף: TXT במקף רגיל, Word עם מחבר המילים', () {
    final adnut = TextBookExportRequest(
      rawContent: 'אמר אדני',
      profile: const TextDisplayProfile(
        holyName: HolyNameDisplay.asIs,
        divineNames: DivineNamesDisplay.substitute,
      ),
      divineNames:
          (DivineNameSpansBuilder()..add(0, 4, 8, DivineNameKind.adnut))
              .build(),
    );
    expect(createTextBookTextExport(adnut), 'אמר אד-ני');
    expect(textBookExportLines(adnut, stripHtml: false).single, 'אמר אד-⁠ני');
  });
}
