import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/stub_settings_bloc.dart';

/// שורות יעד כמו בסנהדרין לז: כותרת הדף היא שורה בפני עצמה בין שורות התוכן.
const _targetLines = ['פתיחה', 'לפני סוף', '<h2>דף לז:</h2>', 'אחרי הכול'];

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() {
    LinkPreviewOverlay.dismiss();
    LibraryProviderManager.instance.resetForTesting();
  });

  /// קישור-טווח שהיעד שלו הוא [lines]; [path2] ייחודי כי התוכן נשמר במטמון.
  Link rangeLink(String path2, List<String> lines) {
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: const {},
      providers: [_LinesProvider(lines)],
    );
    return Link(
      heRef: 'א',
      index1: 1,
      path2: path2,
      index2: 1,
      index2End: lines.length,
      connectionType: 'reference',
    );
  }

  /// שתי החלוניות שבדיווח: תת-תפריט "קישורים" וחלונית הקישור הפנימי בטקסט.
  final surfaces = <String, void Function(BuildContext, Link)>{
    'תת-תפריט "קישורים"': (context, link) =>
        LinkPreviewOverlay.showBesideMenuItem(
          context,
          contentBuilder: buildLinkContextMenuEntry(
            link: link,
            onTap: () {},
          ).hoverPreviewBuilder!,
          itemGlobalRect: const Rect.fromLTWH(500, 40, 120, 30),
          minWidth: 0,
        ),
    'חלונית קישור פנימי': (context, link) => LinkPreviewOverlay.show(
      context,
      link: link,
      globalPosition: const Offset(400, 40),
    ),
  };

  Future<void> showPreview(
    WidgetTester tester,
    String surface,
    Link link, {
    SettingsState? settings,
  }) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: StubSettingsBloc(settings ?? SettingsState.initial()),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    surfaces[surface]!(hostContext, link);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// השורה המוצגת שבה [word] — בגובה השורה המלא, בקואורדינטות מסך.
  Rect lineOf(WidgetTester tester, String word) {
    for (final paragraph
        in tester.allRenderObjects.whereType<RenderParagraph>()) {
      final text = paragraph.text.toPlainText();
      final start = text.indexOf(word);
      if (start < 0) continue;
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + word.length),
            boxHeightStyle: ui.BoxHeightStyle.max,
          )
          .first;
      return box.toRect().shift(paragraph.localToGlobal(Offset.zero));
    }
    throw StateError('"$word" אינו מוצג');
  }

  /// הסגנון האפקטיבי של הספאן שבו [word], כולל הסגנון שעובר בירושה.
  TextStyle styleOf(WidgetTester tester, String word) {
    TextStyle? found;
    void visit(InlineSpan span, TextStyle inherited) {
      final style = inherited.merge(span.style);
      if (span is TextSpan) {
        if (found == null && (span.text?.contains(word) ?? false)) {
          found = style;
        }
        span.children?.forEach((child) => visit(child, style));
      }
    }

    for (final paragraph
        in tester.allRenderObjects.whereType<RenderParagraph>()) {
      visit(paragraph.text, const TextStyle());
      if (found != null) return found!;
    }
    throw StateError('"$word" אינו מוצג');
  }

  /// הטקסט שאזור הבחירה מעתיק אחרי "בחר הכול", מתחת ל-[of].
  String copyAll(WidgetTester tester, Finder of) {
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion).last)
        .selectAll();
    final selection =
        SelectionContainer.maybeOf(tester.element(of))!
            as SelectionContainerDelegate;
    return selection.getSelectedContent()!.plainText;
  }

  group('רווח מיותר סביב כותרת בתצוגה המקדימה של קישור (issue #3709)', () {
    for (final (surface, scale, lines) in [
      ('תת-תפריט "קישורים"', 1.0, _targetLines),
      ('תת-תפריט "קישורים"', 2.0, _targetLines),
      // החלונית מקוצרת לארבע שורות: השורה שלפני הכותרת והכותרת.
      ('חלונית קישור פנימי', 1.0, _targetLines.sublist(1, 3)),
    ]) {
      testWidgets('$surface (טקסט ×$scale): הכותרת בלי שורה ריקה סביבה', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await showPreview(tester, surface, rangeLink('$surface $scale', lines));

        final before = lineOf(tester, 'סוף');
        final heading = lineOf(tester, 'דף');
        expect(heading.top - before.bottom, moreOrLessEquals(0, epsilon: 1));
        expect(heading.height, greaterThan(before.height));
        final headingStyle = styleOf(tester, 'דף');
        expect(headingStyle.fontWeight, FontWeight.bold);
        expect(
          headingStyle.fontSize,
          greaterThan(styleOf(tester, 'סוף').fontSize!),
        );
        if (lines.length < _targetLines.length) return;
        expect(
          lineOf(tester, 'אחרי').top - lineOf(tester, 'לז').bottom,
          moreOrLessEquals(0, epsilon: 1),
        );
      });
    }

    testWidgets('style קיים של הכותרת נשמר', (tester) async {
      await showPreview(
        tester,
        'תת-תפריט "קישורים"',
        rangeLink('style', ['לפני סוף', '<h2 style="color:red">דף</h2>']),
      );

      expect(
        lineOf(tester, 'דף').top - lineOf(tester, 'סוף').bottom,
        moreOrLessEquals(0, epsilon: 1),
      );
      expect(styleOf(tester, 'דף').color, const Color(0xFFFF0000));
    });

    for (final attributes in [
      'title="x > y" style="color:red"',
      '''title='a style=bad' style="color:red"''',
      '''title="a style='bad'" style='color:red' ''',
      'title="<h3>טקסט</h3>" style="color:red"',
      'title="x > y" STYLE = color:red',
      'style="color:red" style="color:blue"',
    ]) {
      testWidgets('עיצוב ומאפייני כותרת נשמרים: $attributes', (tester) async {
        await showPreview(
          tester,
          'תת-תפריט "קישורים"',
          rangeLink(attributes, ['לפני סוף', '<h2 $attributes>דף</h2>']),
        );

        expect(styleOf(tester, 'דף').color, const Color(0xFFFF0000));
        expect(
          tester
              .widget<SmartTextWidget>(find.byType(SmartTextWidget))
              .text
              .replaceFirst('display:inline;', ''),
          'לפני סוף<br><h2 $attributes>דף</h2>',
        );
        expect(
          lineOf(tester, 'דף').top - lineOf(tester, 'סוף').bottom,
          moreOrLessEquals(0, epsilon: 1),
        );
      });
    }

    // כמו ב-CSS: שוליים אנכיים לא חלים על inline, אבל display מפורש גובר.
    for (final (style, gap) in [
      ('margin:7px;color:red', 0.0),
      ('display:block;margin:7px;color:red', 7.0),
    ]) {
      testWidgets('style מפורש בכותרת: $style', (tester) async {
        await showPreview(
          tester,
          'תת-תפריט "קישורים"',
          rangeLink(style, [
            'לפני סוף',
            '<h2 title="x > y" style="$style">דף</h2>',
          ]),
        );

        expect(
          lineOf(tester, 'דף').top - lineOf(tester, 'סוף').bottom,
          moreOrLessEquals(gap, epsilon: 1),
        );
        expect(styleOf(tester, 'דף').color, const Color(0xFFFF0000));
      });
    }

    for (final attributes in ['style', 'style=""', "style=''"]) {
      testWidgets('style ריק: הכותרת צמודה לשורה שלפניה: $attributes', (
        tester,
      ) async {
        await showPreview(
          tester,
          'תת-תפריט "קישורים"',
          rangeLink('empty-$attributes', [
            'לפני סוף',
            '<h2 $attributes>דף</h2>',
          ]),
        );
        expect(
          lineOf(tester, 'דף').top - lineOf(tester, 'סוף').bottom,
          moreOrLessEquals(0, epsilon: 1),
        );
      });
    }

    for (final html in [
      '<h2>דף</h2>',
      '<h2 title="<br><h3>טקסט</h3>">דף</h2>',
      '<!-- <br><h2> --> <h2>דף</h2>',
    ]) {
      testWidgets('כותרת בלי מעבר שורה אמיתי אינה משתנה: $html', (
        tester,
      ) async {
        await showPreview(
          tester,
          'תת-תפריט "קישורים"',
          rangeLink(html, [html]),
        );

        expect(
          tester.widget<SmartTextWidget>(find.byType(SmartTextWidget)).text,
          html,
        );
      });
    }

    testWidgets('ישויות ניקוד מועתקות כמו במקור גם כשהסרת ניקוד פעילה', (
      tester,
    ) async {
      const lines = ['א&#x05B0;ב', '<h2>דף</h2>'];
      await tester.pumpWidget(
        MaterialApp(
          home: SelectionArea(
            child: SmartTextWidget(
              text: lines.join('<br>'),
              settings: const RenderSettings(removeNikud: true),
            ),
          ),
        ),
      );
      final document = copyAll(tester, find.byType(SmartTextWidget));
      expect(document, contains('א\u05B0ב'));

      await showPreview(
        tester,
        'תת-תפריט "קישורים"',
        rangeLink('encoded-nikud', lines),
        settings: SettingsState.initial().copyWith(defaultRemoveNikud: true),
      );
      expect(
        copyAll(tester, find.byType(LinkHoverPreviewContent)),
        endsWith('א\u05B0ב\nדף'),
      );
      expect(
        tester.widget<SmartTextWidget>(find.byType(SmartTextWidget)).text,
        'א&#x05B0;ב<br><h2 style="display:inline">דף</h2>',
      );
    });

    testWidgets('ההעתקה שומרת מעבר שורה משני צדי הכותרת', (tester) async {
      final contents = {
        'כותרת באמצע': (_targetLines, 'פתיחה\nלפני סוף\nדף לז:\nאחרי הכול'),
        'כותרת ראשונה': (['<h2>א</h2>', 'ב'], 'א\nב'),
        'כמה כותרות': (
          ['א', '<h2>ב</h2>', '<h3>ג</h3>', 'ד', '<h2>ה</h2>', 'ו'],
          'א\nב\nג\nד\nה\nו',
        ),
        'שורה ריקה לפני כותרת': (
          ['א', '', '<h2>ב</h2>', '', 'ג'],
          'א\n\nב\n\nג',
        ),
        'בלי כותרת': (['א', 'ב', 'ג'], 'א\nב\nג'),
        'ישויות ומאפיין מצוטט': (
          [
            'א &amp; ב&nbsp;ג',
            '<h2 title="x > y" style="color:red">דף &lt; לז</h2>',
            'ד&#x05D4; &quot;ו&quot;',
          ],
          'א & ב\u00A0ג\nדף < לז\nדה "ו"',
        ),
        'הערה מוטמעת': (
          [
            'א',
            '<h2 title="x > y">דף</h2>',
            'ב<sup class="footnote-marker">א</sup><i class="footnote">הערה נסתרת</i>ג',
          ],
          'א\nדף\nב\u2067א\u2069ג',
        ),
      };
      for (final MapEntry(key: name, value: (lines, expected))
          in contents.entries) {
        await showPreview(tester, 'תת-תפריט "קישורים"', rangeLink(name, lines));
        expect(
          copyAll(tester, find.byType(LinkHoverPreviewContent)),
          endsWith(expected),
          reason: name,
        );
        LinkPreviewOverlay.dismiss();
      }
    });
  });

  group('חלונית הקישור הפנימי חותכת שורות בלי "…" (issue #3709)', () {
    for (final (name, lines) in [
      ('חמש שורות בלי כותרת', ['אלף', 'בית', 'גימל', 'דלת', 'סוף']),
      ('כותרת באמצע', _targetLines),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$name (טקסט ×$scale): "…" מוצג ופורש את השורות החתוכות', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final document = lines
              .map((line) => line.replaceAll(RegExp('<[^>]+>'), ''))
              .join('\n');
          await showPreview(
            tester,
            'חלונית קישור פנימי',
            rangeLink('more $name $scale', lines),
          );

          expect(tester.takeException(), isNull);
          final lastWord = lines.last.split(' ').last;
          final clip = tester.getRect(
            find
                .descendant(
                  of: find.byType(LinkHoverPreviewContent),
                  matching: find.byType(ClipRect),
                )
                .first,
          );
          expect(lineOf(tester, lastWord).bottom, greaterThan(clip.bottom));
          expect(find.text('…'), findsOneWidget);
          expect(
            tester.getRect(find.text('…')).bottom,
            moreOrLessEquals(clip.bottom, epsilon: 1),
          );
          expect(
            copyAll(tester, find.byType(LinkHoverPreviewContent)),
            endsWith(document),
          );

          await tester.tap(find.text('…'));
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.text('…'), findsNothing);
          // התוכן הפרוש נגלל כשהוא גבוה מהחלונית (×2) — גוללים לסופו.
          final expanded = tester.state<ScrollableState>(
            find.byType(Scrollable).last,
          );
          expanded.position.jumpTo(expanded.position.maxScrollExtent);
          await tester.pump();
          final viewport = tester.getRect(find.byType(Scrollable).last);
          expect(
            lineOf(tester, lastWord).bottom,
            lessThanOrEqualTo(viewport.bottom + 0.01),
          );
        });
      }
    }

    for (final (name, lines) in [
      ('ארבע שורות בדיוק', ['אלף', 'בית', 'גימל', 'סוף']),
      ('כותרת ושורה', ['<h2>כותרת</h2>', 'סוף']),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$name (טקסט ×$scale): בלי "…"', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await showPreview(
            tester,
            'חלונית קישור פנימי',
            rangeLink('fits $name $scale', lines),
          );

          expect(tester.takeException(), isNull);
          expect(find.text('…'), findsNothing);
          final clip = tester.getRect(
            find
                .descendant(
                  of: find.byType(LinkHoverPreviewContent),
                  matching: find.byType(ClipRect),
                )
                .first,
          );
          expect(
            lineOf(tester, 'סוף').bottom,
            lessThanOrEqualTo(clip.bottom + 0.01),
          );
        });
      }
    }
  });
}

class _LinesProvider implements LibraryProvider {
  _LinesProvider(this.lines);

  final List<String> lines;

  @override
  Future<String> getLinkContent(Link link) async => lines[link.index2 - 1];

  @override
  String get displayName => 'Fake';
  @override
  bool get isInitialized => true;
  @override
  int get priority => 0;
  @override
  String get providerId => 'fake';
  @override
  String get sourceIndicator => 'T';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
