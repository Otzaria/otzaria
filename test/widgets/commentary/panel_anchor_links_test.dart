import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show stripHtmlIfNeeded;
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/widgets/commentary/commentary_content.dart';
import 'package:otzaria/widgets/commentary/panel_anchor_links.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// הקישור שהקטע שלו מוצג בחלונית: שורה 3 בספר "רש״י".
Link _displayed() => Link(
  heRef: 'רש״י על בראשית א, א',
  index1: 1,
  path2: 'רש״י',
  index2: 3,
  connectionType: LinkTypes.commentary,
  targetCategoryId: 7,
);

Link _anchored({
  required int index1,
  required int charStart,
  int? charEnd,
  String? label,
}) => Link(
  heRef: 'בראשית א, א',
  index1: index1,
  path2: 'בראשית',
  index2: 1,
  connectionType: LinkTypes.linker,
  targetCategoryId: 7,
  anchorStart: charStart,
  anchorEnd: charEnd,
  anchorLabel: label,
);

Link _footnote({int index1 = 3}) => Link(
  heRef: 'הערות על חברותא על ברכות',
  index1: index1,
  path2: 'הערות על חברותא על ברכות',
  index2: 1572,
  connectionType: LinkTypes.footnotes,
  targetCategoryId: 7,
);

Future<void> _pumpPanel(
  WidgetTester tester, {
  required List<Link> loaded,
  bool enabled = true,
  String html = 'אבגדהוזחטיכלמנ',
  void Function(OpenedTab)? onOpen,
  Link? displayed,
}) async {
  TargetLineLinksService.instance = TargetLineLinksService(
    loader: (_, _, _) async => loaded,
  );
  await tester.pumpWidget(
    BlocProvider<SettingsBloc>.value(
      value: _TestSettingsBloc(SettingsState.initial()),
      child: MaterialApp(
        home: PanelAnchoredText(
          link: displayed ?? _displayed(),
          html: html,
          settings: const RenderSettings(),
          enabled: enabled,
          openBookCallback: onOpen ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Offset _centerOfText(WidgetTester tester, String needle) {
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final index = paragraph.text.toPlainText().indexOf(needle);
    if (index < 0) continue;
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: index, extentOffset: index + needle.length),
        )
        .first;
    return paragraph.localToGlobal(box.toRect().center);
  }
  throw StateError('"$needle" not rendered');
}

String _renderedHtml(WidgetTester tester) =>
    tester.widget<SmartTextWidget>(find.byType(SmartTextWidget)).text;

void main() {
  setUp(() {
    BookNotesRepository.instance
      ..clear()
      ..debugLoader = (title, {categoryId, required source}) async =>
          BookNotes.empty;
    DivineNamesRepository.instance
      ..clear()
      ..debugLoader = (title, {categoryId, required source}) async =>
          DivineNameSpans.empty;
  });
  tearDown(() {
    BookNotesRepository.instance
      ..debugLoader = null
      ..clear();
    DivineNamesRepository.instance
      ..debugLoader = null
      ..clear();
  });
  tearDown(TargetLineLinksService.resetInstanceForTesting);
  tearDown(LibraryProviderManager.instance.resetForTesting);

  testWidgets('כשל בטעינת הערות הספר — הציטוטים אינם מוצבים והכשל מדווח', (
    tester,
  ) async {
    BookNotesRepository.instance.debugLoader =
        (title, {categoryId, required source}) async =>
            throw StateError('גוף שאינו מתפענח');
    await _pumpPanel(
      tester,
      loaded: [_anchored(index1: 3, charStart: 2, charEnd: 6)],
    );

    expect(tester.takeException(), isA<StateError>());
    expect(_renderedHtml(tester), isNot(contains('link-anchor-range')));
    final state = tester.state(find.byType(PanelAnchoredText));
    expect(
      (state as PanelAnchorLinksMixin).targetNotesError,
      isA<StateError>(),
    );
  });

  testWidgets('ציטוט בשורה המוצגת נעטף כקישור לחיץ', (tester) async {
    await _pumpPanel(
      tester,
      loaded: [_anchored(index1: 3, charStart: 2, charEnd: 6)],
    );

    final html = _renderedHtml(tester);
    expect(html, contains('link-anchor-range'));
    expect(html, contains('otzaria://anchor?ref=2_0&range=1'));
  });

  testWidgets('ציטוט בשורה אחרת של אותו ספר אינו מוזרק', (tester) async {
    await _pumpPanel(
      tester,
      loaded: [_anchored(index1: 4, charStart: 2, charEnd: 6)],
    );

    expect(_renderedHtml(tester), 'אבגדהוזחטיכלמנ');
  });

  testWidgets('סמן-אות של מפרש-על אינו מוזרק בחלונית', (tester) async {
    await _pumpPanel(
      tester,
      loaded: [_anchored(index1: 3, charStart: 2, label: 'א')],
    );

    expect(_renderedHtml(tester), 'אבגדהוזחטיכלמנ');
  });

  testWidgets('כיבוי בפרופיל התצוגה מחזיר את הטקסט כמות שהוא', (tester) async {
    await _pumpPanel(
      tester,
      loaded: [_anchored(index1: 3, charStart: 2, charEnd: 6)],
      enabled: false,
    );

    expect(_renderedHtml(tester), 'אבגדהוזחטיכלמנ');
  });

  // כמו בגוף הספר: תצוגה מקדימה אחרי השהיה, שמונעת הבהובים כשהסמן חולף.
  testWidgets('ריחוף על ציטוט פותח תצוגה מקדימה, ויציאה סוגרת אותה', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      loaded: [_anchored(index1: 3, charStart: 2, charEnd: 6)],
    );
    addTearDown(LinkPreviewOverlay.dismiss);
    final smartText = tester.widget<SmartTextWidget>(
      find.byType(SmartTextWidget),
    );
    expect(smartText.onAnchorHover, isNotNull);

    smartText.onAnchorHover!(
      'otzaria://anchor?ref=2_0&range=1',
      const Offset(100, 100),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byType(LinkHoverPreviewContent),
      findsNothing,
      reason: 'מעבר מהיר של הסמן אינו פותח חלונית',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinkHoverPreviewContent), findsOneWidget);

    smartText.onAnchorHoverExit!('otzaria://anchor?ref=2_0&range=1');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(LinkHoverPreviewContent), findsNothing);
  });

  testWidgets('יציאה מהירה מהציטוט מבטלת תצוגה מקדימה ממתינה', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      loaded: [_anchored(index1: 3, charStart: 2, charEnd: 6)],
    );
    addTearDown(LinkPreviewOverlay.dismiss);
    final smartText = tester.widget<SmartTextWidget>(
      find.byType(SmartTextWidget),
    );

    smartText.onAnchorHover!(
      'otzaria://anchor?ref=2_0&range=1',
      const Offset(100, 100),
    );
    await tester.pump(const Duration(milliseconds: 100));
    smartText.onAnchorHoverExit!('otzaria://anchor?ref=2_0&range=1');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LinkHoverPreviewContent), findsNothing);
  });

  testWidgets('בלי ציטוטים בשורה אין ריחוף', (tester) async {
    await _pumpPanel(tester, loaded: const []);

    expect(
      tester
          .widget<SmartTextWidget>(find.byType(SmartTextWidget))
          .onAnchorHover,
      isNull,
    );
  });

  testWidgets('לחיצה על הציטוט בזמן ההשהיה אינה פותחת תצוגה מקדימה', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      loaded: [_anchored(index1: 3, charStart: 2, charEnd: 6)],
      onOpen: (_) {},
    );
    addTearDown(LinkPreviewOverlay.dismiss);
    final smartText = tester.widget<SmartTextWidget>(
      find.byType(SmartTextWidget),
    );

    smartText.onAnchorHover!(
      'otzaria://anchor?ref=2_0&range=1',
      const Offset(100, 100),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // עוגן שאינו ברשימה: הלחיצה מבטלת את הריחוף בלי לנווט (הניווט צריך Settings).
    smartText.onAnchorTap!('otzaria://anchor?ref=2_9&range=1');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(LinkHoverPreviewContent), findsNothing);
  });

  testWidgets('תוכן מפרש מחבר ריחוף לציטוט לתצוגה מקדימה', (tester) async {
    final manager = LibraryProviderManager.instance;
    manager.seedMappingsForTesting(
      mapping: const {},
      providers: [_TestLibraryProvider()],
    );
    TargetLineLinksService.instance = TargetLineLinksService(
      loader: (_, _, _) async => [
        _anchored(index1: 3, charStart: 2, charEnd: 6),
      ],
    );
    final settings = _TestSettingsBloc(SettingsState.initial());
    addTearDown(settings.close);

    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: settings,
        child: MaterialApp(
          home: CommentaryContent(
            link: _displayed(),
            fontSize: 18,
            openBookCallback: (_) {},
            displayProfile: TextDisplayProfile.defaults,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final smartText = tester.widget<SmartTextWidget>(
      find.byType(SmartTextWidget).first,
    );
    expect(smartText.onAnchorHover, isNotNull);
    expect(smartText.onAnchorHoverExit, isNotNull);

    smartText.onAnchorHover!(
      'otzaria://anchor?ref=2_0&range=1',
      const Offset(100, 100),
    );
    await tester.pump(const Duration(milliseconds: 280));
    expect(find.byType(LinkHoverPreviewContent), findsOneWidget);
  });

  testWidgets('סמן-מספר של הערה בקטע שבחלונית פעיל לריחוף (issue #2002)', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      loaded: [_footnote()],
      html: 'לדרשא! <small>(26)</small>',
    );

    final smartText = tester.widget<SmartTextWidget>(
      find.byType(SmartTextWidget),
    );
    expect(smartText.text, contains('otzaria://note-marker?line=2&num=26'));
    expect(smartText.onAnchorHover, isNotNull);
  });

  testWidgets('סמן-מספר אינו מזיז ציטוט באופסטים גולמיים (issue #2002)', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      loaded: [
        Link(
          heRef: 'בראשית א, א',
          index1: 3,
          path2: 'בראשית',
          index2: 1,
          connectionType: LinkTypes.linker,
          targetCategoryId: 7,
          anchorStart: 20,
          anchorEnd: 25,
          anchorOffsetsAreRaw: true,
        ),
        _footnote(),
      ],
      html: '<small>(26)</small> אבגדה',
    );

    final html = _renderedHtml(tester);
    expect(html, contains('ref=2_0&range=1">אבגדה</a>'));
    expect(html, contains('note-marker?line=2&num=26">(26)</a>'));
  });

  for (final end in <int?>[null, 3]) {
    testWidgets('סמני הערות בשורה אחת עם br פנימי נשארים פעילים ($end)', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        displayed: Link(
          heRef: 'שורה עם מעבר פנימי',
          index1: 1,
          path2: 'חברותא על ברכות',
          index2: 3,
          index2End: end,
          connectionType: LinkTypes.commentary,
        ),
        loaded: [_footnote()],
        html: 'לפני <small>(26)</small><br>אחרי <small>(27)</small>',
      );

      expect(_renderedHtml(tester), contains('note-marker?line=2&num=26'));
      expect(_renderedHtml(tester), contains('note-marker?line=2&num=27'));
    });
  }

  testWidgets('שורה ללא FOOTNOTES אינה הופכת מספר רגיל לסמן בגלל שורה שכנה', (
    tester,
  ) async {
    final lines = ['ראשון <small>(2)</small>', 'שני <small>(2)</small>'];
    await _pumpPanel(
      tester,
      displayed: _RangeLink(
        lines,
        heRef: 'טווח',
        index1: 1,
        path2: 'רש״י',
        index2: 3,
        index2End: 4,
        connectionType: LinkTypes.commentary,
      ),
      loaded: [_footnote(index1: 3)],
      html: lines.join('<br>'),
    );
    final html = _renderedHtml(tester);
    expect(html, contains('note-marker?line=2&num=2'));
    expect(html, isNot(contains('note-marker?line=3&num=2')));
    expect(stripHtmlIfNeeded(html).split('(2)'), hasLength(3));
  });

  for (final type in [LinkTypes.commentary, LinkTypes.footnotes]) {
    testWidgets('מספר הערה חוזר בטווח אינו משויך לשורה הראשונה ($type)', (
      tester,
    ) async {
      final html = [
        'שנינו במשנה: <b>רבי טרפון אומר</b>: מברך לפני <small>(2)</small> '
            'שתיית מים <b>בורא נפשות רבות וחסרונן.</b>',
        '<b>אמר ליה רבא בר רב חנן לאביי, ואמרי לה, לרב יוסף: הלכתא</b> - '
            '<b>מאי?</b> האם הלכה כתנא קמא הסובר שיש לברך עליהם בתחלה שהכל, '
            'או כרבי טרפון הסובר שיש לברך עליהם בתחלה בורא נפשות?',
        '<b>אמר ליה: פוק חזי מאי עמא דבר!</b> צא וראה היאך נוהגים כולם, '
            'וכבר נהגו לברך בתחלה שהכל, ולבסוף בורא נפשות רבות.',
        '<br><center><big><b>הדרן עלך פרק כיצד מברכין</b></big></center>',
        '<h2>פרק שביעי - שלשה שאכלו</h2>',
        '<big><b>מתניתין:</b></big>',
        '<b>שלשה שאכלו</b> פת, והיו יושבין בסעודה <b>כאחת</b> [יחד] '
            '<small>(1)</small>, <b>חייבין</b> <small>(2)</small> <b>לזמן</b> - '
            'להזדמן ולהצטרף יחד, כדי לברך "ברכת הזימון" בלשון רבים '
            '<small>(3)</small>.',
      ];
      await _pumpPanel(
        tester,
        displayed: _RangeLink(
          html,
          heRef: 'חברותא על ברכות, מח ב–נ א',
          index1: 1,
          path2: 'חברותא על ברכות',
          index2: 4227,
          index2End: 4233,
          connectionType: type,
        ),
        loaded: [
          for (final (source, target) in [(4227, 2318), (4233, 2320)])
            Link(
              heRef: 'הערות על חברותא על ברכות',
              index1: source,
              path2: 'הערות על חברותא על ברכות',
              index2: target,
              connectionType: LinkTypes.footnotes,
              targetCategoryId: 1488,
            ),
          _anchored(index1: 4227, charStart: 0, charEnd: 5),
        ],
        html: html.join('<br>'),
      );

      expect(_renderedHtml(tester), contains('note-marker?line=4226&num=2'));
      expect(_renderedHtml(tester), contains('note-marker?line=4232&num=2'));
      expect(_renderedHtml(tester), contains('anchor?ref=4226_0&range=1'));
      expect(
        stripHtmlIfNeeded(_renderedHtml(tester)).split('(2)').length,
        3,
      );
    });
  }

  testWidgets('ריחוף על סמן-מספר במפרש מציג את ההערה (issue #2002)', (
    tester,
  ) async {
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: const {},
      providers: [
        _TestLibraryProvider(
          contentByPath: const {
            'חברותא על ברכות': 'לדרשא! <small>(26)</small>',
            'הערות על חברותא על ברכות': '<b>(26)</b> בביאור הלכה הוכיח מכאן',
          },
        ),
      ],
    );
    TargetLineLinksService.instance = TargetLineLinksService(
      loader: (_, _, _) async => [_footnote(index1: 2500)],
    );
    final settings = _TestSettingsBloc(SettingsState.initial());
    addTearDown(settings.close);
    addTearDown(LinkPreviewOverlay.dismiss);

    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: settings,
        child: MaterialApp(
          home: CommentaryContent(
            link: Link(
              heRef: 'חברותא על ברכות כח',
              index1: 1,
              path2: 'חברותא על ברכות',
              index2: 2500,
              connectionType: LinkTypes.commentary,
              targetCategoryId: 7,
            ),
            fontSize: 18,
            openBookCallback: (_) {},
            displayProfile: TextDisplayProfile.defaults,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final smartText = tester.widget<SmartTextWidget>(
      find.byType(SmartTextWidget).first,
    );
    expect(smartText.text, contains('otzaria://note-marker?line=2499&num=26'));
    expect(smartText.onAnchorHover, isNotNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(_centerOfText(tester, '(26)'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(LinkHoverPreviewContent), findsOneWidget);
  });

  // הסמן על הציטוט כשהחלונית יוצאת מהעץ (מעבר שורה, החלפת לשונית).
  for (final viaHtml in [false, true]) {
    testWidgets(
      'הסרת החלונית מתחת לסמן סוגרת את התצוגה (HtmlWidget: $viaHtml)',
      (
        tester,
      ) async {
        SmartTextWidget.debugForceHtmlWidget = viaHtml;
        addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
        await _pumpPanel(
          tester,
          loaded: [_anchored(index1: 3, charStart: 2, charEnd: 6)],
        );
        addTearDown(LinkPreviewOverlay.dismiss);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(_centerOfText(tester, 'גדהו'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(LinkHoverPreviewContent), findsOneWidget);

        await tester.pumpWidget(
          BlocProvider<SettingsBloc>.value(
            value: _TestSettingsBloc(SettingsState.initial()),
            child: const MaterialApp(home: SizedBox()),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.byType(LinkHoverPreviewContent), findsNothing);
      },
    );
  }

  group('חברותא במסד בסכמה 7 — ההערות בטבלת line_note של שורת היעד', () {
    BookNotes? notes;
    setUp(() {
      notes = null;
      BookNotesRepository.instance
        ..clear()
        ..debugLoader = (title, {categoryId, required source}) async =>
            title == 'רש״י' ? notes ?? BookNotes.empty : BookNotes.empty;
    });
    tearDown(() {
      BookNotesRepository.instance
        ..debugLoader = null
        ..clear();
      LinkPreviewOverlay.dismiss();
    });

    Future<void> hover(WidgetTester tester, String url) async {
      tester
          .widget<SmartTextWidget>(find.byType(SmartTextWidget))
          .onAnchorHover!(url, const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 300));
    }

    String previewContent(WidgetTester tester) => tester
        .widget<InlineBookNotePreviewContent>(
          find.byType(InlineBookNotePreviewContent),
        )
        .content;

    testWidgets('סמן <sup> בלי קישור FOOTNOTES — ריחוף מציג את ההערה מהטבלה', (
      tester,
    ) async {
      notes = (BookNotesBuilder()..add(2, 0, '(26)', 'בביאור הלכה')).build();
      await _pumpPanel(
        tester,
        loaded: const [],
        html: 'לדרשא!<sup class="footnote-marker">(26)</sup> סוף',
      );

      final html = _renderedHtml(tester);
      expect(html, contains('otzaria://book-note?line=2&note=0'));
      expect(html, isNot(contains('<sup')));
      await hover(tester, 'otzaria://book-note?line=2&note=0');
      expect(previewContent(tester), contains('בביאור הלכה'));
    });

    testWidgets('סמן מודפס (26) והערה בלי marker — לפי פתיחת ההערה', (
      tester,
    ) async {
      notes =
          (BookNotesBuilder()
                ..add(2, 0, null, '(25) אחרת')
                ..add(2, 1, null, '<b>(26)</b> בביאור הלכה'))
              .build();
      await _pumpPanel(
        tester,
        loaded: const [],
        html: 'לדרשא! <small>(26)</small>',
      );

      expect(
        _renderedHtml(tester),
        contains('otzaria://note-marker?line=2&num=26'),
      );
      await hover(tester, 'otzaria://note-marker?line=2&num=26');
      expect(previewContent(tester), contains('בביאור הלכה'));
    });

    testWidgets('טווח שומר על זהות הערה חוזרת ועל שמות השורה השנייה', (
      tester,
    ) async {
      notes =
          (BookNotesBuilder()
                ..add(2, 0, 'א', 'ראשונה')
                ..add(3, 0, 'א', 'שנייה'))
              .build();
      DivineNamesRepository.instance
        ..clear()
        ..debugLoader = (title, {categoryId, required source}) async =>
            (DivineNameSpansBuilder()..add(3, 0, 5, DivineNameKind.elohim))
                .build();
      final lines = [
        'ראשון<br>המשך<sup class="footnote-marker">א</sup>',
        'אלהים<sup class="footnote-marker">א</sup>',
      ];
      await _pumpPanel(
        tester,
        loaded: const [],
        html: lines.join('<br>'),
        displayed: _RangeLink(
          lines,
          heRef: 'טווח',
          index1: 1,
          path2: 'רש״י',
          index2: 3,
          index2End: 4,
          connectionType: LinkTypes.commentary,
        ),
      );
      expect(_renderedHtml(tester), contains('book-note?line=2&note=0'));
      expect(_renderedHtml(tester), contains('book-note?line=3&note=0'));
      expect(_renderedHtml(tester), contains('class="divine-name"'));
      await hover(tester, 'otzaria://book-note?line=3&note=0');
      expect(previewContent(tester), contains('שנייה'));
      expect(previewContent(tester), isNot(contains('ראשונה')));
    });

    testWidgets('בלי הערות בשורה המוצגת — אין ריחוף', (tester) async {
      notes = (BookNotesBuilder()..add(9, 0, '(26)', 'שורה אחרת')).build();
      await _pumpPanel(
        tester,
        loaded: const [],
        html: 'לדרשא!<sup class="footnote-marker">(26)</sup>',
      );

      final smartText = tester.widget<SmartTextWidget>(
        find.byType(SmartTextWidget),
      );
      expect(smartText.onAnchorHover, isNull);
      expect(smartText.text, isNot(contains('book-note')));
    });
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLibraryProvider extends Fake implements LibraryProvider {
  _TestLibraryProvider({this.contentByPath = const {}});

  final Map<String, String> contentByPath;

  @override
  Future<String> getLinkContent(Link link) async =>
      contentByPath[link.path2] ?? 'תוכן בדיקה';
}

class _RangeLink extends Link {
  _RangeLink(
    this.lines, {
    required super.heRef,
    required super.index1,
    required super.path2,
    required super.index2,
    required super.index2End,
    required super.connectionType,
  });
  final List<String> lines;
  @override
  Future<List<LinkContentLine>> get contentLines async => [
    for (final (i, line) in lines.indexed)
      (lineIndex: index2 - 1 + i, content: line),
  ];
}
