import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
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

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  final skip = !engineReady;

  const verse =
      'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃ בָּרָא';

  Future<PluginCorrectionSessionService> begin(
    WidgetTester tester,
    String source,
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
        loadSource: (_) async => source,
      ),
    );
    return service;
  }

  Widget paragraph(
    PluginCorrectionSessionService service,
    String source,
    RenderSettings settings, {
    ThemeData? theme,
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
              original: const Text('קריאה'),
              service: service,
              sessionActive: true,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await activateCorrectionParagraph(tester, find.text('קריאה'));
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

  List<_Segment> segments(WidgetTester tester, {TextStyle? style}) {
    final root = span(tester, style: style);
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

  /// הטווחים שצבועים בצבע ההתאמה, כשטווחים סמוכים ממוזגים.
  List<List<int>> painted(WidgetTester tester, Color color) {
    final result = <List<int>>[];
    for (final segment in segments(tester)) {
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
      final service = await begin(tester, source);
      await tester.pumpWidget(
        paragraph(
          service,
          source,
          const RenderSettings(
            fontSize: 14,
            searchText: 'ברא',
            currentSearchIndex: 1,
          ),
        ),
      );
      await open(tester);
      final scheme = Theme.of(
        tester.element(find.byType(EditableText)),
      ).colorScheme;
      final byStart = {
        for (final segment in segments(tester)) segment.start: segment,
      };
      expect(byStart[0]!.color, AppSurfaces.searchHit(scheme));
      expect(byStart[0]!.background, isNull);
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
      var notifications = 0;
      controller(tester).addListener(() => notifications++);
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
      expect(notifications, greaterThan(0));
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
      expect(byStart()[0]!.background, isNull);
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
      var notifications = 0;
      controller(tester).addListener(() => notifications++);
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
      expect(notifications, 0);
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

    testWidgets('בניות חוזרות עם קלטים זהים לא מחשבות הדגשה מחדש', (
      tester,
    ) async {
      final service = await begin(tester, verse);
      SmartTextRenderStats.enabled = true;
      addTearDown(() => SmartTextRenderStats.enabled = false);
      SmartTextRenderStats.reset();
      await tester.pumpWidget(
        paragraph(
          service,
          verse,
          const RenderSettings(fontSize: 14, searchText: 'ברא'),
        ),
      );
      await open(tester);
      for (var i = 0; i < 20; i++) {
        span(tester);
      }
      expect(_processCalls(), 1);
      await finish(tester, service);
    }, skip: skip);

    testWidgets('פסקה של כ-6000 תווים נבנית מהר גם עם הרבה התאמות', (
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

int _processCalls() {
  final stats = SmartTextRenderStats.takeAndReset();
  if (stats == null) return 0;
  return (stats['processHits'] as int) + (stats['processMisses'] as int);
}
