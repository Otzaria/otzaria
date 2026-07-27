import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../support/search_engine_test_init.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );
}

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  group('SmartTextWidget — בחירת מסלול רינדור', () {
    testWidgets('שורה פשוטה מרונדרת ב-Text.rich בלי HtmlWidget', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: 'ויאמר משה אל העם',
            settings: RenderSettings(fontSize: 20),
          ),
        ),
      );

      expect(find.byType(HtmlWidget), findsNothing);
      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.text.toPlainText(), 'ויאמר משה אל העם');
      expect(richText.textAlign, TextAlign.justify);
    });

    testWidgets('שורה עם תג b נשארת במסלול המהיר עם span מודגש', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '<b>דיבור המתחיל</b> ביאור הדברים',
            settings: RenderSettings(fontSize: 20),
          ),
        ),
      );

      expect(find.byType(HtmlWidget), findsNothing);
      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.text.toPlainText(), 'דיבור המתחיל ביאור הדברים');
    });

    testWidgets('markup מורכב (span עם class) נופל ל-HtmlWidget', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: 'טקסט <span class="link-anchor">א</span>',
            settings: RenderSettings(fontSize: 20),
          ),
        ),
      );

      expect(find.byType(HtmlWidget), findsOneWidget);
    });

    testWidgets('הדגשת חיפוש פעילה נופלת ל-HtmlWidget רק בשורה עם התאמה', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              SmartTextWidget(
                text: 'שורה עם ברכה בתוכה',
                settings: RenderSettings(fontSize: 20, searchText: 'ברכה'),
              ),
              SmartTextWidget(
                text: 'שורה בלי התאמה',
                settings: RenderSettings(fontSize: 20, searchText: 'ברכה'),
              ),
            ],
          ),
        ),
      );

      // השורה עם ההתאמה מקבלת span של הדגשה → HtmlWidget;
      // השורה בלי התאמה נשארת במסלול המהיר.
      expect(find.byType(HtmlWidget), findsOneWidget);
    }, skip: !engineReady);

    testWidgets('טקסט ריק לא תופס גובה', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '',
            settings: RenderSettings(fontSize: 20),
          ),
        ),
      );

      expect(find.byType(HtmlWidget), findsNothing);
      expect(find.byType(RichText), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('justifyText=false מיישר לימין במסלול המהיר', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: 'טקסט קצר',
            settings: RenderSettings(fontSize: 20, justifyText: false),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textAlign, TextAlign.right);
    });
  });

  group('SmartTextWidget — גופן הכותרות', () {
    // רגרסיה: fwfh נותן ל-<h1>-<h6> font-weight:bold, ואז משפחה עם face בולד
    // נפרד (פרנק-רוהל) שולפת את הכותרת מקובץ אחר מהגוף — שני גופנים במסך.
    testWidgets('כותרת נשארת במשקל הגוף ולא עוברת ל-face הבולד', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '<h2>דף ה.</h2>',
            settings: RenderSettings(
              fontSize: 20,
              fontFamily: 'FrankRuhlCLM',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final heading = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((w) => w.text.toPlainText().contains('דף ה.'));
      final style = heading.text.style;
      expect(style?.fontFamily, 'FrankRuhlCLM');
      expect(style?.fontWeight, FontWeight.w400);
    });

    // גופן מערכת שנמצא לו קובץ בולד אחי — אותה תקלה כמו פרנק-רוהל.
    testWidgets('גופן מערכת עם קובץ בולד אחי — הכותרת אינה מודגשת', (
      tester,
    ) async {
      addTearDown(AppFonts.debugResetSystemFontsCache);
      AppFonts.debugMarkSeparateBoldSystemFont('Some Installed Serif');

      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '<h2>דף ה.</h2>',
            settings: RenderSettings(
              fontSize: 20,
              fontFamily: 'Some Installed Serif',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final heading = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((w) => w.text.toPlainText().contains('דף ה.'));
      expect(heading.text.style?.fontWeight, FontWeight.w400);
    });

    // גופן בלי face בולד נפרד — הבולד הוא אותו ציור אות, ולכן נשמר.
    testWidgets('גופן ללא face בולד נפרד — הכותרת נשארת מודגשת', (
      tester,
    ) async {
      for (final font in const [
        'TaameyDavidCLM',
        'KeterYG',
        'Shofar',
        'NotoRashiHebrew',
      ]) {
        await tester.pumpWidget(
          _wrap(
            SmartTextWidget(
              text: '<h2>דף ה.</h2>',
              settings: RenderSettings(fontSize: 20, fontFamily: font),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final heading = tester
            .widgetList<RichText>(find.byType(RichText))
            .firstWhere((w) => w.text.toPlainText().contains('דף ה.'));
        expect(
          heading.text.style?.fontWeight,
          FontWeight.bold,
          reason: '$font: הכותרת אמורה להישאר מודגשת',
        );
      }
    });

    testWidgets('<b> עדיין מקבל בולד — התיקון לא מבטל הדגשה אמיתית', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: '<h2>דף <b>ה.</b></h2>',
            settings: RenderSettings(
              fontSize: 20,
              fontFamily: 'FrankRuhlCLM',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final heading = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((w) => w.text.toPlainText().contains('ה.'));
      var foundBold = false;
      heading.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text != null &&
            span.text!.contains('ה.') &&
            span.style?.fontWeight == FontWeight.bold) {
          foundBold = true;
        }
        return true;
      });
      expect(foundBold, isTrue);
    });
  });
}
