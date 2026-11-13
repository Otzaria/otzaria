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
      testWidgets('$surface (טקסט ×$scale): הכותרת בלי שולי HTML', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await showPreview(tester, surface, rangeLink('$surface $scale', lines));

        final before = lineOf(tester, 'סוף');
        final heading = lineOf(tester, 'דף');
        expect(heading.top - before.bottom, moreOrLessEquals(0, epsilon: 1));
        expect(heading.height, greaterThan(before.height));
        if (lines.length < _targetLines.length) return;
        // אחרי הכותרת נשארת רק השורה הריקה של ה-<br>, שההעתקה צריכה.
        expect(
          lineOf(tester, 'אחרי').top - lineOf(tester, 'לז').bottom,
          moreOrLessEquals(before.height, epsilon: 1),
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
      final heading = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .firstWhere((p) => p.text.toPlainText() == 'דף');
      expect(heading.text.style?.color, const Color(0xFFFF0000));
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

        final heading = tester.allRenderObjects
            .whereType<RenderParagraph>()
            .firstWhere((p) => p.text.toPlainText() == 'דף');
        expect(heading.text.style?.color, const Color(0xFFFF0000));
        expect(
          tester
              .widget<SmartTextWidget>(find.byType(SmartTextWidget))
              .text
              .replaceFirst('margin:0;', ''),
          'לפני סוף<br><h2 $attributes>דף</h2>',
        );
        expect(
          lineOf(tester, 'דף').top - lineOf(tester, 'סוף').bottom,
          moreOrLessEquals(0, epsilon: 1),
        );
      });
    }

    testWidgets('שוליים מפורשים בכותרת גוברים על ברירת המחדל', (tester) async {
      await showPreview(
        tester,
        'תת-תפריט "קישורים"',
        rangeLink('margin', [
          'לפני סוף',
          '<h2 title="x > y" style="margin:7px;color:red">דף</h2>',
        ]),
      );

      expect(
        lineOf(tester, 'דף').top - lineOf(tester, 'סוף').bottom,
        moreOrLessEquals(7, epsilon: 1),
      );
    });

    for (final attributes in ['style', 'style=""', "style=''"]) {
      testWidgets('style ריק מקבל שוליים מצומצמים: $attributes', (
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
        endsWith(document),
      );
      expect(
        tester.widget<SmartTextWidget>(find.byType(SmartTextWidget)).text,
        'א&#x05B0;ב<br><h2 style="margin:0">דף</h2>',
      );
    });

    testWidgets('ההעתקה זהה להעתקת התוכן כמסמך אחד', (tester) async {
      final contents = {
        'כותרת באמצע': _targetLines,
        'כותרת ראשונה': ['<h2>א</h2>', 'ב'],
        'כמה כותרות': ['א', '<h2>ב</h2>', '<h3>ג</h3>', 'ד', '<h2>ה</h2>', 'ו'],
        'שורה ריקה לפני כותרת': ['א', '', '<h2>ב</h2>', '', 'ג'],
        'בלי כותרת': ['א', 'ב', 'ג'],
        'ישויות ומאפיין מצוטט': [
          'א &amp; ב&nbsp;ג',
          '<h2 title="x > y" style="color:red">דף &lt; לז</h2>',
          'ד&#x05D4; &quot;ו&quot;',
        ],
        'הערה מוטמעת': [
          'א',
          '<h2 title="x > y">דף</h2>',
          'ב<sup class="footnote-marker">א</sup><i class="footnote">הערה נסתרת</i>ג',
        ],
      };
      for (final MapEntry(key: name, value: lines) in contents.entries) {
        await tester.pumpWidget(
          MaterialApp(
            home: SelectionArea(
              child: SmartTextWidget(
                text: lines.join('<br>'),
                settings: const RenderSettings(),
              ),
            ),
          ),
        );
        final document = copyAll(tester, find.byType(SmartTextWidget));

        await showPreview(tester, 'תת-תפריט "קישורים"', rangeLink(name, lines));
        expect(
          copyAll(tester, find.byType(LinkHoverPreviewContent)),
          endsWith(document),
          reason: name,
        );
        LinkPreviewOverlay.dismiss();
      }
    });
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
