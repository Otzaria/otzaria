import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// ערימת בדיקות לשחזור מעברי השורה בהעתקה (issue: "לפעמים מועתק בלי ירידות
/// שורה"). הבדיקות מדמות את הצינור האמיתי: השורה הגולמית → הטקסט המוצג בפועל
/// (כללי הרווחים של [SimpleInlineHtml]/HtmlWidget) → הבחירה השטוחה שפלאטר
/// מחזיר → [restoreSelectedTextLineBreaksDetailed] מול השורות המרונדרות.
void main() {
  group('צינור מלא: תצוגה → בחירה שטוחה → שחזור', () {
    test('שתי שורות רגילות', () {
      expectRestoresBreaks(
        rawLines: const ['בראשית ברא אלהים', 'את השמים ואת הארץ'],
        firstLine: 0,
        lastLine: 1,
      );
    });

    test('בחירה חלקית מאמצע שורה ראשונה עד אמצע אחרונה', () {
      expectRestoresBreaks(
        rawLines: const [
          'ויאמר אלהים יהי אור',
          'ויהי אור וירא אלהים',
          'את האור כי טוב',
        ],
        firstLine: 0,
        lastLine: 2,
        startColumn: 6,
        endColumn: 8,
      );
    });

    test('חמש שורות רצופות', () {
      expectRestoresBreaks(
        rawLines: const [
          'אלף בית גימל',
          'דלת הא ואו',
          'זין חית טית',
          'יוד כף למד',
          'מם נון סמך',
        ],
        firstLine: 0,
        lastLine: 4,
      );
    });

    test('שורה עם תגי עיצוב (<b>/<i>) באמצע', () {
      expectRestoresBreaks(
        rawLines: const [
          'ראש <b>מודגש</b> סוף',
          'שורה <i>נטויה</i> שניה',
          'שורה שלישית',
        ],
        firstLine: 0,
        lastLine: 2,
      );
    });

    test('רווחים כפולים בשורת המקור', () {
      expectRestoresBreaks(
        rawLines: const ['מילה   ועוד   מילה', 'שורה   שניה'],
        firstLine: 0,
        lastLine: 1,
      );
    });

    test('&nbsp; ו-&thinsp; בשורת המקור', () {
      expectRestoresBreaks(
        rawLines: const [
          'אלהים&nbsp;לאור&thinsp;{פ}',
          'ויאמר אלהים יהי רקיע',
        ],
        firstLine: 0,
        lastLine: 1,
      );
    });

    test('שורה ריקה בין שתי שורות תוכן', () {
      expectRestoresBreaks(
        rawLines: const ['שורה ראשונה', '', 'שורה שלישית'],
        firstLine: 0,
        lastLine: 2,
      );
    });

    test('הסרת ניקוד וטעמים פעילה', () {
      expectRestoresBreaks(
        rawLines: const [
          'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים',
          'אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃',
        ],
        firstLine: 0,
        lastLine: 1,
        settings: const RenderSettings(removeNikud: true, removeTeamim: true),
      );
    });

    test('הסרת פיסוק פעילה', () {
      expectRestoresBreaks(
        rawLines: const [
          'וידבר ה אל משה לאמר - דבר',
          'אל בני ישראל, ואמרת אליהם.',
        ],
        firstLine: 0,
        lastLine: 1,
        settings: const RenderSettings(removePunctuation: true),
      );
    });

    test('שורה עם <br> באמצע הבחירה', () {
      expectRestoresBreaks(
        rawLines: const ['פסקה ראשונה<br>המשך אחרי שבירה', 'פסקה שניה'],
        firstLine: 0,
        lastLine: 1,
      );
    });

    test('<br> בשורה הראשונה מתוך שלוש', () {
      expectRestoresBreaks(
        rawLines: const ['ראשון<br>עוד ראשון', 'שני שני', 'שלישי שלישי'],
        firstLine: 0,
        lastLine: 2,
      );
    });

    test('entity שאינו רווח (&quot;) בשורת המקור', () {
      expectRestoresBreaks(
        rawLines: const ['אמר &quot;שלום&quot; לחברו', 'שורה שניה רגילה'],
        firstLine: 0,
        lastLine: 1,
      );
    });

    test('entity של אמפרסנד (&amp;) בשורת המקור', () {
      expectRestoresBreaks(
        rawLines: const ['רבי א &amp; רבי ב', 'שורה שניה רגילה'],
        firstLine: 0,
        lastLine: 1,
      );
    });

    test('גרש/גרשיים ומקף מחבר', () {
      expectRestoresBreaks(
        rawLines: const ['ר״ת אומר כי בית־דין', 'פוסק כדעת ר׳ יוסי'],
        firstLine: 0,
        lastLine: 1,
      );
    });
  });

  group('מטריצת הגדרות התצוגה (ניקוד/טעמים/פיסוק/שמות קדושים)', () {
    // פסוק עם ניקוד, טעמים, פיסוק, שם הויה וסוגריים — כל מתג משנה אותו.
    const versesWithEverything = [
      'וַיְדַבֵּ֥ר יְהוָ֖ה אֶל־מֹשֶׁ֥ה לֵּאמֹֽר׃',
      'דַּבֵּ֞ר אֶל־בְּנֵ֤י יִשְׂרָאֵל֙ (וְאָמַרְתָּ֣ אֲלֵהֶ֔ם) אֲנִ֖י יְהוָֽה׃',
      'וְשָׁמְר֥וּ בְנֵֽי־יִשְׂרָאֵ֖ל אֶת־הַשַּׁבָּֽת׃',
    ];

    for (final removeNikud in [false, true]) {
      for (final removeTeamim in [false, true]) {
        for (final removePunctuation in [false, true]) {
          for (final replaceHolyNames in [false, true]) {
            final label = [
              'ניקוד=${removeNikud ? 'מוסר' : 'מוצג'}',
              'טעמים=${removeTeamim ? 'מוסרים' : 'מוצגים'}',
              'פיסוק=${removePunctuation ? 'מוסר' : 'מוצג'}',
              'שמות=${replaceHolyNames ? 'מוחלפים' : 'כמקור'}',
            ].join(', ');

            test(label, () {
              expectRestoresBreaks(
                rawLines: versesWithEverything,
                firstLine: 0,
                lastLine: 2,
                settings: RenderSettings(
                  removeNikud: removeNikud,
                  removeTeamim: removeTeamim,
                  removePunctuation: removePunctuation,
                  replaceHolyNames: replaceHolyNames,
                ),
              );
            });
          }
        }
      }
    }

    test('בחירה חלקית תחת הסרת ניקוד+טעמים+פיסוק יחד', () {
      expectRestoresBreaks(
        rawLines: versesWithEverything,
        firstLine: 0,
        lastLine: 2,
        startColumn: 4,
        endColumn: 9,
        settings: const RenderSettings(
          removeNikud: true,
          removeTeamim: true,
          removePunctuation: true,
        ),
      );
    });

    test('הסרת פיסוק על שורה עם <br> ומקפים', () {
      expectRestoresBreaks(
        rawLines: const [
          'ראשית - הכל<br>ואחר כך: השאר.',
          'שורה שניה, עם פסיק.',
        ],
        firstLine: 0,
        lastLine: 1,
        settings: const RenderSettings(removePunctuation: true),
      );
    });

    test('הסרת ניקוד ממירה מקף-מחבר ופסק לרווח', () {
      expectRestoresBreaks(
        rawLines: const ['אֵ֥ת ׀ הַשָּׁמַ֖יִם וְאֵ֥ת־הָאָֽרֶץ', 'שורה שניה'],
        firstLine: 0,
        lastLine: 1,
        settings: const RenderSettings(removeNikud: true),
      );
    });

    test('עיצוב סוגריים (formatParentheses) פעיל', () {
      expectRestoresBreaks(
        rawLines: const [
          'תחילת השורה (הערה בסוגריים) המשך',
          'שורה שניה (עם סוגריים נוספים)',
        ],
        firstLine: 0,
        lastLine: 1,
        settings: const RenderSettings(formatParentheses: true),
      );
    });

    test('סימוני הערות (<sup>) בתוך הבחירה', () {
      expectRestoresBreaks(
        rawLines: const [
          'טקסט עם הערה<sup class="footnote-marker">1</sup> באמצע',
          'שורה שניה<sup class="footnote-marker">2</sup> גם כן',
        ],
        firstLine: 0,
        lastLine: 1,
      );
    });
  });

  group('הדגשת חיפוש', () {
    const searchLines = [
      'ויאמר משה אל אהרן קרב אל המזבח',
      'ועשה את חטאתך ואת עלתך',
      'וכפר בעדך ובעד העם',
    ];

    test('הדגשת כל התוצאות (color: red)', () {
      expectRestoresBreaks(
        rawLines: searchLines,
        firstLine: 0,
        lastLine: 2,
        settings: const RenderSettings(searchText: 'את'),
      );
    });

    test('הדגשת תוצאה נוכחית (currentSearchIndex)', () {
      expectRestoresBreaks(
        rawLines: searchLines,
        firstLine: 0,
        lastLine: 2,
        settings: const RenderSettings(searchText: 'את', currentSearchIndex: 0),
      );
    });

    test('הדגשה צהובה רציפה (highlightYellowBackground)', () {
      expectRestoresBreaks(
        rawLines: searchLines,
        firstLine: 0,
        lastLine: 2,
        settings: const RenderSettings(
          searchText: 'ועשה את חטאתך',
          highlightYellowBackground: true,
        ),
      );
    });

    test('חיפוש מקורב (fuzzy)', () {
      expectRestoresBreaks(
        rawLines: searchLines,
        firstLine: 0,
        lastLine: 2,
        settings: const RenderSettings(searchText: 'משה', isFuzzySearch: true),
      );
    });

    test('הדגשת חלק ממילה (partialWordHighlight)', () {
      expectRestoresBreaks(
        rawLines: searchLines,
        firstLine: 0,
        lastLine: 2,
        settings: const RenderSettings(
          searchText: 'עלת',
          partialWordHighlight: true,
        ),
      );
    });

    test('הדגשה על שורה עם ניקוד וטעמים כשההסרה פעילה', () {
      expectRestoresBreaks(
        rawLines: const [
          'וַיֹּ֥אמֶר מֹשֶׁ֖ה אֶֽל־אַהֲרֹ֑ן',
          'קְרַ֣ב אֶל־הַמִּזְבֵּ֗חַ',
        ],
        firstLine: 0,
        lastLine: 1,
        settings: const RenderSettings(
          removeNikud: true,
          removeTeamim: true,
          searchText: 'משה',
        ),
      );
    });
  });

  group('פער בין הגדרות התצוגה להגדרות השחזור', () {
    // התצוגה משתמשת ב-highlightText עם רקע צהוב לשורה המודגשת, בעוד
    // renderSelectionLine נבנה מ-searchText בלבד וללא רקע צהוב.
    test('התצוגה מדגישה highlightText בעוד השחזור מקבל searchText', () {
      expectRestoresBreaks(
        rawLines: const [
          'ויאמר משה אל אהרן קרב אל המזבח',
          'ועשה את חטאתך ואת עלתך',
        ],
        firstLine: 0,
        lastLine: 1,
        settings: const RenderSettings(searchText: 'את'),
        displaySettings: const RenderSettings(
          searchText: 'קרב אל המזבח',
          highlightYellowBackground: true,
        ),
      );
    });

    test('התצוגה מעצבת סוגריים והשחזור לא', () {
      expectRestoresBreaks(
        rawLines: const ['תחילה (הערה) המשך', 'שורה שניה (הערה נוספת)'],
        firstLine: 0,
        lastLine: 1,
        settings: const RenderSettings(),
        displaySettings: const RenderSettings(formatParentheses: true),
      );
    });
  });

  group('בחירה שחורגת מהחלון הנראה (גלילה תוך כדי סימון)', () {
    test('הבחירה מתחילה שורה אחת מעל השורות הנראות', () {
      expectRestoresBreaks(
        rawLines: const ['שורה מעל התצוגה', 'שורה נראית א', 'שורה נראית ב'],
        firstLine: 0,
        lastLine: 2,
        visibleFrom: 1,
      );
    });

    test('הבחירה מסתיימת שורה אחת מתחת לשורות הנראות', () {
      expectRestoresBreaks(
        rawLines: const ['שורה נראית א', 'שורה נראית ב', 'שורה מתחת לתצוגה'],
        firstLine: 0,
        lastLine: 2,
        visibleTo: 1,
      );
    });

    test('הבחירה חורגת משני הצדדים', () {
      expectRestoresBreaks(
        rawLines: const [
          'שורה מעל התצוגה',
          'שורה נראית א',
          'שורה נראית ב',
          'שורה מתחת לתצוגה',
        ],
        firstLine: 0,
        lastLine: 3,
        visibleFrom: 1,
        visibleTo: 2,
      );
    });

    test('שורת אמצע חסרה מהתצוגה (נגללה) — כבר נתמך בשחזור הסלחני', () {
      expectRestoresBreaks(
        rawLines: const ['שורה ראשונה', 'שורה אמצעית', 'שורה שלישית'],
        firstLine: 0,
        lastLine: 2,
        visibleLineFilter: (index) => index != 1,
      );
    });

    test('חריגה מהתצוגה יחד עם <br> בבחירה', () {
      expectRestoresBreaks(
        rawLines: const [
          'שורה מעל<br>עם שבירה',
          'שורה נראית א',
          'שורה נראית ב',
        ],
        firstLine: 0,
        lastLine: 2,
        visibleFrom: 1,
      );
    });
  });

  group('טקסט חוזר (מזמורים/פיוטים) — עמימות בין מופעים', () {
    test('פסוקית חוזרת בשורות סמוכות', () {
      expectRestoresBreaks(
        rawLines: const [
          'הודו לה כי טוב כי לעולם חסדו',
          'הודו לאלהי האלהים כי לעולם חסדו',
          'הודו לאדני האדנים כי לעולם חסדו',
        ],
        firstLine: 0,
        lastLine: 2,
      );
    });

    test('שתי שורות זהות לחלוטין בתוך הבחירה', () {
      expectRestoresBreaks(
        rawLines: const ['אנא ה הושיעה נא', 'אנא ה הושיעה נא', 'סוף המזמור'],
        firstLine: 0,
        lastLine: 2,
      );
    });

    test('הבחירה עצמה מופיעה גם בתוך שורה בודדת אחרת בתצוגה', () {
      expectRestoresBreaks(
        rawLines: const ['אמן ואמן', 'אמן', 'ואמן', 'סיום'],
        firstLine: 1,
        lastLine: 2,
      );
    });
  });

  group('אינווריאנטות אקראיות (property-based)', () {
    test('מילים ייחודיות — הבחירה תמיד מתפצלת לשורות המקוריות', () {
      final random = Random(20260725);
      for (var iteration = 0; iteration < 300; iteration++) {
        final lines = <String>[];
        var token = 0;
        final lineCount = 2 + random.nextInt(5);
        for (var i = 0; i < lineCount; i++) {
          final wordCount = 1 + random.nextInt(5);
          lines.add(
            List.generate(wordCount, (_) => 'מ${token++}').join(' '),
          );
        }
        final firstLine = random.nextInt(lines.length - 1);
        final lastLine =
            firstLine + 1 + random.nextInt(lines.length - firstLine - 1);
        expectRestoresBreaks(
          rawLines: lines,
          firstLine: firstLine,
          lastLine: lastLine,
          startColumn: random.nextInt(lines[firstLine].length),
          endColumn: 1 + random.nextInt(lines[lastLine].length),
          reason: 'iteration $iteration',
        );
      }
    });

    test('מאגר מילים חוזר — השחזור לעולם אינו משנה תווים', () {
      const pool = ['אמר', 'רבי', 'יוסי', 'ה', 'לעולם', 'חסדו', 'כי', 'טוב'];
      final random = Random(981);
      for (var iteration = 0; iteration < 300; iteration++) {
        final lineCount = 2 + random.nextInt(4);
        final lines = List.generate(lineCount, (_) {
          final wordCount = 1 + random.nextInt(5);
          return List.generate(
            wordCount,
            (_) => pool[random.nextInt(pool.length)],
          ).join(' ');
        });
        final firstLine = random.nextInt(lines.length - 1);
        final lastLine =
            firstLine + 1 + random.nextInt(lines.length - firstLine - 1);
        final displayLines = lines
            .map((raw) => displayedText(raw, const RenderSettings()))
            .toList();
        final flat = displayLines.sublist(firstLine, lastLine + 1).join();
        final restored = restoreSelectedTextLineBreaksDetailed(
          selectedText: flat,
          visibleLines: lines
              .map(
                (raw) => renderSelectionLine(
                  rawText: raw,
                  settings: const RenderSettings(),
                ),
              )
              .toList(),
        );

        expect(
          restored.text.replaceAll('\n', ''),
          flat.replaceAll('\n', ''),
          reason: 'iteration $iteration — השחזור שינה תווים',
        );
      }
    });
  });
}

/// מדמה את הטקסט שהמשתמש רואה בפועל עבור שורת מקור: אותו עיבוד של
/// [TextRendererService], ואז כללי הרווחים של שכבת התצוגה — כיווץ רצפי רווחים
/// בכל מקטע טקסט, `<br>` כמעבר שורה שבולע רווחים סביבו, וקיצוץ בקצוות.
String displayedText(String rawLine, RenderSettings settings) {
  final processed = TextRendererService.processText(rawLine, settings);
  final buffer = StringBuffer();
  var index = 0;
  final tagPattern = RegExp(r'<[^>]*>');
  final segments = <String>[];

  void addText(String raw) {
    if (raw.isEmpty) return;
    segments.add(_decodeEntities(raw).replaceAll(RegExp(r'\s+'), ' '));
  }

  for (final match in tagPattern.allMatches(processed)) {
    addText(processed.substring(index, match.start));
    index = match.end;
    if (RegExp(r'^<br\s*/?>$', caseSensitive: false).hasMatch(match[0]!)) {
      segments.add('\n');
    }
  }
  addText(processed.substring(index));

  for (var i = 0; i < segments.length; i++) {
    if (segments[i] != '\n') continue;
    if (i > 0 && segments[i - 1] != '\n') {
      segments[i - 1] = segments[i - 1].trimRight();
    }
    if (i + 1 < segments.length && segments[i + 1] != '\n') {
      segments[i + 1] = segments[i + 1].trimLeft();
    }
  }
  for (final segment in segments) {
    buffer.write(segment);
  }
  return buffer.toString().trim();
}

String _decodeEntities(String text) => text
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&thinsp;', ' ')
    .replaceAll('&ensp;', ' ')
    .replaceAll('&emsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

/// בונה את הבחירה השטוחה כפי ש-SelectionArea מחזיר (שרשור הטקסט המוצג ללא
/// מפריד), מריץ את השחזור, ומוודא שהתקבלו מעברי שורה בכל גבול שורה — ושהתווים
/// עצמם לא השתנו.
void expectRestoresBreaks({
  required List<String> rawLines,
  required int firstLine,
  required int lastLine,
  int startColumn = 0,
  int? endColumn,
  RenderSettings settings = const RenderSettings(),
  RenderSettings? displaySettings,
  int visibleFrom = 0,
  int? visibleTo,
  bool Function(int index)? visibleLineFilter,
  String? reason,
}) {
  final displayLines = rawLines
      .map((raw) => displayedText(raw, displaySettings ?? settings))
      .toList();

  final parts = <String>[];
  for (var i = firstLine; i <= lastLine; i++) {
    var part = displayLines[i];
    if (i == lastLine && endColumn != null) {
      part = part.substring(0, endColumn.clamp(0, part.length));
    }
    if (i == firstLine) {
      part = part.substring(startColumn.clamp(0, part.length));
    }
    parts.add(part);
  }
  final flat = parts.join();
  final expected = parts.where((part) => part.isNotEmpty).join('\n');

  final lastVisible = visibleTo ?? rawLines.length - 1;
  final visibleIndices = <int>[];
  for (var i = visibleFrom; i <= lastVisible; i++) {
    if (visibleLineFilter != null && !visibleLineFilter(i)) continue;
    visibleIndices.add(i);
  }

  String renderLine(int index) =>
      renderSelectionLine(rawText: rawLines[index], settings: settings);

  // שכבת התצוגה מרחיבה את החלון סביב השורות הנראות לפי אורך הבחירה. סינון
  // שורה מהאמצע מדמה שורה שרונדרה שונה, ולכן עוקף את ההרחבה הרציפה.
  final visibleLines = visibleLineFilter != null
      ? visibleIndices.map(renderLine).toList()
      : buildSelectionWindow(
          visibleIndices: visibleIndices,
          totalLines: rawLines.length,
          selectionLength: flat.length,
          renderLine: renderLine,
        ).lines;

  final restored = restoreSelectedTextLineBreaks(
    selectedText: flat,
    visibleLines: visibleLines,
  );

  expect(
    restored.replaceAll('\n', ''),
    flat.replaceAll('\n', ''),
    reason: ['השחזור שינה תווים בבחירה', ?reason].join(' — '),
  );
  expect(
    restored.replaceAll(RegExp(r'\n+'), '\n'),
    expected.replaceAll(RegExp(r'\n+'), '\n'),
    reason: ['חסרים מעברי שורה בהעתקה', ?reason].join(' — '),
  );
}
