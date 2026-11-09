import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/tabs/system_settings_tab.dart';

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme,
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

Iterable<RichText> _richText(WidgetTester tester) => find
    .byType(RichText)
    .evaluate()
    .map((element) => element.widget)
    .whereType<RichText>();

bool _hasFontSize(InlineSpan span, double size) {
  if (span is! TextSpan) return false;
  if (span.style?.fontSize == size) return true;
  return span.children?.any((child) => _hasFontSize(child, size)) ?? false;
}

void main() {
  testWidgets('MarkdownBody renders Hebrew RTL with inline formatting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 320,
          child: MarkdownBody(
            data: '**שלום** ו-*עולם*\n\n- פריט ראשון\n- פריט שני',
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownBody), findsOneWidget);
    final rendered = _richText(
      tester,
    ).map((text) => text.text.toPlainText()).join(' ');
    expect(rendered, contains('שלום'));
    expect(rendered, contains('עולם'));
    expect(rendered, contains('פריט ראשון'));
    final hebrew = find
        .byType(RichText)
        .evaluate()
        .firstWhere(
          (element) =>
              (element.widget as RichText).text.toPlainText().contains('שלום'),
        );
    expect(Directionality.of(hebrew), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MarkdownBody preserves link tap callback in RTL', (
    tester,
  ) async {
    String? tappedHref;
    await tester.pumpWidget(
      _app(
        MarkdownBody(
          data: '[קישור](https://example.org/notes)',
          onTapLink: (text, href, title) => tappedHref = href,
        ),
      ),
    );

    await tester.tap(find.text('קישור', findRichText: true));
    await tester.pump();
    expect(tappedHref, 'https://example.org/notes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('MarkdownBody respects an explicit paragraph style', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => MarkdownBody(
            data: 'משפט בדיקה',
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: const TextStyle(fontSize: 23, color: Color(0xFF123456)),
                ),
          ),
        ),
      ),
    );

    expect(
      _richText(tester).any((text) => _hasFontSize(text.text, 23)),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('changelog styles preserve Hebrew blocks in $brightness', (
      tester,
    ) async {
      late MarkdownStyleSheet style;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              style = changelogMarkdownStyle(Theme.of(context));
              return SizedBox(
                width: 280,
                child: MarkdownBody(
                  data:
                      '# כותרת **מודגשת**\n\n> ציטוט **חשוב**\n\n'
                      '1. פריט ראשון\n2. פריט שני',
                  styleSheet: style,
                ),
              );
            },
          ),
          theme: ThemeData(brightness: brightness),
        ),
      );

      for (final content in [
        'כותרת מודגשת',
        'ציטוט חשוב',
        'פריט ראשון',
        'פריט שני',
      ]) {
        final finder = find.text(content, findRichText: true);
        expect(finder, findsOneWidget);
        expect(Directionality.of(tester.element(finder)), TextDirection.rtl);
      }
      final heading = _richText(tester).singleWhere(
        (text) => text.text.toPlainText() == 'כותרת מודגשת',
      );
      final quote = _richText(tester).singleWhere(
        (text) => text.text.toPlainText() == 'ציטוט חשוב',
      );
      expect(_hasFontSize(heading.text, style.h1!.fontSize!), isTrue);
      expect(_hasFontSize(quote.text, style.blockquote!.fontSize!), isTrue);
      expect(style.h1!.fontSize, greaterThan(style.p!.fontSize!));
      expect(find.text('1.', findRichText: true), findsOneWidget);
      expect(find.text('2.', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long Hebrew changelog scrolls in its parent without overflow', (
    tester,
  ) async {
    final longChangelog = List.generate(
      80,
      (index) => '- סעיף $index: עדכון של מנגנון החיפוש והתצוגה בעברית',
    ).join('\n');
    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox(
            width: 280,
            height: 200,
            child: SingleChildScrollView(
              child: MarkdownBody(data: longChangelog),
            ),
          ),
        ),
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and malformed Markdown does not throw', (tester) async {
    for (final source in <String>['', ' ', '**', '#', '[לא שלם](']) {
      await tester.pumpWidget(_app(MarkdownBody(data: source)));
      expect(tester.takeException(), isNull, reason: 'input: $source');
    }
  });
}
