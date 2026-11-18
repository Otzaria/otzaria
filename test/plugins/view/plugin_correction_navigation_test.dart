import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

void main() {
  const sources = ['פסקה ראשונה', 'פסקה שנייה'];

  Future<PluginCorrectionSessionService> begin(WidgetTester tester) async {
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

  Future<void> pump(
    WidgetTester tester,
    PluginCorrectionSessionService service, {
    String searchText = '',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < sources.length; i++)
                PluginCorrectionParagraph(
                  tabId: 'tab',
                  sectionIndex: i,
                  sourceText: sources[i],
                  settings: RenderSettings(searchText: searchText),
                  original: Text('קריאה $i'),
                  service: service,
                  sessionActive: true,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> finish(
    WidgetTester tester,
    PluginCorrectionSessionService service,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => service.flushAll());
  }

  testWidgets('חץ מטה בשורה האחרונה מעביר עריכה לפסקה הבאה, וחץ מעלה חוזר', (
    tester,
  ) async {
    final service = await begin(tester);
    await pump(tester, service);
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text('קריאה 1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final editors = find.byType(EditableText);
    expect(editors, findsOneWidget);
    expect(
      tester.widget<EditableText>(editors).controller.text,
      sources[1],
    );
    expect(tester.widget<EditableText>(editors).focusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      sources[0],
    );
    await finish(tester, service);
  });

  testWidgets('חץ מטה ומעלה שומר על אותו מקום אופקי בפסקה הסמוכה', (
    tester,
  ) async {
    final service = await begin(tester);
    await pump(tester, service);
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.pump();
    EditableText editor() =>
        tester.widget<EditableText>(find.byType(EditableText));
    editor().controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(editor().controller.text, sources[1]);
    expect(editor().controller.selection.baseOffset, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(editor().controller.text, sources[0]);
    expect(editor().controller.selection.baseOffset, 3);
    await finish(tester, service);
  });

  testWidgets('לחיצה אחת מפעילה עריכה, ושדה העריכה מקבל ירידת שורה', (
    tester,
  ) async {
    final service = await begin(tester);
    await pump(tester, service);
    await tester.tap(find.text('קריאה 0'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump(const Duration(seconds: 1));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'פסקה\n ראשונה',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(service.editableText('tab', 0, sources[0]), 'פסקה\n ראשונה');
    expect(service.isCorrected('tab', 0, sources[0]), isTrue);
    await finish(tester, service);
  });

  testWidgets('הפעלת עריכה אינה מקטינה את גובה הפסקה', (tester) async {
    final service = await begin(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: [
                PluginCorrectionParagraph(
                  tabId: 'tab',
                  sectionIndex: 0,
                  sourceText: sources[0],
                  settings: const RenderSettings(),
                  original: const SizedBox(height: 150, child: Text('קריאה 0')),
                  service: service,
                  sessionActive: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final before = tester
        .getSize(find.byType(PluginCorrectionParagraph))
        .height;
    expect(before, 150);
    await tester.tap(find.text('קריאה 0'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    expect(
      tester.getSize(find.byType(PluginCorrectionParagraph)).height,
      greaterThanOrEqualTo(before),
    );
    await finish(tester, service);
  });

  testWidgets('בפסקה של כמה שורות החצים נעים בין השורות ורק בקצה עוברים הלאה', (
    tester,
  ) async {
    const long = 'אבגד הוזח טיכל מנסע פצקר שתאב גדהו זחטי כלמנ סעפצ קרשת';
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final service = PluginCorrectionSessionService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    addTearDown(service.dispose);
    final texts = [long, 'פסקה שנייה'];
    await tester.runAsync(
      () => service.begin(
        owner: 'owner',
        tabId: 'tab',
        bookId: 'ספר',
        bookUid: 'id:1',
        libraryVersion: '1',
        loadSource: (index) async => texts[index],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 160,
                child: Column(
                  children: [
                    for (var i = 0; i < texts.length; i++)
                      PluginCorrectionParagraph(
                        tabId: 'tab',
                        sectionIndex: i,
                        sourceText: texts[i],
                        settings: const RenderSettings(fontSize: 14),
                        original: Text('קריאה $i'),
                        service: service,
                        sessionActive: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('קריאה 0'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    EditableText editor() =>
        tester.widget<EditableText>(find.byType(EditableText));
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final lines = <int>{};
    for (var i = 0; i < long.length; i++) {
      lines.add(render.getLineAtOffset(TextPosition(offset: i)).start);
    }
    expect(
      lines.length,
      greaterThan(2),
      reason: 'הפסקה חייבת להתפרש על כמה שורות',
    );
    editor().controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    var offset = 1;
    // חץ מטה בשורה הראשונה: נשארים בפסקה והסמן יורד שורה.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(editor().controller.text, long);
    expect(editor().controller.selection.baseOffset, greaterThan(offset));
    offset = editor().controller.selection.baseOffset;
    // חץ מעלה מהשורה האמצעית: חוזרים לשורה הראשונה, עדיין באותה פסקה.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(editor().controller.text, long);
    expect(editor().controller.selection.baseOffset, lessThan(offset));
    // בשורה האחרונה חץ מטה עובר לפסקה הבאה.
    editor().controller.selection = TextSelection.collapsed(
      offset: long.length,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(editor().controller.text, texts[1]);
    await finish(tester, service);
  });

  testWidgets('העורך שובר שורות בדיוק כמו התצוגה הרגילה ברוחב צמוד', (
    tester,
  ) async {
    // בגופן הבדיקות כל תו ברוחב גודל הגופן; 4 מילים (19 תווים) עם ריווח 0.25 הן
    // 194.75 פיקסלים: נכנסות ב-196, אבל לא עם ריווח 0.5 או בלי 2 פיקסלי הסמן.
    final words = List.filled(20, 'אבגד').join(' ');
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
        loadSource: (_) async => words,
      ),
    );
    const settings = RenderSettings(fontSize: 10, lineHeight: 1.5);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 196,
                child: PluginCorrectionParagraph(
                  tabId: 'tab',
                  sectionIndex: 0,
                  sourceText: words,
                  settings: settings,
                  original: Text(
                    words,
                    textAlign: TextAlign.justify,
                    style: const TextStyle(fontSize: 10, height: 1.5),
                  ),
                  service: service,
                  sessionActive: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final before = tester.getSize(find.byType(PluginCorrectionParagraph));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(words));
    // תחילת כל שורה: ההיסט הראשון שבו הסמן יורד לשורה חדשה.
    List<int> lineStarts(double Function(int) top) {
      final starts = <int>[0];
      for (var i = 1; i < words.length; i++) {
        if (top(i) > top(i - 1) + 1) starts.add(i);
      }
      return starts;
    }

    final originalStarts = lineStarts(
      (i) => paragraph.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy,
    );
    expect(originalStarts.length, greaterThan(2));
    await tester.tap(find.text(words));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.byType(EditableText), findsOneWidget);
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final editorStarts = lineStarts(
      (i) => render.getLocalRectForCaret(TextPosition(offset: i)).top,
    );
    expect(editorStarts, originalStarts);
    expect(tester.getSize(find.byType(PluginCorrectionParagraph)), before);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => service.flushAll());
  });

  testWidgets('לחיצה על שורה חתוכה בקצה התחתון של התצוגה אינה גוללת את הדף', (
    tester,
  ) async {
    final service = await begin(tester);
    final scroll = ScrollController(initialScrollOffset: 100);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 690),
                  PluginCorrectionParagraph(
                    tabId: 'tab',
                    sectionIndex: 0,
                    sourceText: sources[0],
                    settings: const RenderSettings(fontSize: 14),
                    original: const SizedBox(
                      height: 28,
                      child: Text('קריאה 0'),
                    ),
                    service: service,
                    sessionActive: true,
                  ),
                  const SizedBox(height: 900),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // הפסקה מתחילה 10 פיקסלים לפני סוף התצוגה (גובה 600, גלילה 100): רק
    // חלקה העליון נראה, ולחיצה עליו לא אמורה לחשוף את שאר הסמן בגלילה.
    final paragraph = tester.getRect(find.byType(PluginCorrectionParagraph));
    expect(paragraph.top, 590);
    await tester.tapAt(Offset(paragraph.center.dx, 595));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    expect(scroll.offset, 100);
    await finish(tester, service);
  });

  testWidgets('פסקה מעוצבת (סוגריים מוקטנים, מודגש) נשברת בעורך כמו בקורא', (
    tester,
  ) async {
    // הקורא מקטין טקסט בסוגריים ומכבד תגיות; עורך בטקסט פשוט היה שובר שורות
    // אחרת, וכל מה שמתחת לנקודת הלחיצה היה קופץ.
    final source = [
      for (var i = 0; i < 12; i++) '<b>אבגד</b> הוזח (טיכל מנסע פצקר) שתאב',
    ].join(' ');
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
        loadSource: (_) async => source,
      ),
    );
    const settings = RenderSettings(fontSize: 10, lineHeight: 1.5);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 300,
                child: PluginCorrectionParagraph(
                  tabId: 'tab',
                  sectionIndex: 0,
                  sourceText: source,
                  settings: settings,
                  original: SmartTextWidget(text: source, settings: settings),
                  service: service,
                  sessionActive: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final reading = find.descendant(
      of: find.byType(SmartTextWidget),
      matching: find.byType(RichText),
    );
    expect(reading, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(reading);
    final length = paragraph.text.toPlainText().length;
    List<int> lineStarts(double Function(int) top) {
      final starts = <int>[0];
      for (var i = 1; i < length; i++) {
        if (top(i) > top(i - 1) + 1) starts.add(i);
      }
      return starts;
    }

    final before = tester.getSize(find.byType(PluginCorrectionParagraph));
    final originalStarts = lineStarts(
      (i) => paragraph.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy,
    );
    expect(originalStarts.length, greaterThan(4));
    await tester.tapAt(tester.getCenter(find.byType(SmartTextWidget)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EditableText), findsOneWidget);
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(render.text!.toPlainText().length, length);
    final editorStarts = lineStarts(
      (i) => render.getLocalRectForCaret(TextPosition(offset: i)).top,
    );
    expect(editorStarts, originalStarts);
    expect(tester.getSize(find.byType(PluginCorrectionParagraph)), before);
    await finish(tester, service);
  });

  testWidgets('חיפוש מודגש בעורך כמו בפסקה הרגילה', (tester) async {
    final service = await begin(tester);
    await pump(tester, service, searchText: 'ראשונה');
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.pump();
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    final span = editor.controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      style: editor.style,
      withComposing: false,
    );
    final hit = AppSurfaces.searchHit(
      Theme.of(tester.element(find.byType(EditableText))).colorScheme,
    );
    final marked = (span.children ?? const <InlineSpan>[])
        .whereType<TextSpan>()
        .where((part) => part.style?.color == hit)
        .map((part) => part.text)
        .toList();
    expect(marked, ['ראשונה']);
    await finish(tester, service);
  });

  testWidgets('חיפוש נשאר מודגש בעורך גם אחרי שהטקסט שונה', (tester) async {
    final service = await begin(tester);
    await pump(tester, service, searchText: 'ראשונה');
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.pump();
    final editor = tester.widget<EditableText>(find.byType(EditableText));
    editor.controller.value = TextEditingValue(
      text: 'ראשונה, ${editor.controller.text}',
    );
    await tester.pump();
    final span = editor.controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      style: editor.style,
      withComposing: false,
    );
    final hit = AppSurfaces.searchHit(
      Theme.of(tester.element(find.byType(EditableText))).colorScheme,
    );
    expect(
      (span.children ?? const <InlineSpan>[])
          .whereType<TextSpan>()
          .where((part) => part.style?.color == hit)
          .map((part) => part.text),
      ['ראשונה', 'ראשונה'],
    );
    await finish(tester, service);
  });

  group('הדגשת חיפוש זהה לקורא', () {
    const voweled = 'בְּרֵאשִׁית בָּרָא אֱלֹהִים בָּרָא';

    Future<PluginCorrectionSessionService> pumpSearch(
      WidgetTester tester,
      RenderSettings settings,
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
          loadSource: (_) async => voweled,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: PluginCorrectionParagraph(
                tabId: 'tab',
                sectionIndex: 0,
                sourceText: voweled,
                settings: settings,
                original: SmartTextWidget(text: voweled, settings: settings),
                service: service,
                sessionActive: true,
              ),
            ),
          ),
        ),
      );
      return service;
    }

    List<String> marks(InlineSpan span) {
      final out = <String>[];
      void walk(InlineSpan span) {
        if (span is! TextSpan) return;
        final style = span.style;
        if ((span.text ?? '').isNotEmpty &&
            (style?.color != null || style?.background != null)) {
          out.add('${span.text}|${style?.color}|${style?.background?.color}');
        }
        span.children?.forEach(walk);
      }

      walk(span);
      return out;
    }

    List<String> readingMarks(WidgetTester tester) => marks(
      tester
          .widget<RichText>(
            find.descendant(
              of: find.byType(SmartTextWidget),
              matching: find.byType(RichText),
            ),
          )
          .text,
    );

    TextSpan editorSpan(WidgetTester tester) {
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      return editor.controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: editor.style,
        withComposing: false,
      );
    }

    testWidgets('טקסט מנוקד ושאילתה בלי ניקוד מודגשים כמו בקורא', (
      tester,
    ) async {
      final service = await pumpSearch(
        tester,
        const RenderSettings(searchText: 'ברא'),
      );
      final expected = readingMarks(tester);
      expect(expected.map((e) => e.split('|').first), ['בָּרָא', 'בָּרָא']);
      await activateCorrectionParagraph(tester, find.byType(SmartTextWidget));
      await tester.pump();
      expect(marks(editorSpan(tester)), expected);
      await finish(tester, service);
    });

    testWidgets('אחרי עריכה הטקסט מודגש באותה התאמה של הקורא', (tester) async {
      final service = await pumpSearch(
        tester,
        const RenderSettings(searchText: 'ברא'),
      );
      await activateCorrectionParagraph(tester, find.byType(SmartTextWidget));
      await tester.pump();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      editor.controller.value = TextEditingValue(
        text: 'ברא  ${editor.controller.text}',
      );
      await tester.pump();
      expect(
        marks(editorSpan(tester)).map((e) => e.split('|').first),
        ['ברא', 'בָּרָא', 'בָּרָא'],
      );
      await finish(tester, service);
    });

    testWidgets('ההתאמה הנוכחית מסומנת בעורך כמו בקורא, גם אחרי עריכה', (
      tester,
    ) async {
      final service = await pumpSearch(
        tester,
        const RenderSettings(searchText: 'ברא', currentSearchIndex: 1),
      );
      final expected = readingMarks(tester);
      expect(expected, hasLength(2));
      expect(expected[0], isNot(expected[1].replaceFirst('בָּרָא', 'בָּרָא')));
      await activateCorrectionParagraph(tester, find.byType(SmartTextWidget));
      await tester.pump();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(marks(editorSpan(tester)), expected);
      editor.controller.value = TextEditingValue(
        text: 'x${editor.controller.text}',
      );
      await tester.pump();
      expect(marks(editorSpan(tester)), expected);
      await finish(tester, service);
    });
  });

  Future<PluginCorrectionSessionService> beginTexts(
    WidgetTester tester,
    List<String> texts,
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
        loadSource: (index) async => texts[index],
      ),
    );
    return service;
  }

  Widget paragraphs(
    PluginCorrectionSessionService service,
    List<String> texts, {
    RenderSettings settings = const RenderSettings(fontSize: 14),
    double width = 400,
    List<Widget> between = const [],
    Widget Function(int index, String text)? original,
  }) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                for (var i = 0; i < texts.length; i++) ...[
                  PluginCorrectionParagraph(
                    tabId: 'tab',
                    sectionIndex: i,
                    sourceText: texts[i],
                    settings: settings,
                    original: original?.call(i, texts[i]) ?? Text('קריאה $i'),
                    service: service,
                    sessionActive: true,
                  ),
                  if (i == 0) ...between,
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('גובה שורות העורך זהה לקורא גם עם מילה גדולה בשורה', (
    tester,
  ) async {
    // <big> מותח את השורה שהוא בה, אלא אם יש קו בסיס לגובה השורה.
    final text = [
      'אבגד הוזח טיכל מנסע',
      '<big>פצקר</big>',
      'שתאב גדהו זחטי כלמנ סעפצ קרשת אבגד הוזח טיכל',
    ].join(' ');
    final plain = text.replaceAll(RegExp('<[^>]*>'), '');
    final service = await beginTexts(tester, [text]);
    const settings = RenderSettings(fontSize: 10, lineHeight: 1.5);
    await tester.pumpWidget(
      paragraphs(
        service,
        [text],
        settings: settings,
        width: 120,
        original: (_, source) =>
            SmartTextWidget(text: source, settings: settings),
      ),
    );
    final reading = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(SmartTextWidget),
        matching: find.byType(RichText),
      ),
    );
    List<double> lineTops(double Function(int) top) {
      final tops = <double>[top(0)];
      for (var i = 1; i < plain.length; i++) {
        if (top(i) > tops.last + 1) tops.add(top(i));
      }
      return tops;
    }

    final originalTops = lineTops(
      (i) => reading.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy,
    );
    expect(originalTops.length, greaterThan(3));
    final before = tester.getSize(find.byType(PluginCorrectionParagraph));
    await tester.tapAt(tester.getCenter(find.byType(SmartTextWidget)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final editorTops = lineTops(
      (i) => render.getLocalRectForCaret(TextPosition(offset: i)).top,
    );
    expect(editorTops, originalTops);
    expect(tester.getSize(find.byType(PluginCorrectionParagraph)), before);
    await finish(tester, service);
  });

  testWidgets('חץ בין פסקאות באורכים שונים נוחת בדיוק באותה עמודה', (
    tester,
  ) async {
    const short = 'אבגדהוזחטיכלמנסעפצקר';
    const long = 'שתאבגדהוזחטיכלמנסעפצקרשתאבגדהוזחטיכלמנסעפצקרשתאבגדהוזחטי';
    final service = await beginTexts(tester, [short, long]);
    await tester.pumpWidget(paragraphs(service, [short, long]));
    await activateCorrectionParagraph(tester, find.text('קריאה 0'));
    await tester.pump();
    EditableText editor() =>
        tester.widget<EditableText>(find.byType(EditableText));
    final first = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(
      first.getLineAtOffset(const TextPosition(offset: 0)).end,
      short.length,
      reason: 'הפסקה הקצרה בשורה אחת',
    );
    editor().controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(editor().controller.text, long);
    expect(editor().controller.selection.baseOffset, 7);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(editor().controller.text, short);
    expect(editor().controller.selection.baseOffset, 7);
    editor().controller.selection = const TextSelection.collapsed(offset: 15);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(editor().controller.selection.baseOffset, 15);
    await finish(tester, service);
  });

  testWidgets(
    'מעבר מיקוד לרכיב אחר אינו משאיר עמודה לפסקה שתקבל מיקוד אחר כך',
    (
      tester,
    ) async {
      const short = 'אבגדהוזחטיכלמנסעפצקר';
      const long = 'שתאבגדהוזחטיכלמנסעפצקרשתאבגדהוזחטיכלמנסעפצקרשתאבגדהוזחטי';
      final service = await beginTexts(tester, [short, long]);
      await tester.pumpWidget(
        paragraphs(
          service,
          [short, long],
          between: [TextButton(onPressed: () {}, child: const Text('לחצן'))],
        ),
      );
      await activateCorrectionParagraph(tester, find.text('קריאה 0'));
      await tester.pump();
      tester
          .widget<EditableText>(find.byType(EditableText))
          .controller
          .selection = const TextSelection.collapsed(
        offset: 9,
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(editor.controller.text, long);
      expect(editor.controller.selection.baseOffset, isNot(9));
      await finish(tester, service);
    },
  );

  group('גובה נעול', () {
    const long = 'אבגד הוזח טיכל מנסע פצקר שתאב גדהו זחטי כלמנ סעפצ קרשת';

    Future<PluginCorrectionSessionService> pumpLocked(
      WidgetTester tester, {
      required RenderSettings settings,
      required double width,
    }) async {
      final service = await beginTexts(tester, [long]);
      await tester.pumpWidget(
        paragraphs(
          service,
          [long],
          settings: settings,
          width: width,
          original: (_, text) => Text(
            text,
            style: TextStyle(
              fontSize: settings.fontSize,
              height: settings.lineHeight,
            ),
          ),
        ),
      );
      return service;
    }

    testWidgets('שינוי רוחב בזמן עריכה מבטל את נעילת הגובה', (tester) async {
      const settings = RenderSettings(fontSize: 14);
      final service = await pumpLocked(tester, settings: settings, width: 100);
      await tester.tapAt(tester.getCenter(find.text(long)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      final narrow = tester.getSize(find.byType(PluginCorrectionParagraph));
      await tester.pumpWidget(
        paragraphs(
          service,
          [long],
          settings: settings,
          width: 400,
          original: (_, text) => Text(text),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(PluginCorrectionParagraph)).height,
        lessThan(narrow.height),
      );
      await finish(tester, service);
    });

    testWidgets('שינוי גודל גופן בזמן עריכה מבטל את נעילת הגובה', (
      tester,
    ) async {
      const big = RenderSettings(fontSize: 20);
      final service = await pumpLocked(tester, settings: big, width: 200);
      await tester.tapAt(tester.getCenter(find.text(long)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      final before = tester.getSize(find.byType(PluginCorrectionParagraph));
      await tester.pumpWidget(
        paragraphs(
          service,
          [long],
          settings: const RenderSettings(fontSize: 10),
          width: 200,
          original: (_, text) => Text(text),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(PluginCorrectionParagraph)).height,
        lessThan(before.height),
      );
      await finish(tester, service);
    });
  });

  group('Escape', () {
    testWidgets('יוצא מהעריכה בפסקה שלא תוקנה וחוזר לקורא', (tester) async {
      final service = await begin(tester);
      await pump(tester, service);
      await activateCorrectionParagraph(tester, find.text('קריאה 0'));
      await tester.pump();
      expect(find.byType(EditableText), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('קריאה 0'), findsOneWidget);
      await finish(tester, service);
    });

    testWidgets('בפסקה שתוקנה משאיר את התיקון ומוציא את המיקוד', (
      tester,
    ) async {
      final service = await begin(tester);
      await pump(tester, service);
      await activateCorrectionParagraph(tester, find.text('קריאה 0'));
      await tester.showKeyboard(find.byType(EditableText));
      await tester.pump(const Duration(seconds: 1));
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${sources[0]}!',
          selection: TextSelection.collapsed(offset: sources[0].length + 1),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(service.editableText('tab', 0, sources[0]), '${sources[0]}!');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      expect(editor.focusNode.hasFocus, isFalse);
      expect(service.editableText('tab', 0, sources[0]), '${sources[0]}!');
      await finish(tester, service);
    });
  });
}
