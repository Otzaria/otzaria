import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_restore.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
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
          removePunctuation: true,
        ),
      );
      final secondLine = renderSelectionLine(
        rawText: 'שָׁלוֹם.',
        settings: const RenderSettings(
          removeNikud: true,
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
      // הסתרת פיסוק מסירה את ה"-" ומותירה רווח כפול במקומו;
      // התצוגה ב-HTML מכווצת אותו, ולכן גם renderSelectionLine חייב לכווץ.
      expect(removePunctuation('לאמר - דבר').contains('  '), isTrue);

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
}
