import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

const _long =
    'בראשית ברא אלהים את השמים ואת הארץ והארץ היתה תהו ובהו וחשך על פני תהום '
    'ורוח אלהים מרחפת על פני המים ויאמר אלהים יהי אור ויהי אור וירא אלהים';
const _source = '<b>בראשית ברא</b> $_long';
const _settings = RenderSettings(fontSize: 20, fontFamily: 'FrankRuhlCLM');

Future<PluginCorrectionSessionService> _begin(
  WidgetTester tester,
  List<String> sources,
) async {
  final db = sqlite3.openInMemory();
  addTearDown(db.close);
  final service = PluginCorrectionSessionService()
    ..draftRepository = PluginCorrectionDraftRepository.direct(db);
  addTearDown(service.dispose);
  await tester.runAsync(
    () => service.begin(
      owner: 'owner',
      tabId: 'tab',
      bookId: 'ספר',
      bookUid: 'id:1',
      libraryVersion: '1',
      loadSource: (index) async => sources[index],
    ),
  );
  return service;
}

Widget _paragraph(
  PluginCorrectionSessionService service,
  int index,
  String source, {
  Widget? original,
}) => PluginCorrectionParagraph(
  tabId: 'tab',
  sectionIndex: index,
  sourceText: source,
  settings: _settings,
  original: original ?? SmartTextWidget(text: source, settings: _settings),
  service: service,
  sessionActive: true,
);

Widget _app(Widget body) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: body),
  ),
);

Future<void> _finish(
  WidgetTester tester,
  PluginCorrectionSessionService service,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() async {
    await service.flushAll();
    await service.shutdown(timeout: const Duration(seconds: 5));
  });
}

/// לחיצת עכבר על הפסקה. אם לחיצה אחת לא הפעילה עריכה (התנהגות ישנה),
/// נוספת לחיצה שנייה בחלון הכפול. בסוף ממתינים מעבר לחלון הלחיצה הכפולה.
Future<void> _click(WidgetTester tester, Offset point) async {
  Future<void> press() async {
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 50));
  }

  await press();
  if (find.byType(EditableText).evaluate().isEmpty) await press();
  // פריימים רצופים כמו באפליקציה, ולא קפיצת זמן אחת.
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader('FrankRuhlCLM')
          ..addFont(rootBundle.load('fonts/FrankRuehlCLM-Medium.ttf'))
          ..addFont(rootBundle.load('fonts/FrankRuehlCLM-Bold.ttf')))
        .load();
  });

  // רוחבים שבהם ריווח האותיות של שדה טקסט (0.5) שובר שורה אחרת מהקורא.
  for (final width in [195.0, 228.0, 264.0, 327.0, 441.0]) {
    testWidgets('העורך שובר שורות בדיוק כמו התצוגה הרגילה ברוחב $width', (
      tester,
    ) async {
      final service = await _begin(tester, [_source]);
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: width,
              child: _paragraph(service, 0, _source),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reading = tester.getSize(find.byType(SmartTextWidget));
      await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
      expect(find.byType(EditableText), findsOneWidget);
      final editor = tester.getSize(find.byType(EditableText));
      expect(editor.height, reading.height);
      await _finish(tester, service);
    });
  }

  // עיצוב הסוגריים של הקורא (טקסט מוקטן) משנה שבירת שורות; העורך חייב לשקף אותו.
  final parenthesized = {
    'סוגריים':
        'בראשית ברא אלהים את השמים ואת הארץ (והארץ היתה תהו ובהו וחשך '
        'על פני תהום) ורוח אלהים מרחפת על פני המים ויאמר אלהים יהי אור',
    'סוגריים בתוך small':
        'בראשית ברא אלהים את השמים ואת הארץ <small>(והארץ '
        'היתה תהו ובהו וחשך על פני תהום)</small> ורוח אלהים מרחפת על פני המים',
  };
  for (final entry in parenthesized.entries) {
    for (final format in [true, false]) {
      testWidgets(
        'שבירת השורות בעורך זהה לקורא: ${entry.key}, עיצוב סוגריים=$format',
        (tester) async {
          final source = entry.value;
          final settings = _settings.copyWith(formatParentheses: format);
          final service = await _begin(tester, [source]);
          final mismatches = <double>[];
          for (var width = 180.0; width <= 480; width += 3) {
            await tester.pumpWidget(
              _app(
                Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    width: width,
                    child: PluginCorrectionParagraph(
                      tabId: 'tab',
                      sectionIndex: 0,
                      sourceText: source,
                      settings: settings,
                      original: SmartTextWidget(
                        text: source,
                        settings: settings,
                      ),
                      service: service,
                      sessionActive: true,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final reading = tester.getSize(find.byType(SmartTextWidget));
            await _click(
              tester,
              tester.getCenter(find.byType(SmartTextWidget)),
            );
            if (tester.getSize(find.byType(EditableText)).height !=
                reading.height) {
              mismatches.add(width);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(seconds: 1));
          }
          expect(mismatches, isEmpty);
          await _finish(tester, service);
        },
      );
    }
  }

  testWidgets('העורך יורש ריווח אותיות ומילים מהתצוגה הרגילה', (tester) async {
    final service = await _begin(tester, [_source]);
    await tester.pumpWidget(
      _app(
        DefaultTextStyle(
          style: const TextStyle(letterSpacing: 0.25, wordSpacing: 1.5),
          child: _paragraph(service, 0, _source),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
    final style = tester.widget<EditableText>(find.byType(EditableText)).style;
    expect(style.letterSpacing, 0.25);
    expect(style.wordSpacing, 1.5);
    await _finish(tester, service);
  });

  testWidgets('שדה העורך רחב מהפסקה בשוליים של הסמן בלבד', (tester) async {
    final service = await _begin(tester, [_source]);
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topRight,
          child: SizedBox(width: 300, child: _paragraph(service, 0, _source)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
    expect(tester.getSize(find.byType(PluginCorrectionParagraph)).width, 300);
    expect(tester.getSize(find.byType(EditableText)).width, 302);
    await _finish(tester, service);
  });

  testWidgets('גובה הפסקה נשמר בהחלפה לעורך ומשתחרר בשינוי רוחב', (
    tester,
  ) async {
    const source = 'שורה אחת';
    final service = await _begin(tester, [source]);
    Widget build(double width) => _app(
      Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: width,
          child: _paragraph(
            service,
            0,
            source,
            original: const SizedBox(height: 120, child: Text('קריאה')),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(300));
    final before = tester.getSize(find.byType(PluginCorrectionParagraph));
    await _click(tester, tester.getCenter(find.text('קריאה')));
    expect(find.byType(EditableText), findsOneWidget);
    expect(tester.getSize(find.byType(PluginCorrectionParagraph)), before);
    await tester.pumpWidget(build(200));
    await tester.pump();
    expect(
      tester.getSize(find.byType(PluginCorrectionParagraph)).height,
      lessThan(before.height),
    );
    await _finish(tester, service);
  });

  testWidgets('נעילת הגובה משתחררת בשינוי הגדרות ובתיקון ראשון', (
    tester,
  ) async {
    const source = 'שורה אחת';
    final service = await _begin(tester, [source]);
    Widget build(RenderSettings settings) => _app(
      Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: 300,
          child: PluginCorrectionParagraph(
            tabId: 'tab',
            sectionIndex: 0,
            sourceText: source,
            settings: settings,
            original: const SizedBox(height: 120, child: Text('קריאה')),
            service: service,
            sessionActive: true,
          ),
        ),
      ),
    );
    double height() =>
        tester.getSize(find.byType(PluginCorrectionParagraph)).height;
    await tester.pumpWidget(build(_settings));
    await _click(tester, tester.getCenter(find.text('קריאה')));
    expect(height(), 120);
    await tester.pumpWidget(build(_settings.copyWith(fontSize: 21)));
    await tester.pump();
    expect(height(), lessThan(120));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(build(_settings));
    await _click(tester, tester.getCenter(find.text('קריאה')));
    expect(height(), 120);
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'שורה אחתי',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    await tester.pump();
    expect(service.isCorrected('tab', 0, source), isTrue);
    expect(height(), lessThan(120));
    await _finish(tester, service);
  });

  testWidgets('הפעלה בעכבר אינה גוללת את הדף', (tester) async {
    final service = await _begin(tester, [_source]);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 300,
          child: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 250),
              _paragraph(service, 0, _source),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(SmartTextWidget));
    // סמוך לקצה התחתון של החלון, בטווח ש-EditableText חושף אותו בגלילה עצמית.
    final viewport = tester.getRect(find.byType(ListView));
    await _click(tester, Offset(rect.center.dx, viewport.bottom - 4));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    expect(controller.offset, 0);
    await _finish(tester, service);
  });

  testWidgets('לחיצה אחת מפעילה עריכה, ולחיצה כפולה יוצאת ממנה', (
    tester,
  ) async {
    final service = await _begin(tester, [_source]);
    await tester.pumpWidget(_app(_paragraph(service, 0, _source)));
    await tester.pumpAndSettle();
    await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
    expect(find.byType(EditableText), findsOneWidget);
    final editorPoint = tester.getCenter(find.byType(EditableText));
    await tester.tapAt(editorPoint);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(editorPoint);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(SmartTextWidget), findsOneWidget);
    await _finish(tester, service);
  });

  testWidgets('יציאה בלחיצה כפולה מחזירה את המיקוד לקורא', (tester) async {
    final service = await _begin(tester, [_source]);
    final reader = FocusNode();
    addTearDown(reader.dispose);
    await tester.pumpWidget(
      _app(Focus(focusNode: reader, child: _paragraph(service, 0, _source))),
    );
    await tester.pumpAndSettle();
    await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
    final editorPoint = tester.getCenter(find.byType(EditableText));
    await tester.tapAt(editorPoint);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(editorPoint);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
    expect(reader.hasPrimaryFocus, isTrue);
    await _finish(tester, service);
  });

  testWidgets('לחיצה כפולה בפסקה שתוקנה משאירה את העורך פתוח', (tester) async {
    const source = 'שורה אחת';
    final service = await _begin(tester, [source]);
    await tester.pumpWidget(_app(_paragraph(service, 0, source)));
    await tester.pumpAndSettle();
    await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'שורה אחתי',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    await tester.pump();
    expect(service.isCorrected('tab', 0, source), isTrue);
    final editorPoint = tester.getCenter(find.byType(EditableText));
    await tester.tapAt(editorPoint);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(editorPoint);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 8),
      ),
    );
    await tester.pump();
    expect(service.isCorrected('tab', 0, source), isFalse);
    expect(find.byType(EditableText), findsOneWidget);
    await _finish(tester, service);
  });

  testWidgets('לחיצה מיד אחרי גרירה לסימון אינה יוצאת מהעריכה', (
    tester,
  ) async {
    final service = await _begin(tester, [_source]);
    await tester.pumpWidget(_app(_paragraph(service, 0, _source)));
    await tester.pumpAndSettle();
    await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
    final rect = tester.getRect(find.byType(EditableText));
    final end = rect.center - const Offset(60, 0);
    await tester.dragFrom(rect.center, end - rect.center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(end);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    await _finish(tester, service);
  });

  for (final distance in [16.0, 80.0]) {
    testWidgets(
      'גרירת עכבר של $distance פיקסלים אחרי לחיצה אינה סוגרת את העורך',
      (tester) async {
        final service = await _begin(tester, [_source]);
        await tester.pumpWidget(_app(_paragraph(service, 0, _source)));
        await tester.pumpAndSettle();
        await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
        final editor = find.byType(EditableText);
        final point = tester.getCenter(editor);
        await tester.tapAt(point, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 50));
        final drag = await tester.startGesture(
          point,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await drag.moveBy(const Offset(-6, 0));
        await tester.pump();
        await drag.moveBy(Offset(6 - distance, 0));
        await tester.pump();
        final duringDrag = tester
            .widget<EditableText>(editor)
            .controller
            .selection;
        await drag.up();
        await tester.pumpAndSettle();
        final afterDrag = tester
            .widgetList<EditableText>(editor)
            .firstOrNull
            ?.controller
            .selection;
        await _finish(tester, service);
        expect(duringDrag.isCollapsed, isFalse);
        expect(afterDrag, duringDrag);
      },
      variant: const TargetPlatformVariant({TargetPlatform.windows}),
    );
  }

  group('לחיצה שאינה כפולה אינה יוצאת מהעריכה', () {
    Future<Offset> open(WidgetTester tester) async {
      final service = await _begin(tester, [_source]);
      await tester.pumpWidget(_app(_paragraph(service, 0, _source)));
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
      expect(find.byType(EditableText), findsOneWidget);
      addTearDown(() => _finish(tester, service));
      return tester.getCenter(find.byType(EditableText));
    }

    testWidgets('לחיצה שנייה אחרי חלון הלחיצה הכפולה', (tester) async {
      final point = await open(tester);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('לחיצה שנייה רחוקה מהראשונה', (tester) async {
      await open(tester);
      final rect = tester.getRect(find.byType(EditableText));
      final first = rect.topLeft + const Offset(20, 5);
      final second = rect.bottomRight - const Offset(20, 5);
      expect((second - first).distance, greaterThan(kDoubleTapSlop));
      await tester.tapAt(first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(second);
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('לחיצה בכפתור משני אחרי לחיצה ראשית', (tester) async {
      final point = await open(tester);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsOneWidget);
    });
  });

  testWidgets('הדיכוי של הגלילה העצמית פג אחרי ההפעלה', (tester) async {
    final service = await _begin(tester, [_source]);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 300,
          child: ListView(
            controller: controller,
            children: [
              const SizedBox(height: 250),
              _paragraph(service, 0, _source),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(SmartTextWidget));
    final viewport = tester.getRect(find.byType(ListView));
    await _click(tester, Offset(rect.center.dx, viewport.bottom - 4));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    tester.renderObject(find.byType(EditableText)).showOnScreen();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    await _finish(tester, service);
  });

  testWidgets('אובדן מיקוד אינו סוגר את העורך', (tester) async {
    final service = await _begin(tester, [_source]);
    await tester.pumpWidget(_app(_paragraph(service, 0, _source)));
    await tester.pumpAndSettle();
    await _click(tester, tester.getCenter(find.byType(SmartTextWidget)));
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    editor.focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    await _finish(tester, service);
  });

  testWidgets('רק פסקה אחת פעילה בכל רגע', (tester) async {
    const sources = ['פסקה אחת', 'פסקה שתיים'];
    final service = await _begin(tester, sources);
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            for (var i = 0; i < 2; i++)
              _paragraph(service, i, sources[i], original: Text('קריאה $i')),
          ],
        ),
      ),
    );
    await _click(tester, tester.getCenter(find.text('קריאה 0')));
    await _click(tester, tester.getCenter(find.text('קריאה 1')));
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text('קריאה 0'), findsOneWidget);
    await _finish(tester, service);
  });
}
