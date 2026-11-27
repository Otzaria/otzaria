import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/search_highlight_css.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show HighlightPattern;

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/activate_correction_paragraph.dart';

typedef _Segment = ({
  int start,
  int end,
  Color? color,
  Color? background,
  bool underline,
});

class _CountingCorrectionText extends PluginCorrectionText {
  _CountingCorrectionText(super.source) : super(trackHtml: true);

  int projections = 0;

  @override
  ({String html, List<int> offsets}) searchHtml(
    String text,
    List<CorrectionHtmlOrigin?> origins,
  ) {
    projections++;
    return super.searchHtml(text, origins);
  }
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  final skip = !engineReady;

  const verse =
      'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃ בָּרָא';

  Future<
    ({PluginCorrectionSessionService service, Map<String, dynamic> snapshot})
  >
  startSession(
    WidgetTester tester,
    String source, {
    Database? db,
  }) async {
    if (db == null) {
      db = sqlite3.openInMemory();
      addTearDown(db.close);
    }
    final service = PluginCorrectionSessionService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    addTearDown(service.dispose);
    final snapshot = await tester.runAsync(
      () => service.begin(
        owner: 'owner',
        tabId: 'tab',
        bookId: 'ספר',
        bookUid: 'id:1',
        libraryVersion: '1',
        loadSource: (_) async => source,
      ),
    );
    return (service: service, snapshot: snapshot!);
  }

  Future<PluginCorrectionSessionService> begin(
    WidgetTester tester,
    String source,
  ) async => (await startSession(tester, source)).service;

  Widget paragraph(
    PluginCorrectionSessionService service,
    String source,
    RenderSettings settings, {
    ThemeData? theme,
    bool actualReader = false,
  }) => MaterialApp(
    theme: theme,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: 400,
            child: PluginCorrectionParagraph(
              tabId: 'tab',
              sectionIndex: 0,
              sourceText: source,
              settings: settings,
              original: actualReader
                  ? SmartTextWidget(text: source, settings: settings)
                  : const Text('קריאה'),
              service: service,
              sessionActive: true,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, {bool actualReader = false}) async {
    await activateCorrectionParagraph(
      tester,
      actualReader ? find.byType(SmartTextWidget) : find.text('קריאה'),
    );
    await tester.showKeyboard(find.byType(EditableText));
    await tester.pump(const Duration(seconds: 1));
  }

  PluginCorrectionController controller(WidgetTester tester) =>
      tester.widget<RtlTextField>(find.byType(RtlTextField)).controller
          as PluginCorrectionController;

  TextSpan span(WidgetTester tester, {TextStyle? style}) =>
      controller(tester).buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: style ?? const TextStyle(),
        withComposing: true,
      );

  EditableTextState editor(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText));

  List<_Segment> segments(
    WidgetTester tester, {
    TextStyle? style,
    bool rendered = false,
  }) {
    final root = rendered
        ? editor(tester).renderEditable.text! as TextSpan
        : span(tester, style: style);
    final result = <_Segment>[];
    var offset = 0;
    void add(String text, TextStyle? style) {
      result.add((
        start: offset,
        end: offset + text.length,
        color: style?.color,
        background: style?.backgroundColor,
        underline:
            style?.decoration?.contains(TextDecoration.underline) ?? false,
      ));
      offset += text.length;
    }

    final children = root.children;
    if (children == null) {
      add(root.text ?? '', root.style);
    } else {
      for (final child in children.cast<TextSpan>()) {
        add(child.text ?? '', child.style);
      }
    }
    return result;
  }

  Color hit(WidgetTester tester) => AppSurfaces.searchHit(
    Theme.of(tester.element(find.byType(EditableText))).colorScheme,
  );

  Color? readerBackground(
    String source,
    RenderSettings settings,
    ColorScheme scheme,
  ) {
    final html = SearchHighlightCss.resolve(
      TextRendererService.processText(source, settings),
      scheme,
    );
    final css = RegExp(r'<span style="([^"]*)">').firstMatch(html)![1]!;
    final background = RegExp(r'background-color:\s*([^;]+)')
        .firstMatch(css)?[1];
    return background == null ? null : parseCssColor(background);
  }

  /// הטווחים שצבועים בצבע ההתאמה, כשטווחים סמוכים ממוזגים.
  List<List<int>> painted(
    WidgetTester tester,
    Color color, {
    bool rendered = false,
  }) {
    final result = <List<int>>[];
    for (final segment in segments(tester, rendered: rendered)) {
      if (segment.color != color) continue;
      if (result.isNotEmpty && result.last[1] == segment.start) {
        result.last[1] = segment.end;
      } else {
        result.add([segment.start, segment.end]);
      }
    }
    return result;
  }

  List<List<int>> merged(List<List<int>> ranges) {
    final result = <List<int>>[];
    for (final range in ranges) {
      if (result.isNotEmpty && result.last[1] == range[0]) {
        result.last[1] = range[1];
      } else {
        result.add([...range]);
      }
    }
    return result;
  }

  Future<void> edit(
    WidgetTester tester, {
    required int caretBefore,
    required String text,
    required int caretAfter,
  }) async {
    tester
        .widget<EditableText>(find.byType(EditableText))
        .controller
        .selection = TextSelection.collapsed(
      offset: caretBefore,
    );
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caretAfter),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> finish(
    WidgetTester tester,
    PluginCorrectionSessionService service,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => service.flushAll());
  }

  group('הדגשת חיפוש בעורך', () {
    testWidgets('גוף הערה אינו מודגש לפני עריכה או אחרי עריכה בתוכו', (
      tester,
    ) async {
      const source = 'נאמר <i class="footnote">ברא</i> דבר ברא';
      const settings = RenderSettings(searchText: 'ברא');
      expect(
        SearchHighlightCss.hit.allMatches(
          TextRendererService.processText(source, settings),
        ),
        hasLength(1),
      );
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, settings));
      await open(tester);
      List<int> hits() => [
        for (final part in segments(tester, rendered: true))
          if (part.color == hit(tester)) part.start,
      ];
      expect(hits(), [13]);
      await edit(
        tester,
        caretBefore: 7,
        text: 'נאמר ברא ברא דבר ברא',
        caretAfter: 11,
      );
      expect(hits(), [17]);
      await finish(tester, service);
    }, skip: skip);

    for (final deleteFootnote in [true, false]) {
      testWidgets(
        'טיוטה שומרת את צומת המופע הזהה שנשאר (גוף הערה נמחק: $deleteFootnote)',
        (tester) async {
          const source = '<i class="footnote">ברא </i>ברא';
          const settings = RenderSettings(searchText: 'ברא');
          final db = sqlite3.openInMemory();
          addTearDown(db.close);
          final (:service, :snapshot) = await startSession(
            tester,
            source,
            db: db,
          );
          await tester.pumpWidget(
            paragraph(service, source, settings, actualReader: true),
          );
          final richText = tester.widget<RichText>(
            find
                .descendant(
                  of: find.byType(SmartTextWidget),
                  matching: find.byType(RichText),
                )
                .first,
          );
          expect(richText.text.toPlainText(), 'ברא');
          await open(tester, actualReader: true);
          expect(painted(tester, hit(tester), rendered: true), [
            [4, 7],
          ]);
          editor(tester).widget.controller.selection = deleteFootnote
              ? const TextSelection(baseOffset: 0, extentOffset: 4)
              : const TextSelection(baseOffset: 3, extentOffset: 7);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'ברא',
              selection: TextSelection.collapsed(offset: 0),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          final expected = deleteFootnote
              ? [
                  [0, 3],
                ]
              : <List<int>>[];
          expect(painted(tester, hit(tester), rendered: true), expected);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(editor(tester).widget.focusNode.hasFocus, isFalse);
          expect(painted(tester, hit(tester), rendered: true), expected);
          await finish(tester, service);

          final sessionId = snapshot['sessionId'] as String;
          final saved = (await tester.runAsync(
            () => service.get('owner', sessionId),
          ))!;
          final draftId = saved['draft']['draftId'] as String;
          final draft = (await tester.runAsync(
            () => service.getDraft('owner', draftId),
          ))!;
          final publicChanges = [
            {
              'sectionIndex': 0,
              'originalSourceText': source,
              'originalText': 'ברא ברא',
              'proposedText': 'ברא',
            },
          ];
          expect(saved['changes'], publicChanges);
          expect(draft['changes'], publicChanges);
          await tester.runAsync(
            () => service.end('owner', sessionId, saved['revision'] as int),
          );

          final reopened = await startSession(tester, source, db: db);
          expect(reopened.snapshot['changes'], publicChanges);
          expect(reopened.snapshot['recovery']['restoredSectionIndices'], [0]);
          await tester.pumpWidget(
            paragraph(reopened.service, source, settings, actualReader: true),
          );
          expect(controller(tester).text, 'ברא');
          expect(painted(tester, hit(tester), rendered: true), expected);
          await finish(tester, reopened.service);
        },
        skip: skip,
      );
    }

    testWidgets('החלפת אימוג׳י מישות HTML משמרת את שיוך הטיוטה', (
      tester,
    ) async {
      const source = '&#x1F600; <i class="footnote">ברא </i>ברא';
      const settings = RenderSettings(searchText: 'ברא');
      const expected = [
        [7, 10],
      ];
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      final (:service, :snapshot) = await startSession(tester, source, db: db);
      await tester.pumpWidget(paragraph(service, source, settings));
      await open(tester);
      editor(tester).widget.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '😁 ברא ברא',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(painted(tester, hit(tester), rendered: true), expected);
      await finish(tester, service);
      final id = snapshot['sessionId'] as String;
      final saved = (await tester.runAsync(() => service.get('owner', id)))!;
      await tester.runAsync(
        () => service.end('owner', id, saved['revision'] as int),
      );

      final reopened = await startSession(tester, source, db: db);
      await tester.pumpWidget(paragraph(reopened.service, source, settings));
      expect(controller(tester).text, '😁 ברא ברא');
      expect(painted(tester, hit(tester), rendered: true), expected);
      await finish(tester, reopened.service);
    }, skip: skip);

    testWidgets('טיוטה ישנה עם מופע עמום אינה מייחסת אותו לטקסט הספר', (
      tester,
    ) async {
      const source = '<i class="footnote">ברא </i>ברא';
      final service = await begin(tester, source);
      service.editParagraph('tab', 0, source, 'ברא');
      await tester.pumpWidget(
        paragraph(service, source, const RenderSettings(searchText: 'ברא')),
      );
      expect(controller(tester).text, 'ברא');
      expect(painted(tester, hit(tester), rendered: true), isEmpty);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('מופע עמום בטיוטה ישנה נשאר בלי הדגשה גם כשהספירה לא השתנתה', (
      tester,
    ) async {
      const source = '<i class="footnote">ברא </i>ברא אחר';
      const proposed = 'ברא ברא חדש';
      final service = await begin(tester, source);
      service.editParagraph('tab', 0, source, proposed);
      await tester.pumpWidget(
        paragraph(service, source, const RenderSettings(searchText: 'ברא')),
      );
      expect(controller(tester).text, proposed);
      expect(controller(tester).formats.first.italic, isTrue);
      expect(controller(tester).formats[4].italic, isFalse);
      expect(painted(tester, hit(tester), rendered: true), isEmpty);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('חזרה לנוסח המקור מחזירה גם את שיוך ההדגשה', (tester) async {
      const source = '<i class="footnote">ברא </i>ברא';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(service, source, const RenderSettings(searchText: 'ברא')),
      );
      await open(tester);
      editor(tester).widget.controller.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 7,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ברא',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(painted(tester, hit(tester), rendered: true), isEmpty);
      await edit(tester, caretBefore: 3, text: 'ברא ברא', caretAfter: 7);
      expect(service.isCorrected('tab', 0, source), isFalse);
      expect(painted(tester, hit(tester), rendered: true), [
        [4, 7],
      ]);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('חיפוש שחוצה פיסוק מוסתר צובע את המילים בטקסט העריך', (
      tester,
    ) async {
      const source = 'אב-<b>גד</b> אב-גד';
      const settings = RenderSettings(
        searchText: 'אב גד',
        removePunctuation: true,
        currentSearchIndex: 1,
      );
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, settings));
      await open(tester);
      final scheme = Theme.of(tester.element(find.byType(EditableText)))
          .colorScheme;
      final spans = segments(tester, rendered: true);
      expect(controller(tester).text, 'אב-גד אב-גד');
      expect(
        [
          for (final span in spans)
            if (span.color == hit(tester)) span.start,
        ],
        [0, 3],
      );
      expect(
        [
          for (final span in spans)
            if (span.color == AppSurfaces.searchHitCurrent(scheme)) span.start,
        ],
        [6, 9],
      );
      await finish(tester, service);
    }, skip: skip);

    for (final hidden in [false, true]) {
      testWidgets('שאילתה בלי ניקוד מדגישה טקסט מנוקד כמו בקורא '
          '(ניקוד ${hidden ? "מוסתר" : "מוצג"})', (tester) async {
        final service = await begin(tester, verse);
        final settings = RenderSettings(
          fontSize: 14,
          removeNikud: hidden,
          removeTeamim: hidden,
          searchText: 'ברא',
        );
        await tester.pumpWidget(paragraph(service, verse, settings));
        await open(tester);
        final shown = controller(tester).text;
        final expected = merged(utils.computeHighlightRanges(shown, 'ברא'));
        expect(expected.length, 2);
        expect(painted(tester, hit(tester)), expected);
        await finish(tester, service);
      }, skip: skip);
    }

    testWidgets('טקסט שנערך מודגש לפי הטקסט החדש', (tester) async {
      const source = 'בראשית ברא אלהים';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ברא'),
        ),
      );
      await open(tester);
      await edit(
        tester,
        caretBefore: 16,
        text: 'בראשית ברא אלהים ברא',
        caretAfter: 20,
      );
      final expected = merged(
        utils.computeHighlightRanges('בראשית ברא אלהים ברא', 'ברא'),
      );
      expect(expected.length, 2);
      expect(expected.last, [17, 20]);
      expect(painted(tester, hit(tester)), expected);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('התאמה נוכחית נצבעת בסגנון ההתאמה הנוכחית של הקורא', (
      tester,
    ) async {
      const source = 'ברא אלהים ברא';
      const settings = RenderSettings(
        fontSize: 14,
        searchText: 'ברא',
        currentSearchIndex: 1,
      );
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, settings));
      await open(tester);
      final scheme = Theme.of(
        tester.element(find.byType(EditableText)),
      ).colorScheme;
      final byStart = {
        for (final segment in segments(tester)) segment.start: segment,
      };
      expect(byStart[0]!.color, AppSurfaces.searchHit(scheme));
      expect(
        byStart[0]!.background,
        readerBackground(source, settings, scheme),
      );
      expect(byStart[10]!.color, AppSurfaces.searchHitCurrent(scheme));
      expect(
        byStart[10]!.background,
        AppSurfaces.searchHitCurrentBackground(scheme),
      );
      await finish(tester, service);
    }, skip: skip);

    testWidgets('מילים חילופיות מודגשות כמו בקורא', (tester) async {
      const source = 'ברא אלהים ארץ';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(
            fontSize: 14,
            searchText: 'ברא',
            alternativeWords: {
              0: ['ארץ'],
            },
          ),
        ),
      );
      await open(tester);
      final expected = merged(
        utils.computeHighlightRanges(
          source,
          'ברא',
          alternativeWords: const {
            0: ['ארץ'],
          },
        ),
      );
      expect(expected.length, 2);
      expect(painted(tester, hit(tester)), expected);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('בזמן הרכבה (IME) ההדגשה נשמרת והקו התחתון נוסף', (
      tester,
    ) async {
      const source = 'ברא אלהים';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ברא'),
        ),
      );
      await open(tester);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump();
      final first = segments(tester).firstWhere((s) => s.start == 0);
      expect(first.color, hit(tester));
      expect(first.underline, isTrue);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('הדגשה בזמן הרכבה אחרי ירידת שורה מצוירת בשדה', (
      tester,
    ) async {
      const source = 'ברא אלהים ברא';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ברא'),
        ),
      );
      await open(tester);
      await edit(
        tester,
        caretBefore: 10,
        text: 'ברא אלהים\n ברא',
        caretAfter: 11,
      );
      final fieldValue = editor(tester).textEditingValue;
      expect(fieldValue.text, contains('\r\n'));
      final end = fieldValue.text.length;
      tester.testTextInput.updateEditingValue(
        fieldValue.copyWith(
          selection: TextSelection.collapsed(offset: end),
          composing: TextRange(start: end - 3, end: end),
        ),
      );
      await tester.pump();
      final rendered = segments(tester, rendered: true);
      expect(rendered.first.color, hit(tester));
      expect(rendered.last.color, hit(tester));
      expect(rendered.last.underline, isTrue);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('פסקה שפוצלה ב-Enter מודגשת בשתי השורות', (tester) async {
      const source = 'ברא אלהים ברא';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ברא'),
        ),
      );
      await open(tester);
      await edit(
        tester,
        caretBefore: 10,
        text: 'ברא אלהים\n ברא',
        caretAfter: 11,
      );
      final shown = controller(tester).text;
      expect(shown.contains('\n'), isTrue);
      expect(
        painted(tester, hit(tester)),
        merged(utils.computeHighlightRanges(shown, 'ברא')),
      );
      await finish(tester, service);
    }, skip: skip);

    testWidgets('שינוי גרסת תבנית ההדגשה מדגיש מחדש', (tester) async {
      const source = 'שלום עולם';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'שלום'),
        ),
      );
      await open(tester);
      expect(painted(tester, hit(tester)), [
        [0, 4],
      ]);
      await tester.runAsync(
        () => utils.primeHighlightPattern(
          searchQuery: 'שלום',
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: 0,
          isFuzzy: false,
          fetch: () async => const HighlightPattern(
            combinedPattern: 'עולם',
            wordPatterns: ['עולם'],
            wordBoundaryEligible: [true],
          ),
        ),
      );
      await tester.pump();
      expect(painted(tester, hit(tester)), [
        [5, 9],
      ]);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('שינוי גרסת התבנית מודיע לעורך להתצייר מחדש', (tester) async {
      const source = 'ארץ שמים';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ארץ'),
        ),
      );
      await open(tester);
      final before = segments(tester, rendered: true);
      expect(
        before.where((segment) => segment.color == hit(tester)).single.end,
        3,
      );
      await tester.runAsync(
        () => utils.primeHighlightPattern(
          searchQuery: 'ארץ',
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: 0,
          isFuzzy: false,
          fetch: () async => const HighlightPattern(
            combinedPattern: 'שמים',
            wordPatterns: ['שמים'],
            wordBoundaryEligible: [true],
          ),
        ),
      );
      await tester.pump();
      final after = segments(tester, rendered: true);
      expect(
        after.where((segment) => segment.color == hit(tester)).single.start,
        4,
      );
      await finish(tester, service);
    }, skip: skip);

    testWidgets('החלפת החיפוש בעורך פתוח מעדכנת את ההדגשה', (tester) async {
      const source = 'ברא אלהים ברא';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ברא'),
        ),
      );
      await open(tester);
      expect(painted(tester, hit(tester)), [
        [0, 3],
        [10, 13],
      ]);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'אלהים'),
        ),
      );
      await tester.pump();
      expect(painted(tester, hit(tester)), [
        [4, 9],
      ]);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('החלפת ערכת צבעים צובעת מחדש בצבעי הערכה החדשה', (
      tester,
    ) async {
      const source = 'ברא אלהים';
      const settings = RenderSettings(fontSize: 14, searchText: 'ברא');
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          settings,
          theme: ThemeData(
            colorScheme: const ColorScheme.light(error: Color(0xFFAA0000)),
          ),
        ),
      );
      await open(tester);
      final light = hit(tester);
      expect(painted(tester, light), [
        [0, 3],
      ]);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          settings,
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(error: Color(0xFF00AA00)),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final dark = hit(tester);
      expect(dark, isNot(light));
      expect(painted(tester, dark), [
        [0, 3],
      ]);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('מעבר להתאמה הבאה בעורך פתוח מחליף את סגנון ההתאמה הנוכחית', (
      tester,
    ) async {
      const source = 'ברא אלהים ברא';
      final service = await begin(tester, source);
      Widget at(int index) => paragraph(
        service,
        source,
        RenderSettings(
          fontSize: 14,
          searchText: 'ברא',
          currentSearchIndex: index,
        ),
      );
      await tester.pumpWidget(at(0));
      await open(tester);
      final scheme = Theme.of(
        tester.element(find.byType(EditableText)),
      ).colorScheme;
      Map<int, _Segment> byStart() => {
        for (final segment in segments(tester)) segment.start: segment,
      };
      expect(byStart()[0]!.color, AppSurfaces.searchHitCurrent(scheme));
      await tester.pumpWidget(at(1));
      await tester.pump();
      expect(byStart()[0]!.color, AppSurfaces.searchHit(scheme));
      expect(
        byStart()[0]!.background,
        isNot(AppSurfaces.searchHitCurrentBackground(scheme)),
      );
      expect(byStart()[10]!.color, AppSurfaces.searchHitCurrent(scheme));
      await finish(tester, service);
    }, skip: skip);

    testWidgets(
      'הגדרות הקורא (חלקי/מטושטש/פיסוק/שמות קודש/סוגריים) כמו בקורא',
      (
        tester,
      ) async {
        const source = 'בראשית, ברא; יהוה (ברא) ברה אלהים ברא';
        const settings = RenderSettings(
          fontSize: 14,
          searchText: 'ברא',
          partialWordHighlight: true,
          isFuzzySearch: true,
          searchDistance: 1,
          removePunctuation: true,
          replaceHolyNames: true,
          holyNameStyle: HolyNameStyle.hehApostrophe,
          formatParentheses: true,
        );
        final service = await begin(tester, source);
        await tester.pumpWidget(paragraph(service, source, settings));
        await open(tester);
        expect(controller(tester).text, source);
        expect(painted(tester, hit(tester)), [
          [0, 3],
          [8, 11],
          [19, 22],
          [34, 37],
        ]);
        await finish(tester, service);
      },
      skip: skip,
    );

    testWidgets('סגנון בסיס צבוע לא דורס את צבע ההתאמה', (tester) async {
      const source = 'ברא אלהים';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ברא'),
        ),
      );
      await open(tester);
      const base = TextStyle(color: Color(0xFF123456));
      final byStart = {
        for (final segment in segments(tester, style: base))
          segment.start: segment,
      };
      expect(byStart[0]!.color, hit(tester));
      expect(byStart[3]!.color, isNull);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('אחרי ניקוי החיפוש שינוי גרסת התבנית לא מצייר מחדש', (
      tester,
    ) async {
      const source = 'חדש ישן';
      final service = await begin(tester, source);
      Widget withQuery(String query) => paragraph(
        service,
        source,
        RenderSettings(fontSize: 14, searchText: query),
      );
      await tester.pumpWidget(withQuery('חדש'));
      await open(tester);
      expect(painted(tester, hit(tester)), [
        [0, 3],
      ]);
      await tester.pumpWidget(withQuery(''));
      await tester.pump();
      expect(painted(tester, hit(tester)), isEmpty);
      final before = segments(tester, rendered: true);
      await tester.runAsync(
        () => utils.primeHighlightPattern(
          searchQuery: 'חדש',
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: 0,
          isFuzzy: false,
          fetch: () async => const HighlightPattern(
            combinedPattern: 'ישן',
            wordPatterns: ['ישן'],
            wordBoundaryEligible: [true],
          ),
        ),
      );
      await tester.pump();
      expect(segments(tester, rendered: true), before);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('אחרי סגירת העורך שינוי תבנית לא פוגע בבקר שנסגר', (
      tester,
    ) async {
      const source = 'ים ארץ';
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ים'),
        ),
      );
      await open(tester);
      expect(painted(tester, hit(tester)), [
        [0, 2],
      ]);
      await finish(tester, service);
      await tester.runAsync(
        () => utils.primeHighlightPattern(
          searchQuery: 'ים',
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: 0,
          isFuzzy: false,
          fetch: () async => const HighlightPattern(
            combinedPattern: 'ארץ',
            wordPatterns: ['ארץ'],
            wordBoundaryEligible: [true],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }, skip: skip);

    testWidgets('שינוי גופן וצבע לא מחשב שוב את התאמות החיפוש', (tester) async {
      const source = '<b>ברא</b> אלהים';
      const settings = RenderSettings(fontSize: 14, searchText: 'ברא');
      final service = await begin(tester, source);
      await tester.pumpWidget(paragraph(service, source, settings));
      await open(tester);
      final text = _CountingCorrectionText(source);
      controller(tester).source = text;
      await tester.pumpWidget(
        paragraph(service, source, settings.copyWith(currentSearchIndex: 0)),
      );
      expect(text.projections, 1);

      TextStyle hitStyle() {
        final root = editor(tester).renderEditable.text! as TextSpan;
        return root.children!
            .cast<TextSpan>()
            .singleWhere((span) => span.text == 'ברא')
            .style!;
      }

      final previous = hitStyle();
      final theme = ThemeData(
        colorScheme: const ColorScheme.dark(error: Color(0xFF00AA00)),
      );
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          settings.copyWith(currentSearchIndex: 0, fontSize: 24),
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
      expect(hitStyle().fontSize, 24);
      expect(hitStyle().color, AppSurfaces.searchHitCurrent(theme.colorScheme));
      expect(hitStyle().color, isNot(previous.color));
      expect(text.projections, 1);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('פסקה ארוכה נבנית מהר גם עם הרבה התאמות', (
      tester,
    ) async {
      final source = List.filled(1000, 'ברא').join(' ');
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(fontSize: 14, searchText: 'ברא'),
        ),
      );
      await open(tester);
      span(tester);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        span(tester);
      }
      watch.stop();
      expect(painted(tester, hit(tester)).length, 1000);
      expect(watch.elapsedMilliseconds, lessThan(1000));
      await finish(tester, service);
    }, skip: skip);
  });
}
