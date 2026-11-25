import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart'
    show HtmlWidget;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/view/layout_fix_suggestion_banner.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/utils/numbered_note_markers.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

const _namedAnchor = '<a name="section">יעד</a>';
const _html =
    'טקסט <a href="https://example.com">קישור</a> '
    '<a class="numbered-note-marker" href="otzaria://note-marker?id=1">(9)</a> '
    '<a class="link-anchor-range" href="otzaria://anchor?ref=1_0&range=1">ציטוט</a> '
    '<a href="https://example.com" style="color: #FF0000">מפורש</a> '
    '$_namedAnchor '
    '<a class="link-anchor" href="otzaria://anchor?ref=1_0">(א)</a> '
    '<a class="link-anchor link-anchor-active" href="otzaria://anchor?ref=1_1">(ב)</a>';

Widget _host(ColorScheme cs, Widget child) => MaterialApp(
  theme: AppThemeData.light(cs, compactMenuMode: false),
  themeAnimationDuration: Duration.zero,
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

TextStyle _styleOf(WidgetTester tester, String needle) {
  TextStyle? found;
  void visit(InlineSpan span, TextStyle inherited) {
    if (found != null || span is! TextSpan) return;
    final style = inherited.merge(span.style);
    if (span.text?.contains(needle) ?? false) {
      found = style;
      return;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    visit(richText.text, const TextStyle());
  }
  expect(found, isNotNull, reason: needle);
  return found!;
}

void _expectOverlay(WidgetTester tester, ColorScheme cs) {
  final overlay = tester.widget<RaisedMarkerOverlay>(
    find.byType(RaisedMarkerOverlay),
  );
  expect(overlay.linkColor, AppSurfaces.readerLink(cs));
  expect(overlay.activeBackground, cs.primaryContainer);
  expect(overlay.activeForeground, cs.onPrimaryContainer);
  expect(overlay.markers.any((marker) => marker.active), isTrue);
  for (final marker in ['(א)', '(ב)']) {
    expect(_styleOf(tester, marker).color?.a, 0);
  }

  final render = tester.renderObject<RenderRaisedMarkerOverlay>(
    find.byType(RaisedMarkerOverlay),
  );
  final placements = render.debugPlacements();
  Color? paintedColor(String text) => render
      .debugPaintedSpan(
        placements.singleWhere(
          (placement) => placement.marker.text.contains(text),
        ),
      )
      .style
      ?.color;
  expect(paintedColor('1'), AppSurfaces.readerLink(cs));
  expect(paintedColor('2'), AppSurfaces.readerLink(cs));
  expect(
    paintedColor('(ג)'),
    overlay.baseStyle.color,
    reason: 'צבע קישור דורש יעד שידוע ברינדור',
  );
  expect(paintedColor('ד'), overlay.baseStyle.color);
}

void main() {
  final notes = BookNotesBuilder()
    ..add(4, 0, '1', 'הערה ראשונה')
    ..add(4, 1, '2', 'הערה שנייה');
  final inlineNotes = addInlineNotePreviewLinks(
    '<b>א</b> <sup class="footnote-marker">1</sup>'
    '<sup class="footnote-marker">2</sup><b>בר ישראל דבעי למנסב איתתא</b>',
    lineIndex: 4,
    dbNotes: notes.build(),
  );
  final candidate = addNumberedNoteMarkerLinks('<sup>(ג)</sup>', lineIndex: 4);
  final html = '$_html $inlineNotes $candidate <sup>ד</sup>';
  final schemes = [
    AppThemeData.createColorScheme(AppSeedColors.white, Brightness.light),
    AppThemeData.createColorScheme(AppSeedColors.grey, Brightness.dark),
    AppThemeData.createColorScheme(Colors.blue, Brightness.light),
  ];

  for (final forceHtml in [false, true]) {
    testWidgets(
      'צבעי קישורים וסמני הערות בהחלפת ערכה (HtmlWidget: $forceHtml)',
      (
        tester,
      ) async {
        SmartTextWidget.debugForceHtmlWidget = forceHtml;
        addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
        // זהות ה-widget נשמרת כדי לבדוק שגם מטמון fwfh מתעדכן.
        final child = SmartTextWidget(
          text: forceHtml ? html : html.replaceFirst(_namedAnchor, 'יעד'),
          settings: const RenderSettings(fontSize: 20),
        );
        for (final cs in schemes) {
          await tester.pumpWidget(_host(cs, child));
          await tester.pumpAndSettle();
          expect(
            find.byType(HtmlWidget),
            forceHtml ? findsOneWidget : findsNothing,
          );
          for (final text in ['קישור', '(9)', 'ציטוט']) {
            expect(_styleOf(tester, text).color, AppSurfaces.readerLink(cs));
          }
          expect(_styleOf(tester, 'מפורש').color, const Color(0xFFFF0000));
          expect(_styleOf(tester, 'יעד').color, cs.onSurface);
          _expectOverlay(tester, cs);
        }
      },
    );
  }

  testWidgets('מסלול הקריאה הרציפה משתמש באותו צבע קישור ומעדכן סימונים', (
    tester,
  ) async {
    final state = TextBookLoaded(
      book: TextBook(title: 'ספר בדיקה'),
      showLeftPane: false,
      content: [html],
      fontSize: 20,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      visibleIndices: const [0],
      searchText: '',
    );
    final context = ReaderLineContext(
      state: state,
      lines: [html],
      profile: TextDisplayProfile.defaults,
      lineHtml: (_) => html,
      fontSize: 20,
      lineHeight: 1.5,
    );
    final child = ReaderParagraphRun(
      specs: [buildReaderLineSpec(0, context)],
      lineContext: context,
      onTapUrl: (_) async => true,
    );
    for (final cs in schemes) {
      await tester.pumpWidget(_host(cs, child));
      await tester.pumpAndSettle();
      for (final text in ['קישור', '(9)', 'ציטוט']) {
        expect(_styleOf(tester, text).color, AppSurfaces.readerLink(cs));
      }
      _expectOverlay(tester, cs);
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('הצעת תיקון מקלדת נשארת נראית בערכה נייטרלית $brightness', (
      tester,
    ) async {
      final cs = AppThemeData.createColorScheme(
        AppSeedColors.white,
        brightness,
      );
      await tester.pumpWidget(
        _host(
          cs,
          LayoutFixSuggestionBanner(query: 'akuo', onAccept: (_) {}),
        ),
      );
      expect(find.textContaining('שלום'), findsOneWidget);
      final foreground = _styleOf(tester, 'שלום').color!;
      final background = tester
          .widget<Material>(
            find.descendant(
              of: find.byType(LayoutFixSuggestionBanner),
              matching: find.byType(Material),
            ),
          )
          .color!;
      expect(foreground, cs.primary);
      expect(tester.widget<Icon>(find.byType(Icon)).color, foreground);
      final luminances = [
        foreground.computeLuminance(),
        background.computeLuminance(),
      ]..sort();
      expect(
        (luminances.last + 0.05) / (luminances.first + 0.05),
        greaterThan(3),
      );
    });
  }
}
