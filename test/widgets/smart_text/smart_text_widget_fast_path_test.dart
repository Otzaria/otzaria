import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
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
    testWidgets('שורה פשוטה מרונדרת ב-Text.rich בלי HtmlWidget',
        (tester) async {
      await tester.pumpWidget(_wrap(const SmartTextWidget(
        text: 'ויאמר משה אל העם',
        settings: RenderSettings(fontSize: 20),
      )));

      expect(find.byType(HtmlWidget), findsNothing);
      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.text.toPlainText(), 'ויאמר משה אל העם');
      expect(richText.textAlign, TextAlign.justify);
    });

    testWidgets('שורה עם תג b נשארת במסלול המהיר עם span מודגש',
        (tester) async {
      await tester.pumpWidget(_wrap(const SmartTextWidget(
        text: '<b>דיבור המתחיל</b> ביאור הדברים',
        settings: RenderSettings(fontSize: 20),
      )));

      expect(find.byType(HtmlWidget), findsNothing);
      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.text.toPlainText(), 'דיבור המתחיל ביאור הדברים');
    });

    testWidgets('markup מורכב (span עם class) נופל ל-HtmlWidget',
        (tester) async {
      await tester.pumpWidget(_wrap(const SmartTextWidget(
        text: 'טקסט <span class="link-anchor">א</span>',
        settings: RenderSettings(fontSize: 20),
      )));

      expect(find.byType(HtmlWidget), findsOneWidget);
    });

    testWidgets('הדגשת חיפוש פעילה נופלת ל-HtmlWidget רק בשורה עם התאמה',
        (tester) async {
      await tester.pumpWidget(_wrap(const Column(
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
      )));

      // השורה עם ההתאמה מקבלת span של הדגשה → HtmlWidget;
      // השורה בלי התאמה נשארת במסלול המהיר.
      expect(find.byType(HtmlWidget), findsOneWidget);
    }, skip: !engineReady);

    testWidgets('טקסט ריק לא תופס גובה', (tester) async {
      await tester.pumpWidget(_wrap(const SmartTextWidget(
        text: '',
        settings: RenderSettings(fontSize: 20),
      )));

      expect(find.byType(HtmlWidget), findsNothing);
      expect(find.byType(RichText), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('justifyText=false מיישר לימין במסלול המהיר', (tester) async {
      await tester.pumpWidget(_wrap(const SmartTextWidget(
        text: 'טקסט קצר',
        settings: RenderSettings(fontSize: 20, justifyText: false),
      )));

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.textAlign, TextAlign.right);
    });
  });
}
