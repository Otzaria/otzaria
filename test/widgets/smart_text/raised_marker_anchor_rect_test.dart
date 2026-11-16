import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

/// שורות אמיתיות מ"שמירת שבת כהלכתה - א" — סימון בסוגריים בין רווחים,
/// שהוא המקרה שבו הבאג נצפה.
const _lineWithSpacedMarker =
    'על ידי חום האש <sup>(א)</sup> או תולדותיה, הרי זה עובר על איסור בישול.';

Future<void> _loadReadingFont() async {
  final bytes = File('fonts/FrankRuehlCLM-Medium.ttf').readAsBytesSync();
  await (FontLoader(
    'FrankRuhlCLM',
  )..addFont(Future.value(bytes.buffer.asByteData()))).load();
}

void main() {
  group('sameLineAnchorRect — איחוד תיבות של אותה שורה', () {
    // המספרים לקוחים מפריסה אמיתית של '<sup>(א)</sup>' ב-FrankRuhlCLM:
    // תווי הבידוד (RLI/PDI) חסרים בגופן ונופלים לגופן גיבוי גבוה יותר, ולכן
    // התיבה שלהם מתחילה 2.78px מעל תיבת האותיות — באותה שורה בדיוק.
    test('תיבת בקרה מגופן גיבוי מתאחדת עם תיבת האותיות', () {
      final rect = sameLineAnchorRect(const [
        TextBox.fromLTRBD(558.8, 47.46, 559.1, 69.33, TextDirection.rtl),
        TextBox.fromLTRBD(559.1, 50.24, 578.9, 68.47, TextDirection.rtl),
        TextBox.fromLTRBD(578.9, 47.46, 579.1, 69.33, TextDirection.rtl),
      ])!;

      expect(rect.left, closeTo(558.8, 0.01));
      expect(rect.right, closeTo(579.1, 0.01));
      expect(
        rect.width,
        greaterThan(15),
        reason: 'העוגן חייב לכסות את האותיות, לא רק את תו הבקרה',
      );
    });

    test('תיבה של השורה הבאה אינה מתאחדת', () {
      final rect = sameLineAnchorRect(const [
        TextBox.fromLTRBD(0, 47.46, 12, 69.33, TextDirection.rtl),
        TextBox.fromLTRBD(600, 87.46, 620, 109.33, TextDirection.rtl),
      ])!;

      expect(rect.right, closeTo(12, 0.01));
    });

    test('רשימה ריקה מחזירה null', () {
      expect(sameLineAnchorRect(const []), isNull);
    });
  });

  group('RaisedMarkerOverlay — עוגן בגופן הקריאה האמיתי', () {
    testWidgets('הסימון מצויר על האותיות שלו ולא על הרווח שאחריהן', (
      tester,
    ) async {
      await _loadReadingFont();

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 700,
                  child: SmartTextWidget(
                    text: _lineWithSpacedMarker,
                    settings: const RenderSettings(
                      fontFamily: 'FrankRuhlCLM',
                      fontSize: 25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final overlay = tester.renderObject<RenderRaisedMarkerOverlay>(
        find.byType(RaisedMarkerOverlay),
      );
      final placement = overlay.debugPlacements().single;

      // רוחב העוגן חייב להיות רוחב "(א)" ולא רוחב תו בקרה.
      expect(
        placement.anchorRect.width,
        greaterThan(placement.paintRect.width * 0.8),
        reason: 'העוגן קרס לתיבת תו הבידוד — הציור יוצא מוזז מהאותיות',
      );

      // הרווחים משני צדי הסימון חייבים להישאר פנויים מהציור.
      RenderParagraph? paragraph;
      void visit(RenderObject object) {
        if (object is RenderParagraph) {
          paragraph ??= object;
          return;
        }
        object.visitChildren(visit);
      }

      visit(tester.renderObject(find.byType(RaisedMarkerOverlay)));
      final plain = paragraph!.text.toPlainText();
      final markerStart = plain.indexOf(String.fromCharCode(0x2067));
      final markerEnd = plain.indexOf(String.fromCharCode(0x2069)) + 1;

      Rect charRect(int index) => paragraph!
          .getBoxesForSelection(
            TextSelection(baseOffset: index, extentOffset: index + 1),
          )
          .first
          .toRect();

      final spaceBefore = charRect(markerStart - 1);
      final spaceAfter = charRect(markerEnd);

      expect(
        placement.paintRect.right,
        lessThanOrEqualTo(spaceBefore.right),
        reason: 'הציור גלש מעל הרווח שלפני הסימון',
      );
      expect(
        placement.paintRect.left,
        greaterThanOrEqualTo(spaceAfter.left),
        reason: 'הציור גלש מעל הרווח והמילה שאחרי הסימון',
      );
    });
  });

  // issue #1402: בטקסט בר-בחירה getBoxesForSelection מחזיר תיבה בגובה השורה,
  // והסימון הורם מראש השורה אל השורה שמעליה.
  testWidgets('בתוך SelectionArea הסימון מורם מהאותיות ולא מראש השורה', (
    tester,
  ) async {
    await _loadReadingFont();

    Future<RaisedMarkerPlacement> placementOf({
      required bool selectable,
    }) async {
      RaisedMarkers.clearCacheForTesting();
      Widget text = SmartTextWidget(
        text:
            'צפהו זהב במקום הנחת פה '
            '<a class="link-anchor link-anchor-0" '
            'href="otzaria://anchor?ref=3_0">(ע)</a> היינו עובי השופר',
        settings: const RenderSettings(
          fontSize: 26,
          fontFamily: 'FrankRuhlCLM',
          lineHeight: 2.2,
        ),
        onAnchorTap: (_) {},
      );
      if (selectable) text = SelectionArea(child: text);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: text),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .renderObject<RenderRaisedMarkerOverlay>(
            find.byWidgetPredicate((w) => w is RaisedMarkerOverlay),
          )
          .debugPlacements()
          .single;
    }

    final plain = await placementOf(selectable: false);
    final selectable = await placementOf(selectable: true);

    expect(selectable.anchorRect, plain.anchorRect);
    expect(selectable.paintRect, plain.paintRect);
  });

  // issue #4606: "תורה תמימה" — שורה שנגמרת בסימון, נקודה ו-<br>. Skia מזיז
  // ימינה את תיבות השורה שלפני השבירה, והסימון צויר על האות שלפניו.
  testWidgets('סימון לפני נקודה ו-<br> מצויר במקומו כמו בלי ה-<br>', (
    tester,
  ) async {
    await _loadReadingFont();
    const line =
        '<b>בראשית.</b> תניא, למה נברא העולם בבי"ת ולא באל"ף, מפני שהבי"ת '
        'לשון ברכה והאל"ף לשון ארירה, אמר הקב"ה, אינני בורא אותו באל"ף '
        'שלא יאמרו איך יעמוד העולם שנברא בלשון ארירה, אלא הרי אני בורא '
        'אותו בבי"ת בלשון ברכה ולואי יעמוד <sup class="footnote-marker">ד</sup>.';

    Future<Rect> anchorOf(String text) async {
      RaisedMarkers.clearCacheForTesting();
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 700,
                  child: SmartTextWidget(
                    text: text,
                    settings: const RenderSettings(
                      fontFamily: 'FrankRuhlCLM',
                      fontSize: 25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .renderObject<RenderRaisedMarkerOverlay>(
            find.byType(RaisedMarkerOverlay),
          )
          .debugPlacements()
          .single
          .anchorRect;
    }

    final reference = await anchorOf(line);
    final withBreak = await anchorOf('$line<br>(ירושלמי חגיגה פ"ב ה"א)');

    expect(withBreak.left, closeTo(reference.left, 0.5));
    expect(withBreak.right, closeTo(reference.right, 0.5));
  });

  testWidgets('ספאן מקונן ושני קישורים שומרים על יעדים נפרדים ועל בחירה', (
    tester,
  ) async {
    await _loadReadingFont();
    final tapped = <String>[];
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 500,
              child: SelectionArea(
                onSelectionChanged: (content) => selected = content?.plainText,
                child: SmartTextWidget(
                  text:
                      'לפני <a class="link-anchor link-anchor-0" '
                      'href="otzaria://anchor?ref=5_0"><b><small>ד</small></b></a> '
                      'טקסט רגיל בין הקישורים '
                      '<a class="link-anchor link-anchor-0" '
                      'href="otzaria://anchor?ref=6_0">ה</a>.<br>שורה שניה',
                  settings: const RenderSettings(
                    fontFamily: 'FrankRuhlCLM',
                    fontSize: 25,
                  ),
                  onAnchorTap: tapped.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final overlay = tester.renderObject<RenderRaisedMarkerOverlay>(
      find.byType(RaisedMarkerOverlay),
    );
    final placements = overlay.debugPlacements();
    expect(placements, hasLength(2));
    for (final placement in placements) {
      await tester.tapAt(overlay.localToGlobal(placement.paintRect.center));
      await tester.pump();
    }
    expect(tapped, ['otzaria://anchor?ref=5_0', 'otzaria://anchor?ref=6_0']);
    tapped.clear();
    await tester.tapAt(
      overlay.localToGlobal(Offset(5, overlay.size.height - 5)),
    );
    await tester.pump();
    expect(tapped, isEmpty);
    await tester.longPressAt(
      overlay.localToGlobal(placements.first.paintRect.center),
    );
    await tester.pumpAndSettle();
    expect(tapped, isEmpty, reason: 'בחירת טקסט אינה מפעילה קישור');
    expect(selected, isNotEmpty);
  });

  for (final prefix in ['נעשו ', '']) {
    for (final selectable in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'סימון לפני שבירה נשאר לחיץ ובר-ריחוף: בחירה=$selectable, קנה מידה=$scale, קידומת=$prefix',
          (tester) async {
            await _loadReadingFont();
            const url = 'otzaria://anchor?ref=5_0';
            for (final suffix in ['', '<br>שורה שניה']) {
              RaisedMarkers.clearCacheForTesting();
              String? tapped;
              final hovered = <String>[];
              Widget text = SmartTextWidget(
                text:
                    '$prefix<a class="link-anchor link-anchor-0" href="$url">ד</a>.$suffix',
                settings: const RenderSettings(
                  fontFamily: 'FrankRuhlCLM',
                  fontSize: 25,
                ),
                onAnchorTap: (value) => tapped = value,
                onAnchorHover: (value, _) => hovered.add(value),
              );
              if (selectable) text = SelectionArea(child: text);
              await tester.pumpWidget(
                MaterialApp(
                  home: Directionality(
                    textDirection: TextDirection.rtl,
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Scaffold(
                        body: Align(
                          alignment: Alignment.topRight,
                          child: SizedBox(width: 500, child: text),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final overlay = tester.renderObject<RenderRaisedMarkerOverlay>(
                find.byType(RaisedMarkerOverlay),
              );
              final placement = overlay.debugPlacements().single;
              final point = overlay.localToGlobal(placement.paintRect.center);
              await tester.tapAt(point);
              await tester.pump();
              expect(tapped, url, reason: 'לחיצה על הסימון; suffix=$suffix');

              final mouse = await tester.createGesture(
                kind: PointerDeviceKind.mouse,
              );
              await mouse.addPointer(location: Offset.zero);
              await mouse.moveTo(point);
              await tester.pump();
              expect(hovered, contains(url), reason: 'ריחוף; suffix=$suffix');
              await mouse.removePointer();
            }
          },
        );
      }
    }
  }
}
