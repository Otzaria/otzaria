import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  group('restoreSelectedTextLineBreaks', () {
    test('משחזר מעברי שורה כש-SelectionArea מחזיר טקסט רציף', () {
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'שורה אשורה ב',
        visibleLines: const ['שורה א', 'שורה ב'],
      );

      expect(restored, 'שורה א\nשורה ב');
    });

    test('משחזר בחירה חלקית על פני כמה שורות', () {
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'גדהוזח',
        visibleLines: const ['אבגד', 'הוז', 'חט'],
      );

      expect(restored, 'גד\nהוז\nח');
    });

    test('מחזיר fallback כשהבחירה לא ניתנת למיפוי', () {
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'טקסט לא קיים',
        visibleLines: const ['שורה א', 'שורה ב'],
      );

      expect(restored, 'טקסט לא קיים');
    });

    test('משחזר מעברי שורה גם כששורת אמצע חסרה מהתצוגה', () {
      // 'דהו' נגללה מחוץ לתצוגה — לא קיימת ב-visibleLines אך קיימת בבחירה.
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'אבגדהוזחט',
        visibleLines: const ['אבג', 'זחט'],
      );

      expect(restored, 'אבג\nדהו\nזחט');
      expect(restored.replaceAll('\n', ''), 'אבגדהוזחט');
    });

    test('משחזר מעברי שורה גם כששורת אמצע רונדרה שונה', () {
      // 'דXו' שונה מהתוכן האמיתי 'דהו' — ההתאמה המדויקת נכשלת.
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'אבגדהוזחט',
        visibleLines: const ['אבג', 'דXו', 'זחט'],
      );

      expect(restored, 'אבג\nדהו\nזחט');
      expect(restored.replaceAll('\n', ''), 'אבגדהוזחט');
    });

    test('משחזר בחירה שמתחילה באמצע השורה הראשונה עם שורת אמצע לא-תואמת', () {
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'עולםדהוטוב',
        visibleLines: const ['שלום עולם', 'דXו', 'טוב'],
      );

      expect(restored, 'עולם\nדהו\nטוב');
      expect(restored.replaceAll('\n', ''), 'עולםדהוטוב');
    });

    test(
      'משחזר מעברי שורה כשהתצוגה מכילה NBSP ורווח-דק (מ-&nbsp;/&thinsp;)',
      () {
        // בתצוגה entities נשארים כתווים אמיתיים, ואילו שורות השחזור מכווצות
        // אותם לרווח רגיל — ההתאמה חייבת להתעלם מסוג תו הרווח.
        final restored = restoreSelectedTextLineBreaks(
          selectedText: 'אלהים ׀ לאור׃ {פ}ויאמר אלהים',
          visibleLines: const ['אלהים ׀ לאור׃ {פ}', 'ויאמר אלהים'],
        );

        expect(restored, 'אלהים ׀ לאור׃ {פ}\nויאמר אלהים');
      },
    );

    test('משחזר מעברי פסקה גם כשהבחירה מכילה \\n פנימי (מ-<br>)', () {
      // <br> בתוך שורת מקור מוצג כ-\n בבחירה; שורות השחזור מכווצות אותו
      // לרווח — אסור שה-\n הפנימי יחסום את הזרקת מעברי הפסקה.
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'פסקה ראשונה\nהמשך אחרי שבירה פסקה שניה',
        visibleLines: const ['פסקה ראשונה המשך אחרי שבירה', 'פסקה שניה'],
      );

      expect(restored, 'פסקה ראשונה\nהמשך אחרי שבירה \nפסקה שניה');
    });

    test('לא מכפיל מעבר שורה שכבר קיים בגבול בין שורות', () {
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'שורה א\nשורה ב',
        visibleLines: const ['שורה א', 'שורה ב'],
      );

      expect(restored, 'שורה א\nשורה ב');
    });

    test('מחזיר את מיקום ההתאמה גם כשהבחירה מכילה רווחי יוניקוד', () {
      // NBSP בבחירה מול רווח רגיל בשורות — indexOf רגיל היה נכשל כאן.
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'לאור׃ {פ}ויאמר',
        visibleLines: const ['אלהים לאור׃ {פ}', 'ויאמר אלהים'],
      );

      expect(restored.text, 'לאור׃ {פ}\nויאמר');
      expect(restored.startLine, 0);
      expect(restored.endLine, 1);
      expect(restored.startColumn, 6);
    });

    test('משייך בחירה למופע עם פיזור הרווחים הנכון (לא למופע קודם דומה)', () {
      // אותם תווים בדיוק בשתי שורות, עם רווח במקום שונה — הבחירה חייבת
      // להתאים לשורה השנייה ולא ליפול על המופע הראשון.
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'אב גד',
        visibleLines: const ['אבג ד', 'אב גד'],
      );

      expect(restored.text, 'אב גד');
      expect(restored.startLine, 1);
      expect(restored.endLine, 1);
    });

    test('מעבר שורה מ-<br> צמוד (בלי רווחים) נשמר עקבי מול שורת השחזור', () {
      final line = renderSelectionLine(
        rawText: 'אב<br>גד',
        settings: const RenderSettings(),
      );
      expect(line, 'אב גד');

      // הבחירה כפי שמוצגת: \n במקום ה-<br>.
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'אב\nגדשורה שניה',
        visibleLines: [line, 'שורה שניה'],
      );

      expect(restored, 'אב\nגד\nשורה שניה');
    });

    test('כמה מופעים עם אותו שחזור — הטקסט מוחזר אך המיקום לא (לא מנחשים)', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'כי לעולם חסדו',
        visibleLines: const ['כי לעולם חסדו', 'כי לעולם חסדו'],
      );

      expect(restored.text, 'כי לעולם חסדו');
      expect(restored.startLine, isNull);
      expect(restored.endLine, isNull);
    });

    test('כמה מופעים עם שחזורים שונים — הבחירה מוחזרת כמות שהיא', () {
      // מופע אחד בתוך שורה אחת ומופע שני חוצה גבול שורות — לא ידוע איזה
      // נבחר, ועדיף לא להזריק מעבר שורה שעלול להיות שגוי.
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'אב גד',
        visibleLines: const ['אב גד', 'אב', 'גד'],
      );

      expect(restored.text, 'אב גד');
      expect(restored.startLine, isNull);
    });

    test('preferredLine מכריע בין כמה מופעים תואמים לטובת השורה הידועה', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'כי לעולם חסדו',
        visibleLines: const ['כי לעולם חסדו', 'כי לעולם חסדו'],
        preferredLine: 1,
      );

      expect(restored.text, 'כי לעולם חסדו');
      expect(restored.startLine, 1);
      expect(restored.ambiguous, isFalse);
    });

    test('שחזור סלחני לעולם אינו משנה את תווי הבחירה', () {
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'אבגדהוזחט',
        visibleLines: const ['אבג', 'זחט'],
      );

      expect(restored.replaceAll('\n', ''), 'אבגדהוזחט');
    });

    test('ניקוד תואם שומר על המיקום ומעברי השורה מול מופע בניקוד אחר', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'שָׁם אָב',
        visibleLines: const ['שָׁם', 'אָב', 'שֵׁם אָב'],
      );

      expect(restored, (
        text: 'שָׁם \nאָב',
        startLine: 0,
        endLine: 1,
        startColumn: 0,
        ambiguous: false,
      ));
    });

    test('רמז לשורה עם ניקוד אחר אינו גובר על התאמה מדויקת', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'אֶת',
        visibleLines: const ['אֵת', 'אֶת'],
        preferredLine: 0,
      );

      expect(restored, (
        text: 'אֶת',
        startLine: 1,
        endLine: 1,
        startColumn: 0,
        ambiguous: false,
      ));
    });

    test('עמימות בין התאמות מדויקות נשמרת מול רמז למופע בניקוד אחר', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'אֶת',
        visibleLines: const ['אֶת', 'אֶת', 'אֵת'],
        preferredLine: 2,
      );

      expect(restored, (
        text: 'אֶת',
        startLine: null,
        endLine: null,
        startColumn: null,
        ambiguous: true,
      ));
    });

    test('בחירה הפוכה בלישרים תהילה שומרת על מעבר שורה מול כנבואות', () {
      const firstLine = 'דִּבְרֵי כְזָבִים, וּלְבָבֵימוֹ שָׁבוּ';
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'וּאוֹתָ',
        visibleLines: const [
          firstLine,
          'אוֹתָם לְהַאְמִין כִּנְבוּאוֹת הַצֶּדֶק,',
        ],
        preferredLine: 1,
      );

      expect(restored, (
        text: 'וּ\nאוֹתָ',
        startLine: 0,
        endLine: 1,
        startColumn: firstLine.length - 2,
        ambiguous: false,
      ));
    });

    test('בחירה בלי דגש בסוף שורה עדיין משוחזרת לשורות (#1908)', () {
      // הלוח האמיתי: פלאטר משמיט את הדגש של "וּ" בסוף שורה מנוקדת.
      final lines = [
        for (final raw in const [
          '<blockquote><p><strong>שכל</strong>: אָכֵן שְׁגָגָה הִיא זֹאת אֶל־עֵינֵינוּ</p></blockquote>',
          '<blockquote><p>כִּי עֵין בְּשָׂרִים הֵמָּה,</p></blockquote>',
          '<blockquote><p>עַל־כֵּן אֱמֶת בִּדְבַר־כָּזָב יָמִירוּ,</p></blockquote>',
          '<blockquote><p>חֹשֶׁךְ לְאוֹר שָׂמִים וָאוֹר לַחֹשֶׁךְ.</p></blockquote>',
          '<blockquote><p>הֵן בַּאֲשֶׁר יַשִּׂיגוּ</p></blockquote>',
          '<blockquote><p>יִתְעוּ לְכָל־מִקְרֶה קָטֹן וָפֶגַע,</p></blockquote>',
          '<blockquote><p>אַף כִּי בְּמֻפְלָא וּמְכֻסֶּה מֵהֵמָּה.</p></blockquote>',
          '<blockquote><p>שׁוּר נָא קְצֵה מָשׁוֹט אֶל־תּוֹךְ הַמָּיִם,</p></blockquote>',
          '<blockquote><p>הֵן רַק־מְעֻוָּת וּמְעֻקָּל תִּרְאֵהוּ,</p></blockquote>',
          '<blockquote><p>וּלְבָבְךָ יוֹדֵעַ</p></blockquote>',
          '<blockquote><p>כִּי בֶאֱמֶת יָשָׁר הִנֵּה הִנֵּהוּ.</p></blockquote>',
        ])
          renderSelectionLine(rawText: raw, settings: const RenderSettings()),
      ];
      const selectedLines = [
        'כֵן שְׁגָגָה הִיא זֹאת אֶל־עֵינֵינו',
        'כִּי עֵין בְּשָׂרִים הֵמָּה,',
        'עַל־כֵּן אֱמֶת בִּדְבַר־כָּזָב יָמִירוּ,',
        'חֹשֶׁךְ לְאוֹר שָׂמִים וָאוֹר לַחֹשֶׁךְ.',
        'הֵן בַּאֲשֶׁר יַשִּׂיגו',
        'יִתְעוּ לְכָל־מִקְרֶה קָטֹן וָפֶגַע,',
        'אַף כִּי בְּמֻפְלָא וּמְכֻסֶּה מֵהֵמָּה.',
        'שׁוּר נָא קְצֵה מָשׁוֹט אֶל־תּוֹךְ הַמָּיִם,',
        'הֵן רַק־מְעֻוָּת וּמְעֻקָּל תִּרְאֵהוּ,',
        'וּלְבָבְךָ יוֹדֵעַ',
        'כִּי בֶאֱמֶת',
      ];

      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: selectedLines.join(),
        visibleLines: lines,
      );

      expect(restored.text, selectedLines.join('\n'));
      expect(restored.startLine, 0);
      expect(restored.endLine, 10);
    });

    test('מקף, פסק, סוף פסוק ונון הפוכה משתתפים בהתאמה', () {
      for (final mark in const ['־', '׀', '׃', '׆']) {
        final restored = restoreSelectedTextLineBreaksDetailed(
          selectedText: 'הארץ$mark ויאמר',
          visibleLines: ['את הארץ ויאמר', 'את הָאָרֶץ$mark ויאמר'],
        );

        expect(restored.startLine, 1, reason: mark);
      }
    });

    test('שחזור סלחני מתחיל בסיומת השורה הארוכה ביותר שהבחירה פותחת בה', () {
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'דאבXהוז',
        visibleLines: const ['אבגדאב', 'הוז'],
      );

      expect(restored, 'דאב\nX\nהוז');
    });

    test('בחירה שאינה בשורה ארוכה אינה ריבועית באורך השורה', () {
      final line = 'והנה בשולחן ערוך כתב המחבר ' * 8000;
      final stopwatch = Stopwatch()..start();
      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'טקסט שאינו בשורה',
        visibleLines: [line],
      );
      stopwatch.stop();

      expect(restored, 'טקסט שאינו בשורה');
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('buildSelectionWindow', () {
    String lineAt(int index) => 'שורה $index';

    test('מרחיב את החלון לשני הצדדים עד לכיסוי אורך הבחירה', () {
      final window = buildSelectionWindow(
        visibleIndices: const [5, 6, 7],
        totalLines: 20,
        selectionLength: 20,
        renderLine: lineAt,
      );

      // ההרחבה נעצרת ברגע שסך אורך השורות שנוספו בצד עבר את אורך הבחירה.
      expect(window.baseIndex, 1);
      expect(window.lines.first, 'שורה 1');
      expect(window.lines.last, 'שורה 11');
    });

    test('בחירה קצרה כמעט אינה מרחיבה את החלון', () {
      final window = buildSelectionWindow(
        visibleIndices: const [5, 6],
        totalLines: 20,
        selectionLength: 3,
        renderLine: lineAt,
      );

      expect(window.baseIndex, 4);
      expect(window.lines.length, 4);
    });

    test('אינו חורג מגבולות הספר', () {
      final window = buildSelectionWindow(
        visibleIndices: const [0, 1],
        totalLines: 3,
        selectionLength: 500,
        renderLine: lineAt,
      );

      expect(window.baseIndex, 0);
      expect(window.lines.length, 3);
    });

    test('מכסת התווים חוסמת רינדור של כל הספר', () {
      var rendered = 0;
      final window = buildSelectionWindow(
        visibleIndices: const [500],
        totalLines: 1000,
        selectionLength: 100,
        renderLine: (index) {
          rendered++;
          return lineAt(index);
        },
      );

      expect(window.baseIndex, 487);
      expect(window.lines.length, 27);
      expect(rendered, 27);
    });

    test('שוליים ארוכים משורה 100 — הבחירה כולה נכללת בחלון', () {
      final window = buildSelectionWindow(
        visibleIndices: const [500],
        totalLines: 1000,
        selectionLength: 30000,
        renderLine: lineAt,
      );

      // מכסת התווים מגיעה עד גבולות הספר; חסם השורות הישן (100) היה קוטע
      // כאן את תחילת הבחירה וההעתקה הייתה יוצאת שטוחה.
      expect(window.baseIndex, 0);
      expect(window.lines.length, 1000);
    });

    test('החלון רציף גם כשהאינדקסים הנראים אינם רציפים', () {
      final window = buildSelectionWindow(
        visibleIndices: const [4, 8],
        totalLines: 20,
        selectionLength: 0,
        renderLine: lineAt,
      );

      expect(window.baseIndex, 4);
      expect(window.lines.length, 5);
    });

    test('ללא שורות נראות מחזיר חלון ריק', () {
      final window = buildSelectionWindow(
        visibleIndices: const [],
        totalLines: 20,
        selectionLength: 50,
        renderLine: lineAt,
      );

      expect(window.lines, isEmpty);
      expect(window.baseIndex, 0);
    });

    test('אינדקס נראה מחוץ לתחום נחתך לגבולות הספר', () {
      final window = buildSelectionWindow(
        visibleIndices: const [98, 120],
        totalLines: 100,
        selectionLength: 0,
        renderLine: lineAt,
      );

      expect(window.baseIndex, 98);
      expect(window.lines.length, 2);
    });
  });

  group('resolveSelectionLocation', () {
    test('מיקום ידוע ממופה יחסית ל-baseIndex', () {
      final location = resolveSelectionLocation(
        restored: (
          text: 'א\nב',
          startLine: 1,
          endLine: 2,
          startColumn: 4,
          ambiguous: false,
        ),
        baseIndex: 10,
        fallbackIndex: 99,
      );

      expect(location.selectedIndex, 11);
      expect(location.lineStart, 11);
      expect(location.lineEnd, 12);
      expect(location.startColumn, 4);
    });

    test('התאמה עמומה מאפסת את האינדקס ולא נופלת ל-fallback ישן', () {
      final location = resolveSelectionLocation(
        restored: (
          text: 'א',
          startLine: null,
          endLine: null,
          startColumn: null,
          ambiguous: true,
        ),
        baseIndex: 10,
        fallbackIndex: 99,
      );

      expect(location.selectedIndex, isNull);
      expect(location.lineStart, isNull);
      expect(location.lineEnd, isNull);
      expect(location.startColumn, isNull);
    });

    test('ללא מיקום ושאינו עמום (שחזור סלחני) — נופל ל-fallback', () {
      final location = resolveSelectionLocation(
        restored: (
          text: 'א',
          startLine: null,
          endLine: null,
          startColumn: null,
          ambiguous: false,
        ),
        baseIndex: 10,
        fallbackIndex: 99,
      );

      expect(location.selectedIndex, 99);
      expect(location.lineStart, isNull);
    });
  });

  group('sessionSelectionIndex', () {
    test('מחזיר את האינדקס רק כשקיים טקסט בחירה שמור (סשן פעיל)', () {
      expect(
        sessionSelectionIndex(savedSelectedText: 'טקסט', savedSelectedIndex: 7),
        7,
      );
    });

    test('אינדקס מבחירה קודמת שנוקתה אינו נחשב רמז אמין', () {
      // הבחירה התנקתה (הטקסט null) אבל האינדקס לא אופס — אסור להסתמך עליו.
      expect(
        sessionSelectionIndex(savedSelectedText: null, savedSelectedIndex: 7),
        isNull,
      );
    });
  });

  group('renderSelectionLine', () {
    test('מייצר טקסט תצוגה מעובד לצורך שחזור הבחירה', () {
      final firstLine = renderSelectionLine(
        rawText: 'בְּרֵאשִׁ֖ית!',
        settings: const RenderSettings(
          removeNikud: true,
          removeTeamim: true,
          removePunctuation: true,
        ),
      );
      final secondLine = renderSelectionLine(
        rawText: 'שָׁלוֹם.',
        settings: const RenderSettings(
          removeNikud: true,
          removeTeamim: true,
          removePunctuation: true,
        ),
      );

      final restored = restoreSelectedTextLineBreaks(
        selectedText: 'בראשיתשלום.',
        visibleLines: [firstLine, secondLine],
      );

      expect(firstLine, 'בראשית');
      expect(secondLine, 'שלום.');
      expect(restored, 'בראשית\nשלום.');
    });

    test('מכווץ רווחים כפולים שמותיר הסתרת פיסוק כדי שהתצוגה תתאים', () {
      // התצוגה ב-HTML מכווצת רווחים, ולכן גם renderSelectionLine חייב לכווץ.
      final line = renderSelectionLine(
        rawText: 'לאמר - דבר',
        settings: const RenderSettings(removePunctuation: true),
      );

      expect(line, 'לאמר דבר');
      expect(line.contains('  '), isFalse);
    });

    test('משחזר מעבר שורה בין פסקאות גם כשהוסר פיסוק מוקף ברווחים', () {
      const settings = RenderSettings(removePunctuation: true);
      final firstLine = renderSelectionLine(
        rawText: 'וידבר ה אל משה לאמר - דבר',
        settings: settings,
      );
      final secondLine = renderSelectionLine(
        rawText: 'אל בני ישראל ואמרת אליהם.',
        settings: settings,
      );

      // הבחירה השטוחה שפלאטר מחזיר תואמת את התצוגה (רווחים מכווצים).
      final flatSelection = '$firstLine$secondLine';

      final restored = restoreSelectedTextLineBreaks(
        selectedText: flatSelection,
        visibleLines: [firstLine, secondLine],
      );

      expect(restored, '$firstLine\n$secondLine');
      expect(restored.contains('\n'), isTrue);
    });
  });

  group('פסקאות ממוזגות (מצב רציף)', () {
    // שורות 0–1 בפסקה אחת וכותרת בזרימה לפני שורה 1; שורה 2 פריט נפרד.
    const lines = ['אבג דהו', 'זחט יכל', 'מנס עפצ'];
    final SelectionParagraphs paragraphs = (
      joinsNext: (line) => line == 0,
      headingAt: (line) => line == 1 ? 'כותרת · משנה' : null,
    );

    test('שורות באותה פסקה מחוברות ברווח, ובין פריטים נשאר מעבר שורה', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'דהו זחט יכלמנס',
        visibleLines: lines,
        paragraphs: (joinsNext: (line) => line == 0, headingAt: (_) => null),
      );

      expect(restored.text, 'דהו זחט יכל\nמנס');
      expect(restored.startLine, 0);
      expect(restored.endLine, 2);
      expect(restored.startColumn, 4);
    });

    test('כותרת בזרימה אינה נכללת בטקסט ובמיקום', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'דהו כותרת · משנה זחט',
        visibleLines: lines,
        paragraphs: paragraphs,
      );

      expect(restored.text, 'דהו זחט');
      expect(restored.startLine, 0);
      expect(restored.endLine, 1);
    });

    test('בחירה שמתחילה בתוך הכותרת מתחילה בשורה שהיא פותחת', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'משנה זחט',
        visibleLines: lines,
        paragraphs: paragraphs,
      );

      expect(restored.text, 'זחט');
      expect(restored.startLine, 1);
      expect(restored.startColumn, 0);
    });

    test('בחירה שמסתיימת בתוך הכותרת מסתיימת בשורה שלפניה', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'דהו כותרת',
        visibleLines: lines,
        paragraphs: paragraphs,
      );

      expect(restored.text, 'דהו ');
      expect(restored.endLine, 0);
    });

    for (final selected in [
      'אָב כּוֹתֶרֶת מְנֻקֶּדֶת גַּד',
      'אָב כוֹתֶרֶת מְנֻקֶּדֶת גַּד',
    ]) {
      test('כותרת מנוקדת מושמטת מבחירה רציפה: $selected', () {
        final restored = restoreSelectedTextLineBreaksDetailed(
          selectedText: selected,
          visibleLines: const ['אָב', 'גַּד'],
          paragraphs: (
            joinsNext: (line) => line == 0,
            headingAt: (line) => line == 1 ? 'כּוֹתֶרֶת מְנֻקֶּדֶת' : null,
          ),
        );

        expect(restored, (
          text: 'אָב גַּד',
          startLine: 0,
          endLine: 1,
          startColumn: 0,
          ambiguous: false,
        ));
      });
    }

    for (final gap in ['', ' ', '\n', '\u00a0']) {
      test(
        'ניקוד בסוף שורה נשמר בחיבור רציף כשחסר ניקוד אחר: ${gap.codeUnits}',
        () {
          final restored = restoreSelectedTextLineBreaksDetailed(
            selectedText: 'אָבּ$gapגַד',
            visibleLines: const ['אָבּ', 'גַּד'],
            paragraphs: (
              joinsNext: (line) => line == 0,
              headingAt: (_) => null,
            ),
          );

          expect(restored, (
            text: 'אָבּ גַד',
            startLine: 0,
            endLine: 1,
            startColumn: 0,
            ambiguous: false,
          ));
        },
      );
    }

    test('בלי מבנה פסקאות (מצב רגיל) — מעבר שורה בכל גבול', () {
      final restored = restoreSelectedTextLineBreaksDetailed(
        selectedText: 'דהוזחט',
        visibleLines: lines,
      );

      expect(restored.text, 'דהו\nזחט');
    });
  });

  group('locateSelectionRangesPerLine', () {
    test('בחירה על פני שלוש שורות: סיומת, שורה מלאה, תחילית', () {
      final ranges = locateSelectionRangesPerLine(
        selectedText: 'דהו\nזחט\nיכל',
        visibleLines: const ['אבג דהו', 'זחט', 'יכל מנס'],
      );

      expect(ranges, [
        (line: 0, start: 4, end: 7),
        (line: 1, start: 0, end: 3),
        (line: 2, start: 0, end: 3),
      ]);
    });

    test('רמז עמודה מכריע בין מופעים חוזרים', () {
      final ranges = locateSelectionRangesPerLine(
        selectedText: 'דג',
        visibleLines: const ['דג וגם דג'],
        startColumnHint: 7,
      );

      expect(ranges, [(line: 0, start: 7, end: 9)]);
    });

    test('סובל הבדלי רווחים (NBSP בבחירה, רווח רגיל בתצוגה)', () {
      final ranges = locateSelectionRangesPerLine(
        selectedText: 'דהו זחט',
        visibleLines: const ['אבג דהו', 'זחט יכל'],
      );

      expect(ranges, [
        (line: 0, start: 4, end: 7),
        (line: 1, start: 0, end: 3),
      ]);
    });

    test('מחזיר null כשהבחירה לא נמצאת בשורות', () {
      final ranges = locateSelectionRangesPerLine(
        selectedText: 'טקסט שאיננו',
        visibleLines: const ['אבג', 'דהו'],
      );

      expect(ranges, isNull);
    });

    test('מעדיף מופע שפרוש מהשורה הראשונה עד האחרונה', () {
      // 'דהו' מופיע גם בתוך השורה הראשונה, אבל המופע הנכון הוא זה
      // שמתחיל בשורה 0 ומסתיים בשורה האחרונה.
      final ranges = locateSelectionRangesPerLine(
        selectedText: 'דהו\nזחט',
        visibleLines: const ['דהו זחט דהו', 'זחט'],
      );

      expect(ranges, [
        (line: 0, start: 8, end: 11),
        (line: 1, start: 0, end: 3),
      ]);
    });
  });

  group('ציוני מפרשים בבחירה (#1859)', () {
    const marked =
        'אָמַר <a class="link-anchor link-anchor-0" href="x">(ב)</a>רבי '
        '<span class="link-anchor link-anchor-0">(ג)</span>יוחנן';

    test('עמודת העכבר ממופה למקור רק בשורת תחילת הבחירה', () {
      final line = renderSelectionLineWithMarkers(
        rawText: '<a class="link-anchor link-anchor-0">(א)</a>שלום שלום',
        settings: const RenderSettings(),
      );
      const shown = '(א)שלום';
      final selection = SourceSelection.strip(
        shownText: shown,
        lines: [line],
        startColumn: 0,
      );
      for (final (pointer, expected) in [
        (0, 0),
        (2, 0),
        (3, 0),
        (5, 2),
        (7, 4),
      ]) {
        expect(
          SourceSelection.resolvePointerColumn(
            selection,
            shown,
            pointer,
            lineStart: 4,
            pointerLineIndex: 4,
          ),
          expected,
        );
      }
      expect(
        SourceSelection.resolvePointerColumn(
          selection,
          shown,
          5,
          lineStart: 4,
          pointerLineIndex: 5,
        ),
        isNull,
      );
      expect(
        SourceSelection.resolvePointerColumn(
          selection,
          shown,
          5,
          lineStart: null,
          pointerLineIndex: 4,
        ),
        isNull,
      );
      expect(
        SourceSelection.resolvePointerColumn(
          null,
          'שלום',
          2,
          lineStart: 4,
          pointerLineIndex: 4,
        ),
        2,
      );
    });

    test('עכבר בשורת הסיום של בחירה הפוכה אינו רמז לשורת ההתחלה', () {
      final lines = [
        renderSelectionLineWithMarkers(
          rawText: '<a class="link-anchor link-anchor-0">(א)</a>שלום',
          settings: const RenderSettings(),
        ),
        renderSelectionLineWithMarkers(
          rawText: '<a class="link-anchor link-anchor-0">(ב)</a>עולם',
          settings: const RenderSettings(),
        ),
      ];
      const shown = '(א)שלום\n(ב)עולם';
      final selection = SourceSelection.strip(
        shownText: shown,
        lines: lines,
        startColumn: 0,
      );
      expect(SourceSelection.resolve(selection, shown, 0), (
        text: 'שלום\nעולם',
        column: 0,
      ));
      expect(
        SourceSelection.resolvePointerColumn(
          selection,
          shown,
          5,
          lineStart: 4,
          pointerLineIndex: 5,
        ),
        isNull,
      );
    });

    test('השורה מרונדרת כמו בתצוגה, עם טווחי הציונים', () {
      final line = renderSelectionLineWithMarkers(
        rawText: marked,
        settings: const RenderSettings(removeNikud: true),
      );
      expect(line.text, 'אמר (ב)רבי (ג)יוחנן');
      expect(line.markers, [(4, 7), (11, 14)]);
    });

    test('בחירה שחוצה ציון מוסרת ממנו, ועמודת ההתחלה עוברת למקור', () {
      final line = renderSelectionLineWithMarkers(
        rawText: marked,
        settings: const RenderSettings(removeNikud: true),
      );
      final source = SourceSelection.strip(
        shownText: 'ב)רבי (ג)יוח',
        lines: [line],
        startColumn: 5,
      );
      expect(source, isNotNull);
      expect(SourceSelection.resolve(source, 'ב)רבי (ג)יוח', 5), (
        text: 'רבי יוח',
        column: 4,
      ));
      expect(
        SourceSelection.resolve(source, 'בחירה אחרת', 5),
        (text: 'בחירה אחרת', column: 5),
      );
    });

    test('בחירה שמתחילה אחרי ציון מקבלת את עמודת המקור', () {
      final line = renderSelectionLineWithMarkers(
        rawText: marked,
        settings: const RenderSettings(removeNikud: true),
      );
      final source = SourceSelection.strip(
        shownText: 'יוחנן',
        lines: [line],
        startColumn: 14,
      );
      expect(SourceSelection.resolve(source, 'יוחנן', 14), (
        text: 'יוחנן',
        column: 8,
      ));
    });

    test('בחירה שאינה תואמת לשורות אינה משתנה', () {
      final line = renderSelectionLineWithMarkers(
        rawText: marked,
        settings: const RenderSettings(removeNikud: true),
      );
      expect(
        SourceSelection.strip(shownText: 'שלום', lines: [line], startColumn: 0),
        isNull,
      );
    });

    test('בלי ציונים השורה זהה ל-renderSelectionLine', () {
      const raw = '<b>אָמַר</b> רבי (ב) יוחנן';
      const settings = RenderSettings(removeNikud: true);
      final line = renderSelectionLineWithMarkers(
        rawText: raw,
        settings: settings,
      );
      expect(line.text, renderSelectionLine(rawText: raw, settings: settings));
      expect(line.markers, isEmpty);
    });
  });
}
