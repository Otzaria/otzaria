import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

import '../../marker/marker_test_helpers.dart';

/// המילוי נצבע על הטקסט המוצג, שבו ה-HTML מכווץ רווחים ו-`<br>` הוא מעבר
/// שורה — ועדיין חייב לנחות בדיוק על הטקסט המודגש.
void main() {
  const lines = {
    'שורה פשוטה': 'אבג דהו זחט סוף',
    'אחרי <br>': 'אבג<br>דהו זחט סוף',
    'אחרי רווח כפול': 'אבג דהו  זחט סוף',
    'אחרי תגית ורווח כפול': 'אבג <b>דהו</b>  זחט סוף',
    'אחרי <br> ורווחים': 'אבג <br>  דהו   זחט סוף',
  };

  for (final MapEntry(key: name, value: raw) in lines.entries) {
    testWidgets('the fill lands on the marked text: $name', (tester) async {
      PluginHighlightRegistry.instance.setHighlight(
        ownerPluginId: 'whitespace.test',
        payload: {
          'highlightId': 'h',
          'bookId': 'ספר',
          'sectionIndex': 0,
          'range': anchorFor(
            TextRendererService.stripHtml(raw),
            'זחט',
          ).toJson(),
          'style': {'backgroundColor': '#FFE066'},
        },
      );
      addTearDown(
        () => PluginHighlightRegistry.instance.removePlugin('whitespace.test'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SmartTextWidget(
                text: raw,
                settings: const RenderSettings(fontSize: 20),
                highlightBookId: 'ספר',
                highlightSectionIndex: 0,
              ),
            ),
          ),
        ),
      );

      final overlay = tester.renderObject<RenderPluginHighlightFrameOverlay>(
        find.byType(PluginHighlightFrameOverlay),
      );
      final displayed = tester
          .renderObjectList<RenderParagraph>(
            find.descendant(
              of: find.byType(PluginHighlightFrameOverlay),
              matching: find.byType(RichText),
            ),
          )
          .map((paragraph) => paragraph.text.toPlainText())
          .join()
          .characters
          .toList();
      final range = overlay.displayedRanges.single;
      expect(displayed.sublist(range.start, range.end).join(), 'זחט');
    });
  }
}
