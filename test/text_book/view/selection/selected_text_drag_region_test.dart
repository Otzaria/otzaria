import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/selected_text_drag.dart';

void main() {
  for (final selectedOccurrence in [true, false]) {
    testWidgets(
      'only the selected occurrence starts a drag (selected=$selectedOccurrence)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        String? selected;
        final prepared = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: Scaffold(
              body: SelectedTextDragRegion(
                selectedText: () => selected,
                captureContent: (text) => () async {
                  prepared.add(text);
                  return null;
                },
                child: SelectionArea(
                  onSelectionChanged: (text) => selected = text?.plainText,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text('word first'), Text('word second')],
                  ),
                ),
              ),
            ),
          ),
        );
        final first = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('word first'),
            matching: find.byType(RichText),
          ),
        );
        final b = first
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 4),
            )
            .single
            .toRect();
        final initial = await tester.startGesture(
          first.localToGlobal(Offset(b.left + 0.1, b.center.dy)),
          kind: PointerDeviceKind.mouse,
        );
        await initial.moveTo(
          first.localToGlobal(Offset(b.right + 0.1, b.center.dy)),
        );
        await tester.pump();
        await initial.up();
        await tester.pump(const Duration(milliseconds: 600));
        expect(selected, 'word');
        final second = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text(selectedOccurrence ? 'word first' : 'word second'),
            matching: find.byType(RichText),
          ),
        );
        final b2 = second
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 4),
            )
            .single
            .toRect();
        final next = await tester.startGesture(
          second.localToGlobal(b2.center),
          kind: PointerDeviceKind.mouse,
        );
        await next.moveBy(const Offset(20, 0));
        await tester.pump();
        await next.up();
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
        expect(
          prepared,
          selectedOccurrence ? ['word'] : isEmpty,
          reason: 'the second paragraph has no selected text',
        );
      },
    );
  }
}
