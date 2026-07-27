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

    testWidgets('כותרת בפרנק-רוהל אינה מודגשת — תואם לספר', (tester) async {
      await tester.pumpWidget(buildPreview('<h1>דף ה.</h1>', 'FrankRuhlCLM'));
      await tester.pumpAndSettle();
      expect(
        _findHeading(tester, 'דף ה.').text.style?.fontWeight,
        FontWeight.w400,
      );
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
