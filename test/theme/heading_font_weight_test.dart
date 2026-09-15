import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/library/view/book_versions_dialog.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/editing/services/preview_renderer.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

/// גופנים שהבולד שלהם הוא אותו ציור אות (מעובה או ציר wght) — הכותרת
/// אצלם נשארת מודגשת.
const _sameFaceFonts = [
  'TaameyDavidCLM',
  'KeterYG',
  'Shofar',
  'Tinos',
  'NotoRashiHebrew',
  'Rubik',
  'NotoSerifHebrew',
];

Widget _wrap(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );
}

RichText _findHeading(WidgetTester tester, String text) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .firstWhere((w) => w.text.toPlainText().contains(text));
}

void main() {
  group('AppFonts.headingFontWeightOverride', () {
    test('מחזיר 400 לכותרת בגופן עם face בולד נפרד', () {
      for (final tag in AppFonts.headingTags) {
        expect(
          AppFonts.headingFontWeightOverride(tag, 'FrankRuhlCLM'),
          '400',
          reason: tag,
        );
      }
    });

    test('מחזיר null לכותרת בגופן ללא face בולד נפרד', () {
      for (final font in _sameFaceFonts) {
        expect(
          AppFonts.headingFontWeightOverride('h2', font),
          isNull,
          reason: font,
        );
      }
    });

    test('מחזיר null לתגים שאינם כותרת, גם בגופן עם face נפרד', () {
      for (final tag in const ['p', 'div', 'b', 'strong', 'span', 'a']) {
        expect(
          AppFonts.headingFontWeightOverride(tag, 'FrankRuhlCLM'),
          isNull,
          reason: tag,
        );
      }
    });

    test('תג null או גופן null אינם קורסים', () {
      expect(AppFonts.headingFontWeightOverride(null, 'FrankRuhlCLM'), isNull);
      expect(AppFonts.headingFontWeightOverride('h1', null), isNull);
      expect(AppFonts.headingFontWeightOverride(null, null), isNull);
    });

    test('גופן מערכת שנטען לו bold אחי מקבל 400', () {
      addTearDown(AppFonts.debugResetSystemFontsCache);
      expect(AppFonts.headingFontWeightOverride('h1', 'Guttman Rashi'), isNull);
      AppFonts.debugMarkSeparateBoldSystemFont('Guttman Rashi');
      expect(AppFonts.headingFontWeightOverride('h1', 'Guttman Rashi'), '400');
    });

    // '400' ולא 'normal' — fontWeightTryParse של fwfh מזהה רק מספר או 'bold',
    // ולכן 'normal' נבלע בשקט וההוראה לא מיושמת.
    test('הערך הוא מספר, לא המילה normal', () {
      final value = AppFonts.headingFontWeightOverride('h1', 'FrankRuhlCLM');
      expect(int.tryParse(value!), isNotNull);
    });
  });

  group('AppFonts.headingFontSizeOverride', () {
    test('h3-h6 מדורגות מעל הגוף בגופן עם face בולד נפרד', () {
      expect(AppFonts.headingFontSizeOverride('h3', 'FrankRuhlCLM'), '1.25em');
      expect(AppFonts.headingFontSizeOverride('h4', 'FrankRuhlCLM'), '1.1em');
      expect(AppFonts.headingFontSizeOverride('h5', 'FrankRuhlCLM'), '1.05em');
      expect(AppFonts.headingFontSizeOverride('h6', 'FrankRuhlCLM'), '1.02em');
    });

    test('h5-h6 בגודל הגוף בגופן שההדגשה בו נשמרת', () {
      for (final font in _sameFaceFonts) {
        expect(AppFonts.headingFontSizeOverride('h5', font), '1em');
        expect(AppFonts.headingFontSizeOverride('h6', font), '1em');
      }
    });

    // h1/h2 גדולות דיין בברירת המחדל של fwfh (2em/1.5em).
    test('h1-h2 אינן משתנות', () {
      for (final tag in const ['h1', 'h2']) {
        expect(
          AppFonts.headingFontSizeOverride(tag, 'FrankRuhlCLM'),
          isNull,
          reason: tag,
        );
      }
    });

    test('גופן שההדגשה בו נשמרת אינו מקבל הגדלה', () {
      for (final font in _sameFaceFonts) {
        expect(
          AppFonts.headingFontSizeOverride('h3', font),
          isNull,
          reason: font,
        );
      }
    });

    test('תגים שאינם כותרת, תג null וגופן null מחזירים null', () {
      for (final tag in const ['p', 'div', 'b', 'span']) {
        expect(
          AppFonts.headingFontSizeOverride(tag, 'FrankRuhlCLM'),
          isNull,
          reason: tag,
        );
      }
      expect(AppFonts.headingFontSizeOverride(null, 'FrankRuhlCLM'), isNull);
      expect(AppFonts.headingFontSizeOverride('h3', null), isNull);
    });

    test('גופן מערכת שנטען לו bold אחי מקבל הגדלה', () {
      addTearDown(AppFonts.debugResetSystemFontsCache);
      expect(AppFonts.headingFontSizeOverride('h4', 'Guttman Rashi'), isNull);
      AppFonts.debugMarkSeparateBoldSystemFont('Guttman Rashi');
      expect(AppFonts.headingFontSizeOverride('h4', 'Guttman Rashi'), '1.1em');
    });
  });

  group('SmartTextWidget — כותרות בכל רמות התגים', () {
    testWidgets('h1-h6 בפרנק-רוהל אינן מודגשות', (tester) async {
      for (final tag in AppFonts.headingTags) {
        await tester.pumpWidget(
          _wrap(
            SmartTextWidget(
              text: '<$tag>דף ה.</$tag>',
              settings: const RenderSettings(
                fontSize: 20,
                fontFamily: 'FrankRuhlCLM',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _findHeading(tester, 'דף ה.').text.style?.fontWeight,
          FontWeight.w400,
          reason: tag,
        );
      }
    });

    testWidgets('h1-h6 בגופן ללא face נפרד נשארות מודגשות', (tester) async {
      for (final font in _sameFaceFonts) {
        await tester.pumpWidget(
          _wrap(
            SmartTextWidget(
              text: '<h3>דף ה.</h3>',
              settings: RenderSettings(fontSize: 20, fontFamily: font),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _findHeading(tester, 'דף ה.').text.style?.fontWeight,
          FontWeight.bold,
          reason: font,
        );
      }
    });

    testWidgets('גודל הכותרת נשמר — רק ההדגשה יורדת', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '<h1>דף ה.</h1>',
            settings: RenderSettings(
              fontSize: 20,
              fontFamily: 'FrankRuhlCLM',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final style = _findHeading(tester, 'דף ה.').text.style;
      expect(style?.fontWeight, FontWeight.w400);
      expect(style?.fontSize, greaterThan(20));
    });

    // issue #900: בלי ההדגשה h4 יצאה בגודל הגוף בדיוק ו-h3 גדולה ב-17% בלבד.
    testWidgets('h3 ו-h4 בפרנק-רוהל גדולות מהטקסט', (tester) async {
      for (final entry in const {'h3': 1.25, 'h4': 1.1}.entries) {
        await tester.pumpWidget(
          _wrap(
            SmartTextWidget(
              text: '<${entry.key}>דף ה.</${entry.key}>',
              settings: const RenderSettings(
                fontSize: 20,
                fontFamily: 'FrankRuhlCLM',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final style = _findHeading(tester, 'דף ה.').text.style;
        expect(style?.fontWeight, FontWeight.w400, reason: entry.key);
        expect(
          style?.fontSize,
          closeTo(20 * entry.value, 0.01),
          reason: entry.key,
        );
      }
    });

    testWidgets('h3 בגופן שההדגשה בו נשמרת אינה מוגדלת', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '<h3>דף ה.</h3>',
            settings: RenderSettings(
              fontSize: 20,
              fontFamily: 'TaameyDavidCLM',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final style = _findHeading(tester, 'דף ה.').text.style;
      expect(style?.fontWeight, FontWeight.bold);
      expect(style?.fontSize, closeTo(20 * 1.17, 0.01));
    });

    // issue #1378: ברירת המחדל של fwfh ל-h5/h6 היא 0.83em/0.67em — קטנה מהגוף.
    for (final font in const ['FrankRuhlCLM', 'TaameyDavidCLM']) {
      testWidgets('h4-h6 ב-$font אינן קטנות מהטקסט', (tester) async {
        for (final tag in const ['h4', 'h5', 'h6']) {
          await tester.pumpWidget(
            _wrap(
              SmartTextWidget(
                text: '<$tag>דף ה.</$tag>',
                settings: RenderSettings(fontSize: 20, fontFamily: font),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            _findHeading(tester, 'דף ה.').text.style?.fontSize,
            greaterThanOrEqualTo(20),
            reason: tag,
          );
        }
      });
    }

    testWidgets('טקסט רגיל (ללא כותרת) אינו מושפע', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '<p>שורה <b>מודגשת</b> בפסקה</p>',
            settings: RenderSettings(
              fontSize: 20,
              fontFamily: 'FrankRuhlCLM',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      var foundBold = false;
      _findHeading(tester, 'מודגשת').text.visitChildren((span) {
        if (span is TextSpan &&
            span.text?.contains('מודגשת') == true &&
            span.style?.fontWeight == FontWeight.bold) {
          foundBold = true;
        }
        return true;
      });
      expect(foundBold, isTrue);
    });
  });

  group('PreviewRenderer — תצוגה מקדימה בעורך', () {
    Widget buildPreview(String markdown, String font) {
      return _wrap(
        PreviewRenderer().renderPreview(
          markdown: markdown,
          textStyle: TextStyle(fontSize: 18, fontFamily: font),
          fontFamily: font,
        ),
      );
    }

    testWidgets('כל רמות הכותרת בפרנק-רוהל אינן מודגשות — תואם לספר', (
      tester,
    ) async {
      for (final tag in AppFonts.headingTags) {
        await tester.pumpWidget(
          buildPreview('<$tag>דף ה.</$tag>', 'FrankRuhlCLM'),
        );
        await tester.pumpAndSettle();
        expect(
          _findHeading(tester, 'דף ה.').text.style?.fontWeight,
          FontWeight.w400,
          reason: tag,
        );
      }
    });

    testWidgets('כותרת בגופן ללא face נפרד נשארת מודגשת', (tester) async {
      await tester.pumpWidget(buildPreview('<h1>דף ה.</h1>', 'TaameyDavidCLM'));
      await tester.pumpAndSettle();
      expect(
        _findHeading(tester, 'דף ה.').text.style?.fontWeight,
        FontWeight.bold,
      );
    });

    testWidgets('גודל הכותרת נשמר גם כשההדגשה יורדת', (tester) async {
      await tester.pumpWidget(buildPreview('<h1>דף ה.</h1>', 'FrankRuhlCLM'));
      await tester.pumpAndSettle();
      expect(
        _findHeading(tester, 'דף ה.').text.style?.fontSize,
        greaterThan(18),
      );
    });
  });

  group('BookVersionTile — הערות גרסה מספריא', () {
    Widget buildTile(String notes, String font) {
      return _wrap(
        BookVersionTile(
          book: TextBook(title: 'ברכות'),
          version: BookVersionInfo(
            versionTitle: 'נוסח א',
            heVersionNotes: notes,
            hasContent: true,
          ),
          isOnlyVersion: false,
        ),
        theme: ThemeData(
          textTheme: TextTheme(bodySmall: TextStyle(fontFamily: font)),
        ),
      );
    }

    testWidgets('כותרת בהערה אינה מודגשת בגופן עם face נפרד', (tester) async {
      await tester.pumpWidget(buildTile('<h2>מקור</h2>', 'FrankRuhlCLM'));
      await tester.pumpAndSettle();
      expect(
        _findHeading(tester, 'מקור').text.style?.fontWeight,
        FontWeight.w400,
      );
    });

    testWidgets('כותרת בהערה נשארת מודגשת בגופן ללא face נפרד', (
      tester,
    ) async {
      await tester.pumpWidget(buildTile('<h2>מקור</h2>', 'TaameyDavidCLM'));
      await tester.pumpAndSettle();
      expect(
        _findHeading(tester, 'מקור').text.style?.fontWeight,
        FontWeight.bold,
      );
    });

    testWidgets('הערה בלי כותרת מוצגת כרגיל', (tester) async {
      await tester.pumpWidget(buildTile('הערה <b>חשובה</b>', 'FrankRuhlCLM'));
      await tester.pumpAndSettle();
      expect(find.byType(HtmlWidget), findsOneWidget);
      expect(_findHeading(tester, 'חשובה'), isNotNull);
    });
  });
}
