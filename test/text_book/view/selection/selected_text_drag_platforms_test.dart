import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_drag.dart';
import 'package:super_native_extensions/raw_clipboard.dart';

/// גרירת טקסט נבחר החוצה: Windows עם CF_HTML, ושאר שולחנות העבודה עם פורמטי
/// הלוח הרגילים (טקסט רגיל ו-HTML) בלי תבנית של Windows.
void main() {
  const plain = 'בראשית ברא';
  const html = '<span dir="rtl">בראשית ברא</span>';

  Map<String, Object?> byFormat(TargetPlatform platform) => {
    for (final r in buildSelectedTextDragRepresentations(
      platform: platform,
      plainText: plain,
      html: html,
    ).cast<DataRepresentationSimple>())
      r.format: r.data,
  };

  group('drag representations', () {
    test('Windows keeps CF_UNICODETEXT and CF_HTML', () {
      final data = byFormat(TargetPlatform.windows);
      expect(data.keys, ['NativeShell_CF_13', 'HTML Format']);
      expect(data['NativeShell_CF_13'], plain);
      expect(
        utf8.decode(data['HTML Format']! as List<int>),
        contains('Version:0.9'),
      );
    });

    test('macOS uses the UTI formats', () {
      final data = byFormat(TargetPlatform.macOS);
      expect(data.keys, ['public.utf8-plain-text', 'public.html']);
      expect(data['public.utf8-plain-text'], plain);
      expect(data['public.html'], "<meta charset='utf-8'>$html");
    });

    test('Linux uses MIME types without any Windows header', () {
      final data = byFormat(TargetPlatform.linux);
      expect(data.keys, ['text/plain', 'text/html']);
      expect(data['text/plain'], plain);
      expect(data['text/html'], html);
    });
  });

  group('which platforms start a drag', () {
    test('desktop only', () {
      expect(supportsSelectedTextDrag(TargetPlatform.windows), isTrue);
      expect(supportsSelectedTextDrag(TargetPlatform.macOS), isTrue);
      expect(supportsSelectedTextDrag(TargetPlatform.linux), isTrue);
      expect(supportsSelectedTextDrag(TargetPlatform.android), isFalse);
      expect(supportsSelectedTextDrag(TargetPlatform.iOS), isFalse);
    });

    for (final (platform, listens) in [
      (TargetPlatform.windows, true),
      (TargetPlatform.macOS, true),
      (TargetPlatform.linux, true),
      (TargetPlatform.android, false),
    ]) {
      testWidgets(
        'the region ${listens ? 'listens' : 'is inert'} on $platform',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: SelectedTextDragRegion(
                  selectedText: () => null,
                  captureContent: (_) => null,
                  child: const SizedBox(width: 10, height: 10),
                ),
              ),
            ),
          );
          expect(
            find.descendant(
              of: find.byType(SelectedTextDragRegion),
              matching: find.byType(Listener),
            ),
            listens ? findsOneWidget : findsNothing,
          );
        },
      );
    }
  });
}
